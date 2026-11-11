/*
 * ============================================================================
 * BuzzerManager.cpp — PWM Buzzer Implementation
 * ============================================================================
 */

#if defined(ESP32)
#include <esp_arduino_version.h>
#endif
#include "BuzzerManager.h"
#include "HardwareManager.h"

// Pattern definitions: durations in ms, alternating ON/OFF
// Gas alarm: rapid beep 100ms on, 100ms off
const uint16_t BuzzerManager::PATTERN_GAS[]  = {100, 100};
const uint8_t  BuzzerManager::PATTERN_GAS_LEN = 2;

// Temperature alarm: slow beep 500ms on, 500ms off
const uint16_t BuzzerManager::PATTERN_TEMP[] = {500, 500};
const uint8_t  BuzzerManager::PATTERN_TEMP_LEN = 2;

// Sensor fault: triple beep then pause
const uint16_t BuzzerManager::PATTERN_FAULT[] = {100, 100, 100, 100, 100, 1000};
const uint8_t  BuzzerManager::PATTERN_FAULT_LEN = 6;

// Manual test: single beep
const uint16_t BuzzerManager::PATTERN_MANUAL[] = {500, 0};
const uint8_t  BuzzerManager::PATTERN_MANUAL_LEN = 2;

// Scheduled alarm: melody pattern
const uint16_t BuzzerManager::PATTERN_SCHED[] = {200, 100, 200, 100, 200, 1000};
const uint8_t  BuzzerManager::PATTERN_SCHED_LEN = 6;

// Multi-button prompt chirps (non-repeating)
const uint16_t BuzzerManager::PATTERN_SHORT[]  = {100, 0};
const uint8_t  BuzzerManager::PATTERN_SHORT_LEN = 2;

const uint16_t BuzzerManager::PATTERN_LONG[]   = {500, 0};
const uint8_t  BuzzerManager::PATTERN_LONG_LEN  = 2;

const uint16_t BuzzerManager::PATTERN_CANCEL[] = {100, 50, 100, 0};
const uint8_t  BuzzerManager::PATTERN_CANCEL_LEN = 4;

BuzzerManager::BuzzerManager()
    : _storage(nullptr), _buzzerPin(PIN_BUZZER), _enabled(DEFAULT_BUZZER_ENABLED), _muted(false),
      _alarming(false), _alarmType(0), _volume(BUZZER_DEFAULT_VOLUME),
      _muteStart(0), _toneOn(false), _patternStep(0), _stepStart(0) {}

void BuzzerManager::begin(StorageManager& storage) {
    _storage = &storage;
    _buzzerPin = PIN_BUZZER;

    // Setup buzzer PWM
#if defined(ESP8266)
    pinMode(_buzzerPin, OUTPUT);
    analogWriteFreq(BUZZER_DEFAULT_FREQ);
    analogWrite(_buzzerPin, 0);
#elif ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcAttach(_buzzerPin, BUZZER_DEFAULT_FREQ, BUZZER_LEDC_RESOLUTION);
    ledcWrite(_buzzerPin, 0); // Start silent
#else
    ledcSetup(BUZZER_LEDC_CHANNEL, BUZZER_DEFAULT_FREQ, BUZZER_LEDC_RESOLUTION);
    ledcAttachPin(_buzzerPin, BUZZER_LEDC_CHANNEL);
    ledcWrite(BUZZER_LEDC_CHANNEL, 0); // Start silent
#endif

    loadConfig();

    Serial.printf("[Buzzer] Ready on GPIO %d, enabled: %s, volume: %d\n",
                  _buzzerPin, _enabled ? "yes" : "no", _volume);
}

void BuzzerManager::begin(StorageManager& storage, HardwareManager& hw) {
    _storage = &storage;
    _enabled = hw.isBuzzerEnabled();
    _buzzerPin = hw.getBuzzerPin();

    if (_enabled && _buzzerPin != PIN_UNUSED) {
#if defined(ESP8266)
        pinMode(_buzzerPin, OUTPUT);
        analogWriteFreq(BUZZER_DEFAULT_FREQ);
        analogWrite(_buzzerPin, 0);
#elif ESP_ARDUINO_VERSION_MAJOR >= 3
        ledcAttach(_buzzerPin, BUZZER_DEFAULT_FREQ, BUZZER_LEDC_RESOLUTION);
        ledcWrite(_buzzerPin, 0);
#else
        ledcSetup(BUZZER_LEDC_CHANNEL, BUZZER_DEFAULT_FREQ, BUZZER_LEDC_RESOLUTION);
        ledcAttachPin(_buzzerPin, BUZZER_LEDC_CHANNEL);
        ledcWrite(BUZZER_LEDC_CHANNEL, 0);
#endif
        Serial.printf("[Buzzer] Ready on GPIO %d, enabled: yes\n", _buzzerPin);
    } else {
        _enabled = false;
        Serial.println(F("[Buzzer] Disabled in hardware profile"));
    }

    loadConfig();
}

void BuzzerManager::loop() {
    unsigned long now = millis();

    // Auto-unmute check
    if (_muted && (now - _muteStart >= BUZZER_MUTE_DURATION)) {
        _muted = false;
        Serial.println(F("[Buzzer] Auto-unmuted"));
    }

    // Drive pattern state machine
    if (!_alarming) return;

    const uint16_t* pattern = getPattern(_alarmType);
    uint8_t patLen = getPatternLen(_alarmType);
    if (!pattern || patLen == 0) return;

    uint16_t stepDuration = pattern[_patternStep];

    // Step duration of 0 means end (for non-repeating patterns)
    if (stepDuration == 0) {
        stopAlarm();
        return;
    }

    if (now - _stepStart >= stepDuration) {
        // Advance to next step
        _patternStep++;

        // Check for pattern end
        if (_patternStep >= patLen) {
            if (doesPatternRepeat(_alarmType)) {
                _patternStep = 0; // Loop
            } else {
                stopAlarm();
                return;
            }
        }

        _stepStart = now;

        // Even steps = tone ON, odd steps = tone OFF
        if (_patternStep % 2 == 0) {
            toneOn();
        } else {
            toneOff();
        }
    }
}

void BuzzerManager::startAlarm(uint8_t type) {
    if (!_enabled) return;

    _alarmType = type;
    _alarming = true;
    _patternStep = 0;
    _stepStart = millis();

    // Start with tone ON
    toneOn();

    Serial.printf("[Buzzer] Alarm started: type %d\n", type);
}

void BuzzerManager::stopAlarm() {
    _alarming = false;
    _patternStep = 0;
    toneOff();
}

void BuzzerManager::testBeep() {
    startAlarm(BUZZER_ALARM_MANUAL);
}

void BuzzerManager::beepShort()  { startAlarm(BUZZER_ALARM_SHORT); }
void BuzzerManager::beepLong()   { startAlarm(BUZZER_ALARM_LONG); }
void BuzzerManager::beepCancel() { startAlarm(BUZZER_ALARM_CANCEL); }

void BuzzerManager::mute() {
    _muted = true;
    _muteStart = millis();
    toneOff(); // Silence immediately
    Serial.println(F("[Buzzer] Muted for 5 minutes"));
}

void BuzzerManager::unmute() {
    _muted = false;
    Serial.println(F("[Buzzer] Unmuted"));
}

bool BuzzerManager::isMuted()      { return _muted; }
bool BuzzerManager::isAlarming()   { return _alarming; }
bool BuzzerManager::isEnabled()    { return _enabled; }
uint8_t BuzzerManager::getVolume() { return _volume; }
uint8_t BuzzerManager::getActiveAlarmType() { return _alarmType; }

void BuzzerManager::setEnabled(bool enabled) {
    _enabled = enabled;
    if (!_enabled) stopAlarm();
    saveConfig();
}

void BuzzerManager::setVolume(uint8_t vol) {
    _volume = vol;
    saveConfig();
}

void BuzzerManager::saveConfig() {
    if (!_storage) return;
    JsonDocument doc;
    doc["enabled"] = _enabled;
    doc["volume"] = _volume;
    _storage->saveJson(PATH_BUZZER, doc);
}

// ============================================================================
// Private
// ============================================================================

void BuzzerManager::toneOn() {
    if (_muted || !_enabled || _buzzerPin == PIN_UNUSED) return;
#if defined(ESP8266)
    analogWriteFreq(BUZZER_DEFAULT_FREQ);
    analogWrite(_buzzerPin, map(_volume, 0, 255, 0, 1023));
#elif ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcWriteTone(_buzzerPin, BUZZER_DEFAULT_FREQ);
    ledcWrite(_buzzerPin, _volume);
#else
    ledcWriteTone(BUZZER_LEDC_CHANNEL, BUZZER_DEFAULT_FREQ);
    ledcWrite(BUZZER_LEDC_CHANNEL, _volume);
#endif
    _toneOn = true;
}

void BuzzerManager::toneOff() {
    if (_buzzerPin == PIN_UNUSED) return;
#if defined(ESP8266)
    analogWrite(_buzzerPin, 0);
    digitalWrite(_buzzerPin, LOW);
#elif ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcWriteTone(_buzzerPin, 0);
    ledcWrite(_buzzerPin, 0);
#else
    ledcWriteTone(BUZZER_LEDC_CHANNEL, 0);
    ledcWrite(BUZZER_LEDC_CHANNEL, 0);
#endif
    _toneOn = false;
}

void BuzzerManager::loadConfig() {
    if (!_storage) return;
    JsonDocument doc;
    if (_storage->loadJson(PATH_BUZZER, doc)) {
        _enabled = doc["enabled"] | DEFAULT_BUZZER_ENABLED;
        _volume = doc["volume"] | BUZZER_DEFAULT_VOLUME;
    }
}

const uint16_t* BuzzerManager::getPattern(uint8_t type) {
    switch (type) {
        case BUZZER_ALARM_GAS:       return PATTERN_GAS;
        case BUZZER_ALARM_TEMP:      return PATTERN_TEMP;
        case BUZZER_ALARM_FAULT:     return PATTERN_FAULT;
        case BUZZER_ALARM_MANUAL:    return PATTERN_MANUAL;
        case BUZZER_ALARM_SCHEDULED: return PATTERN_SCHED;
        case BUZZER_ALARM_SHORT:     return PATTERN_SHORT;
        case BUZZER_ALARM_LONG:      return PATTERN_LONG;
        case BUZZER_ALARM_CANCEL:    return PATTERN_CANCEL;
        default:                     return PATTERN_GAS;
    }
}

uint8_t BuzzerManager::getPatternLen(uint8_t type) {
    switch (type) {
        case BUZZER_ALARM_GAS:       return PATTERN_GAS_LEN;
        case BUZZER_ALARM_TEMP:      return PATTERN_TEMP_LEN;
        case BUZZER_ALARM_FAULT:     return PATTERN_FAULT_LEN;
        case BUZZER_ALARM_MANUAL:    return PATTERN_MANUAL_LEN;
        case BUZZER_ALARM_SCHEDULED: return PATTERN_SCHED_LEN;
        case BUZZER_ALARM_SHORT:     return PATTERN_SHORT_LEN;
        case BUZZER_ALARM_LONG:      return PATTERN_LONG_LEN;
        case BUZZER_ALARM_CANCEL:    return PATTERN_CANCEL_LEN;
        default:                     return PATTERN_GAS_LEN;
    }
}

bool BuzzerManager::doesPatternRepeat(uint8_t type) {
    return (type != BUZZER_ALARM_MANUAL && 
            type != BUZZER_ALARM_SHORT && 
            type != BUZZER_ALARM_LONG && 
            type != BUZZER_ALARM_CANCEL);
}
