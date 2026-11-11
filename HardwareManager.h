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
#define MAX_RELAYS          8
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
    CLIMATE_NONE   = 0,
    CLIMATE_DHT11  = 1,
    CLIMATE_DHT22  = 2,
    CLIMATE_BME280 = 3,
    CLIMATE_AHT20  = 4,
    CLIMATE_SHT3X  = 5
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

// Per-channel hardware mapping
struct ChannelHardware {
    bool enabled;               // true = relay channel active, false = disabled/unused
    uint8_t relayPin;           // Output GPIO or PIN_UNUSED
    bool switchEnabled;         // true = wall switch active, false = wall switch disabled
    uint8_t switchPin;          // Input GPIO or PIN_UNUSED
    SwitchMode switchMode;      // SWITCH_MODE_*
    TriggerMode triggerMode;    // TRIGGER_ACTIVE_LOW or TRIGGER_ACTIVE_HIGH
};

// Full hardware profile
struct HardwareConfig {
    char boardName[32];
    uint8_t numRelays;                  // 0..MAX_RELAYS
    ChannelHardware channels[MAX_RELAYS];

    ClimateSensorType dhtType;          // CLIMATE_NONE, CLIMATE_DHT11, CLIMATE_DHT22, CLIMATE_BME280, CLIMATE_AHT20, CLIMATE_SHT3X
    uint8_t dhtPin;                     // GPIO or PIN_UNUSED

    LightSensorType lightType;          // LIGHT_NONE, LIGHT_BH1750 (uses I2C)

    MotionSensorType motionType;        // MOTION_NONE, MOTION_PIR, MOTION_RADAR_LD2410
    uint8_t motionPin;                  // Input GPIO (e.g. 32) or PIN_UNUSED

    ProbeSensorType probeType;          // PROBE_NONE, PROBE_DS18B20
    uint8_t probePin;                   // 1-Wire GPIO (e.g. 15) or PIN_UNUSED

    UltrasonicSensorType ultrasonicType;// ULTRASONIC_NONE, ULTRASONIC_HCSR04P, ULTRASONIC_HCSR04, ULTRASONIC_JSN_SR04T
    uint8_t trigPin;                    // Output GPIO (e.g. 15 or 32) or PIN_UNUSED
    uint8_t echoPin;                    // Input GPIO (e.g. 35) or PIN_UNUSED
    uint16_t tankDepthCm;               // Total tank height (e.g. 150 cm)
    uint16_t tankAirGapCm;              // Sensor air gap to 100% full (e.g. 15 cm)

    bool mq2Enabled;
    uint8_t mq2AnalogPin;               // ADC1 GPIO (32..39) or PIN_UNUSED
    uint8_t mq2DigitalPin;              // Input GPIO or PIN_UNUSED

    bool buzzerEnabled;
    uint8_t buzzerPin;                  // Output PWM GPIO or PIN_UNUSED

    bool lcdEnabled;
    uint8_t lcdI2cAddr;                 // e.g. 0x27, 0x3F
    uint8_t lcdCols;                    // 16 or 20
    uint8_t lcdRows;                    // 2 or 4
    uint8_t i2cSdaPin;                  // default 21
    uint8_t i2cSclPin;                  // default 22

    uint8_t btnMultiPin;                // default 33 or PIN_UNUSED
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

    ClimateSensorType getDhtType() const { return _config.dhtType; }
    uint8_t getDhtPin() const { return _config.dhtPin; }

    LightSensorType getLightType() const { return _config.lightType; }
    MotionSensorType getMotionType() const { return _config.motionType; }
    uint8_t getMotionPin() const { return _config.motionPin; }
    ProbeSensorType getProbeType() const { return _config.probeType; }
    uint8_t getProbePin() const { return _config.probePin; }
    UltrasonicSensorType getUltrasonicType() const { return _config.ultrasonicType; }
    uint8_t getTrigPin() const { return _config.trigPin; }
    uint8_t getEchoPin() const { return _config.echoPin; }
    uint16_t getTankDepthCm() const { return _config.tankDepthCm; }
    uint16_t getTankAirGapCm() const { return _config.tankAirGapCm; }

    bool isMq2Enabled() const { return _config.mq2Enabled; }
    uint8_t getMq2AnalogPin() const { return _config.mq2AnalogPin; }
    uint8_t getMq2DigitalPin() const { return _config.mq2DigitalPin; }

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

    // Helper: list presets and valid pins for Web/App UI
    static void getPresetsJson(JsonArray& arr);
    static void getPinCapabilitiesJson(JsonObject& obj);

private:
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
    void setPresetESP8266_SensorNode(HardwareConfig& cfg);
};

#endif // HARDWARE_MANAGER_H
