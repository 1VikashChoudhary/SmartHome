/*
 * ============================================================================
 * LCDManager.h — Non-blocking LCD1602 / LCD2004 I2C Display Manager
 * ============================================================================
 */

#ifndef LCD_MANAGER_H
#define LCD_MANAGER_H

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

class HardwareManager;
class TimeManager;
class SensorManager;
class RelayManager;
class AlarmScheduler;

#define LCD_MAX_COLS        20
#define LCD_MAX_ROWS        4
#define LCD_MAX_CUSTOM_PAGES 9
#define LCD_PAGE_ID_LEN     12
#define LCD_WIDGET_ID_LEN   16

#define LCD_PAGE_SENSOR     0  // Temp/Hum + Relay states
#define LCD_PAGE_NETWORK    1  // Date + IP
#define LCD_PAGE_GAS        2  // MQ2 value
#define LCD_PAGE_MQTT       3  // MQTT + Uptime

// Display mode strings
#define LCD_MODE_ROTATE        "rotate"
#define LCD_MODE_DHT_RELAY     "dht_relay"
#define LCD_MODE_CUSTOM        "custom"

// Alarm overlay types
#define LCD_ALARM_NONE      0
#define LCD_ALARM_GAS       1
#define LCD_ALARM_TEMP      2
#define LCD_ALARM_OTA       3
#define LCD_ALARM_RESET_WIFI 4
#define LCD_ALARM_RESET_FACT 5
#define LCD_ALARM_RESET_CNCL 6
#define LCD_ALARM_RESET_LIGHT 7

class TimeManager;

class LCDManager {
public:
    LCDManager();

    void begin(StorageManager& storage, TimeManager& time);
    void begin(StorageManager& storage, TimeManager& time, HardwareManager& hw);
    void attachModules(HardwareManager& hw, SensorManager& sensor, RelayManager& relay, AlarmScheduler& alarm);
    void loop();

    // Page control
    void nextPage();
    void setPage(uint8_t page);
    uint8_t getCurrentPage();

    // Alarm overlays
    void showAlarm(uint8_t type);
    void clearAlarm();
    void showOTAProgress(int percent);
    void showBootScreen(const char* deviceName);

    // Settings
    bool isEnabled();
    bool isHardwareAllowed() const { return _hwLcdAllowed; }
    void setEnabled(bool enabled);
    bool getBacklight();
    void setBacklight(bool on);
    uint16_t getRotationInterval();
    void setRotationInterval(uint16_t seconds);
    String getDisplayMode();
    void setDisplayMode(const String& mode);
    bool setPages(const JsonArrayConst& pages);
    bool setCustomLines(const JsonArrayConst& lines);
    void appendConfigJson(JsonObject& lcdObj) const;
    void saveConfig();

    static bool isKnownPageId(const char* id);
    static bool isKnownWidgetId(const char* id);

    // Brightness and Auto-Dim Schedule
    uint8_t getBrightness() const { return _brightness; }
    void setBrightness(uint8_t brightness);
    bool isAutoDimEnabled() const { return _autoDim; }
    void setAutoDimEnabled(bool enabled);
    String getDimStartTime() const { return _dimStartTime; }
    void setDimStartTime(const String& time);
    String getDimEndTime() const { return _dimEndTime; }
    void setDimEndTime(const String& time);
    uint8_t getDimmedBrightness() const { return _dimmedBrightness; }
    void setDimmedBrightness(uint8_t brightness);

    // Data update methods (called from main loop)
    void updateSensorData(float temp, float hum, bool dhtFault, bool dhtEnabled = true, bool hasHumidity = true);
    void updateRelayStates(const bool states[5]);
    void updateRelayStates(const bool states[], uint8_t count);
    void updateNetworkInfo(const String& ip, const String& date, const String& dayOfWeek,
                           bool isAP = false, const String& apSSID = "", const String& apPass = "");
    void updateGasData(int gasValue, int threshold, bool alarm, bool warming, bool mq2Enabled = true, bool isSgp40 = false);
    void updateMqttStatus(bool connected, const String& uptime);

private:
    LiquidCrystal_I2C _lcd;
    StorageManager* _storage;
    TimeManager* _time;
    HardwareManager* _hw;
    SensorManager* _sensor;
    RelayManager* _relay;
    AlarmScheduler* _alarm;

    bool _enabled;
    bool _hwLcdAllowed;
    uint8_t _sdaPin;
    uint8_t _sclPin;
    uint8_t _i2cAddr;
    uint8_t _lcdCols;
    uint8_t _lcdRows;
    bool _backlight;
    String _displayMode;      // "rotate" | "dht_relay"
    uint16_t _rotationInterval;  // seconds

    // Brightness and Dimming settings
    uint8_t _brightness;          // 0-100%
    bool _autoDim;
    String _dimStartTime;         // "HH:MM"
    String _dimEndTime;           // "HH:MM"
    uint8_t _dimmedBrightness;     // 0-100%
    uint8_t _currentAppliedBrightness;

    // Display buffers (diff-based update)
    char _buffer[LCD_MAX_ROWS][LCD_MAX_COLS + 1];
    char _prevBuffer[LCD_MAX_ROWS][LCD_MAX_COLS + 1];
    bool _forceRedraw;

    // Page rotation & customizable layout
    uint8_t _currentPage;
    bool _manualPageOverride;
    unsigned long _lastPageChange;
    unsigned long _lastUpdate;
    unsigned long _lastUserInteraction;
    char _pageOrder[LCD_MAX_CUSTOM_PAGES][LCD_PAGE_ID_LEN];
    uint8_t _pageOrderCount;
    char _customLines[LCD_MAX_ROWS][LCD_WIDGET_ID_LEN];

    // Alarm state
    uint8_t _alarmType;
    int _otaProgress;

    // Cached data for pages
    float _temp, _hum;
    bool _dhtFault;
    bool _dhtEnabled;
    bool _hasHumidity;
    uint8_t _numRelays;
    bool _relayStates[MAX_RELAYS];
    String _ipAddr, _dateStr, _dowStr;
    int _gasValue, _gasThreshold;
    bool _gasAlarm, _gasWarming, _mq2Enabled, _gasIsSgp40;
    bool _mqttConnected;
    String _uptimeStr;
    bool _isAPMode;
    String _apSSID;
    String _apPass;

    // Custom characters
    void createCustomChars();

    // Page & widget helpers
    bool isPageHardwareAvailable(const char* pageId) const;
    uint8_t getActivePages(const char* outPages[LCD_MAX_CUSTOM_PAGES]) const;
    void initDefaultLayout();
    void formatShortLabel(const char* raw, const char* fallback, char* out, size_t outSize) const;
    void formatWidgetLine(const char* widgetKey, char* out, size_t outSize, uint8_t cols) const;
    void formatRelaysLine(char* out, size_t outSize, uint8_t cols, bool compactIcons) const;
    void renderPageById(const char* pageId);
    void renderCustomLayout();
    void renderClimateSlotPage();
    void renderRelaysPage();
    void renderTankPage();
    void renderProbePage();
    void renderLuxPage();
    void renderMotionPage();

    // Page renderers
    void renderSensorPage();
    void renderDHTRelayPage();   // NEW: Line1=DHT, Line2=Relay ON/OFF status
    void renderNetworkPage();
    void renderGasPage();
    void renderMqttPage();
    void renderGasAlarm();
    void renderTempAlarm();
    void renderOTAProgress();
    void renderWiFiResetPrompt();
    void renderFactoryResetPrompt();
    void renderResetCancelledPrompt();
    void renderLightResetPrompt();

    // Display update
    void updateDisplay();
    void setLine(uint8_t row, const char* text);
    void setLinef(uint8_t row, const char* fmt, ...);

    void loadConfig();
    void applyBacklight(uint8_t percent);
    bool isTimeInInterval(int hour, int minute, int startHour, int startMin, int endHour, int endMin);
};

#endif // LCD_MANAGER_H
