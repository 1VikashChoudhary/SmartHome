/*
 * ============================================================================
 * SensorManager.cpp — Universal Sensor Subsystem Implementation
 * ============================================================================
 * Supports:
 *  - Climate: DHT11, DHT22/AM2302 (1-Wire bit-bang),
 *             DS18B20 (1-Wire GPIO Ambient Temperature),
 *             BME280/BMP280 (I2C 0x76/0x77),
 *             AHT20 (I2C 0x38),
 *             SHT31 / SHT3x (I2C 0x44/0x45),
 *             SHT40 / SHT45 (I2C 0x44/0x45)
 *  - Optics:  BH1750 Ambient Light (I2C 0x23/0x5C)
 *  - Motion:  PIR / LD2410 mmWave Radar (Digital GPIO)
 *  - Probe:   DS18B20 Submersible Water Temperature (1-Wire GPIO)
 *  - Tank:    HC-SR04P / HC-SR04 / JSN-SR04T Ultrasonic Distance & Water Level
 *  - Gas/VOC: MQ-2 Analog/Digital Gas & Smoke, SGP40 I2C (0x59) VOC Index
 * ============================================================================
 */

#include "SensorManager.h"
#include "HardwareManager.h"
#include <Wire.h>
#include <math.h>

static bool isI2cClimateSlotType(uint8_t t) {
    return (t == CLIMATE_BME280 || t == CLIMATE_AHT20 ||
            t == CLIMATE_SHT3X || t == CLIMATE_SHT4X);
}

static uint8_t sensirionCrc8(const uint8_t* data, size_t len) {
    uint8_t crc = 0xFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t b = 0; b < 8; b++) {
            crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x31) : (uint8_t)(crc << 1);
        }
    }
    return crc;
}

SensorManager::SensorManager()
    : _storage(nullptr),
      _bootTime(0),
      _tempAlarmThreshold(DHT_TEMP_ALARM_DEFAULT),
      _climateCount(0),
      _lightCount(0),
      _motionCount(0),
      _probeCount(0),
      _ultrasonicCount(0),
      _mq2Count(0),
      _lastDHTRead(0),
      _dhtPollCursor(0),
      _lastEnvRead(0),
      _envPollCursor(0),
      _lastLuxRead(0),
      _lastMQ2Read(0),
      _lastUltrasonicRead(0),
      _ultrasonicCursor(0),
      _ds18State(0),
      _ds18Cursor(0),
      _ds18ConvertStart(0),
      _lastProbeCycle(0),
      _alarmCallback(nullptr),
      _prevTempAlarm(false),
      _prevMQ2Alarm(false),
      _prevSensorFault(false) {
    memset(_climates, 0, sizeof(_climates));
    memset(_lights, 0, sizeof(_lights));
    memset(_motions, 0, sizeof(_motions));
    memset(_probes, 0, sizeof(_probes));
    memset(_ultrasonics, 0, sizeof(_ultrasonics));
    memset(_mq2s, 0, sizeof(_mq2s));
    for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS; i++) {
        _climates[i].pin = PIN_UNUSED;
        snprintf(_climates[i].label, sizeof(_climates[i].label), "Climate %u", (unsigned)(i + 1));
    }
    for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
        _mq2s[i].analogPin = PIN_UNUSED;
        _mq2s[i].digitalPin = PIN_UNUSED;
        _mq2s[i].baseline = MQ2_BASELINE_DEFAULT;
        _mq2s[i].threshold = MQ2_DEFAULT_THRESHOLD;
        snprintf(_mq2s[i].label, sizeof(_mq2s[i].label), "Gas %u", (unsigned)(i + 1));
    }
}

SensorManager::~SensorManager() {
    cleanup();
}

void SensorManager::cleanup() {
    for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS; i++) {
        if (_climates[i].dht) {
            delete _climates[i].dht;
            _climates[i].dht = nullptr;
        }
        if (_climates[i].bmeCalib) {
            delete _climates[i].bmeCalib;
            _climates[i].bmeCalib = nullptr;
        }
        _climates[i].enabled = false;
        _climates[i].type = CLIMATE_NONE;
        _climates[i].pin = PIN_UNUSED;
        _climates[i].i2cAddr = 0;
        _climates[i].i2cDetected = false;
        _climates[i].bmpDetected = false;
        _climates[i].temperature = 0;
        _climates[i].humidity = 0;
        _climates[i].rawTemperature = 0;
        _climates[i].rawHumidity = 0;
        _climates[i].pressure = 0;
        _climates[i].rawPressure = 0;
        _climates[i].tempOffset = DHT_TEMP_OFFSET_DEFAULT;
        _climates[i].humOffset = DHT_HUM_OFFSET_DEFAULT;
        _climates[i].fault = false;
        _climates[i].failCount = 0;
        _climates[i].lastFaultRetry = 0;
        _climates[i].measPending = false;
        _climates[i].measStartMs = 0;
        _climates[i].tFine = 0;
    }
    memset(_lights, 0, sizeof(_lights));
    memset(_motions, 0, sizeof(_motions));
    memset(_probes, 0, sizeof(_probes));
    memset(_ultrasonics, 0, sizeof(_ultrasonics));
    for (uint8_t i = 0; i < MAX_MOTION_SENSORS; i++) _motions[i].pin = PIN_UNUSED;
    for (uint8_t i = 0; i < MAX_PROBE_SENSORS; i++) {
        _probes[i].pin = PIN_UNUSED;
        _probes[i].temperature = -127.0f;
    }
    for (uint8_t i = 0; i < MAX_ULTRASONIC_SENSORS; i++) {
        _ultrasonics[i].trigPin = PIN_UNUSED;
        _ultrasonics[i].echoPin = PIN_UNUSED;
        _ultrasonics[i].tankDepthCm = 150;
        _ultrasonics[i].tankAirGapCm = 15;
    }
    for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
        _mq2s[i].hwAllowed = false;
        _mq2s[i].enabled = false;
        _mq2s[i].type = GAS_MQ2;
        _mq2s[i].analogPin = PIN_UNUSED;
        _mq2s[i].digitalPin = PIN_UNUSED;
        _mq2s[i].i2cAddr = 0;
        _mq2s[i].i2cDetected = false;
        _mq2s[i].measPending = false;
        _mq2s[i].measStartMs = 0;
        _mq2s[i].lastReadMs = 0;
        _mq2s[i].srawTicks = 0;
        _mq2s[i].vocBaseline = 0.0f;
        _mq2s[i].raw = 0;
        _mq2s[i].baseline = MQ2_BASELINE_DEFAULT;
        _mq2s[i].threshold = MQ2_DEFAULT_THRESHOLD;
        _mq2s[i].digitalState = false;
        _mq2s[i].alarmActive = false;
    }
    _climateCount = 0;
    _lightCount = 0;
    _motionCount = 0;
    _probeCount = 0;
    _ultrasonicCount = 0;
    _mq2Count = 0;
    _ds18State = 0;
    _ds18Cursor = 0;
    _dhtPollCursor = 0;
    _envPollCursor = 0;
    _ultrasonicCursor = 0;
}

void SensorManager::begin(StorageManager& storage) {
    cleanup();
    _storage = &storage;
    _bootTime = millis();

    if (PIN_DHT22 != PIN_UNUSED) {
        _climateCount = 1;
        _climates[0].enabled = true;
        _climates[0].type = (DHT_TYPE == DHT11) ? CLIMATE_DHT11 : CLIMATE_DHT22;
        _climates[0].pin = PIN_DHT22;
        snprintf(_climates[0].label, sizeof(_climates[0].label), "Climate 1");
        _climates[0].dht = new DHT(PIN_DHT22, DHT_TYPE);
        _climates[0].dht->begin();
    }

    _mq2Count = 1;
    _mq2s[0].analogPin = PIN_MQ2_ANALOG;
    _mq2s[0].digitalPin = PIN_MQ2_DIGITAL;
    _mq2s[0].hwAllowed = (_mq2s[0].analogPin != PIN_UNUSED || _mq2s[0].digitalPin != PIN_UNUSED);
    _mq2s[0].enabled = _mq2s[0].hwAllowed;
    if (_mq2s[0].digitalPin != PIN_UNUSED) pinMode(_mq2s[0].digitalPin, INPUT);

    loadCalibration();
    if (!_mq2s[0].hwAllowed) _mq2s[0].enabled = false;

    Serial.println(F("[Sensor] Initialized (legacy defaults)"));
}

void SensorManager::begin(StorageManager& storage, HardwareManager& hw) {
    cleanup();
    _storage = &storage;
    _bootTime = millis();

    // Ensure I2C bus is initialized if any I2C sensor or LCD is configured
    if ((hw.hasAnyI2cSensor() || hw.isLcdEnabled()) &&
        hw.getI2cSdaPin() != PIN_UNUSED && hw.getI2cSclPin() != PIN_UNUSED) {
        Wire.begin(hw.getI2cSdaPin(), hw.getI2cSclPin());
    }

    // 1. Climate Sensors (DHT11/22 + BME280/AHT20/SHT3X)
    _climateCount = hw.getClimateCount();
    if (_climateCount > MAX_CLIMATE_SENSORS) _climateCount = MAX_CLIMATE_SENSORS;

    auto climateAddrClaimedByOther = [&](uint8_t selfIdx, uint8_t addr) -> bool {
        for (uint8_t j = 0; j < _climateCount; j++) {
            if (j == selfIdx) continue;
            const ClimateSensorConfig* oc = hw.getClimate(j);
            if (!oc || !isI2cClimateSlotType(oc->type)) continue;
            uint8_t oAddr = oc->i2cAddr ? oc->i2cAddr : HardwareManager::defaultI2cAddrForClimate(oc->type);
            if (oAddr == addr || _climates[j].i2cAddr == addr) return true;
        }
        return false;
    };

    for (uint8_t i = 0; i < _climateCount; i++) {
        const ClimateSensorConfig* cfg = hw.getClimate(i);
        if (!cfg) continue;
        ClimateSlotState& s = _climates[i];
        s.type = (uint8_t)cfg->type;
        s.pin = cfg->pin;
        s.i2cAddr = cfg->i2cAddr ? cfg->i2cAddr : HardwareManager::defaultI2cAddrForClimate(cfg->type);
        strncpy(s.label, cfg->label[0] ? cfg->label : "Climate", sizeof(s.label) - 1);
        s.label[sizeof(s.label) - 1] = '\0';

        if (cfg->type == CLIMATE_DHT11 || cfg->type == CLIMATE_DHT22) {
            if (cfg->pin != PIN_UNUSED) {
                uint8_t model = (cfg->type == CLIMATE_DHT11) ? DHT11 : DHT22;
                s.dht = new DHT(cfg->pin, model);
                s.dht->begin();
                s.enabled = true;
            }
        } else if (cfg->type == CLIMATE_BME280) {
            s.enabled = true;
            if (!initBME280(s, s.i2cAddr)) {
                uint8_t altAddr = (s.i2cAddr == 0x76) ? 0x77 : 0x76;
                if (!climateAddrClaimedByOther(i, altAddr) && initBME280(s, altAddr)) {
                    // fallback succeeded
                } else {
                    s.fault = true;
                    s.lastFaultRetry = _bootTime;
                    SERIAL_PRINTF("[Sensor] Climate %u BME280/BMP280 not responding at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
                }
            }
        } else if (cfg->type == CLIMATE_AHT20) {
            s.enabled = true;
            if (!initAHT20(s, s.i2cAddr ? s.i2cAddr : 0x38)) {
                s.fault = true;
                s.lastFaultRetry = _bootTime;
                SERIAL_PRINTF("[Sensor] Climate %u AHT20 not responding at 0x38\n", (unsigned)(i + 1));
            }
        } else if (cfg->type == CLIMATE_SHT3X) {
            s.enabled = true;
            if (!initSHT3x(s, s.i2cAddr)) {
                uint8_t altAddr = (s.i2cAddr == 0x44) ? 0x45 : 0x44;
                if (!climateAddrClaimedByOther(i, altAddr) && initSHT3x(s, altAddr)) {
                    // fallback succeeded
                } else {
                    s.fault = true;
                    s.lastFaultRetry = _bootTime;
                    SERIAL_PRINTF("[Sensor] Climate %u SHT3x not responding at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
                }
            }
        } else if (cfg->type == CLIMATE_SHT4X) {
            s.enabled = true;
            if (!initSHT4x(s, s.i2cAddr)) {
                uint8_t altAddr = (s.i2cAddr == 0x44) ? 0x45 : 0x44;
                if (!climateAddrClaimedByOther(i, altAddr) && initSHT4x(s, altAddr)) {
                    // fallback succeeded
                } else {
                    s.fault = true;
                    s.lastFaultRetry = _bootTime;
                    SERIAL_PRINTF("[Sensor] Climate %u SHT40/SHT45 not responding at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
                }
            }
        } else if (cfg->type == CLIMATE_DS18B20) {
            if (cfg->pin != PIN_UNUSED) {
                pinMode(cfg->pin, INPUT_PULLUP);
                s.enabled = true;
                s.humidity = 0.0f;
                SERIAL_PRINTF("[Sensor] Climate %u DS18B20 1-Wire on GPIO %d\n", (unsigned)(i + 1), s.pin);
            }
        }
    }

    // 2. BH1750 Ambient Light Sensors
    _lightCount = hw.getLightCount();
    if (_lightCount > MAX_LIGHT_SENSORS) _lightCount = MAX_LIGHT_SENSORS;

    auto lightAddrClaimedByOther = [&](uint8_t selfIdx, uint8_t addr) -> bool {
        for (uint8_t j = 0; j < _lightCount; j++) {
            if (j == selfIdx) continue;
            const LightSensorConfig* ol = hw.getLight(j);
            if (!ol || ol->type != LIGHT_BH1750) continue;
            uint8_t oAddr = ol->i2cAddr ? ol->i2cAddr : 0x23;
            if (oAddr == addr || _lights[j].i2cAddr == addr) return true;
        }
        return false;
    };

    for (uint8_t i = 0; i < _lightCount; i++) {
        const LightSensorConfig* cfg = hw.getLight(i);
        if (!cfg || cfg->type != LIGHT_BH1750) continue;
        LightSlotState& s = _lights[i];
        s.enabled = true;
        s.i2cAddr = cfg->i2cAddr ? cfg->i2cAddr : 0x23;
        strncpy(s.label, cfg->label[0] ? cfg->label : "Light", sizeof(s.label) - 1);
        s.label[sizeof(s.label) - 1] = '\0';
        if (initBH1750(s, s.i2cAddr)) {
            s.detected = true;
            SERIAL_PRINTF("[Sensor] BH1750 #%u detected at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
        } else {
            uint8_t alt = (s.i2cAddr == 0x23) ? 0x5C : 0x23;
            if (!lightAddrClaimedByOther(i, alt) && initBH1750(s, alt)) {
                s.detected = true;
                SERIAL_PRINTF("[Sensor] BH1750 #%u detected at fallback 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
            } else {
                s.detected = false;
                SERIAL_PRINTF("[Sensor] BH1750 #%u not responding at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
            }
        }
    }

    // 3. Motion / Occupancy Sensors
    _motionCount = hw.getMotionCount();
    if (_motionCount > MAX_MOTION_SENSORS) _motionCount = MAX_MOTION_SENSORS;
    for (uint8_t i = 0; i < _motionCount; i++) {
        const MotionSensorConfig* cfg = hw.getMotion(i);
        if (!cfg || cfg->type == MOTION_NONE || cfg->pin == PIN_UNUSED) continue;
        MotionSlotState& s = _motions[i];
        s.enabled = true;
        s.type = (uint8_t)cfg->type;
        s.pin = cfg->pin;
        strncpy(s.label, cfg->label[0] ? cfg->label : "Motion", sizeof(s.label) - 1);
        s.label[sizeof(s.label) - 1] = '\0';
        pinMode(s.pin, INPUT);
        s.detected = (digitalRead(s.pin) == HIGH);
        s.lastMotionTime = s.detected ? _bootTime : 0;
        SERIAL_PRINTF("[Sensor] Motion #%u on GPIO %d\n", (unsigned)(i + 1), s.pin);
    }

    // 4. Submersible Water Temp Probes (DS18B20)
    _probeCount = hw.getProbeCount();
    if (_probeCount > MAX_PROBE_SENSORS) _probeCount = MAX_PROBE_SENSORS;
    for (uint8_t i = 0; i < _probeCount; i++) {
        const ProbeSensorConfig* cfg = hw.getProbe(i);
        if (!cfg || cfg->type != PROBE_DS18B20 || cfg->pin == PIN_UNUSED) continue;
        ProbeSlotState& s = _probes[i];
        s.enabled = true;
        s.pin = cfg->pin;
        s.temperature = -127.0f;
        s.fault = false;
        strncpy(s.label, cfg->label[0] ? cfg->label : "Probe", sizeof(s.label) - 1);
        s.label[sizeof(s.label) - 1] = '\0';
        pinMode(s.pin, INPUT_PULLUP);
        SERIAL_PRINTF("[Sensor] DS18B20 Probe #%u on GPIO %d\n", (unsigned)(i + 1), s.pin);
    }

    // 5. Ultrasonic Tank Level Sensors
    _ultrasonicCount = hw.getUltrasonicCount();
    if (_ultrasonicCount > MAX_ULTRASONIC_SENSORS) _ultrasonicCount = MAX_ULTRASONIC_SENSORS;
    for (uint8_t i = 0; i < _ultrasonicCount; i++) {
        const UltrasonicSensorConfig* cfg = hw.getUltrasonic(i);
        if (!cfg || cfg->type == ULTRASONIC_NONE || cfg->trigPin == PIN_UNUSED || cfg->echoPin == PIN_UNUSED) continue;
        UltrasonicSlotState& s = _ultrasonics[i];
        s.enabled = true;
        s.type = (uint8_t)cfg->type;
        s.trigPin = cfg->trigPin;
        s.echoPin = cfg->echoPin;
        s.tankDepthCm = cfg->tankDepthCm;
        s.tankAirGapCm = cfg->tankAirGapCm;
        strncpy(s.label, cfg->label[0] ? cfg->label : "Tank", sizeof(s.label) - 1);
        s.label[sizeof(s.label) - 1] = '\0';
        pinMode(s.trigPin, OUTPUT);
        digitalWrite(s.trigPin, LOW);
        pinMode(s.echoPin, INPUT);
        SERIAL_PRINTF("[Sensor] Ultrasonic Tank #%u: Trig %d, Echo %d\n", (unsigned)(i + 1), s.trigPin, s.echoPin);
    }

    // 6. Gas & Air Quality Sensors (MQ-2 / SGP40)
    _mq2Count = hw.getMq2Count();
    if (_mq2Count > MAX_MQ2_SENSORS) _mq2Count = MAX_MQ2_SENSORS;
    for (uint8_t i = 0; i < _mq2Count; i++) {
        const Mq2SensorConfig* cfg = hw.getMq2(i);
        if (!cfg) continue;
        Mq2SlotState& s = _mq2s[i];
        s.type = cfg->type;
        if (cfg->type == GAS_SGP40) {
            s.analogPin = PIN_UNUSED;
            s.digitalPin = PIN_UNUSED;
            s.i2cAddr = cfg->i2cAddr ? cfg->i2cAddr : 0x59;
            s.hwAllowed = cfg->enabled &&
                          (hw.getI2cSdaPin() != PIN_UNUSED && hw.getI2cSclPin() != PIN_UNUSED);
            s.enabled = s.hwAllowed;
            s.baseline = 0;
            s.threshold = 250; // Default SGP40 VOC Index alarm threshold (10..500)
            s.vocBaseline = 0.0f;
            strncpy(s.label, cfg->label[0] ? cfg->label : "SGP40", sizeof(s.label) - 1);
            s.label[sizeof(s.label) - 1] = '\0';
            if (s.enabled) {
                if (initSGP40(s, s.i2cAddr)) {
                    SERIAL_PRINTF("[Sensor] Gas #%u SGP40 VOC detected at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
                } else {
                    SERIAL_PRINTF("[Sensor] Gas #%u SGP40 not responding at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
                }
            }
        } else {
            s.i2cAddr = 0;
            s.analogPin = cfg->enabled ? cfg->analogPin : PIN_UNUSED;
            s.digitalPin = cfg->enabled ? cfg->digitalPin : PIN_UNUSED;
            s.hwAllowed = cfg->enabled && (s.analogPin != PIN_UNUSED || s.digitalPin != PIN_UNUSED);
            s.enabled = s.hwAllowed;
            strncpy(s.label, cfg->label[0] ? cfg->label : "Gas", sizeof(s.label) - 1);
            s.label[sizeof(s.label) - 1] = '\0';
            if (s.digitalPin != PIN_UNUSED) {
                pinMode(s.digitalPin, INPUT);
            }
        }
    }

    loadCalibration();
    for (uint8_t i = 0; i < _mq2Count; i++) {
        if (!_mq2s[i].hwAllowed) _mq2s[i].enabled = false;
    }

    SERIAL_PRINTF("[Sensor] Multi-sensor init: C=%d L=%d M=%d P=%d U=%d G=%d\n",
                  _climateCount, _lightCount, _motionCount, _probeCount, _ultrasonicCount, _mq2Count);
}

void SensorManager::loop() {
    unsigned long now = millis();

    // --- 1. DHT11 / DHT22 staggered round-robin ---
    uint8_t dhtSlots = 0;
    for (uint8_t i = 0; i < _climateCount; i++) {
        if (_climates[i].enabled && _climates[i].dht != nullptr) dhtSlots++;
    }
    if (dhtSlots > 0) {
        unsigned long interval = DHT_READ_INTERVAL / dhtSlots;
        if (interval < 600) interval = 600;
        if (now - _lastDHTRead >= interval) {
            _lastDHTRead = now;
            for (uint8_t step = 0; step < _climateCount; step++) {
                uint8_t idx = (_dhtPollCursor + step) % _climateCount;
                ClimateSlotState& s = _climates[idx];
                if (!s.enabled || s.dht == nullptr) continue;
                // Back off faulted/unwired DHT slots to every 15s to avoid 250ms loop stalls every 2s
                if (s.fault && s.lastFaultRetry != 0 && (now - s.lastFaultRetry < 15000UL)) {
                    continue;
                }
                _dhtPollCursor = (idx + 1) % _climateCount;
                s.lastFaultRetry = now;

                float t = s.dht->readTemperature();
                float h = s.dht->readHumidity();
                if (isnan(t) || isnan(h)) {
                    if (s.failCount < 255) s.failCount++;
                    if (s.failCount >= DHT_FAIL_THRESHOLD && !s.fault) {
                        s.fault = true;
                        SERIAL_PRINTF("[Sensor] Climate #%u DHT FAULT\n", (unsigned)(idx + 1));
                    }
                } else {
                    s.failCount = 0;
                    if (s.fault) {
                        s.fault = false;
                        SERIAL_PRINTF("[Sensor] Climate #%u DHT recovered\n", (unsigned)(idx + 1));
                    }
                    s.rawTemperature = t;
                    s.rawHumidity = h;
                    s.temperature = t + s.tempOffset;
                    s.humidity = constrain(h + s.humOffset, 0.0f, 100.0f);
                }
                break;
            }
        }
    }

    // --- 1b. Climate DS18B20 (non-blocking 750ms conversion) ---
    for (uint8_t i = 0; i < _climateCount; i++) {
        ClimateSlotState& s = _climates[i];
        if (!s.enabled || s.type != CLIMATE_DS18B20 || s.pin == PIN_UNUSED) continue;
        if (s.measPending) {
            if (now - s.measStartMs >= 750UL) {
                readClimateDS18B20(s);
            }
        } else {
            unsigned long retryInt = s.fault ? 5000UL : DHT_READ_INTERVAL;
            if (s.lastFaultRetry == 0 || (now - s.lastFaultRetry >= retryInt)) {
                s.lastFaultRetry = now;
                if (ds18b20Reset(s.pin)) {
                    ds18b20WriteByte(s.pin, 0xCC); // SKIP ROM
                    ds18b20WriteByte(s.pin, 0x44); // CONVERT T
                    s.measPending = true;
                    s.measStartMs = now;
                } else {
                    if (s.failCount < 255) s.failCount++;
                    if (s.failCount >= DHT_FAIL_THRESHOLD && !s.fault) {
                        s.fault = true;
                        SERIAL_PRINTF("[Sensor] Climate #%u DS18B20 FAULT\n", (unsigned)(i + 1));
                    }
                }
            }
        }
    }

    // --- 2. I2C Climate (BME280 / AHT20 / SHT3x / SHT4x) staggered round-robin ---
    // Periodically retry initialization for I2C climate sensors connected or recovered after boot
    for (uint8_t i = 0; i < _climateCount; i++) {
        ClimateSlotState& s = _climates[i];
        if (!s.enabled || !isI2cClimateSlotType(s.type) || s.i2cDetected) continue;
        if (now - s.lastFaultRetry < 5000UL) continue;
        s.lastFaultRetry = now;
        bool recovered = false;
        if (s.type == CLIMATE_BME280)      recovered = initBME280(s, s.i2cAddr);
        else if (s.type == CLIMATE_AHT20)  recovered = initAHT20(s, s.i2cAddr ? s.i2cAddr : 0x38);
        else if (s.type == CLIMATE_SHT3X)  recovered = initSHT3x(s, s.i2cAddr);
        else if (s.type == CLIMATE_SHT4X)  recovered = initSHT4x(s, s.i2cAddr);
        if (recovered) {
            s.fault = false;
            SERIAL_PRINTF("[Sensor] Climate #%u I2C recovered at 0x%02X\n", (unsigned)(i + 1), s.i2cAddr);
        }
    }

    // Complete any pending non-blocking AHT20 / SHT3x / SHT4x conversions once their wait window elapses
    for (uint8_t i = 0; i < _climateCount; i++) {
        ClimateSlotState& s = _climates[i];
        if (!s.enabled || !s.i2cDetected || !s.measPending) continue;
        if (s.type == CLIMATE_AHT20 && (now - s.measStartMs >= 80UL)) {
            readAHT20(s);
        } else if (s.type == CLIMATE_SHT3X && (now - s.measStartMs >= 16UL)) {
            readSHT3x(s);
        } else if (s.type == CLIMATE_SHT4X && (now - s.measStartMs >= 12UL)) {
            readSHT4x(s);
        }
    }

    uint8_t i2cClimateSlots = 0;
    for (uint8_t i = 0; i < _climateCount; i++) {
        if (_climates[i].enabled && isI2cClimateSlotType(_climates[i].type) && _climates[i].i2cDetected) {
            i2cClimateSlots++;
        }
    }
    if (i2cClimateSlots > 0) {
        unsigned long interval = DHT_READ_INTERVAL / i2cClimateSlots;
        if (interval < 650) interval = 650;
        if (now - _lastEnvRead >= interval) {
            _lastEnvRead = now;
            for (uint8_t step = 0; step < _climateCount; step++) {
                uint8_t idx = (_envPollCursor + step) % _climateCount;
                ClimateSlotState& s = _climates[idx];
                if (!s.enabled || !isI2cClimateSlotType(s.type) || !s.i2cDetected || s.measPending) continue;
                _envPollCursor = (idx + 1) % _climateCount;
                if (s.type == CLIMATE_BME280)      readBME280(s);
                else if (s.type == CLIMATE_AHT20)  readAHT20(s);
                else if (s.type == CLIMATE_SHT3X)  readSHT3x(s);
                else if (s.type == CLIMATE_SHT4X)  readSHT4x(s);
                break;
            }
        }
    }

    // --- 3. BH1750 Ambient Light (every 1.0 second) ---
    if (_lightCount > 0 && (now - _lastLuxRead >= 1000)) {
        _lastLuxRead = now;
        for (uint8_t i = 0; i < _lightCount; i++) {
            if (_lights[i].enabled && _lights[i].detected) {
                readBH1750(_lights[i]);
            }
        }
    }

    // --- 4. Motion / Occupancy (every loop pass, 3s hold latch) ---
    for (uint8_t i = 0; i < _motionCount; i++) {
        MotionSlotState& s = _motions[i];
        if (!s.enabled || s.pin == PIN_UNUSED) continue;
        if (digitalRead(s.pin) == HIGH) {
            s.detected = true;
            s.lastMotionTime = now;
        } else if (now - s.lastMotionTime > 3000) {
            s.detected = false;
        }
    }

    // --- 5. DS18B20 1-Wire Probes (non-blocking staggered round-robin) ---
    uint8_t activeProbes = 0;
    for (uint8_t i = 0; i < _probeCount; i++) {
        if (_probes[i].enabled && _probes[i].pin != PIN_UNUSED) activeProbes++;
    }
    if (activeProbes > 0) {
        unsigned long waitMs = (activeProbes == 1) ? 2000UL : 250UL;
        if (_ds18State == 0 && (now - _lastProbeCycle >= waitMs)) {
            for (uint8_t step = 0; step < _probeCount; step++) {
                uint8_t idx = (_ds18Cursor + step) % _probeCount;
                ProbeSlotState& p = _probes[idx];
                if (!p.enabled || p.pin == PIN_UNUSED) continue;
                _ds18Cursor = idx;
                if (ds18b20Reset(p.pin)) {
                    ds18b20WriteByte(p.pin, 0xCC); // SKIP ROM
                    ds18b20WriteByte(p.pin, 0x44); // CONVERT T
                    _ds18ConvertStart = now;
                    _ds18State = 1;
                } else {
                    p.fault = true;
                    _ds18Cursor = (idx + 1) % _probeCount;
                    _lastProbeCycle = now;
                }
                break;
            }
        } else if (_ds18State == 1 && (now - _ds18ConvertStart >= 750)) {
            if (_ds18Cursor < _probeCount && _probes[_ds18Cursor].enabled) {
                readDS18B20(_probes[_ds18Cursor]);
            }
            _ds18State = 0;
            _ds18Cursor = (_ds18Cursor + 1) % _probeCount;
            _lastProbeCycle = now;
        }
    }

    // --- 6. Ultrasonic Distance & Water Tank Monitors (staggered to avoid echo cross-talk) ---
    uint8_t activeTanks = 0;
    for (uint8_t i = 0; i < _ultrasonicCount; i++) {
        if (_ultrasonics[i].enabled) activeTanks++;
    }
    if (activeTanks > 0) {
        unsigned long interval = (activeTanks == 1) ? 2000UL : 800UL;
        if (now - _lastUltrasonicRead >= interval) {
            _lastUltrasonicRead = now;
            for (uint8_t step = 0; step < _ultrasonicCount; step++) {
                uint8_t idx = (_ultrasonicCursor + step) % _ultrasonicCount;
                if (!_ultrasonics[idx].enabled) continue;
                _ultrasonicCursor = (idx + 1) % _ultrasonicCount;
                readUltrasonic(_ultrasonics[idx]);
                break;
            }
        }
    }

    // --- 7. Gas & Air Quality Sensors (MQ-2 / SGP40 I2C) ---
    // Complete any pending non-blocking SGP40 measurements after 32ms conversion window
    for (uint8_t i = 0; i < _mq2Count; i++) {
        Mq2SlotState& g = _mq2s[i];
        if (g.enabled && g.type == GAS_SGP40 && g.measPending && (now - g.measStartMs >= 32UL)) {
            readSGP40(g);
            if (!isMq2WarmingAt(i)) {
                if (!g.alarmActive && g.raw >= g.threshold) {
                    g.alarmActive = true;
                } else if (g.alarmActive && g.raw < max(1, g.threshold - 20)) {
                    g.alarmActive = false;
                }
            }
        }
    }

    if (now - _lastMQ2Read >= MQ2_READ_INTERVAL) {
        _lastMQ2Read = now;

        for (uint8_t i = 0; i < _mq2Count; i++) {
            Mq2SlotState& g = _mq2s[i];
            if (!g.enabled) {
                g.raw = 0;
                g.digitalState = false;
                g.alarmActive = false;
                g.measPending = false;
                continue;
            }
            if (g.type == GAS_SGP40) {
                if (!g.measPending) {
                    readSGP40(g);
                }
                continue;
            }
            bool warming = isMq2WarmingAt(i);
            if (g.analogPin != PIN_UNUSED) {
                g.raw = analogRead(g.analogPin);
                g.digitalState = (g.digitalPin != PIN_UNUSED) ? (!digitalRead(g.digitalPin)) : false;
                if (!warming) {
                    if (!g.alarmActive && g.raw >= g.threshold) {
                        g.alarmActive = true;
                    } else if (g.alarmActive && g.raw < (g.threshold - MQ2_HYSTERESIS)) {
                        g.alarmActive = false;
                    }
                }
            } else if (g.digitalPin != PIN_UNUSED) {
                g.digitalState = !digitalRead(g.digitalPin);
                g.raw = g.digitalState ? MQ2_ADC_MAX : 0;
                if (!warming) {
                    g.alarmActive = g.digitalState;
                }
            } else {
                g.raw = 0;
                g.digitalState = false;
                g.alarmActive = false;
            }
        }
    }

    checkAlarms();
}

// ============================================================================
// Native I2C Drivers
// ============================================================================

bool SensorManager::initBME280(ClimateSlotState& s, uint8_t addr) {
    Wire.beginTransmission(addr);
    Wire.write(0xD0);
    if (Wire.endTransmission() != 0) return false;

    Wire.requestFrom((int)addr, 1);
    if (!Wire.available()) return false;
    uint8_t chipId = Wire.read();

    s.i2cDetected = false;
    if (chipId == 0x60) {
        s.bmpDetected = false;
        s.i2cAddr = addr;
        SERIAL_PRINTF("[Sensor] BME280 detected at 0x%02X (ID 0x60)\n", addr);
    } else if (chipId == 0x58) {
        s.bmpDetected = true;
        s.i2cAddr = addr;
        SERIAL_PRINTF("[Sensor] BMP280 detected at 0x%02X (ID 0x58 - No Humidity)\n", addr);
    } else {
        return false;
    }

    if (!s.bmeCalib) s.bmeCalib = new BME280_Calib();
    memset(s.bmeCalib, 0, sizeof(BME280_Calib));

    // Read calibration coefficients (0x88..0xA1: 24 bytes)
    Wire.beginTransmission(addr);
    Wire.write(0x88);
    Wire.endTransmission();
    Wire.requestFrom((int)addr, 24);
    if (Wire.available() < 24) return false;

    uint8_t b[24];
    for (int i = 0; i < 24; i++) b[i] = Wire.read();

    s.bmeCalib->dig_T1 = (uint16_t)(b[0] | (b[1] << 8));
    s.bmeCalib->dig_T2 = (int16_t)(b[2] | (b[3] << 8));
    s.bmeCalib->dig_T3 = (int16_t)(b[4] | (b[5] << 8));

    s.bmeCalib->dig_P1 = (uint16_t)(b[6] | (b[7] << 8));
    s.bmeCalib->dig_P2 = (int16_t)(b[8] | (b[9] << 8));
    s.bmeCalib->dig_P3 = (int16_t)(b[10] | (b[11] << 8));
    s.bmeCalib->dig_P4 = (int16_t)(b[12] | (b[13] << 8));
    s.bmeCalib->dig_P5 = (int16_t)(b[14] | (b[15] << 8));
    s.bmeCalib->dig_P6 = (int16_t)(b[16] | (b[17] << 8));
    s.bmeCalib->dig_P7 = (int16_t)(b[18] | (b[19] << 8));
    s.bmeCalib->dig_P8 = (int16_t)(b[20] | (b[21] << 8));
    s.bmeCalib->dig_P9 = (int16_t)(b[22] | (b[23] << 8));

    if (!s.bmpDetected) {
        Wire.beginTransmission(addr);
        Wire.write(0xA1);
        Wire.endTransmission();
        Wire.requestFrom((int)addr, 1);
        if (Wire.available()) s.bmeCalib->dig_H1 = Wire.read();

        Wire.beginTransmission(addr);
        Wire.write(0xE1);
        Wire.endTransmission();
        Wire.requestFrom((int)addr, 7);
        if (Wire.available() >= 7) {
            uint8_t h[7];
            for (int i = 0; i < 7; i++) h[i] = Wire.read();
            s.bmeCalib->dig_H2 = (int16_t)(h[0] | (h[1] << 8));
            s.bmeCalib->dig_H3 = h[2];
            s.bmeCalib->dig_H4 = (int16_t)(((int8_t)h[3] << 4) | (h[4] & 0x0F));
            s.bmeCalib->dig_H5 = (int16_t)(((int8_t)h[5] << 4) | (h[4] >> 4));
            s.bmeCalib->dig_H6 = (int8_t)h[6];
        }

        // Configure ctrl_hum (0xF2) = 0x01 (1x oversampling)
        Wire.beginTransmission(addr);
        Wire.write(0xF2);
        Wire.write(0x01);
        Wire.endTransmission();
    }

    // Configure ctrl_meas (0xF4) = 0x27 (Temp 1x, Press 1x, Normal Mode)
    Wire.beginTransmission(addr);
    Wire.write(0xF4);
    Wire.write(0x27);
    Wire.endTransmission();

    // Configure config (0xF5) = 0xA0 (1000ms standby, filter off)
    Wire.beginTransmission(addr);
    Wire.write(0xF5);
    Wire.write(0xA0);
    Wire.endTransmission();

    s.i2cDetected = true;
    return true;
}

void SensorManager::readBME280(ClimateSlotState& s) {
    if (!s.bmeCalib) { s.fault = true; return; }
    Wire.beginTransmission(s.i2cAddr);
    Wire.write(0xF7);
    if (Wire.endTransmission() != 0) {
        s.fault = true;
        return;
    }

    uint8_t len = !s.bmpDetected ? 8 : 6;
    Wire.requestFrom((int)s.i2cAddr, (int)len);
    if (Wire.available() < len) {
        s.fault = true;
        return;
    }

    uint8_t buf[8];
    for (int i = 0; i < len; i++) buf[i] = Wire.read();

    const BME280_Calib* c = s.bmeCalib;

    // Temperature Compensation
    int32_t adc_T = ((int32_t)buf[3] << 12) | ((int32_t)buf[4] << 4) | ((int32_t)buf[5] >> 4);
    int32_t var1 = ((((adc_T >> 3) - ((int32_t)c->dig_T1 << 1))) * ((int32_t)c->dig_T2)) >> 11;
    int32_t var2 = (((((adc_T >> 4) - ((int32_t)c->dig_T1)) * ((adc_T >> 4) - ((int32_t)c->dig_T1))) >> 12) * ((int32_t)c->dig_T3)) >> 14;
    s.tFine = var1 + var2;
    float t = ((s.tFine * 5 + 128) >> 8) / 100.0f;

    // Pressure Compensation
    int32_t adc_P = ((int32_t)buf[0] << 12) | ((int32_t)buf[1] << 4) | ((int32_t)buf[2] >> 4);
    int64_t p_var1 = ((int64_t)s.tFine) - 128000;
    int64_t p_var2 = p_var1 * p_var1 * (int64_t)c->dig_P6;
    p_var2 = p_var2 + ((p_var1 * (int64_t)c->dig_P5) << 17);
    p_var2 = p_var2 + (((int64_t)c->dig_P4) << 35);
    p_var1 = ((p_var1 * p_var1 * (int64_t)c->dig_P3) >> 8) + ((p_var1 * (int64_t)c->dig_P2) << 12);
    p_var1 = (((((int64_t)1) << 47) + p_var1)) * ((int64_t)c->dig_P1) >> 33;
    float p = 1013.25f;
    if (p_var1 != 0) {
        int64_t p_calc = 1048576 - adc_P;
        p_calc = (((p_calc << 31) - p_var2) * 3125) / p_var1;
        p_var1 = (((int64_t)c->dig_P9) * (p_calc >> 13) * (p_calc >> 13)) >> 25;
        p_var2 = (((int64_t)c->dig_P8) * p_calc) >> 19;
        p_calc = ((p_calc + p_var1 + p_var2) >> 8) + (((int64_t)c->dig_P7) << 4);
        p = (float)p_calc / 256.0f / 100.0f; // hPa
    }

    // Humidity Compensation (BME280 only)
    float h = 0.0f;
    if (!s.bmpDetected) {
        int32_t adc_H = ((int32_t)buf[6] << 8) | ((int32_t)buf[7]);
        int32_t v_x1_u32r = (s.tFine - ((int32_t)76800));
        v_x1_u32r = (((((adc_H << 14) - (((int32_t)c->dig_H4) << 20) - (((int32_t)c->dig_H5) * v_x1_u32r)) + ((int32_t)16384)) >> 15) *
                     (((((((v_x1_u32r * ((int32_t)c->dig_H6)) >> 10) * (((v_x1_u32r * ((int32_t)c->dig_H3)) >> 11) + ((int32_t)32768))) >> 10) + ((int32_t)2097152)) *
                       ((int32_t)c->dig_H2) + 8192) >> 14));
        v_x1_u32r = (v_x1_u32r - (((((v_x1_u32r >> 15) * (v_x1_u32r >> 15)) >> 7) * ((int32_t)c->dig_H1)) >> 4));
        v_x1_u32r = (v_x1_u32r < 0 ? 0 : v_x1_u32r);
        v_x1_u32r = (v_x1_u32r > 419430400 ? 419430400 : v_x1_u32r);
        h = (float)(v_x1_u32r >> 12) / 1024.0f;
    }

    s.rawTemperature = t;
    s.rawHumidity = h;
    s.rawPressure = p;
    s.temperature = t + s.tempOffset;
    s.humidity = s.bmpDetected ? 0.0f : constrain(h + s.humOffset, 0.0f, 100.0f);
    s.pressure = p;
    s.fault = false;
}

bool SensorManager::initAHT20(ClimateSlotState& s, uint8_t addr) {
    Wire.beginTransmission(addr);
    Wire.write(0x71);
    if (Wire.endTransmission() != 0) return false;

    Wire.requestFrom((int)addr, 1);
    if (!Wire.available()) return false;
    uint8_t status = Wire.read();

    if ((status & 0x18) != 0x18) {
        Wire.beginTransmission(addr);
        Wire.write(0xBE);
        Wire.write(0x08);
        Wire.write(0x00);
        Wire.endTransmission();
        delay(10);
    }
    s.i2cDetected = true;
    s.i2cAddr = addr;
    SERIAL_PRINTF("[Sensor] AHT20 detected at 0x%02X\n", addr);
    return true;
}

void SensorManager::readAHT20(ClimateSlotState& s) {
    if (!s.measPending) {
        Wire.beginTransmission(s.i2cAddr);
        Wire.write(0xAC);
        Wire.write(0x33);
        Wire.write(0x00);
        if (Wire.endTransmission() != 0) {
            s.fault = true;
            return;
        }
        s.measPending = true;
        s.measStartMs = millis();
        return;
    }

    if (millis() - s.measStartMs < 80UL) return;
    s.measPending = false;

    Wire.requestFrom((int)s.i2cAddr, 6);
    if (Wire.available() < 6) {
        s.fault = true;
        return;
    }

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    if ((b[0] & 0x80) != 0) return; // Busy

    uint32_t humRaw = (((uint32_t)b[1] << 12) | ((uint32_t)b[2] << 4) | ((uint32_t)b[3] >> 4));
    uint32_t tempRaw = (((uint32_t)(b[3] & 0x0F) << 16) | ((uint32_t)b[4] << 8) | (uint32_t)b[5]);

    float h = ((float)humRaw * 100.0f) / 1048576.0f;
    float t = (((float)tempRaw * 200.0f) / 1048576.0f) - 50.0f;

    s.rawTemperature = t;
    s.rawHumidity = h;
    s.temperature = t + s.tempOffset;
    s.humidity = constrain(h + s.humOffset, 0.0f, 100.0f);
    s.fault = false;
}

bool SensorManager::initSHT3x(ClimateSlotState& s, uint8_t addr) {
    Wire.beginTransmission(addr);
    Wire.write(0x30);
    Wire.write(0xA2); // Soft Reset
    if (Wire.endTransmission() != 0) return false;

    delay(10);
    s.i2cDetected = true;
    s.i2cAddr = addr;
    SERIAL_PRINTF("[Sensor] SHT3x detected at 0x%02X\n", addr);
    return true;
}

void SensorManager::readSHT3x(ClimateSlotState& s) {
    if (!s.measPending) {
        Wire.beginTransmission(s.i2cAddr);
        Wire.write(0x24);
        Wire.write(0x00); // High repeatability, clock stretching disabled
        if (Wire.endTransmission() != 0) {
            s.fault = true;
            return;
        }
        s.measPending = true;
        s.measStartMs = millis();
        return;
    }

    if (millis() - s.measStartMs < 16UL) return;
    s.measPending = false;

    Wire.requestFrom((int)s.i2cAddr, 6);
    if (Wire.available() < 6) {
        s.fault = true;
        return;
    }

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    if (sensirionCrc8(&b[0], 2) != b[2] || sensirionCrc8(&b[3], 2) != b[5]) {
        s.fault = true;
        return;
    }

    uint16_t tRaw = ((uint16_t)b[0] << 8) | b[1];
    uint16_t hRaw = ((uint16_t)b[3] << 8) | b[4];

    float t = -45.0f + (175.0f * (float)tRaw / 65535.0f);
    float h = 100.0f * ((float)hRaw / 65535.0f);

    s.rawTemperature = t;
    s.rawHumidity = h;
    s.temperature = t + s.tempOffset;
    s.humidity = constrain(h + s.humOffset, 0.0f, 100.0f);
    s.fault = false;
}

bool SensorManager::initSHT4x(ClimateSlotState& s, uint8_t addr) {
    Wire.beginTransmission(addr);
    Wire.write(0x94); // Soft Reset command for SHT40 / SHT45
    if (Wire.endTransmission() != 0) return false;

    delay(2);
    s.i2cDetected = true;
    s.i2cAddr = addr;
    SERIAL_PRINTF("[Sensor] SHT40/SHT45 detected at 0x%02X\n", addr);
    return true;
}

void SensorManager::readSHT4x(ClimateSlotState& s) {
    if (!s.measPending) {
        Wire.beginTransmission(s.i2cAddr);
        Wire.write(0xFD); // Measure T & RH with high precision (no heater)
        if (Wire.endTransmission() != 0) {
            if (s.failCount < 255) s.failCount++;
            if (s.failCount >= DHT_FAIL_THRESHOLD) s.fault = true;
            return;
        }
        s.measPending = true;
        s.measStartMs = millis();
        return;
    }

    if (millis() - s.measStartMs < 12UL) return;
    s.measPending = false;

    Wire.requestFrom((int)s.i2cAddr, 6);
    if (Wire.available() < 6) {
        if (s.failCount < 255) s.failCount++;
        if (s.failCount >= DHT_FAIL_THRESHOLD) s.fault = true;
        return;
    }

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    if (sensirionCrc8(&b[0], 2) != b[2] || sensirionCrc8(&b[3], 2) != b[5]) {
        if (s.failCount < 255) s.failCount++;
        if (s.failCount >= DHT_FAIL_THRESHOLD) s.fault = true;
        return;
    }

    uint16_t tRaw = ((uint16_t)b[0] << 8) | b[1];
    uint16_t hRaw = ((uint16_t)b[3] << 8) | b[4];

    float t = -45.0f + (175.0f * (float)tRaw / 65535.0f);
    float h = constrain(-6.0f + (125.0f * (float)hRaw / 65535.0f), 0.0f, 100.0f);

    s.failCount = 0;
    s.rawTemperature = t;
    s.rawHumidity = h;
    s.temperature = t + s.tempOffset;
    s.humidity = constrain(h + s.humOffset, 0.0f, 100.0f);
    s.fault = false;
}

bool SensorManager::initSGP40(Mq2SlotState& g, uint8_t addr) {
    // Query SGP40 serial number (0x36 0x82, max 1ms, 9-byte response)
    Wire.beginTransmission(addr);
    Wire.write(0x36);
    Wire.write(0x82);
    if (Wire.endTransmission() != 0) {
        g.i2cDetected = false;
        return false;
    }
    delay(1);
    Wire.requestFrom((int)addr, 9);
    if (Wire.available() < 9) {
        g.i2cDetected = false;
        return false;
    }
    while (Wire.available()) (void)Wire.read();
    g.i2cAddr = addr;
    g.i2cDetected = true;
    return true;
}

void SensorManager::readSGP40(Mq2SlotState& g) {
    unsigned long now = millis();
    if (!g.i2cDetected) {
        if (g.lastReadMs != 0 && (now - g.lastReadMs < 5000UL)) return;
        g.lastReadMs = now;
        if (!initSGP40(g, g.i2cAddr ? g.i2cAddr : 0x59)) {
            return;
        }
    }

    if (!g.measPending) {
        float tempC = 25.0f;
        float rh = 50.0f;
        if (_climateCount > 0) {
            uint8_t pCli = primaryClimateIdx();
            if (_climates[pCli].enabled && !_climates[pCli].fault &&
                (_climates[pCli].temperature != 0.0f || _climates[pCli].humidity > 0.0f)) {
                tempC = constrain(_climates[pCli].temperature, -45.0f, 130.0f);
                if (hasHumidityAt(pCli)) {
                    rh = constrain(_climates[pCli].humidity, 0.0f, 100.0f);
                }
            }
        }

        uint16_t rhTicks = (uint16_t)constrain((long)lroundf(rh * 65535.0f / 100.0f), 0L, 65535L);
        uint16_t tTicks  = (uint16_t)constrain((long)lroundf((tempC + 45.0f) * 65535.0f / 175.0f), 0L, 65535L);

        uint8_t rhBytes[2] = { (uint8_t)(rhTicks >> 8), (uint8_t)(rhTicks & 0xFF) };
        uint8_t tBytes[2]  = { (uint8_t)(tTicks >> 8),  (uint8_t)(tTicks & 0xFF) };

        Wire.beginTransmission(g.i2cAddr);
        Wire.write(0x26);
        Wire.write(0x0F);
        Wire.write(rhBytes[0]);
        Wire.write(rhBytes[1]);
        Wire.write(sensirionCrc8(rhBytes, 2));
        Wire.write(tBytes[0]);
        Wire.write(tBytes[1]);
        Wire.write(sensirionCrc8(tBytes, 2));
        if (Wire.endTransmission() != 0) {
            g.i2cDetected = false;
            g.lastReadMs = now;
            return;
        }
        g.measPending = true;
        g.measStartMs = now;
        return;
    }

    if (now - g.measStartMs < 32UL) return;
    g.measPending = false;
    g.lastReadMs = now;

    Wire.requestFrom((int)g.i2cAddr, 3);
    if (Wire.available() < 3) {
        g.i2cDetected = false;
        return;
    }
    uint8_t b[3];
    for (int i = 0; i < 3; i++) b[i] = Wire.read();
    if (sensirionCrc8(&b[0], 2) != b[2]) return;

    uint16_t sraw = ((uint16_t)b[0] << 8) | b[1];
    if (sraw < 1000) return;

    g.srawTicks = sraw;
    bool earlyBoot = (now - _bootTime) < 30000UL;
    if (g.vocBaseline < 1000.0f) {
        g.vocBaseline = (g.baseline >= 1000 && g.baseline <= 65000)
            ? (float)g.baseline
            : (float)sraw;
    } else if ((float)sraw > g.vocBaseline) {
        float alpha = earlyBoot ? 0.15f : 0.02f;
        g.vocBaseline += ((float)sraw - g.vocBaseline) * alpha;
    } else {
        g.vocBaseline += ((float)sraw - g.vocBaseline) * 0.0005f;
    }

    float delta = g.vocBaseline - (float)sraw;
    int vocIdx = constrain((int)lroundf(100.0f + (delta / 15.0f)), 1, 500);
    g.raw = (g.raw == 0)
        ? vocIdx
        : constrain((int)lroundf((float)g.raw * 0.4f + (float)vocIdx * 0.6f), 1, 500);
}

bool SensorManager::initBH1750(LightSlotState& s, uint8_t addr) {
    Wire.beginTransmission(addr);
    Wire.write(0x01); // Power On
    if (Wire.endTransmission() == 0) {
        Wire.beginTransmission(addr);
        Wire.write(0x10); // Continuous High Resolution Mode
        Wire.endTransmission();
        s.i2cAddr = addr;
        return true;
    }
    return false;
}

void SensorManager::readBH1750(LightSlotState& s) {
    Wire.requestFrom((int)s.i2cAddr, 2);
    if (Wire.available() >= 2) {
        uint16_t raw = ((uint16_t)Wire.read() << 8) | Wire.read();
        s.lux = (float)raw / 1.2f;
    }
}

// ============================================================================
// 1-Wire DS18B20 Driver
// ============================================================================

bool SensorManager::ds18b20Reset(uint8_t pin) {
    if (pin == PIN_UNUSED) return false;
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
    delayMicroseconds(480);

    pinMode(pin, INPUT_PULLUP);
    delayMicroseconds(70);
    bool presence = (digitalRead(pin) == LOW);
    delayMicroseconds(410);
    return presence;
}

void SensorManager::ds18b20WriteByte(uint8_t pin, uint8_t b) {
    for (uint8_t i = 0; i < 8; i++) {
        pinMode(pin, OUTPUT);
        digitalWrite(pin, LOW);
        if (b & 1) {
            delayMicroseconds(5);
            pinMode(pin, INPUT_PULLUP);
            delayMicroseconds(55);
        } else {
            delayMicroseconds(60);
            pinMode(pin, INPUT_PULLUP);
            delayMicroseconds(5);
        }
        b >>= 1;
    }
}

uint8_t SensorManager::ds18b20ReadByte(uint8_t pin) {
    uint8_t res = 0;
    for (uint8_t i = 0; i < 8; i++) {
        pinMode(pin, OUTPUT);
        digitalWrite(pin, LOW);
        delayMicroseconds(2);
        pinMode(pin, INPUT_PULLUP);
        delayMicroseconds(8);
        if (digitalRead(pin) != 0) {
            res |= (1 << i);
        }
        delayMicroseconds(50);
    }
    return res;
}

bool SensorManager::readDS18B20Scratchpad(uint8_t pin, float& outTempC) {
    if (!ds18b20Reset(pin)) return false;
    ds18b20WriteByte(pin, 0xCC); // SKIP ROM
    ds18b20WriteByte(pin, 0xBE); // READ SCRATCHPAD

    uint8_t lsb = ds18b20ReadByte(pin);
    uint8_t msb = ds18b20ReadByte(pin);
    ds18b20Reset(pin); // Release 1-Wire bus from remaining scratchpad bytes

    int16_t raw = (int16_t)((msb << 8) | lsb);
    if (raw == -1 || (lsb == 0xFF && msb == 0xFF)) return false;
    float c = (float)raw / 16.0f;
    if (c < -55.0f || c > 125.0f) return false;
    outTempC = c;
    return true;
}

void SensorManager::readDS18B20(ProbeSlotState& s) {
    float c = -127.0f;
    if (readDS18B20Scratchpad(s.pin, c)) {
        s.temperature = c;
        s.fault = false;
    } else {
        s.fault = true;
    }
}

void SensorManager::readClimateDS18B20(ClimateSlotState& s) {
    s.measPending = false;
    float c = 0.0f;
    if (readDS18B20Scratchpad(s.pin, c)) {
        s.failCount = 0;
        if (s.fault) {
            s.fault = false;
            SERIAL_PRINTF("[Sensor] Climate DS18B20 recovered\n");
        }
        s.rawTemperature = c;
        s.rawHumidity = 0.0f;
        s.temperature = c + s.tempOffset;
        s.humidity = 0.0f;
    } else {
        if (s.failCount < 255) s.failCount++;
        if (s.failCount >= DHT_FAIL_THRESHOLD && !s.fault) {
            s.fault = true;
            SERIAL_PRINTF("[Sensor] Climate DS18B20 FAULT\n");
        }
    }
}

// ============================================================================
// Ultrasonic Distance & Tank Level Driver
// ============================================================================

void SensorManager::readUltrasonic(UltrasonicSlotState& s) {
    if (s.trigPin == PIN_UNUSED || s.echoPin == PIN_UNUSED) return;

    digitalWrite(s.trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(s.trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(s.trigPin, LOW);

    // 25ms timeout cap = ~4.3m max distance (prevents task watchdog reset)
    unsigned long duration = pulseIn(s.echoPin, HIGH, 25000);
    if (duration > 0) {
        float dist = (float)duration * 0.0343f / 2.0f;
        s.distanceCm = dist;

        float usableDepth = (float)(s.tankDepthCm - s.tankAirGapCm);
        if (usableDepth > 0) {
            float waterHeight = (float)s.tankDepthCm - dist;
            float pct = (waterHeight / usableDepth) * 100.0f;
            s.tankLevelPct = (int)constrain(pct, 0.0f, 100.0f);
        }
    }
}

// ============================================================================
// Primary / Indexed Helpers & Getters
// ============================================================================

static const char* climateTypeLabel(uint8_t t, bool isBmp) {
    switch (t) {
        case CLIMATE_DHT11:   return "DHT11";
        case CLIMATE_DHT22:   return "DHT22";
        case CLIMATE_BME280:  return isBmp ? "BMP280" : "BME280";
        case CLIMATE_AHT20:   return "AHT20";
        case CLIMATE_SHT3X:   return "SHT3x";
        case CLIMATE_SHT4X:   return "SHT40/SHT45";
        case CLIMATE_DS18B20: return "DS18B20";
        default:              return "None";
    }
}

uint8_t SensorManager::primaryClimateIdx() const {
    for (uint8_t i = 0; i < _climateCount; i++) {
        if (_climates[i].enabled) return i;
    }
    return 0;
}
uint8_t SensorManager::primaryLightIdx() const {
    for (uint8_t i = 0; i < _lightCount; i++) {
        if (_lights[i].enabled && _lights[i].detected) return i;
    }
    return 0;
}
uint8_t SensorManager::primaryMotionIdx() const {
    for (uint8_t i = 0; i < _motionCount; i++) {
        if (_motions[i].enabled) return i;
    }
    return 0;
}
uint8_t SensorManager::primaryProbeIdx() const {
    for (uint8_t i = 0; i < _probeCount; i++) {
        if (_probes[i].enabled) return i;
    }
    return 0;
}
uint8_t SensorManager::primaryUltrasonicIdx() const {
    for (uint8_t i = 0; i < _ultrasonicCount; i++) {
        if (_ultrasonics[i].enabled) return i;
    }
    return 0;
}
uint8_t SensorManager::primaryMq2Idx() const {
    uint8_t firstEnabled = 0;
    bool foundEnabled = false;
    int maxAlarmRaw = -1;
    uint8_t alarmIdx = 0;
    for (uint8_t i = 0; i < _mq2Count; i++) {
        if (!_mq2s[i].enabled) continue;
        if (!foundEnabled) { firstEnabled = i; foundEnabled = true; }
        if (_mq2s[i].alarmActive && _mq2s[i].raw > maxAlarmRaw) {
            maxAlarmRaw = _mq2s[i].raw;
            alarmIdx = i;
        }
    }
    return (maxAlarmRaw >= 0) ? alarmIdx : firstEnabled;
}

// --- Indexed getters ---
bool SensorManager::isClimateActiveAt(uint8_t idx) const {
    return idx < _climateCount && _climates[idx].enabled;
}
float SensorManager::getTemperatureAt(uint8_t idx) const {
    return (idx < _climateCount) ? _climates[idx].temperature : 0.0f;
}
float SensorManager::getHumidityAt(uint8_t idx) const {
    return (idx < _climateCount) ? _climates[idx].humidity : 0.0f;
}
float SensorManager::getPressureAt(uint8_t idx) const {
    return (idx < _climateCount && _climates[idx].type == CLIMATE_BME280 && _climates[idx].i2cDetected)
           ? _climates[idx].pressure : 0.0f;
}
bool SensorManager::hasBarometerAt(uint8_t idx) const {
    return idx < _climateCount && _climates[idx].enabled &&
           _climates[idx].type == CLIMATE_BME280 && _climates[idx].i2cDetected;
}
bool SensorManager::hasHumidityAt(uint8_t idx) const {
    return idx < _climateCount && _climates[idx].enabled &&
           !_climates[idx].bmpDetected && _climates[idx].type != CLIMATE_DS18B20;
}
bool SensorManager::isClimateFaultAt(uint8_t idx) const {
    return idx < _climateCount && _climates[idx].enabled && _climates[idx].fault;
}
float SensorManager::getTempOffsetAt(uint8_t idx) const {
    return (idx < MAX_CLIMATE_SENSORS) ? _climates[idx].tempOffset : 0.0f;
}
float SensorManager::getHumOffsetAt(uint8_t idx) const {
    return (idx < MAX_CLIMATE_SENSORS) ? _climates[idx].humOffset : 0.0f;
}
void SensorManager::setTempOffsetAt(uint8_t idx, float offset) {
    if (idx < MAX_CLIMATE_SENSORS) _climates[idx].tempOffset = offset;
}
void SensorManager::setHumOffsetAt(uint8_t idx, float offset) {
    if (idx < MAX_CLIMATE_SENSORS) _climates[idx].humOffset = offset;
}

bool SensorManager::isLightActiveAt(uint8_t idx) const {
    return idx < _lightCount && _lights[idx].enabled && _lights[idx].detected;
}
float SensorManager::getLuxAt(uint8_t idx) const {
    return (idx < _lightCount) ? _lights[idx].lux : 0.0f;
}

bool SensorManager::isMotionActiveAt(uint8_t idx) const {
    return idx < _motionCount && _motions[idx].enabled;
}
bool SensorManager::isMotionDetectedAt(uint8_t idx) const {
    return isMotionActiveAt(idx) && _motions[idx].detected;
}
uint32_t SensorManager::getMotionAgeSecondsAt(uint8_t idx) const {
    if (!isMotionActiveAt(idx) || _motions[idx].lastMotionTime == 0) return 99999;
    return (uint32_t)((millis() - _motions[idx].lastMotionTime) / 1000);
}

bool SensorManager::isProbeActiveAt(uint8_t idx) const {
    return idx < _probeCount && _probes[idx].enabled;
}
float SensorManager::getProbeTemperatureAt(uint8_t idx) const {
    return (idx < _probeCount) ? _probes[idx].temperature : -127.0f;
}
bool SensorManager::isProbeFaultAt(uint8_t idx) const {
    return isProbeActiveAt(idx) && _probes[idx].fault;
}

bool SensorManager::isUltrasonicActiveAt(uint8_t idx) const {
    return idx < _ultrasonicCount && _ultrasonics[idx].enabled;
}
float SensorManager::getDistanceCmAt(uint8_t idx) const {
    return (idx < _ultrasonicCount) ? _ultrasonics[idx].distanceCm : 0.0f;
}
int SensorManager::getTankLevelPercentAt(uint8_t idx) const {
    return (idx < _ultrasonicCount) ? _ultrasonics[idx].tankLevelPct : 0;
}

uint8_t SensorManager::getMq2TypeAt(uint8_t idx) const {
    return (idx < _mq2Count) ? _mq2s[idx].type : GAS_MQ2;
}
bool SensorManager::isMq2ActiveAt(uint8_t idx) const {
    return idx < _mq2Count && _mq2s[idx].enabled;
}
bool SensorManager::isMq2HwAllowedAt(uint8_t idx) const {
    return idx < _mq2Count && _mq2s[idx].hwAllowed;
}
bool SensorManager::isMq2WarmingAt(uint8_t idx) const {
    if (idx >= _mq2Count || !_mq2s[idx].enabled) return false;
    unsigned long warmupMs = (_mq2s[idx].type == GAS_SGP40) ? 15000UL : MQ2_WARMUP_TIME;
    return (millis() - _bootTime) < warmupMs;
}
int SensorManager::getMQ2RawAt(uint8_t idx) const {
    return (idx < _mq2Count) ? _mq2s[idx].raw : 0;
}
int SensorManager::getMQ2PercentAt(uint8_t idx) const {
    if (idx >= _mq2Count) return 0;
    const Mq2SlotState& g = _mq2s[idx];
    if (g.type == GAS_SGP40) {
        return constrain((g.raw * 100) / 500, 0, 100);
    }
    if (g.raw <= g.baseline) return 0;
    int range = MQ2_ADC_MAX - g.baseline;
    if (range <= 0) return 0;
    return constrain(((g.raw - g.baseline) * 100) / range, 0, 100);
}
int SensorManager::getMQ2BaselineAt(uint8_t idx) const {
    return (idx < MAX_MQ2_SENSORS) ? _mq2s[idx].baseline : MQ2_BASELINE_DEFAULT;
}
int SensorManager::getMQ2ThresholdAt(uint8_t idx) const {
    return (idx < MAX_MQ2_SENSORS) ? _mq2s[idx].threshold : MQ2_DEFAULT_THRESHOLD;
}
bool SensorManager::isMQ2AlarmAt(uint8_t idx) const {
    return idx < _mq2Count && _mq2s[idx].enabled && _mq2s[idx].alarmActive;
}
bool SensorManager::isMQ2DigitalTriggerAt(uint8_t idx) const {
    return idx < _mq2Count && _mq2s[idx].digitalState;
}
void SensorManager::setMQ2ThresholdAt(int idx, int threshold) {
    if (idx < 0) {
        for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
            int maxTh = (_mq2s[i].type == GAS_SGP40) ? 500 : MQ2_ADC_MAX;
            _mq2s[i].threshold = constrain(threshold, 10, maxTh);
        }
    } else if (idx < MAX_MQ2_SENSORS) {
        int maxTh = (_mq2s[idx].type == GAS_SGP40) ? 500 : MQ2_ADC_MAX;
        _mq2s[idx].threshold = constrain(threshold, 10, maxTh);
    }
}
void SensorManager::setMQ2EnabledAt(int idx, bool enabled) {
    if (idx < 0) {
        for (uint8_t i = 0; i < _mq2Count; i++) {
            _mq2s[i].enabled = _mq2s[i].hwAllowed ? enabled : false;
        }
    } else if (idx < _mq2Count) {
        _mq2s[idx].enabled = _mq2s[idx].hwAllowed ? enabled : false;
    }
}
void SensorManager::calibrateMQ2At(int idx) {
    auto applyCal = [&](uint8_t slotIdx) {
        Mq2SlotState& g = _mq2s[slotIdx];
        if (!g.enabled) return;
        if (g.type == GAS_SGP40) {
            if (g.srawTicks >= 1000) {
                g.vocBaseline = (float)g.srawTicks;
                g.baseline = (int)g.srawTicks;
                g.raw = 100;
                SERIAL_PRINTF("[Sensor] Gas #%u (SGP40) clean-air baseline calibrated to %u ticks (VOC Index = 100)\n",
                              (unsigned)(slotIdx + 1), g.srawTicks);
            }
        } else {
            g.baseline = g.raw;
            SERIAL_PRINTF("[Sensor] MQ2 #%u baseline calibrated to %d\n", (unsigned)(slotIdx + 1), g.baseline);
        }
    };
    if (idx < 0) {
        for (uint8_t i = 0; i < _mq2Count; i++) applyCal(i);
        saveCalibration();
    } else if (idx < _mq2Count && _mq2s[idx].enabled) {
        applyCal((uint8_t)idx);
        saveCalibration();
    }
}

// --- Legacy / Primary / Aggregate Getters ---
bool SensorManager::isDhtEnabled() const {
    for (uint8_t i = 0; i < _climateCount; i++) if (_climates[i].enabled) return true;
    return false;
}
float SensorManager::getTemperature()        { return isDhtEnabled() ? _climates[primaryClimateIdx()].temperature : 0.0f; }
float SensorManager::getHumidity()           { return isDhtEnabled() ? _climates[primaryClimateIdx()].humidity : 0.0f; }
float SensorManager::getRawTemperature()     { return isDhtEnabled() ? _climates[primaryClimateIdx()].rawTemperature : 0.0f; }
float SensorManager::getRawHumidity()        { return isDhtEnabled() ? _climates[primaryClimateIdx()].rawHumidity : 0.0f; }
float SensorManager::getPressure()           {
    for (uint8_t i = 0; i < _climateCount; i++) if (hasBarometerAt(i)) return _climates[i].pressure;
    return 0.0f;
}
bool SensorManager::hasBarometer() const {
    for (uint8_t i = 0; i < _climateCount; i++) if (hasBarometerAt(i)) return true;
    return false;
}
bool SensorManager::hasHumidity() const {
    return isDhtEnabled() && hasHumidityAt(primaryClimateIdx());
}
bool SensorManager::isPrimarySgp40() const {
    return _mq2Count > 0 && _mq2s[primaryMq2Idx()].type == GAS_SGP40;
}
bool SensorManager::isDHTFault() {
    for (uint8_t i = 0; i < _climateCount; i++) if (isClimateFaultAt(i)) return true;
    return false;
}
float SensorManager::getTempOffset()         { return _climates[primaryClimateIdx()].tempOffset; }
float SensorManager::getHumOffset()          { return _climates[primaryClimateIdx()].humOffset; }
void  SensorManager::setTempOffset(float o)  { setTempOffsetAt(primaryClimateIdx(), o); }
void  SensorManager::setHumOffset(float o)   { setHumOffsetAt(primaryClimateIdx(), o); }
float SensorManager::getTempAlarmThreshold() { return _tempAlarmThreshold; }
void  SensorManager::setTempAlarmThreshold(float t) { _tempAlarmThreshold = t; }

bool SensorManager::isTempAlarm() {
    for (uint8_t i = 0; i < _climateCount; i++) {
        if (_climates[i].enabled && !_climates[i].fault && _climates[i].temperature >= _tempAlarmThreshold) {
            return true;
        }
    }
    return false;
}

float SensorManager::getLux() {
    return isLuxEnabled() ? _lights[primaryLightIdx()].lux : 0.0f;
}
bool SensorManager::isLuxEnabled() const {
    for (uint8_t i = 0; i < _lightCount; i++) if (isLightActiveAt(i)) return true;
    return false;
}

bool SensorManager::isMotionEnabled() const {
    for (uint8_t i = 0; i < _motionCount; i++) if (_motions[i].enabled) return true;
    return false;
}
bool SensorManager::isMotionDetected() {
    for (uint8_t i = 0; i < _motionCount; i++) if (isMotionDetectedAt(i)) return true;
    return false;
}
uint32_t SensorManager::getMotionAgeSeconds() {
    uint32_t minAge = 99999;
    for (uint8_t i = 0; i < _motionCount; i++) {
        if (_motions[i].enabled) {
            uint32_t a = getMotionAgeSecondsAt(i);
            if (a < minAge) minAge = a;
        }
    }
    return minAge;
}

bool SensorManager::isProbeEnabled() const {
    for (uint8_t i = 0; i < _probeCount; i++) if (_probes[i].enabled) return true;
    return false;
}
float SensorManager::getProbeTemperature() {
    return isProbeEnabled() ? _probes[primaryProbeIdx()].temperature : -127.0f;
}
bool SensorManager::isProbeFault() {
    for (uint8_t i = 0; i < _probeCount; i++) if (isProbeFaultAt(i)) return true;
    return false;
}

bool SensorManager::isUltrasonicEnabled() const {
    for (uint8_t i = 0; i < _ultrasonicCount; i++) if (_ultrasonics[i].enabled) return true;
    return false;
}
float SensorManager::getDistanceCm() {
    return isUltrasonicEnabled() ? _ultrasonics[primaryUltrasonicIdx()].distanceCm : 0.0f;
}
int SensorManager::getTankLevelPercent() {
    return isUltrasonicEnabled() ? _ultrasonics[primaryUltrasonicIdx()].tankLevelPct : 0;
}

bool SensorManager::isMQ2Enabled() {
    for (uint8_t i = 0; i < _mq2Count; i++) if (_mq2s[i].enabled) return true;
    return false;
}
bool SensorManager::isMQ2HardwareAllowed() const {
    for (uint8_t i = 0; i < _mq2Count; i++) if (_mq2s[i].hwAllowed) return true;
    return false;
}
int  SensorManager::getMQ2Raw()            { return isMQ2Enabled() ? _mq2s[primaryMq2Idx()].raw : 0; }
bool SensorManager::isMQ2Alarm() {
    for (uint8_t i = 0; i < _mq2Count; i++) if (isMQ2AlarmAt(i)) return true;
    return false;
}
bool SensorManager::isMQ2DigitalTrigger()  {
    for (uint8_t i = 0; i < _mq2Count; i++) if (_mq2s[i].enabled && _mq2s[i].digitalState) return true;
    return false;
}
int  SensorManager::getMQ2Threshold()      { return _mq2s[primaryMq2Idx()].threshold; }
void SensorManager::setMQ2Threshold(int t) { setMQ2ThresholdAt(-1, t); }
int  SensorManager::getMQ2Baseline()       { return _mq2s[primaryMq2Idx()].baseline; }
void SensorManager::setMQ2Enabled(bool e)  { setMQ2EnabledAt(-1, e); }
int  SensorManager::getMQ2Percent()        { return isMQ2Enabled() ? getMQ2PercentAt(primaryMq2Idx()) : 0; }
bool SensorManager::isMQ2Warming() {
    if (!isMQ2Enabled()) return false;
    return isMq2WarmingAt(primaryMq2Idx());
}
void SensorManager::calibrateMQ2() { calibrateMQ2At(-1); }

bool SensorManager::hasAnySensorFault() {
    return isDHTFault() || isProbeFault();
}
bool SensorManager::hasAnyAlarm() {
    return isTempAlarm() || isMQ2Alarm();
}
void SensorManager::setAlarmCallback(void (*cb)(uint8_t, bool)) {
    _alarmCallback = cb;
}

void SensorManager::saveCalibration() {
    if (!_storage) return;

    JsonDocument doc;
    doc["temp_offset"]    = _climates[0].tempOffset;
    doc["hum_offset"]     = _climates[0].humOffset;
    doc["temp_alarm"]     = _tempAlarmThreshold;
    doc["mq2_threshold"]  = _mq2s[0].threshold;
    doc["mq2_baseline"]   = _mq2s[0].baseline;
    doc["mq2_enabled"]    = _mq2s[0].enabled;

    JsonArray tOff = doc["temp_offsets"].to<JsonArray>();
    JsonArray hOff = doc["hum_offsets"].to<JsonArray>();
    for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS; i++) {
        tOff.add(_climates[i].tempOffset);
        hOff.add(_climates[i].humOffset);
    }

    JsonArray gTh = doc["mq2_thresholds"].to<JsonArray>();
    JsonArray gBs = doc["mq2_baselines"].to<JsonArray>();
    JsonArray gEn = doc["mq2_enables"].to<JsonArray>();
    JsonArray gTp = doc["mq2_types"].to<JsonArray>();
    for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
        gTh.add(_mq2s[i].threshold);
        gBs.add(_mq2s[i].baseline);
        gEn.add(_mq2s[i].enabled);
        gTp.add(_mq2s[i].type);
    }

    _storage->saveJson(PATH_SENSORS, doc);
    Serial.println(F("[Sensor] Calibration saved"));
}

void SensorManager::appendStatusJson(JsonObject& obj) {
    bool priSgp40 = isPrimarySgp40();

    // Primary / Aggregate Scalar Compatibility Keys
    obj["temperature"]      = serialized(String(getTemperature(), 1));
    obj["humidity"]         = serialized(String(getHumidity(), 1));
    obj["humidity_enabled"] = hasHumidity();
    obj["pressure"]         = serialized(String(getPressure(), 1));
    obj["pressure_enabled"] = hasBarometer();
    obj["dht_enabled"]      = isDhtEnabled();
    obj["dht_fault"]        = isDHTFault();
    obj["temp_threshold"]   = _tempAlarmThreshold;

    obj["lux"]              = serialized(String(getLux(), 1));
    obj["lux_enabled"]      = isLuxEnabled();

    obj["motion"]           = isMotionDetected();
    obj["motion_age_s"]     = getMotionAgeSeconds();
    obj["motion_enabled"]   = isMotionEnabled();

    obj["probe_temp"]       = serialized(String(getProbeTemperature(), 1));
    obj["probe_fault"]      = isProbeFault();
    obj["probe_enabled"]    = isProbeEnabled();

    obj["distance_cm"]      = serialized(String(getDistanceCm(), 1));
    obj["tank_level_pct"]   = getTankLevelPercent();
    obj["tank_enabled"]     = isUltrasonicEnabled();

    obj["gas_raw"]          = getMQ2Raw();
    obj["gas_percent"]      = getMQ2Percent();
    obj["gas_max"]          = priSgp40 ? 500 : MQ2_ADC_MAX;
    obj["gas_unit"]         = priSgp40 ? "VOC" : "ADC";
    obj["gas_alarm"]        = isMQ2Alarm();
    obj["gas_enabled"]      = isMQ2Enabled();
    obj["gas_hw_allowed"]   = isMQ2HardwareAllowed();
    obj["gas_threshold"]    = getMQ2Threshold();
    obj["gas_warming"]      = isMQ2Warming();

    // Multi-Instance Sensor Telemetry Arrays
    JsonArray climatesArr = obj["climates"].to<JsonArray>();
    for (uint8_t i = 0; i < _climateCount; i++) {
        const ClimateSlotState& c = _climates[i];
        JsonObject it = climatesArr.add<JsonObject>();
        it["index"]            = i;
        it["enabled"]          = c.enabled;
        it["type"]             = c.type;
        it["type_name"]        = climateTypeLabel(c.type, c.bmpDetected);
        it["label"]            = c.label;
        it["temperature"]      = serialized(String(c.temperature, 1));
        it["humidity"]         = serialized(String(c.humidity, 1));
        it["humidity_enabled"] = hasHumidityAt(i);
        it["pressure"]         = serialized(String(hasBarometerAt(i) ? c.pressure : 0.0f, 1));
        it["barometer"]        = hasBarometerAt(i);
        it["fault"]            = c.fault;
        it["temp_alarm"]       = c.enabled && !c.fault && (c.temperature >= _tempAlarmThreshold);
        it["temp_offset"]      = c.tempOffset;
        it["hum_offset"]       = c.humOffset;
    }

    JsonArray lightsArr = obj["lights"].to<JsonArray>();
    for (uint8_t i = 0; i < _lightCount; i++) {
        const LightSlotState& l = _lights[i];
        JsonObject it = lightsArr.add<JsonObject>();
        it["index"]    = i;
        it["enabled"]  = l.enabled && l.detected;
        it["i2c_addr"] = l.i2cAddr;
        it["label"]    = l.label;
        it["lux"]      = serialized(String(l.lux, 1));
    }

    JsonArray motionsArr = obj["motions"].to<JsonArray>();
    for (uint8_t i = 0; i < _motionCount; i++) {
        const MotionSlotState& m = _motions[i];
        JsonObject it = motionsArr.add<JsonObject>();
        it["index"]    = i;
        it["enabled"]  = m.enabled;
        it["type"]     = m.type;
        it["label"]    = m.label;
        it["detected"] = isMotionDetectedAt(i);
        it["age_s"]    = getMotionAgeSecondsAt(i);
    }

    JsonArray probesArr = obj["probes"].to<JsonArray>();
    for (uint8_t i = 0; i < _probeCount; i++) {
        const ProbeSlotState& p = _probes[i];
        JsonObject it = probesArr.add<JsonObject>();
        it["index"]       = i;
        it["enabled"]     = p.enabled;
        it["label"]       = p.label;
        it["temperature"] = serialized(String(p.temperature, 1));
        it["fault"]       = p.fault;
    }

    JsonArray tanksArr = obj["tanks"].to<JsonArray>();
    for (uint8_t i = 0; i < _ultrasonicCount; i++) {
        const UltrasonicSlotState& u = _ultrasonics[i];
        JsonObject it = tanksArr.add<JsonObject>();
        it["index"]       = i;
        it["enabled"]     = u.enabled;
        it["type"]        = u.type;
        it["label"]       = u.label;
        it["distance_cm"] = serialized(String(u.distanceCm, 1));
        it["level_pct"]   = u.tankLevelPct;
    }

    JsonArray mq2Arr = obj["mq2s"].to<JsonArray>();
    for (uint8_t i = 0; i < _mq2Count; i++) {
        const Mq2SlotState& g = _mq2s[i];
        bool isSgp = (g.type == GAS_SGP40);
        JsonObject it = mq2Arr.add<JsonObject>();
        it["index"]      = i;
        it["enabled"]    = g.enabled;
        it["hw_allowed"] = g.hwAllowed;
        it["type"]       = g.type;
        it["type_name"]  = isSgp ? "SGP40" : "MQ-2";
        it["i2c_addr"]   = isSgp ? g.i2cAddr : 0;
        it["unit"]       = isSgp ? "VOC" : "ADC";
        it["gas_max"]    = isSgp ? 500 : MQ2_ADC_MAX;
        it["label"]      = g.label;
        it["raw"]        = g.raw;
        it["percent"]    = getMQ2PercentAt(i);
        it["threshold"]  = g.threshold;
        it["baseline"]   = g.baseline;
        it["alarm"]      = g.alarmActive;
        it["digital"]    = g.digitalState;
        it["warming"]    = isMq2WarmingAt(i);
    }
}

void SensorManager::toJson(JsonObject& obj) {
    appendStatusJson(obj);
    obj["temp_raw"]     = serialized(String(getRawTemperature(), 1));
    obj["hum_raw"]      = serialized(String(getRawHumidity(), 1));
    uint8_t pCli = primaryClimateIdx();
    obj["pressure_raw"] = serialized(String(hasBarometerAt(pCli) ? _climates[pCli].rawPressure : 0.0f, 1));
    obj["temp_alarm"]   = isTempAlarm();
    obj["temp_offset"]  = getTempOffset();
    obj["hum_offset"]   = getHumOffset();
    obj["gas_baseline"] = getMQ2Baseline();
    obj["gas_digital"]  = isMQ2DigitalTrigger();
}

void SensorManager::loadCalibration() {
    if (!_storage) return;

    JsonDocument doc;
    if (_storage->loadJson(PATH_SENSORS, doc)) {
        _tempAlarmThreshold = doc["temp_alarm"] | DHT_TEMP_ALARM_DEFAULT;
        float defTempOff = doc["temp_offset"] | DHT_TEMP_OFFSET_DEFAULT;
        float defHumOff  = doc["hum_offset"]  | DHT_HUM_OFFSET_DEFAULT;
        int defMq2Th     = constrain(doc["mq2_threshold"] | MQ2_DEFAULT_THRESHOLD, 10, MQ2_ADC_MAX);
        int defMq2Base   = constrain(doc["mq2_baseline"]  | MQ2_BASELINE_DEFAULT, 0, MQ2_ADC_MAX);
        bool defMq2En    = doc["mq2_enabled"] | true;

        JsonArrayConst tOff = doc["temp_offsets"].as<JsonArrayConst>();
        JsonArrayConst hOff = doc["hum_offsets"].as<JsonArrayConst>();
        for (uint8_t i = 0; i < MAX_CLIMATE_SENSORS; i++) {
            _climates[i].tempOffset = (!tOff.isNull() && i < tOff.size()) ? (float)tOff[i] : defTempOff;
            _climates[i].humOffset  = (!hOff.isNull() && i < hOff.size()) ? (float)hOff[i] : defHumOff;
        }

        JsonArrayConst gTh = doc["mq2_thresholds"].as<JsonArrayConst>();
        JsonArrayConst gBs = doc["mq2_baselines"].as<JsonArrayConst>();
        JsonArrayConst gEn = doc["mq2_enables"].as<JsonArrayConst>();
        JsonArrayConst gTp = doc["mq2_types"].as<JsonArrayConst>();
        for (uint8_t i = 0; i < MAX_MQ2_SENSORS; i++) {
            _mq2s[i].enabled = (!gEn.isNull() && i < gEn.size()) ? (bool)gEn[i] : defMq2En;
            uint8_t savedType = (!gTp.isNull() && i < gTp.size()) ? (uint8_t)gTp[i] : (uint8_t)GAS_MQ2;
            bool typeMatched = (savedType == _mq2s[i].type);

            if (_mq2s[i].type == GAS_SGP40) {
                if (typeMatched) {
                    int rawTh = (!gTh.isNull() && i < gTh.size()) ? (int)gTh[i] : 250;
                    int rawBs = (!gBs.isNull() && i < gBs.size()) ? (int)gBs[i] : 0;
                    _mq2s[i].threshold = constrain(rawTh, 10, 500);
                    _mq2s[i].baseline  = constrain(rawBs, 0, 65535);
                    if (_mq2s[i].baseline >= 1000) {
                        _mq2s[i].vocBaseline = (float)_mq2s[i].baseline;
                    }
                } else {
                    _mq2s[i].threshold   = 250;
                    _mq2s[i].baseline    = 0;
                    _mq2s[i].vocBaseline = 0.0f;
                }
            } else {
                if (typeMatched) {
                    _mq2s[i].threshold = constrain((!gTh.isNull() && i < gTh.size()) ? (int)gTh[i] : defMq2Th, 10, MQ2_ADC_MAX);
                    _mq2s[i].baseline  = constrain((!gBs.isNull() && i < gBs.size()) ? (int)gBs[i] : defMq2Base, 0, MQ2_ADC_MAX);
                } else {
                    _mq2s[i].threshold = MQ2_DEFAULT_THRESHOLD;
                    _mq2s[i].baseline  = MQ2_BASELINE_DEFAULT;
                }
            }
        }
    }
}

void SensorManager::checkAlarms() {
    if (!_alarmCallback) return;

    bool gasAlarm = isMQ2Alarm();
    if (gasAlarm != _prevMQ2Alarm) {
        _prevMQ2Alarm = gasAlarm;
        _alarmCallback(ALARM_TYPE_GAS, gasAlarm);
    }

    bool tempAlarm = isTempAlarm();
    if (tempAlarm != _prevTempAlarm) {
        _prevTempAlarm = tempAlarm;
        _alarmCallback(ALARM_TYPE_TEMP, tempAlarm);
    }

    bool fault = isDHTFault();
    if (fault != _prevSensorFault) {
        _prevSensorFault = fault;
        _alarmCallback(ALARM_TYPE_SENSOR_FAULT, fault);
    }
}
