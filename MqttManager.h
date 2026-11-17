/*
 * ============================================================================
 * MqttManager.h — Async MQTT Client with Home Assistant Support
 * ============================================================================
 */

#ifndef MQTT_MANAGER_H
#define MQTT_MANAGER_H

#include <Arduino.h>
#include <AsyncMqttClient.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

class EventLogger;
class SensorManager;

class MqttManager {
public:
    MqttManager();

    void begin(StorageManager& storage, EventLogger& logger);
    void loop();

    void connect();
    void disconnect();
    void suspend();
    void resume();
    bool isConnected();
    bool isEnabled();
    void setEnabled(bool enabled);
    String getStateString();

    // Publishing
    void publishRelayState(uint8_t index, bool state);
    void publishSensorData(SensorManager& sensorMgr);
    void publishAlarmEvent(const char* alarmType, bool active, const char* summary = nullptr, bool anyHazardActive = false);
    void publishDiagnostics(const String& json);
    void publishAvailability(bool online);
    void publishHomeAssistantDiscovery(bool allowYield = false);
    void publishHomeAssistantDiscoveryRemove(uint8_t index);
    void publishInitialStates();

    // Config
    void saveConfig(const String& broker, uint16_t port,
                    const String& user, const String& pass,
                    const String& clientId, const String& prefix);
    String getBroker();
    uint16_t getPort();
    String getPrefix();
    String getUser();
    // Server-side only. Never serialize this value to the web/app API.
    String getPassword();
    void toJson(JsonObject& obj);

    // Relay command callback
    void setRelayCallback(void (*cb)(uint8_t index, bool state));

private:
    AsyncMqttClient _client;
    StorageManager* _storage;
    EventLogger* _logger;

    bool _enabled;
    bool _suspended;
    String _broker;
    uint16_t _port;
    String _user;
    String _pass;
    String _clientId;
    String _prefix;
    String _willTopic;

    // Reconnect state
    bool _wasConnected;
    bool _connectInProgress;
    bool _pendingBirthSync;
    unsigned long _lastReconnectAttempt;
    unsigned long _reconnectInterval;
    unsigned long _connectStartedAt;
    unsigned long _birthSyncReadyAt;

    // Publish timing
    unsigned long _lastPublish;

    // Diagnostics
    String _lastError;

    // Callbacks
    void (*_relayCallback)(uint8_t, bool);

    // Event handlers
    void onConnect(bool sessionPresent);
    void onDisconnect(AsyncMqttClientDisconnectReason reason);
    void onMessage(char* topic, char* payload, AsyncMqttClientMessageProperties properties,
                   size_t len, size_t index, size_t total);

    static MqttManager* _instance;
    static void _onConnect(bool sp);
    static void _onDisconnect(AsyncMqttClientDisconnectReason r);
    static void _onMessage(char* t, char* p, AsyncMqttClientMessageProperties pr,
                           size_t l, size_t i, size_t tot);

    void loadConfig();
    void applyClientConfig();
    static String defaultDeviceSlug();
    String getDeviceId();
    String getDeviceName();
    void addDeviceInfo(JsonObject& device, const String& deviceId, const String& deviceName);
    bool publishDiscoveryConfig(const String& topic, JsonDocument& doc);
    void publishHaSensorEntity(const char* component, const String& objSuffix, const String& name,
                               const String& statTopicSuffix, const char* unit, const char* devClass,
                               const char* icon, const char* plOn, const char* plOff,
                               const String& deviceId, const String& deviceName,
                               const String& availabilityTopic, bool enabled);
    void subscribeTopics();
    String buildTopic(const String& suffix);
};

#endif // MQTT_MANAGER_H
