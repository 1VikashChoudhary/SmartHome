/*
 * ============================================================================
 * ButtonManager.h — Debounced Multi-Button & Dynamic Wall Switches
 * ============================================================================
 * 
 * Supports up to MAX_RELAYS (8) wall switches with configurable switch modes:
 * Toggle, Push-Button (Momentary), Follow (Stateful), and Detached.
 * Wall switches use POLLED debounce (200ms) with relay EMI lockout.
 * ============================================================================
 */

#ifndef BUTTON_MANAGER_H
#define BUTTON_MANAGER_H

#include <Arduino.h>
#include "Config.h"
#include "HardwareManager.h"

// Multi-function button event types
#define BUTTON_EVENT_DOWN            0
#define BUTTON_EVENT_HELD_3S         1
#define BUTTON_EVENT_HELD_6S         2
#define BUTTON_EVENT_HELD_10S        3
#define BUTTON_EVENT_HELD_14S        4
#define BUTTON_EVENT_RELEASE_SHORT   5
#define BUTTON_EVENT_RELEASE_LONG    6
#define BUTTON_EVENT_RELEASE_WIFI    7
#define BUTTON_EVENT_RELEASE_FACT    8
#define BUTTON_EVENT_RELEASE_CANCEL  9

// Wall switch action types for callback
#define SWITCH_ACTION_TOGGLE         0
#define SWITCH_ACTION_ON             1
#define SWITCH_ACTION_OFF            2

class ButtonManager {
public:
    ButtonManager();

    void begin();
    void begin(HardwareManager& hw);
    void loop();

    // Initialize wall switch pin states (call AFTER RelayManager::initWallSwitchStates)
    void initWallSwitchPins();
    void initWallSwitchPins(HardwareManager& hw);

    // Callbacks
    void setWallSwitchCallback(void (*cb)(uint8_t index));
    void setWallSwitchActionCallback(void (*cb)(uint8_t index, uint8_t action));
    void setMultiButtonCallback(void (*cb)(uint8_t eventType));
    void setLockoutCallback(bool (*cb)());

private:
    // --- Wall Switches ---
    struct SwitchState {
        uint8_t pin;
        SwitchMode mode;
        bool lastReading;             // Last raw pin reading
        bool stableState;             // Confirmed debounced state
        unsigned long lastChangeTime; // When the reading last changed
    };

    uint8_t _numRelays;
    SwitchState _switches[MAX_RELAYS];

    void (*_wallSwitchCb)(uint8_t);
    void (*_wallSwitchActionCb)(uint8_t, uint8_t);
    bool (*_lockoutCb)();

    void processSwitches();

    // --- Control Button (polled) ---
    struct ButtonState {
        uint8_t pin;
        bool enabled;
        bool lastReading;
        bool stableState;
        unsigned long lastDebounceTime;
        unsigned long pressStartTime;
        bool isPressed;
        bool longPressFired;
        bool wifiResetFired;
        bool factoryResetFired;
        bool cancelFired;
    };

    ButtonState _btnMulti;
    void (*_multiCb)(uint8_t);

    void initButton(ButtonState& btn, uint8_t pin);
    void processButton(ButtonState& btn, void (*callback)(uint8_t));
};

#endif // BUTTON_MANAGER_H
