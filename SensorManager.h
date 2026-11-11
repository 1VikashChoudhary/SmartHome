/*
 * ============================================================================
 * SensorManager.h — DHT22 + MQ2 Gas Sensor Management
 * ============================================================================
 */

#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include <Arduino.h>
#include <DHT.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

class HardwareManager;

// Alarm type codes for callback
#define ALARM_TYPE_GAS          0
#define ALARM_TYPE_TEMP         1
#define ALARM_TYPE_SENSOR_FAULT 2
#define ALARM_TYPE_TANK_LOW     3
#define ALARM_TYPE_TANK_FULL    4
#define ALARM_TYPE_MOTION       5

class SensorManager {
public:
    SensorManager();

    void begin(StorageManager& storage);
    void begin(StorageManager& storage, HardwareManager& hw);
    void loop();

    bool isDhtEnabled() const { return _dhtEnabled; }

    // --- Climate (DHT / BME280 / AHT20 / SHT3x) ---
    float getTemperature();
    float getHumidity();
    float getRawTemperature();
    float getRawHumidity();
    float getPressure();
    bool  hasBarometer() const { return _bmeDetected; }
    bool  isDHTFault();
    float getTempOffset();
    float getHumOffset();
    void  setTempOffset(float offset);
    void  setHumOffset(float offset);
    float getTempAlarmThreshold();
    void  setTempAlarmThreshold(float threshold);
    bool  isTempAlarm();

    // --- Optics (BH1750 Ambient Light) ---
    float getLux();
    bool  isLuxEnabled() const { return _bh1750Detected; }

    // --- Motion / Presence (PIR / Radar) ---
    bool     isMotionDetected();
    uint32_t getMotionAgeSeconds();
    bool     isMotionEnabled() const { return _motionEnabled; }

    // --- Submersible Water Temp Probe (DS18B20) ---
    float getProbeTemperature();
    bool  isProbeFault();
    bool  isProbeEnabled() const { return _probeEnabled; }

    // --- Ultrasonic Distance & Tank Level (HC-SR04 / HC-SR04P / JSN-SR04T) ---
    float getDistanceCm();
    int   getTankLevelPercent();
    bool  isUltrasonicEnabled() const { return _ultrasonicEnabled; }

    // --- MQ2 ---
    int getMQ2Raw();
    int getMQ2Percent();
    bool isMQ2Warming();
    bool isMQ2Alarm();
    bool isMQ2DigitalTrigger();
    int getMQ2Threshold();
    void setMQ2Threshold(int threshold);
    int getMQ2Baseline();
    void calibrateMQ2();
    bool isMQ2Enabled();
    void setMQ2Enabled(bool enabled);

    // --- General ---
    bool hasAnySensorFault();
    bool hasAnyAlarm();
    void setAlarmCallback(void (*cb)(uint8_t alarmType, bool active));
    void saveCalibration();
    void toJson(JsonObject& obj);

private:
    StorageManager* _storage;
    DHT _dht;
    bool _dhtEnabled;
    uint8_t _mq2AnalogPin;
    uint8_t _mq2DigitalPin;

    // DHT22 data
    float _temperature;
    float _humidity;
    float _rawTemperature;
    float _rawHumidity;
    float _tempOffset;
    float _humOffset;
    float _tempAlarmThreshold;
    bool _dhtFault;
    uint8_t _dhtFailCount;
    bool _tempAlarmActive;

    // MQ2 data
    int _mq2Raw;
    int _mq2Baseline;
    int _mq2Threshold;
    bool _mq2AlarmActive;
    bool _mq2DigitalState;
    bool _mq2Enabled;
    unsigned long _bootTime;

    // Timing
    unsigned long _lastDHTRead;
    unsigned long _lastMQ2Read;
    unsigned long _lastEnvRead;
    unsigned long _lastLuxRead;

    // Climate Sensor Extensions (I2C)
    uint8_t _climateType;
    bool    _bmeDetected;
    bool    _bmpDetected;
    bool    _ahtDetected;
    bool    _shtDetected;
    bool    _bh1750Detected;
    uint8_t _bmeAddr;
    uint8_t _shtAddr;
    float   _pressure;
    float   _rawPressure;
    float   _lux;

    // Motion / Presence
    bool          _motionEnabled;
    uint8_t       _motionPin;
    bool          _motionDetected;
    unsigned long _lastMotionTime;

    // DS18B20 1-Wire Probe
    bool          _probeEnabled;
    uint8_t       _probePin;
    float         _probeTemperature;
    bool          _probeFault;
    unsigned long _lastProbeRead;

    // Ultrasonic Tank Monitor
    bool          _ultrasonicEnabled;
    uint8_t       _trigPin;
    uint8_t       _echoPin;
    uint16_t      _tankDepthCm;
    uint16_t      _tankAirGapCm;
    float         _distanceCm;
    int           _tankLevelPct;
    unsigned long _lastUltrasonicRead;

    // Bosch BME280 / BMP280 Calibration
    struct BME280_Calib {
        uint16_t dig_T1;
        int16_t  dig_T2, dig_T3;
        uint16_t dig_P1;
        int16_t  dig_P2, dig_P3, dig_P4, dig_P5, dig_P6, dig_P7, dig_P8, dig_P9;
        uint8_t  dig_H1, dig_H3;
        int16_t  dig_H2, dig_H4, dig_H5;
        int8_t   dig_H6;
    } _bmeCalib;
    int32_t _t_fine;

    // Native I2C Drivers
    bool initBME280(uint8_t addr);
    void readBME280();
    bool initAHT20();
    void readAHT20();
    bool initSHT3x(uint8_t addr);
    void readSHT3x();
    bool initBH1750();
    void readBH1750();

    // 1-Wire DS18B20
    bool    ds18b20Reset();
    void    ds18b20WriteByte(uint8_t b);
    uint8_t ds18b20ReadByte();
    void    readDS18B20();

    // Ultrasonic
    void readUltrasonic();

    // Callback
    void (*_alarmCallback)(uint8_t, bool);

    // Previous alarm states (for edge detection)
    bool _prevTempAlarm;
    bool _prevMQ2Alarm;
    bool _prevSensorFault;

    void loadCalibration();
    void checkAlarms();
};

#endif // SENSOR_MANAGER_H
