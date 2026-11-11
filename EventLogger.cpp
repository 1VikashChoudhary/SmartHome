/*
 * ============================================================================
 * EventLogger.cpp — Ring-buffer Event Logger Implementation
 * ============================================================================
 */

#include "EventLogger.h"

EventLogger::EventLogger()
    : _storage(nullptr), _head(0), _count(0), _dirty(false),
      _lastPersist(0), _lastAutoClean(0) {
    memset(_entries, 0, sizeof(_entries));
}

void EventLogger::begin(StorageManager& storage) {
    _storage = &storage;
    loadFromStorage();
    _lastPersist = millis();
    _lastAutoClean = millis();
    Serial.printf("[Logger] Initialized with %d entries\n", _count);
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
    Serial.printf("[LOG][%s][%s] %s\n", levelToString(level), source, message.c_str());
}

void EventLogger::logInfo(const char* source, const String& message)     { log(LOG_INFO, source, message); }
void EventLogger::logWarning(const char* source, const String& message)  { log(LOG_WARNING, source, message); }
void EventLogger::logError(const char* source, const String& message)    { log(LOG_ERROR, source, message); }
void EventLogger::logCritical(const char* source, const String& message) { log(LOG_CRITICAL, source, message); }

uint16_t EventLogger::getCount() { return _count; }

void EventLogger::clear() {
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
    if (_count == 0) return;

    int start;
    int total = min((int)_count, limit);

    // Calculate starting index (oldest entry within limit)
    if (_count >= MAX_LOG_ENTRIES) {
        start = (_head - total + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;
    } else {
        start = max(0, (int)_head - total);
    }

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
    String csv = F("Timestamp,Level,Source,Message\n");

    if (_count == 0) return csv;

    int start;
    if (_count >= MAX_LOG_ENTRIES) {
        start = _head; // Oldest entry
    } else {
        start = 0;
    }

    for (uint16_t i = 0; i < _count; i++) {
        int idx = (start + i) % MAX_LOG_ENTRIES;
        const LogEntry& e = _entries[idx];

        csv += String(e.timestamp) + "," +
               levelToString(e.level) + "," +
               e.source + ",\"" + e.message + "\"\n";
    }
    return csv;
}

void EventLogger::persistNow() {
    if (!_storage || _count == 0) return;

    JsonDocument doc;
    JsonArray arr = doc["logs"].to<JsonArray>();

    int start;
    if (_count >= MAX_LOG_ENTRIES) {
        start = _head;
    } else {
        start = 0;
    }

    // Save last 100 entries max to keep file size manageable
    int saveCount = min((int)_count, 100);
    int saveStart = (_head - saveCount + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;

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
        _lastPersist = millis();
    }
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
    if (_count == 0) return;

    uint32_t now = getTimestamp();
    if (now < 1600000000) return; // Can't clean without valid time

    uint32_t cutoff = now - (LOG_AUTO_CLEAR_DAYS * 86400UL);
    int cleaned = 0;

    // Remove entries older than cutoff from the tail
    while (_count > 0) {
        int oldest;
        if (_count >= MAX_LOG_ENTRIES) {
            oldest = _head;
        } else {
            oldest = (_head - _count + MAX_LOG_ENTRIES) % MAX_LOG_ENTRIES;
        }

        if (_entries[oldest].timestamp < cutoff && _entries[oldest].timestamp > 1600000000) {
            _count--;
            cleaned++;
        } else {
            break;
        }
    }

    if (cleaned > 0) {
        _dirty = true;
        Serial.printf("[Logger] Auto-cleaned %d old entries\n", cleaned);
    }
}

void EventLogger::loadFromStorage() {
    if (!_storage) return;

    JsonDocument doc;
    if (!_storage->loadJson(PATH_LOGS, doc)) return;

    JsonArray arr = doc["logs"].as<JsonArray>();
    _head = 0;
    _count = 0;

    for (JsonObject obj : arr) {
        if (_count >= MAX_LOG_ENTRIES) {
            // Ring buffer full, overwrite oldest
            _head = (_head + 1) % MAX_LOG_ENTRIES;
        }

        int idx = (_head + _count) % MAX_LOG_ENTRIES;
        if (_count < MAX_LOG_ENTRIES) {
            idx = _count;
        } else {
            idx = _head;
            _head = (_head + 1) % MAX_LOG_ENTRIES;
        }

        _entries[idx].timestamp = obj["ts"] | 0;
        _entries[idx].level = obj["lvl"] | 0;
        strncpy(_entries[idx].source, obj["src"] | "???", sizeof(_entries[idx].source) - 1);
        strncpy(_entries[idx].message, obj["msg"] | "", sizeof(_entries[idx].message) - 1);

        if (_count < MAX_LOG_ENTRIES) _count++;
    }

    _head = _count % MAX_LOG_ENTRIES;
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
