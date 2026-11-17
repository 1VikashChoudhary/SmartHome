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
    SERIAL_PRINTF("[Hardware] Profile loaded: %s (%d relays, Climates:%d, Lights:%d, Motions:%d, Probes:%d, Tanks:%d, MQ2:%d, LCD:%s, Buzzer:%s)\n",
                  _config.boardName, _config.numRelays,
                  _config.numClimates, _config.numLights, _config.numMotions,
                  _config.numProbes, _config.numUltrasonics, _config.numMq2s,
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

void HardwareManager::setTriggerMode(uint8_t ch, TriggerMode mode) {
    if (ch >= _config.numRelays) return;
    _config.channels[ch].triggerMode = mode;
    save();
}

static void assignDefaultLabel(char* dst, size_t dstSize, const char* raw, const char* prefix, uint8_t idx) {
    if (raw && raw[0] != '\0') {
        strncpy(dst, raw, dstSize - 1);
        dst[dstSize - 1] = '\0';
    } else {
        snprintf(dst, dstSize, "%s %u", prefix, (unsigned)(idx + 1));
    }
}

static bool isI2cClimateType(ClimateSensorType t) {
    return (t == CLIMATE_BME280 || t == CLIMATE_AHT20 ||
            t == CLIMATE_SHT3X || t == CLIMATE_SHT4X);
}

static bool isOneWireClimateType(ClimateSensorType t) {
    return (t == CLIMATE_DHT11 || t == CLIMATE_DHT22 ||
            t == CLIMATE_DS18B20);
}

uint8_t HardwareManager::defaultI2cAddrForClimate(ClimateSensorType t) {
    switch (t) {
        case CLIMATE_BME280: return 0x76;
        case CLIMATE_AHT20:  return 0x38;
        case CLIMATE_SHT3X:
        case CLIMATE_SHT4X:  return 0x44;
        default:             return 0;
    }
}

uint8_t HardwareManager::defaultI2cAddrForLight(LightSensorType t) {
    return (t == LIGHT_BH1750) ? 0x23 : 0;
}

const char* HardwareManager::gasTypeShortName(uint8_t t) {
    static const char* const kNames[] = {
        "MQ-2", "SGP40", "MQ-3", "MQ-4", "MQ-5",
        "MQ-6", "MQ-7", "MQ-8", "MQ-9", "MQ-135"
    };
    return (t <= GAS_MQ_MAX) ? kNames[t] : "MQ-2";
}

const ClimateSensorConfig* HardwareManager::getClimate(uint8_t idx) const {
    return (idx < _config.numClimates) ? &_config.climates[idx] : nullptr;
}
const LightSensorConfig* HardwareManager::getLight(uint8_t idx) const {
    return (idx < _config.numLights) ? &_config.lights[idx] : nullptr;
}
const MotionSensorConfig* HardwareManager::getMotion(uint8_t idx) const {
    return (idx < _config.numMotions) ? &_config.motions[idx] : nullptr;
}
const ProbeSensorConfig* HardwareManager::getProbe(uint8_t idx) const {
    return (idx < _config.numProbes) ? &_config.probes[idx] : nullptr;
}
const UltrasonicSensorConfig* HardwareManager::getUltrasonic(uint8_t idx) const {
    return (idx < _config.numUltrasonics) ? &_config.ultrasonics[idx] : nullptr;
}
const Mq2SensorConfig* HardwareManager::getMq2(uint8_t idx) const {
    return (idx < _config.numMq2s) ? &_config.mq2Sensors[idx] : nullptr;
}

bool HardwareManager::hasAnyI2cSensor() const {
    for (uint8_t i = 0; i < _config.numClimates; i++) {
        if (isI2cClimateType(_config.climates[i].type)) return true;
    }
    for (uint8_t i = 0; i < _config.numLights; i++) {
        if (_config.lights[i].type == LIGHT_BH1750) return true;
    }
    for (uint8_t i = 0; i < _config.numMq2s; i++) {
        if (_config.mq2Sensors[i].enabled && _config.mq2Sensors[i].type == GAS_SGP40) return true;
    }
    return false;
}

ClimateSensorType HardwareManager::getDhtType() const {
    return (_config.numClimates > 0) ? _config.climates[0].type : CLIMATE_NONE;
}
uint8_t HardwareManager::getDhtPin() const {
    if (_config.numClimates > 0 && isOneWireClimateType(_config.climates[0].type)) {
        return _config.climates[0].pin;
    }
    return PIN_UNUSED;
}
LightSensorType HardwareManager::getLightType() const {
    return (_config.numLights > 0) ? _config.lights[0].type : LIGHT_NONE;
}
MotionSensorType HardwareManager::getMotionType() const {
    return (_config.numMotions > 0) ? _config.motions[0].type : MOTION_NONE;
}
uint8_t HardwareManager::getMotionPin() const {
    return (_config.numMotions > 0) ? _config.motions[0].pin : PIN_UNUSED;
}
ProbeSensorType HardwareManager::getProbeType() const {
    return (_config.numProbes > 0) ? _config.probes[0].type : PROBE_NONE;
}
uint8_t HardwareManager::getProbePin() const {
    return (_config.numProbes > 0) ? _config.probes[0].pin : PIN_UNUSED;
}
UltrasonicSensorType HardwareManager::getUltrasonicType() const {
    return (_config.numUltrasonics > 0) ? _config.ultrasonics[0].type : ULTRASONIC_NONE;
}
uint8_t HardwareManager::getTrigPin() const {
    return (_config.numUltrasonics > 0) ? _config.ultrasonics[0].trigPin : PIN_UNUSED;
}
uint8_t HardwareManager::getEchoPin() const {
    return (_config.numUltrasonics > 0) ? _config.ultrasonics[0].echoPin : PIN_UNUSED;
}
uint16_t HardwareManager::getTankDepthCm() const {
    return (_config.numUltrasonics > 0) ? _config.ultrasonics[0].tankDepthCm : 150;
}
uint16_t HardwareManager::getTankAirGapCm() const {
    return (_config.numUltrasonics > 0) ? _config.ultrasonics[0].tankAirGapCm : 15;
}
bool HardwareManager::isMq2Enabled() const {
    return (_config.numMq2s > 0) && _config.mq2Sensors[0].enabled;
}
uint8_t HardwareManager::getMq2AnalogPin() const {
    if (_config.numMq2s > 0 && _config.mq2Sensors[0].type != GAS_SGP40) {
        return _config.mq2Sensors[0].analogPin;
    }
    return PIN_UNUSED;
}
uint8_t HardwareManager::getMq2DigitalPin() const {
    if (_config.numMq2s > 0 && _config.mq2Sensors[0].type != GAS_SGP40) {
        return _config.mq2Sensors[0].digitalPin;
    }
    return PIN_UNUSED;
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
    if (presetName.equalsIgnoreCase("SmartHome ESP8266 2-CH Dual") || presetName.equalsIgnoreCase("2ch") || presetName.equalsIgnoreCase("default") || presetName.equalsIgnoreCase("SmartHome 2-CH Dual")) {
        setPresetESP8266_2CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 1-CH Mini") || presetName.equalsIgnoreCase("1ch") || presetName.equalsIgnoreCase("smartplug") || presetName.equalsIgnoreCase("SmartHome 1-CH Mini")) {
        setPresetESP8266_1CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 3-CH Pro") || presetName.equalsIgnoreCase("3ch") || presetName.equalsIgnoreCase("SmartHome 3-CH Pro")) {
        setPresetESP8266_3CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 4-CH Quad") || presetName.equalsIgnoreCase("4ch") || presetName.equalsIgnoreCase("SmartHome 4-CH Pro") || presetName.equalsIgnoreCase("SmartHome 5-CH Standard") || presetName.equalsIgnoreCase("5ch")) {
        setPresetESP8266_4CH(newCfg);
    } else if (presetName.equalsIgnoreCase("SmartHome ESP8266 8-CH Max") || presetName.equalsIgnoreCase("8ch") || presetName.equalsIgnoreCase("SmartHome 8-CH Max")) {
        setPresetESP8266_8CH(newCfg);
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
    // Allowed output pins (GPIO 2, 12, 15 carry boot strapping badges in capabilities/UI):
    // 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33
    return (pin == 2 || pin == 4 || pin == 5 || pin == 12 || pin == 13 ||
            pin == 14 || pin == 15 || pin == 16 || pin == 17 || pin == 18 ||
            pin == 19 || pin == 21 || pin == 22 || pin == 23 || pin == 25 ||
            pin == 26 || pin == 27 || pin == 32 || pin == 33);
#endif
}

bool HardwareManager::isSafeInputPin(uint8_t pin) {
    if (pin == PIN_UNUSED) return true;
#if defined(ESP8266)
    // Disallow SPI flash pins (6-11), UART0 (1, 3), and analog-only ADC pin A0 (17)
    if (pin >= 6 && pin <= 11) return false;
    if (pin == 1 || pin == 3 || pin == 17) return false;
    // Safe digital inputs: 0, 2, 4, 5, 12, 13, 14, 15, 16
    return (pin == 0 || pin == 2 || pin == 4 || pin == 5 ||
            pin == 12 || pin == 13 || pin == 14 || pin == 15 || pin == 16);
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
        outError = String(F("Number of relays exceeds maximum limit (")) + String(MAX_RELAYS) + ")";
        return false;
    }
    if (cfg.numClimates > MAX_CLIMATE_SENSORS) {
        outError = String(F("Number of climate sensors exceeds maximum limit (")) + String(MAX_CLIMATE_SENSORS) + ")";
        return false;
    }
    if (cfg.numLights > MAX_LIGHT_SENSORS) {
        outError = String(F("Number of light sensors exceeds maximum limit (")) + String(MAX_LIGHT_SENSORS) + ")";
        return false;
    }
    if (cfg.numMotions > MAX_MOTION_SENSORS) {
        outError = String(F("Number of motion sensors exceeds maximum limit (")) + String(MAX_MOTION_SENSORS) + ")";
        return false;
    }
    if (cfg.numProbes > MAX_PROBE_SENSORS) {
        outError = String(F("Number of temperature probes exceeds maximum limit (")) + String(MAX_PROBE_SENSORS) + ")";
        return false;
    }
    if (cfg.numUltrasonics > MAX_ULTRASONIC_SENSORS) {
        outError = String(F("Number of ultrasonic tank sensors exceeds maximum limit (")) + String(MAX_ULTRASONIC_SENSORS) + ")";
        return false;
    }
    if (cfg.numMq2s > MAX_MQ2_SENSORS) {
        outError = String(F("Number of MQ-2 gas sensors exceeds maximum limit (")) + String(MAX_MQ2_SENSORS) + ")";
        return false;
    }

    // Bitmap / tracker for assigned pins to detect conflicts (0..39)
    int8_t pinUsage[40];
    for (int i = 0; i < 40; i++) pinUsage[i] = -1;

    // Tracker for claimed 7-bit I2C addresses on shared I2C bus
    uint8_t usedI2cAddrs[16];
    String usedI2cOwners[16];
    uint8_t usedI2cCount = 0;

    auto claimPin = [&](uint8_t pin, const char* component) -> bool {
        if (pin == PIN_UNUSED) return true;
        if (pin >= 40) {
            outError = String(component) + F(": invalid GPIO ") + String(pin);
            return false;
        }
#if defined(ESP8266)
        if (pin > 17) {
            outError = String(component) + F(": invalid GPIO ") + String(pin) + F(" (ESP8266 supports GPIO 0-16, A0/17)");
            return false;
        }
#endif
        if (pinUsage[pin] != -1) {
            outError = String(F("GPIO conflict: Pin ")) + String(pin) + F(" assigned to multiple peripherals (") + String(component) + ")";
            return false;
        }
        pinUsage[pin] = 1;
        return true;
    };

    auto claimI2cAddr = [&](uint8_t addr, const String& owner) -> bool {
        if (addr < 0x08 || addr > 0x77) {
            outError = owner + F(": invalid I2C address 0x") + String(addr, HEX);
            return false;
        }
        for (uint8_t k = 0; k < usedI2cCount; k++) {
            if (usedI2cAddrs[k] == addr) {
                char hexBuf[8];
                snprintf(hexBuf, sizeof(hexBuf), "0x%02X", addr);
                outError = String(F("I2C address conflict: ")) + String(hexBuf) + F(" assigned to both ") + usedI2cOwners[k] + F(" and ") + owner;
                return false;
            }
        }
        if (usedI2cCount < 16) {
            usedI2cAddrs[usedI2cCount] = addr;
            usedI2cOwners[usedI2cCount] = owner;
            usedI2cCount++;
        }
        return true;
    };

    // 1. Relays
    for (uint8_t i = 0; i < cfg.numRelays; i++) {
        if (!cfg.channels[i].enabled) continue; // Disabled channel does not claim any pins

        uint8_t rPin = cfg.channels[i].relayPin;
        if (rPin != PIN_UNUSED) {
            if (!isSafeOutputPin(rPin)) {
                outError = String(F("Relay ")) + String(i + 1) + F(": GPIO ") + String(rPin) + F(" cannot be used as an output (input-only or system pin)");
                return false;
            }
            if (!claimPin(rPin, ("Relay " + String(i + 1)).c_str())) return false;
        }

        if (cfg.channels[i].switchEnabled) {
            uint8_t sPin = cfg.channels[i].switchPin;
            if (sPin != PIN_UNUSED) {
                if (!isSafeInputPin(sPin)) {
                    outError = String(F("Switch ")) + String(i + 1) + F(": GPIO ") + String(sPin) + F(" is not a valid input pin");
                    return false;
                }
                if (!claimPin(sPin, ("Switch " + String(i + 1)).c_str())) return false;
            }
        }
    }

    bool i2cActive = cfg.lcdEnabled;

    // 2. Climate Sensors (DHT11/22/DS18B20 per-GPIO, BME280/AHT20/SHT3X/SHT4X shared I2C)
    for (uint8_t i = 0; i < cfg.numClimates; i++) {
        const ClimateSensorConfig& c = cfg.climates[i];
        String tag = "Climate " + String(i + 1);
        if (c.type == CLIMATE_NONE) continue;
        if (c.type > CLIMATE_DS18B20) {
            outError = tag + F(": Invalid climate sensor type");
            return false;
        }
        if (isOneWireClimateType(c.type)) {
            if (c.pin == PIN_UNUSED) {
                outError = tag + F(": Please select a bidirectional GPIO pin");
                return false;
            }
            if (!isSafeOutputPin(c.pin)) {
                outError = (c.type == CLIMATE_DS18B20)
                    ? (tag + F(": Climate DS18B20 1-Wire pin GPIO ") + String(c.pin) + F(" must support bidirectional output"))
                    : (tag + F(": GPIO ") + String(c.pin) + F(" cannot be an input-only pin (requires bidirectional output)"));
                return false;
            }
            if (!claimPin(c.pin, tag.c_str())) return false;
        } else {
            uint8_t addr = c.i2cAddr ? c.i2cAddr : defaultI2cAddrForClimate(c.type);
            if (c.type == CLIMATE_BME280 && addr != 0x76 && addr != 0x77) {
                outError = tag + F(": BME280/BMP280 supports I2C address 0x76 or 0x77");
                return false;
            }
            if (c.type == CLIMATE_AHT20 && addr != 0x38) {
                outError = tag + F(": AHT20 uses fixed I2C address 0x38");
                return false;
            }
            if ((c.type == CLIMATE_SHT3X || c.type == CLIMATE_SHT4X) && addr != 0x44 && addr != 0x45) {
                outError = tag + (c.type == CLIMATE_SHT4X
                    ? F(": SHT40/SHT45 supports I2C address 0x44 or 0x45")
                    : F(": SHT3x supports I2C address 0x44 or 0x45"));
                return false;
            }
            if (!claimI2cAddr(addr, tag)) return false;
            i2cActive = true;
        }
    }

    // 2a. Ambient Light Sensors (BH1750 on shared I2C bus)
    for (uint8_t i = 0; i < cfg.numLights; i++) {
        const LightSensorConfig& l = cfg.lights[i];
        if (l.type == LIGHT_NONE) continue;
        String tag = "Light " + String(i + 1);
        uint8_t addr = l.i2cAddr ? l.i2cAddr : defaultI2cAddrForLight(l.type);
        if (addr != 0x23 && addr != 0x5C) {
            outError = tag + F(": BH1750 supports I2C address 0x23 or 0x5C");
            return false;
        }
        if (!claimI2cAddr(addr, tag)) return false;
        i2cActive = true;
    }

    // 2b. Motion / Occupancy Sensors
    for (uint8_t i = 0; i < cfg.numMotions; i++) {
        const MotionSensorConfig& m = cfg.motions[i];
        if (m.type == MOTION_NONE) continue;
        String tag = "Motion " + String(i + 1);
        if (m.pin == PIN_UNUSED) {
            outError = tag + F(": Please select a valid input GPIO pin");
            return false;
        }
        if (!isSafeInputPin(m.pin)) {
            outError = tag + F(": GPIO ") + String(m.pin) + F(" is not a valid input pin");
            return false;
        }
        if (!claimPin(m.pin, tag.c_str())) return false;
    }

    // 2c. Submersible Water Temp Probes (DS18B20)
    for (uint8_t i = 0; i < cfg.numProbes; i++) {
        const ProbeSensorConfig& p = cfg.probes[i];
        if (p.type == PROBE_NONE) continue;
        String tag = "Probe " + String(i + 1);
        if (p.pin == PIN_UNUSED) {
            outError = tag + F(": Please select a valid 1-Wire GPIO pin");
            return false;
        }
        if (!isSafeOutputPin(p.pin)) {
            outError = tag + F(": GPIO ") + String(p.pin) + F(" cannot be an input-only pin");
            return false;
        }
        if (!claimPin(p.pin, tag.c_str())) return false;
    }

    // 2d. Ultrasonic Distance & Water Tank Level Sensors
    for (uint8_t i = 0; i < cfg.numUltrasonics; i++) {
        const UltrasonicSensorConfig& u = cfg.ultrasonics[i];
        if (u.type == ULTRASONIC_NONE) continue;
        String tag = "Ultrasonic Tank " + String(i + 1);
        if (u.trigPin == PIN_UNUSED || u.echoPin == PIN_UNUSED) {
            outError = tag + F(": Both Trig and Echo GPIO pins are required");
            return false;
        }
        if (u.tankDepthCm < 20 || u.tankDepthCm > 500 ||
            u.tankAirGapCm < 5 || u.tankAirGapCm > 100 ||
            u.tankDepthCm <= u.tankAirGapCm) {
            outError = tag + F(": Tank depth (20-500 cm) must be greater than air gap (5-100 cm)");
            return false;
        }
        if (!isSafeOutputPin(u.trigPin)) {
            outError = tag + F(" Trig: GPIO ") + String(u.trigPin) + F(" cannot be an input-only pin");
            return false;
        }
        if (!claimPin(u.trigPin, (tag + " Trig").c_str())) return false;
        if (!isSafeInputPin(u.echoPin)) {
            outError = tag + F(" Echo: GPIO ") + String(u.echoPin) + F(" is not a valid input pin");
            return false;
        }
        if (!claimPin(u.echoPin, (tag + " Echo").c_str())) return false;
    }

    // 3. Gas & Air Quality Sensors (MQ Series / SGP40 I2C)
    for (uint8_t i = 0; i < cfg.numMq2s; i++) {
        const Mq2SensorConfig& g = cfg.mq2Sensors[i];
        if (!g.enabled) continue;
        if (g.type > GAS_MQ_MAX) {
            outError = String(F("Gas ")) + String(i + 1) + F(": Invalid gas sensor type");
            return false;
        }
        if (g.type == GAS_SGP40) {
            String tag = "SGP40 " + String(i + 1);
            uint8_t addr = (g.i2cAddr == 0) ? 0x59 : g.i2cAddr;
            if (addr != 0x59) {
                outError = tag + F(": Invalid I2C address for SGP40 sensor (must be 0x59)");
                return false;
            }
            if (!claimI2cAddr(addr, tag)) return false;
            i2cActive = true;
            continue;
        }
        String tag = String(gasTypeShortName(g.type)) + " " + String(i + 1);
        if (g.analogPin == PIN_UNUSED && g.digitalPin == PIN_UNUSED) {
            outError = tag + F(": Enable requires at least an Analog or Digital GPIO pin");
            return false;
        }
        if (g.analogPin != PIN_UNUSED) {
            if (!isAdc1Pin(g.analogPin)) {
#if defined(ESP8266)
                outError = tag + F(" Analog: GPIO ") + String(g.analogPin) + F(" is not A0 (ESP8266 only has A0 / GPIO 17 for analog input).");
#else
                outError = tag + F(" Analog: GPIO ") + String(g.analogPin) + F(" is not on ADC1 (ADC2 conflicts with Wi-Fi). Use GPIO 32-36 or 39.");
#endif
                return false;
            }
            if (!claimPin(g.analogPin, (tag + " Analog").c_str())) return false;
        }
        if (g.digitalPin != PIN_UNUSED) {
            if (!isSafeInputPin(g.digitalPin)) {
                outError = tag + F(" Digital: GPIO ") + String(g.digitalPin) + F(" is not a valid input pin");
                return false;
            }
            if (!claimPin(g.digitalPin, (tag + " Digital").c_str())) return false;
        }
    }

    // 4. Buzzer
    if (cfg.buzzerEnabled && cfg.buzzerPin != PIN_UNUSED) {
        if (!isSafeOutputPin(cfg.buzzerPin)) {
            outError = String(F("Buzzer: GPIO ")) + String(cfg.buzzerPin) + F(" cannot be used as an output (input-only or system pin)");
            return false;
        }
        if (!claimPin(cfg.buzzerPin, "Buzzer")) return false;
    }

    // 5. I2C Bus (LCD Display and/or I2C Sensors: BME280, AHT20, SHT31, BH1750)
    if (cfg.lcdEnabled) {
        if (!claimI2cAddr(cfg.lcdI2cAddr, "LCD Display")) return false;
    }
    if (i2cActive) {
        if (cfg.i2cSdaPin == PIN_UNUSED || cfg.i2cSclPin == PIN_UNUSED) {
            outError = F("I2C Bus: Both SDA and SCL GPIO pins are required when LCD or I2C sensors are enabled");
            return false;
        }
        if (!isSafeOutputPin(cfg.i2cSdaPin)) {
            outError = String(F("I2C SDA: GPIO ")) + String(cfg.i2cSdaPin) + F(" cannot be an input-only pin");
            return false;
        }
        if (!claimPin(cfg.i2cSdaPin, "I2C SDA")) return false;
        if (!isSafeOutputPin(cfg.i2cSclPin)) {
            outError = String(F("I2C SCL: GPIO ")) + String(cfg.i2cSclPin) + F(" cannot be an input-only pin");
            return false;
        }
        if (!claimPin(cfg.i2cSclPin, "I2C SCL")) return false;
    }

    // 6. Multi-function Button
    if (cfg.btnMultiPin != PIN_UNUSED) {
        if (!isSafeInputPin(cfg.btnMultiPin)) {
            outError = String(F("Multi-function Button: GPIO ")) + String(cfg.btnMultiPin) + F(" is not a valid input pin");
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

    JsonArray climatesArr = obj["climates"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numClimates; i++) {
        JsonObject c = climatesArr.add<JsonObject>();
        c["type"]     = (uint8_t)_config.climates[i].type;
        c["pin"]      = isOneWireClimateType(_config.climates[i].type) ? _config.climates[i].pin : PIN_UNUSED;
        c["i2c_addr"] = isI2cClimateType(_config.climates[i].type) ? _config.climates[i].i2cAddr : 0;
        c["label"]    = _config.climates[i].label;
    }

    JsonArray lightsArr = obj["lights"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numLights; i++) {
        JsonObject l = lightsArr.add<JsonObject>();
        l["type"]     = (uint8_t)_config.lights[i].type;
        l["i2c_addr"] = _config.lights[i].i2cAddr;
        l["label"]    = _config.lights[i].label;
    }

    JsonArray motionsArr = obj["motions"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numMotions; i++) {
        JsonObject m = motionsArr.add<JsonObject>();
        m["type"]  = (uint8_t)_config.motions[i].type;
        m["pin"]   = _config.motions[i].pin;
        m["label"] = _config.motions[i].label;
    }

    JsonArray probesArr = obj["probes"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numProbes; i++) {
        JsonObject p = probesArr.add<JsonObject>();
        p["type"]  = (uint8_t)_config.probes[i].type;
        p["pin"]   = _config.probes[i].pin;
        p["label"] = _config.probes[i].label;
    }

    JsonArray usArr = obj["ultrasonics"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numUltrasonics; i++) {
        JsonObject u = usArr.add<JsonObject>();
        u["type"]       = (uint8_t)_config.ultrasonics[i].type;
        u["trig_pin"]   = _config.ultrasonics[i].trigPin;
        u["echo_pin"]   = _config.ultrasonics[i].echoPin;
        u["tank_depth"] = _config.ultrasonics[i].tankDepthCm;
        u["air_gap"]    = _config.ultrasonics[i].tankAirGapCm;
        u["label"]      = _config.ultrasonics[i].label;
    }

    JsonArray mq2Arr = obj["mq2_sensors"].to<JsonArray>();
    for (uint8_t i = 0; i < _config.numMq2s; i++) {
        JsonObject g = mq2Arr.add<JsonObject>();
        g["enabled"]     = _config.mq2Sensors[i].enabled;
        g["type"]        = _config.mq2Sensors[i].type;
        g["analog_pin"]  = (_config.mq2Sensors[i].type == GAS_SGP40) ? PIN_UNUSED : _config.mq2Sensors[i].analogPin;
        g["digital_pin"] = (_config.mq2Sensors[i].type == GAS_SGP40) ? PIN_UNUSED : _config.mq2Sensors[i].digitalPin;
        g["i2c_addr"]    = (_config.mq2Sensors[i].type == GAS_SGP40)
            ? (_config.mq2Sensors[i].i2cAddr ? _config.mq2Sensors[i].i2cAddr : 0x59)
            : 0;
        g["label"]       = _config.mq2Sensors[i].label;
    }

    // Legacy slot-0 summary objects (backward compatibility for existing tooling/backups)
    JsonObject dht = obj["dht"].to<JsonObject>();
    dht["type"] = (uint8_t)getDhtType();
    dht["pin"]  = getDhtPin();
    if (_config.numClimates > 0 && _config.climates[0].i2cAddr > 0) {
        dht["i2c_addr"] = _config.climates[0].i2cAddr;
    }

    JsonObject light = obj["light"].to<JsonObject>();
    light["type"] = (uint8_t)getLightType();
    if (_config.numLights > 0 && _config.lights[0].i2cAddr > 0) {
        light["i2c_addr"] = _config.lights[0].i2cAddr;
    }

    JsonObject motion = obj["motion"].to<JsonObject>();
    motion["type"] = (uint8_t)getMotionType();
    motion["pin"]  = getMotionPin();

    JsonObject probe = obj["probe"].to<JsonObject>();
    probe["type"] = (uint8_t)getProbeType();
    probe["pin"]  = getProbePin();

    JsonObject ultrasonic = obj["ultrasonic"].to<JsonObject>();
    ultrasonic["type"]       = (uint8_t)getUltrasonicType();
    ultrasonic["trig_pin"]   = getTrigPin();
    ultrasonic["echo_pin"]   = getEchoPin();
    ultrasonic["tank_depth"] = getTankDepthCm();
    ultrasonic["air_gap"]    = getTankAirGapCm();

    JsonObject mq2 = obj["mq2"].to<JsonObject>();
    mq2["enabled"]     = isMq2Enabled();
    mq2["analog_pin"]  = getMq2AnalogPin();
    mq2["digital_pin"] = getMq2DigitalPin();

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

static bool readPinField(JsonObjectConst obj, const char* key, uint8_t defaultPin,
                         uint8_t& outPin, const String& label, String& outError) {
    if (!obj.containsKey(key) || obj[key].isNull()) {
        outPin = defaultPin;
        return true;
    }
    if (!obj[key].is<long>()) {
        outError = label + F(": GPIO pin must be an integer");
        return false;
    }
    long raw = obj[key].as<long>();
    if (raw < 0 || raw > 255) {
        outError = label + F(": GPIO pin out of range (") + String(raw) + ")";
        return false;
    }
    outPin = (uint8_t)raw;
    return true;
}

static bool readByteRangeField(JsonObjectConst obj, const char* key, uint8_t defaultVal,
                               uint8_t maxVal, uint8_t& outVal, const String& label, String& outError) {
    if (!obj.containsKey(key) || obj[key].isNull()) {
        outVal = defaultVal;
        return true;
    }
    if (!obj[key].is<long>()) {
        outError = label + F(": field must be an integer");
        return false;
    }
    long raw = obj[key].as<long>();
    if (raw < 0 || raw > (long)maxVal) {
        outError = label + F(": value out of range (") + String(raw) + ")";
        return false;
    }
    outVal = (uint8_t)raw;
    return true;
}

bool HardwareManager::parseHardwareJson(JsonObjectConst obj, HardwareConfig& newCfg, String& outError) {
    memset(&newCfg, 0, sizeof(newCfg));

    const char* bName = obj["board_name"] | "Custom";
    strncpy(newCfg.boardName, bName, sizeof(newCfg.boardName) - 1);
    newCfg.boardName[sizeof(newCfg.boardName) - 1] = '\0';

    long rawNumRelays = obj.containsKey("num_relays") ? obj["num_relays"].as<long>() : 0;
    if (rawNumRelays < 0 || rawNumRelays > MAX_RELAYS) {
        outError = String(F("Number of relays out of range (0-")) + String(MAX_RELAYS) + ")";
        return false;
    }
    newCfg.numRelays = (uint8_t)rawNumRelays;

    JsonArrayConst chArr = obj["channels"].as<JsonArrayConst>();
    uint8_t idx = 0;
    for (JsonObjectConst ch : chArr) {
        if (idx >= MAX_RELAYS) break;
        String chTag = "Channel " + String(idx + 1);
        uint8_t rPin = PIN_UNUSED;
        uint8_t sPin = PIN_UNUSED;
        uint8_t swMode = (uint8_t)SWITCH_MODE_TOGGLE;
        uint8_t trigMode = (uint8_t)TRIGGER_ACTIVE_LOW;
        if (!readPinField(ch, "relay_pin", PIN_UNUSED, rPin, chTag + F(" Relay"), outError)) return false;
        if (!readPinField(ch, "switch_pin", PIN_UNUSED, sPin, chTag + F(" Switch"), outError)) return false;
        if (!readByteRangeField(ch, "switch_mode", (uint8_t)SWITCH_MODE_TOGGLE, SWITCH_MODE_DETACHED,
                                swMode, chTag + F(" switch_mode"), outError)) return false;
        if (!readByteRangeField(ch, "trigger", (uint8_t)TRIGGER_ACTIVE_LOW, TRIGGER_ACTIVE_HIGH,
                                trigMode, chTag + F(" trigger"), outError)) return false;
        newCfg.channels[idx].enabled       = ch.containsKey("enabled") ? (bool)ch["enabled"] : (rPin != PIN_UNUSED);
        newCfg.channels[idx].relayPin      = rPin;
        newCfg.channels[idx].switchEnabled = ch.containsKey("switch_enabled") ? (bool)ch["switch_enabled"] : (sPin != PIN_UNUSED);
        newCfg.channels[idx].switchPin     = sPin;
        newCfg.channels[idx].switchMode    = (SwitchMode)swMode;
        newCfg.channels[idx].triggerMode   = (TriggerMode)trigMode;
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

#if defined(ESP8266)
    const uint8_t defDhtPin    = PIN_UNUSED;
    const uint8_t defMotionPin = PIN_UNUSED;
    const uint8_t defProbePin  = PIN_UNUSED;
    const uint8_t defTrigPin   = PIN_UNUSED;
    const uint8_t defEchoPin   = PIN_UNUSED;
    const uint8_t defMq2APin   = 17; // A0 on ESP8266
    const uint8_t defMq2DPin   = PIN_UNUSED;
    const uint8_t defBuzPin    = 2;
    const uint8_t defSdaPin    = 4;
    const uint8_t defSclPin    = 5;
    const uint8_t defBtnPin    = 0;
#else
    const uint8_t defDhtPin    = 4;
    const uint8_t defMotionPin = 32;
    const uint8_t defProbePin  = 15;
    const uint8_t defTrigPin   = 15;
    const uint8_t defEchoPin   = 35;
    const uint8_t defMq2APin   = 34;
    const uint8_t defMq2DPin   = 35;
    const uint8_t defBuzPin    = 5;
    const uint8_t defSdaPin    = 21;
    const uint8_t defSclPin    = 22;
    const uint8_t defBtnPin    = 33;
#endif

    // 1. Climate Sensors (array preferred, fallback to legacy "dht" object)
    if (obj.containsKey("climates") && obj["climates"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["climates"].as<JsonArrayConst>();
        if (arr.size() > MAX_CLIMATE_SENSORS) {
            outError = "Number of climate sensors exceeds maximum limit (" + String(MAX_CLIMATE_SENSORS) + ")";
            return false;
        }
        uint8_t cIdx = 0;
        for (JsonObjectConst c : arr) {
            uint8_t dType = (uint8_t)CLIMATE_NONE;
            if (!readByteRangeField(c, "type", (uint8_t)CLIMATE_NONE, CLIMATE_DS18B20,
                                    dType, "Climate " + String(cIdx + 1), outError)) return false;
            ClimateSensorType ct = (ClimateSensorType)dType;
            uint8_t addr = 0;
            uint8_t pin = PIN_UNUSED;
            if (isI2cClimateType(ct)) {
                if (!readByteRangeField(c, "i2c_addr", 0, 127, addr, "Climate " + String(cIdx + 1) + F(" i2c_addr"), outError)) return false;
                if (addr == 0) addr = defaultI2cAddrForClimate(ct);
            } else if (isOneWireClimateType(ct)) {
                if (!readPinField(c, "pin", PIN_UNUSED, pin, "Climate " + String(cIdx + 1), outError)) return false;
            }
            newCfg.climates[cIdx].type    = ct;
            newCfg.climates[cIdx].pin     = pin;
            newCfg.climates[cIdx].i2cAddr = addr;
            assignDefaultLabel(newCfg.climates[cIdx].label, sizeof(newCfg.climates[cIdx].label),
                               c["label"] | "", "Climate", cIdx);
            cIdx++;
        }
        newCfg.numClimates = cIdx;
    } else if (obj.containsKey("dht")) {
        JsonObjectConst dht = obj["dht"];
        uint8_t dPin = defDhtPin;
        if (!readPinField(dht, "pin", defDhtPin, dPin, F("Climate 1"), outError)) return false;
        uint8_t dType = (uint8_t)(dPin != PIN_UNUSED ? CLIMATE_DHT22 : CLIMATE_NONE);
        if (!readByteRangeField(dht, "type", dType, CLIMATE_DS18B20, dType, F("Climate 1"), outError)) return false;
        if (dType != CLIMATE_NONE) {
            ClimateSensorType ct = (ClimateSensorType)dType;
            uint8_t addr = 0;
            uint8_t pin = PIN_UNUSED;
            if (isI2cClimateType(ct)) {
                if (!readByteRangeField(dht, "i2c_addr", 0, 127, addr, F("Climate 1 i2c_addr"), outError)) return false;
                if (addr == 0) addr = defaultI2cAddrForClimate(ct);
            } else if (isOneWireClimateType(ct)) {
                pin = dPin;
            }
            newCfg.numClimates = 1;
            newCfg.climates[0].type    = ct;
            newCfg.climates[0].pin     = pin;
            newCfg.climates[0].i2cAddr = addr;
            assignDefaultLabel(newCfg.climates[0].label, sizeof(newCfg.climates[0].label), nullptr, "Climate", 0);
        }
    } else {
        newCfg.numClimates = 0;
    }

    // 2. Ambient Light Sensors
    if (obj.containsKey("lights") && obj["lights"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["lights"].as<JsonArrayConst>();
        if (arr.size() > MAX_LIGHT_SENSORS) {
            outError = "Number of light sensors exceeds maximum limit (" + String(MAX_LIGHT_SENSORS) + ")";
            return false;
        }
        uint8_t lIdx = 0;
        for (JsonObjectConst l : arr) {
            uint8_t lType = (uint8_t)LIGHT_NONE;
            if (!readByteRangeField(l, "type", (uint8_t)LIGHT_NONE, LIGHT_BH1750,
                                    lType, "Light " + String(lIdx + 1), outError)) return false;
            LightSensorType lt = (LightSensorType)lType;
            uint8_t addr = 0;
            if (!readByteRangeField(l, "i2c_addr", 0, 127, addr, "Light " + String(lIdx + 1) + F(" i2c_addr"), outError)) return false;
            if (addr == 0 && lt == LIGHT_BH1750) addr = defaultI2cAddrForLight(lt);
            newCfg.lights[lIdx].type    = lt;
            newCfg.lights[lIdx].i2cAddr = addr;
            assignDefaultLabel(newCfg.lights[lIdx].label, sizeof(newCfg.lights[lIdx].label),
                               l["label"] | "", "Light", lIdx);
            lIdx++;
        }
        newCfg.numLights = lIdx;
    } else if (obj.containsKey("light")) {
        JsonObjectConst light = obj["light"];
        uint8_t lType = (uint8_t)LIGHT_NONE;
        if (!readByteRangeField(light, "type", (uint8_t)LIGHT_NONE, LIGHT_BH1750, lType, F("Light 1"), outError)) return false;
        if (lType != LIGHT_NONE) {
            LightSensorType lt = (LightSensorType)lType;
            uint8_t addr = 0;
            if (!readByteRangeField(light, "i2c_addr", 0, 127, addr, F("Light 1 i2c_addr"), outError)) return false;
            if (addr == 0) addr = defaultI2cAddrForLight(lt);
            newCfg.numLights = 1;
            newCfg.lights[0].type    = lt;
            newCfg.lights[0].i2cAddr = addr;
            assignDefaultLabel(newCfg.lights[0].label, sizeof(newCfg.lights[0].label), nullptr, "Light", 0);
        }
    }

    // 3. Motion Sensors
    if (obj.containsKey("motions") && obj["motions"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["motions"].as<JsonArrayConst>();
        if (arr.size() > MAX_MOTION_SENSORS) {
            outError = "Number of motion sensors exceeds maximum limit (" + String(MAX_MOTION_SENSORS) + ")";
            return false;
        }
        uint8_t mIdx = 0;
        for (JsonObjectConst m : arr) {
            uint8_t mType = (uint8_t)MOTION_NONE;
            if (!readByteRangeField(m, "type", (uint8_t)MOTION_NONE, MOTION_RADAR_LD2410,
                                    mType, "Motion " + String(mIdx + 1), outError)) return false;
            uint8_t mPin = PIN_UNUSED;
            if (!readPinField(m, "pin", PIN_UNUSED, mPin, "Motion " + String(mIdx + 1), outError)) return false;
            newCfg.motions[mIdx].type = (MotionSensorType)mType;
            newCfg.motions[mIdx].pin  = mPin;
            assignDefaultLabel(newCfg.motions[mIdx].label, sizeof(newCfg.motions[mIdx].label),
                               m["label"] | "", "Motion", mIdx);
            mIdx++;
        }
        newCfg.numMotions = mIdx;
    } else if (obj.containsKey("motion")) {
        JsonObjectConst mot = obj["motion"];
        uint8_t mType = (uint8_t)MOTION_NONE;
        if (!readByteRangeField(mot, "type", (uint8_t)MOTION_NONE, MOTION_RADAR_LD2410, mType, F("Motion 1"), outError)) return false;
        if (mType != MOTION_NONE) {
            uint8_t mPin = defMotionPin;
            if (!readPinField(mot, "pin", defMotionPin, mPin, F("Motion 1"), outError)) return false;
            newCfg.numMotions = 1;
            newCfg.motions[0].type = (MotionSensorType)mType;
            newCfg.motions[0].pin  = mPin;
            assignDefaultLabel(newCfg.motions[0].label, sizeof(newCfg.motions[0].label), nullptr, "Motion", 0);
        }
    }

    // 4. Water Temp Probes (DS18B20)
    if (obj.containsKey("probes") && obj["probes"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["probes"].as<JsonArrayConst>();
        if (arr.size() > MAX_PROBE_SENSORS) {
            outError = "Number of temperature probes exceeds maximum limit (" + String(MAX_PROBE_SENSORS) + ")";
            return false;
        }
        uint8_t pIdx = 0;
        for (JsonObjectConst p : arr) {
            uint8_t pType = (uint8_t)PROBE_NONE;
            if (!readByteRangeField(p, "type", (uint8_t)PROBE_NONE, PROBE_DS18B20,
                                    pType, "Probe " + String(pIdx + 1), outError)) return false;
            uint8_t pPin = PIN_UNUSED;
            if (!readPinField(p, "pin", PIN_UNUSED, pPin, "Probe " + String(pIdx + 1), outError)) return false;
            newCfg.probes[pIdx].type = (ProbeSensorType)pType;
            newCfg.probes[pIdx].pin  = pPin;
            assignDefaultLabel(newCfg.probes[pIdx].label, sizeof(newCfg.probes[pIdx].label),
                               p["label"] | "", "Probe", pIdx);
            pIdx++;
        }
        newCfg.numProbes = pIdx;
    } else if (obj.containsKey("probe")) {
        JsonObjectConst prb = obj["probe"];
        uint8_t pType = (uint8_t)PROBE_NONE;
        if (!readByteRangeField(prb, "type", (uint8_t)PROBE_NONE, PROBE_DS18B20, pType, F("Probe 1"), outError)) return false;
        if (pType != PROBE_NONE) {
            uint8_t pPin = defProbePin;
            if (!readPinField(prb, "pin", defProbePin, pPin, F("Probe 1"), outError)) return false;
            newCfg.numProbes = 1;
            newCfg.probes[0].type = (ProbeSensorType)pType;
            newCfg.probes[0].pin  = pPin;
            assignDefaultLabel(newCfg.probes[0].label, sizeof(newCfg.probes[0].label), nullptr, "Probe", 0);
        }
    }

    // 5. Ultrasonic Tank Level Sensors
    if (obj.containsKey("ultrasonics") && obj["ultrasonics"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["ultrasonics"].as<JsonArrayConst>();
        if (arr.size() > MAX_ULTRASONIC_SENSORS) {
            outError = "Number of ultrasonic tank sensors exceeds maximum limit (" + String(MAX_ULTRASONIC_SENSORS) + ")";
            return false;
        }
        uint8_t uIdx = 0;
        for (JsonObjectConst u : arr) {
            String uTag = "Ultrasonic Tank " + String(uIdx + 1);
            uint8_t uType = (uint8_t)ULTRASONIC_NONE;
            if (!readByteRangeField(u, "type", (uint8_t)ULTRASONIC_NONE, ULTRASONIC_JSN_SR04T, uType, uTag, outError)) return false;
            int depthVal = u["tank_depth"] | 150;
            int airVal   = u["air_gap"] | 15;
            if (depthVal < 0 || depthVal > 65535 || airVal < 0 || airVal > 65535) {
                outError = "Ultrasonic Tank Sensor: Tank depth and air gap must be valid positive values";
                return false;
            }
            uint8_t trigPin = PIN_UNUSED, echoPin = PIN_UNUSED;
            if (!readPinField(u, "trig_pin", PIN_UNUSED, trigPin, uTag + F(" Trig"), outError)) return false;
            if (!readPinField(u, "echo_pin", PIN_UNUSED, echoPin, uTag + F(" Echo"), outError)) return false;
            newCfg.ultrasonics[uIdx].type         = (UltrasonicSensorType)uType;
            newCfg.ultrasonics[uIdx].trigPin      = trigPin;
            newCfg.ultrasonics[uIdx].echoPin      = echoPin;
            newCfg.ultrasonics[uIdx].tankDepthCm  = (uint16_t)depthVal;
            newCfg.ultrasonics[uIdx].tankAirGapCm = (uint16_t)airVal;
            assignDefaultLabel(newCfg.ultrasonics[uIdx].label, sizeof(newCfg.ultrasonics[uIdx].label),
                               u["label"] | "", "Tank", uIdx);
            uIdx++;
        }
        newCfg.numUltrasonics = uIdx;
    } else if (obj.containsKey("ultrasonic")) {
        JsonObjectConst us = obj["ultrasonic"];
        uint8_t uType = (uint8_t)ULTRASONIC_NONE;
        if (!readByteRangeField(us, "type", (uint8_t)ULTRASONIC_NONE, ULTRASONIC_JSN_SR04T, uType, F("Ultrasonic Tank 1"), outError)) return false;
        if (uType != ULTRASONIC_NONE) {
            int depthVal = us["tank_depth"] | 150;
            int airVal   = us["air_gap"] | 15;
            if (depthVal < 0 || depthVal > 65535 || airVal < 0 || airVal > 65535) {
                outError = "Ultrasonic Tank Sensor: Tank depth and air gap must be valid positive values";
                return false;
            }
            uint8_t trigPin = defTrigPin, echoPin = defEchoPin;
            if (!readPinField(us, "trig_pin", defTrigPin, trigPin, F("Ultrasonic Tank 1 Trig"), outError)) return false;
            if (!readPinField(us, "echo_pin", defEchoPin, echoPin, F("Ultrasonic Tank 1 Echo"), outError)) return false;
            newCfg.numUltrasonics = 1;
            newCfg.ultrasonics[0].type         = (UltrasonicSensorType)uType;
            newCfg.ultrasonics[0].trigPin      = trigPin;
            newCfg.ultrasonics[0].echoPin      = echoPin;
            newCfg.ultrasonics[0].tankDepthCm  = (uint16_t)depthVal;
            newCfg.ultrasonics[0].tankAirGapCm = (uint16_t)airVal;
            assignDefaultLabel(newCfg.ultrasonics[0].label, sizeof(newCfg.ultrasonics[0].label), nullptr, "Tank", 0);
        }
    }

    // 6. Gas & Air Quality Sensors (MQ-2 / SGP40)
    if (obj.containsKey("mq2_sensors") && obj["mq2_sensors"].is<JsonArrayConst>()) {
        JsonArrayConst arr = obj["mq2_sensors"].as<JsonArrayConst>();
        if (arr.size() > MAX_MQ2_SENSORS) {
            outError = "Number of gas sensors exceeds maximum limit (" + String(MAX_MQ2_SENSORS) + ")";
            return false;
        }
        uint8_t gIdx = 0;
        for (JsonObjectConst g : arr) {
            String gTag = "Gas " + String(gIdx + 1);
            uint8_t gType = (uint8_t)GAS_MQ2;
            if (!readByteRangeField(g, "type", (uint8_t)GAS_MQ2, GAS_MQ_MAX, gType, gTag, outError)) return false;
            newCfg.mq2Sensors[gIdx].enabled = g["enabled"] | true;
            newCfg.mq2Sensors[gIdx].type    = gType;
            if (gType == GAS_SGP40) {
                uint8_t addr = 0x59;
                if (!readByteRangeField(g, "i2c_addr", 0x59, 127, addr, gTag + F(" i2c_addr"), outError)) return false;
                if (addr == 0) addr = 0x59;
                newCfg.mq2Sensors[gIdx].analogPin  = PIN_UNUSED;
                newCfg.mq2Sensors[gIdx].digitalPin = PIN_UNUSED;
                newCfg.mq2Sensors[gIdx].i2cAddr    = addr;
            } else {
                uint8_t aPin = PIN_UNUSED, dPin = PIN_UNUSED;
                if (!readPinField(g, "analog_pin", PIN_UNUSED, aPin, gTag + F(" Analog"), outError)) return false;
                if (!readPinField(g, "digital_pin", PIN_UNUSED, dPin, gTag + F(" Digital"), outError)) return false;
                newCfg.mq2Sensors[gIdx].analogPin  = aPin;
                newCfg.mq2Sensors[gIdx].digitalPin = dPin;
                newCfg.mq2Sensors[gIdx].i2cAddr    = 0;
            }
            assignDefaultLabel(newCfg.mq2Sensors[gIdx].label, sizeof(newCfg.mq2Sensors[gIdx].label),
                               g["label"] | "", gType == GAS_SGP40 ? "SGP40" : "Gas", gIdx);
            gIdx++;
        }
        newCfg.numMq2s = gIdx;
    } else if (obj.containsKey("mq2")) {
        JsonObjectConst mq2 = obj["mq2"];
        bool en = mq2["enabled"] | true;
        if (en) {
            uint8_t aPin = defMq2APin, dPin = defMq2DPin;
            if (!readPinField(mq2, "analog_pin", defMq2APin, aPin, F("MQ-2 Analog"), outError)) return false;
            if (!readPinField(mq2, "digital_pin", defMq2DPin, dPin, F("MQ-2 Digital"), outError)) return false;
            newCfg.numMq2s = 1;
            newCfg.mq2Sensors[0].enabled    = true;
            newCfg.mq2Sensors[0].type       = GAS_MQ2;
            newCfg.mq2Sensors[0].analogPin  = aPin;
            newCfg.mq2Sensors[0].digitalPin = dPin;
            newCfg.mq2Sensors[0].i2cAddr    = 0;
            assignDefaultLabel(newCfg.mq2Sensors[0].label, sizeof(newCfg.mq2Sensors[0].label), nullptr, "Gas", 0);
        }
    } else {
        newCfg.numMq2s = 0;
    }

    if (obj.containsKey("buzzer")) {
        JsonObjectConst buz = obj["buzzer"];
        newCfg.buzzerEnabled = buz["enabled"] | false;
        if (!readPinField(buz, "pin", PIN_UNUSED, newCfg.buzzerPin, F("Buzzer"), outError)) return false;
    } else {
        newCfg.buzzerEnabled = false;
        newCfg.buzzerPin     = PIN_UNUSED;
    }

    if (obj.containsKey("lcd")) {
        JsonObjectConst lcd = obj["lcd"];
        newCfg.lcdEnabled  = lcd["enabled"] | false;
        if (!readByteRangeField(lcd, "i2c_addr", 0x27, 127, newCfg.lcdI2cAddr, F("LCD i2c_addr"), outError)) return false;
        if (!readByteRangeField(lcd, "cols", 16, 40, newCfg.lcdCols, F("LCD cols"), outError)) return false;
        if (!readByteRangeField(lcd, "rows", 2, 4, newCfg.lcdRows, F("LCD rows"), outError)) return false;
        if (!readPinField(lcd, "sda_pin", PIN_UNUSED, newCfg.i2cSdaPin, F("I2C SDA"), outError)) return false;
        if (!readPinField(lcd, "scl_pin", PIN_UNUSED, newCfg.i2cSclPin, F("I2C SCL"), outError)) return false;
    } else {
        newCfg.lcdEnabled  = false;
        newCfg.lcdI2cAddr = 0x27;
        newCfg.lcdCols    = 16;
        newCfg.lcdRows    = 2;
        newCfg.i2cSdaPin  = PIN_UNUSED;
        newCfg.i2cSclPin  = PIN_UNUSED;
    }

    if (!readPinField(obj, "btn_multi_pin", PIN_UNUSED, newCfg.btnMultiPin, F("Multi-Button"), outError)) return false;
    (void)defBtnPin;

    return validateConfig(newCfg, outError);
}

bool HardwareManager::validateHardwareJson(JsonObjectConst obj, String& outError) {
    HardwareConfig tmpCfg;
    return parseHardwareJson(obj, tmpCfg, outError);
}

bool HardwareManager::fromJson(JsonObjectConst obj, String& outError) {
    HardwareConfig newCfg;
    if (!parseHardwareJson(obj, newCfg, outError)) {
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
        SERIAL_PRINTF("[Hardware] Error parsing hardware.json: %s\n", err.c_str());
        return false;
    }
    return true;
}

// ============================================================================
// Presets
// ============================================================================
static void initPresetBase(HardwareConfig& cfg, const char* name, uint8_t numRelays,
                           const uint8_t* relayPins, const uint8_t* switchPins,
                           SwitchMode swMode = SWITCH_MODE_TOGGLE) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.boardName, name, sizeof(cfg.boardName) - 1);
    cfg.numRelays = numRelays;
    for (int i = 0; i < MAX_RELAYS; i++) {
        bool active = (i < numRelays);
        uint8_t rp = (active && relayPins) ? relayPins[i] : PIN_UNUSED;
        uint8_t sp = (active && switchPins) ? switchPins[i] : PIN_UNUSED;
        cfg.channels[i].enabled       = active;
        cfg.channels[i].relayPin      = rp;
        cfg.channels[i].switchEnabled = active && (sp != PIN_UNUSED);
        cfg.channels[i].switchPin     = sp;
        cfg.channels[i].switchMode    = swMode;
        cfg.channels[i].triggerMode   = TRIGGER_ACTIVE_LOW;
    }
    cfg.lcdI2cAddr  = 0x27;
    cfg.lcdCols     = 16;
    cfg.lcdRows     = 2;
    cfg.i2cSdaPin   = PIN_UNUSED;
    cfg.i2cSclPin   = PIN_UNUSED;
    cfg.buzzerPin   = PIN_UNUSED;
    cfg.btnMultiPin = PIN_UNUSED;
}

static void addPresetClimate(HardwareConfig& cfg, ClimateSensorType t, uint8_t pin, uint8_t addr = 0) {
    if (cfg.numClimates >= MAX_CLIMATE_SENSORS || t == CLIMATE_NONE) return;
    uint8_t idx = cfg.numClimates++;
    cfg.climates[idx].type    = t;
    cfg.climates[idx].pin     = pin;
    cfg.climates[idx].i2cAddr = addr;
    assignDefaultLabel(cfg.climates[idx].label, sizeof(cfg.climates[idx].label), nullptr, "Climate", idx);
}

static void addPresetMq2(HardwareConfig& cfg, uint8_t aPin, uint8_t dPin, bool enabled = false) {
    if (cfg.numMq2s >= MAX_MQ2_SENSORS) return;
    uint8_t idx = cfg.numMq2s++;
    cfg.mq2Sensors[idx].enabled    = enabled;
    cfg.mq2Sensors[idx].type       = GAS_MQ2;
    cfg.mq2Sensors[idx].analogPin  = aPin;
    cfg.mq2Sensors[idx].digitalPin = dPin;
    cfg.mq2Sensors[idx].i2cAddr    = 0;
    assignDefaultLabel(cfg.mq2Sensors[idx].label, sizeof(cfg.mq2Sensors[idx].label), nullptr, "Gas", idx);
}

void HardwareManager::setPreset5CH(HardwareConfig& cfg) {
    const uint8_t rPins[5] = {16, 17, 18, 19, 23};
    const uint8_t sPins[5] = {13, 14, 27, 26, 25};
    initPresetBase(cfg, "SmartHome 5-CH Standard", 5, rPins, sPins);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    addPresetMq2(cfg, 34, 35);
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 21;
    cfg.i2cSclPin     = 22;
    cfg.btnMultiPin   = 33;
}

void HardwareManager::setPreset1CH(HardwareConfig& cfg) {
    const uint8_t rPins[1] = {16};
    const uint8_t sPins[1] = {13};
    initPresetBase(cfg, "SmartHome 1-CH Mini", 1, rPins, sPins, SWITCH_MODE_PUSHBUTTON);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    cfg.btnMultiPin = 33;
}

void HardwareManager::setPreset2CH(HardwareConfig& cfg) {
    const uint8_t rPins[2] = {16, 17};
    const uint8_t sPins[2] = {13, 14};
    initPresetBase(cfg, "SmartHome 2-CH Dual", 2, rPins, sPins);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    addPresetMq2(cfg, 34, 35);
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 21;
    cfg.i2cSclPin     = 22;
    cfg.btnMultiPin   = 33;
}

void HardwareManager::setPreset4CH(HardwareConfig& cfg) {
    const uint8_t rPins[4] = {16, 17, 18, 19};
    const uint8_t sPins[4] = {13, 14, 27, 26};
    initPresetBase(cfg, "SmartHome 4-CH Pro", 4, rPins, sPins);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    addPresetMq2(cfg, 34, 35);
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 21;
    cfg.i2cSclPin     = 22;
    cfg.btnMultiPin   = 33;
}

void HardwareManager::setPreset8CH(HardwareConfig& cfg) {
    const uint8_t rPins[8] = {16, 17, 18, 19, 23, 25, 26, 27};
    initPresetBase(cfg, "SmartHome 8-CH Max", 8, rPins, nullptr);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 21;
    cfg.i2cSclPin     = 22;
    cfg.btnMultiPin   = 33;
}

void HardwareManager::setPresetSensorNode(HardwareConfig& cfg) {
    initPresetBase(cfg, "SmartHome Sensor Node", 0, nullptr, nullptr);

    addPresetClimate(cfg, CLIMATE_DHT22, 4);
    addPresetMq2(cfg, 34, 35);
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 5;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 21;
    cfg.i2cSclPin     = 22;
    cfg.btnMultiPin   = 33;
}

void HardwareManager::setPresetESP8266_2CH(HardwareConfig& cfg) {
    const uint8_t rPins[2] = {12, 14}; // D6, D5
    const uint8_t sPins[2] = {13, 16}; // D7 (pullup), D0 (wake)
    initPresetBase(cfg, "SmartHome ESP8266 2-CH Dual", 2, rPins, sPins);

    addPresetMq2(cfg, 17, PIN_UNUSED); // A0
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2; // D4
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 4; // D2
    cfg.i2cSclPin     = 5; // D1
    cfg.btnMultiPin   = 0; // D3 / FLASH button
}

void HardwareManager::setPresetESP8266_1CH(HardwareConfig& cfg) {
    const uint8_t rPins[1] = {12}; // D6
    const uint8_t sPins[1] = {13}; // D7
    initPresetBase(cfg, "SmartHome ESP8266 1-CH Mini", 1, rPins, sPins, SWITCH_MODE_PUSHBUTTON);

    addPresetClimate(cfg, CLIMATE_DHT22, 14); // D5
    addPresetMq2(cfg, 17, PIN_UNUSED);       // A0
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 4;
    cfg.i2cSclPin     = 5;
    cfg.btnMultiPin   = 0;
}

void HardwareManager::setPresetESP8266_3CH(HardwareConfig& cfg) {
    const uint8_t rPins[3] = {12, 14, 15}; // D6, D5, D8
    const uint8_t sPins[3] = {13, 16, PIN_UNUSED}; // D7, D0
    initPresetBase(cfg, "SmartHome ESP8266 3-CH Pro", 3, rPins, sPins);

    addPresetMq2(cfg, 17, PIN_UNUSED); // A0
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 4;
    cfg.i2cSclPin     = 5;
    cfg.btnMultiPin   = 0;
}

void HardwareManager::setPresetESP8266_SensorNode(HardwareConfig& cfg) {
    initPresetBase(cfg, "SmartHome ESP8266 Sensor Node", 0, nullptr, nullptr);

    addPresetClimate(cfg, CLIMATE_DHT22, 12); // D6
    addPresetMq2(cfg, 17, PIN_UNUSED);        // A0
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2;
    cfg.lcdEnabled    = true;
    cfg.i2cSdaPin     = 4;
    cfg.i2cSclPin     = 5;
    cfg.btnMultiPin   = 0;

    cfg.numMotions = 1;
    cfg.motions[0].type = MOTION_PIR;
    cfg.motions[0].pin  = 14; // D5
    assignDefaultLabel(cfg.motions[0].label, sizeof(cfg.motions[0].label), nullptr, "Motion", 0);

    cfg.numProbes = 1;
    cfg.probes[0].type = PROBE_DS18B20;
    cfg.probes[0].pin  = 13; // D7
    assignDefaultLabel(cfg.probes[0].label, sizeof(cfg.probes[0].label), nullptr, "Probe", 0);
}

void HardwareManager::setPresetESP8266_4CH(HardwareConfig& cfg) {
    const uint8_t rPins[4] = {12, 14, 4, 5}; // D6, D5, D2, D1
    const uint8_t sPins[4] = {13, 16, PIN_UNUSED, PIN_UNUSED}; // D7, D0
    initPresetBase(cfg, "SmartHome ESP8266 4-CH Quad", 4, rPins, sPins);

    addPresetMq2(cfg, 17, PIN_UNUSED); // A0
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2; // D4
    cfg.btnMultiPin   = 0; // D3 / FLASH
}

void HardwareManager::setPresetESP8266_8CH(HardwareConfig& cfg) {
    // 8 Relays on ESP8266:
    // GPIO 12 (D6), GPIO 14 (D5), GPIO 4 (D2), GPIO 5 (D1),
    // GPIO 13 (D7), GPIO 15 (D8), GPIO 0 (D3), GPIO 16 (D0)
    const uint8_t rPins[8] = {12, 14, 4, 5, 13, 15, 0, 16};
    initPresetBase(cfg, "SmartHome ESP8266 8-CH Max", 8, rPins, nullptr);

    addPresetMq2(cfg, 17, PIN_UNUSED); // A0 (ADC0)
    cfg.buzzerEnabled = true;
    cfg.buzzerPin     = 2; // D4
}

void HardwareManager::getPresetsJson(JsonArray& arr) {
#if defined(ESP8266)
    const char* presets[] = {
        "SmartHome ESP8266 2-CH Dual",
        "SmartHome ESP8266 1-CH Mini",
        "SmartHome ESP8266 3-CH Pro",
        "SmartHome ESP8266 4-CH Quad",
        "SmartHome ESP8266 8-CH Max",
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
    const uint8_t safeInputs[] = {0, 2, 4, 5, 12, 13, 14, 15, 16};
    for (uint8_t p : safeInputs) inputs.add(p);

    JsonArray adc1 = obj["adc1"].to<JsonArray>();
    adc1.add(17);

    JsonArray inputOnly = obj["input_only"].to<JsonArray>();
    inputOnly.add(17);

    JsonArray strapping = obj["strapping"].to<JsonArray>();
    const uint8_t strapPins[] = {0, 2, 15};
    for (uint8_t p : strapPins) strapping.add(p);
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

    JsonArray strapping = obj["strapping"].to<JsonArray>();
    const uint8_t strapPins[] = {0, 2, 12, 15};
    for (uint8_t p : strapPins) strapping.add(p);
#endif

    JsonObject limits = obj["sensor_limits"].to<JsonObject>();
    limits["relays"]      = MAX_RELAYS;
    limits["climates"]    = MAX_CLIMATE_SENSORS;
    limits["lights"]      = MAX_LIGHT_SENSORS;
    limits["motions"]     = MAX_MOTION_SENSORS;
    limits["probes"]      = MAX_PROBE_SENSORS;
    limits["ultrasonics"] = MAX_ULTRASONIC_SENSORS;
    limits["mq2s"]        = MAX_MQ2_SENSORS;
}
