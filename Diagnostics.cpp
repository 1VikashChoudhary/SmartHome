/*
 * ============================================================================
 * Diagnostics.cpp — System Diagnostics Implementation
 * ============================================================================
 */

#include "Diagnostics.h"

Diagnostics::Diagnostics()
    : _minFreeHeap(UINT32_MAX), _lastCheck(0), _bootTime(0),
      _rolloverCount(0), _lastMillis(0) {}

void Diagnostics::begin() {
    _bootTime = millis();
    _rolloverCount = 0;
    _lastMillis = _bootTime;
    _minFreeHeap = ESP.getFreeHeap();
#if defined(ESP8266)
    _resetReason = ESP.getResetReason();
#else
    _resetReason = decodeResetReason(esp_reset_reason());
#endif

    Serial.println(F("[Diag] System Diagnostics:"));
    SERIAL_PRINTF("  Chip: %s rev%d  ID: %08lX\n", getChipModel().c_str(), getChipRevision(), (unsigned long)getChipId());
    SERIAL_PRINTF("  CPU: %lu MHz  Flash: %lu KB  Heap: %lu KB\n",
                  (unsigned long)getCpuFreqMHz(), (unsigned long)(getFlashSize() / 1024), (unsigned long)(getTotalHeap() / 1024));
    SERIAL_PRINTF("  Reset reason: %s\n", _resetReason.c_str());
    SERIAL_PRINTF("  SDK: %s  Firmware: %s (%s %s)\n",
                  getSdkVersion().c_str(), FW_VERSION, FW_BUILD_DATE, FW_BUILD_TIME);
}

void Diagnostics::loop() {
    unsigned long now = millis();
    if (now < _lastMillis) {
        _rolloverCount++;
    }
    _lastMillis = now;
    if (now - _lastCheck < DIAG_UPDATE_INTERVAL) return;
    _lastCheck = now;

    uint32_t freeHeap = ESP.getFreeHeap();
    if (freeHeap < _minFreeHeap) {
        _minFreeHeap = freeHeap;
    }

    if (isLowMemory()) {
        SERIAL_PRINTF("[Diag] WARNING: Low memory! Free: %lu bytes\n", (unsigned long)freeHeap);
    }
}

uint32_t Diagnostics::getFreeHeap()    { return ESP.getFreeHeap(); }
uint32_t Diagnostics::getMinFreeHeap() { return _minFreeHeap; }
uint32_t Diagnostics::getTotalHeap()   {
#if defined(ESP8266)
    return 81920; // 80 KB internal data RAM
#else
    return ESP.getHeapSize();
#endif
}

float Diagnostics::getHeapFragmentation() {
#if defined(ESP8266)
    return (float)ESP.getHeapFragmentation();
#else
    uint32_t maxBlock = ESP.getMaxAllocHeap();
    uint32_t freeHeap = ESP.getFreeHeap();
    if (freeHeap == 0) return 100.0f;
    return (1.0f - ((float)maxBlock / (float)freeHeap)) * 100.0f;
#endif
}

String Diagnostics::getUptimeString() {
    unsigned long totalSec = getUptimeSeconds();
    unsigned long days    = totalSec / 86400;
    unsigned long hours   = (totalSec % 86400) / 3600;
    unsigned long minutes = (totalSec % 3600) / 60;
    unsigned long seconds = totalSec % 60;

    char buf[24];
    if (days > 0) {
        snprintf(buf, sizeof(buf), "%lud %luh %lum", days, hours, minutes);
    } else if (hours > 0) {
        snprintf(buf, sizeof(buf), "%luh %lum %lus", hours, minutes, seconds);
    } else {
        snprintf(buf, sizeof(buf), "%lum %lus", minutes, seconds);
    }
    return String(buf);
}

unsigned long Diagnostics::getUptimeSeconds() {
    unsigned long now = millis();
    if (now < _lastMillis) {
        _rolloverCount++;
    }
    _lastMillis = now;
    uint64_t totalMs = ((uint64_t)_rolloverCount << 32) | (uint64_t)now;
    return (unsigned long)(totalMs / 1000ULL);
}

String Diagnostics::getResetReason() { return _resetReason; }

String Diagnostics::getChipModel() {
#if defined(ESP8266)
    return F("ESP8266");
#else
    return String(ESP.getChipModel());
#endif
}

uint8_t Diagnostics::getChipRevision() {
#if defined(ESP8266)
    return 0;
#else
    return ESP.getChipRevision();
#endif
}

uint32_t Diagnostics::getChipId() {
#if defined(ESP8266)
    return ESP.getChipId();
#else
    uint64_t mac = ESP.getEfuseMac();
    return (uint32_t)(mac & 0xFFFFFFFF);
#endif
}

uint32_t Diagnostics::getCpuFreqMHz() { return ESP.getCpuFreqMHz(); }
uint32_t Diagnostics::getFlashSize()  {
#if defined(ESP8266)
    return ESP.getFlashChipRealSize();
#else
    return ESP.getFlashChipSize();
#endif
}
String Diagnostics::getSdkVersion()   { return String(ESP.getSdkVersion()); }
String Diagnostics::getFirmwareVersion() { return String(FW_VERSION); }
String Diagnostics::getBuildDate() {
    return String(FW_BUILD_DATE) + " " + String(FW_BUILD_TIME);
}

bool Diagnostics::isLowMemory() {
    return ESP.getFreeHeap() < MIN_FREE_HEAP;
}

void Diagnostics::toJson(JsonObject& obj) {
    obj["free_heap"]     = getFreeHeap();
    obj["min_heap"]      = getMinFreeHeap();
    obj["total_heap"]    = getTotalHeap();
    obj["heap_frag"]     = (int)getHeapFragmentation();
    obj["uptime"]        = getUptimeString();
    obj["uptime_sec"]    = getUptimeSeconds();
    obj["reset_reason"]  = getResetReason();
    obj["chip_model"]    = getChipModel();
    obj["chip_rev"]      = getChipRevision();
    obj["chip_id"]       = String(getChipId(), HEX);
    obj["cpu_freq"]      = getCpuFreqMHz();
    obj["flash_size"]    = getFlashSize();
    obj["sdk_version"]   = getSdkVersion();
    obj["fw_version"]    = getFirmwareVersion();
    obj["fw_build"]      = getBuildDate();
    obj["low_memory"]    = isLowMemory();
}

#if defined(ESP32)
String Diagnostics::decodeResetReason(esp_reset_reason_t reason) {
    switch (reason) {
        case ESP_RST_POWERON:   return F("Power On");
        case ESP_RST_EXT:       return F("External Reset");
        case ESP_RST_SW:        return F("Software Reset");
        case ESP_RST_PANIC:     return F("Exception/Panic");
        case ESP_RST_INT_WDT:   return F("Interrupt Watchdog");
        case ESP_RST_TASK_WDT:  return F("Task Watchdog");
        case ESP_RST_WDT:       return F("Other Watchdog");
        case ESP_RST_DEEPSLEEP: return F("Deep Sleep");
        case ESP_RST_BROWNOUT:  return F("Brownout");
        case ESP_RST_SDIO:      return F("SDIO");
        default:                return F("Unknown");
    }
}
#endif
