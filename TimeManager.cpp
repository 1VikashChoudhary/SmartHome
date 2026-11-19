/*
 * ============================================================================
 * TimeManager.cpp — NTP Time Synchronization Implementation
 * ============================================================================
 */

#include "TimeManager.h"

#if defined(ESP32)
namespace {
struct TimeLockGuard {
    SemaphoreHandle_t m;
    explicit TimeLockGuard(SemaphoreHandle_t mtx) : m(mtx) {
        if (m) xSemaphoreTakeRecursive(m, portMAX_DELAY);
    }
    ~TimeLockGuard() {
        if (m) xSemaphoreGiveRecursive(m);
    }
};
}
#define TIME_LOCK() TimeLockGuard _timeGuard(_timeMutex)
#else
#define TIME_LOCK() ((void)0)
#endif

TimeManager::TimeManager()
    : _storage(nullptr), _timezone(DEFAULT_TIMEZONE), _use24h(DEFAULT_24H_FORMAT),
      _timeSet(false), _lastSyncTime(0), _lastSyncCheck(0)
#if defined(ESP32)
      , _timeMutex(nullptr)
#endif
{
    memset(&_timeInfo, 0, sizeof(_timeInfo));
#if defined(ESP32)
    _timeMutex = xSemaphoreCreateRecursiveMutex();
#endif
#ifdef ENABLE_DS3231
    _rtcAvailable = false;
#endif
}

void TimeManager::begin(StorageManager& storage) {
    _storage = &storage;

    // Load settings from config
    JsonDocument doc;
    if (_storage->loadJson(PATH_CONFIG, doc)) {
        TIME_LOCK();
        _timezone = doc["timezone"] | DEFAULT_TIMEZONE;
        _use24h = doc["use_24h"] | DEFAULT_24H_FORMAT;
    }

    // Apply timezone BEFORE reading DS3231 RTC so mktime() interprets local RTC time accurately
    configureNTP();

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

    SERIAL_PRINTF("[Time] Timezone: %s, 24h: %s\n", getTimezone().c_str(), _use24h ? "yes" : "no");
}

void TimeManager::loop() {
    unsigned long now = millis();

    // Periodic NTP sync check
    if (now - _lastSyncCheck >= 10000) { // Check every 10 seconds
        _lastSyncCheck = now;

        struct tm ti;
        if (getLocalTimeCopy(ti)) {
            bool newlySynced = false;
            {
                TIME_LOCK();
                if (!_timeSet && ti.tm_year > (2020 - 1900)) {
                    _timeSet = true;
                    _lastSyncTime = now;
                    newlySynced = true;
                }
            }
            if (newlySynced) {
                SERIAL_PRINTF("[Time] NTP synced: %s\n", getFormattedDateTime().c_str());

#ifdef ENABLE_DS3231
                if (_rtcAvailable) syncRTCFromNTP();
#endif
            }
        }
    }

    // Force resync every NTP_SYNC_INTERVAL
    bool needResync = false;
    {
        TIME_LOCK();
        needResync = _timeSet && (now - _lastSyncTime >= NTP_SYNC_INTERVAL);
        if (needResync) _lastSyncTime = now;
    }
    if (needResync) {
        Serial.println(F("[Time] Periodic NTP resync"));
        configureNTP();
    }
}

bool TimeManager::isTimeSet() { TIME_LOCK(); return _timeSet; }

String TimeManager::getFormattedTime() {
    struct tm ti;
    if (!getLocalTimeCopy(ti)) return F("--:--:--");

    const uint8_t hr = (uint8_t)constrain(ti.tm_hour, 0, 23);
    const uint8_t mn = (uint8_t)constrain(ti.tm_min, 0, 59);
    const uint8_t sc = (uint8_t)constrain(ti.tm_sec, 0, 59);
    bool use24h = getUse24h();

    char buf[24];
    if (use24h) {
        snprintf(buf, sizeof(buf), "%02u:%02u:%02u", hr, mn, sc);
    } else {
        const char* ampm = (hr >= 12) ? "PM" : "AM";
        uint8_t h12 = hr % 12;
        if (h12 == 0) h12 = 12;
        snprintf(buf, sizeof(buf), "%u:%02u:%02u %s", h12, mn, sc, ampm);
    }
    return String(buf);
}

String TimeManager::getFormattedDate() {
    struct tm ti;
    if (!getLocalTimeCopy(ti)) return F("-- --- ----");

    static const char* months[] = {
        "Jan","Feb","Mar","Apr","May","Jun",
        "Jul","Aug","Sep","Oct","Nov","Dec"
    };

    const uint8_t d = (uint8_t)constrain(ti.tm_mday, 1, 31);
    const uint8_t m = (uint8_t)constrain(ti.tm_mon, 0, 11);
    const int yr = ti.tm_year + 1900;

    char buf[24];
    snprintf(buf, sizeof(buf), "%02u %s %04d", d, months[m], yr);
    return String(buf);
}

String TimeManager::getFormattedDateTime() {
    return getFormattedDate() + " " + getFormattedTime();
}

String TimeManager::getDayOfWeek() {
    struct tm ti;
    if (!getLocalTimeCopy(ti)) return F("---");
    static const char* days[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
    const uint8_t w = (uint8_t)constrain(ti.tm_wday, 0, 6);
    return String(days[w]);
}

int TimeManager::getDayOfWeekNum() {
    struct tm ti;
    return getLocalTimeCopy(ti) ? ti.tm_wday : 0; // 0=Sun
}

int TimeManager::getHour()   { struct tm ti; return getLocalTimeCopy(ti) ? ti.tm_hour : 0; }
int TimeManager::getMinute() { struct tm ti; return getLocalTimeCopy(ti) ? ti.tm_min : 0; }
int TimeManager::getSecond() { struct tm ti; return getLocalTimeCopy(ti) ? ti.tm_sec : 0; }

time_t TimeManager::getEpoch() {
    time_t now;
    time(&now);
    return now;
}

void TimeManager::setTimezone(const String& tz) {
    {
        TIME_LOCK();
        _timezone = tz;
    }
    configureNTP();

    // Save to config without wiping existing fields if loadJson fails
    if (_storage) {
        JsonDocument doc;
        if (_storage->loadJson(PATH_CONFIG, doc) || !_storage->fileExists(PATH_CONFIG)) {
            doc["timezone"] = tz;
            _storage->saveJson(PATH_CONFIG, doc);
        } else {
            Serial.println(F("[Time] Refusing to overwrite /config.json after loadJson failure"));
        }
    }
    SERIAL_PRINTF("[Time] Timezone changed to: %s\n", tz.c_str());
}

void TimeManager::setUse24h(bool use24h) {
    {
        TIME_LOCK();
        _use24h = use24h;
    }
    if (_storage) {
        JsonDocument doc;
        if (_storage->loadJson(PATH_CONFIG, doc) || !_storage->fileExists(PATH_CONFIG)) {
            doc["use_24h"] = use24h;
            _storage->saveJson(PATH_CONFIG, doc);
        } else {
            Serial.println(F("[Time] Refusing to overwrite /config.json after loadJson failure"));
        }
    }
}

bool TimeManager::getUse24h() { TIME_LOCK(); return _use24h; }
String TimeManager::getTimezone() { TIME_LOCK(); return _timezone; }
unsigned long TimeManager::getLastSyncTime() { TIME_LOCK(); return _lastSyncTime; }

void TimeManager::forceSync() {
    configureNTP();
    {
        TIME_LOCK();
        _lastSyncTime = millis();
    }
    Serial.println(F("[Time] Forced NTP sync"));
}

// ============================================================================
// Private Methods
// ============================================================================

void TimeManager::configureNTP() {
    String tzCopy = getTimezone();
    configTzTime(tzCopy.c_str(), NTP_SERVER_1, NTP_SERVER_2);
}

bool TimeManager::updateTimeInfo() {
    TIME_LOCK();
    return getLocalTime(&_timeInfo, 0); // 0 = non-blocking (don't wait)
}

bool TimeManager::getLocalTimeCopy(struct tm& out) {
    TIME_LOCK();
    return getLocalTime(&out, 0);
}

#ifdef ENABLE_DS3231
void TimeManager::syncRTCFromNTP() {
    if (!_timeSet || !_rtcAvailable) return;

    time_t now = getEpoch();
    struct tm* t = localtime(&now);
    if (!t) return;
    _rtc.adjust(DateTime(t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
                          t->tm_hour, t->tm_min, t->tm_sec));
    Serial.println(F("[Time] RTC synced from NTP"));
}

void TimeManager::loadTimeFromRTC() {
    if (!_rtcAvailable) return;

    DateTime rtcTime = _rtc.now();
    struct timeval tv;
    struct tm t = {};
    t.tm_year = rtcTime.year() - 1900;
    t.tm_mon = rtcTime.month() - 1;
    t.tm_mday = rtcTime.day();
    t.tm_hour = rtcTime.hour();
    t.tm_min = rtcTime.minute();
    t.tm_sec = rtcTime.second();
    t.tm_isdst = -1;
    tv.tv_sec = mktime(&t);
    tv.tv_usec = 0;
    settimeofday(&tv, nullptr);

    _timeSet = true;
    SERIAL_PRINTF("[Time] Loaded from RTC: %s\n", getFormattedDateTime().c_str());
}
#endif
