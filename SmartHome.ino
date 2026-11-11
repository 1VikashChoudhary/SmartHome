/*
 * ============================================================================
 * SmartHome.ino — ESP32 Smart Home & Monitoring System
 * ============================================================================
 * 
 * Main sketch: initializes all modules and orchestrates the non-blocking
 * main loop. Every module's loop() returns immediately when not yet due.
 * 
 * Target: ESP32 DevKit v1 (ESP-WROOM-32)
 * Framework: Arduino (ESP32 Core 2.x+)
 * IDE: Arduino IDE 2.x or PlatformIO
 * 
 * Required Libraries:
 *   - ESPAsyncWebServer (by me-no-dev)
 *   - AsyncTCP (by me-no-dev)
 *   - AsyncMqttClient (by marvinroger)
 *   - ArduinoJson v7+ (by bblanchon)
 *   - DHT sensor library (by Adafruit)
 *   - LiquidCrystal_I2C (by johnrickman)
 * 
 * Built-in (ESP32 core):
 *   - WiFi, ESPmDNS, ArduinoOTA, LittleFS, Wire, time.h
 * 
 * Copyright (c) 2026 — Production Ready
 * ============================================================================
 */

#include <Arduino.h>
#if defined(ESP32)
#include <esp_arduino_version.h>
#include <esp_task_wdt.h>
#endif

// Project modules
#include "Config.h"
#include "StorageManager.h"
#include "HardwareManager.h"
#include "WifiManager.h"
#include "OTAManager.h"
#include "TimeManager.h"
#include "Diagnostics.h"
#include "SensorManager.h"
#include "BuzzerManager.h"
#include "RelayManager.h"
#include "ButtonManager.h"
#include "LCDManager.h"
#include "MqttManager.h"
#include "AlarmScheduler.h"
#include "RuleManager.h"
#include "EventLogger.h"
#include "WebSocketManager.h"
#include "WebServerManager.h"

// ============================================================================
// Module Instances (global, single instance each)
// ============================================================================
StorageManager    storage;
HardwareManager   hwMgr;
WifiManager       wifiMgr;
OTAManager        otaMgr;
TimeManager       timeMgr;
Diagnostics       diag;
SensorManager     sensorMgr;
BuzzerManager     buzzerMgr;
RelayManager      relayMgr;
ButtonManager     buttonMgr;
LCDManager        lcdMgr;
MqttManager       mqttMgr;
AlarmScheduler    alarmSched;
RuleManager       ruleMgr;
EventLogger       logger;
WebSocketManager  wsMgr;
WebServerManager  webServer;

// ============================================================================

// ============================================================================
// WebSocket data provider — builds JSON status for broadcast
// ============================================================================
String wsDataProvider() {
    JsonDocument doc;

    // Device info (cached in RAM to eliminate SPI flash wear during 1Hz WebSocket broadcast)
    doc["device_name"] = webServer.getDeviceName();
    doc["fw_version"] = FW_VERSION;
    doc["platform"] = PLATFORM_NAME;
    doc["model"] = String(PLATFORM_NAME) + "-SmartHome";
    doc["mac"] = wifiMgr.getMAC();
    doc["device_id"] = wifiMgr.getDeviceId();
    doc["num_relays"] = relayMgr.getRelayCount();
    doc["auth_required"] = webServer.isAuthEnabled();

    // WiFi
    doc["wifi_state"] = wifiMgr.getStateString();
    doc["rssi"] = wifiMgr.getRSSI();
    doc["signal"] = wifiMgr.getSignalPercent();
    doc["ip"] = wifiMgr.getIP();
    doc["hostname"] = wifiMgr.getHostname();

    // MQTT
    doc["mqtt_state"] = mqttMgr.getStateString();

    // Time
    doc["uptime"] = diag.getUptimeString();
    doc["datetime"] = timeMgr.getFormattedDateTime();
    doc["free_heap"] = diag.getFreeHeap();

    // Sensors
    doc["temperature"] = serialized(String(sensorMgr.getTemperature(), 1));
    doc["humidity"] = serialized(String(sensorMgr.getHumidity(), 1));
    doc["pressure"] = serialized(String(sensorMgr.getPressure(), 1));
    doc["pressure_enabled"] = sensorMgr.hasBarometer();
    doc["dht_fault"] = sensorMgr.isDHTFault();
    doc["temp_threshold"] = sensorMgr.getTempAlarmThreshold();
    doc["lux"] = serialized(String(sensorMgr.getLux(), 1));
    doc["lux_enabled"] = sensorMgr.isLuxEnabled();
    doc["motion"] = sensorMgr.isMotionDetected();
    doc["motion_age_s"] = sensorMgr.getMotionAgeSeconds();
    doc["motion_enabled"] = sensorMgr.isMotionEnabled();
    doc["probe_temp"] = serialized(String(sensorMgr.getProbeTemperature(), 1));
    doc["probe_fault"] = sensorMgr.isProbeFault();
    doc["probe_enabled"] = sensorMgr.isProbeEnabled();
    doc["distance_cm"] = serialized(String(sensorMgr.getDistanceCm(), 1));
    doc["tank_level_pct"] = sensorMgr.getTankLevelPercent();
    doc["tank_enabled"] = sensorMgr.isUltrasonicEnabled();
    doc["gas_raw"] = sensorMgr.getMQ2Raw();
    doc["gas_percent"] = sensorMgr.getMQ2Percent();
    doc["gas_max"] = MQ2_ADC_MAX;
    doc["gas_alarm"] = sensorMgr.isMQ2Alarm();
    doc["gas_enabled"] = sensorMgr.isMQ2Enabled();
    doc["gas_threshold"] = sensorMgr.getMQ2Threshold();
    doc["gas_warming"] = sensorMgr.isMQ2Warming();

    // Relays
    JsonArray relays = doc["relays"].to<JsonArray>();
    relayMgr.toJson(relays);
    for (uint8_t i = 0; i < relays.size(); i++) {
        String activeRule = ruleMgr.getActiveRuleForRelay(i);
        if (activeRule.length() > 0) {
            relays[i]["active_rule"] = activeRule;
        }
    }

    String output;
    output.reserve(measureJson(doc) + 1);
    serializeJson(doc, output);
    return output;
}

// ============================================================================
// Alarm action callback — dispatches alarm actions to modules
// ============================================================================
void onAlarmAction(AlarmAction action, uint8_t relay) {
    switch (action) {
        case ACTION_RELAY_ON:
            if (relay < relayMgr.getRelayCount()) relayMgr.setState(relay, true);
            break;
        case ACTION_RELAY_OFF:
            if (relay < relayMgr.getRelayCount()) relayMgr.setState(relay, false);
            break;
        case ACTION_RELAY_TOGGLE:
            if (relay < relayMgr.getRelayCount()) relayMgr.toggle(relay);
            break;
        case ACTION_BUZZER:
            buzzerMgr.startAlarm(BUZZER_ALARM_SCHEDULED);
            break;
        case ACTION_ALL_ON:
            relayMgr.allOn();
            break;
        case ACTION_ALL_OFF:
            relayMgr.allOff();
            break;
    }
    logger.logInfo("Alarm", "Scheduled action fired: " + String((int)action));
}

// ============================================================================
// Sensor alarm callback — dispatches alarms to buzzer and LCD
// ============================================================================
void onSensorAlarm(uint8_t alarmType, bool active) {
    if (active) {
        switch (alarmType) {
            case ALARM_TYPE_GAS:
                buzzerMgr.startAlarm(BUZZER_ALARM_GAS);
                lcdMgr.showAlarm(LCD_ALARM_GAS);
                logger.logCritical("Sensor", "GAS ALARM triggered!");
                wsMgr.broadcastAlarm("gas", true);
                break;
            case ALARM_TYPE_TEMP:
                buzzerMgr.startAlarm(BUZZER_ALARM_TEMP);
                lcdMgr.showAlarm(LCD_ALARM_TEMP);
                logger.logCritical("Sensor", "HIGH TEMPERATURE alarm!");
                wsMgr.broadcastAlarm("temperature", true);
                break;
            case ALARM_TYPE_SENSOR_FAULT:
                buzzerMgr.startAlarm(BUZZER_ALARM_FAULT);
                logger.logError("Sensor", "DHT22 sensor fault detected");
                wsMgr.broadcastAlarm("sensor_fault", true);
                // Activate failsafe relays
                relayMgr.activateFailsafe();
                break;
        }
    } else {
        // Alarm cleared
        buzzerMgr.stopAlarm();
        lcdMgr.clearAlarm();
        wsMgr.broadcastAlarm(
            alarmType == ALARM_TYPE_GAS ? "gas" :
            alarmType == ALARM_TYPE_TEMP ? "temperature" : "sensor_fault",
            false
        );
        logger.logInfo("Sensor", "Alarm cleared");
    }
}

// ============================================================================
// Relay state change callback — notify MQTT, WebSocket, logger
// ============================================================================
void onRelayChange(uint8_t index, bool state) {
    // Publish to MQTT
    mqttMgr.publishRelayState(index, state);

    // Broadcast via WebSocket (instant update)
    wsMgr.broadcastRelayChange(index, state);
    if (!relayMgr.hasActiveTimer(index)) {
        wsMgr.broadcastRelayTimer(index, false, false, 0);
    }

    // Log the event
    logger.logInfo("Relay", relayMgr.getName(index) + " → " + (state ? "ON" : "OFF"));
}

// ============================================================================
// MQTT relay command callback
// ============================================================================
void onMqttRelayCommand(uint8_t index, bool state) {
    relayMgr.setState(index, state);
}

// ============================================================================
// Wall switch action callback — handles Toggle, Follow, and Push-Button modes
// ============================================================================
void onWallSwitchAction(uint8_t index, uint8_t action) {
    if (action == SWITCH_ACTION_ON) {
        relayMgr.setState(index, true);
    } else if (action == SWITCH_ACTION_OFF) {
        relayMgr.setState(index, false);
    } else {
        relayMgr.toggle(index);
    }
    relayMgr.updateSwitchState(index);
    Serial.printf("[Main] Wall switch %d action %d → %s\n",
                  index + 1, action, relayMgr.getState(index) ? "ON" : "OFF");
}

void onWallSwitch(uint8_t index) {
    onWallSwitchAction(index, SWITCH_ACTION_TOGGLE);
}

// ============================================================================
// WiFi connection callback
// ============================================================================
void onWiFiConnect(bool connected) {
    if (connected) {
        logger.logInfo("WiFi", "Connected to " + wifiMgr.getSSID() + " (" + wifiMgr.getIP() + ")");
    } else {
        logger.logWarning("WiFi", "Disconnected");
    }
}

// ============================================================================
// Button callbacks
// ============================================================================
void onMultiButtonEvent(uint8_t event) {
    bool alarmActive = sensorMgr.hasAnyAlarm();

    if (alarmActive) {
        if (event == BUTTON_EVENT_DOWN) {
            buzzerMgr.mute();
            logger.logInfo("Button", "Buzzer muted via multi-button");
            wsMgr.broadcastToast("Buzzer muted for 5 minutes", "info");
        }
        return;
    }

    switch (event) {
        case BUTTON_EVENT_RELEASE_SHORT:
            lcdMgr.nextPage();
            break;

        case BUTTON_EVENT_HELD_3S:
            lcdMgr.showAlarm(LCD_ALARM_RESET_LIGHT);
            buzzerMgr.beepShort();
            break;

        case BUTTON_EVENT_HELD_6S:
            lcdMgr.showAlarm(LCD_ALARM_RESET_WIFI);
            buzzerMgr.beepShort();
            break;

        case BUTTON_EVENT_HELD_10S:
            lcdMgr.showAlarm(LCD_ALARM_RESET_FACT);
            buzzerMgr.beepLong();
            break;

        case BUTTON_EVENT_HELD_14S:
            lcdMgr.showAlarm(LCD_ALARM_RESET_CNCL);
            buzzerMgr.beepCancel();
            break;

        case BUTTON_EVENT_RELEASE_WIFI:
            lcdMgr.clearAlarm();
            logger.logWarning("Button", "WiFi reset via button");
            wifiMgr.resetWiFi();
            break;

        case BUTTON_EVENT_RELEASE_FACT:
            lcdMgr.clearAlarm();
            logger.logCritical("Button", "Factory reset via button");
            logger.persistNow();
            storage.factoryReset();
            ESP.restart();
            break;

        case BUTTON_EVENT_RELEASE_CANCEL:
            lcdMgr.clearAlarm();
            logger.logInfo("Button", "Reset cancelled");
            wsMgr.broadcastToast("Reset cancelled", "info");
            break;

        case BUTTON_EVENT_RELEASE_LONG:
            lcdMgr.clearAlarm();
            lcdMgr.setBacklight(!lcdMgr.getBacklight());
            logger.logInfo("Button", "LCD Backlight toggled via multi-button");
            break;
    }
}

// ============================================================================
// OTA callbacks
// ============================================================================
void onOTAStart() {
    logger.logInfo("OTA", "Update started");
    // Suspend competing network activity before OTA takes the socket
    mqttMgr.suspend();
    wsMgr.disconnectAll();   // Actively close WS connections first
    wsMgr.setEnabled(false); // Then prevent new activity
    storage.setWriteEnabled(false);
    Serial.println(F("[OTA] Network suspended, ready for upload"));
}

void onOTAProgress(int progress, int total) {
    int pct = (progress * 100) / total;
    static int lastLcdPct = -1;
    if (pct >= lastLcdPct + 10 || pct == 100) {
        lastLcdPct = pct;
        lcdMgr.showOTAProgress(pct);
    }
}

void onOTAEnd() {
    logger.logInfo("OTA", "Update complete, rebooting");
    // Note: For HTTP OTA, we do NOT resume MQTT/WS/Storage here because:
    // 1. The device is about to reboot (Ticker scheduled in WebServerManager)
    // 2. Resuming network services could generate traffic that competes with
    //    sending the HTTP 200 response to the browser
    // For ArduinoOTA, the OTA library handles the reboot after this callback,
    // but resuming is still harmless since reboot is immediate.
    // So we simply don't resume — the reboot will happen in ~1 second anyway.
}

void onOTAError(const String& error) {
    logger.logError("OTA", "Update failed: " + error);
    mqttMgr.resume();
    wsMgr.setEnabled(true);
    storage.setWriteEnabled(true);
    lcdMgr.clearAlarm();
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    // --- Serial ---
    Serial.begin(115200);
    while (!Serial && millis() < 2000) {} // Wait up to 2s for serial
    Serial.println();
    Serial.println(F("========================================"));
    Serial.printf("  %s v%s\n", FW_NAME, FW_VERSION);
    Serial.printf("  Build: %s %s\n", FW_BUILD_DATE, FW_BUILD_TIME);
    Serial.println(F("========================================"));

    // --- Watchdog ---
#if defined(ESP32)
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    esp_task_wdt_config_t wdt_config = {
        .timeout_ms = WDT_TIMEOUT_SECONDS * 1000,
        .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
        .trigger_panic = true
    };
    esp_task_wdt_init(&wdt_config);
#else
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true); // Enable panic on timeout
#endif
    esp_task_wdt_add(NULL); // Add current thread
#elif defined(ESP8266)
    ESP.wdtEnable(WDT_TIMEOUT_SECONDS * 1000);
#endif

    // --- Storage (must be first — other modules depend on it) ---
    if (!storage.begin()) {
        Serial.println(F("FATAL: Storage initialization failed!"));
        // Continue anyway — modules will use defaults
    }

    // --- Dynamic Hardware Profile Engine (loads /hardware.json or defaults) ---
    hwMgr.begin(storage);

    // --- Event Logger (early, so other modules can log during init) ---
    logger.begin(storage);
    logger.logInfo("System", String(FW_NAME) + " v" + FW_VERSION + " booting");

    // --- Diagnostics ---
    diag.begin();
    logger.logInfo("System", "Reset reason: " + diag.getResetReason());

    // --- LCD (show boot screen early) ---
    lcdMgr.begin(storage, timeMgr, hwMgr);
    JsonDocument cfgDoc;
    const char* devName = DEFAULT_DEVICE_NAME;
    if (storage.loadJson(PATH_CONFIG, cfgDoc)) {
        devName = cfgDoc["device_name"] | DEFAULT_DEVICE_NAME;
    }
    lcdMgr.showBootScreen(devName);

    // --- Sensors ---
    sensorMgr.begin(storage, hwMgr);
    sensorMgr.setAlarmCallback(onSensorAlarm);

    // --- Buzzer ---
    buzzerMgr.begin(storage, hwMgr);

    // --- Relays (init GPIOs + restore states BEFORE interrupts) ---
    relayMgr.begin(storage, hwMgr);
    relayMgr.setChangeCallback(onRelayChange);

    // --- Buttons & Wall Switches ---
    buttonMgr.begin(hwMgr);
    buttonMgr.setWallSwitchActionCallback(onWallSwitchAction);
    buttonMgr.setMultiButtonCallback(onMultiButtonEvent);

    // --- NOW initialize wall switch polling (after relay states are settled) ---
    buttonMgr.initWallSwitchPins(hwMgr);

    // --- Connect lockout callback so ButtonManager ignores switches during relay EMI ---
    buttonMgr.setLockoutCallback([]() -> bool {
        return relayMgr.isInLockout();
    });

    // --- WiFi ---
    wifiMgr.begin(storage);
    wifiMgr.setConnectCallback(onWiFiConnect);

    // --- Time (NTP — needs WiFi) ---
    timeMgr.begin(storage);

    // --- OTA ---
    bool enableArduinoOta = false;
    String otaAdminPass = "";
    JsonDocument otaCfg;
    if (storage.loadJson(PATH_CONFIG, otaCfg)) {
        enableArduinoOta = otaCfg["arduino_ota"] | false;
        otaAdminPass = otaCfg["web_pass"] | "";
    }
    otaMgr.begin(wifiMgr.getHostname(), enableArduinoOta, otaAdminPass);
    otaMgr.setStartCallback(onOTAStart);
    otaMgr.setProgressCallback(onOTAProgress);
    otaMgr.setEndCallback(onOTAEnd);
    otaMgr.setErrorCallback(onOTAError);

    // --- MQTT ---
    mqttMgr.begin(storage, logger);
    mqttMgr.setRelayCallback(onMqttRelayCommand);

    // --- Alarm Scheduler ---
    alarmSched.begin(storage);
    alarmSched.setActionCallback(onAlarmAction);

    // --- Sensor Automation Rules ---
    ruleMgr.begin(storage);

    // --- WebSocket ---
    wsMgr.begin(webServer.getServer());
    wsMgr.setDataProvider(wsDataProvider);
    wsMgr.setAuthValidator([](const String& user, const String& pass, const String& token) -> bool {
        if (!webServer.isAuthEnabled()) return true;
        if (webServer.verifyWsToken(token)) return true;
        return webServer.verifyCredentials(user, pass);
    });

    // --- Web Server (must be last — depends on all other modules) ---
    webServer.setWebSocketManager(wsMgr);
    webServer.begin(storage, wifiMgr, relayMgr, sensorMgr, buzzerMgr,
                    mqttMgr, timeMgr, lcdMgr, alarmSched, ruleMgr, logger, diag, otaMgr, hwMgr);

    // --- Boot complete ---
    logger.logInfo("System", "Boot complete. Free heap: " + String(diag.getFreeHeap()));

    Serial.println(F("========================================"));
    Serial.printf("  Boot complete in %lu ms\n", millis());
    Serial.printf("  Free Heap: %u bytes\n", ESP.getFreeHeap());
    Serial.printf("  IP: %s\n", wifiMgr.getIP().c_str());
    Serial.println(F("========================================"));
}

// ============================================================================
// MAIN LOOP — fully non-blocking
// ============================================================================
void loop() {
    // Feed watchdog
#if defined(ESP32)
    esp_task_wdt_reset();
#elif defined(ESP8266)
    ESP.wdtFeed();
#endif

    // --- OTA receives priority — only run essentials during upload ---
    otaMgr.loop();          // ArduinoOTA.handle()

    if (otaMgr.isUpdating()) {
        // Keep feeding WDT — OTA TCP receive can stall long enough to trigger a reset
#if defined(ESP32)
        esp_task_wdt_reset();
#elif defined(ESP8266)
        ESP.wdtFeed();
#endif
        yield();
        return;
    }

    // WiFi reconnect management runs only outside OTA (avoids disturbing the OTA TCP socket)
    wifiMgr.loop();

    // --- Normal runtime loops ---
    timeMgr.loop();         // NTP resync check
    sensorMgr.loop();       // DHT22 + MQ2 reads
    buzzerMgr.loop();       // Beep pattern state machine
    relayMgr.loop();        // Auto timers, wall switch flags, state persistence
    buttonMgr.loop();       // Debounce + press detection
    alarmSched.loop();      // Scheduled alarm check
    ruleMgr.loop(sensorMgr.getTemperature(), sensorMgr.getHumidity(), sensorMgr.isDHTFault(),
                 sensorMgr.getMQ2Raw(), sensorMgr.isMQ2Warming(),
                 sensorMgr.isLuxEnabled() ? sensorMgr.getLux() : -1.0f,
                 sensorMgr.getProbeTemperature(),
                 sensorMgr.isProbeFault() || !sensorMgr.isProbeEnabled(),
                 sensorMgr.isUltrasonicEnabled() ? sensorMgr.getTankLevelPercent() : -1,
                 relayMgr);
    mqttMgr.loop();         // MQTT reconnect
    lcdMgr.loop();          // Display update + page rotation
    logger.loop();          // Periodic persist + auto-clean
    diag.loop();            // Heap monitoring
    wsMgr.loop();           // WebSocket broadcast

    // --- Update LCD with current data ---
    static unsigned long lastLCDDataUpdate = 0;
    if (millis() - lastLCDDataUpdate >= 1000) {
        lastLCDDataUpdate = millis();

        // Sensor data for LCD
        lcdMgr.updateSensorData(sensorMgr.getTemperature(), sensorMgr.getHumidity(), sensorMgr.isDHTFault());

        // Relay states for LCD
        bool relayStates[MAX_RELAYS] = {false};
        for (uint8_t i = 0; i < relayMgr.getRelayCount() && i < MAX_RELAYS; i++) {
            relayStates[i] = relayMgr.getState(i);
        }
        lcdMgr.updateRelayStates(relayStates, relayMgr.getRelayCount());

        // Network info for LCD
        lcdMgr.updateNetworkInfo(wifiMgr.getIP(), timeMgr.getFormattedDate(), timeMgr.getDayOfWeek(),
                                 wifiMgr.isAPMode(), wifiMgr.getAPSSID(), wifiMgr.getAPPassword());

        // Gas data for LCD
        lcdMgr.updateGasData(sensorMgr.getMQ2Raw(), sensorMgr.getMQ2Threshold(),
                             sensorMgr.isMQ2Alarm(), sensorMgr.isMQ2Warming());

        // MQTT + uptime for LCD
        lcdMgr.updateMqttStatus(mqttMgr.isConnected(), diag.getUptimeString());
    }

    // --- Periodic MQTT sensor publish ---
    if (mqttMgr.isConnected()) {
        mqttMgr.publishSensorData(
            sensorMgr.getTemperature(),
            sensorMgr.getHumidity(),
            sensorMgr.getMQ2Raw(),
            sensorMgr.isMQ2Alarm(),
            sensorMgr.hasBarometer() ? sensorMgr.getPressure() : 0.0f,
            sensorMgr.isLuxEnabled() ? sensorMgr.getLux() : -1.0f,
            sensorMgr.isMotionDetected(),
            sensorMgr.isProbeEnabled() ? sensorMgr.getProbeTemperature() : -127.0f,
            sensorMgr.isUltrasonicEnabled() ? sensorMgr.getTankLevelPercent() : -1
        );
    }

    // --- Handle deferred reboot ---
    if (webServer.isRebootRequested() && (millis() - webServer.getRebootRequestTime() >= webServer.getRebootDelay())) {
        ESP.restart();
    }

    // --- Yield to prevent WDT on fast loop ---
    yield();
}
