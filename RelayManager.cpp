/*
 * ============================================================================
 * RelayManager.cpp — Dynamic Multi-Relay Controller Implementation
 * ============================================================================
 * 
 * Supports up to MAX_RELAYS (8) dynamic channels with per-relay GPIO assignment,
 * trigger polarity, boot state, auto-on/off timers, and anti-brownout staggering.
 * Decouples hardware GPIO pins from logical state via HardwareManager.
 * ============================================================================
 */

#include "RelayManager.h"
#include "HardwareManager.h"

RelayManager::RelayManager()
    : _storage(nullptr), _hw(nullptr), _numRelays(NUM_RELAYS),
      _hasSwitched(false), _lastRelaySwitchTime(0), _lastStaggerStep(0),
      _statesDirty(false), _lastStateSave(0), _changeCallback(nullptr) {
#if defined(ESP32)
    _mux = portMUX_INITIALIZER_UNLOCKED;
#endif
    memset(_timers, 0, sizeof(_timers));
    memset(_pendingStaggerOn, 0, sizeof(_pendingStaggerOn));
    memset(_pendingNotifyOff, 0, sizeof(_pendingNotifyOff));
    setDefaults();
}

// ============================================================================
// Initialize (Legacy Overload)
// ============================================================================
void RelayManager::begin(StorageManager& storage) {
    _storage = &storage;
    _hw = nullptr;
    _numRelays = NUM_RELAYS;

    loadConfig();
    loadStates();

    for (uint8_t i = 0; i < _numRelays; i++) {
        uint8_t pin = getRelayPin(i);
        if (pin != PIN_UNUSED) {
            bool offLevel = (_config[i].triggerMode == TRIGGER_ACTIVE_LOW) ? HIGH : LOW;
            digitalWrite(pin, offLevel);
            pinMode(pin, OUTPUT);
        }

        switch (_config[i].bootState) {
            case BOOT_ALWAYS_ON:  _state[i].logicalState = true; break;
            case BOOT_ALWAYS_OFF: _state[i].logicalState = false; break;
            case BOOT_RESTORE_LAST:
            default: break;
        }

        _state[i].autoOffStart = 0;
        _state[i].autoOnStart = 0;
        _pendingStaggerOn[i] = false;
    }

    initWallSwitchStates();

    bool firstOnEnergized = false;
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_state[i].logicalState) {
            if (_config[i].autoOffMinutes > 0) _state[i].autoOffStart = millis();
            if (!firstOnEnergized) {
                firstOnEnergized = true;
                applyState(i);
                _lastRelaySwitchTime = millis();
                _hasSwitched = true;
                _lastStaggerStep = millis();
            } else {
                _pendingStaggerOn[i] = true;
            }
        } else {
            if (_config[i].autoOnMinutes > 0) _state[i].autoOnStart = millis();
            applyState(i);
        }
    }

    _lastStateSave = millis();
    SERIAL_PRINTF("[Relay] Initialized (%d relays, legacy mode)\n", _numRelays);
}

// ============================================================================
// Initialize (Hardware Profile Engine)
// ============================================================================
void RelayManager::begin(StorageManager& storage, HardwareManager& hw) {
    _storage = &storage;
    _hw = &hw;
    _numRelays = hw.getNumRelays();
    if (_numRelays > MAX_RELAYS) _numRelays = MAX_RELAYS;

    loadConfig();
    loadStates();

    // Initialize relay GPIO pins and apply boot states
    for (uint8_t i = 0; i < _numRelays; i++) {
        _config[i].triggerMode = hw.getTriggerMode(i);
        if (!isChannelEnabled(i)) {
            _state[i].logicalState = false;
            _state[i].autoOffStart = 0;
            _state[i].autoOnStart = 0;
            _pendingStaggerOn[i] = false;
            continue;
        }
        uint8_t pin = getRelayPin(i);
        if (pin != PIN_UNUSED) {
            bool offLevel = (_config[i].triggerMode == TRIGGER_ACTIVE_LOW) ? HIGH : LOW;
            digitalWrite(pin, offLevel);
            pinMode(pin, OUTPUT);
        }

        switch (_config[i].bootState) {
            case BOOT_ALWAYS_ON:  _state[i].logicalState = true; break;
            case BOOT_ALWAYS_OFF: _state[i].logicalState = false; break;
            case BOOT_RESTORE_LAST:
            default: break;
        }

        _state[i].autoOffStart = 0;
        _state[i].autoOnStart = 0;
        _pendingStaggerOn[i] = false;
    }

    // Handle wall switch physical states at boot
    initWallSwitchStates();

    // Anti-brownout boot sequencing: energize first ON relay immediately,
    // and stagger remaining ON relays by 120ms in loop()
    bool firstOnEnergized = false;
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (!isChannelEnabled(i)) {
            SERIAL_PRINTF("[Relay] %d '%s': DISABLED (unused)\n", i + 1, _config[i].name);
            continue;
        }
        if (_state[i].logicalState) {
            if (_config[i].autoOffMinutes > 0) {
                _state[i].autoOffStart = millis();
            }
            if (!firstOnEnergized) {
                firstOnEnergized = true;
                applyState(i);
                _lastRelaySwitchTime = millis();
                _hasSwitched = true;
                _lastStaggerStep = millis();
            } else {
                _pendingStaggerOn[i] = true;
            }
        } else {
            if (_config[i].autoOnMinutes > 0) {
                _state[i].autoOnStart = millis();
            }
            applyState(i);
        }

        SERIAL_PRINTF("[Relay] %d '%s' (%s, GPIO %d): %s (trigger: %s, boot: %d)\n",
                      i + 1, _config[i].name, _config[i].icon, getRelayPin(i),
                      _state[i].logicalState ? (_pendingStaggerOn[i] ? "ON (staggered)" : "ON") : "OFF",
                      _config[i].triggerMode == TRIGGER_ACTIVE_LOW ? "ActiveLOW" : "ActiveHIGH",
                      _config[i].bootState);
    }

    _lastStateSave = millis();
    SERIAL_PRINTF("[Relay] Initialized (%d configured channels)\n", _numRelays);
}

uint8_t RelayManager::getRelayPin(uint8_t index) const {
    if (index >= _numRelays) return PIN_UNUSED;
    if (_hw) return _hw->getRelayPin(index);
    return (index < NUM_RELAYS) ? RELAY_PINS[index] : PIN_UNUSED;
}

bool RelayManager::isChannelEnabled(uint8_t index) const {
    if (index >= _numRelays) return false;
    if (_hw) return _hw->isChannelEnabled(index);
    return getRelayPin(index) != PIN_UNUSED;
}

bool RelayManager::isSwitchEnabled(uint8_t index) const {
    if (index >= _numRelays) return false;
    if (_hw) return _hw->isSwitchEnabled(index);
    return (index < NUM_RELAYS) && (SWITCH_PINS[index] != PIN_UNUSED);
}

// ============================================================================
// Non-blocking loop — staggered energization, auto timers, state persistence
// ============================================================================
void RelayManager::loop() {
    unsigned long now = millis();

    // --- Non-blocking OFF notification dispatch (keeps async_tcp HTTP handler fast) ---
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_pendingNotifyOff[i]) {
            _pendingNotifyOff[i] = false;
            if (!_state[i].logicalState && _changeCallback) {
                _changeCallback(i, false);
            }
            break; // Dispatch one per loop iteration to avoid WebSocket/MQTT queue burst
        }
    }

    // --- Non-blocking anti-brownout staggered coil energization (120ms spacing) ---
    if (now - _lastStaggerStep >= RELAY_STAGGER_MS) {
        for (uint8_t i = 0; i < _numRelays; i++) {
            if (_pendingStaggerOn[i]) {
                _pendingStaggerOn[i] = false;
                _lastStaggerStep = now;
                if (_state[i].logicalState) {
                    applyState(i);
                    _lastRelaySwitchTime = now;
                    _hasSwitched = true;
                    SERIAL_PRINTF("[Relay] %d staggered ON coil energized\n", i + 1);
                    if (_changeCallback) {
                        _changeCallback(i, true);
                    }
                }
                break; // Energize one coil per 120ms interval
            }
        }
    }

    // --- Auto-OFF timers ---
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_state[i].autoOffStart > 0 && _config[i].autoOffMinutes > 0) {
            if (now - _state[i].autoOffStart >= (unsigned long)_config[i].autoOffMinutes * 60000UL) {
                _state[i].autoOffStart = 0;
                setState(i, false);
                SERIAL_PRINTF("[Relay] %d auto-OFF triggered\n", i + 1);
            }
        }
    }

    // --- Auto-ON timers ---
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_state[i].autoOnStart > 0 && _config[i].autoOnMinutes > 0) {
            if (now - _state[i].autoOnStart >= (unsigned long)_config[i].autoOnMinutes * 60000UL) {
                _state[i].autoOnStart = 0;
                setState(i, true);
                SERIAL_PRINTF("[Relay] %d auto-ON triggered\n", i + 1);
            }
        }
    }

    // --- One-Shot Quick Timers ---
    for (uint8_t i = 0; i < _numRelays; i++) {
        bool timerFired = false;
        bool target = false;
#if defined(ESP32)
        portENTER_CRITICAL(&_mux);
#endif
        if (_timers[i].active && _timers[i].durationMillis > 0) {
            if (now - _timers[i].startMillis >= _timers[i].durationMillis) {
                target = _timers[i].targetState;
                _timers[i].active = false;
                _timers[i].durationMillis = 0;
                _timers[i].startMillis = 0;
                timerFired = true;
            }
        }
#if defined(ESP32)
        portEXIT_CRITICAL(&_mux);
#endif
        if (timerFired) {
            setState(i, target);
            SERIAL_PRINTF("[Relay] %d quick timer finished -> state %s\n", i + 1, target ? "ON" : "OFF");
        }
    }

    // --- Coalesced state persistence ---
    if (_statesDirty && (now - _lastStateSave >= RELAY_SAVE_COALESCE)) {
        saveStates();
    }
}

// ============================================================================
// State Control
// ============================================================================
bool RelayManager::getState(uint8_t index) {
    if (index >= _numRelays) return false;
    return _state[index].logicalState;
}

void RelayManager::setState(uint8_t index, bool state) {
    if (index >= _numRelays || !isChannelEnabled(index)) return;
    if (_state[index].logicalState == state && !_pendingStaggerOn[index]) return; // No change

    // Track physical relay cycle count in NVS for wear-leveling monitoring
    if (_storage && _state[index].logicalState != state) {
        _storage->incrementRelayCycleNVS(index);
    }

    _pendingStaggerOn[index] = false;
    _pendingNotifyOff[index] = false;
    _state[index].logicalState = state;
    applyState(index);

    // Cancel quick timer if relay has reached the target state or was switched off manually
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    if (_timers[index].active && (state == _timers[index].targetState || !state)) {
        _timers[index].active = false;
        _timers[index].durationMillis = 0;
        _timers[index].startMillis = 0;
    }
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif

    // Record relay switch time for EMI lockout
    _lastRelaySwitchTime = millis();
    _hasSwitched = true;

    // Handle auto timers
    if (state) {
        _state[index].autoOnStart = 0;
        if (_config[index].autoOffMinutes > 0) {
            _state[index].autoOffStart = millis();
        }
    } else {
        _state[index].autoOffStart = 0;
        if (_config[index].autoOnMinutes > 0) {
            _state[index].autoOnStart = millis();
        }
    }

    _statesDirty = true;

    if (_changeCallback) {
        _changeCallback(index, state);
    }
}

void RelayManager::toggle(uint8_t index) {
    if (index >= _numRelays || !isChannelEnabled(index)) return;
    setState(index, !_state[index].logicalState);
}

void RelayManager::allOn() {
    unsigned long now = millis();
    bool anyQueued = false;

    for (uint8_t i = 0; i < _numRelays; i++) {
        if (!isChannelEnabled(i)) continue;
        _pendingNotifyOff[i] = false;
        if (_state[i].logicalState && !_pendingStaggerOn[i]) continue;

        if (_storage && !_state[i].logicalState) {
            _storage->incrementRelayCycleNVS(i);
        }
        _state[i].logicalState = true;

#if defined(ESP32)
        portENTER_CRITICAL(&_mux);
#endif
        if (_timers[i].active && _timers[i].targetState) {
            _timers[i].active = false;
            _timers[i].durationMillis = 0;
            _timers[i].startMillis = 0;
        }
#if defined(ESP32)
        portEXIT_CRITICAL(&_mux);
#endif
        _state[i].autoOnStart = 0;
        if (_config[i].autoOffMinutes > 0) {
            _state[i].autoOffStart = now;
        }

        _pendingStaggerOn[i] = true;
        anyQueued = true;
        _statesDirty = true;
    }

    if (anyQueued) {
        _lastStaggerStep = now - (RELAY_STAGGER_MS - 30);
    }
}

void RelayManager::allOff() {
    unsigned long now = millis();
    for (uint8_t i = 0; i < _numRelays; i++) {
        bool wasOn = _state[i].logicalState || _pendingStaggerOn[i];
        _pendingStaggerOn[i] = false;
        if (!wasOn) continue;

        if (_storage && _state[i].logicalState) {
            _storage->incrementRelayCycleNVS(i);
        }
        _state[i].logicalState = false;
        applyState(i);
        _lastRelaySwitchTime = now;
        _hasSwitched = true;

#if defined(ESP32)
        portENTER_CRITICAL(&_mux);
#endif
        if (_timers[i].active && !_timers[i].targetState) {
            _timers[i].active = false;
            _timers[i].durationMillis = 0;
            _timers[i].startMillis = 0;
        }
#if defined(ESP32)
        portEXIT_CRITICAL(&_mux);
#endif
        _state[i].autoOffStart = 0;
        if (_config[i].autoOnMinutes > 0) {
            _state[i].autoOnStart = now;
        }

        _statesDirty = true;
        _pendingNotifyOff[i] = true;
    }
}

// ============================================================================
// Configuration Getters/Setters
// ============================================================================
String RelayManager::getName(uint8_t index) {
    if (index >= _numRelays) return "";
    return String(_config[index].name);
}

void RelayManager::setName(uint8_t index, const String& name) {
    if (index >= _numRelays) return;
    strncpy(_config[index].name, name.c_str(), sizeof(_config[index].name) - 1);
    _config[index].name[sizeof(_config[index].name) - 1] = '\0';
    saveConfig();
}

String RelayManager::getIcon(uint8_t index) {
    if (index >= _numRelays) return "light";
    return String(_config[index].icon);
}

void RelayManager::setIcon(uint8_t index, const String& icon) {
    if (index >= _numRelays) return;
    String clean = icon;
    clean.trim();
    clean.toLowerCase();
    if (clean.length() == 0) clean = "light";
    strncpy(_config[index].icon, clean.c_str(), sizeof(_config[index].icon) - 1);
    _config[index].icon[sizeof(_config[index].icon) - 1] = '\0';
    saveConfig();
}

TriggerMode RelayManager::getTriggerMode(uint8_t index) {
    if (index >= _numRelays) return TRIGGER_ACTIVE_LOW;
    return _config[index].triggerMode;
}

void RelayManager::setTriggerMode(uint8_t index, TriggerMode mode) {
    if (index >= _numRelays) return;
    _config[index].triggerMode = mode;
    applyState(index);
    saveConfig();
    if (_hw && _hw->getTriggerMode(index) != mode) {
        _hw->setTriggerMode(index, mode);
    }
    SERIAL_PRINTF("[Relay] %d trigger mode → %s\n", index + 1,
                  mode == TRIGGER_ACTIVE_LOW ? "ActiveLOW" : "ActiveHIGH");
}

BootStateMode RelayManager::getBootState(uint8_t index) {
    if (index >= _numRelays) return BOOT_RESTORE_LAST;
    return _config[index].bootState;
}

void RelayManager::setBootState(uint8_t index, BootStateMode mode) {
    if (index >= _numRelays) return;
    _config[index].bootState = mode;
    saveConfig();
}

void RelayManager::setAutoOff(uint8_t index, uint16_t minutes) {
    if (index >= _numRelays) return;
    _config[index].autoOffMinutes = minutes;
    _state[index].autoOffStart = 0;
    saveConfig();
}

void RelayManager::setAutoOn(uint8_t index, uint16_t minutes) {
    if (index >= _numRelays) return;
    _config[index].autoOnMinutes = minutes;
    _state[index].autoOnStart = 0;
    saveConfig();
}

uint16_t RelayManager::getAutoOff(uint8_t index) {
    return (index < _numRelays) ? _config[index].autoOffMinutes : 0;
}

uint16_t RelayManager::getAutoOn(uint8_t index) {
    return (index < _numRelays) ? _config[index].autoOnMinutes : 0;
}

bool RelayManager::getFailsafe(uint8_t index) {
    return (index < _numRelays) ? _config[index].failsafe : false;
}

void RelayManager::setFailsafe(uint8_t index, bool enabled) {
    if (index >= _numRelays) return;
    _config[index].failsafe = enabled;
    saveConfig();
}

bool RelayManager::getManualOverride(uint8_t index) {
    return (index < _numRelays) ? _config[index].manualOverride : false;
}

void RelayManager::setManualOverride(uint8_t index, bool enabled) {
    if (index >= _numRelays) return;
    _config[index].manualOverride = enabled;
    saveConfig();
}

// ============================================================================
// Wall Switch Integration & EMI Lockout
// ============================================================================
bool RelayManager::isInLockout() {
    if (!_hasSwitched) return false;
    return (millis() - _lastRelaySwitchTime) < RELAY_SWITCH_LOCKOUT_MS;
}

void RelayManager::initWallSwitchStates() {
    bool changedAny = false;
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (!isChannelEnabled(i) || !isSwitchEnabled(i)) continue;
        uint8_t pin = _hw ? _hw->getSwitchPin(i) : (i < NUM_RELAYS ? SWITCH_PINS[i] : PIN_UNUSED);
        if (pin == PIN_UNUSED) continue;

#if defined(ESP8266)
        if (pin == 16) {
            pinMode(pin, INPUT); // ESP8266 GPIO 16 has no internal pullup
        } else {
            pinMode(pin, INPUT_PULLUP);
        }
#elif defined(ESP32)
        if (pin >= 34 && pin <= 39) {
            pinMode(pin, INPUT); // ESP32 GPIO 34-39 are input-only with no internal pullups
        } else {
            pinMode(pin, INPUT_PULLUP);
        }
#else
        pinMode(pin, INPUT_PULLUP);
#endif
        bool currentSwitch = !digitalRead(pin);
        bool savedSwitch = _state[i].lastSwitchState;
        SwitchMode swMode = _hw ? _hw->getSwitchMode(i) : SWITCH_MODE_TOGGLE;

        if (_config[i].bootState == BOOT_RESTORE_LAST) {
            if (swMode == SWITCH_MODE_FOLLOW) {
                if (_state[i].logicalState != currentSwitch) {
                    _state[i].logicalState = currentSwitch;
                    changedAny = true;
                }
            } else if (swMode == SWITCH_MODE_FOLLOW_INV) {
                bool desired = !currentSwitch;
                if (_state[i].logicalState != desired) {
                    _state[i].logicalState = desired;
                    changedAny = true;
                }
            } else if (swMode == SWITCH_MODE_TOGGLE && currentSwitch != savedSwitch) {
                SERIAL_PRINTF("[Relay] Switch %d changed during power off (%s→%s), toggling\n",
                              i + 1, savedSwitch ? "ON" : "OFF", currentSwitch ? "ON" : "OFF");
                _state[i].logicalState = !_state[i].logicalState;
                changedAny = true;
            }
        }

        if (_state[i].lastSwitchState != currentSwitch) {
            _state[i].lastSwitchState = currentSwitch;
            changedAny = true;
        }
    }
    if (changedAny) {
        _statesDirty = true;
    }
}

void RelayManager::updateSwitchState(uint8_t index) {
    if (index >= _numRelays) return;
    uint8_t pin = _hw ? _hw->getSwitchPin(index) : (index < NUM_RELAYS ? SWITCH_PINS[index] : PIN_UNUSED);
    if (pin == PIN_UNUSED) return;
    _state[index].lastSwitchState = !digitalRead(pin);
    _statesDirty = true;
}

void RelayManager::setChangeCallback(void (*cb)(uint8_t, bool)) {
    _changeCallback = cb;
}

void RelayManager::activateFailsafe() {
    for (uint8_t i = 0; i < _numRelays; i++) {
        if (_config[i].failsafe && _state[i].logicalState) {
            setState(i, false);
            SERIAL_PRINTF("[Relay] Failsafe: relay %d turned OFF\n", i + 1);
        }
    }
}

// ============================================================================
// Persistence
// ============================================================================
void RelayManager::saveConfig() {
    if (!_storage) return;

    JsonDocument doc;
    doc["version"] = CONFIG_SCHEMA_VERSION;
    JsonArray arr = doc["relays"].to<JsonArray>();

    for (uint8_t i = 0; i < _numRelays; i++) {
        JsonObject r = arr.add<JsonObject>();
        r["name"]     = _config[i].name;
        r["icon"]     = _config[i].icon;
        r["trigger"]  = (uint8_t)_config[i].triggerMode;
        r["boot"]     = (uint8_t)_config[i].bootState;
        r["autoOff"]  = _config[i].autoOffMinutes;
        r["autoOn"]   = _config[i].autoOnMinutes;
        r["failsafe"] = _config[i].failsafe;
        r["override"] = _config[i].manualOverride;
    }

    _storage->saveJson(PATH_RELAYS, doc);
}

void RelayManager::saveStates() {
    if (!_storage) return;

    bool logical[MAX_RELAYS] = {0};
    bool wallSw[MAX_RELAYS] = {0};

    for (uint8_t i = 0; i < _numRelays; i++) {
        logical[i] = _state[i].logicalState;
        wallSw[i] = _state[i].lastSwitchState;
    }

    if (_storage->saveRelayStatesNVS(logical, wallSw, _numRelays)) {
        _statesDirty = false;
        _lastStateSave = millis();
    }
}

// ============================================================================
// JSON Serialization
// ============================================================================
void RelayManager::toJson(JsonArray& arr) {
    for (uint8_t i = 0; i < _numRelays; i++) {
        JsonObject r = arr.add<JsonObject>();
        r["id"]       = i;
        r["name"]     = _config[i].name;
        r["icon"]     = _config[i].icon;
        r["enabled"]  = isChannelEnabled(i);
        r["switch_enabled"] = isSwitchEnabled(i);
        r["state"]    = isChannelEnabled(i) ? _state[i].logicalState : false;
        r["pin"]      = getRelayPin(i);
        r["trigger"]  = (uint8_t)_config[i].triggerMode;
        r["boot"]     = (uint8_t)_config[i].bootState;
        r["auto_off"] = _config[i].autoOffMinutes;
        r["auto_on"]  = _config[i].autoOnMinutes;
        r["cycles"]   = _storage ? _storage->getRelayCycleNVS(i) : 0;
        r["failsafe"] = _config[i].failsafe;
        r["override"] = _config[i].manualOverride;
        r["switch"]   = _state[i].lastSwitchState;

        // Quick timer info
        r["timer_active"]    = hasActiveTimer(i);
        r["timer_target"]    = getTimerTargetState(i);
        r["timer_remaining"] = getTimerRemaining(i);
    }
}

void RelayManager::stateToJson(JsonArray& arr) {
    for (uint8_t i = 0; i < _numRelays; i++) {
        JsonObject s = arr.add<JsonObject>();
        s["id"]      = i;
        s["enabled"] = isChannelEnabled(i);
        s["state"]   = isChannelEnabled(i) ? _state[i].logicalState : false;
        s["timer_active"]    = hasActiveTimer(i);
        s["timer_target"]    = getTimerTargetState(i);
        s["timer_remaining"] = getTimerRemaining(i);
    }
}

// ============================================================================
// One-Shot Quick Timers
// ============================================================================
void RelayManager::startTimer(uint8_t index, bool targetState, uint32_t durationSeconds) {
    if (index >= _numRelays || !isChannelEnabled(index) || durationSeconds == 0) return;
    // Cap duration at max 32-bit millis range (~49.7 days) to avoid uint32 overflow
    uint32_t safeDurationSec = (durationSeconds > 4294967UL) ? 4294967UL : durationSeconds;
    unsigned long durMs = (unsigned long)safeDurationSec * 1000UL;
    unsigned long now = millis();
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    _timers[index].active = false;
    _timers[index].targetState = targetState;
    _timers[index].startMillis = now;
    _timers[index].durationMillis = durMs;
    _timers[index].active = true;
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif
    SERIAL_PRINTF("[Relay] %d quick timer started: %s in %lu s\n",
                  index + 1, targetState ? "ON" : "OFF", (unsigned long)safeDurationSec);
}

void RelayManager::cancelTimer(uint8_t index) {
    if (index >= _numRelays) return;
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    _timers[index].active = false;
    _timers[index].durationMillis = 0;
    _timers[index].startMillis = 0;
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif
    SERIAL_PRINTF("[Relay] %d quick timer cancelled\n", index + 1);
}

bool RelayManager::hasActiveTimer(uint8_t index) {
    if (index >= _numRelays) return false;
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    bool active = _timers[index].active;
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif
    return active;
}

bool RelayManager::getTimerTargetState(uint8_t index) {
    if (index >= _numRelays) return false;
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    bool target = _timers[index].targetState;
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif
    return target;
}

uint32_t RelayManager::getTimerRemaining(uint8_t index) {
    if (index >= _numRelays) return 0;
#if defined(ESP32)
    portENTER_CRITICAL(&_mux);
#endif
    bool active = _timers[index].active;
    unsigned long startMs = _timers[index].startMillis;
    unsigned long durMs = _timers[index].durationMillis;
#if defined(ESP32)
    portEXIT_CRITICAL(&_mux);
#endif
    if (!active) return 0;
    unsigned long elapsed = millis() - startMs;
    if (elapsed >= durMs) return 0;
    return (uint32_t)((durMs - elapsed) / 1000UL);
}

// ============================================================================
// Private — Apply GPIO output from logical state + trigger mode
// ============================================================================
void RelayManager::applyState(uint8_t index) {
    if (index >= _numRelays) return;
    uint8_t pin = getRelayPin(index);
    if (pin == PIN_UNUSED) return;

    bool logicalON = _state[index].logicalState;
    TriggerMode mode = _config[index].triggerMode;

    bool gpioLevel = (mode == TRIGGER_ACTIVE_LOW) ? !logicalON : logicalON;
    digitalWrite(pin, gpioLevel ? HIGH : LOW);
}

// ============================================================================
// Private — Load config from LittleFS
// ============================================================================
void RelayManager::loadConfig() {
    setDefaults();

    if (!_storage) return;
    JsonDocument doc;
    if (!_storage->loadJson(PATH_RELAYS, doc)) return;

    JsonArray arr = doc["relays"].as<JsonArray>();
    uint8_t i = 0;
    for (JsonObject r : arr) {
        if (i >= _numRelays) break;

        const char* name = r["name"] | DEFAULT_RELAY_NAMES[i];
        strncpy(_config[i].name, name, sizeof(_config[i].name) - 1);
        _config[i].name[sizeof(_config[i].name) - 1] = '\0';

        const char* icon = r["icon"] | "light";
        strncpy(_config[i].icon, icon, sizeof(_config[i].icon) - 1);
        _config[i].icon[sizeof(_config[i].icon) - 1] = '\0';

        _config[i].triggerMode    = (TriggerMode)(r["trigger"] | (uint8_t)DEFAULT_TRIGGER_MODE);
        _config[i].bootState      = (BootStateMode)(r["boot"] | (uint8_t)DEFAULT_BOOT_STATE);
        _config[i].autoOffMinutes = r["autoOff"] | 0;
        _config[i].autoOnMinutes  = r["autoOn"] | 0;
        _config[i].failsafe       = r["failsafe"] | false;
        _config[i].manualOverride = r["override"] | false;
        i++;
    }
}

// ============================================================================
// Private — Load states from Decoupled NVS
// ============================================================================
void RelayManager::loadStates() {
    for (uint8_t i = 0; i < MAX_RELAYS; i++) {
        _state[i].logicalState = false;
        _state[i].lastSwitchState = false;
        _state[i].autoOffStart = 0;
        _state[i].autoOnStart = 0;
    }

    if (!_storage) return;

    bool logical[MAX_RELAYS] = {0};
    bool wallSw[MAX_RELAYS] = {0};

    if (_storage->loadRelayStatesNVS(logical, wallSw, _numRelays)) {
        for (uint8_t i = 0; i < _numRelays; i++) {
            _state[i].logicalState = logical[i];
            _state[i].lastSwitchState = wallSw[i];
        }
        SERIAL_PRINTF("[Relay] Restored %d channel states from wear-leveled NVS\n", _numRelays);
    } else {
        Serial.println(F("[Relay] No prior states in NVS; defaults applied"));
    }
}

// ============================================================================
// Private — Set default configuration
// ============================================================================
void RelayManager::setDefaults() {
    for (uint8_t i = 0; i < MAX_RELAYS; i++) {
        strncpy(_config[i].name, DEFAULT_RELAY_NAMES[i], sizeof(_config[i].name) - 1);
        _config[i].name[sizeof(_config[i].name) - 1] = '\0';
        strncpy(_config[i].icon, "light", sizeof(_config[i].icon) - 1);
        _config[i].icon[sizeof(_config[i].icon) - 1] = '\0';
        _config[i].triggerMode = (_hw && i < _numRelays) ? _hw->getTriggerMode(i) : DEFAULT_TRIGGER_MODE;
        _config[i].bootState = DEFAULT_BOOT_STATE;
        _config[i].autoOffMinutes = 0;
        _config[i].autoOnMinutes = 0;
        _config[i].failsafe = false;
        _config[i].manualOverride = false;
    }
}
