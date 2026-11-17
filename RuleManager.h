/*
 * ============================================================================
 * RuleManager.h — Sensor-Based Automation Rule Engine
 * ============================================================================
 * 
 * Evaluates user-defined rules on sensor readings (DHT22 Temp/Humidity, MQ2 Gas)
 * to automatically trigger relays ON/OFF with built-in anti-flapping hysteresis.
 * ============================================================================
 */

#ifndef RULE_MANAGER_H
#define RULE_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#if defined(ESP32)
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#endif
#include "Config.h"
#include "StorageManager.h"
#include "RelayManager.h"

class SensorManager;

enum RuleSensorType : uint8_t {
    RULE_SENSOR_TEMP        = 0,    // Temperature (°C)
    RULE_SENSOR_HUM         = 1,    // Humidity (%)
    RULE_SENSOR_GAS         = 2,    // Gas MQ2 (Raw ADC)
    RULE_SENSOR_LUX         = 3,    // Ambient Light (Lux)
    RULE_SENSOR_PROBE_TEMP  = 4,    // Water Temp Probe (°C)
    RULE_SENSOR_TANK_LEVEL  = 5,    // Tank Level (%)
    RULE_SENSOR_MOTION      = 6     // Motion Detected (1 = Active, 0 = Clear)
};

enum RuleCondition : uint8_t {
    RULE_COND_ABOVE = 0,     // Reading >= Threshold
    RULE_COND_BELOW = 1      // Reading <= Threshold
};

enum RuleActionType : uint8_t {
    RULE_ACT_RELAY_ON  = 0,
    RULE_ACT_RELAY_OFF = 1
};

struct AutomationRule {
    uint8_t id;
    bool enabled;
    char name[24];
    RuleSensorType sensor;
    uint8_t sensorIndex;     // 0-based instance index within sensor group
    RuleCondition condition;
    float threshold;
    float hysteresis;
    uint8_t targetRelay;     // 0-(MAX_RELAYS-1) for single relay, 0xFF for all
    RuleActionType action;
    bool triggered;          // True if rule has fired (latched to prevent re-firing)
};

class RuleManager {
public:
    RuleManager();

    void begin(StorageManager& storage);
    void loop(SensorManager& sensorMgr, RelayManager& relayMgr);

    bool addRule(const AutomationRule& rule);
    bool updateRule(uint8_t id, const AutomationRule& rule);
    bool deleteRule(uint8_t id);
    bool enableRule(uint8_t id, bool enabled);
    const AutomationRule* getRule(uint8_t id);
    String getActiveRuleForRelay(uint8_t relayIdx) const;
    uint8_t getRuleCount();
    uint8_t getNextId();

    void save();
    void toJson(JsonArray& arr);
    bool fromJson(const JsonObject& obj, AutomationRule& rule);

private:
    StorageManager* _storage;
    AutomationRule _rules[MAX_SENSOR_RULES];
    uint8_t _ruleCount;
    unsigned long _lastCheck;
#if defined(ESP32)
    mutable SemaphoreHandle_t _ruleMutex;
    void ensureMutex() const;
#endif

    void loadRules();
    int findRuleIndex(uint8_t id);
    static bool readSensorValue(SensorManager& sensorMgr, RuleSensorType sensor, uint8_t idx, float& outVal);
};

#endif // RULE_MANAGER_H
