/*
 * ============================================================================
 * WifiManager.cpp — Non-blocking WiFi Manager Implementation
 * ============================================================================
 */

#include "WifiManager.h"
#if defined(ESP32)
#include <esp_mac.h>
#endif

namespace {
// The WiFi driver can still be stopped during early boot, in which case
// WiFi.macAddress() reports 00:00:00:00:00:00. The factory STA MAC lives in
// eFuse on ESP32 and is available throughout boot.
void readFactoryStaMac(uint8_t mac[6]) {
#if defined(ESP32)
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK) {
        WiFi.macAddress(mac);
    }
#else
    WiFi.macAddress(mac);
#endif
}

void disableWifiSleep() {
#if defined(ESP8266)
    WiFi.setSleepMode(WIFI_NONE_SLEEP);
#else
    WiFi.setSleep(false);
#endif
}
}

// Static instance pointer for WiFi event callback
WifiManager* WifiManager::_instance = nullptr;

// ============================================================================
// Constructor
// ============================================================================
WifiManager::WifiManager()
    : _storage(nullptr), _state(WIFI_ST_DISCONNECTED),
      _networkCount(0), _currentNetwork(0),
      _lastConnectAttempt(0), _lastConnectTime(0), _connectStartTime(0),
      _disconnectDetectedAt(0), _lastApStaRetry(0),
      _failCount(0), _usingPinnedBssid(false), _skipPinnedBssid(false), _dnsStarted(false),
      _connectCallback(nullptr), _wasConnected(false) {
    for (uint8_t i = 0; i < WIFI_MAX_SAVED_NETWORKS; i++) {
        memset(_networks[i].bssid, 0, sizeof(_networks[i].bssid));
        _networks[i].channel = 0;
        _networks[i].hasBssid = false;
    }
    _instance = this;
}

// ============================================================================
// Initialize WiFi
// ============================================================================
void WifiManager::begin(StorageManager& storage) {
    _storage = &storage;
    WiFi.persistent(false);
    WiFi.setAutoReconnect(true);
    disableWifiSleep();

    // Load saved credentials before deriving AP mode password policy
    loadCredentials();

    // Generate AP SSID and password (Open on unconfigured fresh setup; WPA2 once configured)
    _apSSID = generateAPSSID();
    _apPassword = generateAPPassword();

    // Load hostname from config or default to unique smarthome-XXXX
    JsonDocument doc;
    String customHostname = "";
    if (_storage && _storage->loadJson(PATH_CONFIG, doc)) {
        customHostname = doc["hostname"] | "";
        customHostname.trim();
    }
    if (customHostname.length() > 0) {
        _hostname = customHostname;
    } else {
        uint8_t mac[6];
        readFactoryStaMac(mac);
        char suffix[5];
        snprintf(suffix, sizeof(suffix), "%02X%02X", mac[4], mac[5]);
        _hostname = String(WIFI_DEFAULT_HOSTNAME) + "-" + suffix;
    }

    // Set hostname before connecting
#if defined(ESP8266)
    WiFi.hostname(_hostname);
#else
    WiFi.setHostname(_hostname.c_str());
    // Register WiFi event handler
    WiFi.onEvent(staticWiFiEvent);
#endif

    // Attempt STA connection if we have credentials
    if (_networkCount > 0) {
        _state = WIFI_ST_CONNECTING;
        tryConnect();
    } else {
        // No saved credentials — start AP
        Serial.println(F("[WiFi] No saved credentials, starting AP mode"));
        startAP();
    }
}

// ============================================================================
// Non-blocking loop
// ============================================================================
void WifiManager::loop() {
    unsigned long now = millis();

    switch (_state) {
        case WIFI_ST_CONNECTING:
            // Check if connected
            if (WiFi.status() == WL_CONNECTED) {
                _state = WIFI_ST_CONNECTED;
                _lastConnectTime = now;
                _disconnectDetectedAt = 0;
                _usingPinnedBssid = false;
                _skipPinnedBssid = false;
                _failCount = 0;
                SERIAL_PRINTF("[WiFi] Connected to %s  IP: %s  RSSI: %d dBm\n",
                              WiFi.SSID().c_str(), WiFi.localIP().toString().c_str(), WiFi.RSSI());
                // Re-assert no-sleep after STA link-up so SDK defaults never miss AP-bridged ARPs.
                disableWifiSleep();

                // Cache BSSID and channel for fast reconnect
                saveBssidChannel();

                // Setup mDNS
                setupMDNS();

                // Stop DNS server if it was running
                if (_dnsStarted) {
                    _dnsServer.stop();
                    _dnsStarted = false;
                }

                // Notify callback
                if (_connectCallback && !_wasConnected) {
                    _connectCallback(true);
                }
                _wasConnected = true;
            }
            // Check timeout (fail fast out of pinned BSSID/channel without consuming AP fallback attempts)
            else if (now - _connectStartTime > (_usingPinnedBssid ? 6000UL : (unsigned long)WIFI_CONNECT_TIMEOUT)) {
                if (_usingPinnedBssid) {
                    _skipPinnedBssid = true;
                    Serial.println(F("[WiFi] Pinned BSSID/channel timed out, retrying full scan..."));
                    tryConnect();
                } else {
                    _failCount++;
                    SERIAL_PRINTF("[WiFi] Connection timeout (attempt %d/%d)\n",
                                  _failCount, WIFI_AP_FALLBACK_ATTEMPTS);

                    if (_failCount >= WIFI_AP_FALLBACK_ATTEMPTS) {
                        // Fallback to AP mode
                        Serial.println(F("[WiFi] Max attempts reached, falling back to AP mode"));
                        _lastApStaRetry = now;
                        startAP();
                    } else {
                        // Try next network or retry
                        _currentNetwork = (_currentNetwork + 1) % _networkCount;
                        _state = WIFI_ST_DISCONNECTED;
                        _lastConnectAttempt = now;
                    }
                }
            }
            break;

        case WIFI_ST_CONNECTED:
            // Keep ESP8266 mDNS responder servicing queries continuously
#if defined(ESP8266)
            MDNS.update();
#endif
            // Monitor connection — give native SDK autoReconnect a 3.5s grace window
            // so brief RF/beacon glitches recover without tearing down sockets.
            if (WiFi.status() != WL_CONNECTED) {
                if (_disconnectDetectedAt == 0) {
                    _disconnectDetectedAt = now;
                } else if (now - _disconnectDetectedAt >= 3500) {
                    Serial.println(F("[WiFi] Connection lost, reconnecting..."));
                    _state = WIFI_ST_DISCONNECTED;
                    _disconnectDetectedAt = 0;
                    _lastConnectAttempt = now - WIFI_RECONNECT_INTERVAL + 500; // Retry quickly

                    if (_connectCallback && _wasConnected) {
                        _connectCallback(false);
                    }
                    _wasConnected = false;
                }
            } else if (_disconnectDetectedAt != 0) {
                _disconnectDetectedAt = 0;
                // SDK auto-reconnected; refresh cached BSSID/channel if the ESP roamed
                saveBssidChannel();
            }
            break;

        case WIFI_ST_DISCONNECTED:
            // Retry connection after interval
            if (_networkCount > 0 && (now - _lastConnectAttempt >= WIFI_RECONNECT_INTERVAL)) {
                _state = WIFI_ST_CONNECTING;
                tryConnect();
            }
            break;

        case WIFI_ST_AP_MODE:
            // Process DNS requests for captive portal
            if (_dnsStarted) {
                _dnsServer.processNextRequest();
            }

            // Periodically retry STA connection in background only when no client is attached to SoftAP
            if (_networkCount > 0 && WiFi.status() != WL_CONNECTED &&
                WiFi.softAPgetStationNum() == 0 && (now - _lastApStaRetry >= 30000)) {
                _lastApStaRetry = now;
                _currentNetwork = (_currentNetwork + 1) % _networkCount;
                WiFi.begin(_networks[_currentNetwork].ssid.c_str(),
                           _networks[_currentNetwork].pass.c_str());
            }

            // Also check if STA gets connected (concurrent AP+STA mode)
            if (WiFi.status() == WL_CONNECTED && (uint32_t)WiFi.localIP() != 0) {
                Serial.println(F("[WiFi] STA connected while in AP mode"));
                _state = WIFI_ST_CONNECTED;
                _lastConnectTime = now;
                _disconnectDetectedAt = 0;
                _usingPinnedBssid = false;
                _skipPinnedBssid = false;
                _failCount = 0;
                _wasConnected = true;
                saveBssidChannel();
                setupMDNS();
                if (_dnsStarted) {
                    _dnsServer.stop();
                    _dnsStarted = false;
                }
                // Switch to STA only mode
                WiFi.mode(WIFI_STA);
                disableWifiSleep();
                if (_connectCallback) _connectCallback(true);
            }
            break;
    }
}

// ============================================================================
// Status Methods
// ============================================================================
bool WifiManager::isConnected() {
    return _state == WIFI_ST_CONNECTED && WiFi.status() == WL_CONNECTED;
}

WifiState WifiManager::getState() { return _state; }

String WifiManager::getStateString() {
    switch (_state) {
        case WIFI_ST_DISCONNECTED: return F("Disconnected");
        case WIFI_ST_CONNECTING:   return F("Connecting");
        case WIFI_ST_CONNECTED:    return F("Connected");
        case WIFI_ST_AP_MODE:      return F("AP Mode");
        default:                   return F("Unknown");
    }
}

String WifiManager::getIP() {
    if (_state == WIFI_ST_AP_MODE) return WiFi.softAPIP().toString();
    return WiFi.localIP().toString();
}

String WifiManager::getSSID() {
    if (_state == WIFI_ST_AP_MODE) return _apSSID;
    return WiFi.SSID();
}

String WifiManager::getHostname() { return _hostname; }
String WifiManager::getMAC() {
    uint8_t mac[6];
    readFactoryStaMac(mac);
    char buf[18];
    snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return String(buf);
}
String WifiManager::getDeviceId() {
    uint8_t mac[6];
    readFactoryStaMac(mac);
    char buf[20];
    snprintf(buf, sizeof(buf), "smarthome_%02x%02x%02x", mac[3], mac[4], mac[5]);
    return String(buf);
}
String WifiManager::getAPSSID() { return _apSSID; }
String WifiManager::getAPPassword() { return _apPassword; }
bool WifiManager::isAPMode() { return _state == WIFI_ST_AP_MODE; }

int WifiManager::getRSSI() {
    if (_state == WIFI_ST_CONNECTED) return WiFi.RSSI();
    return -100;
}

int WifiManager::getSignalPercent() {
    int rssi = getRSSI();
    // Convert RSSI to percentage: -100dBm = 0%, -50dBm or better = 100%
    int percent = 2 * (rssi + 100);
    return constrain(percent, 0, 100);
}

unsigned long WifiManager::getLastConnectTime() { return _lastConnectTime; }

// ============================================================================
// Start Access Point mode
// ============================================================================
void WifiManager::startAP() {
    WiFi.disconnect(false);
    WiFi.mode(WIFI_AP_STA); // AP + STA so we can still connect if credentials are saved

    // Re-evaluate AP security (Open for fresh unconfigured setup, WPA2 once configured)
    _apPassword = generateAPPassword();
    const char* pass = _apPassword.length() > 0 ? _apPassword.c_str() : nullptr;
    WiFi.softAP(_apSSID.c_str(), pass);

    // Start DNS server for captive portal
    _dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
    _dnsStarted = true;

    _state = WIFI_ST_AP_MODE;

    SERIAL_PRINTF("[WiFi] AP Mode: SSID=%s  Pass=%s  IP=%s\n",
                  _apSSID.c_str(), pass ? pass : "None (Open)", WiFi.softAPIP().toString().c_str());

    // If we have credentials, keep trying STA in background
    _lastApStaRetry = millis();
    if (_networkCount > 0) {
        WiFi.begin(_networks[0].ssid.c_str(), _networks[0].pass.c_str());
    } else {
        // Trigger non-blocking background Wi-Fi scan so nearby 2.4 GHz networks
        // are immediately ready for the onboarding wizard and captive portal
        WiFi.scanNetworks(true, false);
    }
}

// ============================================================================
// Save WiFi credentials to LittleFS
// ============================================================================
void WifiManager::saveCredentials(const String& ssid, const String& pass) {
    if (ssid.isEmpty()) return;

    // Check if this network already exists — update it
    bool found = false;
    for (uint8_t i = 0; i < _networkCount; i++) {
        if (_networks[i].ssid == ssid) {
            _networks[i].pass = pass;
            _networks[i].hasBssid = false;
            found = true;
            break;
        }
    }

    // Add new network
    if (!found) {
        if (_networkCount >= WIFI_MAX_SAVED_NETWORKS) {
            // Remove oldest (shift down)
            for (uint8_t i = 0; i < WIFI_MAX_SAVED_NETWORKS - 1; i++) {
                _networks[i] = _networks[i + 1];
            }
            _networkCount = WIFI_MAX_SAVED_NETWORKS - 1;
        }
        _networks[_networkCount].ssid = ssid;
        _networks[_networkCount].pass = pass;
        _networks[_networkCount].hasBssid = false;
        _networks[_networkCount].channel = 0;
        _networkCount++;
    }

    // Persist to LittleFS
    JsonDocument doc;
    JsonArray arr = doc["networks"].to<JsonArray>();
    for (uint8_t i = 0; i < _networkCount; i++) {
        JsonObject net = arr.add<JsonObject>();
        net["ssid"] = _networks[i].ssid;
        net["pass"] = _networks[i].pass;
        if (_networks[i].hasBssid) {
            char bssidStr[18];
            snprintf(bssidStr, sizeof(bssidStr), "%02X:%02X:%02X:%02X:%02X:%02X",
                     _networks[i].bssid[0], _networks[i].bssid[1], _networks[i].bssid[2],
                     _networks[i].bssid[3], _networks[i].bssid[4], _networks[i].bssid[5]);
            net["bssid"] = bssidStr;
            net["channel"] = _networks[i].channel;
        }
    }
    _storage->saveJson(PATH_WIFI, doc);

    SERIAL_PRINTF("[WiFi] Saved %d network(s)\n", _networkCount);

    // Attempt connection to new network
    _currentNetwork = _networkCount - 1;
    _failCount = 0;
    _skipPinnedBssid = false;
    _state = WIFI_ST_CONNECTING;
    tryConnect();
}

// ============================================================================
// Reset WiFi — delete credentials and restart AP
// ============================================================================
void WifiManager::resetWiFi() {
    Serial.println(F("[WiFi] Resetting WiFi credentials"));
    WiFi.disconnect(false, true); // Disconnect and erase SDK credentials
    _networkCount = 0;
    _storage->deleteFile(PATH_WIFI);
    startAP();
}

// ============================================================================
// Set connection callback
// ============================================================================
void WifiManager::setConnectCallback(void (*cb)(bool)) {
    _connectCallback = cb;
}

// ============================================================================
// Load saved credentials from LittleFS
// ============================================================================
void WifiManager::loadCredentials() {
    _networkCount = 0;
    JsonDocument doc;
    if (!_storage->loadJson(PATH_WIFI, doc)) return;

    JsonArray arr = doc["networks"].as<JsonArray>();
    for (JsonObject net : arr) {
        if (_networkCount >= WIFI_MAX_SAVED_NETWORKS) break;

        _networks[_networkCount].ssid = net["ssid"] | "";
        _networks[_networkCount].pass = net["pass"] | "";
        if (_networks[_networkCount].ssid.length() == 0) continue;

        memset(_networks[_networkCount].bssid, 0, sizeof(_networks[_networkCount].bssid));
        _networks[_networkCount].hasBssid = false;
        _networks[_networkCount].channel = 0;

        if (net["bssid"].is<const char*>()) {
            String bssidStr = net["bssid"] | "";
            if (bssidStr.length() == 17 &&
                sscanf(bssidStr.c_str(), "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
                       &_networks[_networkCount].bssid[0], &_networks[_networkCount].bssid[1],
                       &_networks[_networkCount].bssid[2], &_networks[_networkCount].bssid[3],
                       &_networks[_networkCount].bssid[4], &_networks[_networkCount].bssid[5]) == 6) {
                _networks[_networkCount].hasBssid = true;
                _networks[_networkCount].channel = net["channel"] | 0;
            }
        }

        _networkCount++;
    }

    SERIAL_PRINTF("[WiFi] Loaded %d saved network(s)\n", _networkCount);
}

// ============================================================================
// Attempt connection to current network (non-blocking)
// ============================================================================
void WifiManager::tryConnect() {
    if (_networkCount == 0) return;

    NetworkCredential& net = _networks[_currentNetwork];
    _connectStartTime = millis();
    _lastConnectAttempt = _connectStartTime;

    WiFi.disconnect(false);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
#if defined(ESP8266)
    WiFi.hostname(_hostname);
#else
    WiFi.setHostname(_hostname.c_str());
#endif

    // Fast reconnect only on initial attempt when we have cached BSSID/channel;
    // on retry (_failCount > 0 or _skipPinnedBssid), scan all channels/APs so multi-AP/mesh or channel-hop recovers.
    if (_failCount == 0 && !_skipPinnedBssid && net.hasBssid && net.channel > 0) {
        _usingPinnedBssid = true;
        SERIAL_PRINTF("[WiFi] Fast connecting to %s (ch %d)\n",
                      net.ssid.c_str(), (int)net.channel);
        WiFi.begin(net.ssid.c_str(), net.pass.c_str(), net.channel, net.bssid, true);
    } else {
        _usingPinnedBssid = false;
        SERIAL_PRINTF("[WiFi] Connecting to %s (full scan)\n", net.ssid.c_str());
        WiFi.begin(net.ssid.c_str(), net.pass.c_str());
    }
    disableWifiSleep();
}

// ============================================================================
// Cache BSSID and channel for fast reconnect
// ============================================================================
void WifiManager::saveBssidChannel() {
    if (_networkCount == 0) return;

    const uint8_t* curBssid = WiFi.BSSID();
    int32_t curChannel = WiFi.channel();
    if (!curBssid || curChannel <= 0) return;

    String connectedSSID = WiFi.SSID();
    for (uint8_t i = 0; i < _networkCount; i++) {
        if (_networks[i].ssid == connectedSSID) {
            // Skip flash write when AP BSSID and channel have not changed
            if (_networks[i].hasBssid &&
                _networks[i].channel == curChannel &&
                memcmp(_networks[i].bssid, curBssid, 6) == 0) {
                return;
            }

            memcpy(_networks[i].bssid, curBssid, 6);
            _networks[i].channel = curChannel;
            _networks[i].hasBssid = true;

            // Persist the BSSID/channel
            JsonDocument doc;
            JsonArray arr = doc["networks"].to<JsonArray>();
            for (uint8_t j = 0; j < _networkCount; j++) {
                JsonObject net = arr.add<JsonObject>();
                net["ssid"] = _networks[j].ssid;
                net["pass"] = _networks[j].pass;
                if (_networks[j].hasBssid) {
                    char bssidStr[18];
                    snprintf(bssidStr, sizeof(bssidStr), "%02X:%02X:%02X:%02X:%02X:%02X",
                             _networks[j].bssid[0], _networks[j].bssid[1], _networks[j].bssid[2],
                             _networks[j].bssid[3], _networks[j].bssid[4], _networks[j].bssid[5]);
                    net["bssid"] = bssidStr;
                    net["channel"] = _networks[j].channel;
                }
            }
            _storage->saveJson(PATH_WIFI, doc);
            break;
        }
    }
}

// ============================================================================
// Setup mDNS
// ============================================================================
void WifiManager::setupMDNS() {
    if (MDNS.begin(_hostname.c_str())) {
        // Standard HTTP service
        MDNS.addService("http", "tcp", WEB_SERVER_PORT);
        MDNS.addServiceTxt("http", "tcp", "mac", getMAC());
        MDNS.addServiceTxt("http", "tcp", "version", FW_VERSION);

        // Dedicated SmartHome discovery service for companion mobile apps
        MDNS.addService("smarthome", "tcp", WEB_SERVER_PORT);
        MDNS.addServiceTxt("smarthome", "tcp", "id", getDeviceId());
        MDNS.addServiceTxt("smarthome", "tcp", "mac", getMAC());
        MDNS.addServiceTxt("smarthome", "tcp", "hostname", _hostname);
        MDNS.addServiceTxt("smarthome", "tcp", "model", PLATFORM_NAME "-SmartHome");
        MDNS.addServiceTxt("smarthome", "tcp", "version", FW_VERSION);
        int nRelays = NUM_RELAYS;
        if (_storage) {
            JsonDocument hwDoc;
            if (_storage->loadJson(PATH_HARDWARE, hwDoc)) {
                nRelays = hwDoc["num_relays"] | NUM_RELAYS;
            }
        }
        MDNS.addServiceTxt("smarthome", "tcp", "relays", String(nRelays));

        String devName = DEFAULT_DEVICE_NAME;
        if (_storage) {
            JsonDocument cfg;
            if (_storage->loadJson(PATH_CONFIG, cfg)) {
                devName = cfg["device_name"] | DEFAULT_DEVICE_NAME;
            }
        }
        MDNS.addServiceTxt("smarthome", "tcp", "name", devName);

        SERIAL_PRINTF("[WiFi] mDNS started: %s.local (_smarthome._tcp registered)\n", _hostname.c_str());
    } else {
        Serial.println(F("[WiFi] mDNS failed to start"));
    }
}

// ============================================================================
// Generate AP SSID with MAC suffix
// ============================================================================
String WifiManager::generateAPSSID() {
    uint8_t mac[6];
    readFactoryStaMac(mac);
    char suffix[5];
    snprintf(suffix, sizeof(suffix), "%02X%02X", mac[4], mac[5]);
    return String(WIFI_AP_SSID_PREFIX) + suffix;
}

// ============================================================================
// Generate AP password: Open ("") on fresh unconfigured setup; WPA2-PSK once
// Wi-Fi credentials, Web Auth, or custom config.json "ap_pass" are present.
// ============================================================================
String WifiManager::generateAPPassword() {
    bool hasWebAuth = false;
    if (_storage) {
        JsonDocument cfg;
        if (_storage->loadJson(PATH_CONFIG, cfg)) {
            if (cfg["ap_pass"].is<const char*>()) {
                String customPass = cfg["ap_pass"] | "";
                if (customPass.length() >= 8 && customPass.length() <= 63) {
                    return customPass;
                }
            }
            String webHash = cfg["web_pass_hash"] | "";
            String webPass = cfg["web_pass"] | "";
            hasWebAuth = (cfg["web_auth"] | false) && (webHash.length() > 0 || webPass.length() > 0);
        }
    }
    if (_networkCount == 0 && !hasWebAuth) {
        return "";
    }
    uint8_t mac[6];
    readFactoryStaMac(mac);
    char suffix[5];
    snprintf(suffix, sizeof(suffix), "%02X%02X", mac[4], mac[5]);
    return String(WIFI_AP_PASSWORD_PREFIX) + suffix + WIFI_AP_PASSWORD_SUFFIX;
}

#if defined(ESP32)
// ============================================================================
// Static WiFi event callback (dispatches to instance)
// ============================================================================
void WifiManager::staticWiFiEvent(WiFiEvent_t event) {
    if (_instance) _instance->onWiFiEvent(event);
}

void WifiManager::onWiFiEvent(WiFiEvent_t event) {
    switch (event) {
        case ARDUINO_EVENT_WIFI_STA_GOT_IP:
            SERIAL_PRINTF("[WiFi] Got IP: %s\n", WiFi.localIP().toString().c_str());
            break;
        case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
            if (_state == WIFI_ST_CONNECTED) {
                Serial.println(F("[WiFi] Station disconnected"));
            }
            break;
        case ARDUINO_EVENT_WIFI_AP_STACONNECTED:
            Serial.println(F("[WiFi] AP client connected"));
            break;
        case ARDUINO_EVENT_WIFI_AP_STADISCONNECTED:
            Serial.println(F("[WiFi] AP client disconnected"));
            break;
        default:
            break;
    }
}
#endif
