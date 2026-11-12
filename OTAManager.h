/*
 * ============================================================================
 * OTAManager.h — ArduinoOTA with Password Protection & Progress Tracking
 * ============================================================================
 */

#ifndef OTA_MANAGER_H
#define OTA_MANAGER_H

#include <Arduino.h>
#include <ArduinoOTA.h>
#if defined(ESP32)
#include <esp_task_wdt.h>
#include <esp_arduino_version.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>
#endif
#include "Config.h"

#ifndef U_SPIFFS
#define U_SPIFFS U_FS
#endif

#ifndef UPDATE_SIZE_UNKNOWN
#define UPDATE_SIZE_UNKNOWN 0xFFFFFFFF
#endif

#if defined(ESP8266)
#define OTA_ERROR_STR() (Update.getErrorString().c_str())
#define OTA_ABORT() Update.end(false)
#else
#define OTA_ERROR_STR() (Update.errorString())
#define OTA_ABORT() Update.abort()
#endif

class OTAManager {
public:
    OTAManager();

    void begin(const String& hostname, bool enableArduinoOta = false, const String& otaPassword = "");
    void loop();

    void setArduinoOtaEnabled(bool enabled, const String& hostname = "", const String& password = "");
    bool isArduinoOtaEnabled() const { return _arduinoOtaEnabled; }

    bool isUpdating();
    int getProgress();
    String getStatusString();

    // --- Dual-Partition OTA Rollback (Zero-Brick Guarantee) ---
    bool isRollbackPending() const { return _stabilityCheckPending; }
    bool isRollbackPossible() const;
    String getRunningPartitionName() const;
    String getOtaStateString() const;
    bool markAppValid();
    bool triggerManualRollback();

    // --- HTTP OTA (web upload) ---
    // Call from the AsyncWebServer upload handler.
    // Returns true while update is in progress, false when done/failed.
    bool handleHttpUpload(uint8_t* data, size_t len, size_t index, size_t contentLen,
                          bool isFirmware, bool isFinal);
    bool lastHttpUpdateOk() const;
    String lastHttpError() const;

    void setProgressCallback(void (*cb)(int progress, int total));
    void setStartCallback(void (*cb)());
    void setEndCallback(void (*cb)());
    void setErrorCallback(void (*cb)(const String& error));

private:
    bool _arduinoOtaEnabled;
    String _hostname;
    String _otaPassword;  // Dynamic admin password for ArduinoOTA
    bool _isUpdating;
    int _progress;
    String _statusString;

    void (*_progressCb)(int, int);
    void (*_startCb)();
    void (*_endCb)();
    void (*_errorCb)(const String&);

    // HTTP OTA state
    bool _httpUpdateOk;
    String _httpLastError;
    size_t _httpTotalSize;
    int _otaLastReportedPct;
    int _httpLastReportedPct;

    // Rollback stability verification state
    bool _stabilityCheckPending;
    unsigned long _stabilityCheckStart;
    static constexpr unsigned long STABILITY_CHECK_DURATION_MS = 30000;

    void restoreWdt();

    static OTAManager* _instance;
    static void onOTAStart();
    static void onOTAEnd();
    static void onOTAProgress(unsigned int progress, unsigned int total);
    static void onOTAError(ota_error_t error);
};

#endif // OTA_MANAGER_H
