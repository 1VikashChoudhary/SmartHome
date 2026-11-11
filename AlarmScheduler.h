/*
 * ============================================================================
 * AlarmScheduler.h — Cron-like Alarm Scheduler
 * ============================================================================
 */

#ifndef ALARM_SCHEDULER_H
#define ALARM_SCHEDULER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <time.h>
#include "Config.h"
#include "StorageManager.h"

enum AlarmType : uint8_t {
    ALARM_ONCE    = 0,
    ALARM_DAILY   = 1,
    ALARM_WEEKLY  = 2,
    ALARM_WEEKDAY = 3,  // Mon-Fri
    ALARM_WEEKEND = 4   // Sat-Sun
};

enum ScheduleMode : uint8_t {
    SCHEDULE_CLOCK = 0,
    SCHEDULE_DELAY = 1
};

enum AlarmAction : uint8_t {
    ACTION_RELAY_ON     = 0,
    ACTION_RELAY_OFF    = 1,
    ACTION_RELAY_TOGGLE = 2,
    ACTION_BUZZER       = 3,
    ACTION_ALL_ON       = 4,
    ACTION_ALL_OFF      = 5
};

struct ScheduledAlarm {
    uint8_t id;
    bool enabled;
    ScheduleMode mode;
    AlarmType type;
    uint8_t hour;           // 0-23
    uint8_t minute;         // 0-59
    uint8_t dayOfWeek;      // 0=Sun, for WEEKLY type
    uint32_t delayMinutes;  // For delay mode
    uint32_t createdAt;     // Epoch seconds when delay timer was armed
    AlarmAction action;
    uint8_t targetRelay;    // 0-4 for single, 0xFF for all
    bool fired;             // For ONCE type
};

class AlarmScheduler {
public:
    AlarmScheduler();

    void begin(StorageManager& storage);
    void loop();

    bool addAlarm(const ScheduledAlarm& alarm);
    bool updateAlarm(uint8_t id, const ScheduledAlarm& alarm);
    bool deleteAlarm(uint8_t id);
    bool enableAlarm(uint8_t id, bool enabled);
    const ScheduledAlarm* getAlarm(uint8_t id);
    uint8_t getAlarmCount();
    uint8_t getNextId();

    void save();
    void setActionCallback(void (*cb)(AlarmAction action, uint8_t relay));
    void toJson(JsonArray& arr);
    bool fromJson(const JsonObject& obj, ScheduledAlarm& alarm);

private:
    StorageManager* _storage;
    ScheduledAlarm _alarms[MAX_ALARMS];
    uint8_t _alarmCount;

    unsigned long _lastCheck;
    int32_t _lastFiredMinuteKey;  // Unique minute key (epoch/60 or yearDay*1440 + hour*60 + min)
    unsigned long _delayArmedMillis[MAX_ALARMS];

    void (*_actionCallback)(AlarmAction, uint8_t);

    void loadAlarms();
    bool shouldFire(const ScheduledAlarm& alarm, int hour, int minute, int dow);
    uint32_t getCurrentEpoch();
    void armDelayAlarm(ScheduledAlarm& alarm, bool resetStart);
    int findAlarmIndex(uint8_t id);
};

#endif // ALARM_SCHEDULER_H
