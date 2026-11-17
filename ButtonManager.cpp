/*
 * ============================================================================
 * ButtonManager.cpp — Debounced Multi-Button & Dynamic Wall Switches
 * ============================================================================
 */

#include "ButtonManager.h"

ButtonManager::ButtonManager()
    : _numRelays(NUM_RELAYS), _wallSwitchCb(nullptr), _wallSwitchActionCb(nullptr),
      _lockoutCb(nullptr), _multiCb(nullptr) {
    for (uint8_t i = 0; i < MAX_RELAYS; i++) {
        _switches[i].pin = (i < NUM_RELAYS) ? SWITCH_PINS[i] : PIN_UNUSED;
        _switches[i].mode = SWITCH_MODE_TOGGLE;
        _switches[i].lastReading = HIGH;
        _switches[i].stableState = HIGH;
        _switches[i].lastChangeTime = 0;
    }
    memset(&_btnMulti, 0, sizeof(_btnMulti));
    _btnMulti.pin = PIN_UNUSED;
    _btnMulti.enabled = false;
}

void ButtonManager::begin() {
    if (PIN_BTN_MULTI != PIN_UNUSED) {
        initButton(_btnMulti, PIN_BTN_MULTI);
        Serial.println(F("[Button] Multi-button initialized (legacy pin)"));
    } else {
        _btnMulti.enabled = false;
        _btnMulti.pin = PIN_UNUSED;
        Serial.println(F("[Button] Multi-button disabled (legacy PIN_UNUSED)"));
    }
}

void ButtonManager::begin(HardwareManager& hw) {
    uint8_t btnPin = hw.getBtnMultiPin();
    if (btnPin != PIN_UNUSED) {
        initButton(_btnMulti, btnPin);
        SERIAL_PRINTF("[Button] Multi-button initialized on GPIO %d\n", btnPin);
    } else {
        _btnMulti.enabled = false;
        Serial.println(F("[Button] Multi-button disabled in hardware profile"));
    }
}

void ButtonManager::loop() {
    processSwitches();
    if (_btnMulti.enabled) {
        processButton(_btnMulti, _multiCb);
    }
}

void ButtonManager::initWallSwitchPins() {
    unsigned long now = millis();
    _numRelays = NUM_RELAYS;

    for (uint8_t i = 0; i < _numRelays; i++) {
        _switches[i].pin = (i < NUM_RELAYS) ? SWITCH_PINS[i] : PIN_UNUSED;
        _switches[i].mode = SWITCH_MODE_TOGGLE;
        if (_switches[i].pin != PIN_UNUSED) {
#if defined(ESP8266)
            if (_switches[i].pin == 16) pinMode(_switches[i].pin, INPUT);
            else pinMode(_switches[i].pin, INPUT_PULLUP);
#elif defined(ESP32)
            if (_switches[i].pin >= 34 && _switches[i].pin <= 39) pinMode(_switches[i].pin, INPUT);
            else pinMode(_switches[i].pin, INPUT_PULLUP);
#else
            pinMode(_switches[i].pin, INPUT_PULLUP);
#endif
            bool currentReading = digitalRead(_switches[i].pin);
            _switches[i].lastReading = currentReading;
            _switches[i].stableState = currentReading;
            _switches[i].lastChangeTime = now;
        }
    }
    Serial.println(F("[Button] Wall switch polling initialized (legacy)"));
}

void ButtonManager::initWallSwitchPins(HardwareManager& hw) {
    unsigned long now = millis();
    _numRelays = hw.getNumRelays();
    if (_numRelays > MAX_RELAYS) _numRelays = MAX_RELAYS;

    for (uint8_t i = 0; i < _numRelays; i++) {
        uint8_t pin = hw.getSwitchPin(i);
        _switches[i].pin = pin;
        _switches[i].mode = hw.getSwitchMode(i);

        if (pin != PIN_UNUSED) {
#if defined(ESP8266)
            if (pin == 16) {
                pinMode(pin, INPUT); // ESP8266 GPIO 16 has no pullup (external pullup)
            } else {
                pinMode(pin, INPUT_PULLUP);
            }
#else
            if (pin >= 34 && pin <= 39) {
                pinMode(pin, INPUT); // ESP32 GPIO 34-39 are input-only and require external pull-up
            } else {
                pinMode(pin, INPUT_PULLUP);
            }
#endif
            bool currentReading = digitalRead(pin);
            _switches[i].lastReading = currentReading;
            _switches[i].stableState = currentReading;
            _switches[i].lastChangeTime = now;
            SERIAL_PRINTF("[Button] Switch %d: GPIO %d (mode %d)\n", i + 1, pin, (int)_switches[i].mode);
        } else {
            SERIAL_PRINTF("[Button] Switch %d: Disabled\n", i + 1);
        }
    }
    SERIAL_PRINTF("[Button] Wall switch polling initialized (%d channels)\n", _numRelays);
}

void ButtonManager::setWallSwitchCallback(void (*cb)(uint8_t)) {
    _wallSwitchCb = cb;
}

void ButtonManager::setWallSwitchActionCallback(void (*cb)(uint8_t, uint8_t)) {
    _wallSwitchActionCb = cb;
}

void ButtonManager::setLockoutCallback(bool (*cb)()) {
    _lockoutCb = cb;
}

void ButtonManager::setMultiButtonCallback(void (*cb)(uint8_t)) {
    _multiCb = cb;
}

void ButtonManager::processSwitches() {
    unsigned long now = millis();

    // If relay lockout is active, reset debounce baselines to avoid EMI false triggers
    if (_lockoutCb && _lockoutCb()) {
        for (uint8_t i = 0; i < _numRelays; i++) {
            if (_switches[i].pin != PIN_UNUSED) {
                _switches[i].lastReading = digitalRead(_switches[i].pin);
                _switches[i].lastChangeTime = now;
            }
        }
        return;
    }

    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_switches[i].pin == PIN_UNUSED) continue;

        bool reading = digitalRead(_switches[i].pin);

        if (reading != _switches[i].lastReading) {
            _switches[i].lastChangeTime = now;
            _switches[i].lastReading = reading;
        }

        if ((now - _switches[i].lastChangeTime) >= SWITCH_DEBOUNCE_MS) {
            if (reading != _switches[i].stableState) {
                _switches[i].stableState = reading;

                SwitchMode mode = _switches[i].mode;
                if (mode == SWITCH_MODE_DETACHED) {
                    // Detached switch: don't control relay
                    continue;
                }

                uint8_t action = SWITCH_ACTION_TOGGLE;
                bool shouldFire = true;

                if (mode == SWITCH_MODE_PUSHBUTTON) {
                    // Momentary push button: only trigger on falling edge (press)
                    if (reading == LOW) {
                        action = SWITCH_ACTION_TOGGLE;
                    } else {
                        shouldFire = false;
                    }
                } else if (mode == SWITCH_MODE_FOLLOW) {
                    // Follow mode: Closed (LOW) = ON, Open (HIGH) = OFF
                    action = (reading == LOW) ? SWITCH_ACTION_ON : SWITCH_ACTION_OFF;
                } else if (mode == SWITCH_MODE_FOLLOW_INV) {
                    // Follow inverted: Closed (LOW) = OFF, Open (HIGH) = ON
                    action = (reading == LOW) ? SWITCH_ACTION_OFF : SWITCH_ACTION_ON;
                } else {
                    // Default SWITCH_MODE_TOGGLE
                    action = SWITCH_ACTION_TOGGLE;
                }

                if (shouldFire) {
                    if (_wallSwitchActionCb) {
                        _wallSwitchActionCb(i, action);
                    } else if (_wallSwitchCb) {
                        _wallSwitchCb(i);
                    }
                    SERIAL_PRINTF("[Button] Wall switch %d changed → pin=%s, action=%d\n",
                                  i + 1, reading == LOW ? "LOW" : "HIGH", action);
                }
            }
        }
    }
}

void ButtonManager::initButton(ButtonState& btn, uint8_t pin) {
    if (pin == PIN_UNUSED) {
        btn.pin = PIN_UNUSED;
        btn.enabled = false;
        return;
    }
    btn.pin = pin;
    btn.enabled = true;
#if defined(ESP8266)
    if (pin == 16) {
        pinMode(pin, INPUT); // ESP8266 GPIO 16 has no internal pullup
    } else {
        pinMode(pin, INPUT_PULLUP);
    }
#elif defined(ESP32)
    if (pin >= 34 && pin <= 39) {
        pinMode(pin, INPUT); // ESP32 GPIO 34-39 are input-only
    } else {
        pinMode(pin, INPUT_PULLUP);
    }
#else
    pinMode(pin, INPUT_PULLUP);
#endif
    btn.lastReading = HIGH;
    btn.stableState = HIGH;
    btn.lastDebounceTime = 0;
    btn.pressStartTime = 0;
    btn.isPressed = false;
    btn.longPressFired = false;
    btn.wifiResetFired = false;
    btn.factoryResetFired = false;
    btn.cancelFired = false;
}

void ButtonManager::processButton(ButtonState& btn, void (*callback)(uint8_t)) {
    if (!btn.enabled || btn.pin == PIN_UNUSED) return;
    unsigned long now = millis();
    bool rawReading = digitalRead(btn.pin);

    if (rawReading != btn.lastReading) {
        btn.lastDebounceTime = now;
        btn.lastReading = rawReading;
    }

    if ((now - btn.lastDebounceTime) < BUTTON_DEBOUNCE_MS) return;

    if (rawReading != btn.stableState) {
        btn.stableState = rawReading;

        if (btn.stableState == LOW) {
            btn.isPressed = true;
            btn.pressStartTime = now;
            btn.longPressFired = false;
            btn.wifiResetFired = false;
            btn.factoryResetFired = false;
            btn.cancelFired = false;
            if (callback) callback(BUTTON_EVENT_DOWN);
        } else {
            if (btn.isPressed) {
                unsigned long duration = now - btn.pressStartTime;
                btn.isPressed = false;

                if (duration >= CANCEL_RESET_PRESS_MS) {
                    if (callback) callback(BUTTON_EVENT_RELEASE_CANCEL);
                } else if (duration >= FACTORY_RESET_PRESS_MS) {
                    if (callback) callback(BUTTON_EVENT_RELEASE_FACT);
                } else if (duration >= WIFI_RESET_PRESS_MS) {
                    if (callback) callback(BUTTON_EVENT_RELEASE_WIFI);
                } else if (duration >= LONG_PRESS_MS) {
                    if (callback) callback(BUTTON_EVENT_RELEASE_LONG);
                } else {
                    if (callback) callback(BUTTON_EVENT_RELEASE_SHORT);
                }
            }
        }
    }

    if (btn.isPressed) {
        unsigned long duration = now - btn.pressStartTime;
        if (duration >= CANCEL_RESET_PRESS_MS && !btn.cancelFired) {
            btn.cancelFired = true;
            if (callback) callback(BUTTON_EVENT_HELD_14S);
        } else if (duration >= FACTORY_RESET_PRESS_MS && !btn.factoryResetFired) {
            btn.factoryResetFired = true;
            if (callback) callback(BUTTON_EVENT_HELD_10S);
        } else if (duration >= WIFI_RESET_PRESS_MS && !btn.wifiResetFired) {
            btn.wifiResetFired = true;
            if (callback) callback(BUTTON_EVENT_HELD_6S);
        } else if (duration >= LONG_PRESS_MS && !btn.longPressFired) {
            btn.longPressFired = true;
            if (callback) callback(BUTTON_EVENT_HELD_3S);
        }
    }
}
