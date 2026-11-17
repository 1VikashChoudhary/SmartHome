/*
 * ============================================================================
 * LCDManager.cpp — Non-blocking LCD1602 / LCD2004 Implementation
 * ============================================================================
 * 
 * KEY DESIGN: Never call lcd.clear(). Only update changed characters via
 * buffer diff to eliminate flicker completely.
 * ============================================================================
 */

#include "LCDManager.h"
#include "TimeManager.h"
#include "HardwareManager.h"
#include "SensorManager.h"
#include "RelayManager.h"
#include "AlarmScheduler.h"

namespace {

const char* const kDefaultPageOrder[LCD_MAX_CUSTOM_PAGES] = {
    "climate", "gas", "tank", "probe", "lux", "motion", "relays", "network", "mqtt"
};

bool parseIndexedWidget(const char* key, const char* prefix, uint8_t maxCount, uint8_t& outIdx) {
    if (!key || !prefix) return false;
    size_t plen = strlen(prefix);
    if (strncmp(key, prefix, plen) != 0) return false;
    const char* numStr = key + plen;
    if (numStr[0] < '0' || numStr[0] > '9' || numStr[1] != '\0') return false;
    uint8_t idx = (uint8_t)(numStr[0] - '0');
    if (idx >= maxCount) return false;
    outIdx = idx;
    return true;
}

} // namespace

// Custom character bitmaps
static const uint8_t CHAR_THERMO[] = {0x04,0x0A,0x0A,0x0E,0x0E,0x1F,0x1F,0x0E};
static const uint8_t CHAR_DROP[]   = {0x04,0x04,0x0A,0x0A,0x11,0x11,0x11,0x0E};
static const uint8_t CHAR_ON[]     = {0x1F,0x1F,0x1F,0x1F,0x1F,0x1F,0x1F,0x1F}; // Filled
static const uint8_t CHAR_OFF[]    = {0x1F,0x11,0x11,0x11,0x11,0x11,0x11,0x1F}; // Hollow
static const uint8_t CHAR_SIGNAL[] = {0x00,0x00,0x00,0x01,0x01,0x05,0x05,0x15};
static const uint8_t CHAR_FLAME[]  = {0x04,0x04,0x0E,0x0E,0x1F,0x1F,0x0E,0x04};
static const uint8_t CHAR_WARN[]   = {0x04,0x04,0x0E,0x0A,0x0E,0x0E,0x04,0x0E};
static const uint8_t CHAR_CHECK[]  = {0x00,0x01,0x03,0x16,0x1C,0x08,0x00,0x00};

LCDManager::LCDManager()
    : _lcd(LCD_I2C_ADDR, LCD_COLS, LCD_ROWS),
      _storage(nullptr), _time(nullptr), _hw(nullptr), _sensor(nullptr),
      _relay(nullptr), _alarm(nullptr), _enabled(DEFAULT_LCD_ENABLED),
      _hwLcdAllowed(true), _sdaPin(PIN_I2C_SDA), _sclPin(PIN_I2C_SCL), _i2cAddr(LCD_I2C_ADDR),
      _lcdCols(LCD_COLS), _lcdRows(LCD_ROWS),
      _backlight(DEFAULT_LCD_BACKLIGHT),
      _displayMode(LCD_MODE_ROTATE),
      _rotationInterval(LCD_DEFAULT_ROTATION / 1000),
      _brightness(100), _autoDim(false),
      _dimStartTime("22:00"), _dimEndTime("06:00"),
      _dimmedBrightness(0), _currentAppliedBrightness(100),
      _forceRedraw(true), _currentPage(0), _manualPageOverride(false),
      _lastPageChange(0), _lastUpdate(0),
      _lastUserInteraction(0), _pageOrderCount(0),
      _alarmType(LCD_ALARM_NONE), _otaProgress(0),
      _temp(0), _hum(0), _dhtFault(false), _dhtEnabled(true), _hasHumidity(true),
      _numRelays(NUM_RELAYS),
      _gasValue(0), _gasThreshold(MQ2_DEFAULT_THRESHOLD),
      _gasAlarm(false), _gasWarming(true), _mq2Enabled(true), _gasIsSgp40(false),
      _mqttConnected(false),
      _isAPMode(false), _apSSID(""), _apPass("") {
    memset(_buffer, ' ', sizeof(_buffer));
    memset(_prevBuffer, 0, sizeof(_prevBuffer)); // Different from spaces to force first draw
    memset(_relayStates, 0, sizeof(_relayStates));
    initDefaultLayout();
    for (int r = 0; r < LCD_MAX_ROWS; r++) {
        _buffer[r][LCD_MAX_COLS] = '\0';
        _prevBuffer[r][LCD_MAX_COLS] = '\0';
    }
}

void LCDManager::begin(StorageManager& storage, TimeManager& time) {
    _storage = &storage;
    _time = &time;
    _numRelays = NUM_RELAYS;
    _sdaPin = PIN_I2C_SDA;
    _sclPin = PIN_I2C_SCL;
    _i2cAddr = LCD_I2C_ADDR;
    _hwLcdAllowed = (_sdaPin != PIN_UNUSED && _sclPin != PIN_UNUSED);
    loadConfig();

    if (!_enabled || !_hwLcdAllowed) {
        _enabled = false;
        Serial.println(F("[LCD] Disabled in config or pins unset"));
        return;
    }

#ifdef PIN_LCD_BACKLIGHT_PWM
    pinMode(PIN_LCD_BACKLIGHT_PWM, OUTPUT);
#endif

    // Initialize I2C bus
    Wire.begin(_sdaPin, _sclPin);

    // Test if LCD is physically present on the I2C bus
    Wire.beginTransmission(_i2cAddr);
    byte error = Wire.endTransmission();
    if (error != 0) {
        SERIAL_PRINTF("[LCD] LCD not detected at I2C address 0x%02X (error: %d). Disabling LCD.\n", _i2cAddr, error);
        _enabled = false;
        return;
    }

    _lcd = LiquidCrystal_I2C(_i2cAddr, _lcdCols, _lcdRows);
    _lcd.init();

    // Determine initial active brightness
    uint8_t initBrightness = _brightness;
    if (_autoDim && _time && _time->isTimeSet()) {
        int hour = _time->getHour();
        int minute = _time->getMinute();
        int startH = 22, startM = 0;
        int endH = 6, endM = 0;
        sscanf(_dimStartTime.c_str(), "%d:%d", &startH, &startM);
        sscanf(_dimEndTime.c_str(), "%d:%d", &endH, &endM);
        if (isTimeInInterval(hour, minute, startH, startM, endH, endM)) {
            initBrightness = _dimmedBrightness;
        }
    }
    _currentAppliedBrightness = initBrightness;
    applyBacklight(_currentAppliedBrightness);

    createCustomChars();
    _forceRedraw = true;
    _lastPageChange = millis();
    _lastUpdate = millis();

    SERIAL_PRINTF("[LCD] Ready (addr: 0x%02X, rotation: %ds, brightness: %d%%)\n",
                  _i2cAddr, _rotationInterval, _brightness);
}

void LCDManager::begin(StorageManager& storage, TimeManager& time, HardwareManager& hw) {
    _storage = &storage;
    _time = &time;
    _hw = &hw;
    _numRelays = hw.getNumRelays();
    if (_numRelays > MAX_RELAYS) _numRelays = MAX_RELAYS;
    loadConfig();

    _sdaPin = hw.getI2cSdaPin();
    _sclPin = hw.getI2cSclPin();
    _i2cAddr = hw.getLcdI2cAddr();
    uint8_t hwCols = hw.getLcdCols();
    uint8_t hwRows = hw.getLcdRows();
    _lcdCols = (hwCols >= 8 && hwCols <= LCD_MAX_COLS) ? hwCols : LCD_COLS;
    _lcdRows = (hwRows >= 1 && hwRows <= LCD_MAX_ROWS) ? hwRows : LCD_ROWS;
    _dhtEnabled = (hw.getDhtType() != CLIMATE_NONE);
    _mq2Enabled = hw.isMq2Enabled();
    _hwLcdAllowed = hw.isLcdEnabled() && (_sdaPin != PIN_UNUSED) && (_sclPin != PIN_UNUSED);

    if (!_enabled || !_hwLcdAllowed) {
        _enabled = false;
        Serial.println(F("[LCD] Disabled in hardware profile"));
        return;
    }

#ifdef PIN_LCD_BACKLIGHT_PWM
    pinMode(PIN_LCD_BACKLIGHT_PWM, OUTPUT);
#endif

    uint8_t sda = _sdaPin;
    uint8_t scl = _sclPin;
    uint8_t addr = _i2cAddr;

    // Initialize I2C bus with hardware profile pins
    Wire.begin(sda, scl);

    Wire.beginTransmission(addr);
    byte error = Wire.endTransmission();
    if (error != 0) {
        SERIAL_PRINTF("[LCD] LCD not detected at I2C 0x%02X (SDA:%d, SCL:%d, error: %d). Disabling LCD.\n",
                      addr, sda, scl, error);
        _enabled = false;
        return;
    }

    _lcd = LiquidCrystal_I2C(addr, _lcdCols, _lcdRows);
    _lcd.init();

    uint8_t initBrightness = _brightness;
    if (_autoDim && _time && _time->isTimeSet()) {
        int hour = _time->getHour();
        int minute = _time->getMinute();
        int startH = 22, startM = 0;
        int endH = 6, endM = 0;
        sscanf(_dimStartTime.c_str(), "%d:%d", &startH, &startM);
        sscanf(_dimEndTime.c_str(), "%d:%d", &endH, &endM);
        if (isTimeInInterval(hour, minute, startH, startM, endH, endM)) {
            initBrightness = _dimmedBrightness;
        }
    }
    _currentAppliedBrightness = initBrightness;
    applyBacklight(_currentAppliedBrightness);

    createCustomChars();
    _forceRedraw = true;
    _lastPageChange = millis();
    _lastUpdate = millis();

    SERIAL_PRINTF("[LCD] Ready via Hardware Profile (addr: 0x%02X, SDA:%d, SCL:%d, %d relays)\n",
                  addr, sda, scl, _numRelays);
}

void LCDManager::attachModules(HardwareManager& hw, SensorManager& sensor, RelayManager& relay, AlarmScheduler& alarm) {
    _hw = &hw;
    _sensor = &sensor;
    _relay = &relay;
    _alarm = &alarm;
    _forceRedraw = true;
}

void LCDManager::loop() {
    if (!_enabled) return;

    unsigned long now = millis();

    // --- Backlight Brightness & Auto Dim Schedule ---
    uint8_t targetBrightness = _brightness;
    if (_autoDim && _time && _time->isTimeSet()) {
        int hour = _time->getHour();
        int minute = _time->getMinute();
        int startH = 22, startM = 0;
        int endH = 6, endM = 0;
        sscanf(_dimStartTime.c_str(), "%d:%d", &startH, &startM);
        sscanf(_dimEndTime.c_str(), "%d:%d", &endH, &endM);
        if (isTimeInInterval(hour, minute, startH, startM, endH, endM)) {
            targetBrightness = _dimmedBrightness;
        }
    }
    if (targetBrightness != _currentAppliedBrightness) {
        _currentAppliedBrightness = targetBrightness;
        applyBacklight(_currentAppliedBrightness);
    }

    // Setup mode is a recovery flow: keep the hotspot credentials visible.
    // Do not let the normal dashboard page rotation hide them.
    if (_isAPMode && _alarmType == LCD_ALARM_NONE) {
        if (_currentPage != 0 || _manualPageOverride) {
            _currentPage = 0;
            _manualPageOverride = false;
            _forceRedraw = true;
        }
        _lastPageChange = now;
    }

    const char* activePages[LCD_MAX_CUSTOM_PAGES];
    uint8_t activeCount = getActivePages(activePages);
    if (_currentPage >= activeCount) {
        _currentPage = 0;
        _forceRedraw = true;
    }

    // Auto page rotation (only in normal Wi-Fi operation, rotate mode, and
    // not during an alarm). AP mode deliberately remains pinned above.
    if (!_isAPMode && _alarmType == LCD_ALARM_NONE && _displayMode == LCD_MODE_ROTATE &&
        _rotationInterval > 0 && activeCount > 1) {
        if (now - _lastPageChange >= (unsigned long)_rotationInterval * 1000UL) {
            _currentPage = (_currentPage + 1) % activeCount;
            _lastPageChange = now;
            _forceRedraw = true;
        }
    }

    // Check idle timeout in Custom / DHT+Relays modes to revert to pinned screen after 5s
    bool isPinnedMode = (_displayMode == LCD_MODE_DHT_RELAY || _displayMode == LCD_MODE_CUSTOM);
    if (!_isAPMode && _alarmType == LCD_ALARM_NONE && isPinnedMode && _manualPageOverride) {
        if (now - _lastUserInteraction >= 5000) {
            _manualPageOverride = false;
            _forceRedraw = true;
        }
    }

    // Update display content periodically
    if (now - _lastUpdate < LCD_UPDATE_INTERVAL && !_forceRedraw) return;
    _lastUpdate = now;

    // Clear off-screen buffer rows cleanly so 20x4 displays never leave stale lines
    uint8_t activeRows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    for (uint8_t r = 0; r < activeRows; r++) {
        setLine(r, "");
    }

    // Render current content to buffer
    if (_alarmType != LCD_ALARM_NONE) {
        switch (_alarmType) {
            case LCD_ALARM_GAS:        renderGasAlarm(); break;
            case LCD_ALARM_TEMP:       renderTempAlarm(); break;
            case LCD_ALARM_OTA:        renderOTAProgress(); break;
            case LCD_ALARM_RESET_WIFI:  renderWiFiResetPrompt(); break;
            case LCD_ALARM_RESET_FACT:  renderFactoryResetPrompt(); break;
            case LCD_ALARM_RESET_CNCL:  renderResetCancelledPrompt(); break;
            case LCD_ALARM_RESET_LIGHT: renderLightResetPrompt(); break;
        }
    } else if (_isAPMode) {
        // The setup hotspot SSID/password is the only useful screen while
        // provisioning. Rendering it directly also protects against a page
        // change requested in the same loop iteration.
        renderNetworkPage();
    } else if (_displayMode == LCD_MODE_CUSTOM && !_manualPageOverride) {
        renderCustomLayout();
    } else if (_displayMode == LCD_MODE_DHT_RELAY && !_manualPageOverride) {
        renderDHTRelayPage();
    } else {
        renderPageById(activePages[_currentPage]);
    }

    // Diff-based display update
    updateDisplay();
    _forceRedraw = false;
}

// ============================================================================
// Page Control
// ============================================================================
void LCDManager::nextPage() {
    const char* activePages[LCD_MAX_CUSTOM_PAGES];
    uint8_t activeCount = getActivePages(activePages);
    if (_displayMode == LCD_MODE_CUSTOM || _displayMode == LCD_MODE_DHT_RELAY) {
        if (!_manualPageOverride) {
            _manualPageOverride = true;
            _currentPage = 0;
        } else {
            _currentPage = (_currentPage + 1) % activeCount;
        }
    } else {
        _currentPage = (_currentPage + 1) % activeCount;
    }
    _lastPageChange = millis();
    _lastUserInteraction = millis();
    _forceRedraw = true;
}

void LCDManager::setPage(uint8_t page) {
    const char* activePages[LCD_MAX_CUSTOM_PAGES];
    uint8_t activeCount = getActivePages(activePages);
    if (page < activeCount) {
        _currentPage = page;
        if (_displayMode == LCD_MODE_CUSTOM || _displayMode == LCD_MODE_DHT_RELAY) {
            _manualPageOverride = true;
        }
        _lastPageChange = millis();
        _lastUserInteraction = millis();
        _forceRedraw = true;
    }
}

uint8_t LCDManager::getCurrentPage() { return _currentPage; }

// ============================================================================
// Alarm Overlays
// ============================================================================
void LCDManager::showAlarm(uint8_t type) {
    _alarmType = type;
    _forceRedraw = true;
}

void LCDManager::clearAlarm() {
    _alarmType = LCD_ALARM_NONE;
    _forceRedraw = true;
}

void LCDManager::showOTAProgress(int percent) {
    _alarmType = LCD_ALARM_OTA;
    _otaProgress = percent;
    _forceRedraw = true;
}

void LCDManager::showBootScreen(const char* deviceName) {
    if (!_enabled) return;
    if (!deviceName) deviceName = "SmartHome";

    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;

    // Direct write for boot screen (one-time, before loop starts)
    _lcd.clear();
    _lcd.setCursor(0, 0);

    // Center device name (bounded to active column width)
    int nameLen = strlen(deviceName);
    int pad = ((int)cols - nameLen) / 2;
    if (pad < 0) pad = 0;
    for (int i = 0; i < pad; i++) _lcd.print(' ');
    for (int i = 0; i < ((int)cols - pad) && i < nameLen; i++) _lcd.print(deviceName[i]);

    _lcd.setCursor(0, 1);
    char verLine[LCD_MAX_COLS + 1];
    snprintf(verLine, sizeof(verLine), "  v%s  Ready  ", FW_VERSION);
    verLine[cols] = '\0';
    _lcd.print(verLine);

    // Mark prev buffer as unknown across all rows to force full redraw on first loop
    memset(_prevBuffer, 0xFF, sizeof(_prevBuffer));
    for (int r = 0; r < LCD_MAX_ROWS; r++) _prevBuffer[r][LCD_MAX_COLS] = '\0';
}

// ============================================================================
// Settings
// ============================================================================
bool LCDManager::isEnabled() { return _enabled; }

void LCDManager::setEnabled(bool enabled) {
    if (enabled && !_hwLcdAllowed) {
        Serial.println(F("[LCD] Cannot enable LCD: disabled or pins unassigned in hardware profile"));
        _enabled = false;
        saveConfig();
        return;
    }
    _enabled = enabled;
    if (_enabled) {
        Wire.begin(_sdaPin, _sclPin);
        Wire.beginTransmission(_i2cAddr);
        if (Wire.endTransmission() != 0) {
            SERIAL_PRINTF("[LCD] Cannot enable LCD: no I2C ACK at 0x%02X\n", _i2cAddr);
            _enabled = false;
            saveConfig();
            return;
        }
        _lcd = LiquidCrystal_I2C(_i2cAddr, _lcdCols, _lcdRows);
        _lcd.init();
        if (_backlight) _lcd.backlight();
        createCustomChars();
        _forceRedraw = true;
    }
    saveConfig();
}

bool LCDManager::getBacklight() { return _brightness > 0; }

void LCDManager::setBacklight(bool on) {
    _backlight = on;
    _brightness = on ? 100 : 0;
    if (_enabled) {
        applyBacklight(_brightness);
        _currentAppliedBrightness = _brightness;
    }
    saveConfig();
}

void LCDManager::setBrightness(uint8_t brightness) {
    _brightness = constrain(brightness, 0, 100);
    _backlight = (_brightness > 0);
    if (_enabled) {
        applyBacklight(_brightness);
        _currentAppliedBrightness = _brightness;
    }
    saveConfig();
}

void LCDManager::setAutoDimEnabled(bool enabled) {
    _autoDim = enabled;
    saveConfig();
}

void LCDManager::setDimStartTime(const String& time) {
    if (time.indexOf(':') < 1 || time.length() < 3 || time.length() > 5) return;
    _dimStartTime = time;
    saveConfig();
}

void LCDManager::setDimEndTime(const String& time) {
    if (time.indexOf(':') < 1 || time.length() < 3 || time.length() > 5) return;
    _dimEndTime = time;
    saveConfig();
}

void LCDManager::setDimmedBrightness(uint8_t brightness) {
    _dimmedBrightness = constrain(brightness, 0, 100);
    saveConfig();
}

uint16_t LCDManager::getRotationInterval() { return _rotationInterval; }

void LCDManager::setRotationInterval(uint16_t seconds) {
    _rotationInterval = constrain(seconds, 3, 30);
    saveConfig();
}

String LCDManager::getDisplayMode() { return _displayMode; }

void LCDManager::setDisplayMode(const String& mode) {
    if (mode == LCD_MODE_DHT_RELAY || mode == LCD_MODE_ROTATE || mode == LCD_MODE_CUSTOM) {
        _displayMode = mode;
    } else {
        _displayMode = LCD_MODE_ROTATE; // Unknown mode — safe default
    }
    _currentPage = 0;
    _manualPageOverride = false;
    _lastPageChange = millis();
    _forceRedraw = true;
    saveConfig();
}

bool LCDManager::setPages(const JsonArrayConst& pages) {
    char nextOrder[LCD_MAX_CUSTOM_PAGES][LCD_PAGE_ID_LEN];
    uint8_t count = 0;
    for (JsonVariantConst v : pages) {
        if (!v.is<const char*>()) continue;
        const char* id = v.as<const char*>();
        if (!isKnownPageId(id)) continue;
        bool dup = false;
        for (uint8_t i = 0; i < count; i++) {
            if (strcmp(nextOrder[i], id) == 0) {
                dup = true;
                break;
            }
        }
        if (dup || count >= LCD_MAX_CUSTOM_PAGES) continue;
        strncpy(nextOrder[count], id, LCD_PAGE_ID_LEN - 1);
        nextOrder[count][LCD_PAGE_ID_LEN - 1] = '\0';
        count++;
    }
    if (count == 0) return false;
    for (uint8_t i = 0; i < count; i++) {
        strncpy(_pageOrder[i], nextOrder[i], LCD_PAGE_ID_LEN);
    }
    _pageOrderCount = count;
    _currentPage = 0;
    _manualPageOverride = false;
    _lastPageChange = millis();
    _forceRedraw = true;
    saveConfig();
    return true;
}

bool LCDManager::setCustomLines(const JsonArrayConst& lines) {
    if (lines.size() == 0) return false;
    char nextLines[LCD_MAX_ROWS][LCD_WIDGET_ID_LEN];
    for (uint8_t r = 0; r < LCD_MAX_ROWS; r++) {
        strncpy(nextLines[r], _customLines[r], LCD_WIDGET_ID_LEN - 1);
        nextLines[r][LCD_WIDGET_ID_LEN - 1] = '\0';
    }
    uint8_t r = 0;
    for (JsonVariantConst v : lines) {
        if (r >= LCD_MAX_ROWS) break;
        if (!v.is<const char*>()) return false;
        const char* id = v.as<const char*>();
        if (!isKnownWidgetId(id)) return false;
        strncpy(nextLines[r], id, LCD_WIDGET_ID_LEN - 1);
        nextLines[r][LCD_WIDGET_ID_LEN - 1] = '\0';
        r++;
    }
    for (uint8_t i = 0; i < LCD_MAX_ROWS; i++) {
        strncpy(_customLines[i], nextLines[i], LCD_WIDGET_ID_LEN);
    }
    _manualPageOverride = false;
    _forceRedraw = true;
    saveConfig();
    return true;
}

void LCDManager::appendConfigJson(JsonObject& lcdObj) const {
    lcdObj["enabled"] = _enabled;
    lcdObj["hw_allowed"] = _hwLcdAllowed;
    lcdObj["cols"] = _lcdCols;
    lcdObj["rows"] = _lcdRows;
    lcdObj["backlight"] = _brightness > 0;
    lcdObj["display_mode"] = _displayMode;
    lcdObj["rotation"] = _rotationInterval;
    lcdObj["brightness"] = _brightness;
    lcdObj["auto_dim"] = _autoDim;
    lcdObj["dim_start"] = _dimStartTime;
    lcdObj["dim_end"] = _dimEndTime;
    lcdObj["dim_brightness"] = _dimmedBrightness;

    JsonArray pagesArr = lcdObj["pages"].to<JsonArray>();
    for (uint8_t i = 0; i < _pageOrderCount; i++) {
        pagesArr.add(_pageOrder[i]);
    }
    JsonArray linesArr = lcdObj["lines"].to<JsonArray>();
    uint8_t activeRows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    for (uint8_t r = 0; r < activeRows; r++) {
        linesArr.add(_customLines[r]);
    }

    JsonObject catalog = lcdObj["catalog"].to<JsonObject>();
    JsonArray catPages = catalog["pages"].to<JsonArray>();
    static const struct { const char* id; const char* label; } kPageLabels[LCD_MAX_CUSTOM_PAGES] = {
        {"climate", "Climate (Temp / Hum / Pressure)"},
        {"gas",     "Air Quality / Gas"},
        {"tank",    "Ultrasonic Tank Level"},
        {"probe",   "Water Temp Probe"},
        {"lux",     "Ambient Light (Lux)"},
        {"motion",  "Motion / Presence"},
        {"relays",  "Relays & Timers"},
        {"network", "Date, Time & IP"},
        {"mqtt",    "MQTT & Uptime"}
    };
    for (uint8_t i = 0; i < LCD_MAX_CUSTOM_PAGES; i++) {
        JsonObject p = catPages.add<JsonObject>();
        p["id"] = kPageLabels[i].id;
        p["label"] = kPageLabels[i].label;
        p["available"] = isPageHardwareAvailable(kPageLabels[i].id);
    }

    JsonArray widgets = catalog["widgets"].to<JsonArray>();
    auto addWidget = [&widgets](const String& id, const String& label) {
        JsonObject w = widgets.add<JsonObject>();
        w["id"] = id;
        w["label"] = label;
    };

    if (_sensor) {
        uint8_t cCount = _sensor->getClimateCount();
        for (uint8_t i = 0; i < cCount; i++) {
            if (!_sensor->isClimateActiveAt(i)) continue;
            const ClimateSensorConfig* cfg = _hw ? _hw->getClimate(i) : nullptr;
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : ("Climate #" + String(i + 1));
            addWidget("climate:" + String(i), lbl + " (Summary)");
            addWidget("temp:" + String(i), lbl + " - Temp");
            if (_sensor->hasHumidityAt(i)) {
                addWidget("hum:" + String(i), lbl + " - Humidity");
            }
            if (_sensor->hasBarometerAt(i)) {
                addWidget("press:" + String(i), lbl + " - Pressure");
            }
        }
        for (uint8_t i = 0; i < _sensor->getMq2Count(); i++) {
            if (!_sensor->isMq2ActiveAt(i)) continue;
            const Mq2SensorConfig* cfg = _hw ? _hw->getMq2(i) : nullptr;
            String kind = (_sensor->getMq2TypeAt(i) == GAS_SGP40) ? "VOC" : "Gas";
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : (kind + " #" + String(i + 1));
            addWidget("gas:" + String(i), lbl + " (" + kind + ")");
        }
        for (uint8_t i = 0; i < _sensor->getUltrasonicCount(); i++) {
            if (!_sensor->isUltrasonicActiveAt(i)) continue;
            const UltrasonicSensorConfig* cfg = _hw ? _hw->getUltrasonic(i) : nullptr;
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : ("Tank #" + String(i + 1));
            addWidget("tank:" + String(i), lbl + " (Level % / cm)");
        }
        for (uint8_t i = 0; i < _sensor->getProbeCount(); i++) {
            if (!_sensor->isProbeActiveAt(i)) continue;
            const ProbeSensorConfig* cfg = _hw ? _hw->getProbe(i) : nullptr;
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : ("Water Probe #" + String(i + 1));
            addWidget("probe:" + String(i), lbl);
        }
        for (uint8_t i = 0; i < _sensor->getLightCount(); i++) {
            if (!_sensor->isLightActiveAt(i)) continue;
            const LightSensorConfig* cfg = _hw ? _hw->getLight(i) : nullptr;
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : ("Light #" + String(i + 1));
            addWidget("lux:" + String(i), lbl + " (Lux)");
        }
        for (uint8_t i = 0; i < _sensor->getMotionCount(); i++) {
            if (!_sensor->isMotionActiveAt(i)) continue;
            const MotionSensorConfig* cfg = _hw ? _hw->getMotion(i) : nullptr;
            String lbl = (cfg && cfg->label[0]) ? String(cfg->label) : ("Motion #" + String(i + 1));
            addWidget("motion:" + String(i), lbl);
        }
    } else {
        if (_dhtEnabled) {
            addWidget("climate:0", "Climate #1 (Summary)");
            addWidget("temp:0", "Climate #1 - Temp");
            if (_hasHumidity) addWidget("hum:0", "Climate #1 - Humidity");
        }
        if (_mq2Enabled) addWidget("gas:0", "Gas / VOC #1");
    }

    if (_numRelays > 0) {
        addWidget("relays", "Relay States");
        addWidget("timer", "Next Active Timer");
    }
    addWidget("time", "Clock & Date");
    addWidget("ip", "IP Address");
    addWidget("mqtt", "MQTT & Uptime");
    addWidget("none", "(Blank Row)");
}

void LCDManager::saveConfig() {
    if (!_storage) return;
    JsonDocument doc;
    _storage->loadJson(PATH_LCD, doc);
    doc["enabled"] = _enabled;
    doc["backlight"] = _backlight;
    doc["display_mode"] = _displayMode;
    doc["rotation"] = _rotationInterval;
    doc["brightness"] = _brightness;
    doc["auto_dim"] = _autoDim;
    doc["dim_start"] = _dimStartTime;
    doc["dim_end"] = _dimEndTime;
    doc["dim_brightness"] = _dimmedBrightness;
    JsonArray pagesArr = doc["pages"].to<JsonArray>();
    for (uint8_t i = 0; i < _pageOrderCount; i++) {
        pagesArr.add(_pageOrder[i]);
    }
    JsonArray linesArr = doc["lines"].to<JsonArray>();
    for (uint8_t r = 0; r < LCD_MAX_ROWS; r++) {
        linesArr.add(_customLines[r]);
    }
    _storage->saveJson(PATH_LCD, doc);
}

// ============================================================================
// Data Update Methods
// ============================================================================
void LCDManager::updateSensorData(float temp, float hum, bool dhtFault, bool dhtEnabled, bool hasHumidity) {
    _temp = temp; _hum = hum; _dhtFault = dhtFault; _dhtEnabled = dhtEnabled; _hasHumidity = hasHumidity;
}

void LCDManager::updateRelayStates(const bool states[5]) {
    updateRelayStates(states, 5);
}

void LCDManager::updateRelayStates(const bool states[], uint8_t count) {
    uint8_t limit = (count < _numRelays) ? count : _numRelays;
    if (limit > MAX_RELAYS) limit = MAX_RELAYS;
    for (uint8_t i = 0; i < limit; i++) {
        if (_relayStates[i] != states[i]) {
            _relayStates[i] = states[i];
            _forceRedraw = true;
        }
    }
}

void LCDManager::updateNetworkInfo(const String& ip, const String& date, const String& dayOfWeek,
                                   bool isAP, const String& apSSID, const String& apPass) {
    _ipAddr = ip;
    _dateStr = date;
    _dowStr = dayOfWeek;
    _isAPMode = isAP;
    _apSSID = apSSID;
    _apPass = apPass;
}

void LCDManager::updateGasData(int gasValue, int threshold, bool alarm, bool warming, bool mq2Enabled, bool isSgp40) {
    _gasValue = gasValue; _gasThreshold = threshold;
    _gasAlarm = alarm; _gasWarming = warming; _mq2Enabled = mq2Enabled; _gasIsSgp40 = isSgp40;
}

void LCDManager::updateMqttStatus(bool connected, const String& uptime) {
    _mqttConnected = connected; _uptimeStr = uptime;
}

// ============================================================================
// Page & Widget Catalog / Renderers
// ============================================================================

void LCDManager::initDefaultLayout() {
    _pageOrderCount = LCD_MAX_CUSTOM_PAGES;
    for (uint8_t i = 0; i < LCD_MAX_CUSTOM_PAGES; i++) {
        strncpy(_pageOrder[i], kDefaultPageOrder[i], LCD_PAGE_ID_LEN - 1);
        _pageOrder[i][LCD_PAGE_ID_LEN - 1] = '\0';
    }
    static const char* const kDefaultLines[LCD_MAX_ROWS] = {"climate:0", "relays", "gas:0", "ip"};
    for (uint8_t r = 0; r < LCD_MAX_ROWS; r++) {
        strncpy(_customLines[r], kDefaultLines[r], LCD_WIDGET_ID_LEN - 1);
        _customLines[r][LCD_WIDGET_ID_LEN - 1] = '\0';
    }
}

bool LCDManager::isKnownPageId(const char* id) {
    if (!id || !id[0]) return false;
    for (uint8_t i = 0; i < LCD_MAX_CUSTOM_PAGES; i++) {
        if (strcmp(id, kDefaultPageOrder[i]) == 0) return true;
    }
    return false;
}

bool LCDManager::isKnownWidgetId(const char* id) {
    if (!id || !id[0]) return false;
    if (strcmp(id, "none") == 0 || strcmp(id, "relays") == 0 || strcmp(id, "timer") == 0 ||
        strcmp(id, "time") == 0 || strcmp(id, "ip") == 0 || strcmp(id, "mqtt") == 0) {
        return true;
    }
    uint8_t dummy = 0;
    return parseIndexedWidget(id, "climate:", MAX_CLIMATE_SENSORS, dummy) ||
           parseIndexedWidget(id, "temp:", MAX_CLIMATE_SENSORS, dummy) ||
           parseIndexedWidget(id, "hum:", MAX_CLIMATE_SENSORS, dummy) ||
           parseIndexedWidget(id, "press:", MAX_CLIMATE_SENSORS, dummy) ||
           parseIndexedWidget(id, "gas:", MAX_MQ2_SENSORS, dummy) ||
           parseIndexedWidget(id, "lux:", MAX_LIGHT_SENSORS, dummy) ||
           parseIndexedWidget(id, "motion:", MAX_MOTION_SENSORS, dummy) ||
           parseIndexedWidget(id, "probe:", MAX_PROBE_SENSORS, dummy) ||
           parseIndexedWidget(id, "tank:", MAX_ULTRASONIC_SENSORS, dummy);
}

bool LCDManager::isPageHardwareAvailable(const char* pageId) const {
    if (!pageId) return false;
    if (strcmp(pageId, "network") == 0 || strcmp(pageId, "mqtt") == 0) return true;
    if (strcmp(pageId, "relays") == 0) return _numRelays > 0;
    if (strcmp(pageId, "climate") == 0) {
        if (_sensor) {
            for (uint8_t i = 0; i < _sensor->getClimateCount(); i++) {
                if (_sensor->isClimateActiveAt(i)) return true;
            }
            return false;
        }
        return _dhtEnabled;
    }
    if (strcmp(pageId, "gas") == 0) {
        return _sensor ? _sensor->isMQ2Enabled() : _mq2Enabled;
    }
    if (strcmp(pageId, "tank") == 0) {
        return _sensor && _sensor->isUltrasonicEnabled();
    }
    if (strcmp(pageId, "probe") == 0) {
        return _sensor && _sensor->isProbeEnabled();
    }
    if (strcmp(pageId, "lux") == 0) {
        return _sensor && _sensor->isLuxEnabled();
    }
    if (strcmp(pageId, "motion") == 0) {
        return _sensor && _sensor->isMotionEnabled();
    }
    return false;
}

uint8_t LCDManager::getActivePages(const char* outPages[LCD_MAX_CUSTOM_PAGES]) const {
    uint8_t count = 0;
    for (uint8_t i = 0; i < _pageOrderCount; i++) {
        if (isPageHardwareAvailable(_pageOrder[i])) {
            outPages[count++] = _pageOrder[i];
        }
    }
    if (count == 0) {
        if (_pageOrderCount > 0) {
            outPages[count++] = _pageOrder[0];
        } else {
            outPages[count++] = "network";
        }
    }
    return count;
}

void LCDManager::formatShortLabel(const char* raw, const char* fallback, char* out, size_t outSize) const {
    if (!out || outSize == 0) return;
    const char* src = (raw && raw[0]) ? raw : fallback;
    if (!src) src = "";
    size_t i = 0;
    while (src[i] != '\0' && i < outSize - 1) {
        out[i] = src[i];
        i++;
    }
    out[i] = '\0';
}

void LCDManager::formatRelaysLine(char* out, size_t outSize, uint8_t cols, bool compactIcons) const {
    if (!out || outSize == 0) return;
    if (_numRelays == 0) {
        snprintf(out, outSize, "No Relays");
        return;
    }
    if (!compactIcons && (_numRelays * 3 - 1) <= (int)cols && outSize >= (size_t)(_numRelays * 3)) {
        int pos = 0;
        for (int i = 0; i < _numRelays; i++) {
            out[pos++] = 'O';
            out[pos++] = _relayStates[i] ? 'N' : 'F';
            if (i < _numRelays - 1) out[pos++] = ' ';
        }
        out[pos] = '\0';
        return;
    }
    int pos = snprintf(out, outSize, "R:");
    int limit = (int)cols - pos;
    if (limit > _numRelays) limit = _numRelays;
    for (int i = 0; i < limit && pos < (int)outSize - 1; i++) {
        out[pos++] = _relayStates[i] ? '\x02' : '\x03';
    }
    out[pos] = '\0';
}

void LCDManager::formatWidgetLine(const char* widgetKey, char* out, size_t outSize, uint8_t cols) const {
    if (!out || outSize == 0) return;
    out[0] = '\0';
    if (!widgetKey || strcmp(widgetKey, "none") == 0) return;

    uint8_t idx = 0;
    if (parseIndexedWidget(widgetKey, "climate:", MAX_CLIMATE_SENSORS, idx)) {
        if (!_sensor || idx >= _sensor->getClimateCount() || !_sensor->isClimateActiveAt(idx)) {
            if (idx == 0 && !_sensor) {
                if (!_dhtEnabled) snprintf(out, outSize, "No Climate Sens");
                else if (_dhtFault) snprintf(out, outSize, _hasHumidity ? "\x08 --.-\xDF""C H:--.-%%" : "\x08 Temp: --.-\xDF""C");
                else if (!_hasHumidity) snprintf(out, outSize, "\x08 Temp: %5.1f\xDF""C", _temp);
                else snprintf(out, outSize, "\x08%5.1f\xDF""C H:%4.1f%%", _temp, _hum);
            } else {
                snprintf(out, outSize, "Climate%u: Off", (unsigned)(idx + 1));
            }
            return;
        }
        bool fault = _sensor->isClimateFaultAt(idx);
        bool hasHum = _sensor->hasHumidityAt(idx);
        bool hasBaro = _sensor->hasBarometerAt(idx);
        float t = _sensor->getTemperatureAt(idx);
        float h = _sensor->getHumidityAt(idx);
        float p = _sensor->getPressureAt(idx);
        if (fault) {
            snprintf(out, outSize, "C%u: Sensor ERR", (unsigned)(idx + 1));
        } else if (cols >= 20 && hasHum && hasBaro) {
            snprintf(out, outSize, "%4.1f\xDF""C %2.0f%% %6.1fhPa", t, h, p);
        } else if (!hasHum && hasBaro) {
            snprintf(out, outSize, "%4.1f\xDF""C %4.0fhPa", t, p);
        } else if (!hasHum) {
            const ClimateSensorConfig* cfg = _hw ? _hw->getClimate(idx) : nullptr;
            char lbl[7];
            formatShortLabel(cfg ? cfg->label : nullptr, "Temp", lbl, sizeof(lbl));
            snprintf(out, outSize, "%-5s:%5.1f\xDF""C", lbl, t);
        } else if (_sensor->getClimateCount() > 1) {
            snprintf(out, outSize, "C%u:%4.1f\xDF""C H:%2.0f%%", (unsigned)(idx + 1), t, h);
        } else {
            snprintf(out, outSize, "\x08%5.1f\xDF""C H:%4.1f%%", t, h);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "temp:", MAX_CLIMATE_SENSORS, idx)) {
        const ClimateSensorConfig* cfg = _hw ? _hw->getClimate(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "Temp%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (_sensor) {
            if (!_sensor->isClimateActiveAt(idx)) snprintf(out, outSize, "%s: Off", lbl);
            else if (_sensor->isClimateFaultAt(idx)) snprintf(out, outSize, "%s: ERR", lbl);
            else snprintf(out, outSize, "%s: %5.1f\xDF""C", lbl, _sensor->getTemperatureAt(idx));
        } else if (idx == 0 && _dhtEnabled) {
            if (_dhtFault) snprintf(out, outSize, "Temp: --.-\xDF""C");
            else snprintf(out, outSize, "Temp: %5.1f\xDF""C", _temp);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "hum:", MAX_CLIMATE_SENSORS, idx)) {
        const ClimateSensorConfig* cfg = _hw ? _hw->getClimate(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "Hum%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (_sensor) {
            if (!_sensor->isClimateActiveAt(idx) || !_sensor->hasHumidityAt(idx)) snprintf(out, outSize, "%s: --", lbl);
            else if (_sensor->isClimateFaultAt(idx)) snprintf(out, outSize, "%s: ERR", lbl);
            else snprintf(out, outSize, "%s: %4.1f%%", lbl, _sensor->getHumidityAt(idx));
        } else if (idx == 0 && _dhtEnabled && _hasHumidity) {
            snprintf(out, outSize, "Hum: %5.1f%%", _hum);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "press:", MAX_CLIMATE_SENSORS, idx)) {
        const ClimateSensorConfig* cfg = _hw ? _hw->getClimate(idx) : nullptr;
        char lbl[7];
        formatShortLabel(cfg ? cfg->label : nullptr, "Pres", lbl, (cols >= 20) ? 7 : 5);
        if (_sensor && _sensor->isClimateActiveAt(idx) && _sensor->hasBarometerAt(idx)) {
            if (_sensor->isClimateFaultAt(idx)) snprintf(out, outSize, "%s: ERR", lbl);
            else snprintf(out, outSize, "%s:%6.1fhPa", lbl, _sensor->getPressureAt(idx));
        } else {
            snprintf(out, outSize, "%s: -- hPa", lbl);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "gas:", MAX_MQ2_SENSORS, idx)) {
        if (!_sensor) {
            if (idx == 0 && _mq2Enabled) {
                const char* tag = _gasIsSgp40 ? "VOC" : "Gas";
                if (_gasWarming) snprintf(out, outSize, "%s:Warming %d", tag, _gasValue);
                else if (_gasAlarm) snprintf(out, outSize, "!%s ALRM! %d", tag, _gasValue);
                else snprintf(out, outSize, "%s:%4d/%4d", tag, _gasValue, _gasThreshold);
            } else {
                snprintf(out, outSize, "Gas%u: Off", (unsigned)(idx + 1));
            }
            return;
        }
        if (!_sensor->isMq2ActiveAt(idx)) {
            snprintf(out, outSize, "Gas%u: Off", (unsigned)(idx + 1));
            return;
        }
        bool isSgp40 = (_sensor->getMq2TypeAt(idx) == GAS_SGP40);
        const char* tag = isSgp40 ? "VOC" : "Gas";
        int val = _sensor->getMQ2RawAt(idx);
        int thr = _sensor->getMQ2ThresholdAt(idx);
        if (_sensor->isMq2WarmingAt(idx)) {
            snprintf(out, outSize, "%s%u:Warm %d", tag, (unsigned)(idx + 1), val);
        } else if (_sensor->isMQ2AlarmAt(idx)) {
            snprintf(out, outSize, "!%s%u ALRM %d!", tag, (unsigned)(idx + 1), val);
        } else {
            snprintf(out, outSize, "%s%u:%4d/%d", tag, (unsigned)(idx + 1), val, thr);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "lux:", MAX_LIGHT_SENSORS, idx)) {
        const LightSensorConfig* cfg = _hw ? _hw->getLight(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "Lux%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (!_sensor || !_sensor->isLightActiveAt(idx)) {
            snprintf(out, outSize, "%s: Off", lbl);
        } else {
            float lux = _sensor->getLuxAt(idx);
            if (lux >= 100.0f) snprintf(out, outSize, "%s:%.0f lx", lbl, lux);
            else snprintf(out, outSize, "%s:%.1f lx", lbl, lux);
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "motion:", MAX_MOTION_SENSORS, idx)) {
        const MotionSensorConfig* cfg = _hw ? _hw->getMotion(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "PIR%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (!_sensor || !_sensor->isMotionActiveAt(idx)) {
            snprintf(out, outSize, "%s: Off", lbl);
        } else if (_sensor->isMotionDetectedAt(idx)) {
            snprintf(out, outSize, "%s: MOTION!", lbl);
        } else {
            uint32_t age = _sensor->getMotionAgeSecondsAt(idx);
            if (age == 0 || age >= 86400UL) snprintf(out, outSize, "%s: Clear", lbl);
            else if (age < 60) snprintf(out, outSize, "%s: Clr %lus", lbl, (unsigned long)age);
            else if (age < 3600) snprintf(out, outSize, "%s: Clr %lum", lbl, (unsigned long)(age / 60));
            else snprintf(out, outSize, "%s: Clr %luh", lbl, (unsigned long)(age / 3600));
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "probe:", MAX_PROBE_SENSORS, idx)) {
        const ProbeSensorConfig* cfg = _hw ? _hw->getProbe(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "Wtr%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (!_sensor || !_sensor->isProbeActiveAt(idx)) {
            snprintf(out, outSize, "%s: Off", lbl);
        } else if (_sensor->isProbeFaultAt(idx)) {
            snprintf(out, outSize, "%s: ERR", lbl);
        } else {
            snprintf(out, outSize, "%s:%5.1f\xDF""C", lbl, _sensor->getProbeTemperatureAt(idx));
        }
        return;
    }

    if (parseIndexedWidget(widgetKey, "tank:", MAX_ULTRASONIC_SENSORS, idx)) {
        const UltrasonicSensorConfig* cfg = _hw ? _hw->getUltrasonic(idx) : nullptr;
        char lbl[8];
        char defLbl[8];
        snprintf(defLbl, sizeof(defLbl), "Tank%u", (unsigned)(idx + 1));
        formatShortLabel(cfg ? cfg->label : nullptr, defLbl, lbl, (cols >= 20) ? 8 : 6);
        if (!_sensor || !_sensor->isUltrasonicActiveAt(idx)) {
            snprintf(out, outSize, "%s: Off", lbl);
        } else {
            int pct = _sensor->getTankLevelPercentAt(idx);
            float cm = _sensor->getDistanceCmAt(idx);
            if (pct < 0) snprintf(out, outSize, "%s: ERR", lbl);
            else snprintf(out, outSize, "%s:%d%% %.0fcm", lbl, pct, cm);
        }
        return;
    }

    if (strcmp(widgetKey, "relays") == 0) {
        formatRelaysLine(out, outSize, cols, _numRelays > 3);
        return;
    }

    if (strcmp(widgetKey, "timer") == 0) {
        if (_relay && _alarm) {
            bool found = false;
            uint8_t bestCh = 0;
            bool bestTarget = false;
            uint32_t bestRem = 0xFFFFFFFFUL;
            uint8_t cnt = _relay->getRelayCount();
            for (uint8_t i = 0; i < cnt && i < MAX_RELAYS; i++) {
                if (!_relay->isChannelEnabled(i)) continue;
                bool active = false, target = false;
                uint32_t rem = 0;
                if (_alarm->resolveEffectiveTimerForRelay(*_relay, i, active, target, rem) && active && rem < bestRem) {
                    found = true;
                    bestCh = i;
                    bestTarget = target;
                    bestRem = rem;
                }
            }
            if (found) {
                uint32_t m = bestRem / 60;
                uint32_t s = bestRem % 60;
                if (m >= 60) {
                    snprintf(out, outSize, "Tmr R%u>%s %luh%02lum", (unsigned)(bestCh + 1), bestTarget ? "ON" : "OF", (unsigned long)(m / 60), (unsigned long)(m % 60));
                } else {
                    snprintf(out, outSize, "Tmr R%u>%s %02lu:%02lu", (unsigned)(bestCh + 1), bestTarget ? "ON" : "OF", (unsigned long)m, (unsigned long)s);
                }
                return;
            }
        }
        snprintf(out, outSize, "Timers: None");
        return;
    }

    if (strcmp(widgetKey, "time") == 0) {
        if (_time && _time->isTimeSet()) {
            String tStr = _time->getFormattedTime();
            if (cols >= 20) {
                if (tStr.length() > 8) {
                    snprintf(out, outSize, "%s %.6s", tStr.c_str(), _dateStr.c_str());
                } else {
                    snprintf(out, outSize, "%s %s", tStr.c_str(), _dateStr.c_str());
                }
            } else {
                snprintf(out, outSize, "%-11s %.3s", tStr.c_str(), _dowStr.c_str());
            }
        } else {
            snprintf(out, outSize, "%-12s %3s", _dateStr.c_str(), _dowStr.c_str());
        }
        return;
    }

    if (strcmp(widgetKey, "ip") == 0) {
        if (cols >= 20) snprintf(out, outSize, "IP: %s", _ipAddr.c_str());
        else snprintf(out, outSize, "%s", _ipAddr.c_str());
        return;
    }

    if (strcmp(widgetKey, "mqtt") == 0) {
        snprintf(out, outSize, "MQ:%s Up:%s", _mqttConnected ? "OK" : "--", _uptimeStr.c_str());
    }
}

void LCDManager::renderCustomLayout() {
    uint8_t activeRows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    char lineBuf[LCD_MAX_COLS + 8];
    for (uint8_t r = 0; r < activeRows; r++) {
        formatWidgetLine(_customLines[r], lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

void LCDManager::renderPageById(const char* pageId) {
    if (!pageId || strcmp(pageId, "climate") == 0) {
        renderClimateSlotPage();
    } else if (strcmp(pageId, "relays") == 0) {
        renderRelaysPage();
    } else if (strcmp(pageId, "gas") == 0) {
        if (_sensor && _sensor->getMq2Count() >= 2) {
            uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
            uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
            uint8_t rowOut = 0;
            char lineBuf[LCD_MAX_COLS + 8];
            for (uint8_t i = 0; i < _sensor->getMq2Count() && rowOut < rows; i++) {
                if (!_sensor->isMq2ActiveAt(i)) continue;
                char key[10];
                snprintf(key, sizeof(key), "gas:%u", (unsigned)i);
                formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
                setLine(rowOut++, lineBuf);
            }
            if (rowOut == 0) renderGasPage();
        } else {
            renderGasPage();
        }
    } else if (strcmp(pageId, "tank") == 0) {
        renderTankPage();
    } else if (strcmp(pageId, "probe") == 0) {
        renderProbePage();
    } else if (strcmp(pageId, "lux") == 0) {
        renderLuxPage();
    } else if (strcmp(pageId, "motion") == 0) {
        renderMotionPage();
    } else if (strcmp(pageId, "network") == 0) {
        renderNetworkPage();
    } else if (strcmp(pageId, "mqtt") == 0) {
        renderMqttPage();
    } else {
        renderSensorPage();
    }
}

void LCDManager::renderClimateSlotPage() {
    if (!_sensor) {
        renderSensorPage();
        return;
    }
    uint8_t activeIndices[MAX_CLIMATE_SENSORS];
    uint8_t activeCount = 0;
    for (uint8_t i = 0; i < _sensor->getClimateCount() && activeCount < MAX_CLIMATE_SENSORS; i++) {
        if (_sensor->isClimateActiveAt(i)) activeIndices[activeCount++] = i;
    }
    if (activeCount <= 1) {
        uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
        if (activeCount == 1 && _sensor->hasBarometerAt(activeIndices[0]) && _sensor->hasHumidityAt(activeIndices[0])) {
            char lineBuf[LCD_MAX_COLS + 8];
            char key[12];
            snprintf(key, sizeof(key), "climate:%u", (unsigned)activeIndices[0]);
            formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
            setLine(0, lineBuf);
            if (_lcdRows >= 4) {
                snprintf(key, sizeof(key), "press:%u", (unsigned)activeIndices[0]);
                formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
                setLine(1, lineBuf);
                formatRelaysLine(lineBuf, sizeof(lineBuf), cols, true);
                setLine(2, lineBuf);
                setLinef(3, "%-14.14s MQ:%s", _ipAddr.c_str(), _mqttConnected ? "OK" : "--");
            } else {
                snprintf(key, sizeof(key), "press:%u", (unsigned)activeIndices[0]);
                formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
                setLine(1, lineBuf);
            }
            return;
        }
        renderSensorPage();
        return;
    }

    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    char lineBuf[LCD_MAX_COLS + 8];
    for (uint8_t r = 0; r < activeCount && r < rows; r++) {
        char key[12];
        snprintf(key, sizeof(key), "climate:%u", (unsigned)activeIndices[r]);
        formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

void LCDManager::renderRelaysPage() {
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    char lineBuf[LCD_MAX_COLS + 8];
    formatRelaysLine(lineBuf, sizeof(lineBuf), cols, _numRelays > 3);
    setLine(0, lineBuf);
    formatWidgetLine("timer", lineBuf, sizeof(lineBuf), cols);
    setLine(1, lineBuf);
    if (_lcdRows >= 4) {
        formatWidgetLine("time", lineBuf, sizeof(lineBuf), cols);
        setLine(2, lineBuf);
        formatWidgetLine("ip", lineBuf, sizeof(lineBuf), cols);
        setLine(3, lineBuf);
    }
}

void LCDManager::renderTankPage() {
    if (!_sensor || !_sensor->isUltrasonicEnabled()) {
        setLine(0, "Tank Disabled");
        setLine(1, "Off in HW Config");
        return;
    }
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t activeIndices[MAX_ULTRASONIC_SENSORS];
    uint8_t activeCount = 0;
    for (uint8_t i = 0; i < _sensor->getUltrasonicCount() && activeCount < MAX_ULTRASONIC_SENSORS; i++) {
        if (_sensor->isUltrasonicActiveAt(i)) activeIndices[activeCount++] = i;
    }
    char lineBuf[LCD_MAX_COLS + 8];
    if (activeCount == 1) {
        uint8_t idx = activeIndices[0];
        const UltrasonicSensorConfig* cfg = _hw ? _hw->getUltrasonic(idx) : nullptr;
        char lbl[12];
        formatShortLabel(cfg ? cfg->label : nullptr, "Tank", lbl, sizeof(lbl));
        int pct = _sensor->getTankLevelPercentAt(idx);
        float cm = _sensor->getDistanceCmAt(idx);
        if (pct < 0) {
            setLinef(0, "%s: Fault", lbl);
            setLine(1, "Check Ultrasonic");
        } else {
            setLinef(0, "%-10s %3d%%", lbl, pct);
            setLinef(1, "Dist: %5.1f cm", cm);
        }
        if (rows >= 4) {
            formatRelaysLine(lineBuf, sizeof(lineBuf), cols, true);
            setLine(2, lineBuf);
            formatWidgetLine("ip", lineBuf, sizeof(lineBuf), cols);
            setLine(3, lineBuf);
        }
        return;
    }
    for (uint8_t r = 0; r < activeCount && r < rows; r++) {
        char key[10];
        snprintf(key, sizeof(key), "tank:%u", (unsigned)activeIndices[r]);
        formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

void LCDManager::renderProbePage() {
    if (!_sensor || !_sensor->isProbeEnabled()) {
        setLine(0, "Probe Disabled");
        setLine(1, "Off in HW Config");
        return;
    }
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t activeIndices[MAX_PROBE_SENSORS];
    uint8_t activeCount = 0;
    for (uint8_t i = 0; i < _sensor->getProbeCount() && activeCount < MAX_PROBE_SENSORS; i++) {
        if (_sensor->isProbeActiveAt(i)) activeIndices[activeCount++] = i;
    }
    char lineBuf[LCD_MAX_COLS + 8];
    if (activeCount == 1) {
        uint8_t idx = activeIndices[0];
        const ProbeSensorConfig* cfg = _hw ? _hw->getProbe(idx) : nullptr;
        char lbl[16];
        formatShortLabel(cfg ? cfg->label : nullptr, "Water Probe", lbl, sizeof(lbl));
        setLine(0, lbl);
        if (_sensor->isProbeFaultAt(idx)) setLine(1, "Temp: ERR");
        else setLinef(1, "Temp: %5.1f\xDF""C", _sensor->getProbeTemperatureAt(idx));
        if (rows >= 4) {
            formatRelaysLine(lineBuf, sizeof(lineBuf), cols, true);
            setLine(2, lineBuf);
            formatWidgetLine("ip", lineBuf, sizeof(lineBuf), cols);
            setLine(3, lineBuf);
        }
        return;
    }
    for (uint8_t r = 0; r < activeCount && r < rows; r++) {
        char key[10];
        snprintf(key, sizeof(key), "probe:%u", (unsigned)activeIndices[r]);
        formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

void LCDManager::renderLuxPage() {
    if (!_sensor || !_sensor->isLuxEnabled()) {
        setLine(0, "Light Disabled");
        setLine(1, "Off in HW Config");
        return;
    }
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t activeIndices[MAX_LIGHT_SENSORS];
    uint8_t activeCount = 0;
    for (uint8_t i = 0; i < _sensor->getLightCount() && activeCount < MAX_LIGHT_SENSORS; i++) {
        if (_sensor->isLightActiveAt(i)) activeIndices[activeCount++] = i;
    }
    char lineBuf[LCD_MAX_COLS + 8];
    if (activeCount == 1) {
        uint8_t idx = activeIndices[0];
        const LightSensorConfig* cfg = _hw ? _hw->getLight(idx) : nullptr;
        char lbl[16];
        formatShortLabel(cfg ? cfg->label : nullptr, "Ambient Light", lbl, sizeof(lbl));
        setLine(0, lbl);
        float lux = _sensor->getLuxAt(idx);
        if (lux >= 100.0f) setLinef(1, "%.0f lx", lux);
        else setLinef(1, "%.1f lx", lux);
        if (rows >= 4) {
            formatRelaysLine(lineBuf, sizeof(lineBuf), cols, true);
            setLine(2, lineBuf);
            formatWidgetLine("ip", lineBuf, sizeof(lineBuf), cols);
            setLine(3, lineBuf);
        }
        return;
    }
    for (uint8_t r = 0; r < activeCount && r < rows; r++) {
        char key[10];
        snprintf(key, sizeof(key), "lux:%u", (unsigned)activeIndices[r]);
        formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

void LCDManager::renderMotionPage() {
    if (!_sensor || !_sensor->isMotionEnabled()) {
        setLine(0, "Motion Disabled");
        setLine(1, "Off in HW Config");
        return;
    }
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t activeIndices[MAX_MOTION_SENSORS];
    uint8_t activeCount = 0;
    for (uint8_t i = 0; i < _sensor->getMotionCount() && activeCount < MAX_MOTION_SENSORS; i++) {
        if (_sensor->isMotionActiveAt(i)) activeIndices[activeCount++] = i;
    }
    char lineBuf[LCD_MAX_COLS + 8];
    if (activeCount == 1) {
        uint8_t idx = activeIndices[0];
        const MotionSensorConfig* cfg = _hw ? _hw->getMotion(idx) : nullptr;
        char lbl[16];
        formatShortLabel(cfg ? cfg->label : nullptr, "Motion Sensor", lbl, sizeof(lbl));
        setLine(0, lbl);
        if (_sensor->isMotionDetectedAt(idx)) {
            setLine(1, "Status: DETECTED");
        } else {
            uint32_t age = _sensor->getMotionAgeSecondsAt(idx);
            if (age == 0 || age >= 86400UL) setLine(1, "Status: Clear");
            else if (age < 60) setLinef(1, "Clear (%lus ago)", (unsigned long)age);
            else if (age < 3600) setLinef(1, "Clear (%lum ago)", (unsigned long)(age / 60));
            else setLinef(1, "Clear (%luh ago)", (unsigned long)(age / 3600));
        }
        if (rows >= 4) {
            formatRelaysLine(lineBuf, sizeof(lineBuf), cols, true);
            setLine(2, lineBuf);
            formatWidgetLine("ip", lineBuf, sizeof(lineBuf), cols);
            setLine(3, lineBuf);
        }
        return;
    }
    for (uint8_t r = 0; r < activeCount && r < rows; r++) {
        char key[12];
        snprintf(key, sizeof(key), "motion:%u", (unsigned)activeIndices[r]);
        formatWidgetLine(key, lineBuf, sizeof(lineBuf), cols);
        setLine(r, lineBuf);
    }
}

// ============================================================================
// Page Renderers
// ============================================================================

void LCDManager::renderSensorPage() {
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;

    // Line 1: T:25.3°C  H:62.1%
    if (!_dhtEnabled) {
        setLine(0, "No Climate Sens ");
    } else if (_dhtFault) {
        setLine(0, _hasHumidity ? "\x08 --.-\xDF""C H:--.-% " : "\x08 Temp: --.-\xDF""C ");
    } else if (!_hasHumidity) {
        setLinef(0, "\x08 Temp: %5.1f\xDF""C ", _temp);
    } else {
        setLinef(0, "\x08%5.1f\xDF""C H:%4.1f%%", _temp, _hum);
    }

    // Line 2: R:■■□■□  MQ:Safe  (in rotate mode, include gas status when enabled)
    char line2[LCD_MAX_COLS + 1];
    if (_numRelays == 0) {
        snprintf(line2, sizeof(line2), "Sensors Active");
    } else {
        snprintf(line2, sizeof(line2), "R:");
        int maxRelayIcons = (int)cols - 2;
        if (maxRelayIcons < 0) maxRelayIcons = 0;
        int shown = (_numRelays < maxRelayIcons) ? _numRelays : maxRelayIcons;
        for (int i = 0; i < shown; i++) {
            line2[2 + i] = _relayStates[i] ? '\x02' : '\x03'; // Custom char ON/OFF
        }
        line2[2 + shown] = '\0';
    }

    if (_displayMode == LCD_MODE_ROTATE && _mq2Enabled && (int)(strlen(line2) + 8) <= (int)cols) {
        // In rotate mode, append gas status alongside relay icons when width permits
        const char* tag = _gasIsSgp40 ? " AQ" : " MQ";
        if (_gasWarming) {
            snprintf(line2 + strlen(line2), sizeof(line2) - strlen(line2), "%s:Warm", tag);
        } else if (_gasAlarm) {
            snprintf(line2 + strlen(line2), sizeof(line2) - strlen(line2), "%s:ALRM", tag);
        } else {
            snprintf(line2 + strlen(line2), sizeof(line2) - strlen(line2), "%s:Safe", tag);
        }
    }

    setLine(1, line2);

    // Extra rows populated automatically on 20x4 I2C displays
    if (_lcdRows >= 4) {
        if (!_mq2Enabled) {
            setLine(2, _gasIsSgp40 ? "SGP40: Disabled" : "Gas: Disabled");
        } else if (_gasWarming) {
            setLinef(2, "\x05 %s:%4d Warming", _gasIsSgp40 ? "VOC" : "Gas", _gasValue);
        } else if (_gasAlarm) {
            setLinef(2, "\x06 %s DANGER! %4d", _gasIsSgp40 ? "VOC" : "GAS", _gasValue);
        } else {
            setLinef(2, "\x07 %s:%4d/%4d OK", _gasIsSgp40 ? "VOC" : "Gas", _gasValue, _gasThreshold);
        }
        setLinef(3, "%-14.14s MQ:%s", _ipAddr.c_str(), _mqttConnected ? "OK" : "--");
    }
}

void LCDManager::renderDHTRelayPage() {
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;

    // Line 1: Plain ASCII temperature and humidity — no custom chars
    if (!_dhtEnabled) {
        setLine(0, "T:--.-C H:--.-% ");
    } else if (_dhtFault) {
        setLine(0, _hasHumidity ? "T:ERR   H:ERR   " : "Temp: ERR       ");
    } else if (!_hasHumidity) {
        setLinef(0, "Temp: %5.1fC    ", _temp);
    } else {
        setLinef(0, "T:%4.1fC H:%4.1f%%", _temp, _hum);
    }

    // Line 2: Relay ON/OFF status
    char line2[LCD_MAX_COLS + 1];
    if (_numRelays == 0) {
        snprintf(line2, sizeof(line2), "No Relays Config");
    } else if ((_numRelays * 3 - 1) <= (int)cols) {
        int pos = 0;
        for (int i = 0; i < _numRelays; i++) {
            if (_relayStates[i]) {
                line2[pos++] = 'O'; line2[pos++] = 'N';
            } else {
                line2[pos++] = 'O'; line2[pos++] = 'F';
            }
            if (i < _numRelays - 1) line2[pos++] = ' ';
        }
        line2[pos] = '\0';
    } else {
        // High channel counts (e.g. 6-8 relays): compact "R:10110101"
        int pos = snprintf(line2, sizeof(line2), "R:");
        for (int i = 0; i < _numRelays && pos < (int)cols; i++) {
            line2[pos++] = _relayStates[i] ? '1' : '0';
        }
        line2[pos] = '\0';
    }
    setLine(1, line2);

    if (_lcdRows >= 4) {
        if (!_mq2Enabled) {
            setLine(2, _gasIsSgp40 ? "SGP40: Disabled" : "Gas: Disabled");
        } else if (_gasAlarm) {
            setLinef(2, "%s ALERT! %d/%d", _gasIsSgp40 ? "VOC" : "GAS", _gasValue, _gasThreshold);
        } else {
            setLinef(2, "%s:%4d/%4d %s", _gasIsSgp40 ? "VOC" : "Gas", _gasValue, _gasThreshold, _gasWarming ? "Warm" : "Safe");
        }
        setLinef(3, "%-14.14s MQ:%s", _ipAddr.c_str(), _mqttConnected ? "OK" : "--");
    }
}



void LCDManager::renderNetworkPage() {
    if (_isAPMode) {
        // The setup credentials must be entered exactly. On a 16x2 LCD the
        // generated SSID (14 chars) and password (15 chars) each fit on their
        // own line, whereas adding "AP:" or "PW:" silently truncates them.
        // Keep this layout stable for recovery: SSID on line 1, password on
        // line 2. The `SmartHome-` / `SmartHome@` prefixes make their role
        // unambiguous without spending display columns on labels.
        setLine(0, _apSSID.c_str());

        // Line 2: WPA2 password when configured, or open setup hint + IP on 16x2 LCD.
        if (_apPass.length() > 0) {
            setLine(1, _apPass.c_str());
        } else {
            setLine(1, "Open 192.168.4.1");
        }
        if (_lcdRows >= 4) {
            setLine(2, "AP IP: 192.168.4.1");
            setLine(3, "Open Browser/App");
        }
        return;
    }

    // Line 1: 12 Jun 2026  Fri
    setLinef(0, "%-12s %3s", _dateStr.c_str(), _dowStr.c_str());

    // Line 2: 192.168.1.100
    setLine(1, _ipAddr.c_str());

    if (_lcdRows >= 4) {
        setLine(2, _mqttConnected ? "MQTT: Connected" : "MQTT: Offline");
        setLinef(3, "Up: %s", _uptimeStr.c_str());
    }
}

void LCDManager::renderGasPage() {
    if (!_mq2Enabled) {
        setLine(0, _gasIsSgp40 ? "SGP40 Disabled  " : "MQ-2 Disabled   ");
        setLine(1, "Off in HW Config");
        return;
    }
    // Line 1: Gas: 125 / 400 (or VOC: 125 / 250)
    setLinef(0, "\x05 %s:%4d/%4d", _gasIsSgp40 ? "VOC" : "Gas", _gasValue, _gasThreshold);

    // Line 2: Status: Safe/DANGER/Warming
    if (_gasWarming) {
        setLine(1, "Status: Warming ");
    } else if (_gasAlarm) {
        setLine(1, "\x06 DANGER! \x06     ");
    } else {
        setLine(1, "\x07 Status: Safe  ");
    }

    if (_lcdRows >= 4) {
        setLinef(2, "Alarm Limit: %d", _gasThreshold);
        setLinef(3, "IP: %s", _ipAddr.c_str());
    }
}

void LCDManager::renderMqttPage() {
    // Line 1: MQTT: Connected
    if (_mqttConnected) {
        setLine(0, "MQTT: Connected ");
    } else {
        setLine(0, "MQTT: Offline   ");
    }

    // Line 2: Up: 2d 14h 32m
    setLinef(1, "Up:%-13s", _uptimeStr.c_str());

    if (_lcdRows >= 4) {
        setLinef(2, "IP: %s", _ipAddr.c_str());
        setLinef(3, "%-12s %3s", _dateStr.c_str(), _dowStr.c_str());
    }
}

void LCDManager::renderGasAlarm() {
    setLine(0, _gasIsSgp40 ? "!!VOC ALERT!!  " : "!!!GAS ALERT!!!");
    setLine(1, "  CHECK NOW!!!  ");
}

void LCDManager::renderTempAlarm() {
    setLine(0, " !!HIGH TEMP!! ");
    setLinef(1, "WARNING: %5.1f\xDF""C", _temp);
}

void LCDManager::renderOTAProgress() {
    setLine(0, " OTA Updating..");
    setLinef(1, " Progress: %3d%%", _otaProgress);
}

void LCDManager::renderWiFiResetPrompt() {
    setLine(0, "  WIFI RESET?   ");
    setLine(1, " Release to Run ");
}

void LCDManager::renderFactoryResetPrompt() {
    setLine(0, " FACTORY RESET? ");
    setLine(1, " Release to Run ");
}

void LCDManager::renderResetCancelledPrompt() {
    setLine(0, "   CANCELLED    ");
    setLine(1, "  Release Now   ");
}

void LCDManager::renderLightResetPrompt() {
    setLine(0, " TOGGLE LIGHT?  ");
    setLine(1, " Release to Run ");
}

// ============================================================================
// Display Update — Character-by-character diff
// ============================================================================
void LCDManager::updateDisplay() {
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    for (uint8_t row = 0; row < rows; row++) {
        for (uint8_t col = 0; col < cols; col++) {
            if (_buffer[row][col] != _prevBuffer[row][col] || _forceRedraw) {
                _lcd.setCursor(col, row);
                _lcd.write(_buffer[row][col]);
                _prevBuffer[row][col] = _buffer[row][col];
            }
        }
    }
}

// ============================================================================
// Buffer Helpers
// ============================================================================
void LCDManager::setLine(uint8_t row, const char* text) {
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    uint8_t cols = (_lcdCols <= LCD_MAX_COLS) ? _lcdCols : LCD_MAX_COLS;
    if (row >= rows) return;
    int len = strlen(text);
    for (int i = 0; i < (int)cols; i++) {
        _buffer[row][i] = (i < len) ? text[i] : ' ';
    }
    _buffer[row][cols] = '\0';
}

void LCDManager::setLinef(uint8_t row, const char* fmt, ...) {
    uint8_t rows = (_lcdRows <= LCD_MAX_ROWS) ? _lcdRows : LCD_MAX_ROWS;
    if (row >= rows) return;
    char temp[LCD_MAX_COLS + 16]; // Extra space for formatting before clamp
    va_list args;
    va_start(args, fmt);
    vsnprintf(temp, sizeof(temp), fmt, args);
    va_end(args);
    setLine(row, temp);
}

// ============================================================================
// Custom Characters
// ============================================================================
void LCDManager::createCustomChars() {
    _lcd.createChar(0, (uint8_t*)CHAR_THERMO);
    _lcd.createChar(1, (uint8_t*)CHAR_DROP);
    _lcd.createChar(2, (uint8_t*)CHAR_ON);
    _lcd.createChar(3, (uint8_t*)CHAR_OFF);
    _lcd.createChar(4, (uint8_t*)CHAR_SIGNAL);
    _lcd.createChar(5, (uint8_t*)CHAR_FLAME);
    _lcd.createChar(6, (uint8_t*)CHAR_WARN);
    _lcd.createChar(7, (uint8_t*)CHAR_CHECK);
}

// ============================================================================
// Load Config
// ============================================================================
void LCDManager::loadConfig() {
    if (!_storage) return;
    JsonDocument doc;
    if (_storage->loadJson(PATH_LCD, doc)) {
        _enabled = doc["enabled"] | DEFAULT_LCD_ENABLED;
        _backlight = doc["backlight"] | DEFAULT_LCD_BACKLIGHT;
        _rotationInterval = constrain(doc["rotation"] | (LCD_DEFAULT_ROTATION / 1000), 3, 30);

        _brightness = constrain(doc["brightness"] | (_backlight ? 100 : 0), 0, 100);
        _autoDim = doc["auto_dim"] | false;
        String ds = doc["dim_start"] | "22:00";
        if (ds.length() < 3 || ds.indexOf(':') < 1) ds = "22:00";
        _dimStartTime = ds;
        String de = doc["dim_end"] | "06:00";
        if (de.length() < 3 || de.indexOf(':') < 1) de = "06:00";
        _dimEndTime = de;
        _dimmedBrightness = constrain(doc["dim_brightness"] | 0, 0, 100);

        // Load display_mode — "rotate", "custom", or "dht_relay"
        // Also handles old "static_sensor" gracefully by falling back to rotate
        if (doc["display_mode"].is<const char*>()) {
            String mode = doc["display_mode"].as<String>();
            if (mode == LCD_MODE_DHT_RELAY) {
                _displayMode = LCD_MODE_DHT_RELAY;
            } else if (mode == LCD_MODE_CUSTOM) {
                _displayMode = LCD_MODE_CUSTOM;
            } else {
                _displayMode = LCD_MODE_ROTATE; // "rotate", "static_sensor", or unknown
            }
        } else {
            _displayMode = LCD_MODE_ROTATE;
        }

        if (doc["pages"].is<JsonArrayConst>()) {
            uint8_t count = 0;
            for (JsonVariantConst v : doc["pages"].as<JsonArrayConst>()) {
                if (!v.is<const char*>()) continue;
                const char* id = v.as<const char*>();
                if (!isKnownPageId(id)) continue;
                bool dup = false;
                for (uint8_t i = 0; i < count; i++) {
                    if (strcmp(_pageOrder[i], id) == 0) {
                        dup = true;
                        break;
                    }
                }
                if (dup || count >= LCD_MAX_CUSTOM_PAGES) continue;
                strncpy(_pageOrder[count], id, LCD_PAGE_ID_LEN - 1);
                _pageOrder[count][LCD_PAGE_ID_LEN - 1] = '\0';
                count++;
            }
            if (count > 0) _pageOrderCount = count;
        }

        if (doc["lines"].is<JsonArrayConst>()) {
            uint8_t r = 0;
            for (JsonVariantConst v : doc["lines"].as<JsonArrayConst>()) {
                if (r >= LCD_MAX_ROWS) break;
                if (v.is<const char*>()) {
                    const char* id = v.as<const char*>();
                    if (isKnownWidgetId(id)) {
                        strncpy(_customLines[r], id, LCD_WIDGET_ID_LEN - 1);
                        _customLines[r][LCD_WIDGET_ID_LEN - 1] = '\0';
                    }
                }
                r++;
            }
        }
    }
}

// ============================================================================
// Apply Backlight Brightness (Handles standard I2C backpack & optional hardware PWM)
// ============================================================================
void LCDManager::applyBacklight(uint8_t percent) {
    if (!_enabled) return;

    // Standard I2C backpack only supports ON/OFF (percent > 0 is ON, percent == 0 is OFF)
    if (percent > 0) {
        _lcd.backlight();
    } else {
        _lcd.noBacklight();
    }

#ifdef PIN_LCD_BACKLIGHT_PWM
    // Optional: write PWM duty cycle for custom dimmed hardware backlight pin
    analogWrite(PIN_LCD_BACKLIGHT_PWM, map(percent, 0, 100, 0, 255));
#endif
}

// ============================================================================
// Check if a time is within a start and end interval (handles crossing midnight)
// ============================================================================
bool LCDManager::isTimeInInterval(int hour, int minute, int startHour, int startMin, int endHour, int endMin) {
    int currentMins = hour * 60 + minute;
    int startMins = startHour * 60 + startMin;
    int endMins = endHour * 60 + endMin;

    if (startMins <= endMins) {
        // Interval within the same day (e.g. 08:00 to 22:00)
        return (currentMins >= startMins && currentMins < endMins);
    } else {
        // Interval crossing midnight (e.g. 22:00 to 06:00)
        return (currentMins >= startMins || currentMins < endMins);
    }
}
