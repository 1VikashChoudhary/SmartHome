/*
 * ============================================================================
 * LCDManager.cpp — Non-blocking LCD1602 Implementation
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
      _temp(0), _hum(0), _dhtFault(false),
      _gasValue(0), _gasThreshold(MQ2_DEFAULT_THRESHOLD),
      _gasAlarm(false), _gasWarming(true),
      _mqttConnected(false),
      _isAPMode(false), _apSSID(""), _apPass(""),
      _numRelays(NUM_RELAYS) {
    memset(_buffer, ' ', sizeof(_buffer));
    memset(_prevBuffer, 0, sizeof(_prevBuffer)); // Different from spaces to force first draw
    memset(_relayStates, 0, sizeof(_relayStates));
    for (int r = 0; r < LCD_ROWS; r++) {
        _buffer[r][LCD_COLS] = '\0';
        _prevBuffer[r][LCD_COLS] = '\0';
    }
}

void LCDManager::begin(StorageManager& storage, TimeManager& time) {
    _storage = &storage;
    _time = &time;
    _numRelays = NUM_RELAYS;
    loadConfig();

    if (!_enabled) {
        Serial.println(F("[LCD] Disabled in config"));
        return;
    }

#ifdef PIN_LCD_BACKLIGHT_PWM
    pinMode(PIN_LCD_BACKLIGHT_PWM, OUTPUT);
#endif

    // Initialize I2C bus
    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);

    // Test if LCD is physically present on the I2C bus
    Wire.beginTransmission(LCD_I2C_ADDR);
    byte error = Wire.endTransmission();
    if (error != 0) {
        Serial.printf("[LCD] LCD not detected at I2C address 0x%02X (error: %d). Disabling LCD.\n", LCD_I2C_ADDR, error);
        _enabled = false;
        return;
    }

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

    Serial.printf("[LCD] Ready (addr: 0x%02X, rotation: %ds, brightness: %d%%)\n",
                  LCD_I2C_ADDR, _rotationInterval, _brightness);
}

void LCDManager::begin(StorageManager& storage, TimeManager& time, HardwareManager& hw) {
    _storage = &storage;
    _time = &time;
    _numRelays = hw.getNumRelays();
    if (_numRelays > MAX_RELAYS) _numRelays = MAX_RELAYS;
    loadConfig();

    if (!_enabled || !hw.isLcdEnabled()) {
        _enabled = false;
        Serial.println(F("[LCD] Disabled in hardware profile"));
        return;
    }

#ifdef PIN_LCD_BACKLIGHT_PWM
    pinMode(PIN_LCD_BACKLIGHT_PWM, OUTPUT);
#endif

    uint8_t sda = hw.getI2cSdaPin();
    uint8_t scl = hw.getI2cSclPin();
    uint8_t addr = hw.getLcdI2cAddr();

    // Initialize I2C bus with hardware profile pins
    Wire.begin(sda, scl);

    Wire.beginTransmission(addr);
    byte error = Wire.endTransmission();
    if (error != 0) {
        Serial.printf("[LCD] LCD not detected at I2C 0x%02X (SDA:%d, SCL:%d, error: %d). Disabling LCD.\n",
                      addr, sda, scl, error);
        _enabled = false;
        return;
    }

    _lcd = LiquidCrystal_I2C(addr, hw.getLcdCols(), hw.getLcdRows());
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

    Serial.printf("[LCD] Ready via Hardware Profile (addr: 0x%02X, SDA:%d, SCL:%d, %d relays)\n",
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

    // Direct write for boot screen (one-time, before loop starts)
    _lcd.clear();
    _lcd.setCursor(0, 0);

    // Center device name
    int nameLen = strlen(deviceName);
    int pad = (LCD_COLS - nameLen) / 2;
    for (int i = 0; i < pad; i++) _lcd.print(' ');
    _lcd.print(deviceName);

    _lcd.setCursor(0, 1);
    char verLine[LCD_COLS + 1];
    snprintf(verLine, sizeof(verLine), "  v%s  Ready  ", FW_VERSION);
    _lcd.print(verLine);

    // Mark prev buffer as unknown to force full redraw on first loop
    memset(_prevBuffer, 0xFF, sizeof(_prevBuffer));
    for (int r = 0; r < LCD_ROWS; r++) _prevBuffer[r][LCD_COLS] = '\0';
}

// ============================================================================
// Settings
// ============================================================================
bool LCDManager::isEnabled() { return _enabled; }

void LCDManager::setEnabled(bool enabled) {
    _enabled = enabled;
    if (_enabled) {
        Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
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
    _dimStartTime = time;
    saveConfig();
}

void LCDManager::setDimEndTime(const String& time) {
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
void LCDManager::updateSensorData(float temp, float hum, bool dhtFault) {
    _temp = temp; _hum = hum; _dhtFault = dhtFault;
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

void LCDManager::updateGasData(int gasValue, int threshold, bool alarm, bool warming) {
    _gasValue = gasValue; _gasThreshold = threshold;
    _gasAlarm = alarm; _gasWarming = warming;
}

void LCDManager::updateMqttStatus(bool connected, const String& uptime) {
    _mqttConnected = connected; _uptimeStr = uptime;
}

// ============================================================================
// Page Renderers
// ============================================================================

void LCDManager::renderSensorPage() {
    // Line 1: T:25.3°C  H:62.1%
    if (_dhtFault) {
        setLine(0, "\x08 --.-\xDF""C H:--.-% ");
    } else {
        setLinef(0, "\x08%5.1f\xDF""C H:%4.1f%%", _temp, _hum);
    }

    // Line 2: R:■■□■□  MQ:Safe  (in rotate mode, include gas status)
    char line2[LCD_COLS + 1];
    if (_numRelays == 0) {
        snprintf(line2, sizeof(line2), "Sensors Active");
    } else {
        snprintf(line2, sizeof(line2), "R:");
        for (int i = 0; i < _numRelays; i++) {
            line2[2 + i] = _relayStates[i] ? '\x02' : '\x03'; // Custom char ON/OFF
        }
        line2[2 + _numRelays] = '\0';
    }

    if (_displayMode == LCD_MODE_ROTATE && _numRelays <= 5) {
        // In rotate mode, append gas status alongside relay icons
        if (_gasWarming) {
            strncat(line2, " MQ:Warm", sizeof(line2) - strlen(line2) - 1);
        } else if (_gasAlarm) {
            strncat(line2, " MQ:ALRM", sizeof(line2) - strlen(line2) - 1);
        } else {
            strncat(line2, " MQ:Safe", sizeof(line2) - strlen(line2) - 1);
        }
    }

    // Pad to LCD_COLS
    int len = strlen(line2);
    while (len < LCD_COLS) line2[len++] = ' ';
    line2[LCD_COLS] = '\0';
    setLine(1, line2);
}

void LCDManager::renderDHTRelayPage() {
    // Line 1: Plain ASCII temperature and humidity — no custom chars
    if (_dhtFault) {
        setLine(0, "T:ERR   H:ERR   ");
    } else {
        setLinef(0, "T:%4.1fC H:%4.1f%%", _temp, _hum);
    }

    // Line 2: Relay ON/OFF status
    char line2[LCD_COLS + 1];
    if (_numRelays == 0) {
        snprintf(line2, sizeof(line2), "No Relays Config");
    } else if (_numRelays <= 5) {
        int pos = 0;
        for (int i = 0; i < _numRelays; i++) {
            if (_relayStates[i]) {
                line2[pos++] = 'O'; line2[pos++] = 'N';
            } else {
                line2[pos++] = 'O'; line2[pos++] = 'F';
            }
            if (i < _numRelays - 1) line2[pos++] = ' ';
        }
        while (pos < LCD_COLS) line2[pos++] = ' ';
        line2[LCD_COLS] = '\0';
    } else {
        // 6 to 8 relays: "R: 1 0 1 1 0 1 0 1"
        int pos = snprintf(line2, sizeof(line2), "R:");
        for (int i = 0; i < _numRelays && pos < LCD_COLS; i++) {
            line2[pos++] = ' ';
            line2[pos++] = _relayStates[i] ? '1' : '0';
        }
        while (pos < LCD_COLS) line2[pos++] = ' ';
        line2[LCD_COLS] = '\0';
    }
    setLine(1, line2);
}



void LCDManager::renderNetworkPage() {
    if (_isAPMode) {
        // The setup credentials must be entered exactly. On a 16x2 LCD the
        // generated SSID (14 chars) and password (15 chars) each fit on their
        // own line, whereas adding "AP:" or "PW:" silently truncates them.
        // Keep this layout stable for recovery: SSID on line 1, password on
        // line 2. The `SmartHome-` / `SmartHome@` prefixes make their role
        // unambiguous without spending display columns on labels.
        char line1[LCD_COLS + 1];
        snprintf(line1, sizeof(line1), "%-16.16s", _apSSID.c_str());
        setLine(0, line1);

        // Line 2: full WPA2 password. Do not prepend a label here.
        char line2[LCD_COLS + 1];
        if (_apPass.length() > 0) {
            snprintf(line2, sizeof(line2), "%-16.16s", _apPass.c_str());
        } else {
            snprintf(line2, sizeof(line2), "IP:192.168.4.1   ");
        }
        setLine(1, line2);
        return;
    }

    // Line 1: 12 Jun 2026  Fri
    char line1[LCD_COLS + 1];
    snprintf(line1, sizeof(line1), "%-12s %3s", _dateStr.c_str(), _dowStr.c_str());
    setLine(0, line1);

    // Line 2: 192.168.1.100
    setLinef(1, "%-16s", _ipAddr.c_str());
}

void LCDManager::renderGasPage() {
    // Line 1: Gas: 125 / 400
    setLinef(0, "\x05 Gas:%4d/%4d", _gasValue, _gasThreshold);

    // Line 2: Status: Safe/DANGER/Warming
    if (_gasWarming) {
        setLine(1, "Status: Warming ");
    } else if (_gasAlarm) {
        setLine(1, "\x06 DANGER! \x06     ");
    } else {
        setLine(1, "\x07 Status: Safe  ");
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
}

void LCDManager::renderGasAlarm() {
    setLine(0, "!!!GAS ALERT!!!");
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
    for (uint8_t row = 0; row < LCD_ROWS; row++) {
        for (uint8_t col = 0; col < LCD_COLS; col++) {
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
    if (row >= LCD_ROWS) return;
    int len = strlen(text);
    for (int i = 0; i < LCD_COLS; i++) {
        _buffer[row][i] = (i < len) ? text[i] : ' ';
    }
    _buffer[row][LCD_COLS] = '\0';
}

void LCDManager::setLinef(uint8_t row, const char* fmt, ...) {
    if (row >= LCD_ROWS) return;
    char temp[LCD_COLS + 8]; // Extra space for safety
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
        _rotationInterval = doc["rotation"] | (LCD_DEFAULT_ROTATION / 1000);

        _brightness = doc["brightness"] | (_backlight ? 100 : 0);
        _autoDim = doc["auto_dim"] | false;
        _dimStartTime = doc["dim_start"].as<String>() != "" ? doc["dim_start"].as<String>() : "22:00";
        _dimEndTime = doc["dim_end"].as<String>() != "" ? doc["dim_end"].as<String>() : "06:00";
        _dimmedBrightness = doc["dim_brightness"] | 0;

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
