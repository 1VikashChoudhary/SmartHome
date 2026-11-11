/*
 * ============================================================================
 * OTAManager.cpp — ArduinoOTA Implementation
 * ============================================================================
 */

#include "OTAManager.h"
#if defined(ESP8266)
#include <Updater.h>
#else
#include <Update.h>
#endif

OTAManager* OTAManager::_instance = nullptr;

OTAManager::OTAManager()
    : _arduinoOtaEnabled(false), _hostname(""), _otaPassword(""),
      _isUpdating(false), _progress(0), _statusString("Idle"),
      _progressCb(nullptr), _startCb(nullptr), _endCb(nullptr), _errorCb(nullptr),
      _httpUpdateOk(false), _httpTotalSize(0),
      _stabilityCheckPending(false), _stabilityCheckStart(0) {
    _instance = this;
}

void OTAManager::begin(const String& hostname, bool enableArduinoOta, const String& otaPassword) {
    _hostname = hostname;
    _otaPassword = otaPassword;
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
                Serial.printf("[OTA-Rollback] New firmware running on '%s' in PENDING_VERIFY state!\n", running->label);
                Serial.println(F("[OTA-Rollback] Zero-Brick stability check ARMED: 30-second verification timer active."));
                Serial.println(F("[OTA-Rollback] If firmware panics or boot-loops, ESP32 bootloader will auto-revert to backup partition."));
            } else {
                _stabilityCheckPending = false;
                Serial.printf("[OTA-Rollback] Partition '%s' is confirmed valid (State: 0x%02X)\n", running->label, (unsigned int)ota_state);
            }
        } else {
            _stabilityCheckPending = false;
            Serial.printf("[OTA-Rollback] Running on partition '%s' (Standard/Factory)\n", running->label);
        }
    }
#else
    _stabilityCheckPending = false;
#endif

    if (enableArduinoOta) {
        setArduinoOtaEnabled(true);
    } else {
        Serial.println(F("[OTA] ArduinoOTA (port 3232) disabled by default. HTTP OTA active."));
    }
}

void OTAManager::setArduinoOtaEnabled(bool enabled, const String& hostname, const String& password) {
    if (hostname.length() > 0) _hostname = hostname;
    if (password.length() > 0) _otaPassword = password;
    if (_hostname.length() == 0) _hostname = OTA_HOSTNAME_PREFIX;
    if (_arduinoOtaEnabled == enabled) return;
    _arduinoOtaEnabled = enabled;
    if (_arduinoOtaEnabled) {
        ArduinoOTA.setHostname(_hostname.c_str());
        // Use admin web password if available, fallback to hostname-based password
        if (_otaPassword.length() > 0) {
            ArduinoOTA.setPassword(_otaPassword.c_str());
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
        Serial.printf("[OTA] ArduinoOTA (port 3232) ENABLED dynamically on '%s'\n", _hostname.c_str());
    } else {
        ArduinoOTA.end();
        Serial.println(F("[OTA] ArduinoOTA (port 3232) DISABLED dynamically"));
    }
}

void OTAManager::loop() {
    if (_arduinoOtaEnabled) {
        ArduinoOTA.handle();
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
        Serial.printf("[OTA-Rollback] mark_app_valid returned error 0x%X\n", err);
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
    if (running && running->label) {
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
        Serial.printf("[OTA-Rollback] esp_ota_mark_app_invalid_rollback_and_reboot failed (0x%X), using Update.rollBack()...\n", err);
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
String OTAManager::getStatusString() { return _statusString; }

void OTAManager::setProgressCallback(void (*cb)(int, int)) { _progressCb = cb; }
void OTAManager::setStartCallback(void (*cb)()) { _startCb = cb; }
void OTAManager::setEndCallback(void (*cb)()) { _endCb = cb; }
void OTAManager::setErrorCallback(void (*cb)(const String&)) { _errorCb = cb; }

// --- Static Callbacks ---

void OTAManager::onOTAStart() {
    if (!_instance) return;
    _instance->_isUpdating = true;
    _instance->_progress = 0;

    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "Firmware" : "Filesystem";
    _instance->_statusString = "Updating " + type;
    Serial.printf("[OTA] Start: %s update\n", type.c_str());

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
    Serial.printf("[OTA] WDT extended to %ds\n", WDT_OTA_TIMEOUT_SECONDS);
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
    if (!_instance) return;
    int pct = (progress * 100) / total;
    _instance->_progress = pct;

    // Keep progress handling coarse to avoid extra work during OTA packet flow.
    static int lastReportedPct = -1;
    if (pct >= lastReportedPct + 5 || pct == 100) {
        lastReportedPct = pct;
        _instance->_statusString = "Updating";
        Serial.printf("[OTA] Progress: %d%%\n", pct);

        if (_instance->_progressCb) _instance->_progressCb(progress, total);
    }
}

void OTAManager::onOTAError(ota_error_t error) {
    if (!_instance) return;
    _instance->_isUpdating = false;

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
    Serial.printf("[OTA] Error: %s\n", errMsg.c_str());

    if (_instance->_errorCb) _instance->_errorCb(errMsg);
}

// ============================================================================
// HTTP OTA — called from WebServerManager upload handler
// ============================================================================

bool OTAManager::lastHttpUpdateOk() const { return _httpUpdateOk; }
String OTAManager::lastHttpError() const   { return _httpLastError; }

bool OTAManager::handleHttpUpload(uint8_t* data, size_t len,
                                   size_t index, size_t contentLen,
                                   bool isFirmware, bool isFinal) {
    if (index == 0) {
        // ---- First chunk — begin update ----
        _isUpdating   = true;
        _httpUpdateOk = false;
        _httpLastError.clear();
        _progress = 0;
        _httpTotalSize = contentLen; // cache for progress calculation

        int command = isFirmware ? U_FLASH : U_SPIFFS;
        _statusString = isFirmware ? "Updating Firmware" : "Updating Filesystem";

        // Integrity check: Verify image format (Magic 0xE9, segment count)
        if (isFirmware) {
            if (len >= 1 && data[0] != 0xE9) {
                _httpLastError = "Invalid firmware binary format (Magic 0xE9 missing)";
                _statusString  = "Error: " + _httpLastError;
                _isUpdating    = false;
                Serial.printf("[OTA-HTTP] Upload rejected: magic byte 0x%02X != 0xE9\n", data[0]);
                if (_errorCb) _errorCb(_httpLastError);
                return false;
            }
            if (len >= 2) {
                uint8_t segments = data[1];
                if (segments == 0 || segments > 16) {
                    _httpLastError = "Corrupted firmware image: invalid segment count (" + String(segments) + ")";
                    _statusString  = "Error: " + _httpLastError;
                    _isUpdating    = false;
                    Serial.printf("[OTA-HTTP] Upload rejected: invalid segment count %u\n", segments);
                    if (_errorCb) _errorCb(_httpLastError);
                    return false;
                }
            }
        }

        // ALWAYS use UPDATE_SIZE_UNKNOWN for HTTP OTA on ESP32.
        // On ESP8266, runAsync(true) and sketch space calculation are used.
        size_t updateSize = UPDATE_SIZE_UNKNOWN;
        (void)contentLen; // Intentionally unused — multipart CL is unreliable
        Serial.printf("[OTA-HTTP] Start: %s (size: dynamic)\n",
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

#if defined(ESP8266)
        Update.runAsync(true);
        size_t maxSketchSpace = (ESP.getFreeSketchSpace() - 0x1000) & 0xFFFFF000;
        if (!Update.begin(maxSketchSpace, command)) {
#else
        if (!Update.begin(updateSize, command)) {
#endif
            _httpLastError = "Not enough space: " + String(OTA_ERROR_STR());
            _statusString  = "Error: " + _httpLastError;
            _isUpdating    = false;
            Serial.printf("[OTA-HTTP] begin() failed: %s\n", OTA_ERROR_STR());
            restoreWdt();
            if (_errorCb) _errorCb(_httpLastError);
            return false;
        }

        if (_startCb) _startCb();
    }

    // ---- Write chunk ----
#if defined(ESP32)
    esp_task_wdt_reset(); // Feed WDT every chunk
#else
    ESP.wdtFeed();
#endif
    if (Update.write(data, len) != len) {
        _httpLastError = "Write failed: " + String(OTA_ERROR_STR());
        _statusString  = "Error: " + _httpLastError;
        _isUpdating    = false;
        Serial.printf("[OTA-HTTP] write() failed: %s\n", OTA_ERROR_STR());
        OTA_ABORT();
        restoreWdt();
        if (_errorCb) _errorCb(_httpLastError);
        return false;
    }

    // ---- Progress ----
    size_t written = index + len;
    int pct = (_httpTotalSize > 0)
              ? (int)((written * 100UL) / _httpTotalSize)
              : (int)(Update.progress() * 100UL / Update.size());
    _progress = min(pct, 99); // hold at 99 until end() succeeds
    static int lastPct = -1;
    if (pct >= lastPct + 5 || isFinal) {
        lastPct = pct;
        Serial.printf("[OTA-HTTP] Progress: %d%%\n", pct);
        if (_progressCb) _progressCb((int)written, (int)_httpTotalSize);
    }

    // ---- Final chunk — commit ----
    if (isFinal) {
        lastPct = -1;
        Serial.printf("[OTA-HTTP] Finalising, written=%u\n", written);
        if (!Update.end(true)) {
            _httpLastError = "Flash verify failed: " + String(OTA_ERROR_STR());
            _statusString  = "Error: " + _httpLastError;
            _isUpdating    = false;
            Serial.printf("[OTA-HTTP] end() failed: %s (err code %d)\n",
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
