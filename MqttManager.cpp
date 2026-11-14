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
#include "SensorManager.h"

MqttManager* MqttManager::_instance = nullptr;

MqttManager::MqttManager()
    : _storage(nullptr), _logger(nullptr), _enabled(false),
      _suspended(false), _port(MQTT_DEFAULT_PORT),
      _wasConnected(false), _connectInProgress(false), _lastReconnectAttempt(0),
      _reconnectInterval(MQTT_RECONNECT_BASE), _connectStartedAt(0),
      _lastPublish(0), _relayCallback(nullptr) {
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
        SERIAL_PRINTF("[MQTT] Configured: %s:%d prefix=%s client_id=%s user=%s (pass_len=%d)\n",
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
        SERIAL_PRINTF("[MQTT] Connect attempt timed out after %lu ms; resetting client state\n",
                      now - _connectStartedAt);
        _lastError = F("Connection timed out");
        _connectInProgress = false;
        _client.disconnect();
    }

    // Auto-reconnect with exponential backoff
    if (!_client.connected() && !_connectInProgress &&
        (now - _lastReconnectAttempt >= _reconnectInterval)) {
        _lastReconnectAttempt = now;
        SERIAL_PRINTF("[MQTT] Reconnecting to %s:%d (interval: %lums)...\n", _broker.c_str(), _port, _reconnectInterval);
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
    if (!_enabled) {
        _lastError = F("Disabled");
        disconnect();
    } else if (_broker.length() > 0) {
        applyClientConfig();
        _reconnectInterval = MQTT_RECONNECT_BASE;
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

static String indexedTopic(const char* base, uint8_t idx) {
    if (idx == 0) return String(base);
    return String(base) + "_" + String(idx + 1);
}

void MqttManager::publishSensorData(SensorManager& sensorMgr) {
    if (!_client.connected()) return;

    unsigned long now = millis();
    if (now - _lastPublish < MQTT_PUBLISH_INTERVAL) return;
    _lastPublish = now;

    char buf[16];

    // Climate Sensors (Temperature, Humidity, optional BME280 Pressure)
    for (uint8_t i = 0; i < sensorMgr.getClimateCount(); i++) {
        if (!sensorMgr.isClimateActiveAt(i)) continue;
        dtostrf(sensorMgr.getTemperatureAt(i), 1, 1, buf);
        _client.publish(buildTopic(indexedTopic("sensor/temperature", i)).c_str(), 0, false, buf);

        dtostrf(sensorMgr.getHumidityAt(i), 1, 1, buf);
        _client.publish(buildTopic(indexedTopic("sensor/humidity", i)).c_str(), 0, false, buf);

        if (sensorMgr.hasBarometerAt(i)) {
            float pres = sensorMgr.getPressureAt(i);
            if (pres > 300.0f) {
                dtostrf(pres, 1, 1, buf);
                _client.publish(buildTopic(indexedTopic("sensor/pressure", i)).c_str(), 0, false, buf);
            }
        }
    }

    // MQ-2 Gas Sensors
    for (uint8_t i = 0; i < sensorMgr.getMq2Count(); i++) {
        if (!sensorMgr.isMq2ActiveAt(i)) continue;
        itoa(sensorMgr.getMQ2RawAt(i), buf, 10);
        _client.publish(buildTopic(indexedTopic("sensor/gas", i)).c_str(), 0, false, buf);

        _client.publish(buildTopic(indexedTopic("sensor/gas_alarm", i)).c_str(), 0, false,
                        sensorMgr.isMQ2AlarmAt(i) ? "danger" : "safe");
    }

    // BH1750 Ambient Light Sensors
    for (uint8_t i = 0; i < sensorMgr.getLightCount(); i++) {
        if (!sensorMgr.isLightActiveAt(i)) continue;
        dtostrf(sensorMgr.getLuxAt(i), 1, 1, buf);
        _client.publish(buildTopic(indexedTopic("sensor/illuminance", i)).c_str(), 0, false, buf);
    }

    // Motion / Occupancy Sensors
    for (uint8_t i = 0; i < sensorMgr.getMotionCount(); i++) {
        if (!sensorMgr.isMotionActiveAt(i)) continue;
        _client.publish(buildTopic(indexedTopic("binary_sensor/motion", i)).c_str(), 0, false,
                        sensorMgr.isMotionDetectedAt(i) ? "ON" : "OFF");
    }

    // Water Temp Probes (DS18B20)
    for (uint8_t i = 0; i < sensorMgr.getProbeCount(); i++) {
        if (!sensorMgr.isProbeActiveAt(i) || sensorMgr.isProbeFaultAt(i)) continue;
        float pt = sensorMgr.getProbeTemperatureAt(i);
        if (pt > -55.0f && pt < 130.0f) {
            dtostrf(pt, 1, 1, buf);
            _client.publish(buildTopic(indexedTopic("sensor/water_temp", i)).c_str(), 0, false, buf);
        }
    }

    // Ultrasonic Tank Level & Distance Sensors
    for (uint8_t i = 0; i < sensorMgr.getUltrasonicCount(); i++) {
        if (!sensorMgr.isUltrasonicActiveAt(i)) continue;
        itoa(sensorMgr.getTankLevelPercentAt(i), buf, 10);
        _client.publish(buildTopic(indexedTopic("sensor/tank_level", i)).c_str(), 0, false, buf);

        float distCm = sensorMgr.getDistanceCmAt(i);
        if (distCm >= 0.0f) {
            dtostrf(distCm, 1, 1, buf);
            _client.publish(buildTopic(indexedTopic("sensor/distance", i)).c_str(), 0, false, buf);
        }
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

void MqttManager::publishHaSensorEntity(const char* component, const String& objSuffix, const String& name,
                                        const String& statTopicSuffix, const char* unit, const char* devClass,
                                        const char* icon, const char* plOn, const char* plOff,
                                        const String& deviceId, const String& deviceName,
                                        const String& availabilityTopic, bool enabled) {
    String cfgTopic = "homeassistant/" + String(component) + "/" + deviceId + "/" + objSuffix + "/config";
    if (!enabled) {
        _client.publish(cfgTopic.c_str(), 0, true, "");
        return;
    }

    JsonDocument doc;
    doc["name"] = name;
    doc["uniq_id"] = deviceId + "_" + objSuffix;
    doc["obj_id"] = deviceId + "_" + objSuffix;
    doc["stat_t"] = buildTopic(statTopicSuffix);
    doc["avty_t"] = availabilityTopic;
    doc["pl_avail"] = "online";
    doc["pl_not_avail"] = "offline";
    if (unit && unit[0])     doc["unit_of_meas"] = unit;
    if (devClass && devClass[0]) doc["dev_cla"] = devClass;
    if (strcmp(component, "sensor") == 0) doc["stat_cla"] = "measurement";
    if (icon && icon[0])     doc["icon"] = icon;
    if (plOn && plOn[0])     doc["pl_on"] = plOn;
    if (plOff && plOff[0])   doc["pl_off"] = plOff;

    JsonObject device = doc["dev"].to<JsonObject>();
    addDeviceInfo(device);
    device["name"] = deviceName;
    publishDiscoveryConfig(cfgTopic, doc);
}

void MqttManager::publishHomeAssistantDiscovery() {
    if (!_client.connected()) return;

    const String deviceId = getDeviceId();
    const String deviceName = getDeviceName();
    const String availabilityTopic = buildTopic("status");

    JsonDocument relayDoc;
    JsonArray relays;
    uint8_t relayCount = NUM_RELAYS;

    bool climateEn[MAX_CLIMATE_SENSORS]    = {false};
    bool bmeEn[MAX_CLIMATE_SENSORS]        = {false};
    bool lightEn[MAX_LIGHT_SENSORS]        = {false};
    bool motionEn[MAX_MOTION_SENSORS]      = {false};
    bool probeEn[MAX_PROBE_SENSORS]        = {false};
    bool tankEn[MAX_ULTRASONIC_SENSORS]    = {false};
    bool mq2En[MAX_MQ2_SENSORS]            = {false};

#if !defined(ESP8266)
    climateEn[0] = true;
#endif
    mq2En[0] = true;

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

            if (hwDoc.containsKey("climates")) {
                memset(climateEn, 0, sizeof(climateEn));
                JsonArray arr = hwDoc["climates"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS && i < arr.size(); i++) {
                    uint8_t dt = arr[i]["type"] | 0;
                    climateEn[i] = (dt != 0);
                    bmeEn[i] = (dt == 3);
                }
            } else if (hwDoc.containsKey("dht")) {
                uint8_t dt = hwDoc["dht"]["type"] | 2;
                climateEn[0] = (dt != 0);
                bmeEn[0] = (dt == 3);
            }

            if (hwDoc.containsKey("lights")) {
                JsonArray arr = hwDoc["lights"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_LIGHT_SENSORS && i < arr.size(); i++) {
                    lightEn[i] = ((arr[i]["type"] | 0) != 0);
                }
            } else if (hwDoc.containsKey("light")) {
                lightEn[0] = ((hwDoc["light"]["type"] | 0) != 0);
            }

            if (hwDoc.containsKey("motions")) {
                JsonArray arr = hwDoc["motions"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_MOTION_SENSORS && i < arr.size(); i++) {
                    motionEn[i] = ((arr[i]["type"] | 0) != 0);
                }
            } else if (hwDoc.containsKey("motion")) {
                motionEn[0] = ((hwDoc["motion"]["type"] | 0) != 0);
            }

            if (hwDoc.containsKey("probes")) {
                JsonArray arr = hwDoc["probes"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_PROBE_SENSORS && i < arr.size(); i++) {
                    probeEn[i] = ((arr[i]["type"] | 0) != 0);
                }
            } else if (hwDoc.containsKey("probe")) {
                probeEn[0] = ((hwDoc["probe"]["type"] | 0) != 0);
            }

            if (hwDoc.containsKey("ultrasonics")) {
                JsonArray arr = hwDoc["ultrasonics"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_ULTRASONIC_SENSORS && i < arr.size(); i++) {
                    tankEn[i] = ((arr[i]["type"] | 0) != 0);
                }
            } else if (hwDoc.containsKey("ultrasonic")) {
                tankEn[0] = ((hwDoc["ultrasonic"]["type"] | 0) != 0);
            }

            if (hwDoc.containsKey("mq2_sensors")) {
                memset(mq2En, 0, sizeof(mq2En));
                JsonArray arr = hwDoc["mq2_sensors"].as<JsonArray>();
                for (uint8_t i = 0; i < MAX_MQ2_SENSORS && i < arr.size(); i++) {
                    mq2En[i] = arr[i]["enabled"] | true;
                }
            } else if (hwDoc.containsKey("mq2")) {
                mq2En[0] = hwDoc["mq2"]["enabled"] | true;
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
    for (uint8_t i = relayCount; i < MAX_RELAYS; i++) {
        publishHomeAssistantDiscoveryRemove(i);
    }

    auto slotTitle = [](const char* base, uint8_t i) -> String {
        return (i == 0) ? String(base) : (String(base) + " " + String(i + 1));
    };

    for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS; i++) {
        publishHaSensorEntity("sensor", indexedTopic("temperature", i), slotTitle("Temperature", i),
                              indexedTopic("sensor/temperature", i), "\xC2\xB0""C", "temperature",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, climateEn[i]);
        publishHaSensorEntity("sensor", indexedTopic("humidity", i), slotTitle("Humidity", i),
                              indexedTopic("sensor/humidity", i), "%", "humidity",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, climateEn[i]);
        publishHaSensorEntity("sensor", indexedTopic("pressure", i), slotTitle("Barometric Pressure", i),
                              indexedTopic("sensor/pressure", i), "hPa", "atmospheric_pressure",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, bmeEn[i]);
    }

    for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
        publishHaSensorEntity("sensor", indexedTopic("gas", i), slotTitle("Gas Level", i),
                              indexedTopic("sensor/gas", i), "raw", nullptr,
                              "mdi:molecule-co", nullptr, nullptr, deviceId, deviceName, availabilityTopic, mq2En[i]);
        publishHaSensorEntity("binary_sensor", indexedTopic("gas_alarm", i), slotTitle("Gas Alarm", i),
                              indexedTopic("sensor/gas_alarm", i), nullptr, "gas",
                              nullptr, "danger", "safe", deviceId, deviceName, availabilityTopic, mq2En[i]);
    }

    for (uint8_t i = 0; i < MAX_LIGHT_SENSORS; i++) {
        publishHaSensorEntity("sensor", indexedTopic("lux", i), slotTitle("Ambient Light", i),
                              indexedTopic("sensor/illuminance", i), "lx", "illuminance",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, lightEn[i]);
    }

    for (uint8_t i = 0; i < MAX_MOTION_SENSORS; i++) {
        publishHaSensorEntity("binary_sensor", indexedTopic("motion", i), slotTitle("Motion Occupancy", i),
                              indexedTopic("binary_sensor/motion", i), nullptr, "motion",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, motionEn[i]);
    }

    for (uint8_t i = 0; i < MAX_PROBE_SENSORS; i++) {
        publishHaSensorEntity("sensor", indexedTopic("water_temp", i), slotTitle("Water Temperature", i),
                              indexedTopic("sensor/water_temp", i), "\xC2\xB0""C", "temperature",
                              nullptr, nullptr, nullptr, deviceId, deviceName, availabilityTopic, probeEn[i]);
    }

    for (uint8_t i = 0; i < MAX_ULTRASONIC_SENSORS; i++) {
        publishHaSensorEntity("sensor", indexedTopic("tank_level", i), slotTitle("Water Tank Level", i),
                              indexedTopic("sensor/tank_level", i), "%", nullptr,
                              "mdi:water-percent", nullptr, nullptr, deviceId, deviceName, availabilityTopic, tankEn[i]);
        publishHaSensorEntity("sensor", indexedTopic("distance", i), slotTitle("Ultrasonic Distance", i),
                              indexedTopic("sensor/distance", i), "cm", "distance",
                              "mdi:ruler", nullptr, nullptr, deviceId, deviceName, availabilityTopic, tankEn[i]);
    }
}

void MqttManager::publishHomeAssistantDiscoveryRemove(uint8_t index) {
    if (!_client.connected()) return;
    String deviceId = getDeviceId();
    String topic = "homeassistant/switch/" + deviceId + "/relay_" + String(index + 1) + "/config";
    _client.publish(topic.c_str(), 1, true, "");
    SERIAL_PRINTF("[MQTT] Sent discovery remove for relay %d\n", index + 1);
}

void MqttManager::publishInitialStates() {
    if (!_client.connected() || !_storage) return;

    uint8_t relayCount = MAX_RELAYS;
    JsonDocument hwDoc;
    if (_storage->loadJson(PATH_HARDWARE, hwDoc)) {
        relayCount = hwDoc["num_relays"] | MAX_RELAYS;
    }
    if (relayCount > MAX_RELAYS) relayCount = MAX_RELAYS;

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
        snprintf(defaultId, sizeof(defaultId), "smarthome-%04X", (unsigned int)chipId);
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
        SERIAL_PRINTF("[MQTT] Configured: %s:%d prefix=%s client_id=%s user=%s (pass_len=%d)\n",
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
    SERIAL_PRINTF("[MQTT] Disconnected (reason: %d)\n", (int)reason);
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
    // Null-terminate payload (64 bytes supports both raw tokens and JSON command payloads)
    char payloadBuf[64];
    size_t copyLen = min(len, sizeof(payloadBuf) - 1);
    if (copyLen > 0 && payload) {
        memcpy(payloadBuf, payload, copyLen);
    }
    payloadBuf[copyLen] = '\0';

    String topicStr = String(topic);
    String payloadStr = String(payloadBuf);
    payloadStr.trim();

    SERIAL_PRINTF("[MQTT] Received: %s = %s\n", topic, payloadBuf);

    if (payloadStr.startsWith("{")) {
        JsonDocument cmdDoc;
        if (!deserializeJson(cmdDoc, payloadStr)) {
            if (cmdDoc["state"].is<const char*>()) {
                payloadStr = cmdDoc["state"].as<String>();
            } else if (cmdDoc["state"].is<int>()) {
                payloadStr = String(cmdDoc["state"].as<int>());
            } else if (cmdDoc["action"].is<const char*>()) {
                payloadStr = cmdDoc["action"].as<String>();
            } else if (cmdDoc["action"].is<int>()) {
                payloadStr = String(cmdDoc["action"].as<int>());
            } else {
                payloadStr = "";
            }
            payloadStr.trim();
        }
    }

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
    snprintf(defaultId, sizeof(defaultId), "smarthome-%04X", (unsigned int)chipId);
    _clientId = String(defaultId);

    if (!_storage) return;
    JsonDocument doc;
    if (!_storage->loadJson(PATH_MQTT, doc)) return;

    _enabled   = doc["enabled"] | false;
    _broker    = doc["broker"] | "";
    _broker.trim();
    _port      = doc["port"] | MQTT_DEFAULT_PORT;
    _user      = doc["user"] | "";
    _user.trim();
    _pass      = doc["pass"] | "";
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
    SERIAL_PRINTF("[MQTT] Discovery %s: %s\n", topic.c_str(), ok ? "OK" : "FAIL");
    return ok;
}

void MqttManager::subscribeTopics() {
    // Subscribe to relay command topics: {prefix}/relay/+/set
    String topic = _prefix + "/relay/+/set";
    _client.subscribe(topic.c_str(), 1);
    SERIAL_PRINTF("[MQTT] Subscribed: %s\n", topic.c_str());
}

String MqttManager::buildTopic(const String& suffix) {
    return _prefix + "/" + suffix;
}
