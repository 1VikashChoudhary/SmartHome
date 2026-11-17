/*
 * ============================================================================
 * StorageManager.cpp — LittleFS Persistent Storage Implementation
 * ============================================================================
 */

#include "StorageManager.h"
#include "HardwareManager.h"

#if defined(ESP32)
namespace {
class RecursiveMutexGuard {
public:
    explicit RecursiveMutexGuard(SemaphoreHandle_t mtx) : _mtx(mtx) {
        if (_mtx) xSemaphoreTakeRecursive(_mtx, portMAX_DELAY);
    }
    ~RecursiveMutexGuard() {
        if (_mtx) xSemaphoreGiveRecursive(_mtx);
    }
private:
    SemaphoreHandle_t _mtx;
};
} // namespace

void StorageManager::ensureMutex() const {
    if (!_fsMutex) {
        _fsMutex = xSemaphoreCreateRecursiveMutex();
    }
}
#define STORAGE_LOCK() ensureMutex(); RecursiveMutexGuard _storageLockGuard(_fsMutex)
#else
#define STORAGE_LOCK() ((void)0)
#endif

// ============================================================================
// Constructor
// ============================================================================
StorageManager::StorageManager() : _initialized(false), _writeEnabled(true)
#if defined(ESP32)
    , _fsMutex(nullptr)
#endif
{}

// ============================================================================
// Initialize LittleFS
// ============================================================================
bool StorageManager::begin() {
    if (_initialized) return true;
#if defined(ESP32)
    ensureMutex();
#endif

#if defined(ESP32)
    // Initialize NVS flash for wear-leveled runtime states
    esp_err_t nvs_ret = nvs_flash_init();
    if (nvs_ret == ESP_ERR_NVS_NO_FREE_PAGES || nvs_ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    // Format LittleFS on first use (formatOnFail = true)
    if (!LittleFS.begin(true)) {
        Serial.println(F("[Storage] FATAL: LittleFS mount failed even after format!"));
        return false;
    }
#elif defined(ESP8266)
    // Initialize EEPROM emulation for wear-leveled runtime states
    EEPROM.begin(256);

    // Mount LittleFS with auto-format fallback
    if (!LittleFS.begin()) {
        Serial.println(F("[Storage] LittleFS mount failed, formatting flash..."));
        LittleFS.format();
        if (!LittleFS.begin()) {
            Serial.println(F("[Storage] FATAL: LittleFS mount failed even after format!"));
            return false;
        }
    }
#endif

    _initialized = true;

    SERIAL_PRINTF("[Storage] LittleFS mounted. Used: %u / %u bytes (%.1f%%)\n",
                  usedBytes(), totalBytes(), usagePercent());

    // Ensure default config files exist
    ensureDefaults();

    // Check for schema version migration
    migrateIfNeeded();

    return true;
}

// ============================================================================
// Load JSON file into ArduinoJson document
// ============================================================================
bool StorageManager::loadJson(const char* path, JsonDocument& doc) {
    if (!_initialized) return false;
    STORAGE_LOCK();

    String bakPath = String(path) + ".bak";
    bool mainExists = LittleFS.exists(path);
    if (!mainExists && !LittleFS.exists(bakPath)) {
        SERIAL_PRINTF("[Storage] File not found: %s\n", path);
        return false;
    }

    auto tryParseFile = [&](const char* targetPath) -> bool {
        File file = LittleFS.open(targetPath, "r");
        if (!file) return false;
        doc.clear();
        DeserializationError error = deserializeJson(doc, file);
        file.close();
        if (error) {
            SERIAL_PRINTF("[Storage] JSON parse error in %s: %s\n", targetPath, error.c_str());
            return false;
        }
        return true;
    };

    if (mainExists && tryParseFile(path)) {
        return true;
    }

    if (LittleFS.exists(bakPath) && tryParseFile(bakPath.c_str())) {
        SERIAL_PRINTF("[Storage] Recovered %s from backup %s\n", path, bakPath.c_str());
        if (_writeEnabled) {
            LittleFS.remove(path);
            LittleFS.rename(bakPath, path);
        }
        return true;
    }

    return false;
}

// ============================================================================
// Save JsonDocument to file (safe write: temp file + rename)
// ============================================================================
bool StorageManager::saveJson(const char* path, const JsonDocument& doc) {
    if (!_initialized) return false;
    STORAGE_LOCK();
    if (!_writeEnabled) {
        SERIAL_PRINTF("[Storage] Write blocked during OTA: %s\n", path);
        return false;
    }

    // Serialize to string first
    String content;
    content.reserve(measureJson(doc) + 1);
    serializeJson(doc, content);

    return writeFile(path, content);
}

// ============================================================================
// Check if file exists
// ============================================================================
bool StorageManager::fileExists(const char* path) {
    if (!_initialized) return false;
    STORAGE_LOCK();
    if (LittleFS.exists(path)) return true;
    String bakPath = String(path) + ".bak";
    return LittleFS.exists(bakPath);
}

// ============================================================================
// Delete a file
// ============================================================================
bool StorageManager::deleteFile(const char* path) {
    if (!_initialized) return false;
    STORAGE_LOCK();
    if (!_writeEnabled) {
        SERIAL_PRINTF("[Storage] Delete blocked during OTA: %s\n", path);
        return false;
    }

    String bakPath = String(path) + ".bak";
    if (LittleFS.exists(bakPath)) LittleFS.remove(bakPath);
    if (LittleFS.exists(path)) {
        bool ok = LittleFS.remove(path);
        SERIAL_PRINTF("[Storage] Delete %s: %s\n", path, ok ? "OK" : "FAIL");
        return ok;
    }
    return true; // Already gone
}

void StorageManager::setWriteEnabled(bool enabled) {
    _writeEnabled = enabled;
    SERIAL_PRINTF("[Storage] Writes %s\n", enabled ? "enabled" : "disabled");
}

bool StorageManager::isWriteEnabled() const {
    return _writeEnabled;
}

// ============================================================================
// Export ALL config files as a single JSON backup
// ============================================================================
String StorageManager::exportAllConfig(bool redactSecrets) {
    STORAGE_LOCK();
    JsonDocument doc;

    // List of static config file paths to export from LittleFS
    const char* configFiles[] = {
        PATH_CONFIG, PATH_HARDWARE, PATH_WIFI, PATH_MQTT, PATH_RELAYS,
        PATH_SENSORS, PATH_ALARMS, PATH_RULES, PATH_LCD, PATH_BUZZER
    };

    for (const char* path : configFiles) {
        if (LittleFS.exists(path)) {
            JsonDocument subDoc;
            if (loadJson(path, subDoc)) {
                // Use the filename (without leading /) as the key
                const char* key = path + 1; // Skip leading '/'

                // Optional redaction for diagnostics sharing (disabled by default for true backups)
                if (redactSecrets) {
                    if (strcmp(path, PATH_WIFI) == 0 && subDoc.containsKey("networks")) {
                        JsonArray arr = subDoc["networks"].as<JsonArray>();
                        for (JsonObject net : arr) {
                            if (net.containsKey("pass")) net["pass"] = "__REDACTED__";
                        }
                    } else if (strcmp(path, PATH_MQTT) == 0 && subDoc.containsKey("pass")) {
                        subDoc["pass"] = "__REDACTED__";
                    } else if (strcmp(path, PATH_CONFIG) == 0) {
                        if (subDoc.containsKey("web_pass")) subDoc["web_pass"] = "__REDACTED__";
                        if (subDoc.containsKey("guest_pass")) subDoc["guest_pass"] = "__REDACTED__";
                        if (subDoc.containsKey("web_pass_hash")) subDoc["web_pass_hash"] = "__REDACTED__";
                        if (subDoc.containsKey("guest_pass_hash")) subDoc["guest_pass_hash"] = "__REDACTED__";
                        if (subDoc.containsKey("ota_pass_md5")) subDoc["ota_pass_md5"] = "__REDACTED__";
                        if (subDoc.containsKey("ap_pass")) subDoc["ap_pass"] = "__REDACTED__";
                    }
                }

                doc[key] = subDoc;
            }
        }
    }

    // Synthesize relay_states from wear-leveled NVS so backups remain complete
    bool nvsLogical[MAX_RELAYS] = {0};
    bool nvsSwitch[MAX_RELAYS] = {0};
    if (loadRelayStatesNVS(nvsLogical, nvsSwitch, MAX_RELAYS)) {
        JsonObject rsDoc = doc["relay_states.json"].to<JsonObject>();
        JsonArray arr = rsDoc["states"].to<JsonArray>();
        for (uint8_t i = 0; i < MAX_RELAYS; i++) {
            JsonObject s = arr.add<JsonObject>();
            s["on"] = nvsLogical[i];
            s["sw"] = nvsSwitch[i];
        }
    }

    doc["_backup_version"] = CONFIG_SCHEMA_VERSION;
    time_t now = time(nullptr);
    doc["_backup_date"] = (now > 1600000000) ? (uint32_t)now : (uint32_t)millis();
#if defined(ESP8266)
    doc["_chip"] = "ESP8266";
#else
    doc["_chip"] = "ESP32";
#endif

    String output;
    output.reserve(measureJson(doc) + 1);
    serializeJson(doc, output);
    return output;
}

// ============================================================================
// Import a config backup blob
// ============================================================================
bool StorageManager::importAllConfig(JsonObjectConst doc) {
    if (!_initialized || !_writeEnabled) return false;
    STORAGE_LOCK();

    // Map of key names to file paths
    struct ConfigMapping {
        const char* key;
        const char* altKey;
        const char* path;
        bool wipeIfMissingInFullBackup;
    };

    const ConfigMapping mappings[] = {
        {"config.json",       "config",       PATH_CONFIG,       false},
        {"hardware.json",     "hardware",     PATH_HARDWARE,     false},
        {"wifi.json",         "wifi",         PATH_WIFI,         false},
        {"mqtt.json",         "mqtt",         PATH_MQTT,         true},
        {"relays.json",       "relays",       PATH_RELAYS,       true},
        {"relay_states.json", "relay_states", PATH_RELAY_STATES, true},
        {"sensors.json",      "sensors",      PATH_SENSORS,      true},
        {"alarms.json",       "alarms",       PATH_ALARMS,       true},
        {"rules.json",        "rules",        PATH_RULES,        true},
        {"lcd.json",          "lcd",          PATH_LCD,          true},
        {"buzzer.json",       "buzzer",       PATH_BUZZER,       true}
    };

    // Determine whether this is a full system backup snapshot
    bool isFullBackup = doc.containsKey("_backup_version") ||
                        doc.containsKey("config.json") ||
                        doc.containsKey("config");

    int restored = 0;
    for (const auto& m : mappings) {
        const char* matchedKey = nullptr;
        if (doc.containsKey(m.key)) {
            matchedKey = m.key;
        } else if (m.altKey && doc.containsKey(m.altKey)) {
            matchedKey = m.altKey;
        }

        if (matchedKey != nullptr) {
            if (!doc[matchedKey].is<JsonObjectConst>()) {
                SERIAL_PRINTF("[Storage] Skipping invalid non-object section: %s\n", matchedKey);
                continue;
            }
            JsonDocument subDoc;
            subDoc.set(doc[matchedKey]);

            // Validate architecture compatibility for hardware.json
            if (strcmp(m.path, PATH_HARDWARE) == 0) {
#if defined(ESP8266)
                auto isValid8266DigitalPin = [](uint8_t p) -> bool {
                    return p == PIN_UNUSED || (p <= 16 && p != 1 && p != 3 && !(p >= 6 && p <= 11));
                };
                bool isEsp8266Compatible = true;
                const char* bChip = doc["_chip"] | "";
                if (strcmp(bChip, "ESP32") == 0) {
                    isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("channels")) {
                    for (JsonObjectConst ch : subDoc["channels"].as<JsonArrayConst>()) {
                        if (!(ch["enabled"] | true)) continue;
                        uint8_t rp = ch["relay_pin"] | PIN_UNUSED;
                        uint8_t sp = ch["switch_pin"] | PIN_UNUSED;
                        bool swEn = ch["switch_enabled"] | true;
                        if (!isValid8266DigitalPin(rp) || (swEn && !isValid8266DigitalPin(sp))) {
                            isEsp8266Compatible = false;
                            break;
                        }
                    }
                }
                bool anyI2c = (subDoc["lcd"]["enabled"] | false);
                if (subDoc.containsKey("climates")) {
                    for (JsonObjectConst c : subDoc["climates"].as<JsonArrayConst>()) {
                        uint8_t dt = c["type"] | 0;
                        uint8_t dp = c["pin"] | PIN_UNUSED;
                        if (dt > 7) {
                            isEsp8266Compatible = false;
                        } else if (dt == 1 || dt == 2 || dt == 7) {
                            if (!isValid8266DigitalPin(dp)) isEsp8266Compatible = false;
                        } else if (dt >= 3) {
                            anyI2c = true;
                        }
                    }
                } else {
                    uint8_t dhtType = subDoc["dht"]["type"] | 0;
                    uint8_t dhtPin = subDoc["dht"]["pin"] | PIN_UNUSED;
                    if (dhtType > 7) {
                        isEsp8266Compatible = false;
                    } else if (dhtType == 1 || dhtType == 2 || dhtType == 7) {
                        if (!isValid8266DigitalPin(dhtPin)) isEsp8266Compatible = false;
                    } else if (dhtType >= 3) {
                        anyI2c = true;
                    }
                }
                if (subDoc.containsKey("lights")) {
                    for (JsonObjectConst l : subDoc["lights"].as<JsonArrayConst>()) {
                        if ((l["type"] | 0) == 1) anyI2c = true;
                    }
                } else if ((subDoc["light"]["type"] | 0) == 1) {
                    anyI2c = true;
                }
                if (subDoc.containsKey("motions")) {
                    for (JsonObjectConst mot : subDoc["motions"].as<JsonArrayConst>()) {
                        if ((mot["type"] | 0) != 0 && !isValid8266DigitalPin(mot["pin"] | PIN_UNUSED)) isEsp8266Compatible = false;
                    }
                } else {
                    uint8_t motionType = subDoc["motion"]["type"] | 0;
                    uint8_t motionPin = subDoc["motion"]["pin"] | PIN_UNUSED;
                    if (motionType != 0 && !isValid8266DigitalPin(motionPin)) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("probes")) {
                    for (JsonObjectConst prb : subDoc["probes"].as<JsonArrayConst>()) {
                        if ((prb["type"] | 0) != 0 && !isValid8266DigitalPin(prb["pin"] | PIN_UNUSED)) isEsp8266Compatible = false;
                    }
                } else {
                    uint8_t probeType = subDoc["probe"]["type"] | 0;
                    uint8_t probePin = subDoc["probe"]["pin"] | PIN_UNUSED;
                    if (probeType != 0 && !isValid8266DigitalPin(probePin)) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("ultrasonics")) {
                    for (JsonObjectConst us : subDoc["ultrasonics"].as<JsonArrayConst>()) {
                        if ((us["type"] | 0) != 0 && (!isValid8266DigitalPin(us["trig_pin"] | PIN_UNUSED) || !isValid8266DigitalPin(us["echo_pin"] | PIN_UNUSED))) {
                            isEsp8266Compatible = false;
                        }
                    }
                } else {
                    uint8_t usType = subDoc["ultrasonic"]["type"] | 0;
                    uint8_t trigPin = subDoc["ultrasonic"]["trig_pin"] | PIN_UNUSED;
                    uint8_t echoPin = subDoc["ultrasonic"]["echo_pin"] | PIN_UNUSED;
                    if (usType != 0 && (!isValid8266DigitalPin(trigPin) || !isValid8266DigitalPin(echoPin))) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("mq2_sensors")) {
                    for (JsonObjectConst g : subDoc["mq2_sensors"].as<JsonArrayConst>()) {
                        if (!(g["enabled"] | true)) continue;
                        uint8_t gt = g["type"] | 0;
                        if (gt == 1) { // SGP40 (I2C)
                            anyI2c = true;
                        } else if (gt == 0) { // MQ-2 (Analog/Digital)
                            uint8_t ap = g["analog_pin"] | PIN_UNUSED;
                            uint8_t dp = g["digital_pin"] | PIN_UNUSED;
                            if ((ap != PIN_UNUSED && ap != 17) || !isValid8266DigitalPin(dp)) isEsp8266Compatible = false;
                        } else {
                            isEsp8266Compatible = false;
                        }
                    }
                } else if (subDoc["mq2"]["enabled"] | false) {
                    uint8_t ap = subDoc["mq2"]["analog_pin"] | PIN_UNUSED;
                    uint8_t dp = subDoc["mq2"]["digital_pin"] | PIN_UNUSED;
                    if ((ap != PIN_UNUSED && ap != 17) || !isValid8266DigitalPin(dp)) isEsp8266Compatible = false;
                }
                if (anyI2c) {
                    uint8_t sda = subDoc["lcd"]["sda_pin"] | PIN_UNUSED;
                    uint8_t scl = subDoc["lcd"]["scl_pin"] | PIN_UNUSED;
                    bool explicitI2cPins = subDoc["lcd"].containsKey("sda_pin") && subDoc["lcd"].containsKey("scl_pin");
                    if (!isValid8266DigitalPin(sda) || !isValid8266DigitalPin(scl) ||
                        (explicitI2cPins && (sda == PIN_UNUSED || scl == PIN_UNUSED || sda == scl))) {
                        isEsp8266Compatible = false;
                    }
                }
                if (subDoc["buzzer"]["enabled"] | false) {
                    uint8_t bp = subDoc["buzzer"]["pin"] | PIN_UNUSED;
                    if (!isValid8266DigitalPin(bp)) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("btn_multi_pin")) {
                    uint8_t bmp = subDoc["btn_multi_pin"] | PIN_UNUSED;
                    if (!isValid8266DigitalPin(bmp)) isEsp8266Compatible = false;
                }
                if (!isEsp8266Compatible) {
                    Serial.println(F("[Storage] Notice: Backup hardware profile belongs to ESP32 (or has invalid ESP8266 GPIOs). Preserving current valid ESP8266 hardware configuration."));
                    continue; // Skip saving hardware.json, preserve existing valid hardware configuration
                }
#elif defined(ESP32)
                auto isValidEsp32OutPin = [](uint8_t p) -> bool {
                    return p == PIN_UNUSED ||
                           (p < 40 && p != 0 && p != 1 && p != 3 && !(p >= 6 && p <= 11) &&
                            p != 34 && p != 35 && p != 36 && p != 39);
                };
                auto isValidEsp32InPin = [](uint8_t p) -> bool {
                    return p == PIN_UNUSED ||
                           (p < 40 && p != 1 && p != 3 && !(p >= 6 && p <= 11));
                };
                bool isEsp32Compatible = true;
                const char* bChip = doc["_chip"] | "";
                if (strcmp(bChip, "ESP8266") == 0) {
                    isEsp32Compatible = false;
                }
                const char* bName = subDoc["board_name"] | "";
                if (strstr(bName, "ESP8266") != nullptr) {
                    isEsp32Compatible = false;
                }
                if (subDoc.containsKey("channels")) {
                    for (JsonObjectConst ch : subDoc["channels"].as<JsonArrayConst>()) {
                        if (!(ch["enabled"] | true)) continue;
                        uint8_t rp = ch["relay_pin"] | PIN_UNUSED;
                        uint8_t sp = ch["switch_pin"] | PIN_UNUSED;
                        bool swEn = ch["switch_enabled"] | true;
                        if (!isValidEsp32OutPin(rp) || (swEn && !isValidEsp32InPin(sp))) {
                            isEsp32Compatible = false;
                            break;
                        }
                    }
                }
                bool anyI2c = (subDoc["lcd"]["enabled"] | false);
                if (subDoc.containsKey("climates")) {
                    for (JsonObjectConst c : subDoc["climates"].as<JsonArrayConst>()) {
                        uint8_t dt = c["type"] | 0;
                        uint8_t dp = c["pin"] | PIN_UNUSED;
                        if (dt > 7) {
                            isEsp32Compatible = false;
                        } else if (dt == 1 || dt == 2 || dt == 7) {
                            if (!isValidEsp32OutPin(dp)) isEsp32Compatible = false;
                        } else if (dt >= 3) {
                            anyI2c = true;
                        }
                    }
                } else {
                    uint8_t dhtType = subDoc["dht"]["type"] | 0;
                    uint8_t dhtPin = subDoc["dht"]["pin"] | PIN_UNUSED;
                    if (dhtType > 7) {
                        isEsp32Compatible = false;
                    } else if (dhtType == 1 || dhtType == 2 || dhtType == 7) {
                        if (!isValidEsp32OutPin(dhtPin)) isEsp32Compatible = false;
                    } else if (dhtType >= 3) {
                        anyI2c = true;
                    }
                }
                if (subDoc.containsKey("lights")) {
                    for (JsonObjectConst l : subDoc["lights"].as<JsonArrayConst>()) {
                        if ((l["type"] | 0) == 1) anyI2c = true;
                    }
                } else if ((subDoc["light"]["type"] | 0) == 1) {
                    anyI2c = true;
                }
                if (subDoc.containsKey("motions")) {
                    for (JsonObjectConst mot : subDoc["motions"].as<JsonArrayConst>()) {
                        if ((mot["type"] | 0) != 0 && !isValidEsp32InPin(mot["pin"] | PIN_UNUSED)) isEsp32Compatible = false;
                    }
                } else {
                    uint8_t motionType = subDoc["motion"]["type"] | 0;
                    uint8_t motionPin = subDoc["motion"]["pin"] | PIN_UNUSED;
                    if (motionType != 0 && !isValidEsp32InPin(motionPin)) isEsp32Compatible = false;
                }
                if (subDoc.containsKey("probes")) {
                    for (JsonObjectConst prb : subDoc["probes"].as<JsonArrayConst>()) {
                        if ((prb["type"] | 0) != 0 && !isValidEsp32OutPin(prb["pin"] | PIN_UNUSED)) isEsp32Compatible = false;
                    }
                } else {
                    uint8_t probeType = subDoc["probe"]["type"] | 0;
                    uint8_t probePin = subDoc["probe"]["pin"] | PIN_UNUSED;
                    if (probeType != 0 && !isValidEsp32OutPin(probePin)) isEsp32Compatible = false;
                }
                if (subDoc.containsKey("ultrasonics")) {
                    for (JsonObjectConst us : subDoc["ultrasonics"].as<JsonArrayConst>()) {
                        if ((us["type"] | 0) != 0 && (!isValidEsp32OutPin(us["trig_pin"] | PIN_UNUSED) || !isValidEsp32InPin(us["echo_pin"] | PIN_UNUSED))) {
                            isEsp32Compatible = false;
                        }
                    }
                } else {
                    uint8_t usType = subDoc["ultrasonic"]["type"] | 0;
                    uint8_t trigPin = subDoc["ultrasonic"]["trig_pin"] | PIN_UNUSED;
                    uint8_t echoPin = subDoc["ultrasonic"]["echo_pin"] | PIN_UNUSED;
                    if (usType != 0 && (!isValidEsp32OutPin(trigPin) || !isValidEsp32InPin(echoPin))) isEsp32Compatible = false;
                }
                if (subDoc.containsKey("mq2_sensors")) {
                    for (JsonObjectConst g : subDoc["mq2_sensors"].as<JsonArrayConst>()) {
                        if (!(g["enabled"] | true)) continue;
                        uint8_t gt = g["type"] | 0;
                        if (gt == 1) { // SGP40 (I2C)
                            anyI2c = true;
                        } else if (gt == 0) { // MQ-2 (Analog/Digital)
                            uint8_t ap = g["analog_pin"] | PIN_UNUSED;
                            uint8_t dp = g["digital_pin"] | PIN_UNUSED;
                            if (ap == 17 || !isValidEsp32InPin(ap) || !isValidEsp32InPin(dp)) isEsp32Compatible = false;
                        } else {
                            isEsp32Compatible = false;
                        }
                    }
                } else if (subDoc["mq2"]["enabled"] | false) {
                    uint8_t ap = subDoc["mq2"]["analog_pin"] | PIN_UNUSED;
                    uint8_t dp = subDoc["mq2"]["digital_pin"] | PIN_UNUSED;
                    if (ap == 17 || !isValidEsp32InPin(ap) || !isValidEsp32InPin(dp)) isEsp32Compatible = false;
                }
                if (anyI2c) {
                    uint8_t sda = subDoc["lcd"]["sda_pin"] | PIN_UNUSED;
                    uint8_t scl = subDoc["lcd"]["scl_pin"] | PIN_UNUSED;
                    bool explicitI2cPins = subDoc["lcd"].containsKey("sda_pin") && subDoc["lcd"].containsKey("scl_pin");
                    if (!isValidEsp32OutPin(sda) || !isValidEsp32OutPin(scl) ||
                        (explicitI2cPins && (sda == PIN_UNUSED || scl == PIN_UNUSED || sda == scl))) {
                        isEsp32Compatible = false;
                    }
                }
                if (subDoc["buzzer"]["enabled"] | false) {
                    uint8_t bp = subDoc["buzzer"]["pin"] | PIN_UNUSED;
                    if (!isValidEsp32OutPin(bp)) isEsp32Compatible = false;
                }
                if (subDoc.containsKey("btn_multi_pin")) {
                    uint8_t bmp = subDoc["btn_multi_pin"] | PIN_UNUSED;
                    if (!isValidEsp32InPin(bmp)) isEsp32Compatible = false;
                }
                if (!isEsp32Compatible) {
                    Serial.println(F("[Storage] Notice: Backup hardware profile belongs to ESP8266 (or has invalid ESP32 GPIOs). Preserving current valid ESP32 hardware configuration."));
                    continue;
                }
#endif
                String hwErr;
                if (!HardwareManager::validateHardwareJson(subDoc.as<JsonObjectConst>(), hwErr)) {
                    SERIAL_PRINTF("[Storage] Invalid hardware profile in backup (%s). Preserving current config.\n", hwErr.c_str());
                    continue;
                }
            }

            // Preserve local secrets if the restored backup was sanitized with __REDACTED__
            if (strcmp(m.path, PATH_WIFI) == 0 && LittleFS.exists(PATH_WIFI)) {
                JsonDocument existing;
                if (loadJson(PATH_WIFI, existing) && existing.containsKey("networks") && subDoc.containsKey("networks")) {
                    JsonArray newArr = subDoc["networks"].as<JsonArray>();
                    JsonArray oldArr = existing["networks"].as<JsonArray>();
                    // Robust matching by SSID rather than fragile array index
                    for (JsonObject newNet : newArr) {
                        if (newNet["pass"] == "__REDACTED__") {
                            const char* ssid = newNet["ssid"] | "";
                            bool matched = false;
                            for (JsonObject oldNet : oldArr) {
                                if (strcmp(oldNet["ssid"] | "", ssid) == 0 && oldNet.containsKey("pass")) {
                                    newNet["pass"] = oldNet["pass"];
                                    matched = true;
                                    break;
                                }
                            }
                            if (!matched) {
                                newNet.remove("pass"); // Never write literal __REDACTED__ to flash
                            }
                        }
                    }
                }
            } else if (strcmp(m.path, PATH_MQTT) == 0 && LittleFS.exists(PATH_MQTT)) {
                if (subDoc["pass"] == "__REDACTED__") {
                    JsonDocument existing;
                    if (loadJson(PATH_MQTT, existing) && existing.containsKey("pass") && existing["pass"] != "__REDACTED__") {
                        subDoc["pass"] = existing["pass"];
                    } else {
                        subDoc.remove("pass");
                    }
                }
            } else if (strcmp(m.path, PATH_CONFIG) == 0 && LittleFS.exists(PATH_CONFIG)) {
                if (subDoc["web_pass"] == "__REDACTED__" || subDoc["web_pass_hash"] == "__REDACTED__" ||
                    subDoc["guest_pass"] == "__REDACTED__" || subDoc["guest_pass_hash"] == "__REDACTED__" ||
                    subDoc["ota_pass_md5"] == "__REDACTED__" || subDoc["ap_pass"] == "__REDACTED__") {
                    JsonDocument existing;
                    if (loadJson(PATH_CONFIG, existing)) {
                        if (subDoc["web_pass_hash"] == "__REDACTED__") {
                            if (existing.containsKey("web_pass_hash") && existing["web_pass_hash"] != "__REDACTED__") {
                                subDoc["web_pass_hash"] = existing["web_pass_hash"];
                            } else {
                                subDoc.remove("web_pass_hash");
                            }
                        }
                        if (subDoc["web_pass"] == "__REDACTED__") {
                            if (existing.containsKey("web_pass") && existing["web_pass"] != "__REDACTED__") {
                                subDoc["web_pass"] = existing["web_pass"];
                            } else {
                                subDoc.remove("web_pass");
                            }
                        }
                        if (subDoc["guest_pass_hash"] == "__REDACTED__") {
                            if (existing.containsKey("guest_pass_hash") && existing["guest_pass_hash"] != "__REDACTED__") {
                                subDoc["guest_pass_hash"] = existing["guest_pass_hash"];
                            } else {
                                subDoc.remove("guest_pass_hash");
                            }
                        }
                        if (subDoc["guest_pass"] == "__REDACTED__") {
                            if (existing.containsKey("guest_pass") && existing["guest_pass"] != "__REDACTED__") {
                                subDoc["guest_pass"] = existing["guest_pass"];
                            } else {
                                subDoc.remove("guest_pass");
                            }
                        }
                        if (subDoc["ota_pass_md5"] == "__REDACTED__") {
                            if (existing.containsKey("ota_pass_md5") && existing["ota_pass_md5"] != "__REDACTED__") {
                                subDoc["ota_pass_md5"] = existing["ota_pass_md5"];
                            } else {
                                subDoc.remove("ota_pass_md5");
                            }
                        }
                        if (subDoc["ap_pass"] == "__REDACTED__") {
                            if (existing.containsKey("ap_pass") && existing["ap_pass"] != "__REDACTED__") {
                                subDoc["ap_pass"] = existing["ap_pass"];
                            } else {
                                subDoc.remove("ap_pass");
                            }
                        }
                    } else {
                        if (subDoc["web_pass_hash"] == "__REDACTED__") subDoc.remove("web_pass_hash");
                        if (subDoc["web_pass"] == "__REDACTED__") subDoc.remove("web_pass");
                        if (subDoc["guest_pass_hash"] == "__REDACTED__") subDoc.remove("guest_pass_hash");
                        if (subDoc["guest_pass"] == "__REDACTED__") subDoc.remove("guest_pass");
                        if (subDoc["ota_pass_md5"] == "__REDACTED__") subDoc.remove("ota_pass_md5");
                        if (subDoc["ap_pass"] == "__REDACTED__") subDoc.remove("ap_pass");
                    }
                }
            } else if (strcmp(m.path, PATH_RELAY_STATES) == 0 && subDoc.containsKey("states")) {
                // Synchronize saved wall-switch baselines ("sw") with the current physical
                // GPIO pin states so RelayManager::initWallSwitchStates() on reboot does not
                // misinterpret a difference between backup-time switch position and current
                // switch position as a power-outage toggle and invert restored relay states!
                JsonArray statesArr = subDoc["states"].as<JsonArray>();
                uint8_t swPins[MAX_RELAYS];
                for (uint8_t i = 0; i < MAX_RELAYS; i++) {
                    swPins[i] = (i < NUM_RELAYS) ? SWITCH_PINS[i] : PIN_UNUSED;
                }
                if (LittleFS.exists(PATH_HARDWARE)) {
                    JsonDocument hwDoc;
                    if (loadJson(PATH_HARDWARE, hwDoc) && hwDoc.containsKey("channels")) {
                        JsonArray chs = hwDoc["channels"].as<JsonArray>();
                        for (uint8_t i = 0; i < MAX_RELAYS && i < chs.size(); i++) {
                            bool swEn = chs[i]["switch_enabled"] | true;
                            bool chEn = chs[i]["enabled"] | true;
                            if (chEn && swEn) {
                                swPins[i] = chs[i]["switch_pin"] | PIN_UNUSED;
                            } else {
                                swPins[i] = PIN_UNUSED;
                            }
                        }
                    }
                }

                bool logical[MAX_RELAYS] = {0};
                bool wallSw[MAX_RELAYS] = {0};
                uint8_t idx = 0;
                for (JsonObject s : statesArr) {
                    if (idx >= MAX_RELAYS) break;
                    logical[idx] = s["on"] | false;
                    uint8_t pin = swPins[idx];
                    if (pin != PIN_UNUSED) {
#if defined(ESP8266)
                        if (pin <= 16 && pin != 1 && pin != 3 && !(pin >= 6 && pin <= 11)) {
                            if (pin == 16) {
                                pinMode(pin, INPUT); // GPIO 16 has no internal pullup
                            } else {
                                pinMode(pin, INPUT_PULLUP);
                            }
                            wallSw[idx] = !digitalRead(pin);
                        } else {
                            wallSw[idx] = s["sw"] | false;
                        }
#else
                        if (pin < 40 && pin != 1 && pin != 3 && !(pin >= 6 && pin <= 11)) {
                            if (pin >= 34 && pin <= 39) {
                                pinMode(pin, INPUT);
                            } else {
                                pinMode(pin, INPUT_PULLUP);
                            }
                            wallSw[idx] = !digitalRead(pin);
                        } else {
                            wallSw[idx] = s["sw"] | false;
                        }
#endif
                    } else {
                        wallSw[idx] = s["sw"] | false;
                    }
                    idx++;
                }

                // Restore directly into wear-leveled NVS (bypassing LittleFS entirely)
                saveRelayStatesNVS(logical, wallSw, idx > 0 ? idx : MAX_RELAYS);
                if (LittleFS.exists(PATH_RELAY_STATES)) {
                    deleteFile(PATH_RELAY_STATES);
                }
                restored++;
                Serial.println(F("[Storage-NVS] Restored relay states into wear-leveled NVS."));
                continue; // Do not write to LittleFS
            }

            if (saveJson(m.path, subDoc)) {
                restored++;
                SERIAL_PRINTF("[Storage] Restored: %s\n", m.path);
            }
        } else if (isFullBackup && m.wipeIfMissingInFullBackup) {
            // If this is a full backup and an optional module file was not present when
            // the backup was created (meaning the module was at factory defaults), wipe
            // any subsequently created state/file so the module genuinely reverts to default!
            if (strcmp(m.path, PATH_RELAY_STATES) == 0) {
                clearNVSState();
                restored++;
                Serial.println(F("[Storage-NVS] Cleared relay states in NVS (missing in full backup)."));
            }
            if (LittleFS.exists(m.path) && deleteFile(m.path)) {
                restored++;
                SERIAL_PRINTF("[Storage] Removed post-backup config to restore default state: %s\n", m.path);
            }
        }
    }

    SERIAL_PRINTF("[Storage] Import complete: %d files applied\n", restored);
    return restored > 0;
}

bool StorageManager::importAllConfig(const String& jsonBlob) {
    if (jsonBlob.length() == 0) return false;
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, jsonBlob);
    if (error) {
        SERIAL_PRINTF("[Storage] Import parse error: %s\n", error.c_str());
        return false;
    }
    return importAllConfig(doc.as<JsonObjectConst>());
}

// ============================================================================
// Factory Reset — delete all config files
// ============================================================================
void StorageManager::factoryReset() {
    STORAGE_LOCK();
    Serial.println(F("[Storage] === FACTORY RESET ==="));

    const char* allFiles[] = {
        PATH_CONFIG, PATH_HARDWARE, PATH_WIFI, PATH_MQTT, PATH_RELAYS,
        PATH_RELAY_STATES, PATH_SENSORS, PATH_ALARMS,
        PATH_RULES, PATH_LCD, PATH_BUZZER, PATH_LOGS
    };

    for (const char* path : allFiles) {
        deleteFile(path);
    }

    clearNVSState();
    Serial.println(F("[Storage] All config files and NVS state cleared. Reboot to apply."));
}

// ============================================================================
// Filesystem usage info
// ============================================================================
size_t StorageManager::usedBytes() {
    if (!_initialized) return 0;
#if defined(ESP8266)
    FSInfo fs_info;
    if (LittleFS.info(fs_info)) return fs_info.usedBytes;
    return 0;
#else
    return LittleFS.usedBytes();
#endif
}

size_t StorageManager::totalBytes() {
    if (!_initialized) return 1; // Avoid divide by zero
#if defined(ESP8266)
    FSInfo fs_info;
    if (LittleFS.info(fs_info)) return fs_info.totalBytes;
    return 1;
#else
    return LittleFS.totalBytes();
#endif
}

float StorageManager::usagePercent() {
    return (float)usedBytes() / (float)totalBytes() * 100.0f;
}

// ============================================================================
// Migrate config files from older schema versions
// ============================================================================
void StorageManager::migrateIfNeeded() {
    // 1. Schema version migration
    JsonDocument doc;
    if (loadJson(PATH_CONFIG, doc)) {
        int version = doc["schema_version"] | 0;
        if (version < CONFIG_SCHEMA_VERSION) {
            SERIAL_PRINTF("[Storage] Migrating config from v%d to v%d\n",
                          version, CONFIG_SCHEMA_VERSION);

            doc["schema_version"] = CONFIG_SCHEMA_VERSION;
            saveJson(PATH_CONFIG, doc);
            Serial.println(F("[Storage] Migration complete"));
        }
    }

    // 2. Decoupled NVS State Migration:
    // If legacy /relay_states.json exists in LittleFS, migrate its contents
    // into the wear-leveled NVS partition and permanently remove the file from LittleFS.
    if (LittleFS.exists(PATH_RELAY_STATES)) {
        JsonDocument rsDoc;
        if (loadJson(PATH_RELAY_STATES, rsDoc) && rsDoc.containsKey("states")) {
            JsonArray arr = rsDoc["states"].as<JsonArray>();
            bool logical[MAX_RELAYS] = {0};
            bool wallSw[MAX_RELAYS] = {0};
            uint8_t count = 0;
            for (JsonObject s : arr) {
                if (count >= MAX_RELAYS) break;
                logical[count] = s["on"] | false;
                wallSw[count] = s["sw"] | false;
                count++;
            }
            saveRelayStatesNVS(logical, wallSw, count > 0 ? count : MAX_RELAYS);
            SERIAL_PRINTF("[Storage-NVS] Migrated %d legacy relay states to wear-leveled NVS.\n", count);
        }
        deleteFile(PATH_RELAY_STATES);
        Serial.println(F("[Storage-NVS] Removed legacy /relay_states.json from LittleFS to eliminate flash wear."));
    }
}

// ============================================================================
// Ensure default config files exist on first boot
// ============================================================================
void StorageManager::ensureDefaults() {
    if (!fileExists(PATH_CONFIG)) {
        Serial.println(F("[Storage] First boot — creating default config"));
        createDefaultConfig();
    }
}

// ============================================================================
// Create default config.json
// ============================================================================
void StorageManager::createDefaultConfig() {
    JsonDocument doc;
    doc["schema_version"] = CONFIG_SCHEMA_VERSION;
    doc["device_name"]    = DEFAULT_DEVICE_NAME;
    doc["timezone"]       = DEFAULT_TIMEZONE;
    doc["use_24h"]        = DEFAULT_24H_FORMAT;
    doc["lcd_enabled"]    = DEFAULT_LCD_ENABLED;
    doc["lcd_backlight"]  = DEFAULT_LCD_BACKLIGHT;
    doc["buzzer_enabled"] = DEFAULT_BUZZER_ENABLED;
    doc["lcd_rotation"]   = LCD_DEFAULT_ROTATION / 1000; // Store as seconds
    doc["web_auth"]       = false;
    doc["web_user"]       = "";
    doc["web_pass"]       = "";
    doc["guest_auth"]     = false;
    doc["guest_user"]     = "guest";
    doc["guest_pass"]     = "";

    saveJson(PATH_CONFIG, doc);
}

// ============================================================================
// Internal: Write string content to file
// ============================================================================
bool StorageManager::writeFile(const char* path, const String& content) {
    STORAGE_LOCK();
    if (!_writeEnabled) {
        SERIAL_PRINTF("[Storage] Write helper blocked during OTA: %s\n", path);
        return false;
    }

    // Write to a temporary file first, then swap via .bak so power loss never leaves config missing
    String tempPath = String(path) + ".tmp";
    String bakPath  = String(path) + ".bak";

    File file = LittleFS.open(tempPath, "w");
    if (!file) {
        SERIAL_PRINTF("[Storage] Failed to create temp file for %s\n", path);
        return false;
    }

    size_t written = file.print(content);
    file.close();

    if (written != content.length()) {
        SERIAL_PRINTF("[Storage] Write incomplete for %s (%u/%u bytes)\n",
                      path, written, content.length());
        LittleFS.remove(tempPath);
        return false;
    }

    bool hadOriginal = LittleFS.exists(path);
    if (hadOriginal) {
        if (LittleFS.exists(bakPath)) LittleFS.remove(bakPath);
        if (!LittleFS.rename(path, bakPath)) {
            SERIAL_PRINTF("[Storage] Backup rename failed for %s\n", path);
            LittleFS.remove(tempPath);
            return false;
        }
    }

    if (!LittleFS.rename(tempPath, path)) {
        SERIAL_PRINTF("[Storage] Rename failed for %s\n", path);
        if (hadOriginal && LittleFS.exists(bakPath)) {
            LittleFS.rename(bakPath, path);
        }
        LittleFS.remove(tempPath);
        return false;
    }

    if (hadOriginal && LittleFS.exists(bakPath)) {
        LittleFS.remove(bakPath);
    }

    SERIAL_PRINTF("[Storage] Saved: %s (%u bytes)\n", path, written);
    return true;
}

// ============================================================================
// Debug: Dump a JSON file to Serial
// ============================================================================
void StorageManager::dumpFile(const char* path) {
    if (!_initialized || !LittleFS.exists(path)) {
        SERIAL_PRINTF("[Storage] Cannot dump %s\n", path);
        return;
    }

    File file = LittleFS.open(path, "r");
    if (!file) return;

    SERIAL_PRINTF("--- %s (%u bytes) ---\n", path, file.size());
    while (file.available()) {
        Serial.write(file.read());
    }
    Serial.println(F("\n---"));
    file.close();
}

// ============================================================================
// Debug: List all files on filesystem
// ============================================================================
void StorageManager::listFiles() {
    if (!_initialized) return;

    Serial.println(F("[Storage] === File Listing ==="));
#if defined(ESP8266)
    Dir dir = LittleFS.openDir("/");
    while (dir.next()) {
        SERIAL_PRINTF("  %-25s %6u bytes\n", dir.fileName().c_str(), (unsigned int)dir.fileSize());
    }
#else
    File root = LittleFS.open("/");
    File file = root.openNextFile();
    while (file) {
        SERIAL_PRINTF("  %-25s %6u bytes\n", file.name(), file.size());
        file = root.openNextFile();
    }
#endif
    SERIAL_PRINTF("[Storage] Total: %u / %u bytes\n", usedBytes(), totalBytes());
}

// ============================================================================
// Decoupled NVS State Engine (100,000+ Cycle Wear-Leveling)
// ============================================================================
#if defined(ESP32)
#define NVS_NAMESPACE_STATE "sh_state"

bool StorageManager::saveRelayStatesNVS(const bool* logicalStates, const bool* switchStates, uint8_t count) {
    if (!logicalStates) return false;
    STORAGE_LOCK();
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        SERIAL_PRINTF("[NVS] nvs_open failed (0x%X)\n", err);
        return false;
    }

    uint16_t logicalMask = 0;
    uint16_t switchMask = 0;
    for (uint8_t i = 0; i < count && i < 16; i++) {
        if (logicalStates[i]) logicalMask |= (1 << i);
        if (switchStates && switchStates[i]) switchMask |= (1 << i);
    }

    nvs_set_u16(handle, "r_on", logicalMask);
    if (switchStates) {
        nvs_set_u16(handle, "r_sw", switchMask);
    }
    nvs_set_u8(handle, "r_cnt", count);
    nvs_commit(handle);
    nvs_close(handle);
    return true;
}

bool StorageManager::loadRelayStatesNVS(bool* logicalStates, bool* switchStates, uint8_t count) {
    if (!logicalStates) return false;
    STORAGE_LOCK();
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_STATE, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    uint16_t logicalMask = 0;
    uint16_t switchMask = 0;
    err = nvs_get_u16(handle, "r_on", &logicalMask);
    if (err != ESP_OK) {
        nvs_close(handle);
        return false;
    }

    nvs_get_u16(handle, "r_sw", &switchMask);

    for (uint8_t i = 0; i < count && i < 16; i++) {
        logicalStates[i] = (logicalMask & (1 << i)) != 0;
        if (switchStates) {
            switchStates[i] = (switchMask & (1 << i)) != 0;
        }
    }
    nvs_close(handle);
    return true;
}

void StorageManager::incrementRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
    STORAGE_LOCK();
    char key[16];
    snprintf(key, sizeof(key), "cyc_%u", index);
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle) == ESP_OK) {
        uint32_t count = 0;
        nvs_get_u32(handle, key, &count);
        count++;
        nvs_set_u32(handle, key, count);
        nvs_commit(handle);
        nvs_close(handle);
    }
}

uint32_t StorageManager::getRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return 0;
    STORAGE_LOCK();
    char key[16];
    snprintf(key, sizeof(key), "cyc_%u", index);
    nvs_handle_t handle;
    uint32_t val = 0;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READONLY, &handle) == ESP_OK) {
        nvs_get_u32(handle, key, &val);
        nvs_close(handle);
    }
    return val;
}

void StorageManager::clearNVSState() {
    STORAGE_LOCK();
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle) == ESP_OK) {
        nvs_erase_all(handle);
        nvs_commit(handle);
        nvs_close(handle);
        Serial.println(F("[Storage-NVS] Cleared all runtime state keys from NVS."));
    }
}

#elif defined(ESP8266)
// Emulate NVS runtime state using dedicated flash EEPROM sector on ESP8266
#define EEPROM_MAGIC_0       0xA5
#define EEPROM_MAGIC_1       0x5C
#define EEPROM_OFF_MAGIC     0   // 2 bytes (0-1)
#define EEPROM_OFF_CNT       2   // 1 byte (2)
#define EEPROM_OFF_LOGICAL   3   // 2 bytes (3-4)
#define EEPROM_OFF_SWITCH    5   // 2 bytes (5-6)
#define EEPROM_OFF_TIMERS    8   // 32 bytes (8-39: 8x uint32_t)
#define EEPROM_OFF_CYCLES    40  // 32 bytes (40-71: 8x uint32_t)

static bool eepromValid() {
    return (EEPROM.read(EEPROM_OFF_MAGIC) == EEPROM_MAGIC_0 && 
            EEPROM.read(EEPROM_OFF_MAGIC + 1) == EEPROM_MAGIC_1);
}

static void eepromInitHeader() {
    if (!eepromValid()) {
        // Zero-initialize erased 0xFF EEPROM bytes before stamping magic header
        // so logical relay masks / switch masks / cycle counters start cleanly at 0.
        for (int i = 0; i < 256; i++) {
            EEPROM.write(i, 0);
        }
        EEPROM.write(EEPROM_OFF_MAGIC, EEPROM_MAGIC_0);
        EEPROM.write(EEPROM_OFF_MAGIC + 1, EEPROM_MAGIC_1);
    }
}

static void eepromWrite32(int offset, uint32_t val) {
    EEPROM.write(offset,     (val)       & 0xFF);
    EEPROM.write(offset + 1, (val >> 8)  & 0xFF);
    EEPROM.write(offset + 2, (val >> 16) & 0xFF);
    EEPROM.write(offset + 3, (val >> 24) & 0xFF);
}

static uint32_t eepromRead32(int offset) {
    uint32_t b0 = EEPROM.read(offset);
    uint32_t b1 = EEPROM.read(offset + 1);
    uint32_t b2 = EEPROM.read(offset + 2);
    uint32_t b3 = EEPROM.read(offset + 3);
    return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
}

bool StorageManager::saveRelayStatesNVS(const bool* logicalStates, const bool* switchStates, uint8_t count) {
    if (!logicalStates) return false;
    eepromInitHeader();
    uint16_t logicalMask = 0;
    uint16_t switchMask = 0;
    for (uint8_t i = 0; i < count && i < 16; i++) {
        if (logicalStates[i]) logicalMask |= (1 << i);
        if (switchStates && switchStates[i]) switchMask |= (1 << i);
    }

    EEPROM.write(EEPROM_OFF_CNT, count);
    EEPROM.write(EEPROM_OFF_LOGICAL, logicalMask & 0xFF);
    EEPROM.write(EEPROM_OFF_LOGICAL + 1, (logicalMask >> 8) & 0xFF);
    if (switchStates) {
        EEPROM.write(EEPROM_OFF_SWITCH, switchMask & 0xFF);
        EEPROM.write(EEPROM_OFF_SWITCH + 1, (switchMask >> 8) & 0xFF);
    }
    return EEPROM.commit();
}

bool StorageManager::loadRelayStatesNVS(bool* logicalStates, bool* switchStates, uint8_t count) {
    if (!logicalStates || !eepromValid()) return false;

    uint16_t logicalMask = EEPROM.read(EEPROM_OFF_LOGICAL) | (EEPROM.read(EEPROM_OFF_LOGICAL + 1) << 8);
    uint16_t switchMask = EEPROM.read(EEPROM_OFF_SWITCH) | (EEPROM.read(EEPROM_OFF_SWITCH + 1) << 8);

    for (uint8_t i = 0; i < count && i < 16; i++) {
        logicalStates[i] = (logicalMask & (1 << i)) != 0;
        if (switchStates) {
            switchStates[i] = (switchMask & (1 << i)) != 0;
        }
    }
    return true;
}

void StorageManager::incrementRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
    eepromInitHeader();
    uint32_t count = eepromRead32(EEPROM_OFF_CYCLES + (index * 4));
    count++;
    eepromWrite32(EEPROM_OFF_CYCLES + (index * 4), count);
    // Defer EEPROM.commit() to RelayManager's coalesced saveRelayStatesNVS() window to prevent flash wear
}

uint32_t StorageManager::getRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS || !eepromValid()) return 0;
    return eepromRead32(EEPROM_OFF_CYCLES + (index * 4));
}

void StorageManager::clearNVSState() {
    for (int i = 0; i < 256; i++) EEPROM.write(i, 0);
    EEPROM.commit();
    Serial.println(F("[Storage-NVS] Cleared all runtime state keys from EEPROM emulation."));
}
#endif
