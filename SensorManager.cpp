/*
 * ============================================================================
 * SensorManager.cpp — Universal Sensor Subsystem Implementation
 * ============================================================================
 * Supports:
 *  - Climate: DHT11, DHT22/AM2302 (1-Wire bit-bang),
 *             BME280/BMP280 (I2C 0x76/0x77),
 *             AHT20 (I2C 0x38),
 *             SHT31 / SHT3x (I2C 0x44/0x45)
 *  - Optics:  BH1750 Ambient Light (I2C 0x23/0x5C)
 *  - Motion:  PIR / LD2410 mmWave Radar (Digital GPIO)
 *  - Probe:   DS18B20 Submersible Water Temperature (1-Wire GPIO)
 *  - Tank:    HC-SR04P / HC-SR04 / JSN-SR04T Ultrasonic Distance & Water Level
 *  - Gas:     MQ-2 Analog Gas & Smoke (ADC1 + DO)
 * ============================================================================
 */

#include "SensorManager.h"
#include "HardwareManager.h"
#include <Wire.h>

// Static DS18B20 state machine
static uint8_t s_ds18State = 0; // 0 = idle/due for convert, 1 = waiting for conversion
static unsigned long s_ds18ConvertStart = 0;

SensorManager::SensorManager()
    : _storage(nullptr), _dht(PIN_DHT22, DHT_TYPE),
      _dhtEnabled(true), _mq2AnalogPin(PIN_MQ2_ANALOG), _mq2DigitalPin(PIN_MQ2_DIGITAL),
      _temperature(0), _humidity(0), _rawTemperature(0), _rawHumidity(0),
      _tempOffset(DHT_TEMP_OFFSET_DEFAULT), _humOffset(DHT_HUM_OFFSET_DEFAULT),
      _tempAlarmThreshold(DHT_TEMP_ALARM_DEFAULT),
      _dhtFault(false), _dhtFailCount(0), _tempAlarmActive(false),
      _mq2Raw(0), _mq2Baseline(MQ2_BASELINE_DEFAULT),
      _mq2Threshold(MQ2_DEFAULT_THRESHOLD),
      _mq2AlarmActive(false), _mq2DigitalState(false), _mq2Enabled(true),
      _bootTime(0), _lastDHTRead(0), _lastMQ2Read(0),
      _lastEnvRead(0), _lastLuxRead(0),
      _climateType(CLIMATE_NONE),
      _bmeDetected(false), _bmpDetected(false), _ahtDetected(false), _shtDetected(false), _bh1750Detected(false),
      _bmeAddr(0x76), _shtAddr(0x44),
      _pressure(0.0f), _rawPressure(0.0f), _lux(0.0f),
      _motionEnabled(false), _motionPin(PIN_UNUSED), _motionDetected(false), _lastMotionTime(0),
      _probeEnabled(false), _probePin(PIN_UNUSED), _probeTemperature(-127.0f), _probeFault(false), _lastProbeRead(0),
      _ultrasonicEnabled(false), _trigPin(PIN_UNUSED), _echoPin(PIN_UNUSED),
      _tankDepthCm(150), _tankAirGapCm(15), _distanceCm(0.0f), _tankLevelPct(0), _lastUltrasonicRead(0),
      _t_fine(0),
      _alarmCallback(nullptr),
      _prevTempAlarm(false), _prevMQ2Alarm(false), _prevSensorFault(false) {
    memset(&_bmeCalib, 0, sizeof(_bmeCalib));
}

void SensorManager::begin(StorageManager& storage) {
    _storage = &storage;
    _bootTime = millis();
    _dhtEnabled = true;
    _mq2AnalogPin = PIN_MQ2_ANALOG;
    _mq2DigitalPin = PIN_MQ2_DIGITAL;

    _dht.begin();
    pinMode(_mq2DigitalPin, INPUT);
    loadCalibration();

    Serial.println(F("[Sensor] Initialized (legacy defaults)"));
}

void SensorManager::begin(StorageManager& storage, HardwareManager& hw) {
    _storage = &storage;
    _bootTime = millis();

    // 1. Climate Sensor Selection
    _climateType = (uint8_t)hw.getDhtType();
    // Ensure I2C bus is initialized if any I2C sensor is configured
    // (guarantees operation even if LCD display is disabled in hardware profile)
    if (_climateType >= CLIMATE_BME280 || hw.getLightType() == LIGHT_BH1750) {
        if (hw.getI2cSdaPin() != PIN_UNUSED && hw.getI2cSclPin() != PIN_UNUSED) {
            Wire.begin(hw.getI2cSdaPin(), hw.getI2cSclPin());
        }
    }

    if (_climateType == CLIMATE_DHT11 || _climateType == CLIMATE_DHT22) {
        if (hw.getDhtPin() != PIN_UNUSED) {
            uint8_t dhtModel = (_climateType == CLIMATE_DHT11) ? DHT11 : DHT22;
            _dht = DHT(hw.getDhtPin(), dhtModel);
            _dht.begin();
            _dhtEnabled = true;
            _dhtFault = false;
        }
    } else if (_climateType == CLIMATE_BME280) {
        _dhtEnabled = true;
        _dhtFault = false;
        if (!initBME280(0x76)) {
            if (!initBME280(0x77)) {
                _dhtFault = true;
                Serial.println(F("[Sensor] BME280/BMP280 not responding at 0x76 or 0x77"));
            }
        }
    } else if (_climateType == CLIMATE_AHT20) {
        _dhtEnabled = true;
        _dhtFault = false;
        if (!initAHT20()) {
            _dhtFault = true;
            Serial.println(F("[Sensor] AHT20 not responding at 0x38"));
        }
    } else if (_climateType == CLIMATE_SHT3X) {
        _dhtEnabled = true;
        _dhtFault = false;
        if (!initSHT3x(0x44)) {
            if (!initSHT3x(0x45)) {
                _dhtFault = true;
                Serial.println(F("[Sensor] SHT3x not responding at 0x44 or 0x45"));
            }
        }
    } else {
        _dhtEnabled = false;
        _dhtFault = false;
        _temperature = 0;
        _humidity = 0;
        _rawTemperature = 0;
        _rawHumidity = 0;
    }

    // 2. BH1750 Ambient Light Sensor (Shared I2C bus)
    if (hw.getLightType() == LIGHT_BH1750) {
        if (initBH1750()) {
            _bh1750Detected = true;
            Serial.println(F("[Sensor] BH1750 Ambient Light sensor detected"));
        } else {
            _bh1750Detected = false;
            Serial.println(F("[Sensor] BH1750 not responding at 0x23 or 0x5C"));
        }
    } else {
        _bh1750Detected = false;
        _lux = 0.0f;
    }

    // 3. Motion / Occupancy Sensor (PIR / Radar)
    if (hw.getMotionType() != MOTION_NONE && hw.getMotionPin() != PIN_UNUSED) {
        _motionEnabled = true;
        _motionPin = hw.getMotionPin();
        pinMode(_motionPin, INPUT);
        _motionDetected = (digitalRead(_motionPin) == HIGH);
        _lastMotionTime = _motionDetected ? millis() : 0;
        Serial.printf("[Sensor] Motion Sensor configured on GPIO %d\n", _motionPin);
    } else {
        _motionEnabled = false;
        _motionPin = PIN_UNUSED;
        _motionDetected = false;
    }

    // 4. Submersible Water Temp Probe (DS18B20 1-Wire)
    if (hw.getProbeType() == PROBE_DS18B20 && hw.getProbePin() != PIN_UNUSED) {
        _probeEnabled = true;
        _probePin = hw.getProbePin();
        pinMode(_probePin, INPUT_PULLUP);
        _probeTemperature = -127.0f;
        _probeFault = false;
        Serial.printf("[Sensor] DS18B20 Probe configured on GPIO %d\n", _probePin);
    } else {
        _probeEnabled = false;
        _probePin = PIN_UNUSED;
    }

    // 5. Ultrasonic Distance & Water Tank Monitor
    if (hw.getUltrasonicType() != ULTRASONIC_NONE) {
        _ultrasonicEnabled = true;
        _trigPin = hw.getTrigPin();
        _echoPin = hw.getEchoPin();
        _tankDepthCm = hw.getTankDepthCm();
        _tankAirGapCm = hw.getTankAirGapCm();
        if (_trigPin != PIN_UNUSED) {
            pinMode(_trigPin, OUTPUT);
            digitalWrite(_trigPin, LOW);
        }
        if (_echoPin != PIN_UNUSED) {
            pinMode(_echoPin, INPUT);
        }
        Serial.printf("[Sensor] Ultrasonic Tank Sensor: Trig GPIO %d, Echo GPIO %d, Depth %d cm, Air Gap %d cm\n",
                      _trigPin, _echoPin, _tankDepthCm, _tankAirGapCm);
    } else {
        _ultrasonicEnabled = false;
    }

    // 6. MQ-2 Gas & Smoke Sensor
    _mq2Enabled = hw.isMq2Enabled();
    _mq2AnalogPin = hw.getMq2AnalogPin();
    _mq2DigitalPin = hw.getMq2DigitalPin();

    if (_mq2DigitalPin != PIN_UNUSED) {
        pinMode(_mq2DigitalPin, INPUT);
    }

    loadCalibration();

    Serial.println(F("[Sensor] Initialized with Hardware Profile"));
    Serial.printf("  Climate: %d, MQ2: %s (A0: GPIO %d, D0: GPIO %d)\n",
                  _climateType, _mq2Enabled ? "Enabled" : "Disabled", _mq2AnalogPin, _mq2DigitalPin);
}

void SensorManager::loop() {
    unsigned long now = millis();

    // --- 1. DHT11 / DHT22 Climate Read (every 2.5 seconds) ---
    if (_dhtEnabled && (_climateType == CLIMATE_DHT11 || _climateType == CLIMATE_DHT22)) {
        if (now - _lastDHTRead >= DHT_READ_INTERVAL) {
            _lastDHTRead = now;

            float t = _dht.readTemperature();
            float h = _dht.readHumidity();

            if (isnan(t) || isnan(h)) {
                _dhtFailCount++;
                if (_dhtFailCount >= DHT_FAIL_THRESHOLD && !_dhtFault) {
                    _dhtFault = true;
                    Serial.println(F("[Sensor] DHT FAULT — consecutive read failures"));
                }
            } else {
                _dhtFailCount = 0;
                if (_dhtFault) {
                    _dhtFault = false;
                    Serial.println(F("[Sensor] DHT recovered"));
                }
                _rawTemperature = t;
                _rawHumidity = h;
                _temperature = t + _tempOffset;
                _humidity = constrain(h + _humOffset, 0.0f, 100.0f);
            }
        }
    }
    // --- 2. I2C Climate Read: BME280 / AHT20 / SHT3x (every 2.5 seconds) ---
    else if (_dhtEnabled && (_climateType == CLIMATE_BME280 || _climateType == CLIMATE_AHT20 || _climateType == CLIMATE_SHT3X)) {
        if (now - _lastEnvRead >= DHT_READ_INTERVAL) {
            _lastEnvRead = now;
            if (_bmeDetected) {
                readBME280();
            } else if (_ahtDetected) {
                readAHT20();
            } else if (_shtDetected) {
                readSHT3x();
            }
        }
    } else if (!_dhtEnabled) {
        _dhtFault = false;
    }

    // --- 3. BH1750 Ambient Light (every 1.0 second) ---
    if (_bh1750Detected && (now - _lastLuxRead >= 1000)) {
        _lastLuxRead = now;
        readBH1750();
    }

    // --- 4. Motion / Occupancy (Sample every 100ms) ---
    if (_motionEnabled && _motionPin != PIN_UNUSED) {
        bool reading = (digitalRead(_motionPin) == HIGH);
        if (reading) {
            _motionDetected = true;
            _lastMotionTime = now;
        } else {
            // Latch motion active for 3 seconds after pin drops low
            if (now - _lastMotionTime > 3000) {
                _motionDetected = false;
            }
        }
    }

    // --- 5. DS18B20 1-Wire Probe (Non-blocking conversion every 2.0 seconds) ---
    if (_probeEnabled && _probePin != PIN_UNUSED) {
        if (s_ds18State == 0 && (now - _lastProbeRead >= 2000)) {
            // Trigger 12-bit temperature conversion
            if (ds18b20Reset()) {
                ds18b20WriteByte(0xCC); // SKIP ROM
                ds18b20WriteByte(0x44); // CONVERT T
                s_ds18ConvertStart = now;
                s_ds18State = 1;
            } else {
                _probeFault = true;
                _lastProbeRead = now;
            }
        } else if (s_ds18State == 1 && (now - s_ds18ConvertStart >= 750)) {
            // Read scratchpad
            readDS18B20();
            s_ds18State = 0;
            _lastProbeRead = now;
        }
    }

    // --- 6. Ultrasonic Distance & Water Tank Monitor (every 2.0 seconds) ---
    if (_ultrasonicEnabled && (now - _lastUltrasonicRead >= 2000)) {
        _lastUltrasonicRead = now;
        readUltrasonic();
    }

    // --- 7. MQ2 Read (every 1 second) ---
    if (now - _lastMQ2Read >= MQ2_READ_INTERVAL) {
        _lastMQ2Read = now;

        if (_mq2Enabled && _mq2AnalogPin != PIN_UNUSED) {
            _mq2Raw = analogRead(_mq2AnalogPin);
            if (_mq2DigitalPin != PIN_UNUSED) {
                _mq2DigitalState = !digitalRead(_mq2DigitalPin);
            } else {
                _mq2DigitalState = false;
            }

            // Alarm logic with hysteresis (only after warmup)
            if (!isMQ2Warming()) {
                if (!_mq2AlarmActive && _mq2Raw >= _mq2Threshold) {
                    _mq2AlarmActive = true;
                } else if (_mq2AlarmActive && _mq2Raw < (_mq2Threshold - MQ2_HYSTERESIS)) {
                    _mq2AlarmActive = false;
                }
            }
        } else {
            _mq2Raw = 0;
            _mq2DigitalState = false;
            _mq2AlarmActive = false;
        }
    }

    checkAlarms();
}

// ============================================================================
// Native I2C Drivers
// ============================================================================

bool SensorManager::initBME280(uint8_t addr) {
    _bmeAddr = addr;
    Wire.beginTransmission(addr);
    Wire.write(0xD0);
    if (Wire.endTransmission() != 0) return false;

    Wire.requestFrom((int)addr, 1);
    if (!Wire.available()) return false;
    uint8_t chipId = Wire.read();

    if (chipId == 0x60) {
        _bmeDetected = true;
        _bmpDetected = false;
        Serial.printf("[Sensor] BME280 detected at 0x%02X (ID 0x60)\n", addr);
    } else if (chipId == 0x58) {
        _bmeDetected = true;
        _bmpDetected = true;
        Serial.printf("[Sensor] BMP280 detected at 0x%02X (ID 0x58 - No Humidity)\n", addr);
    } else {
        return false;
    }

    // Read calibration coefficients (0x88..0xA1: 24 bytes)
    Wire.beginTransmission(addr);
    Wire.write(0x88);
    Wire.endTransmission();
    Wire.requestFrom((int)addr, 24);
    if (Wire.available() < 24) return false;

    uint8_t b[24];
    for (int i = 0; i < 24; i++) b[i] = Wire.read();

    _bmeCalib.dig_T1 = (uint16_t)(b[0] | (b[1] << 8));
    _bmeCalib.dig_T2 = (int16_t)(b[2] | (b[3] << 8));
    _bmeCalib.dig_T3 = (int16_t)(b[4] | (b[5] << 8));

    _bmeCalib.dig_P1 = (uint16_t)(b[6] | (b[7] << 8));
    _bmeCalib.dig_P2 = (int16_t)(b[8] | (b[9] << 8));
    _bmeCalib.dig_P3 = (int16_t)(b[10] | (b[11] << 8));
    _bmeCalib.dig_P4 = (int16_t)(b[12] | (b[13] << 8));
    _bmeCalib.dig_P5 = (int16_t)(b[14] | (b[15] << 8));
    _bmeCalib.dig_P6 = (int16_t)(b[16] | (b[17] << 8));
    _bmeCalib.dig_P7 = (int16_t)(b[18] | (b[19] << 8));
    _bmeCalib.dig_P8 = (int16_t)(b[20] | (b[21] << 8));
    _bmeCalib.dig_P9 = (int16_t)(b[22] | (b[23] << 8));

    if (_bmeDetected && !_bmpDetected) {
        // Read H1 (0xA1)
        Wire.beginTransmission(addr);
        Wire.write(0xA1);
        Wire.endTransmission();
        Wire.requestFrom((int)addr, 1);
        if (Wire.available()) _bmeCalib.dig_H1 = Wire.read();

        // Read H2..H6 (0xE1..0xE7: 7 bytes)
        Wire.beginTransmission(addr);
        Wire.write(0xE1);
        Wire.endTransmission();
        Wire.requestFrom((int)addr, 7);
        if (Wire.available() >= 7) {
            uint8_t h[7];
            for (int i = 0; i < 7; i++) h[i] = Wire.read();
            _bmeCalib.dig_H2 = (int16_t)(h[0] | (h[1] << 8));
            _bmeCalib.dig_H3 = h[2];
            _bmeCalib.dig_H4 = (int16_t)((h[3] << 4) | (h[4] & 0x0F));
            _bmeCalib.dig_H5 = (int16_t)((h[5] << 4) | (h[4] >> 4));
            _bmeCalib.dig_H6 = (int8_t)h[6];
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

    return true;
}

void SensorManager::readBME280() {
    Wire.beginTransmission(_bmeAddr);
    Wire.write(0xF7);
    if (Wire.endTransmission() != 0) {
        _dhtFault = true;
        return;
    }

    uint8_t len = (_bmeDetected && !_bmpDetected) ? 8 : 6;
    Wire.requestFrom((int)_bmeAddr, (int)len);
    if (Wire.available() < len) {
        _dhtFault = true;
        return;
    }

    uint8_t buf[8];
    for (int i = 0; i < len; i++) buf[i] = Wire.read();

    // Temperature Compensation
    int32_t adc_T = ((int32_t)buf[3] << 12) | ((int32_t)buf[4] << 4) | ((int32_t)buf[5] >> 4);
    int32_t var1 = ((((adc_T >> 3) - ((int32_t)_bmeCalib.dig_T1 << 1))) * ((int32_t)_bmeCalib.dig_T2)) >> 11;
    int32_t var2 = (((((adc_T >> 4) - ((int32_t)_bmeCalib.dig_T1)) * ((adc_T >> 4) - ((int32_t)_bmeCalib.dig_T1))) >> 12) * ((int32_t)_bmeCalib.dig_T3)) >> 14;
    _t_fine = var1 + var2;
    float t = ((_t_fine * 5 + 128) >> 8) / 100.0f;

    // Pressure Compensation
    int32_t adc_P = ((int32_t)buf[0] << 12) | ((int32_t)buf[1] << 4) | ((int32_t)buf[2] >> 4);
    int64_t p_var1 = ((int64_t)_t_fine) - 128000;
    int64_t p_var2 = p_var1 * p_var1 * (int64_t)_bmeCalib.dig_P6;
    p_var2 = p_var2 + ((p_var1 * (int64_t)_bmeCalib.dig_P5) << 17);
    p_var2 = p_var2 + (((int64_t)_bmeCalib.dig_P4) << 35);
    p_var1 = ((p_var1 * p_var1 * (int64_t)_bmeCalib.dig_P3) >> 8) + ((p_var1 * (int64_t)_bmeCalib.dig_P2) << 12);
    p_var1 = (((((int64_t)1) << 47) + p_var1)) * ((int64_t)_bmeCalib.dig_P1) >> 33;
    float p = 1013.25f;
    if (p_var1 != 0) {
        int64_t p_calc = 1048576 - adc_P;
        p_calc = (((p_calc << 31) - p_var2) * 3125) / p_var1;
        p_var1 = (((int64_t)_bmeCalib.dig_P9) * (p_calc >> 13) * (p_calc >> 13)) >> 25;
        p_var2 = (((int64_t)_bmeCalib.dig_P8) * p_calc) >> 19;
        p_calc = ((p_calc + p_var1 + p_var2) >> 8) + (((int64_t)_bmeCalib.dig_P7) << 4);
        p = (float)p_calc / 256.0f / 100.0f; // hPa
    }

    // Humidity Compensation (BME280 only)
    float h = 0.0f;
    if (_bmeDetected && !_bmpDetected) {
        int32_t adc_H = ((int32_t)buf[6] << 8) | ((int32_t)buf[7]);
        int32_t v_x1_u32r = (_t_fine - ((int32_t)76800));
        v_x1_u32r = (((((adc_H << 14) - (((int32_t)_bmeCalib.dig_H4) << 20) - (((int32_t)_bmeCalib.dig_H5) * v_x1_u32r)) + ((int32_t)16384)) >> 15) *
                     (((((((v_x1_u32r * ((int32_t)_bmeCalib.dig_H6)) >> 10) * (((v_x1_u32r * ((int32_t)_bmeCalib.dig_H3)) >> 11) + ((int32_t)32768))) >> 10) + ((int32_t)2097152)) *
                       ((int32_t)_bmeCalib.dig_H2) + 8192) >> 14));
        v_x1_u32r = (v_x1_u32r - (((((v_x1_u32r >> 15) * (v_x1_u32r >> 15)) >> 7) * ((int32_t)_bmeCalib.dig_H1)) >> 4));
        v_x1_u32r = (v_x1_u32r < 0 ? 0 : v_x1_u32r);
        v_x1_u32r = (v_x1_u32r > 419430400 ? 419430400 : v_x1_u32r);
        h = (float)(v_x1_u32r >> 12) / 1024.0f;
    }

    _rawTemperature = t;
    _rawHumidity = h;
    _rawPressure = p;
    _temperature = t + _tempOffset;
    _humidity = constrain(h + _humOffset, 0.0f, 100.0f);
    _pressure = p;
    _dhtFault = false;
}

bool SensorManager::initAHT20() {
    Wire.beginTransmission(0x38);
    Wire.write(0x71);
    if (Wire.endTransmission() != 0) return false;

    Wire.requestFrom(0x38, 1);
    if (!Wire.available()) return false;
    uint8_t status = Wire.read();

    if ((status & 0x18) != 0x18) {
        Wire.beginTransmission(0x38);
        Wire.write(0xBE);
        Wire.write(0x08);
        Wire.write(0x00);
        Wire.endTransmission();
        delay(10);
    }
    _ahtDetected = true;
    Serial.println(F("[Sensor] AHT20 detected at 0x38"));
    return true;
}

void SensorManager::readAHT20() {
    Wire.beginTransmission(0x38);
    Wire.write(0xAC);
    Wire.write(0x33);
    Wire.write(0x00);
    if (Wire.endTransmission() != 0) {
        _dhtFault = true;
        return;
    }

    delay(80); // Wait for conversion

    Wire.requestFrom(0x38, 6);
    if (Wire.available() < 6) {
        _dhtFault = true;
        return;
    }

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    if ((b[0] & 0x80) != 0) return; // Busy

    uint32_t humRaw = (((uint32_t)b[1] << 12) | ((uint32_t)b[2] << 4) | ((uint32_t)b[3] >> 4));
    uint32_t tempRaw = (((uint32_t)(b[3] & 0x0F) << 16) | ((uint32_t)b[4] << 8) | (uint32_t)b[5]);

    float h = ((float)humRaw * 100.0f) / 1048576.0f;
    float t = (((float)tempRaw * 200.0f) / 1048576.0f) - 50.0f;

    _rawTemperature = t;
    _rawHumidity = h;
    _temperature = t + _tempOffset;
    _humidity = constrain(h + _humOffset, 0.0f, 100.0f);
    _dhtFault = false;
}

bool SensorManager::initSHT3x(uint8_t addr) {
    _shtAddr = addr;
    Wire.beginTransmission(addr);
    Wire.write(0x30);
    Wire.write(0xA2); // Soft Reset
    if (Wire.endTransmission() != 0) return false;

    delay(10);
    _shtDetected = true;
    Serial.printf("[Sensor] SHT3x detected at 0x%02X\n", addr);
    return true;
}

void SensorManager::readSHT3x() {
    Wire.beginTransmission(_shtAddr);
    Wire.write(0x24);
    Wire.write(0x00); // High repeatability, clock stretching disabled
    if (Wire.endTransmission() != 0) {
        _dhtFault = true;
        return;
    }

    delay(16); // High repeatability measurement max 15ms

    Wire.requestFrom((int)_shtAddr, 6);
    if (Wire.available() < 6) {
        _dhtFault = true;
        return;
    }

    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();

    uint16_t tRaw = ((uint16_t)b[0] << 8) | b[1];
    uint16_t hRaw = ((uint16_t)b[3] << 8) | b[4];

    float t = -45.0f + (175.0f * (float)tRaw / 65535.0f);
    float h = 100.0f * ((float)hRaw / 65535.0f);

    _rawTemperature = t;
    _rawHumidity = h;
    _temperature = t + _tempOffset;
    _humidity = constrain(h + _humOffset, 0.0f, 100.0f);
    _dhtFault = false;
}

bool SensorManager::initBH1750() {
    uint8_t addrs[2] = {0x23, 0x5C};
    for (int i = 0; i < 2; i++) {
        uint8_t a = addrs[i];
        Wire.beginTransmission(a);
        Wire.write(0x01); // Power On
        if (Wire.endTransmission() == 0) {
            Wire.beginTransmission(a);
            Wire.write(0x10); // Continuous High Resolution Mode
            Wire.endTransmission();
            return true;
        }
    }
    return false;
}

void SensorManager::readBH1750() {
    uint8_t a = 0x23;
    Wire.requestFrom((int)a, 2);
    if (Wire.available() < 2) {
        a = 0x5C;
        Wire.requestFrom((int)a, 2);
    }
    if (Wire.available() >= 2) {
        uint16_t raw = ((uint16_t)Wire.read() << 8) | Wire.read();
        _lux = (float)raw / 1.2f;
    }
}

// ============================================================================
// 1-Wire DS18B20 Driver
// ============================================================================

bool SensorManager::ds18b20Reset() {
    if (_probePin == PIN_UNUSED) return false;
    pinMode(_probePin, OUTPUT);
    digitalWrite(_probePin, LOW);
    delayMicroseconds(480);

    pinMode(_probePin, INPUT_PULLUP);
    delayMicroseconds(70);
    bool presence = (digitalRead(_probePin) == LOW);
    delayMicroseconds(410);
    return presence;
}

void SensorManager::ds18b20WriteByte(uint8_t b) {
    for (uint8_t i = 0; i < 8; i++) {
        pinMode(_probePin, OUTPUT);
        digitalWrite(_probePin, LOW);
        if (b & 1) {
            delayMicroseconds(5);
            pinMode(_probePin, INPUT_PULLUP);
            delayMicroseconds(55);
        } else {
            delayMicroseconds(60);
            pinMode(_probePin, INPUT_PULLUP);
            delayMicroseconds(5);
        }
        b >>= 1;
    }
}

uint8_t SensorManager::ds18b20ReadByte() {
    uint8_t res = 0;
    for (uint8_t i = 0; i < 8; i++) {
        pinMode(_probePin, OUTPUT);
        digitalWrite(_probePin, LOW);
        delayMicroseconds(2);
        pinMode(_probePin, INPUT_PULLUP);
        delayMicroseconds(8);
        if (digitalRead(_probePin) != 0) {
            res |= (1 << i);
        }
        delayMicroseconds(50);
    }
    return res;
}

void SensorManager::readDS18B20() {
    if (!ds18b20Reset()) {
        _probeFault = true;
        return;
    }
    ds18b20WriteByte(0xCC); // SKIP ROM
    ds18b20WriteByte(0xBE); // READ SCRATCHPAD

    uint8_t lsb = ds18b20ReadByte();
    uint8_t msb = ds18b20ReadByte();
    ds18b20Reset(); // Release 1-Wire bus from remaining scratchpad bytes

    int16_t raw = (int16_t)((msb << 8) | lsb);
    if (raw == -1 || (lsb == 0xFF && msb == 0xFF)) {
        _probeFault = true;
    } else {
        float c = (float)raw / 16.0f;
        if (c >= -55.0f && c <= 125.0f) {
            _probeTemperature = c;
            _probeFault = false;
        } else {
            _probeFault = true;
        }
    }
}

// ============================================================================
// Ultrasonic Distance & Tank Level Driver
// ============================================================================

void SensorManager::readUltrasonic() {
    if (_trigPin == PIN_UNUSED || _echoPin == PIN_UNUSED) return;

    digitalWrite(_trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(_trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(_trigPin, LOW);

    // 25ms timeout cap = ~4.3m max distance (prevents task watchdog reset)
    unsigned long duration = pulseIn(_echoPin, HIGH, 25000);
    if (duration > 0) {
        float dist = (float)duration * 0.0343f / 2.0f;
        _distanceCm = dist;

        float usableDepth = (float)(_tankDepthCm - _tankAirGapCm);
        if (usableDepth > 0) {
            float waterHeight = (float)_tankDepthCm - dist;
            float pct = (waterHeight / usableDepth) * 100.0f;
            _tankLevelPct = (int)constrain(pct, 0.0f, 100.0f);
        }
    }
}

// ============================================================================
// Getters & Status
// ============================================================================

float SensorManager::getTemperature()        { return _temperature; }
float SensorManager::getHumidity()           { return _humidity; }
float SensorManager::getRawTemperature()     { return _rawTemperature; }
float SensorManager::getRawHumidity()        { return _rawHumidity; }
float SensorManager::getPressure()           { return _bmeDetected ? _pressure : 0.0f; }
bool  SensorManager::isDHTFault()            { return _dhtEnabled ? _dhtFault : false; }
float SensorManager::getTempOffset()         { return _tempOffset; }
float SensorManager::getHumOffset()          { return _humOffset; }
void  SensorManager::setTempOffset(float o)  { _tempOffset = o; }
void  SensorManager::setHumOffset(float o)   { _humOffset = o; }
float SensorManager::getTempAlarmThreshold() { return _tempAlarmThreshold; }
void  SensorManager::setTempAlarmThreshold(float t) { _tempAlarmThreshold = t; }

bool SensorManager::isTempAlarm() {
    if (!_dhtEnabled || _dhtFault) return false;
    return _temperature >= _tempAlarmThreshold;
}

float    SensorManager::getLux()             { return _lux; }
bool     SensorManager::isMotionDetected()   { return _motionEnabled ? _motionDetected : false; }
uint32_t SensorManager::getMotionAgeSeconds() {
    if (!_motionEnabled || _lastMotionTime == 0) return 99999;
    return (uint32_t)((millis() - _lastMotionTime) / 1000);
}

float SensorManager::getProbeTemperature()   { return _probeTemperature; }
bool  SensorManager::isProbeFault()          { return _probeEnabled ? _probeFault : false; }
float SensorManager::getDistanceCm()         { return _distanceCm; }
int   SensorManager::getTankLevelPercent()   { return _tankLevelPct; }

int  SensorManager::getMQ2Raw()              { return _mq2Raw; }
bool SensorManager::isMQ2Alarm()            { return _mq2AlarmActive; }
bool SensorManager::isMQ2DigitalTrigger()   { return _mq2DigitalState; }
int  SensorManager::getMQ2Threshold()       { return _mq2Threshold; }
void SensorManager::setMQ2Threshold(int t)  { _mq2Threshold = t; }
int  SensorManager::getMQ2Baseline()        { return _mq2Baseline; }
bool SensorManager::isMQ2Enabled()          { return _mq2Enabled; }
void SensorManager::setMQ2Enabled(bool e)   { _mq2Enabled = e; }

int SensorManager::getMQ2Percent() {
    if (_mq2Raw <= _mq2Baseline) return 0;
    int range = MQ2_ADC_MAX - _mq2Baseline;
    if (range <= 0) return 0;
    int percent = ((_mq2Raw - _mq2Baseline) * 100) / range;
    return constrain(percent, 0, 100);
}

bool SensorManager::isMQ2Warming() {
    if (!_mq2Enabled) return false;
    return (millis() - _bootTime) < MQ2_WARMUP_TIME;
}

void SensorManager::calibrateMQ2() {
    if (_mq2Enabled) {
        _mq2Baseline = _mq2Raw;
        saveCalibration();
        Serial.printf("[Sensor] MQ2 baseline calibrated to %d\n", _mq2Baseline);
    }
}

bool SensorManager::hasAnySensorFault() {
    return (_dhtEnabled && _dhtFault) || (_probeEnabled && _probeFault);
}

bool SensorManager::hasAnyAlarm() {
    return isTempAlarm() || (_mq2Enabled && isMQ2Alarm());
}

void SensorManager::setAlarmCallback(void (*cb)(uint8_t, bool)) {
    _alarmCallback = cb;
}

void SensorManager::saveCalibration() {
    if (!_storage) return;

    JsonDocument doc;
    doc["temp_offset"]    = _tempOffset;
    doc["hum_offset"]     = _humOffset;
    doc["temp_alarm"]     = _tempAlarmThreshold;
    doc["mq2_threshold"]  = _mq2Threshold;
    doc["mq2_baseline"]   = _mq2Baseline;
    doc["mq2_enabled"]    = _mq2Enabled;
    _storage->saveJson(PATH_SENSORS, doc);

    Serial.println(F("[Sensor] Calibration saved"));
}

void SensorManager::toJson(JsonObject& obj) {
    obj["temperature"]     = serialized(String(_temperature, 1));
    obj["humidity"]        = serialized(String(_humidity, 1));
    obj["temp_raw"]        = serialized(String(_rawTemperature, 1));
    obj["hum_raw"]         = serialized(String(_rawHumidity, 1));
    obj["pressure"]        = serialized(String(_bmeDetected ? _pressure : 0.0f, 1));
    obj["pressure_raw"]    = serialized(String(_bmeDetected ? _rawPressure : 0.0f, 1));
    obj["pressure_enabled"] = _bmeDetected;
    obj["dht_fault"]       = isDHTFault();
    obj["dht_enabled"]     = _dhtEnabled;
    obj["temp_alarm"]      = isTempAlarm();
    obj["temp_threshold"]  = _tempAlarmThreshold;
    obj["temp_offset"]     = _tempOffset;
    obj["hum_offset"]      = _humOffset;

    obj["lux"]             = serialized(String(_lux, 1));
    obj["lux_enabled"]     = _bh1750Detected;

    obj["motion"]          = isMotionDetected();
    obj["motion_age_s"]    = getMotionAgeSeconds();
    obj["motion_enabled"]  = _motionEnabled;

    obj["probe_temp"]      = serialized(String(_probeTemperature, 1));
    obj["probe_fault"]     = _probeFault;
    obj["probe_enabled"]   = _probeEnabled;

    obj["distance_cm"]     = serialized(String(_distanceCm, 1));
    obj["tank_level_pct"]  = _tankLevelPct;
    obj["tank_enabled"]    = _ultrasonicEnabled;

    obj["gas_raw"]         = _mq2Raw;
    obj["gas_percent"]     = getMQ2Percent();
    obj["gas_max"]         = MQ2_ADC_MAX;
    obj["gas_alarm"]       = _mq2AlarmActive;
    obj["gas_enabled"]     = _mq2Enabled;
    obj["gas_threshold"]   = _mq2Threshold;
    obj["gas_baseline"]    = _mq2Baseline;
    obj["gas_warming"]     = isMQ2Warming();
    obj["gas_digital"]     = _mq2DigitalState;
}

void SensorManager::loadCalibration() {
    if (!_storage) return;

    JsonDocument doc;
    if (_storage->loadJson(PATH_SENSORS, doc)) {
        _tempOffset         = doc["temp_offset"]   | DHT_TEMP_OFFSET_DEFAULT;
        _humOffset          = doc["hum_offset"]    | DHT_HUM_OFFSET_DEFAULT;
        _tempAlarmThreshold = doc["temp_alarm"]    | DHT_TEMP_ALARM_DEFAULT;
        _mq2Threshold       = doc["mq2_threshold"] | MQ2_DEFAULT_THRESHOLD;
        _mq2Baseline        = doc["mq2_baseline"]  | MQ2_BASELINE_DEFAULT;
        _mq2Enabled         = doc["mq2_enabled"]   | true;
    }
}

void SensorManager::checkAlarms() {
    if (!_alarmCallback) return;

    bool gasAlarm = _mq2Enabled && _mq2AlarmActive;
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
