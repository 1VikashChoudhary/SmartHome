/*
 * ============================================================================
 * OTAManager.cpp — ArduinoOTA Implementation
 * ============================================================================
 */

#include "OTAManager.h"
#include <LittleFS.h>
#if defined(ESP8266)
#include <Updater.h>
#include <flash_hal.h>
#else
#include <Update.h>
#endif

OTAManager* OTAManager::_instance = nullptr;

#if defined(ESP32)
namespace {
class OtaMutexGuard {
public:
    explicit OtaMutexGuard(SemaphoreHandle_t mtx) : _mtx(mtx) {
        if (_mtx) xSemaphoreTakeRecursive(_mtx, portMAX_DELAY);
    }
    ~OtaMutexGuard() {
        if (_mtx) xSemaphoreGiveRecursive(_mtx);
    }
private:
    SemaphoreHandle_t _mtx;
};
} // namespace

void OTAManager::ensureMutex() const {
    if (!_otaMutex) {
        _otaMutex = xSemaphoreCreateRecursiveMutex();
    }
}
#define OTA_LOCK() ensureMutex(); OtaMutexGuard _otaLockGuard(_otaMutex)
#else
#define OTA_LOCK() ((void)0)
#endif

OTAManager::OTAManager()
    : _arduinoOtaEnabled(false), _hostname(""), _otaPassword(""), _otaPasswordIsHash(false),
      _isUpdating(false), _progress(0), _statusString("Idle"),
      _progressCb(nullptr), _startCb(nullptr), _endCb(nullptr), _errorCb(nullptr),
      _httpUpdateOk(false), _httpInProgress(false), _httpRejected(false),
      _httpBegun(false), _httpHeaderLen(0),
      _activeUploadOwner(nullptr), _lastHttpChunkMs(0),
      _httpTotalSize(0),
      _otaLastReportedPct(-1), _httpLastReportedPct(-1),
      _stabilityCheckPending(false), _stabilityCheckStart(0)
#if defined(ESP32)
    , _otaMutex(nullptr)
#endif
{
    _httpHeaderBuf[0] = 0;
    _httpHeaderBuf[1] = 0;
    _instance = this;
}

void OTAManager::begin(const String& hostname, bool enableArduinoOta, const String& otaPassword, bool isMd5Hash) {
#if defined(ESP32)
    ensureMutex();
#endif
    _hostname = hostname;
    _otaPassword = otaPassword;
    _otaPasswordIsHash = isMd5Hash;
    _arduinoOtaEnabled = false;

#if defined(ESP32)
    // Dual-Partition OTA Rollback (Zero-Brick Guarantee) Check
    const esp_partition_t* running = esp_ota_get_running_partition();
    if (running) {
        esp_ota_img_states_t ota_state;
        if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
            if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
                _stabilityCheckPending = true;
                _stabilityCheckStart = millis();
                SERIAL_PRINTF("[OTA-Rollback] New firmware running on '%s' in PENDING_VERIFY state!\n", running->label);
                Serial.println(F("[OTA-Rollback] Zero-Brick stability check ARMED: 30-second verification timer active."));
                Serial.println(F("[OTA-Rollback] If firmware panics or boot-loops, ESP32 bootloader will auto-revert to backup partition."));
            } else {
                _stabilityCheckPending = false;
                SERIAL_PRINTF("[OTA-Rollback] Partition '%s' is confirmed valid (State: 0x%02X)\n", running->label, (unsigned int)ota_state);
            }
        } else {
            _stabilityCheckPending = false;
            SERIAL_PRINTF("[OTA-Rollback] Running on partition '%s' (Standard/Factory)\n", running->label);
        }
    }
#else
    _stabilityCheckPending = false;
#endif

    if (enableArduinoOta) {
        setArduinoOtaEnabled(true, _hostname, _otaPassword, _otaPasswordIsHash);
    } else {
        Serial.println(F("[OTA] ArduinoOTA (port 3232) disabled by default. HTTP OTA active."));
    }
}

void OTAManager::setArduinoOtaEnabled(bool enabled, const String& hostname, const String& password, bool isMd5Hash) {
    bool configChanged = false;
    if (hostname.length() > 0 && hostname != _hostname) {
        _hostname = hostname;
        configChanged = true;
    }
    if (password.length() > 0 && (password != _otaPassword || isMd5Hash != _otaPasswordIsHash)) {
        _otaPassword = password;
        _otaPasswordIsHash = isMd5Hash;
        configChanged = true;
    }
    if (_hostname.length() == 0) _hostname = OTA_HOSTNAME_PREFIX;
    if (_arduinoOtaEnabled == enabled && !(enabled && configChanged)) return;
    if (_arduinoOtaEnabled && enabled && configChanged) {
        ArduinoOTA.end();
    }
    _arduinoOtaEnabled = enabled;
    if (_arduinoOtaEnabled) {
        ArduinoOTA.setHostname(_hostname.c_str());
        // Use admin web password (or precomputed MD5 hash) if available; fallback to hostname only when none exists
        if (_otaPassword.length() > 0) {
            if (_otaPasswordIsHash) {
                ArduinoOTA.setPasswordHash(_otaPassword.c_str());
            } else {
                ArduinoOTA.setPassword(_otaPassword.c_str());
            }
        } else {
            ArduinoOTA.setPassword(_hostname.c_str());
        }
        ArduinoOTA.setPort(3232);
        ArduinoOTA.setRebootOnSuccess(true);

        ArduinoOTA.onStart(onOTAStart);
        ArduinoOTA.onEnd(onOTAEnd);
        ArduinoOTA.onProgress(onOTAProgress);
        ArduinoOTA.onError(onOTAError);

        ArduinoOTA.begin();
        SERIAL_PRINTF("[OTA] ArduinoOTA (port 3232) ENABLED dynamically on '%s'\n", _hostname.c_str());
    } else {
        ArduinoOTA.end();
        Serial.println(F("[OTA] ArduinoOTA (port 3232) DISABLED dynamically"));
    }
}

void OTAManager::loop() {
    if (_arduinoOtaEnabled && !_httpInProgress) {
        ArduinoOTA.handle();
    }

    // Safety net: if an HTTP OTA client drops silently mid-stream without TCP disconnect notification,
    // abort after 30s of inactivity. Guard with lock-free check first so Core 1 loop() never stalls
    // behind AsyncTCP's flash writes.
    if (_httpInProgress && (millis() - _lastHttpChunkMs > 30000UL)) {
        OTA_LOCK();
        if (_httpInProgress && (millis() - _lastHttpChunkMs > 30000UL)) {
            abortHttpUpload("HTTP OTA transfer timed out");
        }
    }

    // Zero-Brick Guarantee: 30-second stability check
    if (_stabilityCheckPending) {
        if (millis() - _stabilityCheckStart >= STABILITY_CHECK_DURATION_MS) {
            markAppValid();
        }
    }
}

bool OTAManager::markAppValid() {
    _stabilityCheckPending = false;
#if defined(ESP32)
    esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
    if (err == ESP_OK) {
        Serial.println(F("[OTA-Rollback] 30s stability check PASSED! Application marked VALID. Rollback cancelled."));
        return true;
    } else {
        SERIAL_PRINTF("[OTA-Rollback] mark_app_valid returned error 0x%X\n", err);
        return false;
    }
#else
    return true;
#endif
}

bool OTAManager::isRollbackPossible() const {
#if defined(ESP32)
    const esp_partition_t* next = esp_ota_get_next_update_partition(NULL);
    if (!next) return false;
    return Update.canRollBack();
#else
    return false;
#endif
}

String OTAManager::getRunningPartitionName() const {
#if defined(ESP32)
    const esp_partition_t* running = esp_ota_get_running_partition();
    if (running && running->label[0] != '\0') {
        return String(running->label);
    }
    return F("unknown");
#else
    return F("flash");
#endif
}

String OTAManager::getOtaStateString() const {
#if defined(ESP32)
    if (_stabilityCheckPending) {
        unsigned long elapsed = millis() - _stabilityCheckStart;
        unsigned long remaining = (elapsed < STABILITY_CHECK_DURATION_MS) ? (STABILITY_CHECK_DURATION_MS - elapsed) / 1000 : 0;
        return "Testing (" + String(remaining) + "s left)";
    }
    const esp_partition_t* running = esp_ota_get_running_partition();
    if (running) {
        esp_ota_img_states_t ota_state;
        if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
            switch (ota_state) {
                case ESP_OTA_IMG_NEW:            return F("New");
                case ESP_OTA_IMG_PENDING_VERIFY: return F("Pending Verification");
                case ESP_OTA_IMG_VALID:          return F("Valid (Stable)");
                case ESP_OTA_IMG_INVALID:        return F("Invalid");
                case ESP_OTA_IMG_ABORTED:        return F("Aborted");
                default:                         break;
            }
        }
    }
    return F("Stable");
#else
    return F("Stable");
#endif
}

bool OTAManager::triggerManualRollback() {
#if defined(ESP32)
    if (!isRollbackPossible()) {
        Serial.println(F("[OTA-Rollback] Rollback not possible (no valid alternate partition found)"));
        return false;
    }
    Serial.println(F("[OTA-Rollback] Triggering rollback to alternate partition and rebooting..."));
    esp_err_t err = esp_ota_mark_app_invalid_rollback_and_reboot();
    if (err != ESP_OK) {
        SERIAL_PRINTF("[OTA-Rollback] esp_ota_mark_app_invalid_rollback_and_reboot failed (0x%X), using Update.rollBack()...\n", err);
        if (Update.rollBack()) {
            ESP.restart();
            return true;
        }
        return false;
    }
    return true;
#else
    return false;
#endif
}

bool OTAManager::isUpdating() { return _isUpdating; }
int OTAManager::getProgress() { return _progress; }
String OTAManager::getStatusString() { OTA_LOCK(); return _statusString; }

void OTAManager::setProgressCallback(void (*cb)(int, int)) { _progressCb = cb; }
void OTAManager::setStartCallback(void (*cb)()) { _startCb = cb; }
void OTAManager::setEndCallback(void (*cb)()) { _endCb = cb; }
void OTAManager::setErrorCallback(void (*cb)(const String&)) { _errorCb = cb; }

// --- Static Callbacks ---

void OTAManager::onOTAStart() {
    if (!_instance) return;
    if (_instance->_httpInProgress) {
        Serial.println(F("[OTA] Rejected ArduinoOTA start while HTTP OTA is in progress"));
        return;
    }
    _instance->_isUpdating = true;
    _instance->_progress = 0;
    _instance->_otaLastReportedPct = -1;

    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "Firmware" : "Filesystem";
    _instance->_statusString = "Updating " + type;
    SERIAL_PRINTF("[OTA] Start: %s update\n", type.c_str());

    // Extend watchdog during OTA — flash erase can briefly stall the CPU
    // beyond the normal 30s WDT timeout.
    if (_instance && _instance->_stabilityCheckPending) {
        _instance->markAppValid();
    }
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms  = WDT_OTA_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic  = true
    };
    esp_task_wdt_reconfigure(&wdt_cfg);
#else
    esp_task_wdt_init(WDT_OTA_TIMEOUT_SECONDS, true);
#endif
    SERIAL_PRINTF("[OTA] WDT extended to %ds\n", WDT_OTA_TIMEOUT_SECONDS);
#else
    ESP.wdtFeed();
#endif

    if (_instance->_startCb) _instance->_startCb();
}

void OTAManager::onOTAEnd() {
    if (!_instance) return;
    _instance->_isUpdating = false;
    _instance->_progress = 100;
    _instance->_statusString = "Success — Rebooting";
    Serial.println(F("\n[OTA] Update complete, rebooting..."));

    // Restore normal WDT before reboot
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms  = WDT_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic  = true
    };
    esp_task_wdt_reconfigure(&wdt_cfg);
#else
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
#else
    ESP.wdtFeed();
#endif

    if (_instance->_endCb) _instance->_endCb();
}

void OTAManager::onOTAProgress(unsigned int progress, unsigned int total) {
    if (!_instance || total == 0) return;
    int pct = (progress * 100) / total;
    _instance->_progress = pct;

    // Keep progress handling coarse to avoid extra work during OTA packet flow.
    if (pct >= _instance->_otaLastReportedPct + 5 || pct == 100) {
        _instance->_otaLastReportedPct = pct;
        _instance->_statusString = "Updating";
        SERIAL_PRINTF("[OTA] Progress: %d%%\n", pct);

        if (_instance->_progressCb) _instance->_progressCb(progress, total);
    }
}

void OTAManager::onOTAError(ota_error_t error) {
    if (!_instance) return;
    _instance->_isUpdating = false;
    _instance->_otaLastReportedPct = -1;

    // Restore normal WDT after failed OTA
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms  = WDT_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic  = true
    };
    esp_task_wdt_reconfigure(&wdt_cfg);
#else
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
#else
    ESP.wdtFeed();
#endif

    String errMsg;
    switch (error) {
        case OTA_AUTH_ERROR:    errMsg = "Auth Failed";       break;
        case OTA_BEGIN_ERROR:   errMsg = "Begin Failed";      break;
        case OTA_CONNECT_ERROR: errMsg = "Connect Failed";    break;
        case OTA_RECEIVE_ERROR: errMsg = "Receive Failed";    break;
        case OTA_END_ERROR:     errMsg = "End Failed";        break;
        default:                errMsg = "Unknown Error";     break;
    }

    _instance->_statusString = "Error: " + errMsg;
    SERIAL_PRINTF("[OTA] Error: %s\n", errMsg.c_str());

    if (_instance->_errorCb) _instance->_errorCb(errMsg);
}

// ============================================================================
// HTTP OTA — called from WebServerManager upload handler
// ============================================================================

bool OTAManager::lastHttpUpdateOk() const { OTA_LOCK(); return _httpUpdateOk; }
String OTAManager::lastHttpError() const   { OTA_LOCK(); return _httpLastError; }

void OTAManager::abortHttpUpload(const char* reason, const void* owner) {
    OTA_LOCK();
    if (!_httpInProgress && !_isUpdating) return;
    if (owner != nullptr && _activeUploadOwner != nullptr && owner != _activeUploadOwner) return;
    _httpRejected = true;
    _httpInProgress = false;
    bool wasBegun = _httpBegun;
    _httpBegun = false;
    _httpHeaderLen = 0;
    _activeUploadOwner = nullptr;
    _isUpdating = false;
    _httpUpdateOk = false;
    _httpLastReportedPct = -1;
    _httpLastError = (reason && reason[0]) ? String(reason) : String("Upload aborted");
    _statusString = "Error: " + _httpLastError;
    if (wasBegun) {
        OTA_ABORT();
    }
    restoreWdt();
    SERIAL_PRINTF("[OTA-HTTP] Aborted: %s\n", _httpLastError.c_str());
    if (_errorCb) _errorCb(_httpLastError);
}

bool OTAManager::handleHttpUpload(uint8_t* data, size_t len,
                                   size_t index, size_t contentLen,
                                   bool isFirmware, bool isFinal,
                                   const void* owner, bool* outConflict) {
    OTA_LOCK();
    if (outConflict) *outConflict = false;
    if (index == 0) {
        if (_httpInProgress || _isUpdating) {
            if (outConflict) *outConflict = true;
            return false;
        }
        // ---- First chunk — initialize state ----
        _httpRejected = false;
        _httpBegun = false;
        _httpHeaderLen = 0;
        _httpInProgress = true;
        _activeUploadOwner = owner;
        _lastHttpChunkMs = millis();
        _isUpdating   = true;
        _httpUpdateOk = false;
        _httpLastError.clear();
        _progress = 0;
        _httpTotalSize = contentLen; // cache for progress calculation
        _httpLastReportedPct = -1;
        _statusString = isFirmware ? "Updating Firmware" : "Updating Filesystem";
    } else if (_httpRejected || !_httpInProgress ||
               (owner != nullptr && _activeUploadOwner != nullptr && owner != _activeUploadOwner)) {
        return false;
    }

    _lastHttpChunkMs = millis();

    size_t dataOffset = 0;
    if (!_httpBegun) {
        if (isFirmware) {
            // Accumulate the first 2 bytes across chunks so 0/1-byte first chunks cannot bypass header checks.
            while (_httpHeaderLen < 2 && dataOffset < len) {
                _httpHeaderBuf[_httpHeaderLen++] = data[dataOffset++];
            }
            if (_httpHeaderLen >= 1 && _httpHeaderBuf[0] != 0xE9) {
                _httpLastError = "Invalid firmware binary format (Magic 0xE9 missing)";
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                _httpInProgress = false;
                _httpBegun     = false;
                _httpHeaderLen = 0;
                _activeUploadOwner = nullptr;
                _httpRejected  = true;
                SERIAL_PRINTF("[OTA-HTTP] Upload rejected: magic byte 0x%02X != 0xE9\n", _httpHeaderBuf[0]);
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
            if (_httpHeaderLen < 2) {
                if (isFinal) {
                    _httpLastError = "Invalid firmware binary (truncated header)";
                    _statusString  = "Error: " + _httpLastError;
                    _isUpdating    = false;
                    _httpInProgress = false;
                    _httpBegun     = false;
                    _httpHeaderLen = 0;
                    _activeUploadOwner = nullptr;
                    _httpRejected  = true;
                    if (_errorCb) _errorCb(_httpLastError);
                    return false;
                }
                return true; // Wait for next chunk to inspect segment count
            }
            uint8_t segments = _httpHeaderBuf[1];
            if (segments == 0 || segments > 16) {
                _httpLastError = "Corrupted firmware image: invalid segment count (" + String(segments) + ")";
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                _httpInProgress = false;
                _httpBegun     = false;
                _httpHeaderLen = 0;
                _activeUploadOwner = nullptr;
                _httpRejected  = true;
                SERIAL_PRINTF("[OTA-HTTP] Upload rejected: invalid segment count %u\n", segments);
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
#if defined(ESP8266)
            // Reject ESP32 firmware binaries uploaded directly to an ESP8266 (ESP32 app desc magic 0xABCD5432 at offset 32)
            if (index == 0 && len >= 36 &&
                data[32] == 0x32 && data[33] == 0x54 && data[34] == 0xCD && data[35] == 0xAB) {
                _httpLastError = "Incompatible firmware: ESP32 binary cannot be flashed onto ESP8266";
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                _httpInProgress = false;
                _httpBegun     = false;
                _httpHeaderLen = 0;
                _activeUploadOwner = nullptr;
                _httpRejected  = true;
                Serial.println(F("[OTA-HTTP] Upload rejected: ESP32 app magic detected on ESP8266"));
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
#endif
        } else {
            if (index == 0 && len == 0 && isFinal) {
                _httpLastError = "Empty filesystem image";
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                _httpInProgress = false;
                _httpBegun     = false;
                _httpHeaderLen = 0;
                _activeUploadOwner = nullptr;
                _httpRejected  = true;
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
        }

#if defined(ESP8266)
        int command = isFirmware ? U_FLASH : U_FS;
#else
        int command = isFirmware ? U_FLASH : U_SPIFFS;
        // ALWAYS use UPDATE_SIZE_UNKNOWN for HTTP OTA on ESP32.
        // On ESP8266, runAsync(true) and target-partition space calculation are used.
        size_t updateSize = UPDATE_SIZE_UNKNOWN;
#endif
        (void)contentLen; // Intentionally unused — multipart CL is unreliable
        SERIAL_PRINTF("[OTA-HTTP] Start: %s (size: dynamic)\n",
                      isFirmware ? "Firmware" : "Filesystem");

        // Extend WDT for flash erase
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
        esp_task_wdt_config_t wdt_cfg = {
            .timeout_ms  = WDT_OTA_TIMEOUT_SECONDS * 1000,
            .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
            .trigger_panic  = true
        };
        esp_task_wdt_reconfigure(&wdt_cfg);
#else
        esp_task_wdt_init(WDT_OTA_TIMEOUT_SECONDS, true);
#endif
#else
        ESP.wdtFeed();
#endif

        // If a new firmware update is initiated while previous rollback check was pending,
        // validate current partition so esp_ota_begin() doesn't reject with ESP_ERR_OTA_ROLLBACK_INVALID_STATE.
        if (isFirmware && _stabilityCheckPending) {
            markAppValid();
        }

        // Suspend competing network/storage services and unmount LittleFS before filesystem flash erase
        if (_startCb) _startCb();
        if (!isFirmware) {
            LittleFS.end();
        }

#if defined(ESP8266)
        Update.runAsync(true);
        uint32_t freeSketch = ESP.getFreeSketchSpace();
        size_t maxUpdateSpace = isFirmware
            ? ((freeSketch > 0x1000) ? ((freeSketch - 0x1000) & 0xFFFFF000) : 0)
            : ((size_t)FS_PHYS_SIZE);
        if (maxUpdateSpace == 0 || !Update.begin(maxUpdateSpace, command)) {
#else
        if (!Update.begin(updateSize, command)) {
#endif
            _httpLastError = "Not enough space: " + String(OTA_ERROR_STR());
            _statusString  = "Error: " + _httpLastError;
            _isUpdating    = false;
            _httpInProgress = false;
            _httpBegun     = false;
            _httpHeaderLen = 0;
            _activeUploadOwner = nullptr;
            _httpRejected  = true;
            SERIAL_PRINTF("[OTA-HTTP] begin() failed: %s\n", OTA_ERROR_STR());
            if (!isFirmware) {
                LittleFS.begin();
            }
            restoreWdt();
            if (_errorCb) _errorCb(_httpLastError);
            return false;
        }

        _httpBegun = true;

        if (isFirmware && _httpHeaderLen > 0) {
            if (Update.write(_httpHeaderBuf, _httpHeaderLen) != _httpHeaderLen) {
                _httpLastError = "Header write failed: " + String(OTA_ERROR_STR());
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                _httpInProgress = false;
                _httpBegun     = false;
                _httpHeaderLen = 0;
                _activeUploadOwner = nullptr;
                _httpRejected  = true;
                OTA_ABORT();
                restoreWdt();
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
        }
    }

    // ---- Write remaining chunk bytes ----
#if defined(ESP8266)
    ESP.wdtFeed();
#endif
    size_t remainLen = len - dataOffset;
    if (remainLen > 0 && Update.write(data + dataOffset, remainLen) != remainLen) {
        _httpLastError = "Write failed: " + String(OTA_ERROR_STR());
        _statusString  = "Error: " + _httpLastError;
        _isUpdating    = false;
        _httpInProgress = false;
        _activeUploadOwner = nullptr;
        _httpRejected  = true;
        _httpLastReportedPct = -1;
        SERIAL_PRINTF("[OTA-HTTP] write() failed: %s\n", OTA_ERROR_STR());
        OTA_ABORT();
        restoreWdt();
        if (_errorCb) _errorCb(_httpLastError);
        return false;
    }

    // ---- Progress ----
    size_t written = index + len;
    int pct = 0;
    if (_httpTotalSize > 0) {
        pct = (int)((written * 100UL) / _httpTotalSize);
    } else if (Update.size() > 0) {
        pct = (int)(Update.progress() * 100UL / Update.size());
    }
    _progress = min(pct, 99); // hold at 99 until end() succeeds
    if (pct >= _httpLastReportedPct + 5 || isFinal) {
        _httpLastReportedPct = pct;
        SERIAL_PRINTF("[OTA-HTTP] Progress: %d%%\n", pct);
        if (_progressCb && _httpTotalSize > 0) _progressCb((int)written, (int)_httpTotalSize);
    }

    // ---- Final chunk — commit ----
    if (isFinal) {
        _httpLastReportedPct = -1;
        _httpInProgress = false;
        _activeUploadOwner = nullptr;
        SERIAL_PRINTF("[OTA-HTTP] Finalising, written=%u\n", written);
        if (!Update.end(true)) {
            _httpLastError = "Flash verify failed: " + String(OTA_ERROR_STR());
            _statusString  = "Error: " + _httpLastError;
            _isUpdating    = false;
            _httpLastReportedPct = -1;
            SERIAL_PRINTF("[OTA-HTTP] end() failed: %s (err code %d)\n",
                          OTA_ERROR_STR(), Update.getError());
            restoreWdt();
            if (_errorCb) _errorCb(_httpLastError);
            return false;
        }

        _httpUpdateOk = true;
        _progress     = 100;
        _statusString = "Success — Rebooting";
        _isUpdating   = false;
        Serial.println(F("[OTA-HTTP] Update complete!"));
        restoreWdt();
        if (_endCb) _endCb();
    }

    return true;
}

// Private helper — restores WDT to normal timeout
void OTAManager::restoreWdt() {
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms  = WDT_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic  = true
    };
    esp_task_wdt_reconfigure(&wdt_cfg);
#else
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
#else
    ESP.wdtFeed();
#endif
}
