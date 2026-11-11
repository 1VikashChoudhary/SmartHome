/*
 * ============================================================================
 * StorageManager.cpp — LittleFS Persistent Storage Implementation
 * ============================================================================
 */

#include "StorageManager.h"

// ============================================================================
// Constructor
// ============================================================================
StorageManager::StorageManager() : _initialized(false), _writeEnabled(true) {}

// ============================================================================
// Initialize LittleFS
// ============================================================================
bool StorageManager::begin() {
    if (_initialized) return true;

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

    Serial.printf("[Storage] LittleFS mounted. Used: %u / %u bytes (%.1f%%)\n",
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

    if (!LittleFS.exists(path)) {
        Serial.printf("[Storage] File not found: %s\n", path);
        return false;
    }

    File file = LittleFS.open(path, "r");
    if (!file) {
        Serial.printf("[Storage] Failed to open: %s\n", path);
        return false;
    }

    DeserializationError error = deserializeJson(doc, file);
    file.close();

    if (error) {
        Serial.printf("[Storage] JSON parse error in %s: %s\n", path, error.c_str());
        return false;
    }

    return true;
}

// ============================================================================
// Save JsonDocument to file (safe write: temp file + rename)
// ============================================================================
bool StorageManager::saveJson(const char* path, const JsonDocument& doc) {
    if (!_initialized) return false;
    if (!_writeEnabled) {
        Serial.printf("[Storage] Write blocked during OTA: %s\n", path);
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
    return LittleFS.exists(path);
}

// ============================================================================
// Delete a file
// ============================================================================
bool StorageManager::deleteFile(const char* path) {
    if (!_initialized) return false;
    if (!_writeEnabled) {
        Serial.printf("[Storage] Delete blocked during OTA: %s\n", path);
        return false;
    }

    if (LittleFS.exists(path)) {
        bool ok = LittleFS.remove(path);
        Serial.printf("[Storage] Delete %s: %s\n", path, ok ? "OK" : "FAIL");
        return ok;
    }
    return true; // Already gone
}

void StorageManager::setWriteEnabled(bool enabled) {
    _writeEnabled = enabled;
    Serial.printf("[Storage] Writes %s\n", enabled ? "enabled" : "disabled");
}

bool StorageManager::isWriteEnabled() const {
    return _writeEnabled;
}

// ============================================================================
// Export ALL config files as a single JSON backup
// ============================================================================
String StorageManager::exportAllConfig(bool redactSecrets) {
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
                        // Note: web_pass_hash and guest_pass_hash are already one-way SHA-256 hashes, keeping them intact
                        // avoids corrupting logins if the backup is subsequently restored.
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
    if (!_initialized) return false;

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
            JsonDocument subDoc;
            subDoc.set(doc[matchedKey]);

            // Validate architecture compatibility for hardware.json
            if (strcmp(m.path, PATH_HARDWARE) == 0) {
#if defined(ESP8266)
                bool isEsp8266Compatible = true;
                const char* bChip = doc["_chip"] | "";
                if (strcmp(bChip, "ESP32") == 0) {
                    isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("channels")) {
                    for (JsonObjectConst ch : subDoc["channels"].as<JsonArrayConst>()) {
                        uint8_t rp = ch["relay_pin"] | PIN_UNUSED;
                        uint8_t sp = ch["switch_pin"] | PIN_UNUSED;
                        if ((rp != PIN_UNUSED && rp > 16) || (sp != PIN_UNUSED && sp > 16)) {
                            isEsp8266Compatible = false;
                            break;
                        }
                    }
                }
                if (subDoc.containsKey("lcd")) {
                    uint8_t sda = subDoc["lcd"]["sda_pin"] | PIN_UNUSED;
                    uint8_t scl = subDoc["lcd"]["scl_pin"] | PIN_UNUSED;
                    if ((sda != PIN_UNUSED && sda > 16) || (scl != PIN_UNUSED && scl > 16)) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("buzzer")) {
                    uint8_t bp = subDoc["buzzer"]["pin"] | PIN_UNUSED;
                    if (bp != PIN_UNUSED && bp > 16) isEsp8266Compatible = false;
                }
                if (subDoc.containsKey("btn_multi_pin")) {
                    uint8_t bmp = subDoc["btn_multi_pin"] | PIN_UNUSED;
                    if (bmp != PIN_UNUSED && bmp > 16) isEsp8266Compatible = false;
                }
                if (!isEsp8266Compatible) {
                    Serial.println(F("[Storage] Notice: Backup hardware profile belongs to ESP32 (or has pins > 16). Preserving current valid ESP8266 hardware configuration."));
                    continue; // Skip saving hardware.json, preserve existing valid hardware configuration
                }
#elif defined(ESP32)
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
                        uint8_t rp = ch["relay_pin"] | PIN_UNUSED;
                        if (rp == 12) isEsp32Compatible = false; // GPIO 12 is MTDI strapping pin on ESP32
                    }
                }
                if (!isEsp32Compatible) {
                    Serial.println(F("[Storage] Notice: Backup hardware profile belongs to ESP8266. Preserving current valid ESP32 hardware configuration."));
                    continue;
                }
#endif
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
                    subDoc["guest_pass"] == "__REDACTED__" || subDoc["guest_pass_hash"] == "__REDACTED__") {
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
                    } else {
                        if (subDoc["web_pass_hash"] == "__REDACTED__") subDoc.remove("web_pass_hash");
                        if (subDoc["web_pass"] == "__REDACTED__") subDoc.remove("web_pass");
                        if (subDoc["guest_pass_hash"] == "__REDACTED__") subDoc.remove("guest_pass_hash");
                        if (subDoc["guest_pass"] == "__REDACTED__") subDoc.remove("guest_pass");
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
                Serial.printf("[Storage] Restored: %s\n", m.path);
            }
        } else if (isFullBackup && m.wipeIfMissingInFullBackup && LittleFS.exists(m.path)) {
            // If this is a full backup and an optional module file was not present when
            // the backup was created (meaning the module was at factory defaults), delete
            // any subsequently created file so the module genuinely reverts to the backup state!
            if (deleteFile(m.path)) {
                restored++;
                Serial.printf("[Storage] Removed post-backup config to restore default state: %s\n", m.path);
            }
        }
    }

    Serial.printf("[Storage] Import complete: %d files applied\n", restored);
    return restored > 0;
}

bool StorageManager::importAllConfig(const String& jsonBlob) {
    if (jsonBlob.length() == 0) return false;
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, jsonBlob);
    if (error) {
        Serial.printf("[Storage] Import parse error: %s\n", error.c_str());
        return false;
    }
    return importAllConfig(doc.as<JsonObjectConst>());
}

// ============================================================================
// Factory Reset — delete all config files
// ============================================================================
void StorageManager::factoryReset() {
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
            Serial.printf("[Storage] Migrating config from v%d to v%d\n",
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
            Serial.printf("[Storage-NVS] Migrated %d legacy relay states to wear-leveled NVS.\n", count);
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
    if (!_writeEnabled) {
        Serial.printf("[Storage] Write helper blocked during OTA: %s\n", path);
        return false;
    }

    // Write to a temporary file first, then rename for atomic write
    String tempPath = String(path) + ".tmp";

    File file = LittleFS.open(tempPath, "w");
    if (!file) {
        Serial.printf("[Storage] Failed to create temp file for %s\n", path);
        return false;
    }

    size_t written = file.print(content);
    file.close();

    if (written != content.length()) {
        Serial.printf("[Storage] Write incomplete for %s (%u/%u bytes)\n",
                      path, written, content.length());
        LittleFS.remove(tempPath);
        return false;
    }

    // Atomic rename: remove old, rename temp to target
    LittleFS.remove(path);
    if (!LittleFS.rename(tempPath, path)) {
        Serial.printf("[Storage] Rename failed for %s\n", path);
        return false;
    }

    Serial.printf("[Storage] Saved: %s (%u bytes)\n", path, written);
    return true;
}

// ============================================================================
// Debug: Dump a JSON file to Serial
// ============================================================================
void StorageManager::dumpFile(const char* path) {
    if (!_initialized || !LittleFS.exists(path)) {
        Serial.printf("[Storage] Cannot dump %s\n", path);
        return;
    }

    File file = LittleFS.open(path, "r");
    if (!file) return;

    Serial.printf("--- %s (%u bytes) ---\n", path, file.size());
    while (file.available()) {
        Serial.write(file.read());
    }
    Serial.println("\n---");
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
        Serial.printf("  %-25s %6u bytes\n", dir.fileName().c_str(), (unsigned int)dir.fileSize());
    }
#else
    File root = LittleFS.open("/");
    File file = root.openNextFile();
    while (file) {
        Serial.printf("  %-25s %6u bytes\n", file.name(), file.size());
        file = root.openNextFile();
    }
#endif
    Serial.printf("[Storage] Total: %u / %u bytes\n", usedBytes(), totalBytes());
}

// ============================================================================
// Decoupled NVS State Engine (100,000+ Cycle Wear-Leveling)
// ============================================================================
#if defined(ESP32)
#define NVS_NAMESPACE_STATE "sh_state"

bool StorageManager::saveRelayStatesNVS(const bool* logicalStates, const bool* switchStates, uint8_t count) {
    if (!logicalStates) return false;
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        Serial.printf("[NVS] nvs_open failed (0x%X)\n", err);
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

void StorageManager::saveRelayAutoTimerNVS(uint8_t index, uint32_t remainingSec) {
    if (index >= MAX_RELAYS) return;
    char key[16];
    snprintf(key, sizeof(key), "timer_%u", index);
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle) == ESP_OK) {
        nvs_set_u32(handle, key, remainingSec);
        nvs_commit(handle);
        nvs_close(handle);
    }
}

uint32_t StorageManager::getRelayAutoTimerNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return 0;
    char key[16];
    snprintf(key, sizeof(key), "timer_%u", index);
    nvs_handle_t handle;
    uint32_t val = 0;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READONLY, &handle) == ESP_OK) {
        nvs_get_u32(handle, key, &val);
        nvs_close(handle);
    }
    return val;
}

void StorageManager::clearRelayAutoTimerNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
    char key[16];
    snprintf(key, sizeof(key), "timer_%u", index);
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE_STATE, NVS_READWRITE, &handle) == ESP_OK) {
        nvs_erase_key(handle, key);
        nvs_commit(handle);
        nvs_close(handle);
    }
}

void StorageManager::incrementRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
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
    EEPROM.write(EEPROM_OFF_MAGIC, EEPROM_MAGIC_0);
    EEPROM.write(EEPROM_OFF_MAGIC + 1, EEPROM_MAGIC_1);
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

void StorageManager::saveRelayAutoTimerNVS(uint8_t index, uint32_t remainingSec) {
    if (index >= MAX_RELAYS) return;
    eepromInitHeader();
    eepromWrite32(EEPROM_OFF_TIMERS + (index * 4), remainingSec);
    EEPROM.commit();
}

uint32_t StorageManager::getRelayAutoTimerNVS(uint8_t index) {
    if (index >= MAX_RELAYS || !eepromValid()) return 0;
    return eepromRead32(EEPROM_OFF_TIMERS + (index * 4));
}

void StorageManager::clearRelayAutoTimerNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
    eepromInitHeader();
    eepromWrite32(EEPROM_OFF_TIMERS + (index * 4), 0);
    EEPROM.commit();
}

void StorageManager::incrementRelayCycleNVS(uint8_t index) {
    if (index >= MAX_RELAYS) return;
    eepromInitHeader();
    uint32_t count = eepromRead32(EEPROM_OFF_CYCLES + (index * 4));
    count++;
    eepromWrite32(EEPROM_OFF_CYCLES + (index * 4), count);
    EEPROM.commit();
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
