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
#if defined(ESP32)
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#endif
#include "Config.h"
#include "StorageManager.h"

class HardwareManager;

#ifndef MAX_CLIMATE_SENSORS
#define MAX_CLIMATE_SENSORS     4
#endif
#ifndef MAX_LIGHT_SENSORS
#define MAX_LIGHT_SENSORS       2
#endif
#ifndef MAX_MOTION_SENSORS
#define MAX_MOTION_SENSORS      6
#endif
#ifndef MAX_PROBE_SENSORS
#define MAX_PROBE_SENSORS       4
#endif
#ifndef MAX_ULTRASONIC_SENSORS
#define MAX_ULTRASONIC_SENSORS  4
#endif
#ifndef MAX_MQ2_SENSORS
#define MAX_MQ2_SENSORS         4
#endif

// Alarm type codes for callback
#define ALARM_TYPE_GAS          0
#define ALARM_TYPE_TEMP         1
#define ALARM_TYPE_SENSOR_FAULT 2
#define ALARM_TYPE_TANK_LOW     3
#define ALARM_TYPE_TANK_FULL    4
#define ALARM_TYPE_MOTION       5

// Bosch BME280 / BMP280 Calibration
struct BME280_Calib {
    uint16_t dig_T1;
    int16_t  dig_T2, dig_T3;
    uint16_t dig_P1;
    int16_t  dig_P2, dig_P3, dig_P4, dig_P5, dig_P6, dig_P7, dig_P8, dig_P9;
    uint8_t  dig_H1, dig_H3;
    int16_t  dig_H2, dig_H4, dig_H5;
    int8_t   dig_H6;
};

struct ClimateSlotState {
    bool     enabled;
    uint8_t  type;
    uint8_t  pin;
    uint8_t  i2cAddr;
    char     label[16];
    DHT*     dht;
    bool     i2cDetected;
    bool     bmpDetected;
    BME280_Calib* bmeCalib;
    int32_t  tFine;
    float    temperature;
    float    humidity;
    float    rawTemperature;
    float    rawHumidity;
    float    pressure;
    float    rawPressure;
    float    tempOffset;
    float    humOffset;
    bool          fault;
    bool          hasReading;
    uint8_t       failCount;
    unsigned long lastFaultRetry;
    bool          measPending;
    unsigned long measStartMs;
};

struct LightSlotState {
    bool     enabled;
    bool     detected;
    bool     hasReading;
    uint8_t  i2cAddr;
    char     label[16];
    float    lux;
};

struct MotionSlotState {
    bool          enabled;
    uint8_t       type;
    uint8_t       pin;
    char          label[16];
    bool          detected;
    unsigned long lastMotionTime;
};

struct ProbeSlotState {
    bool          enabled;
    uint8_t       pin;
    char          label[16];
    float         temperature;
    bool          fault;
    uint8_t       failCount;
    unsigned long lastRead;
};

struct UltrasonicSlotState {
    bool     enabled;
    uint8_t  type;
    uint8_t  trigPin;
    uint8_t  echoPin;
    uint16_t tankDepthCm;
    uint16_t tankAirGapCm;
    char     label[16];
    float    distanceCm;
    int      tankLevelPct;
    bool     fault;
    bool     hasReading;
    uint8_t  failCount;
};

struct Mq2SlotState {
    bool          hwAllowed;
    bool          enabled;
    uint8_t       type;         // GAS_MQ2 (0) or GAS_SGP40 (1)
    uint8_t       analogPin;
    uint8_t       digitalPin;
    uint8_t       i2cAddr;
    bool          i2cDetected;
    bool          measPending;
    unsigned long measStartMs;
    unsigned long lastReadMs;
    uint16_t      srawTicks;
    float         vocBaseline;
    char          label[16];
    int           raw;
    int           baseline;
    int           threshold;
    bool          digitalState;
    bool          alarmActive;
};

class SensorManager {
public:
    SensorManager();
    ~SensorManager();

    void begin(StorageManager& storage);
    void begin(StorageManager& storage, HardwareManager& hw);
    void loop();

    // --- Counts & Multi-Instance Accessors ---
    uint8_t getClimateCount() const { return _climateCount; }
    bool    isClimateActiveAt(uint8_t idx) const;
    float   getTemperatureAt(uint8_t idx) const;
    float   getHumidityAt(uint8_t idx) const;
    float   getPressureAt(uint8_t idx) const;
    bool    hasBarometerAt(uint8_t idx) const;
    bool    hasHumidityAt(uint8_t idx) const;
    bool    isClimateFaultAt(uint8_t idx) const;
    bool    isClimateValidAt(uint8_t idx) const;
    float   getTempOffsetAt(uint8_t idx) const;
    float   getHumOffsetAt(uint8_t idx) const;
    void    setTempOffsetAt(uint8_t idx, float offset);
    void    setHumOffsetAt(uint8_t idx, float offset);

    uint8_t getLightCount() const { return _lightCount; }
    bool    isLightActiveAt(uint8_t idx) const;
    bool    isLightValidAt(uint8_t idx) const;
    float   getLuxAt(uint8_t idx) const;

    uint8_t  getMotionCount() const { return _motionCount; }
    bool     isMotionActiveAt(uint8_t idx) const;
    bool     isMotionDetectedAt(uint8_t idx) const;
    uint32_t getMotionAgeSecondsAt(uint8_t idx) const;

    uint8_t getProbeCount() const { return _probeCount; }
    bool    isProbeActiveAt(uint8_t idx) const;
    float   getProbeTemperatureAt(uint8_t idx) const;
    bool    isProbeFaultAt(uint8_t idx) const;

    uint8_t getUltrasonicCount() const { return _ultrasonicCount; }
    bool    isUltrasonicActiveAt(uint8_t idx) const;
    bool    isUltrasonicFaultAt(uint8_t idx) const;
    bool    isUltrasonicValidAt(uint8_t idx) const;
    float   getDistanceCmAt(uint8_t idx) const;
    int     getTankLevelPercentAt(uint8_t idx) const;

    uint8_t getMq2Count() const { return _mq2Count; }
    uint8_t getMq2TypeAt(uint8_t idx) const;
    bool    isMq2ActiveAt(uint8_t idx) const;
    bool    isMq2HwAllowedAt(uint8_t idx) const;
    bool    isMq2WarmingAt(uint8_t idx) const;
    int     getMQ2RawAt(uint8_t idx) const;
    int     getMQ2PercentAt(uint8_t idx) const;
    int     getMQ2BaselineAt(uint8_t idx) const;
    int     getMQ2ThresholdAt(uint8_t idx) const;
    bool    isMQ2AlarmAt(uint8_t idx) const;
    bool    isMQ2DigitalTriggerAt(uint8_t idx) const;
    void    setMQ2ThresholdAt(int idx, int threshold);
    void    setMQ2EnabledAt(int idx, bool enabled);
    void    calibrateMQ2At(int idx = -1);

    // --- Compatibility / Aggregate / Primary Accessors ---
    bool isDhtEnabled() const;
    float getTemperature();
    float getHumidity();
    float getRawTemperature();
    float getRawHumidity();
    float getPressure();
    bool  hasBarometer() const;
    bool  hasHumidity() const;
    bool  isPrimarySgp40() const;
    const char* getPrimaryGasTypeName() const;
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
    bool  isLuxEnabled() const;

    // --- Motion / Presence (PIR / Radar) ---
    bool     isMotionDetected();
    uint32_t getMotionAgeSeconds();
    bool     isMotionEnabled() const;

    // --- Submersible Water Temp Probe (DS18B20) ---
    float getProbeTemperature();
    bool  isProbeFault();
    bool  isProbeEnabled() const;

    // --- Ultrasonic Distance & Tank Level (HC-SR04 / HC-SR04P / JSN-SR04T) ---
    float getDistanceCm();
    int   getTankLevelPercent();
    bool  isUltrasonicEnabled() const;

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
    bool isMQ2HardwareAllowed() const;
    void setMQ2Enabled(bool enabled);

    // --- General ---
    bool hasAnySensorFault();
    bool hasAnyAlarm();
    void setAlarmCallback(void (*cb)(uint8_t alarmType, bool active));
    void saveCalibration();
    void appendStatusJson(JsonObject& obj);
    void toJson(JsonObject& obj);

private:
    StorageManager* _storage;
    unsigned long _bootTime;
    float _tempAlarmThreshold;

    ClimateSlotState    _climates[MAX_CLIMATE_SENSORS];
    uint8_t             _climateCount;
    LightSlotState      _lights[MAX_LIGHT_SENSORS];
    uint8_t             _lightCount;
    MotionSlotState     _motions[MAX_MOTION_SENSORS];
    uint8_t             _motionCount;
    ProbeSlotState      _probes[MAX_PROBE_SENSORS];
    uint8_t             _probeCount;
    UltrasonicSlotState _ultrasonics[MAX_ULTRASONIC_SENSORS];
    uint8_t             _ultrasonicCount;
    Mq2SlotState        _mq2s[MAX_MQ2_SENSORS];
    uint8_t             _mq2Count;

    // Staggered polling schedulers
    unsigned long _lastDHTRead;
    uint8_t       _dhtPollCursor;
    unsigned long _lastEnvRead;
    uint8_t       _envPollCursor;
    unsigned long _lastLuxRead;
    unsigned long _lastLightRetry[MAX_LIGHT_SENSORS];
    unsigned long _lastMQ2Read;
    unsigned long _lastUltrasonicRead;
    uint8_t       _ultrasonicCursor;

    // Non-blocking DS18B20 round-robin state machine
    uint8_t       _ds18State;
    uint8_t       _ds18Cursor;
    unsigned long _ds18ConvertStart;
    unsigned long _lastProbeCycle;

    void cleanup();
    uint8_t primaryClimateIdx() const;
    uint8_t primaryLightIdx() const;
    uint8_t primaryMotionIdx() const;
    uint8_t primaryProbeIdx() const;
    uint8_t primaryUltrasonicIdx() const;
    uint8_t primaryMq2Idx() const;

    // Native I2C Bus & Self-Healing Recovery
    uint8_t       _i2cSdaPin;
    uint8_t       _i2cSclPin;
    unsigned long _lastI2cRecoveryMs;
    void recoverI2cBus();
    void recoverDhtSlot(ClimateSlotState& slot);
    void markClimateFailure(ClimateSlotState& slot, const char* tag);
    void markClimateSuccess(ClimateSlotState& slot, const char* tag);

    // Native I2C Drivers
    bool initBME280(ClimateSlotState& slot, uint8_t addr);
    void readBME280(ClimateSlotState& slot);
    bool initAHT20(ClimateSlotState& slot, uint8_t addr);
    void readAHT20(ClimateSlotState& slot);
    bool initSHT3x(ClimateSlotState& slot, uint8_t addr);
    void readSHT3x(ClimateSlotState& slot);
    bool initSHT4x(ClimateSlotState& slot, uint8_t addr);
    void readSHT4x(ClimateSlotState& slot);
    bool initBH1750(LightSlotState& slot, uint8_t addr);
    void readBH1750(LightSlotState& slot);
    bool initSGP40(Mq2SlotState& slot, uint8_t addr);
    void readSGP40(Mq2SlotState& slot);

    // 1-Wire DS18B20
    bool    ds18b20Reset(uint8_t pin);
    void    ds18b20WriteByte(uint8_t pin, uint8_t b);
    uint8_t ds18b20ReadByte(uint8_t pin);
    bool    readDS18B20Scratchpad(uint8_t pin, float& outTempC);
    void    readDS18B20(ProbeSlotState& slot);
    void    readClimateDS18B20(ClimateSlotState& slot);

    // Ultrasonic
    void readUltrasonic(UltrasonicSlotState& slot);

    // Callback
    void (*_alarmCallback)(uint8_t, bool);

    // Previous alarm states (for edge detection)
    bool _prevTempAlarm;
    bool _prevMQ2Alarm;
    bool _prevSensorFault;
    mutable bool _tempAlarmLatched;
    bool _warmupDone[MAX_MQ2_SENSORS];

#if defined(ESP32)
    mutable SemaphoreHandle_t _sensorMutex;
    void ensureMutex() const;
#endif

    void loadCalibration();
    void checkAlarms();
};

#endif // SENSOR_MANAGER_H
