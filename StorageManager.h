/*
 * ============================================================================
 * StorageManager.h — LittleFS Persistent Storage Manager
 * ============================================================================
 * Provides versioned JSON configuration storage with flash-wear mitigation.
 * All persistent settings (WiFi, MQTT, relay config, etc.) are managed here.
 * ============================================================================
 */

#ifndef STORAGE_MANAGER_H
#define STORAGE_MANAGER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#if defined(ESP32)
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <nvs.h>
#include <nvs_flash.h>
#elif defined(ESP8266)
#include <EEPROM.h>
#endif
#include "Config.h"

class StorageManager {
public:
    StorageManager();

    // Initialize LittleFS filesystem
    bool begin();

    // --- Generic JSON File Operations ---

    // Load a JSON file into a JsonDocument. Returns false if file not found or parse error.
    bool loadJson(const char* path, JsonDocument& doc);

    // Save a JsonDocument to a file. Atomically writes (write to temp, rename).
    bool saveJson(const char* path, const JsonDocument& doc);

    // Check if a file exists
    bool fileExists(const char* path);

    // Delete a specific file
    bool deleteFile(const char* path);

    // Enable or disable filesystem writes temporarily (used during OTA).
    void setWriteEnabled(bool enabled);
    bool isWriteEnabled() const;

    // --- Bulk Operations ---

    // Export ALL config files as a single JSON blob (for backup)
    String exportAllConfig(bool redactSecrets = false);

    // Import a config backup blob (for restore). Returns true on success.
    bool importAllConfig(const String& jsonBlob);
    bool importAllConfig(JsonObjectConst doc);

    // Delete all config files (factory reset). Does NOT unmount LittleFS.
    void factoryReset();

    // --- Decoupled NVS State Engine (100,000+ Cycle Wear-Leveling) ---
    // High-frequency runtime states are persisted in NVS rather than LittleFS
    bool saveRelayStatesNVS(const bool* logicalStates, const bool* switchStates, uint8_t count);
    bool loadRelayStatesNVS(bool* logicalStates, bool* switchStates, uint8_t count);
    void incrementRelayCycleNVS(uint8_t index);
    uint32_t getRelayCycleNVS(uint8_t index);
    void clearNVSState();

    // --- Filesystem Info ---

    size_t usedBytes();
    size_t totalBytes();
    float usagePercent();

    // --- Config Version Migration ---

    // Check and migrate config files from older schema versions
    void migrateIfNeeded();

    // --- Utility ---

    // Pretty-print a JSON file to Serial (debug helper)
    void dumpFile(const char* path);

    // List all files on the filesystem to Serial
    void listFiles();

private:
    bool _initialized;
    bool _writeEnabled;
#if defined(ESP32)
    mutable SemaphoreHandle_t _fsMutex;
    void ensureMutex() const;
#endif

    // Create default config file if it doesn't exist
    void ensureDefaults();

    // Create a default config.json
    void createDefaultConfig();

    // Internal save helper (no coalescing — caller manages timing)
    bool writeFile(const char* path, const String& content);
};

#endif // STORAGE_MANAGER_H
