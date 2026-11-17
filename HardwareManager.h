/*
 * ============================================================================
 * HardwareManager.h — Dynamic Hardware Profile & GPIO Template Engine
 * ============================================================================
 * 
 * Provides Tasmota-style dynamic GPIO configuration, board templates, and
 * pin validation. Decouples hardware pins and channel counts from compile-time
 * constants so a single firmware binary can run on any ESP32 board.
 * 
 * Target: ESP32 DevKit v1 (ESP-WROOM-32)
 * Framework: Arduino
 * ============================================================================
 */

#ifndef HARDWARE_MANAGER_H
#define HARDWARE_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

#ifndef MAX_RELAYS
#define MAX_RELAYS              8
#endif
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

#ifndef PIN_UNUSED
#define PIN_UNUSED          255
#endif

// Wall switch behavior modes (matches Tasmota SwitchMode)
enum SwitchMode : uint8_t {
    SWITCH_MODE_TOGGLE     = 0, // Traditional rocker: flips relay on any edge
    SWITCH_MODE_FOLLOW     = 1, // Closed/LOW = ON, Open/HIGH = OFF
    SWITCH_MODE_FOLLOW_INV = 2, // Closed/LOW = OFF, Open/HIGH = ON
    SWITCH_MODE_PUSHBUTTON = 3, // Momentary pushbutton: flips on press (falling edge)
    SWITCH_MODE_DETACHED   = 4  // Detached: switch does not control relay directly
};

// Climate sensor types
enum ClimateSensorType : uint8_t {
    CLIMATE_NONE    = 0,
    CLIMATE_DHT11   = 1,
    CLIMATE_DHT22   = 2,
    CLIMATE_BME280  = 3,
    CLIMATE_AHT20   = 4,
    CLIMATE_SHT3X   = 5,
    CLIMATE_SHT4X   = 6, // SHT40 / SHT45 (I2C 0x44 / 0x45)
    CLIMATE_DS18B20 = 7  // DS18B20 Ambient Temperature (1-Wire GPIO)
};

// Ambient Light sensor types
enum LightSensorType : uint8_t {
    LIGHT_NONE   = 0,
    LIGHT_BH1750 = 1
};

// Motion / Presence sensor types
enum MotionSensorType : uint8_t {
    MOTION_NONE         = 0,
    MOTION_PIR          = 1,
    MOTION_RADAR_LD2410 = 2
};

// Submersible Probe sensor types
enum ProbeSensorType : uint8_t {
    PROBE_NONE    = 0,
    PROBE_DS18B20 = 1
};

// Ultrasonic Distance & Tank Level sensor types
enum UltrasonicSensorType : uint8_t {
    ULTRASONIC_NONE      = 0,
    ULTRASONIC_HCSR04P   = 1, // 3.3V Native (Recommended, No Resistors)
    ULTRASONIC_HCSR04    = 2, // 5V Legacy (Requires Voltage Divider on Echo)
    ULTRASONIC_JSN_SR04T = 3  // Waterproof Probe (3.3V-5V)
};

// Gas & Air Quality sensor types
enum GasSensorType : uint8_t {
    GAS_MQ2   = 0, // Analog A0 / Digital D0 MQ-2 Smoke & LPG
    GAS_SGP40 = 1  // I2C (0x59) Sensirion SGP40 Indoor Air Quality / VOC
};

// Per-channel hardware mapping
struct ChannelHardware {
    bool enabled;               // true = relay channel active, false = disabled/unused
    uint8_t relayPin;           // Output GPIO or PIN_UNUSED
    bool switchEnabled;         // true = wall switch active, false = wall switch disabled
    uint8_t switchPin;          // Input GPIO or PIN_UNUSED
    SwitchMode switchMode;      // SWITCH_MODE_*
    TriggerMode triggerMode;    // TRIGGER_ACTIVE_LOW or TRIGGER_ACTIVE_HIGH
};

// Per-sensor instance hardware mapping structs
struct ClimateSensorConfig {
    ClimateSensorType type;     // CLIMATE_NONE..CLIMATE_DS18B20
    uint8_t pin;                // GPIO for DHT11/DHT22/DS18B20 or PIN_UNUSED
    uint8_t i2cAddr;            // I2C address for BME280/AHT20/SHT3X/SHT4X (0 = auto/default)
    char label[16];             // Optional label e.g. "Living Room"
};

struct LightSensorConfig {
    LightSensorType type;       // LIGHT_NONE, LIGHT_BH1750
    uint8_t i2cAddr;            // 0x23 or 0x5C
    char label[16];
};

struct MotionSensorConfig {
    MotionSensorType type;      // MOTION_NONE, MOTION_PIR, MOTION_RADAR_LD2410
    uint8_t pin;                // Input GPIO or PIN_UNUSED
    char label[16];
};

struct ProbeSensorConfig {
    ProbeSensorType type;       // PROBE_NONE, PROBE_DS18B20
    uint8_t pin;                // 1-Wire GPIO or PIN_UNUSED
    char label[16];
};

struct UltrasonicSensorConfig {
    UltrasonicSensorType type;  // ULTRASONIC_NONE..ULTRASONIC_JSN_SR04T
    uint8_t trigPin;            // Output GPIO or PIN_UNUSED
    uint8_t echoPin;            // Input GPIO or PIN_UNUSED
    uint16_t tankDepthCm;       // Total tank height (20-500 cm)
    uint16_t tankAirGapCm;      // Sensor air gap to 100% full (5-100 cm)
    char label[16];
};

struct Mq2SensorConfig {
    bool enabled;
    uint8_t type;               // GAS_MQ2 (0) or GAS_SGP40 (1)
    uint8_t analogPin;          // ADC1 GPIO (32..39 ESP32, 17/A0 ESP8266) or PIN_UNUSED
    uint8_t digitalPin;         // Input GPIO or PIN_UNUSED
    uint8_t i2cAddr;            // I2C address for SGP40 (0x59) or 0
    char label[16];
};

// Full hardware profile
struct HardwareConfig {
    char boardName[32];
    uint8_t numRelays;                  // 0..MAX_RELAYS
    ChannelHardware channels[MAX_RELAYS];

    uint8_t numClimates;                // 0..MAX_CLIMATE_SENSORS
    ClimateSensorConfig climates[MAX_CLIMATE_SENSORS];

    uint8_t numLights;                  // 0..MAX_LIGHT_SENSORS
    LightSensorConfig lights[MAX_LIGHT_SENSORS];

    uint8_t numMotions;                 // 0..MAX_MOTION_SENSORS
    MotionSensorConfig motions[MAX_MOTION_SENSORS];

    uint8_t numProbes;                  // 0..MAX_PROBE_SENSORS
    ProbeSensorConfig probes[MAX_PROBE_SENSORS];

    uint8_t numUltrasonics;             // 0..MAX_ULTRASONIC_SENSORS
    UltrasonicSensorConfig ultrasonics[MAX_ULTRASONIC_SENSORS];

    uint8_t numMq2s;                    // 0..MAX_MQ2_SENSORS
    Mq2SensorConfig mq2Sensors[MAX_MQ2_SENSORS];

    bool buzzerEnabled;
    uint8_t buzzerPin;                  // Output PWM GPIO or PIN_UNUSED

    bool lcdEnabled;
    uint8_t lcdI2cAddr;                 // e.g. 0x27, 0x3F
    uint8_t lcdCols;                    // 16 or 20
    uint8_t lcdRows;                    // 2 or 4
    uint8_t i2cSdaPin;                  // default 21 / 4
    uint8_t i2cSclPin;                  // default 22 / 5

    uint8_t btnMultiPin;                // default 33 / 0 or PIN_UNUSED
};

class HardwareManager {
public:
    HardwareManager();

    void begin(StorageManager& storage);

    // --- Accessors ---
    const HardwareConfig& getConfig() const { return _config; }
    const char* getBoardName() const { return _config.boardName; }
    uint8_t getNumRelays() const { return _config.numRelays; }

    bool isChannelEnabled(uint8_t ch) const;
    bool isSwitchEnabled(uint8_t ch) const;
    uint8_t getRelayPin(uint8_t ch) const;
    uint8_t getSwitchPin(uint8_t ch) const;
    SwitchMode getSwitchMode(uint8_t ch) const;
    TriggerMode getTriggerMode(uint8_t ch) const;
    void setTriggerMode(uint8_t ch, TriggerMode mode);

    // --- Multi-Instance Sensor Accessors ---
    uint8_t getClimateCount() const { return _config.numClimates; }
    const ClimateSensorConfig* getClimate(uint8_t idx) const;
    uint8_t getLightCount() const { return _config.numLights; }
    const LightSensorConfig* getLight(uint8_t idx) const;
    uint8_t getMotionCount() const { return _config.numMotions; }
    const MotionSensorConfig* getMotion(uint8_t idx) const;
    uint8_t getProbeCount() const { return _config.numProbes; }
    const ProbeSensorConfig* getProbe(uint8_t idx) const;
    uint8_t getUltrasonicCount() const { return _config.numUltrasonics; }
    const UltrasonicSensorConfig* getUltrasonic(uint8_t idx) const;
    uint8_t getMq2Count() const { return _config.numMq2s; }
    const Mq2SensorConfig* getMq2(uint8_t idx) const;
    bool hasAnyI2cSensor() const;
    static uint8_t defaultI2cAddrForClimate(ClimateSensorType t);
    static uint8_t defaultI2cAddrForLight(LightSensorType t);

    // --- Slot-0 Convenience Compatibility Accessors ---
    ClimateSensorType getDhtType() const;
    uint8_t getDhtPin() const;
    LightSensorType getLightType() const;
    MotionSensorType getMotionType() const;
    uint8_t getMotionPin() const;
    ProbeSensorType getProbeType() const;
    uint8_t getProbePin() const;
    UltrasonicSensorType getUltrasonicType() const;
    uint8_t getTrigPin() const;
    uint8_t getEchoPin() const;
    uint16_t getTankDepthCm() const;
    uint16_t getTankAirGapCm() const;
    bool isMq2Enabled() const;
    uint8_t getMq2AnalogPin() const;
    uint8_t getMq2DigitalPin() const;

    bool isBuzzerEnabled() const { return _config.buzzerEnabled; }
    uint8_t getBuzzerPin() const { return _config.buzzerPin; }

    bool isLcdEnabled() const { return _config.lcdEnabled; }
    uint8_t getLcdI2cAddr() const { return _config.lcdI2cAddr; }
    uint8_t getLcdCols() const { return _config.lcdCols; }
    uint8_t getLcdRows() const { return _config.lcdRows; }
    uint8_t getI2cSdaPin() const { return _config.i2cSdaPin; }
    uint8_t getI2cSclPin() const { return _config.i2cSclPin; }

    uint8_t getBtnMultiPin() const { return _config.btnMultiPin; }

    // --- Template Presets ---
    bool applyPreset(const String& presetName);
    void resetToDefault();

    // --- Validation ---
    static bool validateConfig(const HardwareConfig& cfg, String& outError);
    static bool isSafeOutputPin(uint8_t pin);
    static bool isSafeInputPin(uint8_t pin);
    static bool isAdc1Pin(uint8_t pin);

    // --- Persistence & JSON ---
    bool save();
    bool load();
    void toJson(JsonObject& obj) const;
    bool fromJson(JsonObjectConst obj, String& outError);
    static bool validateHardwareJson(JsonObjectConst obj, String& outError);

    // Helper: list presets and valid pins for Web/App UI
    static void getPresetsJson(JsonArray& arr);
    static void getPinCapabilitiesJson(JsonObject& obj);

private:
    static bool parseHardwareJson(JsonObjectConst obj, HardwareConfig& newCfg, String& outError);
    StorageManager* _storage;
    HardwareConfig _config;

    void setPreset5CH(HardwareConfig& cfg);
    void setPreset1CH(HardwareConfig& cfg);
    void setPreset2CH(HardwareConfig& cfg);
    void setPreset4CH(HardwareConfig& cfg);
    void setPreset8CH(HardwareConfig& cfg);
    void setPresetSensorNode(HardwareConfig& cfg);

    void setPresetESP8266_2CH(HardwareConfig& cfg);
    void setPresetESP8266_1CH(HardwareConfig& cfg);
    void setPresetESP8266_3CH(HardwareConfig& cfg);
    void setPresetESP8266_4CH(HardwareConfig& cfg);
    void setPresetESP8266_8CH(HardwareConfig& cfg);
    void setPresetESP8266_SensorNode(HardwareConfig& cfg);
};

#endif // HARDWARE_MANAGER_H
