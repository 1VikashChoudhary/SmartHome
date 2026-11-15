/*
 * ============================================================================
 * WifiManager.h — Non-blocking WiFi Manager with Captive Portal
 * ============================================================================
 */

#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>
#if defined(ESP8266)
#include <ESP8266WiFi.h>
#include <ESP8266mDNS.h>
#else
#include <WiFi.h>
#include <ESPmDNS.h>
#endif
#include <DNSServer.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

// WiFi connection states
enum WifiState : uint8_t {
    WIFI_ST_DISCONNECTED = 0,
    WIFI_ST_CONNECTING   = 1,
    WIFI_ST_CONNECTED    = 2,
    WIFI_ST_AP_MODE      = 3
};

class WifiManager {
public:
    WifiManager();

    void begin(StorageManager& storage);
    void loop();

    // --- Status ---
    bool isConnected();
    bool isAPMode();
    WifiState getState();
    String getStateString();
    String getIP();
    String getSSID();
    String getHostname();
    String getMAC();
    String getDeviceId();
    String getAPSSID();
    String getAPPassword();
    int getRSSI();
    int getSignalPercent();
    unsigned long getLastConnectTime();

    // --- Control ---
    void startAP();
    void saveCredentials(const String& ssid, const String& pass);
    void resetWiFi();

    // --- Callback ---
    void setConnectCallback(void (*cb)(bool connected));

private:
    StorageManager* _storage;
    WifiState _state;
    String _hostname;
    String _apSSID;
    String _apPassword;  // Per-device MAC-derived AP password

    // Saved networks
    struct NetworkCredential {
        String ssid;
        String pass;
        uint8_t bssid[6];
        int32_t channel;
        bool hasBssid;
    };
    NetworkCredential _networks[WIFI_MAX_SAVED_NETWORKS];
    uint8_t _networkCount;
    uint8_t _currentNetwork;

    // Timing
    unsigned long _lastConnectAttempt;
    unsigned long _lastConnectTime;
    unsigned long _connectStartTime;
    unsigned long _disconnectDetectedAt;
    unsigned long _lastApStaRetry;
    uint8_t _failCount;
    bool _usingPinnedBssid;
    bool _skipPinnedBssid;

    // Captive portal DNS
    DNSServer _dnsServer;
    bool _dnsStarted;

    // Callback
    void (*_connectCallback)(bool);
    bool _wasConnected;

    // Internal
    void loadCredentials();
    void tryConnect();
    void saveBssidChannel();
    void setupMDNS();
    String generateAPSSID();
    String generateAPPassword();
#if defined(ESP32)
    void onWiFiEvent(WiFiEvent_t event);
    static void staticWiFiEvent(WiFiEvent_t event);
#endif
    static WifiManager* _instance;
};

#endif // WIFI_MANAGER_H
