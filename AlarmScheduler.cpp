/*
 * ============================================================================
 * AlarmScheduler.cpp — Cron-like Alarm Scheduler Implementation
 * ============================================================================
 */

#include "AlarmScheduler.h"
#include "RelayManager.h"

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
    SERIAL_PRINTF("[Alarm] Initialized with %d alarm(s)\n", _alarmCount);
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
                        // Migrate offline timer to epoch without unsigned underflow
                        unsigned long elapsedSec = (now - _delayArmedMillis[i]) / 1000UL;
                        a.createdAt = (epochNow > elapsedSec) ? (epochNow - (uint32_t)elapsedSec) : epochNow;
                        _delayArmedMillis[i] = 0;
                        changed = true;
                    } else {
                        armDelayAlarm(i, true);
                        changed = true;
                        continue;
                    }
                }
                if (epochNow < a.createdAt + (a.delayMinutes * 60UL)) continue;
            } else {
                // Offline fallback using millis()
                if (_delayArmedMillis[i] == 0) {
                    _delayArmedMillis[i] = (now == 0) ? 1 : now;
                }
                if (now - _delayArmedMillis[i] < (unsigned long)a.delayMinutes * 60000UL) continue;
            }
        } else {
            if (!hasLocalTime || skipClockChecks) continue;
            if (a.type == ALARM_ONCE && a.fired) continue;
            if (!shouldFire(a, hour, minute, dow)) continue;
        }

            SERIAL_PRINTF("[Alarm] Firing alarm %d: action=%d relay=%d\n",
                          a.id, a.action, a.targetRelay);

        // Disarm one-shot / delay alarms before triggering callbacks so
        // onRelayChange() and WebSocket broadcasts immediately reflect expiration.
        if (a.mode == SCHEDULE_DELAY || a.type == ALARM_ONCE) {
            a.fired = true;
            a.enabled = false;
            _delayArmedMillis[i] = 0;
            changed = true;
        }

        if (_actionCallback) {
            _actionCallback(a.action, a.targetRelay);
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

    uint8_t idx = _alarmCount;
    _alarms[idx] = alarm;
    _delayArmedMillis[idx] = 0;
    if (_alarms[idx].id == 0) {
        _alarms[idx].id = getNextId();
    }
    _alarmCount++;
    if (_alarms[idx].mode == SCHEDULE_DELAY && _alarms[idx].enabled) {
        armDelayAlarm(idx, _alarms[idx].createdAt == 0);
    }
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
        armDelayAlarm((uint8_t)idx, true);
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
            armDelayAlarm((uint8_t)idx, true);
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
    toJson(arr, false);
    _storage->saveJson(PATH_ALARMS, doc);
}

void AlarmScheduler::setActionCallback(void (*cb)(AlarmAction, uint8_t)) {
    _actionCallback = cb;
}

void AlarmScheduler::toJson(JsonArray& arr, bool includeRuntime) {
    uint32_t epochNow = 0;
    struct tm timeInfo;
    bool hasLocalTime = false;
    unsigned long nowMillis = 0;

    if (includeRuntime) {
        epochNow = getCurrentEpoch();
        hasLocalTime = getLocalTime(&timeInfo, 0);
        nowMillis = millis();
    }

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
        if (includeRuntime) {
            obj["rem_sec"] = computeAlarmRemainingSeconds(i, epochNow, hasLocalTime, timeInfo, nowMillis);
        }
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
    if (alarm.type == ALARM_WEEKLY && alarm.dayOfWeek > 6) return false;
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

bool AlarmScheduler::matchesDayOfWeek(AlarmType type, uint8_t alarmDow, int dow) {
    switch (type) {
        case ALARM_ONCE:
        case ALARM_DAILY:
            return true;

        case ALARM_WEEKLY:
            return dow == alarmDow;

        case ALARM_WEEKDAY:
            return (dow >= 1 && dow <= 5); // Mon-Fri

        case ALARM_WEEKEND:
            return (dow == 0 || dow == 6); // Sun or Sat

        default:
            return false;
    }
}

bool AlarmScheduler::shouldFire(const ScheduledAlarm& alarm, int hour, int minute, int dow) {
    if (alarm.hour != hour || alarm.minute != minute) return false;
    return matchesDayOfWeek(alarm.type, alarm.dayOfWeek, dow);
}

uint32_t AlarmScheduler::getCurrentEpoch() const {
    time_t now;
    time(&now);
    return (now >= 1600000000) ? (uint32_t)now : 0;
}

bool AlarmScheduler::targetsRelay(const ScheduledAlarm& alarm, uint8_t relayIndex) {
    switch (alarm.action) {
        case ACTION_RELAY_ON:
        case ACTION_RELAY_OFF:
        case ACTION_RELAY_TOGGLE:
            return (alarm.targetRelay == relayIndex || alarm.targetRelay == 0xFF);

        case ACTION_ALL_ON:
        case ACTION_ALL_OFF:
            return true;

        default:
            return false;
    }
}

uint32_t AlarmScheduler::computeAlarmRemainingSeconds(
    uint8_t index, uint32_t epochNow, bool hasLocalTime,
    const struct tm& timeInfo, unsigned long nowMillis) const {
    if (index >= _alarmCount) return 0;
    const ScheduledAlarm& a = _alarms[index];
    if (!a.enabled) return 0;

    if (a.mode == SCHEDULE_DELAY) {
        if (a.fired || a.delayMinutes == 0) return 0;
        uint32_t totalSec = a.delayMinutes * 60UL;

        if (epochNow != 0 && a.createdAt != 0) {
            uint32_t endEpoch = a.createdAt + totalSec;
            return (epochNow < endEpoch) ? (endEpoch - epochNow) : 0;
        }
        if (_delayArmedMillis[index] != 0) {
            unsigned long totalMs = (unsigned long)a.delayMinutes * 60000UL;
            unsigned long elapsedMs = nowMillis - _delayArmedMillis[index];
            if (elapsedMs >= totalMs) return 0;
            return (uint32_t)((totalMs - elapsedMs + 999UL) / 1000UL);
        }
        return totalSec;
    }

    // SCHEDULE_CLOCK
    if (a.type == ALARM_ONCE && a.fired) return 0;
    if (!hasLocalTime) return 0;

    int32_t nowSecOfDay = (int32_t)timeInfo.tm_hour * 3600L +
                          (int32_t)timeInfo.tm_min * 60L +
                          (int32_t)timeInfo.tm_sec;
    int32_t targetSecOfDay = (int32_t)a.hour * 3600L + (int32_t)a.minute * 60L;

    for (int d = 0; d <= 7; d++) {
        int candDow = (timeInfo.tm_wday + d) % 7;
        if (!matchesDayOfWeek(a.type, a.dayOfWeek, candDow)) continue;
        int32_t diff = (int32_t)d * 86400L + targetSecOfDay - nowSecOfDay;
        if (diff > 0) return (uint32_t)diff;
    }
    return 0;
}

uint32_t AlarmScheduler::getAlarmRemainingSeconds(uint8_t index) const {
    uint32_t epochNow = getCurrentEpoch();
    struct tm timeInfo;
    bool hasLocalTime = getLocalTime(&timeInfo, 0);
    return computeAlarmRemainingSeconds(index, epochNow, hasLocalTime, timeInfo, millis());
}

bool AlarmScheduler::getActiveTimerForRelay(uint8_t relayIndex, bool currentRelayState,
                                            bool& targetState, uint32_t& remainingSec) const {
    uint32_t epochNow = getCurrentEpoch();
    struct tm timeInfo;
    memset(&timeInfo, 0, sizeof(timeInfo));
    unsigned long nowMillis = millis();

    bool found = false;
    bool bestTarget = false;
    uint32_t bestRem = 0;

    for (uint8_t i = 0; i < _alarmCount; i++) {
        const ScheduledAlarm& a = _alarms[i];
        if (!a.enabled || a.fired || a.mode != SCHEDULE_DELAY || a.delayMinutes == 0) {
            continue;
        }
        if (!targetsRelay(a, relayIndex)) continue;

        uint32_t rem = computeAlarmRemainingSeconds(i, epochNow, false, timeInfo, nowMillis);
        if (rem == 0) continue;

        bool tgt;
        switch (a.action) {
            case ACTION_RELAY_ON:
            case ACTION_ALL_ON:
                tgt = true;
                break;
            case ACTION_RELAY_OFF:
            case ACTION_ALL_OFF:
                tgt = false;
                break;
            case ACTION_RELAY_TOGGLE:
                tgt = !currentRelayState;
                break;
            default:
                continue;
        }

        if (!found || rem < bestRem) {
            found = true;
            bestTarget = tgt;
            bestRem = rem;
        }
    }

    if (found) {
        targetState = bestTarget;
        remainingSec = bestRem;
    }
    return found;
}

bool AlarmScheduler::resolveEffectiveTimerForRelay(RelayManager& relay, uint8_t relayIndex,
                                                   bool& active, bool& targetState,
                                                   uint32_t& remainingSec) const {
    active = false;
    targetState = false;
    remainingSec = 0;

    if (relayIndex >= relay.getRelayCount() || !relay.isChannelEnabled(relayIndex)) {
        return false;
    }

    if (relay.hasActiveTimer(relayIndex)) {
        uint32_t quickRem = relay.getTimerRemaining(relayIndex);
        if (quickRem > 0) {
            active = true;
            targetState = relay.getTimerTargetState(relayIndex);
            remainingSec = quickRem;
        }
    }

    bool alarmTarget = false;
    uint32_t alarmRem = 0;
    if (getActiveTimerForRelay(relayIndex, relay.getState(relayIndex), alarmTarget, alarmRem)) {
        if (!active || alarmRem < remainingSec) {
            active = true;
            targetState = alarmTarget;
            remainingSec = alarmRem;
        }
    }

    return active;
}

void AlarmScheduler::applyTimersToRelayArray(JsonArray& relays, RelayManager& relay) const {
    uint8_t count = relays.size();
    for (uint8_t i = 0; i < count; i++) {
        bool active = false;
        bool target = false;
        uint32_t rem = 0;
        resolveEffectiveTimerForRelay(relay, i, active, target, rem);
        relays[i]["timer_active"] = active;
        relays[i]["timer_target"] = target;
        relays[i]["timer_remaining"] = rem;
    }
}

bool AlarmScheduler::cancelDelayTimersForRelay(uint8_t relayIndex) {
    bool changed = false;
    for (uint8_t i = 0; i < _alarmCount; i++) {
        ScheduledAlarm& a = _alarms[i];
        if (!a.enabled || a.fired || a.mode != SCHEDULE_DELAY) continue;
        if (!targetsRelay(a, relayIndex)) continue;
        a.enabled = false;
        _delayArmedMillis[i] = 0;
        changed = true;
    }
    if (changed) {
        save();
    }
    return changed;
}

void AlarmScheduler::armDelayAlarm(uint8_t index, bool resetStart) {
    if (index >= _alarmCount) return;
    ScheduledAlarm& alarm = _alarms[index];
    if (alarm.mode != SCHEDULE_DELAY) return;

    if (resetStart) {
        alarm.createdAt = 0;
        unsigned long nowMs = millis();
        _delayArmedMillis[index] = (nowMs == 0) ? 1 : nowMs;
    }

    if (!resetStart && alarm.createdAt != 0) return;

    uint32_t now = getCurrentEpoch();
    if (now != 0) {
        alarm.createdAt = now;
        _delayArmedMillis[index] = 0;
    } else if (_delayArmedMillis[index] == 0) {
        unsigned long nowMs = millis();
        _delayArmedMillis[index] = (nowMs == 0) ? 1 : nowMs;
    }
}

int AlarmScheduler::findAlarmIndex(uint8_t id) {
    for (uint8_t i = 0; i < _alarmCount; i++) {
        if (_alarms[i].id == id) return i;
    }
    return -1;
}
