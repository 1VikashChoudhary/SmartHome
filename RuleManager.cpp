/*
 * ============================================================================
 * RuleManager.cpp — Sensor-Based Automation Rule Engine Implementation
 * ============================================================================
 */

#include "RuleManager.h"
#include "SensorManager.h"

RuleManager::RuleManager()
    : _storage(nullptr), _ruleCount(0), _lastCheck(0) {
    memset(_rules, 0, sizeof(_rules));
}

void RuleManager::begin(StorageManager& storage) {
    _storage = &storage;
    loadRules();
    _lastCheck = millis();
    SERIAL_PRINTF("[Rule] Initialized with %d rule(s)\n", _ruleCount);
}

void RuleManager::loop(SensorManager& sensorMgr, RelayManager& relayMgr) {
    unsigned long now = millis();
    if (now - _lastCheck < 1000) return; // Evaluate every 1 second
    _lastCheck = now;

    for (uint8_t i = 0; i < _ruleCount; i++) {
        AutomationRule& r = _rules[i];
        if (!r.enabled) continue;

        float val = 0.0f;
        if (!readSensorValue(sensorMgr, r.sensor, r.sensorIndex, val) || isnan(val)) {
            continue;
        }

        if (r.condition == RULE_COND_ABOVE) {
            if (!r.triggered) {
                if (val >= r.threshold) {
                    r.triggered = true;
                    bool state = (r.action == RULE_ACT_RELAY_ON);
                    if (r.targetRelay == 0xFF) {
                        if (state) relayMgr.allOn(); else relayMgr.allOff();
                    } else if (r.targetRelay < MAX_RELAYS) {
                        relayMgr.setState(r.targetRelay, state);
                    }
                    SERIAL_PRINTF("[Rule] Fired rule %d ('%s' s#%d): val=%.1f >= th=%.1f -> Relay %d %s\n",
                                  r.id, r.name, (int)r.sensorIndex + 1, val, r.threshold, r.targetRelay + 1, state ? "ON" : "OFF");
                }
            } else {
                // Anti-flapping hysteresis to reset latch
                float resetTh = r.threshold - r.hysteresis;
                if (val < resetTh) {
                    r.triggered = false;
                    SERIAL_PRINTF("[Rule] Rearmed rule %d ('%s'): val=%.1f < reset=%.1f\n",
                                  r.id, r.name, val, resetTh);
                }
            }
        } else { // RULE_COND_BELOW
            if (!r.triggered) {
                if (val <= r.threshold) {
                    r.triggered = true;
                    bool state = (r.action == RULE_ACT_RELAY_ON);
                    if (r.targetRelay == 0xFF) {
                        if (state) relayMgr.allOn(); else relayMgr.allOff();
                    } else if (r.targetRelay < MAX_RELAYS) {
                        relayMgr.setState(r.targetRelay, state);
                    }
                    SERIAL_PRINTF("[Rule] Fired rule %d ('%s' s#%d): val=%.1f <= th=%.1f -> Relay %d %s\n",
                                  r.id, r.name, (int)r.sensorIndex + 1, val, r.threshold, r.targetRelay + 1, state ? "ON" : "OFF");
                }
            } else {
                // Anti-flapping hysteresis to reset latch
                float resetTh = r.threshold + r.hysteresis;
                if (val > resetTh) {
                    r.triggered = false;
                    SERIAL_PRINTF("[Rule] Rearmed rule %d ('%s'): val=%.1f > reset=%.1f\n",
                                  r.id, r.name, val, resetTh);
                }
            }
        }
    }
}

bool RuleManager::readSensorValue(SensorManager& sensorMgr, RuleSensorType sensor, uint8_t idx, float& outVal) {
    switch (sensor) {
        case RULE_SENSOR_TEMP:
            if (!sensorMgr.isClimateActiveAt(idx) || sensorMgr.isClimateFaultAt(idx)) return false;
            outVal = sensorMgr.getTemperatureAt(idx);
            return true;
        case RULE_SENSOR_HUM:
            if (!sensorMgr.isClimateActiveAt(idx) || sensorMgr.isClimateFaultAt(idx) || !sensorMgr.hasHumidityAt(idx)) return false;
            outVal = sensorMgr.getHumidityAt(idx);
            return true;
        case RULE_SENSOR_GAS:
            if (!sensorMgr.isMq2ActiveAt(idx) || sensorMgr.isMq2WarmingAt(idx)) return false;
            outVal = (float)sensorMgr.getMQ2RawAt(idx);
            return true;
        case RULE_SENSOR_LUX:
            if (!sensorMgr.isLightActiveAt(idx)) return false;
            outVal = sensorMgr.getLuxAt(idx);
            return true;
        case RULE_SENSOR_PROBE_TEMP: {
            if (!sensorMgr.isProbeActiveAt(idx) || sensorMgr.isProbeFaultAt(idx)) return false;
            float p = sensorMgr.getProbeTemperatureAt(idx);
            if (p < -55.0f) return false;
            outVal = p;
            return true;
        }
        case RULE_SENSOR_TANK_LEVEL:
            if (!sensorMgr.isUltrasonicActiveAt(idx)) return false;
            outVal = (float)sensorMgr.getTankLevelPercentAt(idx);
            return true;
        case RULE_SENSOR_MOTION:
            if (!sensorMgr.isMotionActiveAt(idx)) return false;
            outVal = sensorMgr.isMotionDetectedAt(idx) ? 1.0f : 0.0f;
            return true;
        default:
            return false;
    }
}

bool RuleManager::addRule(const AutomationRule& rule) {
    if (_ruleCount >= MAX_SENSOR_RULES) return false;

    _rules[_ruleCount] = rule;
    if (_rules[_ruleCount].id == 0) {
        _rules[_ruleCount].id = getNextId();
    }
    _rules[_ruleCount].triggered = false;
    _ruleCount++;
    save();
    return true;
}

bool RuleManager::updateRule(uint8_t id, const AutomationRule& rule) {
    int idx = findRuleIndex(id);
    if (idx < 0) return false;

    _rules[idx] = rule;
    _rules[idx].id = id;
    _rules[idx].triggered = false;
    save();
    return true;
}

bool RuleManager::deleteRule(uint8_t id) {
    int idx = findRuleIndex(id);
    if (idx < 0) return false;

    for (uint8_t i = idx; i < _ruleCount - 1; i++) {
        _rules[i] = _rules[i + 1];
    }
    _ruleCount--;
    save();
    return true;
}

bool RuleManager::enableRule(uint8_t id, bool enabled) {
    int idx = findRuleIndex(id);
    if (idx < 0) return false;

    _rules[idx].enabled = enabled;
    _rules[idx].triggered = false;
    save();
    return true;
}

const AutomationRule* RuleManager::getRule(uint8_t id) {
    int idx = findRuleIndex(id);
    if (idx < 0) return nullptr;
    return &_rules[idx];
}

String RuleManager::getActiveRuleForRelay(uint8_t relayIdx) const {
    for (uint8_t i = 0; i < _ruleCount; i++) {
        const AutomationRule& r = _rules[i];
        if (r.enabled && r.triggered && (r.targetRelay == relayIdx || r.targetRelay == 0xFF)) {
            return String(r.name);
        }
    }
    return "";
}

uint8_t RuleManager::getRuleCount() {
    return _ruleCount;
}

uint8_t RuleManager::getNextId() {
    uint8_t maxId = 0;
    for (uint8_t i = 0; i < _ruleCount; i++) {
        if (_rules[i].id > maxId) maxId = _rules[i].id;
    }
    return maxId + 1;
}

void RuleManager::save() {
    if (!_storage) return;

    JsonDocument doc;
    JsonArray arr = doc["rules"].to<JsonArray>();
    toJson(arr);

    _storage->saveJson(PATH_RULES, doc);
}

void RuleManager::toJson(JsonArray& arr) {
    for (uint8_t i = 0; i < _ruleCount; i++) {
        const AutomationRule& r = _rules[i];
        JsonObject obj = arr.add<JsonObject>();
        obj["id"]     = r.id;
        obj["en"]     = r.enabled;
        obj["name"]   = r.name;
        obj["sensor"] = (uint8_t)r.sensor;
        obj["s_idx"]  = r.sensorIndex;
        obj["cond"]   = (uint8_t)r.condition;
        obj["th"]     = r.threshold;
        obj["hyst"]   = r.hysteresis;
        obj["relay"]  = r.targetRelay;
        obj["act"]    = (uint8_t)r.action;
        obj["trig"]   = r.triggered;
    }
}

bool RuleManager::fromJson(const JsonObject& obj, AutomationRule& rule) {
    rule.id          = obj["id"] | 0;
    rule.enabled     = obj["en"] | true;
    const char* nm   = obj["name"] | "Rule";
    strncpy(rule.name, nm, sizeof(rule.name) - 1);
    rule.name[sizeof(rule.name) - 1] = '\0';
    rule.sensor      = (RuleSensorType)(uint8_t)(obj["sensor"] | 0);
    uint8_t sIdx     = obj.containsKey("s_idx") ? (uint8_t)(obj["s_idx"] | 0) : (uint8_t)(obj["sensor_index"] | 0);
    rule.sensorIndex = sIdx;
    rule.condition   = (RuleCondition)(uint8_t)(obj["cond"] | 0);
    rule.threshold   = obj["th"] | 0.0f;
    float defaultHyst = 0.5f;
    if (rule.sensor == RULE_SENSOR_HUM) defaultHyst = 2.0f;
    else if (rule.sensor == RULE_SENSOR_GAS) defaultHyst = 30.0f;
    else if (rule.sensor == RULE_SENSOR_LUX) defaultHyst = 15.0f;
    else if (rule.sensor == RULE_SENSOR_TANK_LEVEL) defaultHyst = 3.0f;
    else if (rule.sensor == RULE_SENSOR_MOTION) defaultHyst = 0.5f;
    rule.hysteresis  = obj["hyst"] | defaultHyst;
    rule.targetRelay = obj["relay"] | 0;
    rule.action      = (RuleActionType)(uint8_t)(obj["act"] | 0);
    rule.triggered   = false;

    // Validate
    if (rule.sensor > RULE_SENSOR_MOTION) return false;
    uint8_t maxIdx = 1;
    switch (rule.sensor) {
        case RULE_SENSOR_TEMP:
        case RULE_SENSOR_HUM:        maxIdx = MAX_CLIMATE_SENSORS; break;
        case RULE_SENSOR_GAS:        maxIdx = MAX_MQ2_SENSORS; break;
        case RULE_SENSOR_LUX:        maxIdx = MAX_LIGHT_SENSORS; break;
        case RULE_SENSOR_PROBE_TEMP: maxIdx = MAX_PROBE_SENSORS; break;
        case RULE_SENSOR_TANK_LEVEL: maxIdx = MAX_ULTRASONIC_SENSORS; break;
        case RULE_SENSOR_MOTION:     maxIdx = MAX_MOTION_SENSORS; break;
        default: break;
    }
    if (rule.sensorIndex >= maxIdx) return false;
    if (rule.condition > RULE_COND_BELOW) return false;
    if (rule.action > RULE_ACT_RELAY_OFF) return false;
    if (rule.targetRelay >= MAX_RELAYS && rule.targetRelay != 0xFF) return false;
    return true;
}

void RuleManager::loadRules() {
    _ruleCount = 0;
    if (!_storage) return;

    JsonDocument doc;
    if (!_storage->loadJson(PATH_RULES, doc)) return;

    JsonArray arr = doc["rules"].as<JsonArray>();
    for (JsonObject obj : arr) {
        if (_ruleCount >= MAX_SENSOR_RULES) break;
        if (fromJson(obj, _rules[_ruleCount])) {
            _ruleCount++;
        }
    }
}

int RuleManager::findRuleIndex(uint8_t id) {
    for (uint8_t i = 0; i < _ruleCount; i++) {
        if (_rules[i].id == id) return i;
    }
    return -1;
}
