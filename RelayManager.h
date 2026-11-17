/*
 * ============================================================================
 * RelayManager.h — 5-Relay Controller with Per-Relay Trigger Polarity
 * ============================================================================
 * 
 * Each relay independently supports ACTIVE_LOW or ACTIVE_HIGH trigger mode.
 * Changing polarity does NOT change the logical ON/OFF state.
 * States are persisted to LittleFS with flash-wear coalescing.
 * ============================================================================
 */

#ifndef RELAY_MANAGER_H
#define RELAY_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "Config.h"
#include "StorageManager.h"

class HardwareManager;

// Per-relay configuration (persisted in relays.json)
struct RelayConfig {
    char name[20];
    char icon[16];              // Appliance icon/category ("light", "fan", "ac", "geyser", "tv", "socket", "pump", "router")
    TriggerMode triggerMode;
    BootStateMode bootState;
    uint16_t autoOffMinutes;    // 0 = disabled
    uint16_t autoOnMinutes;     // 0 = disabled
    bool failsafe;              // Turn OFF on crash/sensor failure
    bool manualOverride;        // Bypass scheduled operations
};

// Per-relay runtime state (persisted in relay_states.json)
struct RelayState {
    bool logicalState;          // true = ON, false = OFF
    bool lastSwitchState;       // Last known wall switch position
    unsigned long autoOffStart; // millis() when auto-off started (0 = inactive)
    unsigned long autoOnStart;  // millis() when auto-on started (0 = inactive)
};

// One-shot quick countdown timer
struct OneShotTimer {
    volatile bool active;
    volatile bool targetState;   // true = turn ON, false = turn OFF
    volatile unsigned long startMillis;
    volatile unsigned long durationMillis;
};

class RelayManager {
public:
    RelayManager();

    void begin(StorageManager& storage);
    void begin(StorageManager& storage, HardwareManager& hw);
    void loop();

    uint8_t getRelayCount() const { return _numRelays; }
    uint8_t getRelayPin(uint8_t index) const;
    bool isChannelEnabled(uint8_t index) const;
    bool isSwitchEnabled(uint8_t index) const;

    // --- State Control ---
    bool getState(uint8_t index);
    void setState(uint8_t index, bool state);
    void toggle(uint8_t index);
    void allOn();
    void allOff();

    // --- Configuration ---
    String getName(uint8_t index);
    void setName(uint8_t index, const String& name);
    String getIcon(uint8_t index);
    void setIcon(uint8_t index, const String& icon);
    TriggerMode getTriggerMode(uint8_t index);
    void setTriggerMode(uint8_t index, TriggerMode mode);
    BootStateMode getBootState(uint8_t index);
    void setBootState(uint8_t index, BootStateMode mode);
    void setAutoOff(uint8_t index, uint16_t minutes);
    void setAutoOn(uint8_t index, uint16_t minutes);
    uint16_t getAutoOff(uint8_t index);
    uint16_t getAutoOn(uint8_t index);
    bool getFailsafe(uint8_t index);
    void setFailsafe(uint8_t index, bool enabled);
    bool getManualOverride(uint8_t index);
    void setManualOverride(uint8_t index, bool enabled);

    // --- Wall Switch Integration ---
    void initWallSwitchStates();                // Boot: compare saved vs current switch
    void updateSwitchState(uint8_t index);      // Update saved switch state after toggle

    // --- EMI Lockout ---
    bool isInLockout();                         // True if relay recently switched (EMI blanking)

    // --- Persistence ---
    void saveConfig();
    void saveStates();

    // --- Callback ---
    void setChangeCallback(void (*cb)(uint8_t index, bool state));

    // --- One-Shot Quick Timers ---
    void startTimer(uint8_t index, bool targetState, uint32_t durationSeconds);
    void cancelTimer(uint8_t index);
    bool hasActiveTimer(uint8_t index);
    bool getTimerTargetState(uint8_t index);
    uint32_t getTimerRemaining(uint8_t index);

    // --- Failsafe ---
    void activateFailsafe();

    // --- JSON Serialization ---
    void toJson(JsonArray& arr);
    void stateToJson(JsonArray& arr);

private:
    StorageManager* _storage;
    HardwareManager* _hw;
    uint8_t _numRelays;
    RelayConfig _config[MAX_RELAYS];
    RelayState _state[MAX_RELAYS];
    OneShotTimer _timers[MAX_RELAYS];

    // EMI lockout — blanking period after any relay switches
    bool _hasSwitched;
    unsigned long _lastRelaySwitchTime;

#if defined(ESP32)
    mutable portMUX_TYPE _mux;
#endif

    // Non-blocking anti-brownout staggered energization (120ms spacing between coils)
    static const unsigned long RELAY_STAGGER_MS = 120;
    bool _pendingStaggerOn[MAX_RELAYS];
    bool _pendingNotifyOff[MAX_RELAYS];
    unsigned long _lastStaggerStep;

    // State persistence coalescing
    bool _statesDirty;
    unsigned long _lastStateSave;

    // Callback
    void (*_changeCallback)(uint8_t, bool);

    // Internal
    void applyState(uint8_t index);             // Write GPIO based on logical state + polarity
    void loadConfig();
    void loadStates();
    void setDefaults();
};

#endif // RELAY_MANAGER_H
