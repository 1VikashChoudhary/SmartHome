/*
 * ============================================================================
 * EventLogger.cpp — Ring-buffer Event Logger Implementation
 * ============================================================================
 */

#include "EventLogger.h"

#if defined(ESP32)
namespace {
class LogMutexGuard {
public:
    explicit LogMutexGuard(SemaphoreHandle_t mtx) : _mtx(mtx) {
        if (_mtx) xSemaphoreTakeRecursive(_mtx, portMAX_DELAY);
    }
    ~LogMutexGuard() {
        if (_mtx) xSemaphoreGiveRecursive(_mtx);
    }
private:
    SemaphoreHandle_t _mtx;
};
} // namespace

void EventLogger::ensureMutex() const {
    if (!_logMutex) {
        _logMutex = xSemaphoreCreateRecursiveMutex();
    }
}
#define LOG_LOCK() ensureMutex(); LogMutexGuard _logLockGuard(_logMutex)
#else
#define LOG_LOCK() ((void)0)
#endif

EventLogger::EventLogger()
    : _storage(nullptr), _head(0), _count(0), _dirty(false),
      _lastPersist(0), _lastAutoClean(0)
#if defined(ESP32)
    , _logMutex(nullptr)
#endif
{
    memset(_entries, 0, sizeof(_entries));
}

void EventLogger::begin(StorageManager& storage) {
    _storage = &storage;
#if defined(ESP32)
    ensureMutex();
#endif
    loadFromStorage();
    _lastPersist = millis();
    _lastAutoClean = millis();
    SERIAL_PRINTF("[Logger] Initialized with %d entries\n", _count);
}

void EventLogger::loop() {
    unsigned long now = millis();

    // Periodic persist to flash
    if (_dirty && (now - _lastPersist >= LOG_PERSIST_INTERVAL)) {
        persistNow();
    }

    // Daily auto-clean check (every hour is fine)
    if (now - _lastAutoClean >= 3600000UL) {
        _lastAutoClean = now;
        autoClean();
    }
}

void EventLogger::log(uint8_t level, const char* source, const String& message) {
    LOG_LOCK();
    LogEntry& entry = _entries[_head];
    entry.timestamp = getTimestamp();
    entry.level = level;
    strncpy(entry.source, source, sizeof(entry.source) - 1);
    entry.source[sizeof(entry.source) - 1] = '\0';
    strncpy(entry.message, message.c_str(), sizeof(entry.message) - 1);
    entry.message[sizeof(entry.message) - 1] = '\0';

    _head = (_head + 1) % MAX_LOG_ENTRIES;
    if (_count < MAX_LOG_ENTRIES) _count++;
    _dirty = true;

    // Also print to Serial
    SERIAL_PRINTF("[LOG][%s][%s] %s\n", levelToString(level), source, message.c_str());
}

void EventLogger::logInfo(const char* source, const String& message)     { log(LOG_INFO, source, message); }
void EventLogger::logWarning(const char* source, const String& message)  { log(LOG_WARNING, source, message); }
void EventLogger::logError(const char* source, const String& message)    { log(LOG_ERROR, source, message); }
void EventLogger::logCritical(const char* source, const String& message) { log(LOG_CRITICAL, source, message); }

uint16_t EventLogger::getCount() {
    LOG_LOCK();
    return _count;
}

void EventLogger::clear() {
    LOG_LOCK();
    _head = 0;
    _count = 0;
    _dirty = false;
    memset(_entries, 0, sizeof(_entries));
    if (_storage) _storage->deleteFile(PATH_LOGS);
    Serial.println(F("[Logger] Logs cleared"));
}

String EventLogger::toJson(int limit) {
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    toJsonArray(arr, limit);
    String output;
    serializeJson(doc, output);
    return output;
}

void EventLogger::toJsonArray(JsonArray& arr, int limit) {
    LOG_LOCK();
    if (_count == 0 || limit <= 0) return;

    int total = min((int)_count, limit);
    int start = ((int)_head - total + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;

    for (int i = 0; i < total; i++) {
        int idx = (start + i) % MAX_LOG_ENTRIES;
        const LogEntry& e = _entries[idx];

        JsonObject obj = arr.add<JsonObject>();
        obj["ts"] = e.timestamp;
        obj["lvl"] = e.level;
        obj["lvl_s"] = levelToString(e.level);
        obj["src"] = e.source;
        obj["msg"] = e.message;
    }
}

String EventLogger::toCSV() {
    LOG_LOCK();
    String csv;
    csv.reserve((size_t)_count * 56 + 40);
    csv = F("Timestamp,Level,Source,Message\n");

    if (_count == 0) return csv;

    int start = ((int)_head - (int)_count + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;

    for (uint16_t i = 0; i < _count; i++) {
        int idx = (start + i) % MAX_LOG_ENTRIES;
        const LogEntry& e = _entries[idx];

        String src = String(e.source);
        src.replace("\"", "\"\"");
        src.replace("\r", " ");
        src.replace("\n", " ");

        String msg = String(e.message);
        msg.replace("\"", "\"\"");
        msg.replace("\r", " ");
        msg.replace("\n", " ");

        csv += String(e.timestamp) + "," +
               levelToString(e.level) + ",\"" +
               src + "\",\"" + msg + "\"\n";
    }
    return csv;
}

void EventLogger::persistNow() {
    LOG_LOCK();
    if (!_storage) return;
    if (_count == 0) {
        _storage->deleteFile(PATH_LOGS);
        _dirty = false;
        _lastPersist = millis();
        return;
    }

    JsonDocument doc;
    JsonArray arr = doc["logs"].to<JsonArray>();

    // Save last 100 entries max to keep file size manageable
    int saveCount = min((int)_count, 100);
    int saveStart = ((int)_head - saveCount + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;

    for (int i = 0; i < saveCount; i++) {
        int idx = (saveStart + i) % MAX_LOG_ENTRIES;
        const LogEntry& e = _entries[idx];
        JsonObject obj = arr.add<JsonObject>();
        obj["ts"] = e.timestamp;
        obj["lvl"] = e.level;
        obj["src"] = e.source;
        obj["msg"] = e.message;
    }

    if (_storage->saveJson(PATH_LOGS, doc)) {
        _dirty = false;
    }
    _lastPersist = millis();
}

// ============================================================================
// Private
// ============================================================================

uint32_t EventLogger::getTimestamp() {
    time_t now;
    time(&now);
    if (now > 1600000000) return (uint32_t)now; // Valid epoch
    return millis() / 1000; // Fallback to uptime seconds
}

void EventLogger::autoClean() {
    LOG_LOCK();
    if (_count == 0) return;

    uint32_t now = getTimestamp();
    if (now < 1600000000) return; // Can't clean without valid time

    uint32_t cutoff = now - (LOG_AUTO_CLEAR_DAYS * 86400UL);
    int cleaned = 0;

    // Compact expired epoch-timestamped entries in-place without stalling on pre-NTP uptime records
    uint16_t start = ((uint16_t)_head + MAX_LOG_ENTRIES - _count) % MAX_LOG_ENTRIES;
    uint16_t writeOffset = 0;
    for (uint16_t i = 0; i < _count; i++) {
        uint16_t readIdx = (start + i) % MAX_LOG_ENTRIES;
        if (_entries[readIdx].timestamp > 1600000000 && _entries[readIdx].timestamp < cutoff) {
            cleaned++;
        } else {
            if (writeOffset != i) {
                uint16_t writeIdx = (start + writeOffset) % MAX_LOG_ENTRIES;
                _entries[writeIdx] = _entries[readIdx];
            }
            writeOffset++;
        }
    }

    if (cleaned > 0) {
        _count = writeOffset;
        _head = (start + writeOffset) % MAX_LOG_ENTRIES;
        if (_count == 0) {
            if (_storage) _storage->deleteFile(PATH_LOGS);
            _dirty = false;
        } else {
            _dirty = true;
        }
        SERIAL_PRINTF("[Logger] Auto-cleaned %d old entries\n", cleaned);
    }
}

void EventLogger::loadFromStorage() {
    if (!_storage) return;

    JsonDocument doc;
    if (!_storage->loadJson(PATH_LOGS, doc)) return;

    JsonArray arr = doc["logs"].as<JsonArray>();
    _head = 0;
    _count = 0;
    memset(_entries, 0, sizeof(_entries));

    for (JsonObject obj : arr) {
        LogEntry& entry = _entries[_head];
        entry.timestamp = obj["ts"] | 0;
        entry.level = obj["lvl"] | 0;
        strncpy(entry.source, obj["src"] | "???", sizeof(entry.source) - 1);
        entry.source[sizeof(entry.source) - 1] = '\0';
        strncpy(entry.message, obj["msg"] | "", sizeof(entry.message) - 1);
        entry.message[sizeof(entry.message) - 1] = '\0';

        _head = (_head + 1) % MAX_LOG_ENTRIES;
        if (_count < MAX_LOG_ENTRIES) _count++;
    }
}

const char* EventLogger::levelToString(uint8_t level) {
    switch (level) {
        case LOG_INFO:     return "INFO";
        case LOG_WARNING:  return "WARN";
        case LOG_ERROR:    return "ERROR";
        case LOG_CRITICAL: return "CRIT";
        default:           return "???";
    }
}
