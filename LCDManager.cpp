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
      _storage(nullptr), _time(nullptr), _enabled(DEFAULT_LCD_ENABLED),
      _hwLcdAllowed(true), _sdaPin(PIN_I2C_SDA), _sclPin(PIN_I2C_SCL), _i2cAddr(LCD_I2C_ADDR),
      _lcdCols(LCD_COLS), _lcdRows(LCD_ROWS),
      _backlight(DEFAULT_LCD_BACKLIGHT),
      _displayMode(LCD_MODE_ROTATE),
      _rotationInterval(LCD_DEFAULT_ROTATION / 1000),
      _brightness(100), _autoDim(false),
      _dimStartTime("22:00"), _dimEndTime("06:00"),
      _dimmedBrightness(0), _currentAppliedBrightness(100),
      _forceRedraw(true), _currentPage(0),
      _lastPageChange(0), _lastUpdate(0),
      _lastUserInteraction(0),
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
        if (_currentPage != LCD_PAGE_NETWORK) {
            _currentPage = LCD_PAGE_NETWORK;
            _forceRedraw = true;
        }
        _lastPageChange = now;
    }

    // Auto page rotation (only in normal Wi-Fi operation, rotate mode, and
    // not during an alarm). AP mode deliberately remains pinned above.
    if (!_isAPMode && _alarmType == LCD_ALARM_NONE && _displayMode == LCD_MODE_ROTATE && _rotationInterval > 0) {
        if (now - _lastPageChange >= (unsigned long)_rotationInterval * 1000UL) {
            _currentPage = (_currentPage + 1) % LCD_NUM_PAGES;
            _lastPageChange = now;
            _forceRedraw = true;
        }
    }

    // Check idle timeout in DHT+Relays mode to revert to page 0 after 5s
    if (_displayMode == LCD_MODE_DHT_RELAY && _currentPage != 0) {
        if (now - _lastUserInteraction >= 5000) {
            _currentPage = 0;
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
    } else {
        // Normal display rendering
        switch (_currentPage) {
            case LCD_PAGE_SENSOR:  
                if (_displayMode == LCD_MODE_DHT_RELAY) {
                    renderDHTRelayPage(); 
                } else {
                    renderSensorPage(); 
                }
                break;
            case LCD_PAGE_NETWORK: renderNetworkPage(); break;
            case LCD_PAGE_GAS:     renderGasPage(); break;
            case LCD_PAGE_MQTT:    renderMqttPage(); break;
        }
    }

    // Diff-based display update
    updateDisplay();
    _forceRedraw = false;
}

// ============================================================================
// Page Control
// ============================================================================
void LCDManager::nextPage() {
    _currentPage = (_currentPage + 1) % LCD_NUM_PAGES;
    _lastPageChange = millis();
    _lastUserInteraction = millis();
    _forceRedraw = true;
}

void LCDManager::setPage(uint8_t page) {
    if (page < LCD_NUM_PAGES) {
        _currentPage = page;
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
    if (mode == LCD_MODE_DHT_RELAY || mode == LCD_MODE_ROTATE) {
        _displayMode = mode;
    } else {
        _displayMode = LCD_MODE_ROTATE; // Unknown mode — safe default
    }
    _currentPage = 0;
    _lastPageChange = millis();
    _forceRedraw = true;
    saveConfig();
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

        // Line 2: full WPA2 password. Do not prepend a label here.
        if (_apPass.length() > 0) {
            setLine(1, _apPass.c_str());
        } else {
            setLine(1, "IP:192.168.4.1");
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

        // Load display_mode — "rotate" or "dht_relay"
        // Also handles old "static_sensor" gracefully by falling back to rotate
        if (doc["display_mode"].is<const char*>()) {
            String mode = doc["display_mode"].as<String>();
            if (mode == LCD_MODE_DHT_RELAY) {
                _displayMode = LCD_MODE_DHT_RELAY;
            } else {
                _displayMode = LCD_MODE_ROTATE; // "rotate", "static_sensor", or unknown
            }
        } else {
            _displayMode = LCD_MODE_ROTATE;
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
