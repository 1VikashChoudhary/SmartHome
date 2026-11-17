/*
 * ============================================================================
 * Config.h — Central Configuration for ESP32 Smart Home & Monitoring System
 * ============================================================================
 * 
 * All compile-time constants, GPIO assignments, timing values, feature flags,
 * and default settings live here. Every module includes this file.
 * 
 * Target: ESP32 DevKit v1 (ESP-WROOM-32)
 * Framework: Arduino
 * 
 * Copyright (c) 2026 — Production Use
 * ============================================================================
 */

#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ============================================================================
// Firmware Information
// ============================================================================
#define FW_NAME             "SmartHome"
#define FW_VERSION          "1.1.0"
#define FW_BUILD_DATE       __DATE__
#define FW_BUILD_TIME       __TIME__
#define FW_AUTHOR           "SmartHome Project"

// ============================================================================
// Feature Flags (uncomment to enable optional hardware)
// ============================================================================
// #define ENABLE_DS3231     // Enable DS3231 RTC for offline timekeeping
// #define ENABLE_OLED       // Enable OLED display (future)
// #define ENABLE_ESPNOW     // Enable ESP-NOW (future)

// ============================================================================
// GPIO Pin Assignments — ESP32 DevKit v1
// ============================================================================
//
// Pin selection rationale:
//   - Relay pins (16,17,18,19,23): Safe at boot, no strapping functions
//   - Switch pins (13,14,27,26,25): Safe GPIOs with internal pull-up support
//   - Sensor ADC (34): ADC1 channel — ADC2 is unusable when WiFi is active
//   - MQ2 digital (35): Input-only pin, perfect for digital trigger
//   - Buzzer (5): Supports LEDC PWM for tone/volume control
//   - I2C (21,22): Default ESP32 I2C bus
//   - Buttons (15,32,33): Available GPIOs with pull-up support
//
// Avoided pins:
//   GPIO 0:  Boot button / strapping pin
//   GPIO 1:  UART0 TX (Serial output)
//   GPIO 2:  Onboard LED / strapping pin
//   GPIO 3:  UART0 RX (Serial input)
//   GPIO 6-11: Internal flash (UNUSABLE)
//   GPIO 12: Strapping pin (flash voltage — can brick if pulled HIGH!)
//   GPIO 36,39: Reserved for future expansion (input-only)
// ============================================================================

// ============================================================================
// Target Platform & Identification
// ============================================================================
#if defined(ESP8266)
#define TARGET_PLATFORM     "ESP8266"
#define PLATFORM_NAME       "ESP8266"
#elif defined(ESP32)
#define TARGET_PLATFORM     "ESP32"
#define PLATFORM_NAME       "ESP32"
#else
#define TARGET_PLATFORM     "Unknown"
#define PLATFORM_NAME       "Generic"
#endif

#ifndef PIN_UNUSED
#define PIN_UNUSED          255
#endif

// ============================================================================
// GPIO Pin Assignments
// ============================================================================
#if defined(ESP8266)
// --- ESP8266 Pin Selection (NodeMCU / D1 Mini / ESP-12F) ---
// Safe output pins: GPIO 12 (D6), GPIO 14 (D5)
// Safe input pins:  GPIO 13 (D7 - INPUT_PULLUP), GPIO 16 (D0 - requires ext 10k pullup)
// I2C bus:          GPIO 4 (D2 - SDA), GPIO 5 (D1 - SCL)
// Buzzer:           GPIO 2 (D4 - Boot HIGH / Active LOW tone)
// Multi-Button:     GPIO 0 (D3 - Boot Flash button with ext 10k pullup to 3.3V)
// ADC:              A0 (Single 10-bit channel 0-1023)

#define PIN_RELAY_1         12    // D6
#define PIN_RELAY_2         14    // D5
#define PIN_RELAY_3         PIN_UNUSED
#define PIN_RELAY_4         PIN_UNUSED
#define PIN_RELAY_5         PIN_UNUSED

#define PIN_SWITCH_1        13    // D7 (INPUT_PULLUP)
#define PIN_SWITCH_2        16    // D0 (Needs ext pull-up)
#define PIN_SWITCH_3        PIN_UNUSED
#define PIN_SWITCH_4        PIN_UNUSED
#define PIN_SWITCH_5        PIN_UNUSED

#define PIN_DHT22           PIN_UNUSED  // Default to shared I2C (BME280/AHT20/SHT3x)
#define PIN_MQ2_ANALOG      A0          // Native ADC pin
#define PIN_MQ2_DIGITAL     PIN_UNUSED  // Handled via software analog threshold

#define PIN_BUZZER          2     // D4 (Software PWM / Tone)
#define PIN_I2C_SDA         4     // D2 (Default ESP8266 SDA)
#define PIN_I2C_SCL         5     // D1 (Default ESP8266 SCL)
#define PIN_BTN_MULTI       0     // D3 (Boot button, momentary to GND)

#define NUM_RELAYS          2     // Default active relays for ESP8266

#else
// --- ESP32 DevKit v1 (ESP-WROOM-32) ---
#define PIN_RELAY_1         16
#define PIN_RELAY_2         17
#define PIN_RELAY_3         18
#define PIN_RELAY_4         19
#define PIN_RELAY_5         23

#define PIN_SWITCH_1        13
#define PIN_SWITCH_2        14
#define PIN_SWITCH_3        27
#define PIN_SWITCH_4        26
#define PIN_SWITCH_5        25

#define PIN_DHT22           4     // DHT22 data pin
#define PIN_MQ2_ANALOG      34    // ADC1_CH6
#define PIN_MQ2_DIGITAL     35

#define PIN_BUZZER          5     // LEDC PWM capable
#define PIN_I2C_SDA         21    // Default ESP32 SDA
#define PIN_I2C_SCL         22    // Default ESP32 SCL
#define PIN_BTN_MULTI       33    // Combined Multi-function Button

#define NUM_RELAYS          5     // Default active relays for ESP32
#endif

// ============================================================================
// Relay & Sensor Configuration (Dynamic Hardware Profile limits)
// ============================================================================
#define MAX_RELAYS              8
#define MAX_CLIMATE_SENSORS     4
#define MAX_LIGHT_SENSORS       2
#define MAX_MOTION_SENSORS      6
#define MAX_PROBE_SENSORS       4
#define MAX_ULTRASONIC_SENSORS  4
#define MAX_MQ2_SENSORS         4

// Legacy static pin arrays (used for default board initialization)
static const uint8_t RELAY_PINS[NUM_RELAYS] = {
#if defined(ESP8266)
    PIN_RELAY_1, PIN_RELAY_2
#else
    PIN_RELAY_1, PIN_RELAY_2, PIN_RELAY_3, PIN_RELAY_4, PIN_RELAY_5
#endif
};

// Wall Switch GPIO array (matched 1:1 with relays)
static const uint8_t SWITCH_PINS[NUM_RELAYS] = {
#if defined(ESP8266)
    PIN_SWITCH_1, PIN_SWITCH_2
#else
    PIN_SWITCH_1, PIN_SWITCH_2, PIN_SWITCH_3, PIN_SWITCH_4, PIN_SWITCH_5
#endif
};

// Default relay names (up to MAX_RELAYS)
static const char* const DEFAULT_RELAY_NAMES[MAX_RELAYS] = {
    "Relay 1", "Relay 2", "Relay 3", "Relay 4", "Relay 5", "Relay 6", "Relay 7", "Relay 8"
};

// Trigger mode — configurable per relay from web dashboard
enum TriggerMode : uint8_t {
    TRIGGER_ACTIVE_LOW  = 0,   // Relay ON when GPIO LOW (most common)
    TRIGGER_ACTIVE_HIGH = 1    // Relay ON when GPIO HIGH
};

// Boot state — what happens to relay on power-up
enum BootStateMode : uint8_t {
    BOOT_RESTORE_LAST = 0,     // Restore state from before power loss
    BOOT_ALWAYS_ON    = 1,     // Always turn ON at boot
    BOOT_ALWAYS_OFF   = 2      // Always turn OFF at boot
};

// Default trigger mode for all relays
#define DEFAULT_TRIGGER_MODE    TRIGGER_ACTIVE_LOW

// Default boot state for all relays
#define DEFAULT_BOOT_STATE      BOOT_RESTORE_LAST

// ============================================================================
// LCD Configuration (16×2 I2C)
// ============================================================================
#define LCD_I2C_ADDR        0x27
#define LCD_COLS            16
#define LCD_ROWS            2
#define LCD_NUM_PAGES       4     // Normal display pages (not counting alarm)
#define LCD_CUSTOM_CHARS    8     // Max custom characters (0-7)
// #define PIN_LCD_BACKLIGHT_PWM 12 // Optional: uncomment if you wired LCD backlight to an ESP32 PWM pin for true dimming

// ============================================================================
// DHT22 Sensor
// ============================================================================
#define DHT_TYPE            DHT22
#define DHT_READ_INTERVAL   2000      // ms — DHT22 minimum sampling period
#define DHT_FAIL_THRESHOLD  5         // Consecutive failures before fault flag (~10s glitch immunity)
#define DHT_TEMP_ALARM_DEFAULT 45.0f  // °C — default high temperature alarm
#define DHT_TEMP_OFFSET_DEFAULT 0.0f  // °C — calibration offset
#define DHT_HUM_OFFSET_DEFAULT  0.0f  // % — calibration offset

// ============================================================================
// MQ2 Gas Sensor
// ============================================================================
#define MQ2_READ_INTERVAL       1000      // ms
#define MQ2_WARMUP_TIME         60000     // ms — sensor needs ~60s to stabilize

#if defined(ESP8266)
#define MQ2_DEFAULT_THRESHOLD   100       // ADC value (0-1023) for alarm on 10-bit ADC
#define MQ2_HYSTERESIS          15        // ADC below threshold to clear alarm
#define MQ2_ADC_MAX             1023      // 10-bit ADC resolution on ESP8266
#define MQ2_BASELINE_DEFAULT    25        // Clean air baseline ADC value
#else
#define MQ2_DEFAULT_THRESHOLD   400       // ADC value (0-4095) for alarm on 12-bit ADC
#define MQ2_HYSTERESIS          50        // ADC below threshold to clear alarm
#define MQ2_ADC_MAX             4095      // 12-bit ADC resolution on ESP32
#define MQ2_BASELINE_DEFAULT    100       // Clean air baseline ADC value
#endif

// ============================================================================
// Buzzer Configuration
// ============================================================================
#define BUZZER_LEDC_CHANNEL     0         // ESP32 LEDC channel (0-15)
#define BUZZER_DEFAULT_FREQ     2700      // Hz — default tone frequency
#define BUZZER_LEDC_RESOLUTION  8         // bits (0-255 duty cycle)
#define BUZZER_MUTE_DURATION    300000    // ms — 5 minutes mute timeout
#define BUZZER_DEFAULT_VOLUME   128       // Duty cycle (0-255)

// ============================================================================
// WiFi Configuration
// ============================================================================
#define WIFI_AP_SSID_PREFIX           "SmartHome-"  // Followed by last 4 of MAC
#define WIFI_CONNECT_TIMEOUT          30000UL   // ms — time to wait for STA connection
#define WIFI_QUICK_RECONNECT_INTERVAL 5000UL    // ms — brief pause when rotating saved SSIDs or quick link-drop retry
#define WIFI_RECONNECT_INTERVAL       120000UL  // ms — retry router every 2 minutes when unavailable
#define WIFI_MAX_SAVED_NETWORKS       3         // Max stored SSID/password pairs
#define WIFI_DEFAULT_HOSTNAME         "smarthome"

// ============================================================================
// MQTT Configuration
// ============================================================================
#define MQTT_RECONNECT_BASE     2000      // ms — exponential backoff start
#define MQTT_RECONNECT_MAX      30000     // ms — max reconnect interval
#define MQTT_PUBLISH_INTERVAL   30000     // ms — sensor data publish interval
#define MQTT_DEFAULT_PORT       1883
#define MQTT_DEFAULT_PREFIX     "smarthome"
#define MQTT_KEEPALIVE          60        // seconds
#define MQTT_CONNECT_TIMEOUT    10000     // ms — abort hung connect attempts
#define MQTT_BUFFER_SIZE        512       // bytes

// ============================================================================
// NTP / Time Configuration
// ============================================================================
#define NTP_SERVER_1            "pool.ntp.org"
#define NTP_SERVER_2            "time.google.com"
#define NTP_SYNC_INTERVAL       14400000  // ms — 4 hours
#define DEFAULT_TIMEZONE        "IST-5:30"  // POSIX TZ string for India
#define DEFAULT_24H_FORMAT      true

// ============================================================================
// OTA Configuration
// ============================================================================
#define DEFAULT_ARDUINO_OTA     false     // Default state: port 3232 disabled by default; toggleable in Settings
// OTA_PASSWORD removed — ArduinoOTA now uses the admin web password dynamically
#define OTA_HOSTNAME_PREFIX     "smarthome"

// ============================================================================
// Persistent Storage — LittleFS File Paths
// ============================================================================
#define PATH_CONFIG             "/config.json"
#define PATH_HARDWARE           "/hardware.json"
#define PATH_WIFI               "/wifi.json"
#define PATH_MQTT               "/mqtt.json"
#define PATH_RELAYS             "/relays.json"
#define PATH_RELAY_STATES       "/relay_states.json"
#define PATH_SENSORS            "/sensors.json"
#define PATH_ALARMS             "/alarms.json"
#define PATH_LCD                "/lcd.json"
#define PATH_BUZZER             "/buzzer.json"
#define PATH_LOGS               "/logs.json"
#define PATH_RULES              "/rules.json"

#define CONFIG_SCHEMA_VERSION   2   // Increment on breaking config changes

// ============================================================================
// Timing Constants — Non-blocking Intervals (all milliseconds)
// ============================================================================
#define RELAY_SAVE_COALESCE     5000      // Min gap between relay state saves
#define LCD_DEFAULT_ROTATION    5000      // Auto page rotation interval
#define LCD_UPDATE_INTERVAL     500       // Display content refresh
#define BUTTON_DEBOUNCE_MS      50        // Software debounce for all buttons
#define SWITCH_DEBOUNCE_MS      200       // Wall switch debounce (200ms for AC noise immunity)
#define RELAY_SWITCH_LOCKOUT_MS 300       // Ignore switch inputs after relay change (EMI blanking)
#define LONG_PRESS_MS           3000      // Long press detection threshold
#define WIFI_RESET_PRESS_MS     6000      // WiFi Reset threshold (6 seconds)
#define FACTORY_RESET_PRESS_MS  10000     // Factory Reset threshold (10 seconds)
#define CANCEL_RESET_PRESS_MS   14000     // Cancel Reset threshold (14 seconds)
#define WS_STATUS_MIN_INTERVAL  5000      // Minimum per-client status interval
#define WS_STATUS_MAX_INTERVAL  60000     // Maximum per-client status interval
#define DIAG_UPDATE_INTERVAL    5000      // Diagnostics refresh
#define LOG_PERSIST_INTERVAL    300000    // Write log to flash (5 min)
#define LOG_AUTO_CLEAR_DAYS     7         // Auto-clear old log entries
#define ALARM_CHECK_INTERVAL    1000      // Check scheduled alarms/timers (1s)
#define SENSOR_FAULT_RECOVERY   60000     // Retry failed sensor after 60s

// ============================================================================
// Resource Limits
// ============================================================================
#if defined(ESP8266)
#define MAX_ALARMS              10        // Maximum scheduled alarms (scaled for ESP8266 RAM)
#define MAX_SENSOR_RULES        6         // Maximum sensor automation rules
#define MAX_LOG_ENTRIES         20        // Ring buffer log capacity (saves ~18KB RAM on ESP8266)
#define MAX_WS_CLIENTS          3         // Simultaneous WebSocket connections
#define MIN_FREE_HEAP           4096      // 4KB threshold on ESP8266
#define MAX_JSON_DOC_SIZE       2048      // ArduinoJson document capacity
#define SERIAL_PRINTF(fmt, ...) Serial.printf_P(PSTR(fmt), ##__VA_ARGS__)
#else
#define MAX_ALARMS              20        // Maximum scheduled alarms
#define MAX_SENSOR_RULES        10        // Maximum sensor automation rules
#define MAX_LOG_ENTRIES         200       // Ring buffer log capacity
#define MAX_WS_CLIENTS          8         // Simultaneous WebSocket connections
#define MIN_FREE_HEAP           10240     // 10KB — reduce functionality below this
#define MAX_JSON_DOC_SIZE       4096      // ArduinoJson document capacity
#define SERIAL_PRINTF(fmt, ...) Serial.printf(fmt, ##__VA_ARGS__)
#endif

// ============================================================================
// Web Server
// ============================================================================
#define WEB_SERVER_PORT         80
#define DNS_PORT                53        // For captive portal DNS

// ============================================================================
// Watchdog
// ============================================================================
#define WDT_TIMEOUT_SECONDS     30        // Hardware watchdog timeout (normal ops)
#define WDT_OTA_TIMEOUT_SECONDS 60        // Extended timeout during OTA flash erase

// ============================================================================
// Default Device Settings
// ============================================================================
#define DEFAULT_DEVICE_NAME     "SmartHome"
#define DEFAULT_LCD_ENABLED     true
#define DEFAULT_LCD_BACKLIGHT   true
#define DEFAULT_BUZZER_ENABLED  true

#endif // CONFIG_H
