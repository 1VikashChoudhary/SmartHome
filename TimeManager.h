/*
 * ============================================================================
 * TimeManager.h — NTP Time Synchronization + Optional DS3231 RTC
 * ============================================================================
 */

#ifndef TIME_MANAGER_H
#define TIME_MANAGER_H

#include <Arduino.h>
#include <time.h>
#include <ArduinoJson.h>
#if defined(ESP32)
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#endif
#include "Config.h"
#include "StorageManager.h"

#ifdef ENABLE_DS3231
#include <RTClib.h>
#endif

class TimeManager {
public:
    TimeManager();

    void begin(StorageManager& storage);
    void loop();

    bool isTimeSet();
    String getFormattedTime();
    String getFormattedDate();
    String getFormattedDateTime();
    String getDayOfWeek();
    int getDayOfWeekNum();   // 0=Sun, 6=Sat
    int getHour();
    int getMinute();
    int getSecond();
    time_t getEpoch();

    void setTimezone(const String& tz);
    void setUse24h(bool use24h);
    bool getUse24h();
    String getTimezone();
    unsigned long getLastSyncTime();
    void forceSync();

private:
    StorageManager* _storage;
    String _timezone;
    bool _use24h;
    bool _timeSet;
    unsigned long _lastSyncTime;
    unsigned long _lastSyncCheck;
    struct tm _timeInfo;
#if defined(ESP32)
    SemaphoreHandle_t _timeMutex;
#endif

    void configureNTP();
    bool updateTimeInfo();
    bool getLocalTimeCopy(struct tm& out);

#ifdef ENABLE_DS3231
    RTC_DS3231 _rtc;
    bool _rtcAvailable;
    void syncRTCFromNTP();
    void loadTimeFromRTC();
#endif
};

#endif // TIME_MANAGER_H
