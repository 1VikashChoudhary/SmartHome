/*
 * ============================================================================
 * EventLogger.h — Ring-buffer Event Logger with CSV Export
 * ============================================================================
 */

#ifndef EVENT_LOGGER_H
#define EVENT_LOGGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <time.h>
#include "Config.h"
#include "StorageManager.h"

// Log levels
#define LOG_INFO     0
#define LOG_WARNING  1
#define LOG_ERROR    2
#define LOG_CRITICAL 3

struct LogEntry {
    uint32_t timestamp;     // epoch seconds
    uint8_t level;          // 0-3
    char source[12];        // module name
    char message[80];       // event description
};

class EventLogger {
public:
    EventLogger();

    void begin(StorageManager& storage);
    void loop();

    void log(uint8_t level, const char* source, const String& message);
    void logInfo(const char* source, const String& message);
    void logWarning(const char* source, const String& message);
    void logError(const char* source, const String& message);
    void logCritical(const char* source, const String& message);

    uint16_t getCount();
    void clear();
    String toJson(int limit = 50);
    String toCSV();
    void toJsonArray(JsonArray& arr, int limit = 50);
    void persistNow();

private:
    StorageManager* _storage;
    LogEntry _entries[MAX_LOG_ENTRIES];
    uint16_t _head;
    uint16_t _count;
    bool _dirty;
    unsigned long _lastPersist;
    unsigned long _lastAutoClean;

    uint32_t getTimestamp();
    void autoClean();
    void loadFromStorage();
    static const char* levelToString(uint8_t level);
};

#endif // EVENT_LOGGER_H
