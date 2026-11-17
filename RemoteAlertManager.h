/*
 * ============================================================================
 * RemoteAlertManager.h — Optional Away-from-Home Push Alert Dispatcher
 * (Supports HTTPS/HTTP webhooks & ntfy.sh on ESP32; HTTP LAN webhooks on ESP8266)
 * ============================================================================
 */

#ifndef REMOTE_ALERT_MANAGER_H
#define REMOTE_ALERT_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#if defined(ESP32)
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#endif
#include "StorageManager.h"
#include "EventLogger.h"

class RemoteAlertManager {
public:
    RemoteAlertManager();

    void begin(StorageManager& storage, EventLogger& logger);
    void loop();

    bool isEnabled() const;
    String getUrl() const;
    bool hasToken() const;
    static bool isHttpsSupported();

    static bool validateUrl(const String& url, bool enabled, String& outError);

    void applyConfig(bool enabled, const String& url, bool hasToken, const String& token, bool clearToken);
    void toConfigJson(JsonObject& obj) const;

    void notifyAlarm(const String& deviceName, const String& mac,
                     const char* alarmType, const String& detailMsg);
    bool sendTestAlert(const String& deviceName, const String& mac, String& outError);
    void finishDispatch();

private:
    StorageManager* _storage;
    EventLogger* _logger;

    bool _enabled;
    String _url;
    String _token;

    volatile bool _inFlight;
    unsigned long _lastGasSentMs;
    unsigned long _lastTempSentMs;
    unsigned long _lastFaultSentMs;
    void* _pendingEsp8266Job;
#if defined(ESP32)
    mutable SemaphoreHandle_t _alertMutex;
    void ensureMutex() const;
#endif

    void loadConfig();
    bool dispatch(const String& deviceName, const String& mac,
                  const String& alarmType, const String& title,
                  const String& message, bool isTest, String& outError);
};

#endif // REMOTE_ALERT_MANAGER_H
