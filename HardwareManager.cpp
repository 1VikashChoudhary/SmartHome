/*
 * ============================================================================
 * HardwareManager.cpp — Dynamic Hardware Profile & GPIO Template Engine
 * ============================================================================
 */

#include "HardwareManager.h"

#define PATH_HARDWARE_FILE "/hardware.json"

HardwareManager::HardwareManager()
    : _storage(nullptr) {
#if defined(ESP8266)
    setPresetESP8266_2CH(_config);
#else
    setPreset5CH(_config);
#endif
}

void HardwareManager::begin(StorageManager& storage) {
    _storage = &storage;
    if (!load()) {
#if defined(ESP8266)
        Serial.println(F("[Hardware] No hardware profile found, saving default ESP8266 2-CH profile"));
        setPresetESP8266_2CH(_config);
#else
        Serial.println(F("[Hardware] No hardware profile found, saving default 5-CH profile"));
        setPreset5CH(_config);
#endif
        save();
    }
    Serial.printf("[Hardware] Profile loaded: %s (%d relays, DHT:%d pin:%d, MQ2:%s pin:%d, LCD:%s, Buzzer:%s)\n",
                  _config.boardName, _config.numRelays,
                  (int)_config.dhtType, _config.dhtPin,
                  _config.mq2Enabled ? "YES" : "NO", _config.mq2AnalogPin,
                  _config.lcdEnabled ? "YES" : "NO",
                  _config.buzzerEnabled ? "YES" : "NO");
}

bool HardwareManager::isChannelEnabled(uint8_t ch) const {
    if (ch >= _config.numRelays) return false;
    return _config.channels[ch].enabled && (_config.channels[ch].relayPin != PIN_UNUSED);
}

bool HardwareManager::isSwitchEnabled(uint8_t ch) const {
    if (ch >= _config.numRelays) return false;
    return _config.channels[ch].enabled && _config.channels[ch].switchEnabled && (_config.channels[ch].switchPin != PIN_UNUSED);
}

uint8_t HardwareManager::getRelayPin(uint8_t ch) const {
    if (!isChannelEnabled(ch)) return PIN_UNUSED;
    return _config.channels[ch].relayPin;
}

uint8_t HardwareManager::getSwitchPin(uint8_t ch) const {
    if (!isSwitchEnabled(ch)) return PIN_UNUSED;
    return _config.channels[ch].switchPin;
}

SwitchMode HardwareManager::getSwitchMode(uint8_t ch) const {
    if (ch >= _config.numRelays) return SWITCH_MODE_TOGGLE;
    return _config.channels[ch].switchMode;
}

TriggerMode HardwareManager::getTriggerMode(uint8_t ch) const {
    if (ch >= _config.numRelays) return TRIGGER_ACTIVE_LOW;
    return _config.channels[ch].triggerMode;
}

void HardwareManager::resetToDefault() {
#if defined(ESP8266)
    setPresetESP8266_2CH(_config);
#else
    setPreset5CH(_config);
#endif
    save();
}

bool HardwareManager::applyPreset(const String& presetName) {
    HardwareConfig newCfg;
#if defined(ESP8266)
    if (presetName.equalsIgnoreCase("SmartHome ESP8266 2-CH Dual") || presetName.equalsIgnoreCase("2ch") || presetName.equalsIgnoreCase("default") || presetName.equalsIgnoreCase("SmartHome 2-CH Dual") || presetName.equalsIgnoreCase("SmartHome 5-CH Standard") || presetName.equalsIgnoreCase("5ch") || presetName.equalsIgnoreCase("SmartHome 4-CH Pro") || presetName.equalsIgnoreCase("4ch") || presetName.equalsIgnoreCase("SmartHome 8-CH Max") || presetName.equalsIgnoreCase("8ch")) {
        setPresetESP8266_2CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 1-CH Mini") || presetName.equalsIgnoreCase("1ch") || presetName.equalsIgnoreCase("smartplug") || presetName.equalsIgnoreCase("SmartHome 1-CH Mini")) {
        setPresetESP8266_1CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 3-CH Pro") || presetName.equalsIgnoreCase("3ch") || presetName.equalsIgnoreCase("SmartHome 3-CH Pro")) {
        setPresetESP8266_3CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 Sensor Node") || presetName.equalsIgnoreCase("0ch") || presetName.equalsIgnoreCase("sensor_node") || presetName.equalsIgnoreCase("SmartHome Sensor Node")) {
        setPresetESP8266_SensorNode(newCfg);
    } else {
        return false;
    }
#else
    if (presetName.equalsIgnoreCase("SmartHome 5-CH Standard") || presetName.equalsIgnoreCase("5ch") || presetName.equalsIgnoreCase("default")) {
        setPreset5CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome 1-CH Mini") || presetName.equalsIgnoreCase("1ch") || presetName.equalsIgnoreCase("smartplug")) {
        setPreset1CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome 2-CH Dual") || presetName.equalsIgnoreCase("2ch")) {
        setPreset2CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome 4-CH Pro") || presetName.equalsIgnoreCase("4ch")) {
        setPreset4CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome 8-CH Max") || presetName.equalsIgnoreCase("8ch")) {
        setPreset8CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome Sensor Node") || presetName.equalsIgnoreCase("0ch") || presetName.equalsIgnoreCase("sensor_node")) {
        setPresetSensorNode(newCfg);
    } else {
        return false;
    }
#endif

    _config = newCfg;
    return save();
}

// ============================================================================
// Pin Safety Rules for ESP32 & ESP8266
// ============================================================================
bool HardwareManager::isSafeOutputPin(uint8_t pin) {
    if (pin == PIN_UNUSED) return true;
#if defined(ESP8266)
    // Disallow SPI flash pins (6-11), UART0 (1, 3), and analog pin A0 (17)
    if (pin >= 6 && pin <= 11) return false;
    if (pin == 1 || pin == 3 || pin == 17) return false;
    // Allowed output pins: 0, 2, 4, 5, 12, 13, 14, 15, 16
    return (pin == 0 || pin == 2 || pin == 4 || pin == 5 ||
            pin == 12 || pin == 13 || pin == 14 || pin == 15 || pin == 16);
#else
    // Disallow SPI flash pins (6-11)
    if (pin >= 6 && pin <= 11) return false;
    // Disallow Input-Only pins (34, 35, 36, 39)
    if (pin == 34 || pin == 35 || pin == 36 || pin == 39) return false;
    // Disallow UART0 pins (1, 3) to protect serial monitor
    if (pin == 1 || pin == 3) return false;
    // Allowed output pins: 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33
    return (pin == 2 || pin == 4 || pin == 5 || pin == 12 || pin == 13 ||
            pin == 14 || pin == 15 || pin == 16 || pin == 17 || pin == 18 ||
            pin == 19 || pin == 21 || pin == 22 || pin == 23 || pin == 25 ||
            pin == 26 || pin == 27 || pin == 32 || pin == 33);
#endif
}

bool HardwareManager::isSafeInputPin(uint8_t pin) {
    if (pin == PIN_UNUSED) return true;
#if defined(ESP8266)
    // Disallow SPI flash pins (6-11), UART0 (1, 3)
    if (pin >= 6 && pin <= 11) return false;
    if (pin == 1 || pin == 3) return false;
    // Safe inputs: 0, 2, 4, 5, 12, 13, 14, 15, 16, 17(A0)
    return (pin == 0 || pin == 2 || pin == 4 || pin == 5 ||
            pin == 12 || pin == 13 || pin == 14 || pin == 15 || pin == 16 || pin == 17);
#else
    // Disallow SPI flash pins (6-11)
    if (pin >= 6 && pin <= 11) return false;
    // Disallow UART0 pins (1, 3)
    if (pin == 1 || pin == 3) return false;
    // Pins 34-39 are input only (no internal pullups, external pullup needed)
    // Pins 0, 2, 4, 5, 12-19, 21-23, 25-27, 32-39 are all valid inputs
    return (pin == 0 || pin == 2 || pin == 4 || pin == 5 || (pin >= 12 && pin <= 19) ||
            pin == 21 || pin == 22 || pin == 23 || (pin >= 25 && pin <= 27) ||
            (pin >= 32 && pin <= 36) || pin == 39);
#endif
}

bool HardwareManager::isAdc1Pin(uint8_t pin) {
    if (pin == PIN_UNUSED) return true;
#if defined(ESP8266)
    // ESP8266 has only A0 (GPIO 17 / A0)
    return (pin == 17 || pin == A0);
#else
    // ESP32 ADC1 channels: GPIO 32, 33, 34, 35, 36, 39
    return (pin == 32 || pin == 33 || pin == 34 || pin == 35 || pin == 36 || pin == 39);
#endif
}

// ============================================================================
// Comprehensive Hardware Pin Safety & Conflict Detector
// ============================================================================
bool HardwareManager::validateConfig(const HardwareConfig& cfg, String& outError) {
    if (cfg.numRelays > MAX_RELAYS) {
        outError = "Number of relays exceeds maximum limit (" + String(MAX_RELAYS) + ")";
        return false;
    }

    // Bitmap / tracker for assigned pins to detect conflicts (0..39)
    int8_t pinUsage[40];
    for (int i = 0; i < 40; i++) pinUsage[i] = -1;

    auto claimPin = [&](uint8_t pin, const char* component) -> bool {
        if (pin == PIN_UNUSED) return true;
        if (pin >= 40) {
            outError = String(component) + ": invalid GPIO " + String(pin);
            return false;
        }
#if defined(ESP8266)
        if (pin > 17) {
            outError = String(component) + ": invalid GPIO " + String(pin) + " (ESP8266 supports GPIO 0-16, A0/17)";
            return false;
        }
#endif
        if (pinUsage[pin] != -1) {
            outError = "GPIO conflict: Pin " + String(pin) + " assigned to multiple peripherals (" + String(component) + ")";
            return false;
        }
        pinUsage[pin] = 1;
        return true;
    };

    // 1. Relays
    for (uint8_t i = 0; i < cfg.numRelays; i++) {
        if (!cfg.channels[i].enabled) continue; // Disabled channel does not claim any pins

        uint8_t rPin = cfg.channels[i].relayPin;
        if (rPin != PIN_UNUSED) {
            if (!isSafeOutputPin(rPin)) {
                outError = "Relay " + String(i + 1) + ": GPIO " + String(rPin) + " cannot be used as an output (input-only or system pin)";
                return false;
            }
            if (!claimPin(rPin, ("Relay " + String(i + 1)).c_str())) return false;
        }

        if (cfg.channels[i].switchEnabled) {
            uint8_t sPin = cfg.channels[i].switchPin;
            if (sPin != PIN_UNUSED) {
                if (!isSafeInputPin(sPin)) {
                    outError = "Switch " + String(i + 1) + ": GPIO " + String(sPin) + " is not a valid input pin";
                    return false;
                }
                if (!claimPin(sPin, ("Switch " + String(i + 1)).c_str())) return false;
            }
        }
    }

    // 2. DHT Climate Sensor
    if ((cfg.dhtType == CLIMATE_DHT11 || cfg.dhtType == CLIMATE_DHT22) && cfg.dhtPin != PIN_UNUSED) {
        // DHT requires bidirectional open-drain, so input-only pins (34-39) are INVALID
        if (!isSafeOutputPin(cfg.dhtPin)) {
            outError = "DHT Climate Sensor: GPIO " + String(cfg.dhtPin) + " cannot be an input-only pin (requires bidirectional output)";
            return false;
        }
        if (!claimPin(cfg.dhtPin, "DHT Sensor")) return false;
    }
    // Note: CLIMATE_BME280, CLIMATE_AHT20, CLIMATE_SHT3X use shared I2C bus (i2cSdaPin/i2cSclPin)

    // 2b. Motion / Occupancy Sensor
    if (cfg.motionType != MOTION_NONE && cfg.motionPin != PIN_UNUSED) {
        if (!isSafeInputPin(cfg.motionPin)) {
            outError = "Motion Sensor: GPIO " + String(cfg.motionPin) + " is not a valid input pin";
            return false;
        }
        if (!claimPin(cfg.motionPin, "Motion Sensor")) return false;
    }

    // 2c. Submersible Water Temp Probe (DS18B20)
    if (cfg.probeType == PROBE_DS18B20 && cfg.probePin != PIN_UNUSED) {
        if (!isSafeOutputPin(cfg.probePin)) {
            outError = "DS18B20 Probe: GPIO " + String(cfg.probePin) + " cannot be an input-only pin";
            return false;
        }
        if (!claimPin(cfg.probePin, "DS18B20 Probe")) return false;
    }

    // 2d. Ultrasonic Distance & Water Tank Level Sensor
    if (cfg.ultrasonicType != ULTRASONIC_NONE) {
        if (cfg.trigPin != PIN_UNUSED) {
            if (!isSafeOutputPin(cfg.trigPin)) {
                outError = "Ultrasonic Trig: GPIO " + String(cfg.trigPin) + " cannot be an input-only pin";
                return false;
            }
            if (!claimPin(cfg.trigPin, "Ultrasonic Trig")) return false;
        }
        if (cfg.echoPin != PIN_UNUSED) {
            if (!isSafeInputPin(cfg.echoPin)) {
                outError = "Ultrasonic Echo: GPIO " + String(cfg.echoPin) + " is not a valid input pin";
                return false;
            }
            if (!claimPin(cfg.echoPin, "Ultrasonic Echo")) return false;
        }
    }

    // 3. MQ-2 Gas Sensor
    if (cfg.mq2Enabled) {
        if (cfg.mq2AnalogPin != PIN_UNUSED) {
            if (!isAdc1Pin(cfg.mq2AnalogPin)) {
#if defined(ESP8266)
                outError = "MQ-2 Analog: GPIO " + String(cfg.mq2AnalogPin) + " is not A0 (ESP8266 only has A0 / GPIO 17 for analog input).";
#else
                outError = "MQ-2 Analog: GPIO " + String(cfg.mq2AnalogPin) + " is not on ADC1 (ADC2 conflicts with Wi-Fi). Use GPIO 32-36 or 39.";
#endif
                return false;
            }
            if (!claimPin(cfg.mq2AnalogPin, "MQ2 Analog")) return false;
        }
        if (cfg.mq2DigitalPin != PIN_UNUSED) {
            if (!isSafeInputPin(cfg.mq2DigitalPin)) {
                outError = "MQ-2 Digital: GPIO " + String(cfg.mq2DigitalPin) + " is not a valid input pin";
                return false;
            }
            if (!claimPin(cfg.mq2DigitalPin, "MQ2 Digital")) return false;
        }
    }

    // 4. Buzzer
    if (cfg.buzzerEnabled && cfg.buzzerPin != PIN_UNUSED) {
        if (!isSafeOutputPin(cfg.buzzerPin)) {
            outError = "Buzzer: GPIO " + String(cfg.buzzerPin) + " cannot be used as an output (input-only or system pin)";
            return false;
        }
        if (!claimPin(cfg.buzzerPin, "Buzzer")) return false;
    }

    // 5. I2C Bus (LCD Display and/or I2C Sensors: BME280, AHT20, SHT31, BH1750)
    bool i2cActive = cfg.lcdEnabled || (cfg.dhtType >= CLIMATE_BME280) || (cfg.lightType == LIGHT_BH1750);
    if (i2cActive) {
        if (cfg.i2cSdaPin != PIN_UNUSED) {
            if (!isSafeOutputPin(cfg.i2cSdaPin)) {
                outError = "I2C SDA: GPIO " + String(cfg.i2cSdaPin) + " cannot be an input-only pin";
                return false;
            }
            if (!claimPin(cfg.i2cSdaPin, "I2C SDA")) return false;
        }
        if (cfg.i2cSclPin != PIN_UNUSED) {
            if (!isSafeOutputPin(cfg.i2cSclPin)) {
                outError = "I2C SCL: GPIO " + String(cfg.i2cSclPin) + " cannot be an input-only pin";
                return false;
            }
            if (!claimPin(cfg.i2cSclPin, "I2C SCL")) return false;
        }
    }

    // 6. Multi-function Button
    if (cfg.btnMultiPin != PIN_UNUSED) {
        if (!isSafeInputPin(cfg.btnMultiPin)) {
            outError = "Multi-function Button: GPIO " + String(cfg.btnMultiPin) + " is not a valid input pin";
            return false;
        }
        if (!claimPin(cfg.btnMultiPin, "Multi-Button")) return false;
    }

    return true;
}

// ============================================================================
// Serialization
// ============================================================================
void HardwareManager::toJson(JsonObject& obj) const {
    obj["board_name"] = _config.boardName;
    obj["num_relays"] = _config.numRelays;

    JsonArray relaysArr = obj["channels"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numRelays; i++) {
        JsonObject ch = relaysArr.add<JsonObject>();
        ch["enabled"]        = _config.channels[i].enabled;
        ch["relay_pin"]      = _config.channels[i].relayPin;
        ch["switch_enabled"] = _config.channels[i].switchEnabled;
        ch["switch_pin"]     = _config.channels[i].switchPin;
        ch["switch_mode"]    = (uint8_t)_config.channels[i].switchMode;
        ch["trigger"]        = (uint8_t)_config.channels[i].triggerMode;
    }

    JsonObject dht = obj["dht"].to<JsonObject>();
    dht["type"] = (uint8_t)_config.dhtType;
    dht["pin"]  = _config.dhtPin;

    JsonObject light = obj["light"].to<JsonObject>();
    light["type"] = (uint8_t)_config.lightType;

    JsonObject motion = obj["motion"].to<JsonObject>();
    motion["type"] = (uint8_t)_config.motionType;
    motion["pin"]  = _config.motionPin;

    JsonObject probe = obj["probe"].to<JsonObject>();
    probe["type"] = (uint8_t)_config.probeType;
    probe["pin"]  = _config.probePin;

    JsonObject ultrasonic = obj["ultrasonic"].to<JsonObject>();
    ultrasonic["type"]       = (uint8_t)_config.ultrasonicType;
    ultrasonic["trig_pin"]   = _config.trigPin;
    ultrasonic["echo_pin"]   = _config.echoPin;
    ultrasonic["tank_depth"] = _config.tankDepthCm;
    ultrasonic["air_gap"]    = _config.tankAirGapCm;

    JsonObject mq2 = obj["mq2"].to<JsonObject>();
    mq2["enabled"]    = _config.mq2Enabled;
    mq2["analog_pin"] = _config.mq2AnalogPin;
    mq2["digital_pin"] = _config.mq2DigitalPin;

    JsonObject buzzer = obj["buzzer"].to<JsonObject>();
    buzzer["enabled"] = _config.buzzerEnabled;
    buzzer["pin"]     = _config.buzzerPin;

    JsonObject lcd = obj["lcd"].to<JsonObject>();
    lcd["enabled"]  = _config.lcdEnabled;
    lcd["i2c_addr"] = _config.lcdI2cAddr;
    lcd["cols"]     = _config.lcdCols;
    lcd["rows"]     = _config.lcdRows;
    lcd["sda_pin"]  = _config.i2cSdaPin;
    lcd["scl_pin"]  = _config.i2cSclPin;

    obj["btn_multi_pin"] = _config.btnMultiPin;
}

bool HardwareManager::fromJson(JsonObjectConst obj, String& outError) {
    HardwareConfig newCfg;
    memset(&newCfg, 0, sizeof(newCfg));

    const char* bName = obj["board_name"] | "Custom";
    strncpy(newCfg.boardName, bName, sizeof(newCfg.boardName) - 1);
    newCfg.boardName[sizeof(newCfg.boardName) - 1] = '\0';

    newCfg.numRelays = obj["num_relays"] | 0;
    if (newCfg.numRelays > MAX_RELAYS) newCfg.numRelays = MAX_RELAYS;

    JsonArrayConst chArr = obj["channels"].as<JsonArrayConst>();
    uint8_t idx = 0;
    for (JsonObjectConst ch : chArr) {
        if (idx >= MAX_RELAYS) break;
        uint8_t rPin = ch["relay_pin"] | PIN_UNUSED;
        uint8_t sPin = ch["switch_pin"] | PIN_UNUSED;
        newCfg.channels[idx].enabled       = ch.containsKey("enabled") ? (bool)ch["enabled"] : (rPin != PIN_UNUSED);
        newCfg.channels[idx].relayPin      = rPin;
        newCfg.channels[idx].switchEnabled = ch.containsKey("switch_enabled") ? (bool)ch["switch_enabled"] : (sPin != PIN_UNUSED);
        newCfg.channels[idx].switchPin     = sPin;
        newCfg.channels[idx].switchMode    = (SwitchMode)(ch["switch_mode"] | (uint8_t)SWITCH_MODE_TOGGLE);
        newCfg.channels[idx].triggerMode   = (TriggerMode)(ch["trigger"] | (uint8_t)TRIGGER_ACTIVE_LOW);
        idx++;
    }

    // Fill defaults for any remaining channels
    for (; idx < MAX_RELAYS; idx++) {
        newCfg.channels[idx].enabled       = false;
        newCfg.channels[idx].relayPin      = PIN_UNUSED;
        newCfg.channels[idx].switchEnabled = false;
        newCfg.channels[idx].switchPin     = PIN_UNUSED;
        newCfg.channels[idx].switchMode    = SWITCH_MODE_TOGGLE;
        newCfg.channels[idx].triggerMode   = TRIGGER_ACTIVE_LOW;
    }

    if (obj.containsKey("dht")) {
        JsonObjectConst dht = obj["dht"];
        newCfg.dhtType = (ClimateSensorType)(dht["type"] | (uint8_t)CLIMATE_DHT22);
        newCfg.dhtPin  = dht["pin"] | 4;
    } else {
        newCfg.dhtType = CLIMATE_DHT22;
        newCfg.dhtPin  = 4;
    }

    if (obj.containsKey("light")) {
        JsonObjectConst light = obj["light"];
        newCfg.lightType = (LightSensorType)(light["type"] | (uint8_t)LIGHT_NONE);
    } else {
        newCfg.lightType = LIGHT_NONE;
    }

    if (obj.containsKey("motion")) {
        JsonObjectConst mot = obj["motion"];
        newCfg.motionType = (MotionSensorType)(mot["type"] | (uint8_t)MOTION_NONE);
        newCfg.motionPin  = mot["pin"] | 32;
    } else {
        newCfg.motionType = MOTION_NONE;
        newCfg.motionPin  = 32;
    }

    if (obj.containsKey("probe")) {
        JsonObjectConst prb = obj["probe"];
        newCfg.probeType = (ProbeSensorType)(prb["type"] | (uint8_t)PROBE_NONE);
        newCfg.probePin  = prb["pin"] | 15;
    } else {
        newCfg.probeType = PROBE_NONE;
        newCfg.probePin  = 15;
    }

    if (obj.containsKey("ultrasonic")) {
        JsonObjectConst us = obj["ultrasonic"];
        newCfg.ultrasonicType = (UltrasonicSensorType)(us["type"] | (uint8_t)ULTRASONIC_NONE);
        newCfg.trigPin        = us["trig_pin"] | 15;
        newCfg.echoPin        = us["echo_pin"] | 35;
        newCfg.tankDepthCm    = us["tank_depth"] | 150;
        newCfg.tankAirGapCm   = us["air_gap"] | 15;
    } else {
        newCfg.ultrasonicType = ULTRASONIC_NONE;
        newCfg.trigPin        = 15;
        newCfg.echoPin        = 35;
        newCfg.tankDepthCm    = 150;
        newCfg.tankAirGapCm   = 15;
    }

    if (obj.containsKey("mq2")) {
        JsonObjectConst mq2 = obj["mq2"];
        newCfg.mq2Enabled    = mq2["enabled"] | true;
        newCfg.mq2AnalogPin  = mq2["analog_pin"] | 34;
        newCfg.mq2DigitalPin = mq2["digital_pin"] | 35;
    } else {
        newCfg.mq2Enabled    = true;
        newCfg.mq2AnalogPin  = 34;
        newCfg.mq2DigitalPin = 35;
    }

    if (obj.containsKey("buzzer")) {
        JsonObjectConst buz = obj["buzzer"];
        newCfg.buzzerEnabled = buz["enabled"] | true;
        newCfg.buzzerPin     = buz["pin"] | 5;
    } else {
        newCfg.buzzerEnabled = true;
        newCfg.buzzerPin     = 5;
    }

    if (obj.containsKey("lcd")) {
        JsonObjectConst lcd = obj["lcd"];
        newCfg.lcdEnabled  = lcd["enabled"] | true;
        newCfg.lcdI2cAddr = lcd["i2c_addr"] | 0x27;
        newCfg.lcdCols    = lcd["cols"] | 16;
        newCfg.lcdRows    = lcd["rows"] | 2;
        newCfg.i2cSdaPin  = lcd["sda_pin"] | 21;
        newCfg.i2cSclPin  = lcd["scl_pin"] | 22;
    } else {
        newCfg.lcdEnabled  = true;
        newCfg.lcdI2cAddr = 0x27;
        newCfg.lcdCols    = 16;
        newCfg.lcdRows    = 2;
        newCfg.i2cSdaPin  = 21;
        newCfg.i2cSclPin  = 22;
    }

    newCfg.btnMultiPin = obj["btn_multi_pin"] | 33;

    if (!validateConfig(newCfg, outError)) {
        return false;
    }

    _config = newCfg;
    return true;
}

// ============================================================================
// Persistence
// ============================================================================
bool HardwareManager::save() {
    if (!_storage) return false;
    JsonDocument doc;
    JsonObject obj = doc.to<JsonObject>();
    toJson(obj);
    return _storage->saveJson(PATH_HARDWARE_FILE, doc);
}

bool HardwareManager::load() {
    if (!_storage) return false;
    if (!_storage->fileExists(PATH_HARDWARE_FILE)) return false;

    JsonDocument doc;
    if (!_storage->loadJson(PATH_HARDWARE_FILE, doc)) return false;

    String err;
    JsonObjectConst root = doc.as<JsonObjectConst>();
    if (!fromJson(root, err)) {
        Serial.printf("[Hardware] Error parsing hardware.json: %s\n", err.c_str());
        return false;
    }
    return true;
}

// ============================================================================
// Presets
// ============================================================================
void HardwareManager::setPreset5CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome 5-CH Standard", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 5;

    const uint8_t rPins[5] = {16, 17, 18, 19, 23};
    const uint8_t sPins[5] = {13, 14, 27, 26, 25};
    for (int i = 0; i < 5; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = true;
        cfg.channels[i].switchPin     = sPins[i];
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    for (int i = 5; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;

    cfg.mq2Enabled    = true;
    cfg.mq2AnalogPin  = 34;
    cfg.mq2DigitalPin = 35;

    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;

    cfg.lcdEnabled  = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = 21;
    cfg.i2cSclPin  = 22;

    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPreset1CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome 1-CH Mini", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 1;

    cfg.channels[0].enabled       = true;
    cfg.channels[0].relayPin      = 16;
    cfg.channels[0].switchEnabled = true;
    cfg.channels[0].switchPin     = 13;
    cfg.channels[0].switchMode    = SWITCH_MODE_PUSHBUTTON;
    cfg.channels[0].triggerMode   = TRIGGER_ACTIVE_LOW;

    for (int i = 1; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;

    cfg.mq2Enabled    = false;
    cfg.mq2AnalogPin  = PIN_UNUSED;
    cfg.mq2DigitalPin = PIN_UNUSED;

    cfg.buzzerEnabled = false;
    cfg.buzzerPin     = PIN_UNUSED;

    cfg.lcdEnabled  = false;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = PIN_UNUSED;
    cfg.i2cSclPin  = PIN_UNUSED;

    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPreset2CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome 2-CH Dual", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 2;

    const uint8_t rPins[2] = {16, 17};
    const uint8_t sPins[2] = {13, 14};
    for (int i = 0; i < 2; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = true;
        cfg.channels[i].switchPin     = sPins[i];
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    for (int i = 2; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;
    cfg.mq2Enabled = true;
    cfg.mq2AnalogPin = 34;
    cfg.mq2DigitalPin = 35;
    cfg.buzzerEnabled = true;
    cfg.buzzerPin = 5;
    cfg.lcdEnabled = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols = 16;
    cfg.lcdRows = 2;
    cfg.i2cSdaPin = 21;
    cfg.i2cSclPin = 22;
    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPreset4CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome 4-CH Pro", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 4;

    const uint8_t rPins[4] = {16, 17, 18, 19};
    const uint8_t sPins[4] = {13, 14, 27, 26};
    for (int i = 0; i < 4; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = true;
        cfg.channels[i].switchPin     = sPins[i];
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    for (int i = 4; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;
    cfg.mq2Enabled = true;
    cfg.mq2AnalogPin = 34;
    cfg.mq2DigitalPin = 35;
    cfg.buzzerEnabled = true;
    cfg.buzzerPin = 5;
    cfg.lcdEnabled = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols = 16;
    cfg.lcdRows = 2;
    cfg.i2cSdaPin = 21;
    cfg.i2cSclPin = 22;
    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPreset8CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome 8-CH Max", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 8;

    const uint8_t rPins[8] = {16, 17, 18, 19, 23, 25, 26, 27};
    for (int i = 0; i < 8; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;
    cfg.mq2Enabled = false;
    cfg.mq2AnalogPin = PIN_UNUSED;
    cfg.mq2DigitalPin = PIN_UNUSED;
    cfg.buzzerEnabled = true;
    cfg.buzzerPin = 5;
    cfg.lcdEnabled = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols = 16;
    cfg.lcdRows = 2;
    cfg.i2cSdaPin = 21;
    cfg.i2cSclPin = 22;
    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPresetSensorNode(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome Sensor Node", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 0;

    for (int i = 0; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 4;
    cfg.mq2Enabled = true;
    cfg.mq2AnalogPin = 34;
    cfg.mq2DigitalPin = 35;
    cfg.buzzerEnabled = true;
    cfg.buzzerPin = 5;
    cfg.lcdEnabled = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols = 16;
    cfg.lcdRows = 2;
    cfg.i2cSdaPin = 21;
    cfg.i2cSclPin = 22;
    cfg.btnMultiPin = 33;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = 32;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = 15;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = 15;
    cfg.echoPin = 35;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPresetESP8266_2CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome ESP8266 2-CH Dual", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 2;

    const uint8_t rPins[2] = {12, 14}; // D6, D5
    const uint8_t sPins[2] = {13, 16}; // D7 (pullup), D0 (wake)
    for (int i = 0; i < 2; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = true;
        cfg.channels[i].switchPin     = sPins[i];
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    for (int i = 2; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_NONE;
    cfg.dhtPin  = PIN_UNUSED;

    cfg.mq2Enabled    = true;
    cfg.mq2AnalogPin  = 17; // A0
    cfg.mq2DigitalPin = PIN_UNUSED;

    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2; // D4

    cfg.lcdEnabled  = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = 4; // D2
    cfg.i2cSclPin  = 5; // D1

    cfg.btnMultiPin = 0; // D3 / FLASH button

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = PIN_UNUSED;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = PIN_UNUSED;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = PIN_UNUSED;
    cfg.echoPin = PIN_UNUSED;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPresetESP8266_1CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome ESP8266 1-CH Mini", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 1;

    cfg.channels[0].enabled       = true;
    cfg.channels[0].relayPin      = 12; // D6
    cfg.channels[0].switchEnabled = true;
    cfg.channels[0].switchPin     = 13; // D7
    cfg.channels[0].switchMode    = SWITCH_MODE_PUSHBUTTON;
    cfg.channels[0].triggerMode   = TRIGGER_ACTIVE_LOW;

    for (int i = 1; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 14; // D5

    cfg.mq2Enabled    = true;
    cfg.mq2AnalogPin  = 17; // A0
    cfg.mq2DigitalPin = PIN_UNUSED;

    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;

    cfg.lcdEnabled  = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = 4;
    cfg.i2cSclPin  = 5;

    cfg.btnMultiPin = 0;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = PIN_UNUSED;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = PIN_UNUSED;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = PIN_UNUSED;
    cfg.echoPin = PIN_UNUSED;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPresetESP8266_3CH(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome ESP8266 3-CH Pro", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 3;

    const uint8_t rPins[3] = {12, 14, 15}; // D6, D5, D8
    const uint8_t sPins[3] = {13, 16, PIN_UNUSED}; // D7, D0
    for (int i = 0; i < 3; i++) {
        cfg.channels[i].enabled       = true;
        cfg.channels[i].relayPin      = rPins[i];
        cfg.channels[i].switchEnabled = (sPins[i] != PIN_UNUSED);
        cfg.channels[i].switchPin     = sPins[i];
        cfg.channels[i].switchMode    = SWITCH_MODE_TOGGLE;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    for (int i = 3; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_NONE;
    cfg.dhtPin  = PIN_UNUSED;

    cfg.mq2Enabled    = true;
    cfg.mq2AnalogPin  = 17; // A0
    cfg.mq2DigitalPin = PIN_UNUSED;

    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;

    cfg.lcdEnabled  = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = 4;
    cfg.i2cSclPin  = 5;

    cfg.btnMultiPin = 0;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_NONE;
    cfg.motionPin = PIN_UNUSED;
    cfg.probeType = PROBE_NONE;
    cfg.probePin = PIN_UNUSED;
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = PIN_UNUSED;
    cfg.echoPin = PIN_UNUSED;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::setPresetESP8266_SensorNode(HardwareConfig& cfg) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, "SmartHome ESP8266 Sensor Node", sizeof(cfg.boardName) - 1);
    cfg.numRelays = 0;

    for (int i = 0; i < MAX_RELAYS; i++) {
        cfg.channels[i].enabled       = false;
        cfg.channels[i].relayPin      = PIN_UNUSED;
        cfg.channels[i].switchEnabled = false;
        cfg.channels[i].switchPin     = PIN_UNUSED;
    }

    cfg.dhtType = CLIMATE_DHT22;
    cfg.dhtPin  = 12; // D6

    cfg.mq2Enabled    = true;
    cfg.mq2AnalogPin  = 17; // A0
    cfg.mq2DigitalPin = PIN_UNUSED;

    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;

    cfg.lcdEnabled  = true;
    cfg.lcdI2cAddr = 0x27;
    cfg.lcdCols    = 16;
    cfg.lcdRows    = 2;
    cfg.i2cSdaPin  = 4;
    cfg.i2cSclPin  = 5;

    cfg.btnMultiPin = 0;

    cfg.lightType = LIGHT_NONE;
    cfg.motionType = MOTION_PIR;
    cfg.motionPin = 14; // D5
    cfg.probeType = PROBE_DS18B20;
    cfg.probePin = 13; // D7
    cfg.ultrasonicType = ULTRASONIC_NONE;
    cfg.trigPin = PIN_UNUSED;
    cfg.echoPin = PIN_UNUSED;
    cfg.tankDepthCm = 150;
    cfg.tankAirGapCm = 15;
}

void HardwareManager::getPresetsJson(JsonArray& arr) {
#if defined(ESP8266)
    const char* presets[] = {
        "SmartHome ESP8266 2-CH Dual",
        "SmartHome ESP8266 1-CH Mini",
        "SmartHome ESP8266 3-CH Pro",
        "SmartHome ESP8266 Sensor Node"
    };
#else
    const char* presets[] = {
        "SmartHome 5-CH Standard",
        "SmartHome 1-CH Mini",
        "SmartHome 2-CH Dual",
        "SmartHome 4-CH Pro",
        "SmartHome 8-CH Max",
        "SmartHome Sensor Node"
    };
#endif
    for (const char* p : presets) arr.add(p);
}

void HardwareManager::getPinCapabilitiesJson(JsonObject& obj) {
#if defined(ESP8266)
    JsonArray outputs = obj["outputs"].to<JsonArray>();
    const uint8_t safeOutputs[] = {0, 2, 4, 5, 12, 13, 14, 15, 16};
    for (uint8_t p : safeOutputs) outputs.add(p);

    JsonArray inputs = obj["inputs"].to<JsonArray>();
    const uint8_t safeInputs[] = {0, 2, 4, 5, 12, 13, 14, 15, 16, 17};
    for (uint8_t p : safeInputs) inputs.add(p);

    JsonArray adc1 = obj["adc1"].to<JsonArray>();
    adc1.add(17);

    JsonArray inputOnly = obj["input_only"].to<JsonArray>();
    inputOnly.add(17);
#else
    JsonArray outputs = obj["outputs"].to<JsonArray>();
    const uint8_t safeOutputs[] = {2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33};
    for (uint8_t p : safeOutputs) outputs.add(p);

    JsonArray inputs = obj["inputs"].to<JsonArray>();
    const uint8_t safeInputs[] = {0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39};
    for (uint8_t p : safeInputs) inputs.add(p);

    JsonArray adc1 = obj["adc1"].to<JsonArray>();
    const uint8_t adc1Pins[] = {32, 33, 34, 35, 36, 39};
    for (uint8_t p : adc1Pins) adc1.add(p);

    JsonArray inputOnly = obj["input_only"].to<JsonArray>();
    const uint8_t inOnlyPins[] = {34, 35, 36, 39};
    for (uint8_t p : inOnlyPins) inputOnly.add(p);
#endif
}
