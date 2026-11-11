/*
 * ============================================================================
 * TimeManager.cpp — NTP Time Synchronization Implementation
 * ============================================================================
 */

#include "TimeManager.h"

TimeManager::TimeManager()
    : _storage(nullptr), _timezone(DEFAULT_TIMEZONE), _use24h(DEFAULT_24H_FORMAT),
      _timeSet(false), _lastSyncTime(0), _lastSyncCheck(0) {
    memset(&_timeInfo, 0, sizeof(_timeInfo));
#ifdef ENABLE_DS3231
    _rtcAvailable = false;
#endif
}

void TimeManager::begin(StorageManager& storage) {
    _storage = &storage;

    // Load settings from config
    JsonDocument doc;
    if (_storage->loadJson(PATH_CONFIG, doc)) {
        _timezone = doc["timezone"] | DEFAULT_TIMEZONE;
        _use24h = doc["use_24h"] | DEFAULT_24H_FORMAT;
    }

#ifdef ENABLE_DS3231
    // Initialize DS3231 RTC
    if (_rtc.begin()) {
        _rtcAvailable = true;
        Serial.println(F("[Time] DS3231 RTC found"));
        if (_rtc.lostPower()) {
            Serial.println(F("[Time] RTC lost power, will sync from NTP"));
        } else {
            loadTimeFromRTC();
        }
    } else {
        Serial.println(F("[Time] DS3231 RTC not found"));
    }
#endif

    // Configure NTP
    configureNTP();
    Serial.printf("[Time] Timezone: %s, 24h: %s\n", _timezone.c_str(), _use24h ? "yes" : "no");
}

void TimeManager::loop() {
    unsigned long now = millis();

    // Periodic NTP sync check
    if (now - _lastSyncCheck >= 10000) { // Check every 10 seconds
        _lastSyncCheck = now;

        if (updateTimeInfo()) {
            if (!_timeSet && _timeInfo.tm_year > (2020 - 1900)) {
                _timeSet = true;
                _lastSyncTime = now;
                Serial.printf("[Time] NTP synced: %s\n", getFormattedDateTime().c_str());

#ifdef ENABLE_DS3231
                if (_rtcAvailable) syncRTCFromNTP();
#endif
            }
        }
    }

    // Force resync every NTP_SYNC_INTERVAL
    if (_timeSet && (now - _lastSyncTime >= NTP_SYNC_INTERVAL)) {
        Serial.println(F("[Time] Periodic NTP resync"));
        configureNTP();
        _lastSyncTime = now;
    }
}

bool TimeManager::isTimeSet() { return _timeSet; }

String TimeManager::getFormattedTime() {
    if (!updateTimeInfo()) return F("--:--:--");

    char buf[12];
    if (_use24h) {
        snprintf(buf, sizeof(buf), "%02d:%02d:%02d",
                 _timeInfo.tm_hour, _timeInfo.tm_min, _timeInfo.tm_sec);
    } else {
        int h = _timeInfo.tm_hour;
        const char* ampm = (h >= 12) ? "PM" : "AM";
        if (h > 12) h -= 12;
        if (h == 0) h = 12;
        snprintf(buf, sizeof(buf), "%d:%02d:%02d %s",
                 h, _timeInfo.tm_min, _timeInfo.tm_sec, ampm);
    }
    return String(buf);
}

String TimeManager::getFormattedDate() {
    if (!updateTimeInfo()) return F("-- --- ----");

    static const char* months[] = {
        "Jan","Feb","Mar","Apr","May","Jun",
        "Jul","Aug","Sep","Oct","Nov","Dec"
    };

    char buf[16];
    snprintf(buf, sizeof(buf), "%02d %s %04d",
             _timeInfo.tm_mday,
             months[_timeInfo.tm_mon],
             _timeInfo.tm_year + 1900);
    return String(buf);
}

String TimeManager::getFormattedDateTime() {
    return getFormattedDate() + " " + getFormattedTime();
}

String TimeManager::getDayOfWeek() {
    if (!updateTimeInfo()) return F("---");
    static const char* days[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
    return String(days[_timeInfo.tm_wday]);
}

int TimeManager::getDayOfWeekNum() {
    updateTimeInfo();
    return _timeInfo.tm_wday; // 0=Sun
}

int TimeManager::getHour()   { updateTimeInfo(); return _timeInfo.tm_hour; }
int TimeManager::getMinute() { updateTimeInfo(); return _timeInfo.tm_min; }
int TimeManager::getSecond() { updateTimeInfo(); return _timeInfo.tm_sec; }

time_t TimeManager::getEpoch() {
    time_t now;
    time(&now);
    return now;
}

void TimeManager::setTimezone(const String& tz) {
    _timezone = tz;
    configureNTP();

    // Save to config
    if (_storage) {
        JsonDocument doc;
        _storage->loadJson(PATH_CONFIG, doc);
        doc["timezone"] = _timezone;
        _storage->saveJson(PATH_CONFIG, doc);
    }
    Serial.printf("[Time] Timezone changed to: %s\n", _timezone.c_str());
}

void TimeManager::setUse24h(bool use24h) {
    _use24h = use24h;
    if (_storage) {
        JsonDocument doc;
        _storage->loadJson(PATH_CONFIG, doc);
        doc["use_24h"] = _use24h;
        _storage->saveJson(PATH_CONFIG, doc);
    }
}

bool TimeManager::getUse24h() { return _use24h; }
String TimeManager::getTimezone() { return _timezone; }
unsigned long TimeManager::getLastSyncTime() { return _lastSyncTime; }

void TimeManager::forceSync() {
    configureNTP();
    _lastSyncTime = millis();
    Serial.println(F("[Time] Forced NTP sync"));
}

// ============================================================================
// Private Methods
// ============================================================================

void TimeManager::configureNTP() {
    configTzTime(_timezone.c_str(), NTP_SERVER_1, NTP_SERVER_2);
}

bool TimeManager::updateTimeInfo() {
    return getLocalTime(&_timeInfo, 0); // 0 = non-blocking (don't wait)
}

#ifdef ENABLE_DS3231
void TimeManager::syncRTCFromNTP() {
    if (!_timeSet || !_rtcAvailable) return;

    time_t now = getEpoch();
    struct tm* t = localtime(&now);
    _rtc.adjust(DateTime(t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
                          t->tm_hour, t->tm_min, t->tm_sec));
    Serial.println(F("[Time] RTC synced from NTP"));
}

void TimeManager::loadTimeFromRTC() {
    if (!_rtcAvailable) return;

    DateTime rtcTime = _rtc.now();
    struct timeval tv;
    struct tm t;
    t.tm_year = rtcTime.year() - 1900;
    t.tm_mon = rtcTime.month() - 1;
    t.tm_mday = rtcTime.day();
    t.tm_hour = rtcTime.hour();
    t.tm_min = rtcTime.minute();
    t.tm_sec = rtcTime.second();
    tv.tv_sec = mktime(&t);
    tv.tv_usec = 0;
    settimeofday(&tv, nullptr);

    _timeSet = true;
    Serial.printf("[Time] Loaded from RTC: %s\n", getFormattedDateTime().c_str());
}
#endif
