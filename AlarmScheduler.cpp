/*
 * ============================================================================
 * AlarmScheduler.cpp — Cron-like Alarm Scheduler Implementation
 * ============================================================================
 */

#include "AlarmScheduler.h"

AlarmScheduler::AlarmScheduler()
    : _storage(nullptr), _alarmCount(0), _lastCheck(0),
      _lastFiredMinuteKey(-1), _actionCallback(nullptr) {
    memset(_alarms, 0, sizeof(_alarms));
    memset(_delayArmedMillis, 0, sizeof(_delayArmedMillis));
}

void AlarmScheduler::begin(StorageManager& storage) {
    _storage = &storage;
    loadAlarms();
    _lastCheck = millis();
    Serial.printf("[Alarm] Initialized with %d alarm(s)\n", _alarmCount);
}

void AlarmScheduler::loop() {
    unsigned long now = millis();
    if (now - _lastCheck < ALARM_CHECK_INTERVAL) return;
    _lastCheck = now;

    uint32_t epochNow = getCurrentEpoch();
    struct tm timeInfo;
    bool hasLocalTime = getLocalTime(&timeInfo, 0);

    int hour = hasLocalTime ? timeInfo.tm_hour : -1;
    int minute = hasLocalTime ? timeInfo.tm_min : -1;
    int dow = hasLocalTime ? timeInfo.tm_wday : -1; // 0=Sun

    int32_t currentMinuteKey = -1;
    if (epochNow > 0) {
        currentMinuteKey = (int32_t)(epochNow / 60);
    } else if (hasLocalTime) {
        currentMinuteKey = (int32_t)((timeInfo.tm_yday * 1440) + (hour * 60) + minute);
    }

    // Prevent double-fire of clock alarms within the exact same minute
    bool skipClockChecks = (currentMinuteKey >= 0 && currentMinuteKey == _lastFiredMinuteKey);

    bool fired = false;
    bool changed = false;
    for (uint8_t i = 0; i < _alarmCount; i++) {
        ScheduledAlarm& a = _alarms[i];
        if (!a.enabled) {
            _delayArmedMillis[i] = 0;
            continue;
        }
        if (a.mode == SCHEDULE_DELAY) {
            if (a.fired || a.delayMinutes == 0) continue;
            if (epochNow != 0) {
                if (a.createdAt == 0) {
                    if (_delayArmedMillis[i] > 0) {
                        // Migrate offline timer to epoch
                        a.createdAt = epochNow - (now - _delayArmedMillis[i]) / 1000;
                        _delayArmedMillis[i] = 0;
                        changed = true;
                    } else {
                        armDelayAlarm(a, true);
                        changed = true;
                        continue;
                    }
                }
                if (epochNow < a.createdAt + (a.delayMinutes * 60UL)) continue;
            } else {
                // Offline fallback using millis()
                if (_delayArmedMillis[i] == 0) {
                    _delayArmedMillis[i] = now;
                }
                if (now - _delayArmedMillis[i] < (unsigned long)a.delayMinutes * 60000UL) continue;
            }
        } else {
            if (!hasLocalTime || skipClockChecks) continue;
            if (a.type == ALARM_ONCE && a.fired) continue;
            if (!shouldFire(a, hour, minute, dow)) continue;
        }

            Serial.printf("[Alarm] Firing alarm %d: action=%d relay=%d\n",
                          a.id, a.action, a.targetRelay);

        if (_actionCallback) {
            _actionCallback(a.action, a.targetRelay);
        }

        if (a.mode == SCHEDULE_DELAY || a.type == ALARM_ONCE) {
            a.fired = true;
            a.enabled = false;
            _delayArmedMillis[i] = 0;
            changed = true;
        }

        fired = true;
        if (a.mode != SCHEDULE_DELAY && currentMinuteKey >= 0) {
            _lastFiredMinuteKey = currentMinuteKey;
        }
    }

    if (fired) {
        changed = true;
    }

    if (changed) {
        save(); // Persist fired state / delay arming
    }
}

bool AlarmScheduler::addAlarm(const ScheduledAlarm& alarm) {
    if (_alarmCount >= MAX_ALARMS) return false;

    _alarms[_alarmCount] = alarm;
    _delayArmedMillis[_alarmCount] = 0;
    if (_alarms[_alarmCount].id == 0) {
        _alarms[_alarmCount].id = getNextId();
    }
    if (_alarms[_alarmCount].mode == SCHEDULE_DELAY && _alarms[_alarmCount].enabled) {
        armDelayAlarm(_alarms[_alarmCount], _alarms[_alarmCount].createdAt == 0);
    }
    _alarmCount++;
    save();
    return true;
}

bool AlarmScheduler::updateAlarm(uint8_t id, const ScheduledAlarm& alarm) {
    int idx = findAlarmIndex(id);
    if (idx < 0) return false;

    _alarms[idx] = alarm;
    _alarms[idx].id = id; // Preserve ID
    _delayArmedMillis[idx] = 0; // Reset runtime timer on update
    if (_alarms[idx].mode == SCHEDULE_DELAY && _alarms[idx].enabled) {
        armDelayAlarm(_alarms[idx], true);
    }
    save();
    return true;
}

bool AlarmScheduler::deleteAlarm(uint8_t id) {
    int idx = findAlarmIndex(id);
    if (idx < 0) return false;

    // Shift remaining alarms down
    for (int i = idx; i < _alarmCount - 1; i++) {
        _alarms[i] = _alarms[i + 1];
        _delayArmedMillis[i] = _delayArmedMillis[i + 1];
    }
    _alarmCount--;
    memset(&_alarms[_alarmCount], 0, sizeof(ScheduledAlarm));
    _delayArmedMillis[_alarmCount] = 0;
    save();
    return true;
}

bool AlarmScheduler::enableAlarm(uint8_t id, bool enabled) {
    int idx = findAlarmIndex(id);
    if (idx < 0) return false;

    _alarms[idx].enabled = enabled;
    if (enabled) {
        if (_alarms[idx].mode == SCHEDULE_DELAY) {
            _alarms[idx].fired = false;
            _delayArmedMillis[idx] = 0;
            armDelayAlarm(_alarms[idx], true);
        } else if (_alarms[idx].type == ALARM_ONCE) {
            _alarms[idx].fired = false; // Re-arm one-time alarm
        }
    } else {
        _delayArmedMillis[idx] = 0;
    }
    save();
    return true;
}

const ScheduledAlarm* AlarmScheduler::getAlarm(uint8_t id) {
    int idx = findAlarmIndex(id);
    if (idx < 0) return nullptr;
    return &_alarms[idx];
}

uint8_t AlarmScheduler::getAlarmCount() { return _alarmCount; }

uint8_t AlarmScheduler::getNextId() {
    uint8_t maxId = 0;
    for (uint8_t i = 0; i < _alarmCount; i++) {
        if (_alarms[i].id > maxId) maxId = _alarms[i].id;
    }
    return maxId + 1;
}

void AlarmScheduler::save() {
    if (!_storage) return;

    JsonDocument doc;
    JsonArray arr = doc["alarms"].to<JsonArray>();
    toJson(arr);
    _storage->saveJson(PATH_ALARMS, doc);
}

void AlarmScheduler::setActionCallback(void (*cb)(AlarmAction, uint8_t)) {
    _actionCallback = cb;
}

void AlarmScheduler::toJson(JsonArray& arr) {
    for (uint8_t i = 0; i < _alarmCount; i++) {
        const ScheduledAlarm& a = _alarms[i];
        JsonObject obj = arr.add<JsonObject>();
        obj["id"]     = a.id;
        obj["en"]     = a.enabled;
        obj["mode"]   = (uint8_t)a.mode;
        obj["type"]   = (uint8_t)a.type;
        obj["hour"]   = a.hour;
        obj["min"]    = a.minute;
        obj["dow"]    = a.dayOfWeek;
        obj["delay"]  = a.delayMinutes;
        obj["created"] = a.createdAt;
        obj["action"] = (uint8_t)a.action;
        obj["relay"]  = a.targetRelay;
        obj["fired"]  = a.fired;
    }
}

bool AlarmScheduler::fromJson(const JsonObject& obj, ScheduledAlarm& alarm) {
    alarm.id          = obj["id"] | 0;
    alarm.enabled     = obj["en"] | true;
    alarm.mode        = (ScheduleMode)(uint8_t)(obj["mode"] | 0);
    alarm.type        = (AlarmType)(uint8_t)(obj["type"] | 0);
    alarm.hour        = obj["hour"] | 0;
    alarm.minute      = obj["min"] | 0;
    alarm.dayOfWeek   = obj["dow"] | 0;
    alarm.delayMinutes = obj["delay"] | 0;
    alarm.createdAt   = obj["created"] | 0;
    alarm.action      = (AlarmAction)(uint8_t)(obj["action"] | 0);
    alarm.targetRelay = obj["relay"] | 0;
    alarm.fired       = obj["fired"] | false;

    // Validate
    if (alarm.mode > SCHEDULE_DELAY) return false;
    if (alarm.mode == SCHEDULE_CLOCK && (alarm.hour > 23 || alarm.minute > 59)) return false;
    if (alarm.mode == SCHEDULE_DELAY && alarm.delayMinutes == 0) return false;
    if (alarm.type > ALARM_WEEKEND) return false;
    if (alarm.action > ACTION_ALL_OFF) return false;
    if (alarm.targetRelay >= MAX_RELAYS && alarm.targetRelay != 0xFF) return false;
    return true;
}

// ============================================================================
// Private
// ============================================================================

void AlarmScheduler::loadAlarms() {
    _alarmCount = 0;
    if (!_storage) return;

    JsonDocument doc;
    if (!_storage->loadJson(PATH_ALARMS, doc)) return;

    JsonArray arr = doc["alarms"].as<JsonArray>();
    for (JsonObject obj : arr) {
        if (_alarmCount >= MAX_ALARMS) break;
        if (fromJson(obj, _alarms[_alarmCount])) {
            _alarmCount++;
        }
    }
}

bool AlarmScheduler::shouldFire(const ScheduledAlarm& alarm, int hour, int minute, int dow) {
    if (alarm.hour != hour || alarm.minute != minute) return false;

    switch (alarm.type) {
        case ALARM_ONCE:
        case ALARM_DAILY:
            return true;

        case ALARM_WEEKLY:
            return dow == alarm.dayOfWeek;

        case ALARM_WEEKDAY:
            return (dow >= 1 && dow <= 5); // Mon-Fri

        case ALARM_WEEKEND:
            return (dow == 0 || dow == 6); // Sun or Sat

        default:
            return false;
    }
}

uint32_t AlarmScheduler::getCurrentEpoch() {
    time_t now;
    time(&now);
    return (now >= 1600000000) ? (uint32_t)now : 0;
}

void AlarmScheduler::armDelayAlarm(ScheduledAlarm& alarm, bool resetStart) {
    if (alarm.mode != SCHEDULE_DELAY) return;
    if (!resetStart && alarm.createdAt != 0) return;

    uint32_t now = getCurrentEpoch();
    if (now != 0) {
        alarm.createdAt = now;
    }
}

int AlarmScheduler::findAlarmIndex(uint8_t id) {
    for (uint8_t i = 0; i < _alarmCount; i++) {
        if (_alarms[i].id == id) return i;
    }
    return -1;
}
