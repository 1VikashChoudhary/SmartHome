/*
 * ============================================================================
 * WebServerManager.h — AsyncWebServer with REST API
 * ============================================================================
 */

#ifndef WEB_SERVER_MANAGER_H
#define WEB_SERVER_MANAGER_H

#include <Arduino.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"
#include "WifiManager.h"
#include "RelayManager.h"
#include "SensorManager.h"
#include "BuzzerManager.h"
#include "MqttManager.h"
#include "TimeManager.h"
#include "LCDManager.h"
#include "AlarmScheduler.h"
#include "RuleManager.h"
#include "EventLogger.h"
#include "Diagnostics.h"
#include "OTAManager.h"
#include "WebSocketManager.h"
#include "HardwareManager.h"
#include "WebPages.h"

enum AuthRole {
    AUTH_ROLE_NONE  = 0,
    AUTH_ROLE_GUEST = 1,
    AUTH_ROLE_ADMIN = 2
};

class WebServerManager {
public:
    WebServerManager();

    void begin(StorageManager& storage, WifiManager& wifi, RelayManager& relay,
               SensorManager& sensor, BuzzerManager& buzzer, MqttManager& mqtt,
               TimeManager& timeMgr, LCDManager& lcd, AlarmScheduler& alarm,
               RuleManager& rules, EventLogger& logger, Diagnostics& diag, OTAManager& ota);

    void begin(StorageManager& storage, WifiManager& wifi, RelayManager& relay,
               SensorManager& sensor, BuzzerManager& buzzer, MqttManager& mqtt,
               TimeManager& timeMgr, LCDManager& lcd, AlarmScheduler& alarm,
               RuleManager& rules, EventLogger& logger, Diagnostics& diag, OTAManager& ota,
               HardwareManager& hw);

    void setWebSocketManager(WebSocketManager& ws) { _ws = &ws; }
    AsyncWebServer& getServer();

    // Authentication helpers (Multi-User Privilege Tiers: Admin vs. Family / Guest)
    bool isAuthEnabled() const;
    bool isGuestAuthEnabled() const { return _guestAuthEnabled; }
    const String& getGuestUsername() const { return _guestUsername; }
    bool hasGuestPassword() const { return (_guestPasswordHash.length() > 0 || _guestPassword.length() > 0); }
    bool verifyCredentials(const String& user, const String& pass) const;
    bool verifyWsToken(const String& token) const;
    const String& getWsToken() const { return _wsToken; }
    const String& getDeviceName() const { return _deviceName; }
    AuthRole getRequestRole(AsyncWebServerRequest* req);
    bool isAuthorized(AsyncWebServerRequest* req, AuthRole requiredRole = AUTH_ROLE_GUEST);

    // Safe reboot interface
    bool isRebootRequested() const { return _rebootRequested; }
    unsigned long getRebootRequestTime() const { return _rebootRequestTime; }
    unsigned long getRebootDelay() const { return _rebootDelay; }
    void requestReboot(unsigned long delayMs = 1000);

private:
    AsyncWebServer _server;

    // Module references
    StorageManager* _storage;
    WifiManager* _wifi;
    RelayManager* _relay;
    SensorManager* _sensor;
    BuzzerManager* _buzzer;
    MqttManager* _mqtt;
    TimeManager* _time;
    LCDManager* _lcd;
    AlarmScheduler* _alarm;
    RuleManager* _rules;
    EventLogger* _logger;
    Diagnostics* _diag;
    OTAManager* _ota;
    WebSocketManager* _ws;
    HardwareManager* _hw;

    // Reboot state
    volatile bool _rebootRequested;
    unsigned long _rebootRequestTime;
    unsigned long _rebootDelay;

    // Device identity cache (in RAM to eliminate SPI flash wear during 1Hz polling)
    String _deviceName;

    // Authentication Settings (Multi-User Privilege Tiers: Admin vs. Family / Guest)
    bool _webAuthEnabled;
    String _webUsername;
    String _webPassword;
    String _webPasswordHash;

    bool _guestAuthEnabled;
    String _guestUsername;
    String _guestPassword;
    String _guestPasswordHash;

    String _wsToken;
    void regenerateWsToken();
    AuthRole authenticateRequest(AsyncWebServerRequest* req);

    // Rate Limiting & Security Hardening
    struct RateLimitEntry {
        IPAddress ip;
        uint8_t failedCount;
        unsigned long lockoutUntil;
        unsigned long lastAttempt;
    };
    static const int RATE_LIMIT_CACHE_SIZE = 8;
    RateLimitEntry _rateLimits[RATE_LIMIT_CACHE_SIZE];

    bool isRateLimited(const IPAddress& ip);
    void recordFailedAttempt(const IPAddress& ip);
    void resetRateLimit(const IPAddress& ip);
    static bool constantTimeCompare(const String& a, const String& b);
    static String sha256Hex(const String& input);
    static String md5Hex(const String& input);

    // Route setup
    void setupPageRoutes();
    void setupAPIRoutes();
    void setupCaptivePortal();

    // Response helpers
    void sendJson(AsyncWebServerRequest* req, int code, const JsonDocument& doc);
    void sendOk(AsyncWebServerRequest* req, const String& message = "OK");
    void sendError(AsyncWebServerRequest* req, int code, const String& message);

    // Request body helpers
    bool collectJsonBody(AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total, JsonDocument& doc);
    void cleanTempObject(AsyncWebServerRequest* req);
};

#endif // WEB_SERVER_MANAGER_H
