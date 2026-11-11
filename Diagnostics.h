/*
 * ============================================================================
 * Diagnostics.h — System Diagnostics & Health Monitoring
 * ============================================================================
 */

#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <Arduino.h>
#include <ArduinoJson.h>
#if defined(ESP32)
#include <esp_system.h>
#endif
#include "Config.h"

class Diagnostics {
public:
    Diagnostics();

    void begin();
    void loop();

    uint32_t getFreeHeap();
    uint32_t getMinFreeHeap();
    uint32_t getTotalHeap();
    float getHeapFragmentation();
    String getUptimeString();
    unsigned long getUptimeSeconds();
    String getResetReason();
    String getChipModel();
    uint8_t getChipRevision();
    uint32_t getChipId();
    uint32_t getCpuFreqMHz();
    uint32_t getFlashSize();
    String getSdkVersion();
    String getFirmwareVersion();
    String getBuildDate();
    bool isLowMemory();

    void toJson(JsonObject& obj);

private:
    uint32_t _minFreeHeap;
    unsigned long _lastCheck;
    unsigned long _bootTime;
    String _resetReason;

#if defined(ESP32)
    String decodeResetReason(esp_reset_reason_t reason);
#endif
};

#endif // DIAGNOSTICS_H
