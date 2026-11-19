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

#if defined(ESP32)
namespace {
class WifiMutexGuard {
public:
    explicit WifiMutexGuard(SemaphoreHandle_t mtx) : _mtx(mtx) {
        if (_mtx) xSemaphoreTakeRecursive(_mtx, portMAX_DELAY);
    }
    ~WifiMutexGuard() {
        if (_mtx) xSemaphoreGiveRecursive(_mtx);
    }
private:
    SemaphoreHandle_t _mtx;
};
} // namespace

void WifiManager::ensureMutex() const {
    if (!_wifiMutex) {
        _wifiMutex = xSemaphoreCreateRecursiveMutex();
    }
}
#define WIFI_LOCK() ensureMutex(); WifiMutexGuard _wifiLockGuard(_wifiMutex)
#else
#define WIFI_LOCK() ((void)0)
#endif

// ============================================================================
// Constructor
// ============================================================================
WifiManager::WifiManager()
    : _storage(nullptr), _state(WIFI_ST_DISCONNECTED),
      _networkCount(0), _currentNetwork(0),
      _lastConnectAttempt(0), _lastConnectTime(0), _connectStartTime(0),
      _disconnectDetectedAt(0),
      _failCount(0), _quickRetryPending(false), _usingPinnedBssid(false), _skipPinnedBssid(false),
      _dnsStarted(false), _apScanPending(false), _apStartedAt(0),
      _pendingReset(false), _pendingResetAt(0), _pendingResetDelay(250),
      _pendingReconnect(false), _pendingReconnectAt(0), _pendingReconnectDelay(250),
      _connectCallback(nullptr), _wasConnected(false)
#if defined(ESP32)
    , _wifiMutex(nullptr)
#endif
{
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
#if defined(ESP32)
    ensureMutex();
#endif
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

    if (_pendingReset && (now - _pendingResetAt >= _pendingResetDelay)) {
        _pendingReset = false;
        resetWiFi();
        return;
    }

    if (_pendingReconnect && (now - _pendingReconnectAt >= _pendingReconnectDelay)) {
        WIFI_LOCK();
        _pendingReconnect = false;
        if (_dnsStarted) {
            _dnsServer.stop();
            _dnsStarted = false;
        }
        _apScanPending = false;
        _failCount = 0;
        _quickRetryPending = false;
        _skipPinnedBssid = false;
        _wasConnected = false;
        _state = WIFI_ST_CONNECTING;
        tryConnect();
        return;
    }

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
            // Check timeout (fail fast out of pinned BSSID/channel before full scan)
            else if (now - _connectStartTime > (_usingPinnedBssid ? 6000UL : (unsigned long)WIFI_CONNECT_TIMEOUT)) {
                if (_usingPinnedBssid) {
                    _skipPinnedBssid = true;
                    Serial.println(F("[WiFi] Pinned BSSID/channel timed out, retrying full scan..."));
                    tryConnect();
                } else {
                    _failCount++;
                    _quickRetryPending = false;
                    _currentNetwork = (_currentNetwork + 1) % _networkCount;
                    _state = WIFI_ST_DISCONNECTED;
                    _lastConnectAttempt = now;
                    WiFi.disconnect(false);
                    if (_failCount >= _networkCount) {
                        SERIAL_PRINTF("[WiFi] Router unavailable (failed %u/%u saved network(s)); retrying in 2 min until WiFi reset\n",
                                      (unsigned)_failCount, (unsigned)_networkCount);
                    } else {
                        SERIAL_PRINTF("[WiFi] Connection timeout (%u/%u), trying next saved network...\n",
                                      (unsigned)_failCount, (unsigned)_networkCount);
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
                    Serial.println(F("[WiFi] Connection lost, attempting reconnect..."));
                    _state = WIFI_ST_DISCONNECTED;
                    _disconnectDetectedAt = 0;
                    _failCount = 0;
                    _quickRetryPending = true;
                    _lastConnectAttempt = now - WIFI_QUICK_RECONNECT_INTERVAL + 500; // Quick first retry

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
            // Retry quickly between saved SSIDs (or immediate link-drop retry),
            // otherwise wait 2 minutes between cycles indefinitely until router returns or WiFi is reset.
            if (_networkCount > 0) {
                unsigned long retryWait = (_quickRetryPending || _failCount < _networkCount)
                    ? WIFI_QUICK_RECONNECT_INTERVAL
                    : WIFI_RECONNECT_INTERVAL;
                if (now - _lastConnectAttempt >= retryWait) {
                    if (_failCount >= _networkCount) {
                        _failCount = 0;
                    }
                    _quickRetryPending = false;
                    _state = WIFI_ST_CONNECTING;
                    tryConnect();
                }
            }
            break;

        case WIFI_ST_AP_MODE:
            // Only active when _networkCount == 0 (fresh setup or explicit WiFi/factory reset)
            if (_dnsStarted) {
                _dnsServer.processNextRequest();
            }
            // Defer initial background Wi-Fi scan until clients finish DHCP + captive portal checks
            // so single-radio channel hopping doesn't interfere with initial association.
            if (_apScanPending && (now - _apStartedAt >= 4000UL)) {
                _apScanPending = false;
                int scanStatus = WiFi.scanComplete();
                if (scanStatus != WIFI_SCAN_RUNNING && scanStatus < 0) {
                    WiFi.scanDelete();
                    WiFi.scanNetworks(true, false);
                }
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
    WIFI_LOCK();
    if (_state == WIFI_ST_AP_MODE) return _apSSID;
    return WiFi.SSID();
}

String WifiManager::getHostname() { WIFI_LOCK(); return _hostname; }
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
String WifiManager::getAPSSID() { WIFI_LOCK(); return _apSSID; }
String WifiManager::getAPPassword() { WIFI_LOCK(); return _apPassword; }
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
    if (_dnsStarted) {
        _dnsServer.stop();
        _dnsStarted = false;
    }

    // Bounce existing SoftAP cleanly when re-entering AP setup (e.g., repeated reset)
    // so already-associated phones re-run DHCP + OS captive portal detection.
    if (WiFi.getMode() & WIFI_AP) {
        WiFi.softAPdisconnect(false);
        delay(100);
    }

    WiFi.disconnect(false);
    WiFi.mode(WIFI_AP_STA); // AP + STA so onboarding WiFi scan works reliably

    // Re-evaluate AP security (Open unless custom ap_pass configured in config.json)
    _apPassword = generateAPPassword();
    const char* pass = _apPassword.length() > 0 ? _apPassword.c_str() : nullptr;
    WiFi.softAP(_apSSID.c_str(), pass);

    IPAddress apIP(192, 168, 4, 1);
#if defined(ESP32)
    WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0), IPAddress(192, 168, 4, 2), apIP);
#else
    WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
#endif

    // Start DNS server for captive portal with 0s TTL so Android/iOS do not cache stale lookups across resets
    _dnsServer.setTTL(0);
    _dnsServer.start(DNS_PORT, "*", apIP);
    _dnsStarted = true;

    _state = WIFI_ST_AP_MODE;

    SERIAL_PRINTF("[WiFi] AP Setup Mode: SSID=%s  Pass=%s  IP=%s\n",
                  _apSSID.c_str(), pass ? pass : "None (Open)", WiFi.softAPIP().toString().c_str());

    // Clear stale scan results; defer background scan 4s so AP stays on ch 1 during initial DHCP/probe
    WiFi.scanDelete();
    _apScanPending = true;
    _apStartedAt = millis();
}

// ============================================================================
// Save WiFi credentials to LittleFS
// ============================================================================
void WifiManager::saveCredentials(const String& ssid, const String& pass, bool connectNow) {
    WIFI_LOCK();
    if (ssid.isEmpty()) return;

    // Check if this network already exists — update it
    bool found = false;
    uint8_t targetIdx = 0;
    for (uint8_t i = 0; i < _networkCount; i++) {
        if (_networks[i].ssid == ssid) {
            _networks[i].pass = pass;
            _networks[i].hasBssid = false;
            targetIdx = i;
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
        targetIdx = _networkCount;
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

    _currentNetwork = targetIdx;
    if (connectNow) {
        // Attempt connection to new network (and exit setup AP mode immediately)
        if (_dnsStarted) {
            _dnsServer.stop();
            _dnsStarted = false;
        }
        _pendingReconnect = false;
        _apScanPending = false;
        _failCount = 0;
        _quickRetryPending = false;
        _skipPinnedBssid = false;
        _wasConnected = false;
        _state = WIFI_ST_CONNECTING;
        tryConnect();
    } else {
        requestReconnect(300);
    }
}

void WifiManager::requestReconnect(unsigned long delayMs) {
    WIFI_LOCK();
    _pendingReconnect = true;
    _pendingReconnectAt = millis();
    _pendingReconnectDelay = delayMs;
}

// ============================================================================
// Reset WiFi — delete credentials and restart AP
// ============================================================================
void WifiManager::resetWiFi() {
    Serial.println(F("[WiFi] Resetting WiFi credentials"));
    _pendingReset = false;
    _apScanPending = false;
    MDNS.end();
    WiFi.disconnect(false, true); // Disconnect and erase SDK credentials
    _networkCount = 0;
    _failCount = 0;
    _quickRetryPending = false;
    _usingPinnedBssid = false;
    _skipPinnedBssid = false;
    _disconnectDetectedAt = 0;
    _wasConnected = false;
    _storage->deleteFile(PATH_WIFI);
    startAP();
}

void WifiManager::requestReset(unsigned long delayMs) {
    _pendingReset = true;
    _pendingResetAt = millis();
    _pendingResetDelay = delayMs;
}

bool WifiManager::setHostname(const String& hostname) {
    WIFI_LOCK();
    String h = hostname;
    h.trim();
    if (h.length() == 0 || h.length() > 24) return false;
    for (size_t i = 0; i < h.length(); i++) {
        char c = h[i];
        bool isAlnum = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        bool isHyphen = (c == '-' && i > 0 && i + 1 < h.length());
        if (!isAlnum && !isHyphen) return false;
    }
    if (h == _hostname) return true;
    _hostname = h;
#if defined(ESP8266)
    WiFi.hostname(_hostname);
#else
    WiFi.setHostname(_hostname.c_str());
#endif
    if (isConnected()) {
        MDNS.end();
        setupMDNS();
    }
    return true;
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
    MDNS.end();
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
// Generate AP password: Open ("") by default for fresh/reset setup; optional
// custom "ap_pass" (8-63 chars) from config.json if explicitly configured.
// ============================================================================
String WifiManager::generateAPPassword() {
    if (_storage) {
        JsonDocument cfg;
        if (_storage->loadJson(PATH_CONFIG, cfg)) {
            if (cfg["ap_pass"].is<const char*>()) {
                String customPass = cfg["ap_pass"] | "";
                if (customPass.length() >= 8 && customPass.length() <= 63) {
                    return customPass;
                }
            }
        }
    }
    return "";
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
