/*
 * ============================================================================
 * MqttManager.cpp — Async MQTT Client Implementation
 * ============================================================================
 */

#include "MqttManager.h"
#if defined(ESP8266)
#include <ESP8266WiFi.h>
#else
#include <WiFi.h>
#endif
#include "EventLogger.h"

MqttManager* MqttManager::_instance = nullptr;

MqttManager::MqttManager()
    : _storage(nullptr), _logger(nullptr), _enabled(false), _port(MQTT_DEFAULT_PORT),
      _suspended(false),
      _wasConnected(false), _connectInProgress(false), _lastReconnectAttempt(0),
      _connectStartedAt(0),
      _reconnectInterval(MQTT_RECONNECT_BASE), _lastPublish(0),
      _relayCallback(nullptr) {
    _instance = this;
}

void MqttManager::begin(StorageManager& storage, EventLogger& logger) {
    _storage = &storage;
    _logger = &logger;
    loadConfig();

    // Set up callbacks
    _client.onConnect(_onConnect);
    _client.onDisconnect(_onDisconnect);
    _client.onMessage(_onMessage);

    if (_enabled && _broker.length() > 0) {
        applyClientConfig();
        Serial.printf("[MQTT] Configured: %s:%d prefix=%s client_id=%s user=%s (pass_len=%d)\n",
                      _broker.c_str(), _port, _prefix.c_str(), _clientId.c_str(), _user.c_str(), _pass.length());
        connect();
    } else {
        Serial.println(F("[MQTT] Disabled or not configured"));
    }
}

void MqttManager::loop() {
    if (!_enabled || _suspended || _broker.length() == 0) return;

    // Do not attempt to connect if WiFi is not connected
    if (WiFi.status() != WL_CONNECTED) {
        _reconnectInterval = MQTT_RECONNECT_BASE; // Reset backoff so we reconnect quickly when WiFi returns
        return;
    }

    unsigned long now = millis();

    if (_connectInProgress && (now - _connectStartedAt >= MQTT_CONNECT_TIMEOUT)) {
        Serial.printf("[MQTT] Connect attempt timed out after %lu ms; resetting client state\n",
                      now - _connectStartedAt);
        _lastError = F("Connection timed out");
        _connectInProgress = false;
        _client.disconnect();
    }

    // Auto-reconnect with exponential backoff
    if (!_client.connected() && !_connectInProgress &&
        (now - _lastReconnectAttempt >= _reconnectInterval)) {
        _lastReconnectAttempt = now;
        Serial.printf("[MQTT] Reconnecting to %s:%d (interval: %lums)...\n", _broker.c_str(), _port, _reconnectInterval);
        connect();

        // Exponential backoff
        _reconnectInterval = min(_reconnectInterval * 2, (unsigned long)MQTT_RECONNECT_MAX);
    }
}

void MqttManager::connect() {
    if (!_enabled || _suspended || _broker.length() == 0) return;
    if (WiFi.status() != WL_CONNECTED) return;
    if (_client.connected() || _connectInProgress) return;
    applyClientConfig();
    _connectInProgress = true;
    _connectStartedAt = millis();
    _lastError = F("Connecting");
    Serial.println(F("[MQTT] Calling _client.connect()..."));
    _client.connect();
}

void MqttManager::disconnect() {
    _connectInProgress = false;
    _connectStartedAt = 0;
    _client.disconnect();
    _wasConnected = false;
}

void MqttManager::suspend() {
    _suspended = true;
    _lastError = F("Suspended for OTA");
    disconnect();
}

void MqttManager::resume() {
    _suspended = false;
    _reconnectInterval = MQTT_RECONNECT_BASE;
    _lastReconnectAttempt = 0;
    if (_enabled && _broker.length() > 0) {
        connect();
    }
}

bool MqttManager::isConnected() { return _client.connected(); }
bool MqttManager::isEnabled()   { return _enabled; }

void MqttManager::setEnabled(bool enabled) {
    _enabled = enabled;
    if (!_enabled) {
        _lastError = F("Disabled");
        disconnect();
    } else if (_broker.length() > 0) {
        applyClientConfig();
        connect();
    }
}

String MqttManager::getStateString() {
    if (!_enabled) return F("Disabled");
    if (_suspended) return F("Suspended");
    if (_client.connected()) return F("Connected");
    if (_connectInProgress) return F("Connecting");
    if (_broker.length() == 0) return F("Not Configured");
    if (_lastError.length() > 0) return _lastError;
    return F("Disconnected");
}

// ============================================================================
// Publishing
// ============================================================================
void MqttManager::publishRelayState(uint8_t index, bool state) {
    if (!_client.connected()) return;

    String topic = buildTopic("relay/" + String(index + 1) + "/state");
    _client.publish(topic.c_str(), 1, true, state ? "ON" : "OFF");
}

void MqttManager::publishSensorData(float temp, float hum, int gasRaw, bool gasAlarm,
                                    float pressure, float lux, bool motion,
                                    float probeTemp, int tankLevel) {
    if (!_client.connected()) return;

    unsigned long now = millis();
    if (now - _lastPublish < MQTT_PUBLISH_INTERVAL) return;
    _lastPublish = now;

    char buf[16];

    dtostrf(temp, 1, 1, buf);
    _client.publish(buildTopic("sensor/temperature").c_str(), 0, false, buf);

    dtostrf(hum, 1, 1, buf);
    _client.publish(buildTopic("sensor/humidity").c_str(), 0, false, buf);

    itoa(gasRaw, buf, 10);
    _client.publish(buildTopic("sensor/gas").c_str(), 0, false, buf);

    _client.publish(buildTopic("sensor/gas_alarm").c_str(), 0, false,
                    gasAlarm ? "danger" : "safe");

    if (pressure > 300.0f) {
        dtostrf(pressure, 1, 1, buf);
        _client.publish(buildTopic("sensor/pressure").c_str(), 0, false, buf);
    }

    if (lux >= 0.0f) {
        dtostrf(lux, 1, 1, buf);
        _client.publish(buildTopic("sensor/illuminance").c_str(), 0, false, buf);
    }

    _client.publish(buildTopic("binary_sensor/motion").c_str(), 0, false,
                    motion ? "ON" : "OFF");

    if (probeTemp > -55.0f && probeTemp < 130.0f) {
        dtostrf(probeTemp, 1, 1, buf);
        _client.publish(buildTopic("sensor/water_temp").c_str(), 0, false, buf);
    }

    if (tankLevel >= 0) {
        itoa(tankLevel, buf, 10);
        _client.publish(buildTopic("sensor/tank_level").c_str(), 0, false, buf);
    }
}

void MqttManager::publishDiagnostics(const String& json) {
    if (!_client.connected()) return;
    _client.publish(buildTopic("diagnostics").c_str(), 0, false, json.c_str());
}

void MqttManager::publishAvailability(bool online) {
    if (!_client.connected()) return;
    _client.publish(buildTopic("status").c_str(), 1, true, online ? "online" : "offline");
}

void MqttManager::publishHomeAssistantDiscovery() {
    if (!_client.connected()) return;

    const String deviceId = getDeviceId();
    const String deviceName = getDeviceName();
    const String availabilityTopic = buildTopic("status");

    JsonDocument relayDoc;
    JsonArray relays = relayDoc["relays"].as<JsonArray>();
    uint8_t relayCount = NUM_RELAYS;
    bool dhtEnabled = true;
    bool bmeEnabled = false;
    bool mq2Enabled = true;
    bool lightEnabled = false;
    bool motionEnabled = false;
    bool probeEnabled = false;
    bool tankEnabled = false;

    bool channelEnabled[MAX_RELAYS];
    for (uint8_t i = 0; i < MAX_RELAYS; i++) channelEnabled[i] = true;

    if (_storage) {
        JsonDocument hwDoc;
        if (_storage->loadJson(PATH_HARDWARE, hwDoc)) {
            relayCount = hwDoc["num_relays"] | NUM_RELAYS;
            if (hwDoc.containsKey("channels")) {
                JsonArray chArr = hwDoc["channels"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_RELAYS && i < chArr.size(); i++) {
                    channelEnabled[i] = chArr[i]["enabled"] | true;
                }
            }
            if (hwDoc.containsKey("dht")) {
                uint8_t dt = hwDoc["dht"]["type"] | 2;
                dhtEnabled = (dt != 0);
                bmeEnabled = (dt == 3);
            }
            if (hwDoc.containsKey("mq2")) {
                mq2Enabled = hwDoc["mq2"]["enabled"] | true;
            }
            if (hwDoc.containsKey("light")) {
                lightEnabled = ((hwDoc["light"]["type"] | 0) != 0);
            }
            if (hwDoc.containsKey("motion")) {
                motionEnabled = ((hwDoc["motion"]["type"] | 0) != 0);
            }
            if (hwDoc.containsKey("probe")) {
                probeEnabled = ((hwDoc["probe"]["type"] | 0) != 0);
            }
            if (hwDoc.containsKey("ultrasonic")) {
                tankEnabled = ((hwDoc["ultrasonic"]["type"] | 0) != 0);
            }
        }
        _storage->loadJson(PATH_RELAYS, relayDoc);
        relays = relayDoc["relays"].as<JsonArray>();
    }

    if (relayCount > MAX_RELAYS) relayCount = MAX_RELAYS;

    for (uint8_t i = 0; i < relayCount; i++) {
        if (!channelEnabled[i]) {
            publishHomeAssistantDiscoveryRemove(i);
            continue;
        }
        const char* relayName = DEFAULT_RELAY_NAMES[i];
        if (!relays.isNull() && i < relays.size()) {
            relayName = relays[i]["name"] | DEFAULT_RELAY_NAMES[i];
        }

        JsonDocument doc;
        doc["name"] = relayName;
        doc["uniq_id"] = deviceId + "_relay_" + String(i + 1);
        doc["obj_id"] = deviceId + "_relay_" + String(i + 1);
        doc["stat_t"] = buildTopic("relay/" + String(i + 1) + "/state");
        doc["cmd_t"] = buildTopic("relay/" + String(i + 1) + "/set");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["pl_on"] = "ON";
        doc["pl_off"] = "OFF";
        doc["stat_on"] = "ON";
        doc["stat_off"] = "OFF";
        doc["icon"] = "mdi:light-switch";

        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;

        String topic = "homeassistant/switch/" + deviceId + "/relay_" + String(i + 1) + "/config";
        publishDiscoveryConfig(topic, doc);
    }

    if (dhtEnabled) {
        JsonDocument doc;
        doc["name"] = "Temperature";
        doc["uniq_id"] = deviceId + "_temperature";
        doc["obj_id"] = deviceId + "_temperature";
        doc["stat_t"] = buildTopic("sensor/temperature");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "°C";
        doc["dev_cla"] = "temperature";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/temperature/config", doc);
    }

    if (dhtEnabled) {
        JsonDocument doc;
        doc["name"] = "Humidity";
        doc["uniq_id"] = deviceId + "_humidity";
        doc["obj_id"] = deviceId + "_humidity";
        doc["stat_t"] = buildTopic("sensor/humidity");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "%";
        doc["dev_cla"] = "humidity";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/humidity/config", doc);
    }

    if (mq2Enabled) {
        JsonDocument doc;
        doc["name"] = "Gas Level";
        doc["uniq_id"] = deviceId + "_gas";
        doc["obj_id"] = deviceId + "_gas";
        doc["stat_t"] = buildTopic("sensor/gas");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "raw";
        doc["stat_cla"] = "measurement";
        doc["icon"] = "mdi:molecule-co";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/gas/config", doc);
    }

    if (mq2Enabled) {
        JsonDocument doc;
        doc["name"] = "Gas Alarm";
        doc["uniq_id"] = deviceId + "_gas_alarm";
        doc["obj_id"] = deviceId + "_gas_alarm";
        doc["stat_t"] = buildTopic("sensor/gas_alarm");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["pl_on"] = "danger";
        doc["pl_off"] = "safe";
        doc["dev_cla"] = "gas";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/binary_sensor/" + deviceId + "/gas_alarm/config", doc);
    }

    // Barometric Pressure (BME280)
    if (bmeEnabled) {
        JsonDocument doc;
        doc["name"] = "Barometric Pressure";
        doc["uniq_id"] = deviceId + "_pressure";
        doc["obj_id"] = deviceId + "_pressure";
        doc["stat_t"] = buildTopic("sensor/pressure");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "hPa";
        doc["dev_cla"] = "atmospheric_pressure";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/pressure/config", doc);
    } else {
        _client.publish(("homeassistant/sensor/" + deviceId + "/pressure/config").c_str(), 1, true, "");
    }

    // Ambient Light (BH1750)
    if (lightEnabled) {
        JsonDocument doc;
        doc["name"] = "Ambient Light";
        doc["uniq_id"] = deviceId + "_lux";
        doc["obj_id"] = deviceId + "_lux";
        doc["stat_t"] = buildTopic("sensor/illuminance");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "lx";
        doc["dev_cla"] = "illuminance";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/illuminance/config", doc);
    } else {
        _client.publish(("homeassistant/sensor/" + deviceId + "/illuminance/config").c_str(), 1, true, "");
    }

    // Motion / Occupancy (PIR / Radar)
    if (motionEnabled) {
        JsonDocument doc;
        doc["name"] = "Motion Occupancy";
        doc["uniq_id"] = deviceId + "_motion";
        doc["obj_id"] = deviceId + "_motion";
        doc["stat_t"] = buildTopic("binary_sensor/motion");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["dev_cla"] = "motion";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/binary_sensor/" + deviceId + "/motion/config", doc);
    } else {
        _client.publish(("homeassistant/binary_sensor/" + deviceId + "/motion/config").c_str(), 1, true, "");
    }

    // Water Temp Probe (DS18B20)
    if (probeEnabled) {
        JsonDocument doc;
        doc["name"] = "Water Temperature";
        doc["uniq_id"] = deviceId + "_water_temp";
        doc["obj_id"] = deviceId + "_water_temp";
        doc["stat_t"] = buildTopic("sensor/water_temp");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "°C";
        doc["dev_cla"] = "temperature";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/water_temp/config", doc);
    } else {
        _client.publish(("homeassistant/sensor/" + deviceId + "/water_temp/config").c_str(), 1, true, "");
    }

    // Water Tank Level (HC-SR04/P / JSN-SR04T)
    if (tankEnabled) {
        JsonDocument doc;
        doc["name"] = "Water Tank Level";
        doc["uniq_id"] = deviceId + "_tank_level";
        doc["obj_id"] = deviceId + "_tank_level";
        doc["stat_t"] = buildTopic("sensor/tank_level");
        doc["avty_t"] = availabilityTopic;
        doc["pl_avail"] = "online";
        doc["pl_not_avail"] = "offline";
        doc["unit_of_meas"] = "%";
        doc["icon"] = "mdi:water-percent";
        doc["stat_cla"] = "measurement";
        JsonObject device = doc["dev"].to<JsonObject>();
        addDeviceInfo(device);
        device["name"] = deviceName;
        publishDiscoveryConfig("homeassistant/sensor/" + deviceId + "/tank_level/config", doc);
    } else {
        _client.publish(("homeassistant/sensor/" + deviceId + "/tank_level/config").c_str(), 1, true, "");
    }
}

void MqttManager::publishHomeAssistantDiscoveryRemove(uint8_t index) {
    if (!_client.connected()) return;
    String deviceId = getDeviceId();
    String topic = "homeassistant/switch/" + deviceId + "/relay_" + String(index + 1) + "/config";
    _client.publish(topic.c_str(), 1, true, "");
    Serial.printf("[MQTT] Sent discovery remove for relay %d\n", index + 1);
}

void MqttManager::publishInitialStates() {
    if (!_client.connected() || !_storage) return;

    uint8_t relayCount = MAX_RELAYS;
    JsonDocument hwDoc;
    if (_storage->loadJson(PATH_HARDWARE, hwDoc)) {
        relayCount = hwDoc["num_relays"] | MAX_RELAYS;
    }

    bool logical[MAX_RELAYS] = {0};
    bool wallSw[MAX_RELAYS] = {0};
    if (_storage && _storage->loadRelayStatesNVS(logical, wallSw, relayCount)) {
        for (uint8_t i = 0; i < relayCount; i++) {
            publishRelayState(i, logical[i]);
        }
    }

    _lastPublish = millis() - MQTT_PUBLISH_INTERVAL;
}

// ============================================================================
// Config
// ============================================================================
void MqttManager::saveConfig(const String& broker, uint16_t port,
                              const String& user, const String& pass,
                              const String& clientId, const String& prefix) {
    _broker = broker;
    _broker.trim();
    _port = port > 0 ? port : MQTT_DEFAULT_PORT;
    _user = user;
    _user.trim();

    if (_user.length() == 0) {
        _pass = "";
    } else if (pass.length() > 0) {
        _pass = pass;
        _pass.trim();
    }

    _clientId = clientId;
    _clientId.trim();
    if (_clientId.length() == 0) {
        // Generate default client ID from chip ID if none is set
#if defined(ESP8266)
        uint32_t chipId = (uint32_t)(ESP.getChipId() & 0xFFFF);
#else
        uint32_t chipId = (uint32_t)(ESP.getEfuseMac() & 0xFFFF);
#endif
        char defaultId[20];
        snprintf(defaultId, sizeof(defaultId), "smarthome-%04X", chipId);
        _clientId = String(defaultId);
    }
    _prefix = prefix;
    _prefix.trim();
    if (_prefix.length() == 0) {
        _prefix = MQTT_DEFAULT_PREFIX;
    }

    if (_storage) {
        JsonDocument doc;
        doc["enabled"]   = _enabled;
        doc["broker"]    = _broker;
        doc["port"]      = _port;
        doc["user"]      = _user;
        doc["pass"]      = _pass;
        doc["client_id"] = _clientId;
        doc["prefix"]    = _prefix;
        _storage->saveJson(PATH_MQTT, doc);
    }

    // Reconnect with new settings
    disconnect();
    if (_enabled && _broker.length() > 0) {
        applyClientConfig();
        Serial.printf("[MQTT] Configured: %s:%d prefix=%s client_id=%s user=%s (pass_len=%d)\n",
                      _broker.c_str(), _port, _prefix.c_str(), _clientId.c_str(), _user.c_str(), _pass.length());

        _reconnectInterval = MQTT_RECONNECT_BASE;
        connect();
    }
}

String MqttManager::getBroker()  { return _broker; }
uint16_t MqttManager::getPort()  { return _port; }
String MqttManager::getPrefix()  { return _prefix; }
String MqttManager::getUser()    { return _user; }
String MqttManager::getPassword() { return _pass; }

void MqttManager::toJson(JsonObject& obj) {
    obj["enabled"]   = _enabled;
    obj["broker"]    = _broker;
    obj["port"]      = _port;
    obj["user"]      = _user;
    obj["pass"]      = ""; // Don't expose password
    obj["client_id"] = _clientId;
    obj["prefix"]    = _prefix;
    obj["connected"] = _client.connected();
    obj["state"]     = getStateString();
}

void MqttManager::setRelayCallback(void (*cb)(uint8_t, bool)) {
    _relayCallback = cb;
}

// ============================================================================
// Event Handlers
// ============================================================================
void MqttManager::onConnect(bool sessionPresent) {
    Serial.println(F("[MQTT] Connected"));
    _wasConnected = true;
    _connectInProgress = false;
    _connectStartedAt = 0;
    _lastError = "";
    _reconnectInterval = MQTT_RECONNECT_BASE; // Reset backoff

    if (_logger) {
        _logger->logInfo("MQTT", "Connected to broker: " + _broker);
    }

    // Publish birth message
    publishAvailability(true);

    // Publish retained Home Assistant discovery config
    publishHomeAssistantDiscovery();

    // Publish current retained state topics immediately
    publishInitialStates();

    // Subscribe to relay command topics
    subscribeTopics();
}

void MqttManager::onDisconnect(AsyncMqttClientDisconnectReason reason) {
    Serial.printf("[MQTT] Disconnected (reason: %d)\n", (int)reason);
    _wasConnected = false;
    _connectInProgress = false;
    _connectStartedAt = 0;

    if (_enabled && _broker.length() > 0) {
        String reasonStr = F("Disconnected");
        switch (reason) {
            case AsyncMqttClientDisconnectReason::TCP_DISCONNECTED: reasonStr = "TCP disconnected (broker unreachable)"; break;
            case AsyncMqttClientDisconnectReason::MQTT_UNACCEPTABLE_PROTOCOL_VERSION: reasonStr = "Unacceptable protocol version"; break;
            case AsyncMqttClientDisconnectReason::MQTT_IDENTIFIER_REJECTED: reasonStr = "Client ID rejected"; break;
            case AsyncMqttClientDisconnectReason::MQTT_SERVER_UNAVAILABLE: reasonStr = "Server unavailable"; break;
            case AsyncMqttClientDisconnectReason::MQTT_MALFORMED_CREDENTIALS: reasonStr = "Bad username or password"; break;
            case AsyncMqttClientDisconnectReason::MQTT_NOT_AUTHORIZED: reasonStr = "Not authorized"; break;
            default: reasonStr = "Unknown error " + String((int)reason); break;
        }
        _lastError = reasonStr;
        if (_logger) {
            _logger->logWarning("MQTT", "Disconnected: " + reasonStr);
        }
    } else if (!_enabled) {
        _lastError = F("Disabled");
    } else if (_broker.length() == 0) {
        _lastError = F("Not Configured");
    }
}

void MqttManager::onMessage(char* topic, char* payload,
                             AsyncMqttClientMessageProperties properties,
                             size_t len, size_t index, size_t total) {
    // Null-terminate payload
    char payloadBuf[16];
    size_t copyLen = min(len, sizeof(payloadBuf) - 1);
    memcpy(payloadBuf, payload, copyLen);
    payloadBuf[copyLen] = '\0';

    String topicStr = String(topic);
    String payloadStr = String(payloadBuf);

    Serial.printf("[MQTT] Received: %s = %s\n", topic, payloadBuf);

    // Parse relay commands: {prefix}/relay/{N}/set
    String relayPrefix = _prefix + "/relay/";
    if (topicStr.startsWith(relayPrefix) && topicStr.endsWith("/set")) {
        // Extract relay number
        int start = relayPrefix.length();
        int end = topicStr.indexOf("/set");
        String relayNumStr = topicStr.substring(start, end);
        int relayNum = relayNumStr.toInt();

        if (relayNum >= 1 && relayNum <= MAX_RELAYS) {
            if (payloadStr.equalsIgnoreCase("ON") || payloadStr == "1") {
                if (_relayCallback) _relayCallback(relayNum - 1, true);
            } else if (payloadStr.equalsIgnoreCase("OFF") || payloadStr == "0") {
                if (_relayCallback) _relayCallback(relayNum - 1, false);
            }
        }
    }
}

// Static callback dispatchers
void MqttManager::_onConnect(bool sp)       { if (_instance) _instance->onConnect(sp); }
void MqttManager::_onDisconnect(AsyncMqttClientDisconnectReason r) { if (_instance) _instance->onDisconnect(r); }
void MqttManager::_onMessage(char* t, char* p, AsyncMqttClientMessageProperties pr,
                              size_t l, size_t i, size_t tot) {
    if (_instance) _instance->onMessage(t, p, pr, l, i, tot);
}

// ============================================================================
// Private
// ============================================================================
void MqttManager::loadConfig() {
    _enabled = false;
    _broker = "";
    _port = MQTT_DEFAULT_PORT;
    _user = "";
    _pass = "";
    _prefix = MQTT_DEFAULT_PREFIX;
    _lastError = "";

    // Generate default client ID from chip ID
#if defined(ESP8266)
    uint32_t chipId = (uint32_t)(ESP.getChipId() & 0xFFFF);
#else
    uint32_t chipId = (uint32_t)(ESP.getEfuseMac() & 0xFFFF);
#endif
    char defaultId[20];
    snprintf(defaultId, sizeof(defaultId), "smarthome-%04X", chipId);
    _clientId = String(defaultId);

    if (!_storage) return;
    JsonDocument doc;
    if (!_storage->loadJson(PATH_MQTT, doc)) return;

    _enabled   = doc["enabled"] | false;
    _broker    = doc["broker"].as<String>();
    _broker.trim();
    _port      = doc["port"] | MQTT_DEFAULT_PORT;
    _user      = doc["user"].as<String>();
    _user.trim();
    _pass      = doc["pass"].as<String>();
    _pass.trim();
    _clientId  = doc["client_id"] | _clientId;
    _clientId.trim();
    _prefix    = doc["prefix"] | MQTT_DEFAULT_PREFIX;
    _prefix.trim();
    if (_prefix.length() == 0) _prefix = MQTT_DEFAULT_PREFIX;
}

void MqttManager::applyClientConfig() {
    IPAddress brokerIP;
    if (brokerIP.fromString(_broker)) {
        _client.setServer(brokerIP, _port);
    } else {
        _client.setServer(_broker.c_str(), _port);
    }

    _client.setKeepAlive(MQTT_KEEPALIVE);

    if (_user.length() > 0) {
        _client.setCredentials(_user.c_str(), _pass.c_str());
    } else {
        _client.setCredentials(nullptr, nullptr);
    }

    if (_clientId.length() > 0) {
        _client.setClientId(_clientId.c_str());
    }

    _willTopic = buildTopic("status");
    _client.setWill(_willTopic.c_str(), 1, true, "offline");
}

String MqttManager::getDeviceId() {
    String id = _clientId;
    id.toLowerCase();
    id.replace(" ", "_");
    id.replace("-", "_");
    return id;
}

String MqttManager::getDeviceName() {
    if (!_storage) return DEFAULT_DEVICE_NAME;

    JsonDocument doc;
    if (_storage->loadJson(PATH_CONFIG, doc)) {
        return doc["device_name"] | DEFAULT_DEVICE_NAME;
    }

    return DEFAULT_DEVICE_NAME;
}

void MqttManager::addDeviceInfo(JsonObject& device) {
    const String deviceId = getDeviceId();
    device["name"] = getDeviceName();
    device["mf"] = "Vikash Smart Home";
    device["mdl"] = FW_NAME;
    device["sw"] = FW_VERSION;

    JsonArray ids = device["ids"].to<JsonArray>();
    ids.add(deviceId);
}

bool MqttManager::publishDiscoveryConfig(const String& topic, JsonDocument& doc) {
    if (!_client.connected()) return false;

    String payload;
    payload.reserve(measureJson(doc) + 1);
    serializeJson(doc, payload);

    bool ok = _client.publish(topic.c_str(), 1, true, payload.c_str());
    Serial.printf("[MQTT] Discovery %s: %s\n", topic.c_str(), ok ? "OK" : "FAIL");
    return ok;
}

void MqttManager::subscribeTopics() {
    // Subscribe to relay command topics: {prefix}/relay/+/set
    String topic = _prefix + "/relay/+/set";
    _client.subscribe(topic.c_str(), 1);
    Serial.printf("[MQTT] Subscribed: %s\n", topic.c_str());
}

String MqttManager::buildTopic(const String& suffix) {
    return _prefix + "/" + suffix;
}
