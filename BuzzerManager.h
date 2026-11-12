/*
 * ============================================================================
 * BuzzerManager.h — PWM Buzzer with Non-blocking Beep Patterns
 * ============================================================================
 */

#ifndef BUZZER_MANAGER_H
#define BUZZER_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

class HardwareManager;

// Alarm types
#define BUZZER_ALARM_GAS       0  // Rapid beep
#define BUZZER_ALARM_TEMP      1  // Slow beep
#define BUZZER_ALARM_FAULT     2  // Triple beep
#define BUZZER_ALARM_MANUAL    3  // Single beep
#define BUZZER_ALARM_SCHEDULED 4  // Melody pattern
#define BUZZER_ALARM_SHORT     5  // Short beep (100ms)
#define BUZZER_ALARM_LONG      6  // Long beep (500ms)
#define BUZZER_ALARM_CANCEL    7  // Double beep

class BuzzerManager {
public:
    BuzzerManager();

    void begin(StorageManager& storage);
    void begin(StorageManager& storage, HardwareManager& hw);
    void loop();

    void startAlarm(uint8_t type);
    void stopAlarm();
    void testBeep();
    void mute();
    void unmute();
    void beepShort();
    void beepLong();
    void beepCancel();

    bool isMuted();
    bool isAlarming();
    bool isEnabled();
    bool isHardwareAllowed() const { return _hwAllowed; }
    void setEnabled(bool enabled);
    uint8_t getVolume();
    void setVolume(uint8_t vol);
    uint8_t getActiveAlarmType();
    void saveConfig();

private:
    StorageManager* _storage;
    uint8_t _buzzerPin;
    bool _hwAllowed;
    bool _enabled;
    bool _muted;
    bool _alarming;
    uint8_t _alarmType;
    uint8_t _volume;

    // Mute timing
    unsigned long _muteStart;

    // Pattern state machine
    bool _toneOn;
    uint8_t _patternStep;
    unsigned long _stepStart;

    // Pattern definitions: arrays of {onMs, offMs, ...} terminated by 0
    // Gas: rapid 100/100
    static const uint16_t PATTERN_GAS[];
    static const uint8_t  PATTERN_GAS_LEN;
    // Temp: slow 500/500
    static const uint16_t PATTERN_TEMP[];
    static const uint8_t  PATTERN_TEMP_LEN;
    // Fault: triple beep 100/100/100/100/100/1000
    static const uint16_t PATTERN_FAULT[];
    static const uint8_t  PATTERN_FAULT_LEN;
    // Manual: single 500
    static const uint16_t PATTERN_MANUAL[];
    static const uint8_t  PATTERN_MANUAL_LEN;
    // Scheduled: melody
    static const uint16_t PATTERN_SCHED[];
    static const uint8_t  PATTERN_SCHED_LEN;
    
    // Multi-button prompt chirps
    static const uint16_t PATTERN_SHORT[];
    static const uint8_t  PATTERN_SHORT_LEN;
    static const uint16_t PATTERN_LONG[];
    static const uint8_t  PATTERN_LONG_LEN;
    static const uint16_t PATTERN_CANCEL[];
    static const uint8_t  PATTERN_CANCEL_LEN;

    const uint16_t* getPattern(uint8_t type);
    uint8_t getPatternLen(uint8_t type);
    bool doesPatternRepeat(uint8_t type);

    void toneOn();
    void toneOff();
    void loadConfig();
};

#endif // BUZZER_MANAGER_H
