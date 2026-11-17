/*
 * ============================================================================
 * WebServerManager.cpp — AsyncWebServer + REST API Implementation
 * ============================================================================
 */

#include "WebServerManager.h"
#include "RemoteAlertManager.h"
#include <math.h>
#if defined(ESP8266)
#include <bearssl/bearssl_hash.h>
#include <MD5Builder.h>
#else
#include <mbedtls/sha256.h>
#include <mbedtls/md5.h>
#endif

namespace {

struct TempBodyState {
    String body;
    bool handled;
};

TempBodyState* ensureTempBodyState(AsyncWebServerRequest* req) {
    if (!req) return nullptr;
    if (!req->_tempObject) {
        TempBodyState* state = new TempBodyState();
        state->handled = false;
        req->_tempObject = state;
        // Ensure ~AsyncWebServerRequest() never calls free() on a C++ TempBodyState* if TCP drops early.
        req->onDisconnect([req]() {
            if (req->_tempObject) {
                delete static_cast<TempBodyState*>(req->_tempObject);
                req->_tempObject = nullptr;
            }
        });
    }
    return static_cast<TempBodyState*>(req->_tempObject);
}

struct RelayTimerSnapshot {
    bool active;
    bool target;
    uint32_t remaining;
};

void captureRelayTimerSnapshots(RelayManager* relay, AlarmScheduler* alarm,
                                RelayTimerSnapshot* out, uint8_t count) {
    if (!relay) return;
    for (uint8_t i = 0; i < count; i++) {
        out[i] = {false, false, 0};
        if (!relay->isChannelEnabled(i)) continue;
        if (alarm) {
            alarm->resolveEffectiveTimerForRelay(*relay, i, out[i].active, out[i].target, out[i].remaining);
        } else if (relay->hasActiveTimer(i)) {
            uint32_t rem = relay->getTimerRemaining(i);
            if (rem > 0) {
                out[i] = {true, relay->getTimerTargetState(i), rem};
            }
        }
    }
}

void broadcastChangedRelayTimers(RelayManager* relay, AlarmScheduler* alarm,
                                 WebSocketManager* ws, const RelayTimerSnapshot* before,
                                 uint8_t count, int8_t forceRelayIndex = -1) {
    if (!relay || !ws) return;
    for (uint8_t i = 0; i < count; i++) {
        if (!relay->isChannelEnabled(i)) continue;
        RelayTimerSnapshot after = {false, false, 0};
        if (alarm) {
            alarm->resolveEffectiveTimerForRelay(*relay, i, after.active, after.target, after.remaining);
        } else if (relay->hasActiveTimer(i)) {
            uint32_t rem = relay->getTimerRemaining(i);
            if (rem > 0) {
                after = {true, relay->getTimerTargetState(i), rem};
            }
        }
        uint32_t diff = (after.remaining > before[i].remaining)
            ? (after.remaining - before[i].remaining)
            : (before[i].remaining - after.remaining);
        if ((int8_t)i == forceRelayIndex ||
            after.active != before[i].active ||
            after.target != before[i].target ||
            (after.active && diff > 2)) {
            ws->broadcastRelayTimer(i, after.active, after.target, after.remaining);
        }
    }
}

} // namespace

WebServerManager::WebServerManager()
    : _server(WEB_SERVER_PORT),
      _storage(nullptr), _wifi(nullptr), _relay(nullptr), _sensor(nullptr),
      _buzzer(nullptr), _mqtt(nullptr), _time(nullptr), _lcd(nullptr),
      _alarm(nullptr), _rules(nullptr), _logger(nullptr), _diag(nullptr), _ota(nullptr),
      _ws(nullptr), _hw(nullptr), _remoteAlert(nullptr),
      _rebootRequested(false), _rollbackRequested(false), _rebootRequestTime(0), _rebootDelay(0),
      _deviceName(DEFAULT_DEVICE_NAME),
      _webAuthEnabled(false), _webUsername("admin"), _webPassword(""), _webPasswordHash(""),
      _guestAuthEnabled(false), _guestUsername("guest"), _guestPassword(""), _guestPasswordHash("") {
    for (int i = 0; i < RATE_LIMIT_CACHE_SIZE; i++) {
        _rateLimits[i].ip = IPAddress(0, 0, 0, 0);
        _rateLimits[i].failedCount = 0;
        _rateLimits[i].lockoutUntil = 0;
        _rateLimits[i].lastAttempt = 0;
    }
}

void WebServerManager::begin(StorageManager& storage, WifiManager& wifi,
                              RelayManager& relay, SensorManager& sensor,
                              BuzzerManager& buzzer, MqttManager& mqtt,
                              TimeManager& timeMgr, LCDManager& lcd,
                              AlarmScheduler& alarm, RuleManager& rules,
                              EventLogger& logger, Diagnostics& diag, OTAManager& ota) {
    _storage = &storage;
    _wifi = &wifi;
    _relay = &relay;
    _sensor = &sensor;
    _buzzer = &buzzer;
    _mqtt = &mqtt;
    _time = &timeMgr;
    _lcd = &lcd;
    _alarm = &alarm;
    _rules = &rules;
    _logger = &logger;
    _diag = &diag;
    _ota = &ota;

    // Load device identity cache
    _deviceName = DEFAULT_DEVICE_NAME;

    // Load web authentication settings (Multi-User Privilege Tiers: Admin vs. Family / Guest)
    _webAuthEnabled = false;
    _webUsername = "admin";
    _webPassword = "";
    _webPasswordHash = "";
    _guestAuthEnabled = false;
    _guestUsername = "guest";
    _guestPassword = "";
    _guestPasswordHash = "";

    JsonDocument cfgDoc;
    if (_storage && _storage->loadJson(PATH_CONFIG, cfgDoc)) {
        String dn = cfgDoc["device_name"] | DEFAULT_DEVICE_NAME;
        dn.trim();
        if (dn.length() > 0) _deviceName = dn;

        _webAuthEnabled = cfgDoc["web_auth"] | false;
        _webUsername = cfgDoc["web_user"] | "admin";
        _webUsername.trim();
        if (_webUsername.length() == 0) _webUsername = "admin";
        _webPassword = cfgDoc["web_pass"] | "";
        _webPasswordHash = cfgDoc["web_pass_hash"] | "";

        _guestAuthEnabled = cfgDoc["guest_auth"] | false;
        _guestUsername = cfgDoc["guest_user"] | "guest";
        _guestUsername.trim();
        if (_guestUsername.length() == 0) _guestUsername = "guest";
        _guestPassword = cfgDoc["guest_pass"] | "";
        _guestPasswordHash = cfgDoc["guest_pass_hash"] | "";

        bool needSave = false;
        // Migration: If legacy plaintext web_pass exists, compute salted SHA-256 + ArduinoOTA MD5 and remove plaintext
        if (_webPassword.length() > 0) {
            if (_webPasswordHash.length() == 0) {
                _webPasswordHash = hashPasswordSalted(_webPassword);
                cfgDoc["web_pass_hash"] = _webPasswordHash;
            }
            if (String(cfgDoc["ota_pass_md5"] | "").length() == 0) {
                cfgDoc["ota_pass_md5"] = md5Hex(_webPassword);
            }
            cfgDoc.remove("web_pass");
            needSave = true;
            Serial.println(F("[Web] Migrated plaintext admin password to salted SHA-256 hash"));
        }
        if (_guestPasswordHash.length() == 0 && _guestPassword.length() > 0) {
            _guestPasswordHash = hashPasswordSalted(_guestPassword);
            cfgDoc["guest_pass_hash"] = _guestPasswordHash;
            cfgDoc.remove("guest_pass");
            needSave = true;
            Serial.println(F("[Web] Migrated plaintext guest password to salted SHA-256 hash"));
        }
        if (needSave) {
            _storage->saveJson(PATH_CONFIG, cfgDoc);
        }
    }
    regenerateWsToken();

    setupPageRoutes();
    setupAPIRoutes();
    setupCaptivePortal();

    _server.begin();
    SERIAL_PRINTF("[Web] Server started on port %d\n", WEB_SERVER_PORT);
}

void WebServerManager::begin(StorageManager& storage, WifiManager& wifi,
                              RelayManager& relay, SensorManager& sensor,
                              BuzzerManager& buzzer, MqttManager& mqtt,
                              TimeManager& timeMgr, LCDManager& lcd,
                              AlarmScheduler& alarm, RuleManager& rules,
                              EventLogger& logger, Diagnostics& diag, OTAManager& ota,
                              HardwareManager& hw) {
    _hw = &hw;
    begin(storage, wifi, relay, sensor, buzzer, mqtt, timeMgr, lcd, alarm, rules, logger, diag, ota);
}

AsyncWebServer& WebServerManager::getServer() { return _server; }

void WebServerManager::requestReboot(unsigned long delayMs) {
    _rollbackRequested = false;
    _rebootRequested = true;
    _rebootRequestTime = millis();
    _rebootDelay = delayMs;
    SERIAL_PRINTF("[Web] Reboot requested. Delay: %lu ms\n", delayMs);
}

void WebServerManager::requestRollbackReboot(unsigned long delayMs) {
    _rollbackRequested = true;
    _rebootRequested = true;
    _rebootRequestTime = millis();
    _rebootDelay = delayMs;
    SERIAL_PRINTF("[Web] Rollback reboot requested. Delay: %lu ms\n", delayMs);
}

// ============================================================================
// Page Routes
// ============================================================================
void WebServerManager::setupPageRoutes() {
    // Main dashboard (or Captive Portal in AP setup mode unless ?dashboard=1)
    _server.on("/", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        const char* html = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE && !req->hasParam("dashboard"))
            ? PAGE_CAPTIVE : PAGE_INDEX;
        AsyncWebServerResponse* r = req->beginResponse_P(200, "text/html", html);
        r->addHeader("Connection", "close");
        req->send(r);
    });

    // Firmware update page
    _server.on("/update", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        AsyncWebServerResponse* r = req->beginResponse_P(200, "text/html", PAGE_OTA_UPDATE);
        r->addHeader("Connection", "close");
        req->send(r);
    });

    // Logout landing page
    _server.on("/logout", HTTP_GET, [](AsyncWebServerRequest* req) {
        AsyncWebServerResponse* r = req->beginResponse_P(200, "text/html", PAGE_LOGGED_OUT);
        r->addHeader("Connection", "close");
        r->addHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        r->addHeader("Pragma", "no-cache");
        r->addHeader("Expires", "0");
        req->send(r);
    });

    // Captive portal redirect
    _server.on("/generate_204", HTTP_GET, [](AsyncWebServerRequest* req) {
        req->redirect("/");
    });
    _server.on("/fwlink", HTTP_GET, [](AsyncWebServerRequest* req) {
        req->redirect("/");
    });
}

// ============================================================================
// REST API Routes
// ============================================================================
void WebServerManager::setupAPIRoutes() {
    // --- /api/logout — Explicit credential eviction endpoint for HTTP Basic Auth ---
    _server.on("/api/logout", HTTP_ANY, [this](AsyncWebServerRequest* req) {
        regenerateWsToken();
        AsyncWebServerResponse* r = req->beginResponse(
            401, "application/json",
            "{\"status\":\"logged_out\",\"message\":\"Logged out successfully\"}"
        );
        r->addHeader("WWW-Authenticate", "Basic realm=\"SmartHome\"");
        r->addHeader("Connection", "close");
        r->addHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        r->addHeader("Pragma", "no-cache");
        r->addHeader("Expires", "0");
        req->send(r);
    });

    // --- GET /api/discovery — Lightweight unauthenticated discovery endpoint for mobile/companion apps ---
    _server.on("/api/discovery", HTTP_GET, [this](AsyncWebServerRequest* req) {
        JsonDocument doc;
        doc["service"]        = "smarthome";
        doc["device_name"]    = _deviceName;
        doc["device_id"]      = _wifi ? _wifi->getDeviceId() : "";
        doc["mac"]            = _wifi ? _wifi->getMAC() : "";
        doc["hostname"]       = _wifi ? _wifi->getHostname() : "";
        doc["ip"]             = _wifi ? _wifi->getIP() : "";
        doc["fw_version"]     = FW_VERSION;
        doc["platform"]       = PLATFORM_NAME;
        doc["model"]          = String(PLATFORM_NAME) + "-SmartHome";
        doc["num_relays"]     = _relay ? _relay->getRelayCount() : NUM_RELAYS;
        doc["auth_required"]  = isAuthConfigured();
        doc["guest_auth_enabled"] = _guestAuthEnabled;
        doc["uptime"]         = _diag ? _diag->getUptimeString() : "";
        sendJson(req, 200, doc);
    });

    // --- GET /api/status — Full system status (used by WebSocket too) ---
    _server.on("/api/status", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;

        doc["device_name"] = _deviceName;

        doc["fw_version"] = FW_VERSION;
        doc["platform"] = PLATFORM_NAME;
        doc["model"] = String(PLATFORM_NAME) + "-SmartHome";
        doc["mac"] = _wifi ? _wifi->getMAC() : "";
        doc["device_id"] = _wifi ? _wifi->getDeviceId() : "";
        doc["num_relays"] = _relay ? _relay->getRelayCount() : NUM_RELAYS;
        doc["auth_required"] = isAuthConfigured();
        doc["auth_role"] = (getRequestRole(req) == AUTH_ROLE_ADMIN) ? "admin" : "guest";
        doc["guest_auth_enabled"] = _guestAuthEnabled;
        doc["wifi_state"] = _wifi->getStateString();
        doc["rssi"] = _wifi->getRSSI();
        doc["signal"] = _wifi->getSignalPercent();
        doc["ip"] = _wifi->getIP();
        doc["hostname"] = _wifi->getHostname();
        doc["mqtt_state"] = _mqtt->getStateString();
        doc["uptime"] = _diag->getUptimeString();
        doc["free_heap"] = _diag->getFreeHeap();
        doc["datetime"] = _time->getFormattedDateTime();

        // Sensors (primary summary + multi-instance telemetry arrays)
        JsonObject statusObj = doc.as<JsonObject>();
        _sensor->appendStatusJson(statusObj);

        // Relays
        JsonArray relays = doc["relays"].to<JsonArray>();
        _relay->toJson(relays);
        if (_alarm) {
            _alarm->applyTimersToRelayArray(relays, *_relay);
        }
        if (_rules) {
            for (uint8_t i = 0; i < relays.size(); i++) {
                String activeRule = _rules->getActiveRuleForRelay(i);
                if (activeRule.length() > 0) {
                    relays[i]["active_rule"] = activeRule;
                }
            }
        }

        sendJson(req, 200, doc);
    });

    // --- GET /api/wifi/scan — Non-blocking nearby 2.4 GHz Wi-Fi scanner for Captive Portal & App Onboarding ---
    _server.on("/api/wifi/scan", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        JsonDocument doc;
        bool forceRefresh = req->hasParam("refresh") && req->getParam("refresh")->value() == "1";
        int n = WiFi.scanComplete();

        if (forceRefresh && n != WIFI_SCAN_RUNNING) {
            WiFi.scanDelete();
            WiFi.scanNetworks(true, false);
            doc["scanning"] = true;
            doc["networks"].to<JsonArray>();
            sendJson(req, 200, doc);
            return;
        }

        if (n == WIFI_SCAN_RUNNING) {
            doc["scanning"] = true;
            doc["networks"].to<JsonArray>();
            sendJson(req, 200, doc);
            return;
        }

        if (n == WIFI_SCAN_FAILED || n < 0) {
            WiFi.scanNetworks(true, false);
            doc["scanning"] = true;
            doc["networks"].to<JsonArray>();
            sendJson(req, 200, doc);
            return;
        }

        doc["scanning"] = false;
        JsonArray arr = doc["networks"].to<JsonArray>();

        // Deduplicate SSIDs (keep strongest RSSI per SSID)
        for (int i = 0; i < n; i++) {
            String ssid = WiFi.SSID(i);
            ssid.trim();
            if (ssid.length() == 0) continue;
            int rssi = WiFi.RSSI(i);

            bool duplicate = false;
            for (JsonObject existing : arr) {
                if (existing["ssid"] == ssid) {
                    if (rssi > (existing["rssi"] | -100)) {
                        existing["rssi"] = rssi;
                        int sig = 2 * (rssi + 100);
                        if (sig > 100) sig = 100;
                        if (sig < 0) sig = 0;
                        existing["signal"] = sig;
                    }
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;

            int sig = 2 * (rssi + 100);
            if (sig > 100) sig = 100;
            if (sig < 0) sig = 0;

            JsonObject net = arr.add<JsonObject>();
            net["ssid"] = ssid;
            net["rssi"] = rssi;
            net["signal"] = sig;
#if defined(ESP8266)
            net["secure"] = (WiFi.encryptionType(i) != AUTH_OPEN);
#else
            net["secure"] = (WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
#endif
            net["channel"] = WiFi.channel(i);
        }

        sendJson(req, 200, doc);
    });

    // --- GET /api/sensors ---
    _server.on("/api/sensors", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonObject obj = doc.to<JsonObject>();
        _sensor->toJson(obj);
        sendJson(req, 200, doc);
    });

    // --- GET /api/relays ---
    _server.on("/api/relays", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonArray arr = doc.to<JsonArray>();
        _relay->toJson(arr);
        if (_alarm) {
            _alarm->applyTimersToRelayArray(arr, *_relay);
        }
        if (_rules) {
            for (uint8_t i = 0; i < arr.size(); i++) {
                String activeRule = _rules->getActiveRuleForRelay(i);
                if (activeRule.length() > 0) {
                    arr[i]["active_rule"] = activeRule;
                }
            }
        }
        sendJson(req, 200, doc);
    });

    // --- GET /api/config ---
    _server.on("/api/config", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        bool isAdmin = (!isAuthConfigured()) || (getRequestRole(req) == AUTH_ROLE_ADMIN);
        JsonDocument doc;

        // Device config (populate live defaults even if config file is missing)
        doc["device_name"] = _deviceName;
        doc["hostname"] = _wifi ? _wifi->getHostname() : "";
        doc["mac"] = _wifi ? _wifi->getMAC() : "";
        doc["device_id"] = _wifi ? _wifi->getDeviceId() : "";
        doc["timezone"] = _time ? _time->getTimezone() : DEFAULT_TIMEZONE;
        doc["use_24h"] = _time ? _time->getUse24h() : DEFAULT_24H_FORMAT;
        if (isAdmin) {
            doc["web_auth"] = _webAuthEnabled;
            doc["web_user"] = _webUsername;
            doc["web_pass_set"] = (_webPasswordHash.length() > 0 || _webPassword.length() > 0);
            doc["guest_auth"] = _guestAuthEnabled;
            doc["guest_user"] = _guestUsername;
            doc["guest_pass_set"] = (_guestPasswordHash.length() > 0 || _guestPassword.length() > 0);
            doc["ap_pass_set"] = false;
            doc["arduino_ota"] = _ota ? _ota->isArduinoOtaEnabled() : false;
        }

        JsonDocument cfgDoc;
        if (_storage->loadJson(PATH_CONFIG, cfgDoc)) {
            doc["device_name"] = cfgDoc["device_name"] | _deviceName;
            doc["timezone"] = cfgDoc["timezone"] | (_time ? _time->getTimezone() : DEFAULT_TIMEZONE);
            doc["use_24h"] = cfgDoc["use_24h"] | (_time ? _time->getUse24h() : DEFAULT_24H_FORMAT);
            if (isAdmin) {
                doc["web_auth"] = cfgDoc["web_auth"] | _webAuthEnabled;
                doc["web_user"] = cfgDoc["web_user"] | _webUsername;
                String savedPass = cfgDoc["web_pass"] | "";
                String savedHash = cfgDoc["web_pass_hash"] | "";
                doc["web_pass_set"] = (savedHash.length() > 0 || savedPass.length() > 0);
                String savedApPass = cfgDoc["ap_pass"] | "";
                doc["ap_pass_set"] = (savedApPass.length() >= 8 && savedApPass.length() <= 63);
                if (_remoteAlert) {
                    JsonObject rootObj = doc.as<JsonObject>();
                    _remoteAlert->toConfigJson(rootObj);
                }
            }
        }
        if (isAdmin && !doc.containsKey("alert_https_supported")) {
            doc["alert_https_supported"] = RemoteAlertManager::isHttpsSupported();
        }
        doc["ws_token"] = isAdmin ? _wsToken : _wsGuestToken;
        doc["auth_role"] = isAdmin ? "admin" : "guest";

        // MQTT config (redacted for Guest role)
        JsonObject mqttObj = doc["mqtt"].to<JsonObject>();
        if (isAdmin) {
            _mqtt->toJson(mqttObj);
        } else {
            mqttObj["enabled"] = _mqtt->isEnabled();
            mqttObj["connected"] = _mqtt->isConnected();
            mqttObj["state"] = _mqtt->getStateString();
        }

        // LCD config
        JsonObject lcdObj = doc["lcd"].to<JsonObject>();
        _lcd->appendConfigJson(lcdObj);

        // Buzzer config
        JsonObject buzObj = doc["buzzer"].to<JsonObject>();
        buzObj["enabled"] = _buzzer->isEnabled();
        buzObj["hw_allowed"] = _buzzer->isHardwareAllowed();
        buzObj["volume"] = _buzzer->getVolume();

        // Sensor config
        JsonObject senObj = doc["sensor"].to<JsonObject>();
        senObj["temp_offset"] = _sensor->getTempOffset();
        senObj["hum_offset"] = _sensor->getHumOffset();
        senObj["temp_alarm"] = _sensor->getTempAlarmThreshold();
        senObj["mq2_enabled"] = _sensor->isMQ2Enabled();
        senObj["mq2_hw_allowed"] = _sensor->isMQ2HardwareAllowed();
        senObj["mq2_threshold"] = _sensor->getMQ2Threshold();
        senObj["mq2_baseline"] = _sensor->getMQ2Baseline();
        senObj["humidity_enabled"] = _sensor->hasHumidity();
        senObj["gas_unit"] = _sensor->isPrimarySgp40() ? "VOC" : "ADC";
        senObj["gas_max"] = _sensor->isPrimarySgp40() ? 500 : MQ2_ADC_MAX;
        JsonArray cliCalArr = senObj["climates"].to<JsonArray>();
        for (uint8_t i = 0; i < _sensor->getClimateCount(); i++) {
            JsonObject co = cliCalArr.add<JsonObject>();
            co["index"]            = i;
            co["temp_offset"]      = _sensor->getTempOffsetAt(i);
            co["hum_offset"]       = _sensor->getHumOffsetAt(i);
            co["humidity_enabled"] = _sensor->hasHumidityAt(i);
        }
        JsonArray mqCalArr = senObj["mq2_sensors"].to<JsonArray>();
        for (uint8_t i = 0; i < _sensor->getMq2Count(); i++) {
            uint8_t mType = _sensor->getMq2TypeAt(i);
            JsonObject mo = mqCalArr.add<JsonObject>();
            mo["index"]      = i;
            mo["type"]       = mType;
            mo["gas_max"]    = (mType == GAS_SGP40) ? 500 : MQ2_ADC_MAX;
            mo["enabled"]    = _sensor->isMq2ActiveAt(i);
            mo["hw_allowed"] = _sensor->isMq2HwAllowedAt(i);
            mo["threshold"]  = _sensor->getMQ2ThresholdAt(i);
            mo["baseline"]   = _sensor->getMQ2BaselineAt(i);
        }

        sendJson(req, 200, doc);
    });

    // --- GET /api/logs ---
    _server.on("/api/logs", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        if (req->hasParam("format") && req->getParam("format")->value() == "csv") {
            AsyncResponseStream *response = req->beginResponseStream("text/csv");
            response->addHeader("Connection", "close");
            response->print(_logger->toCSV());
            req->send(response);
        } else {
            AsyncResponseStream *response = req->beginResponseStream("application/json");
            response->addHeader("Connection", "close");
            response->print(_logger->toJson());
            req->send(response);
        }
    });

    // --- GET /api/alarms ---
    _server.on("/api/alarms", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonArray arr = doc.to<JsonArray>();
        _alarm->toJson(arr);
        sendJson(req, 200, doc);
    });

    // --- GET /api/rules ---
    _server.on("/api/rules", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonArray arr = doc.to<JsonArray>();
        if (_rules) _rules->toJson(arr);
        sendJson(req, 200, doc);
    });

    // --- GET /api/diagnostics ---
    _server.on("/api/diagnostics", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonObject obj = doc.to<JsonObject>();
        _diag->toJson(obj);
        obj["ota_status"] = _ota->getStatusString();
        obj["ota_partition"] = _ota->getRunningPartitionName();
        obj["ota_state"] = _ota->getOtaStateString();
        obj["ota_rollback_possible"] = _ota->isRollbackPossible();
        obj["fs_used"] = _storage->usedBytes();
        obj["fs_total"] = _storage->totalBytes();
        obj["ws_clients"] = _ws ? _ws->getClientCount() : 0;
        sendJson(req, 200, doc);
    });

    // --- GET /api/backup ---
    _server.on("/api/backup", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        // Flush any pending relay states or sensor calibration before exporting
        if (_relay) _relay->saveStates();
        if (_sensor) _sensor->saveCalibration();
        bool sanitize = req->hasParam("sanitize") && req->getParam("sanitize")->value() == "1";
        AsyncResponseStream *response = req->beginResponseStream("application/json");
        response->addHeader("Connection", "close");
        response->print(_storage->exportAllConfig(sanitize));
        req->send(response);
    });

    // --- POST /api/relay/all ---
    _server.on("/api/relay/all", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_GUEST); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/relay/all")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_GUEST, data, len, index, total, doc)) return;

        String action = doc["action"] | "";
        if (action == "on") _relay->allOn();
        else if (action == "off") _relay->allOff();
        else { sendError(req, 400, F("Invalid action")); return; }

        sendOk(req);
    });

    // --- POST /api/relay/config ---
    _server.on("/api/relay/config", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/relay/config")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        int id = doc["id"] | -1;
        if (id < 0 || id >= (_relay ? _relay->getRelayCount() : NUM_RELAYS)) { sendError(req, 400, F("Invalid relay ID")); return; }

        if (doc["name"].is<const char*>()) {
            String oldName = _relay->getName(id);
            String newName = doc["name"] | "";
            if (oldName != newName) {
                // Delete old entity first from Home Assistant
                _mqtt->publishHomeAssistantDiscoveryRemove(id);
                _relay->setName(id, newName);
                _mqtt->publishHomeAssistantDiscovery();
            }
        }
        if (doc["icon"].is<const char*>()) _relay->setIcon(id, doc["icon"] | "");
        if (doc.containsKey("trigger")) {
            int trig = doc["trigger"];
            if (trig == TRIGGER_ACTIVE_LOW || trig == TRIGGER_ACTIVE_HIGH) {
                TriggerMode mode = (TriggerMode)trig;
                _relay->setTriggerMode(id, mode);
                if (_hw) _hw->setTriggerMode(id, mode);
            }
        }
        if (doc.containsKey("boot")) {
            int boot = doc["boot"];
            if (boot >= BOOT_RESTORE_LAST && boot <= BOOT_ALWAYS_OFF) {
                _relay->setBootState(id, (BootStateMode)boot);
            }
        }
        if (doc.containsKey("autoOff")) _relay->setAutoOff(id, doc["autoOff"]);
        if (doc.containsKey("autoOn"))  _relay->setAutoOn(id, doc["autoOn"]);
        if (doc.containsKey("failsafe")) _relay->setFailsafe(id, doc["failsafe"]);

        _logger->logInfo("Relay", "Relay " + String(id + 1) + " config updated");
        sendOk(req);
    });

    // --- POST /api/relay/timer (MUST BE BEFORE /api/relay to prevent prefix capture) ---
    _server.on("/api/relay/timer", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_GUEST); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/relay/timer")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_GUEST, data, len, index, total, doc)) return;
        if (!_relay) { sendError(req, 500, F("Relay module not initialized")); return; }

        int id = doc["id"] | -1;
        String action = doc["action"] | "";
        uint32_t duration = doc["duration"] | 0; // seconds

        if (id < 0 || id >= (_relay ? _relay->getRelayCount() : NUM_RELAYS)) { sendError(req, 400, F("Invalid relay ID")); return; }

        if (action == "cancel") {
            uint8_t relayCount = (_relay && _ws) ? min((uint8_t)MAX_RELAYS, _relay->getRelayCount()) : 0;
            RelayTimerSnapshot beforeTimers[MAX_RELAYS] = {};
            captureRelayTimerSnapshots(_relay, _alarm, beforeTimers, relayCount);

            _relay->cancelTimer(id);
            if (_alarm) _alarm->cancelDelayTimersForRelay(id);
            broadcastChangedRelayTimers(_relay, _alarm, _ws, beforeTimers, relayCount, (int8_t)id);
            if (_logger) _logger->logInfo("Timer", "Timer cancelled for " + _relay->getName(id));
        } else if (action == "on" || action == "off") {
            if (duration == 0) { sendError(req, 400, F("Duration must be greater than 0")); return; }
            bool targetState = (action == "on");
            _relay->startTimer(id, targetState, duration);
            bool effActive = true;
            bool effTarget = targetState;
            uint32_t effRem = duration;
            if (_alarm) {
                _alarm->resolveEffectiveTimerForRelay(*_relay, id, effActive, effTarget, effRem);
            }
            if (_ws) _ws->broadcastRelayTimer(id, effActive, effTarget, effRem);
            if (_logger) _logger->logInfo("Timer", "Timer set: " + _relay->getName(id) + " -> " + (targetState ? "ON" : "OFF") + " in " + String(duration) + "s");
        } else {
            sendError(req, 400, F("Invalid action"));
            return;
        }

        sendOk(req);
    });

    // --- POST /api/relay ---
    _server.on("/api/relay", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_GUEST); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/relay")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_GUEST, data, len, index, total, doc)) return;

        int id = doc["id"] | -1;
        String action = doc["action"] | "";

        if (id < 0 || id >= (_relay ? _relay->getRelayCount() : NUM_RELAYS)) { sendError(req, 400, F("Invalid relay ID")); return; }

        if (action == "on")          _relay->setState(id, true);
        else if (action == "off")    _relay->setState(id, false);
        else if (action == "toggle") _relay->toggle(id);
        else { sendError(req, 400, F("Invalid action")); return; }

        sendOk(req);
    });

    // --- POST /api/buzzer ---
    _server.on("/api/buzzer", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_GUEST); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_GUEST, data, len, index, total, doc)) return;

        bool isAdmin = (!isAuthConfigured()) || (getRequestRole(req) == AUTH_ROLE_ADMIN);

        if (doc["action"].is<const char*>()) {
            String action = doc["action"] | "";
            if (action == "test") {
                if (!isAdmin) { sendError(req, 403, F("Forbidden: Admin privileges required")); return; }
                _buzzer->testBeep();
            }
            else if (action == "mute") _buzzer->mute();
            else if (action == "unmute") _buzzer->unmute();
            else if (action == "stop") _buzzer->stopAlarm();
        }
        if (doc.containsKey("enabled") || doc.containsKey("volume")) {
            if (!isAdmin) { sendError(req, 403, F("Forbidden: Admin privileges required")); return; }
        }
        if (doc.containsKey("enabled")) {
            bool en = doc["enabled"];
            if (en && !_buzzer->isHardwareAllowed()) {
                sendError(req, 400, F("Buzzer is disabled or GPIO pin unassigned in Hardware Profile"));
                return;
            }
            _buzzer->setEnabled(en);
        }
        if (doc.containsKey("volume")) {
            int vol = doc["volume"] | -1;
            if (vol < 0 || vol > 255) {
                sendError(req, 400, F("Buzzer volume must be 0-255"));
                return;
            }
            _buzzer->setVolume((uint8_t)vol);
        }

        sendOk(req);
    });

    // --- POST /api/alarm ---
    _server.on("/api/alarm", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        uint8_t relayCount = (_relay && _ws) ? min((uint8_t)MAX_RELAYS, _relay->getRelayCount()) : 0;
        RelayTimerSnapshot beforeTimers[MAX_RELAYS] = {};
        captureRelayTimerSnapshots(_relay, _alarm, beforeTimers, relayCount);

        // Delete
        if (doc["delete"] | false) {
            uint8_t id = doc["id"] | 0;
            if (_alarm->deleteAlarm(id)) {
                broadcastChangedRelayTimers(_relay, _alarm, _ws, beforeTimers, relayCount);
            }
            sendOk(req, F("Alarm deleted"));
            return;
        }

        // Enable/disable (only when not editing fields)
        if (doc.containsKey("id") && doc.containsKey("en") &&
            !doc.containsKey("hour") && !doc.containsKey("delay") && !doc.containsKey("action")) {
            uint8_t id = doc["id"] | 0;
            if (_alarm->enableAlarm(id, doc["en"])) {
                broadcastChangedRelayTimers(_relay, _alarm, _ws, beforeTimers, relayCount);
            }
            sendOk(req);
            return;
        }

        // Add or update timer task
        ScheduledAlarm a;
        JsonObject obj = doc.as<JsonObject>();
        if (!_alarm->fromJson(obj, a)) { sendError(req, 400, F("Invalid alarm data")); return; }

        uint8_t id = doc["id"] | 0;
        a.enabled = doc["en"] | true;
        a.fired = false;

        if (id > 0 && _alarm->getAlarm(id) != nullptr) {
            if (_alarm->updateAlarm(id, a)) {
                broadcastChangedRelayTimers(_relay, _alarm, _ws, beforeTimers, relayCount);
                _logger->logInfo("Alarm", "Alarm " + String(id) + " updated");
                sendOk(req, F("Alarm updated"));
            } else {
                sendError(req, 400, F("Alarm update failed"));
            }
        } else {
            a.id = _alarm->getNextId();
            if (_alarm->addAlarm(a)) {
                broadcastChangedRelayTimers(_relay, _alarm, _ws, beforeTimers, relayCount);
                _logger->logInfo("Alarm", "Alarm " + String(a.id) + " added");
                sendOk(req, F("Alarm added"));
            } else {
                sendError(req, 400, F("Max alarms reached"));
            }
        }
    });

    // --- POST /api/rule ---
    _server.on("/api/rule", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;
        if (!_rules) { sendError(req, 500, F("Rules module not initialized")); return; }

        // Delete
        if (doc["delete"] | false) {
            uint8_t id = doc["id"] | 0;
            _rules->deleteRule(id);
            if (_logger) _logger->logInfo("Rule", "Rule " + String(id) + " deleted");
            sendOk(req, F("Rule deleted"));
            return;
        }

        // Enable/disable (only when not editing rule fields)
        if (doc.containsKey("id") && doc.containsKey("en") &&
            !doc.containsKey("sensor") && !doc.containsKey("th") && !doc.containsKey("name")) {
            uint8_t id = doc["id"] | 0;
            _rules->enableRule(id, doc["en"]);
            sendOk(req);
            return;
        }

        // Add or update rule
        AutomationRule r;
        JsonObject obj = doc.as<JsonObject>();
        if (!_rules->fromJson(obj, r)) { sendError(req, 400, F("Invalid rule data")); return; }

        uint8_t id = doc["id"] | 0;
        r.enabled = doc["en"] | true;
        r.triggered = false;

        if (id > 0 && _rules->getRule(id) != nullptr) {
            if (_rules->updateRule(id, r)) {
                if (_logger) _logger->logInfo("Rule", "Rule " + String(id) + " updated");
                sendOk(req, F("Rule updated"));
            } else {
                sendError(req, 400, F("Rule update failed"));
            }
        } else {
            r.id = _rules->getNextId();
            if (_rules->addRule(r)) {
                if (_logger) _logger->logInfo("Rule", "Rule " + String(r.id) + " added");
                sendOk(req, F("Rule added"));
            } else {
                sendError(req, 400, F("Max rules reached"));
            }
        }
    });

    // --- POST /api/config/wifi ---
    _server.on("/api/config/wifi", HTTP_POST, [this](AsyncWebServerRequest* req) {
        bool bodyHandled = false;
        if (req && req->_tempObject) {
            TempBodyState* state = static_cast<TempBodyState*>(req->_tempObject);
            bodyHandled = state->handled;
            delete state;
            req->_tempObject = nullptr;
        }
        // Handle form POST from captive portal
        if (req->hasParam("ssid", true) && req->hasParam("pass", true)) {
            if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
            String ssid = req->getParam("ssid", true)->value();
            String pass = req->getParam("pass", true)->value();
            String dn = req->hasParam("device_name", true) ? req->getParam("device_name", true)->value() : "";
            bool authEn = req->hasParam("web_auth", true) && req->getParam("web_auth", true)->value() == "1";
            String wu = req->hasParam("web_user", true) ? req->getParam("web_user", true)->value() : "";
            String wp = req->hasParam("web_pass", true) ? req->getParam("web_pass", true)->value() : "";
            String ap = req->hasParam("ap_pass", true) ? req->getParam("ap_pass", true)->value() : "";
            bool apClear = req->hasParam("ap_pass_clear", true) && req->getParam("ap_pass_clear", true)->value() == "1";
            if (ap.length() > 0 && (ap.length() < 8 || ap.length() > 63)) {
                sendError(req, 400, F("SoftAP password must be 8-63 characters"));
                return;
            }
            bool hasAuth = authEn || wp.length() > 0 || ap.length() > 0 || apClear;
            if (!authEn && wp.length() == 0) wu = "";
            if (!applyWifiOnboardingSettings(req, dn, hasAuth, authEn, wu, wp, authEn, ap, apClear)) {
                sendError(req, 403, F("Admin authentication required to modify configured credentials"));
                return;
            }
            _wifi->saveCredentials(ssid, pass);
            _logger->logInfo("WiFi", "Credentials saved: " + ssid);
            req->send(200, "text/html", "<html><body style='background:#0f1117;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'><h2>Connecting to " + escapeHtml(ssid) + "...<br>Please wait.</h2></body></html>");
            return;
        }
        if (!bodyHandled) {
            if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
            sendError(req, 400, F("Empty request body"));
        }
    }, NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        // Handle JSON POST from dashboard
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        if (doc["action"] == "reset") {
            _wifi->resetWiFi();
            _logger->logWarning("WiFi", F("WiFi credentials reset"));
            sendOk(req, F("WiFi reset"));
            return;
        }

        String ssid = doc["ssid"] | "";
        String pass = doc["pass"] | "";
        if (ssid.length() > 0) {
            if (doc.containsKey("ap_pass") && !doc["ap_pass"].isNull() && !doc["ap_pass"].is<const char*>()) {
                sendError(req, 400, F("SoftAP password must be 8-63 characters"));
                return;
            }
            String ap = doc["ap_pass"].is<const char*>() ? (doc["ap_pass"] | "") : "";
            bool apClear = doc["ap_pass_clear"] | false;
            if (ap.length() > 0 && (ap.length() < 8 || ap.length() > 63)) {
                sendError(req, 400, F("SoftAP password must be 8-63 characters"));
                return;
            }
            String dn = doc["device_name"].is<const char*>() ? (doc["device_name"] | "") : "";
            bool hasAuth = doc.containsKey("web_auth") || doc.containsKey("web_user") ||
                           doc.containsKey("web_pass") || ap.length() > 0 || apClear;
            bool authEn = doc["web_auth"] | false;
            String wu = doc["web_user"].is<const char*>() ? (doc["web_user"] | "") : "";
            String wp = doc["web_pass"].is<const char*>() ? (doc["web_pass"] | "") : "";
            if (!applyWifiOnboardingSettings(req, dn, hasAuth, authEn, wu, wp, doc.containsKey("web_auth"), ap, apClear)) {
                sendError(req, 403, F("Admin authentication required to modify configured credentials"));
                return;
            }
            _wifi->saveCredentials(ssid, pass);
            _logger->logInfo("WiFi", "Credentials saved: " + ssid);
            sendOk(req, F("WiFi saved"));
        } else {
            sendError(req, 400, F("SSID required"));
        }
    });

    // --- POST /api/config/mqtt ---
    _server.on("/api/config/mqtt", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        if (doc.containsKey("enabled")) _mqtt->setEnabled(doc["enabled"]);
        if (doc.containsKey("broker")) {
            // `/api/config` intentionally never returns the MQTT password.
            // Treat a missing or empty `pass` in an update as "keep existing"
            // so changing a host, port, or prefix from the companion app
            // cannot silently erase a working broker credential.
            String password = _mqtt->getPassword();
            if (doc.containsKey("pass")) {
                String supplied = doc["pass"] | "";
                if (supplied.length() > 0) password = supplied;
            }
            _mqtt->saveConfig(
                doc["broker"] | "",
                doc["port"] | MQTT_DEFAULT_PORT,
                doc["user"] | "",
                password,
                doc["client_id"] | "",
                doc["prefix"] | MQTT_DEFAULT_PREFIX
            );
        }

        _logger->logInfo("MQTT", F("MQTT config updated"));
        sendOk(req);
    });

    // --- POST /api/config/lcd ---
    _server.on("/api/config/lcd", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        if (doc.containsKey("brightness")) {
            if (!doc["brightness"].is<int>()) {
                sendError(req, 400, F("LCD brightness must be 0-100"));
                return;
            }
            int brightVal = doc["brightness"].as<int>();
            if (brightVal < 0 || brightVal > 100) {
                sendError(req, 400, F("LCD brightness must be 0-100"));
                return;
            }
        }
        if (doc.containsKey("dim_brightness")) {
            if (!doc["dim_brightness"].is<int>()) {
                sendError(req, 400, F("LCD dimmed brightness must be 0-100"));
                return;
            }
            int dimVal = doc["dim_brightness"].as<int>();
            if (dimVal < 0 || dimVal > 100) {
                sendError(req, 400, F("LCD dimmed brightness must be 0-100"));
                return;
            }
        }

        if (doc.containsKey("display_mode")) {
            if (!doc["display_mode"].is<const char*>()) {
                sendError(req, 400, F("Invalid display_mode"));
                return;
            }
            String mode = doc["display_mode"] | "";
            if (mode != LCD_MODE_ROTATE && mode != LCD_MODE_DHT_RELAY && mode != LCD_MODE_CUSTOM) {
                sendError(req, 400, F("Unsupported LCD display_mode"));
                return;
            }
        }
        if (doc.containsKey("pages")) {
            if (!doc["pages"].is<JsonArrayConst>()) {
                sendError(req, 400, F("LCD pages must be an array"));
                return;
            }
            int validPages = 0;
            for (JsonVariantConst v : doc["pages"].as<JsonArrayConst>()) {
                if (v.is<const char*>() && LCDManager::isKnownPageId(v.as<const char*>())) {
                    validPages++;
                }
            }
            if (validPages == 0) {
                sendError(req, 400, F("Select at least one valid LCD page"));
                return;
            }
        }
        if (doc.containsKey("lines")) {
            if (!doc["lines"].is<JsonArrayConst>()) {
                sendError(req, 400, F("LCD lines must be an array"));
                return;
            }
            JsonArrayConst linesArr = doc["lines"].as<JsonArrayConst>();
            if (linesArr.size() == 0) {
                sendError(req, 400, F("LCD lines cannot be empty"));
                return;
            }
            uint8_t r = 0;
            for (JsonVariantConst v : linesArr) {
                if (r >= LCD_MAX_ROWS) break;
                if (!v.is<const char*>() || !LCDManager::isKnownWidgetId(v.as<const char*>())) {
                    sendError(req, 400, F("Invalid custom LCD row widget"));
                    return;
                }
                r++;
            }
        }

        if (doc.containsKey("enabled")) {
            bool en = doc["enabled"];
            if (en && !_lcd->isHardwareAllowed()) {
                sendError(req, 400, F("LCD is disabled in Hardware Profile or I2C pins unassigned"));
                return;
            }
            _lcd->setEnabled(en);
        }

        if (doc.containsKey("backlight")) {
            _lcd->setBacklight((bool)doc["backlight"]);
        }
        if (doc["display_mode"].is<const char*>()) {
            String mode = doc["display_mode"] | "";
            _lcd->setDisplayMode(mode);
        }
        if (doc.containsKey("pages")) {
            if (!_lcd->setPages(doc["pages"].as<JsonArrayConst>())) {
                sendError(req, 400, F("Select at least one valid LCD page"));
                return;
            }
        }
        if (doc.containsKey("lines")) {
            if (!_lcd->setCustomLines(doc["lines"].as<JsonArrayConst>())) {
                sendError(req, 400, F("Invalid custom LCD row widget"));
                return;
            }
        }
        if (doc.containsKey("rotation"))  _lcd->setRotationInterval(doc["rotation"]);
        if (doc.containsKey("brightness")) {
            _lcd->setBrightness((uint8_t)doc["brightness"].as<int>());
        }
        if (doc.containsKey("auto_dim"))   _lcd->setAutoDimEnabled(doc["auto_dim"]);
        if (doc["dim_start"].is<const char*>())  _lcd->setDimStartTime(doc["dim_start"] | "");
        if (doc["dim_end"].is<const char*>())    _lcd->setDimEndTime(doc["dim_end"] | "");
        if (doc.containsKey("dim_brightness")) {
            _lcd->setDimmedBrightness((uint8_t)doc["dim_brightness"].as<int>());
        }

        sendOk(req);
    });

    // --- POST /api/config/sensor ---
    _server.on("/api/config/sensor", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        bool hasIdx = doc.containsKey("sensor_index");
        int sIdx = hasIdx ? (int)(doc["sensor_index"] | -1) : -1;
        bool hasCliKey = doc.containsKey("temp_offset") || doc.containsKey("hum_offset");
        bool hasMq2Key = doc.containsKey("mq2_enabled") || doc.containsKey("mq2_threshold") ||
                         (doc.containsKey("calibrate_mq2") && (bool)doc["calibrate_mq2"]);
        if (hasIdx) {
            if (sIdx < 0 ||
                (hasCliKey && sIdx >= MAX_CLIMATE_SENSORS) ||
                (hasMq2Key && sIdx >= MAX_MQ2_SENSORS)) {
                sendError(req, 400, F("Invalid sensor_index"));
                return;
            }
        }

        if (doc.containsKey("temp_offset")) {
            float off = doc["temp_offset"] | 0.0f;
            if (!isfinite(off) || off < -50.0f || off > 50.0f) {
                sendError(req, 400, F("Invalid temp_offset"));
                return;
            }
            if (hasIdx && sIdx >= 0) _sensor->setTempOffsetAt((uint8_t)sIdx, off);
            else _sensor->setTempOffset(off);
        }
        if (doc.containsKey("hum_offset")) {
            float off = doc["hum_offset"] | 0.0f;
            if (!isfinite(off) || off < -50.0f || off > 50.0f) {
                sendError(req, 400, F("Invalid hum_offset"));
                return;
            }
            if (hasIdx && sIdx >= 0) _sensor->setHumOffsetAt((uint8_t)sIdx, off);
            else _sensor->setHumOffset(off);
        }
        if (doc.containsKey("temp_alarm")) {
            float alarmTh = doc["temp_alarm"] | 0.0f;
            if (!isfinite(alarmTh) || alarmTh < -50.0f || alarmTh > 150.0f) {
                sendError(req, 400, F("Invalid temp_alarm"));
                return;
            }
            _sensor->setTempAlarmThreshold(alarmTh);
        }
        if (doc.containsKey("mq2_enabled")) {
            bool en = doc["mq2_enabled"];
            bool allowed = (hasIdx && sIdx >= 0)
                ? _sensor->isMq2HwAllowedAt((uint8_t)sIdx)
                : _sensor->isMQ2HardwareAllowed();
            if (en && !allowed) {
                sendError(req, 400, F("Gas/VOC sensor is disabled or pins/I2C unassigned in Hardware Profile"));
                return;
            }
            if (hasIdx && sIdx >= 0) _sensor->setMQ2EnabledAt((uint8_t)sIdx, en);
            else _sensor->setMQ2Enabled(en);
        }
        if (doc.containsKey("mq2_threshold")) {
            int th = doc["mq2_threshold"];
            if (hasIdx && sIdx >= 0) _sensor->setMQ2ThresholdAt((uint8_t)sIdx, th);
            else _sensor->setMQ2Threshold(th);
        }
        if (doc.containsKey("calibrate_mq2") && doc["calibrate_mq2"]) {
            if (hasIdx && sIdx >= 0) _sensor->calibrateMQ2At((uint8_t)sIdx);
            else _sensor->calibrateMQ2();
        }

        _sensor->saveCalibration();
        sendOk(req);
    });

    // --- POST /api/config ---
    _server.on("/api/config", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/config")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;

        bool apPassClear = doc["ap_pass_clear"] | false;
        if (doc.containsKey("ap_pass") && !doc["ap_pass"].isNull() && !doc["ap_pass"].is<const char*>()) {
            sendError(req, 400, F("SoftAP password must be 8-63 characters"));
            return;
        }
        String apPass = doc["ap_pass"].is<const char*>() ? (doc["ap_pass"] | "") : "";
        if (!apPassClear && apPass.length() > 0 && (apPass.length() < 8 || apPass.length() > 63)) {
            sendError(req, 400, F("SoftAP password must be 8-63 characters"));
            return;
        }

        if (doc.containsKey("alert_webhook_url") && !doc["alert_webhook_url"].isNull() &&
            !doc["alert_webhook_url"].is<const char*>()) {
            sendError(req, 400, F("Invalid webhook URL"));
            return;
        }

        JsonDocument cfg;
        _storage->loadJson(PATH_CONFIG, cfg);

        if (doc.containsKey("alert_webhook_en") || doc.containsKey("alert_webhook_url")) {
            bool whEn = doc.containsKey("alert_webhook_en")
                ? (doc["alert_webhook_en"] | false)
                : (cfg["alert_webhook_en"] | false);
            String whUrl = doc.containsKey("alert_webhook_url")
                ? (doc["alert_webhook_url"].is<const char*>() ? (doc["alert_webhook_url"] | "") : "")
                : (cfg["alert_webhook_url"] | "");
            whUrl.trim();
            String whErr;
            if (!RemoteAlertManager::validateUrl(whUrl, whEn, whErr)) {
                sendError(req, 400, whErr);
                return;
            }
        }

        if (doc.containsKey("device_name")) {
            String dn = doc["device_name"] | DEFAULT_DEVICE_NAME;
            dn.trim();
            if (dn.length() > 0) {
                _deviceName = dn;
                cfg["device_name"] = dn;
            }
        }
        if (doc.containsKey("hostname")) {
            String h = doc["hostname"] | "";
            h.trim();
            if (h.length() > 0) cfg["hostname"] = h;
            else cfg.remove("hostname");
        }
        if (doc["timezone"].is<const char*>()) {
            String tz = doc["timezone"] | "";
            if (tz.length() > 0) {
                cfg["timezone"] = tz;
                _time->setTimezone(tz);
            }
        }
        if (doc.containsKey("use_24h")) {
            cfg["use_24h"] = doc["use_24h"];
            _time->setUse24h(doc["use_24h"]);
        }
        if (doc.containsKey("web_auth")) {
            cfg["web_auth"] = doc["web_auth"];
            _webAuthEnabled = doc["web_auth"];
        }
        if (doc["web_user"].is<const char*>()) {
            String u = doc["web_user"] | "";
            u.trim();
            if (u.length() == 0) u = "admin";
            cfg["web_user"] = u;
            _webUsername = u;
        }
        if (doc["web_pass"].is<const char*>()) {
            String pass = doc["web_pass"] | "";
            if (pass.length() > 0) {
                _webPasswordHash = hashPasswordSalted(pass);
                cfg["web_pass_hash"] = _webPasswordHash;
                cfg["ota_pass_md5"] = md5Hex(pass);
                cfg.remove("web_pass"); // Never write plaintext password to flash
                _webPassword = pass;
            }
        }
        if (doc.containsKey("guest_auth")) {
            _guestAuthEnabled = doc["guest_auth"] | false;
            cfg["guest_auth"] = _guestAuthEnabled;
        }
        if (doc["guest_user"].is<const char*>()) {
            String gu = doc["guest_user"] | "";
            gu.trim();
            if (gu.length() == 0) gu = "guest";
            cfg["guest_user"] = gu;
            _guestUsername = gu;
        }
        if (doc["guest_pass"].is<const char*>()) {
            String gpass = doc["guest_pass"] | "";
            if (gpass.length() > 0) {
                _guestPasswordHash = hashPasswordSalted(gpass);
                cfg["guest_pass_hash"] = _guestPasswordHash;
                cfg.remove("guest_pass");
                _guestPassword = gpass;
            } else if (doc["guest_pass_clear"] | false) {
                _guestPasswordHash = "";
                _guestPassword = "";
                cfg.remove("guest_pass_hash");
                cfg.remove("guest_pass");
            }
        } else if (doc["guest_pass_clear"] | false) {
            _guestPasswordHash = "";
            _guestPassword = "";
            cfg.remove("guest_pass_hash");
            cfg.remove("guest_pass");
        }
        if (apPassClear) {
            cfg.remove("ap_pass");
        } else if (apPass.length() > 0) {
            cfg["ap_pass"] = apPass;
        }
        if (doc.containsKey("alert_webhook_en") || doc.containsKey("alert_webhook_url") ||
            doc.containsKey("alert_webhook_token") || (doc["alert_webhook_token_clear"] | false)) {
            bool whEn = doc.containsKey("alert_webhook_en")
                ? (doc["alert_webhook_en"] | false)
                : (cfg["alert_webhook_en"] | false);
            String whUrl = doc.containsKey("alert_webhook_url")
                ? (doc["alert_webhook_url"].is<const char*>() ? (doc["alert_webhook_url"] | "") : "")
                : (cfg["alert_webhook_url"] | "");
            whUrl.trim();
            bool hasTok = doc["alert_webhook_token"].is<const char*>();
            String whTok = hasTok ? (doc["alert_webhook_token"] | "") : "";
            bool clrTok = doc["alert_webhook_token_clear"] | false;
            cfg["alert_webhook_en"] = whEn;
            if (whUrl.length() > 0) cfg["alert_webhook_url"] = whUrl;
            else cfg.remove("alert_webhook_url");
            if (clrTok) cfg.remove("alert_webhook_token");
            else if (hasTok && whTok.length() > 0) cfg["alert_webhook_token"] = whTok;
            if (_remoteAlert) {
                _remoteAlert->applyConfig(whEn, whUrl, hasTok, whTok, clrTok);
            }
        }
        if (doc.containsKey("web_auth") || doc.containsKey("web_user") || doc.containsKey("web_pass") ||
            doc.containsKey("guest_auth") || doc.containsKey("guest_user") || doc.containsKey("guest_pass") ||
            (doc["guest_pass_clear"] | false)) {
            // Clear rate limits so newly configured credentials never hit a stale lockout
            for (int i = 0; i < RATE_LIMIT_CACHE_SIZE; i++) {
                _rateLimits[i].ip = IPAddress(0, 0, 0, 0);
                _rateLimits[i].failedCount = 0;
                _rateLimits[i].lockoutUntil = 0;
                _rateLimits[i].lastAttempt = 0;
            }
            // Rotate WebSocket token and immediately drop existing WebSocket sessions
            // so any connected companion app or browser must re-authenticate with the new password!
            regenerateWsToken();
            if (_ws) _ws->disconnectAll();
        }
        if (doc.containsKey("arduino_ota")) {
            bool en = doc["arduino_ota"];
            cfg["arduino_ota"] = en;
            String otaSecret = _webPassword;
            bool isHash = false;
            if (otaSecret.length() == 0) {
                String savedMd5 = cfg["ota_pass_md5"] | "";
                if (savedMd5.length() == 32) {
                    otaSecret = savedMd5;
                    isHash = true;
                }
            }
            if (_ota) _ota->setArduinoOtaEnabled(en, _wifi ? _wifi->getHostname() : "", otaSecret, isHash);
            _logger->logInfo("OTA", en ? "ArduinoOTA port 3232 enabled" : "ArduinoOTA port 3232 disabled");
        } else if (_ota && _ota->isArduinoOtaEnabled() && _webPassword.length() > 0 && doc["web_pass"].is<const char*>()) {
            _ota->setArduinoOtaEnabled(true, _wifi ? _wifi->getHostname() : "", _webPassword, false);
        }

        _storage->saveJson(PATH_CONFIG, cfg);
        _logger->logInfo("Config", F("Device config updated"));
        JsonDocument resDoc;
        resDoc["status"] = "ok";
        resDoc["message"] = "OK";
        resDoc["ws_token"] = _wsToken;
        sendJson(req, 200, resDoc);
    });

    // --- GET /api/hardware ---
    _server.on("/api/hardware", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        JsonObject obj = doc.to<JsonObject>();
        if (_hw) {
            _hw->toJson(obj);
            obj["platform"] = PLATFORM_NAME;
            JsonArray presets = obj["presets"].to<JsonArray>();
            HardwareManager::getPresetsJson(presets);
            JsonObject caps = obj["pin_capabilities"].to<JsonObject>();
            HardwareManager::getPinCapabilitiesJson(caps);
        } else {
            obj["error"] = "Hardware manager not initialized";
        }
        sendJson(req, 200, doc);
    });

    // --- POST /api/hardware/template ---
    _server.on("/api/hardware/template", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/hardware/template")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;
        if (!_hw) { sendError(req, 500, F("Hardware manager not initialized")); return; }

        String templateName = doc["template"] | "";
        if (templateName.length() == 0) {
            sendError(req, 400, F("Template name required"));
            return;
        }

        if (!_hw->applyPreset(templateName)) {
            sendError(req, 400, "Unknown template preset: " + templateName);
            return;
        }

        _logger->logInfo("Hardware", "Preset applied: " + templateName);
        _logger->persistNow();

        JsonDocument res;
        res["status"] = "ok";
        res["message"] = "Preset applied. Rebooting...";
        res["reboot_required"] = true;
        sendJson(req, 200, res);

        requestReboot(1500);
    });

    // --- POST /api/hardware/reset ---
    _server.on("/api/hardware/reset", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!req->url().equals("/api/hardware/reset")) return;
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        if (!_hw) { sendError(req, 500, F("Hardware manager not initialized")); return; }

        _hw->resetToDefault();
#if defined(ESP8266)
        _logger->logWarning("Hardware", F("Hardware profile reset to ESP8266 2-CH default"));
#else
        _logger->logWarning("Hardware", F("Hardware profile reset to 5-CH Standard default"));
#endif
        _logger->persistNow();

        JsonDocument res;
        res["status"] = "ok";
#if defined(ESP8266)
        res["message"] = "Hardware configuration reset to default 2-CH. Rebooting...";
#else
        res["message"] = "Hardware configuration reset to default 5-CH. Rebooting...";
#endif
        res["reboot_required"] = true;
        sendJson(req, 200, res);

        requestReboot(1500);
    });

    // --- POST /api/hardware ---
    _server.on("/api/hardware", HTTP_POST, [this](AsyncWebServerRequest* req) { finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN); },
        NULL, [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
        if (!req->url().equals("/api/hardware")) return;
        JsonDocument doc;
        if (!authorizeAndCollectJson(req, AUTH_ROLE_ADMIN, data, len, index, total, doc)) return;
        if (!_hw) { sendError(req, 500, F("Hardware manager not initialized")); return; }

        String err;
        if (!_hw->fromJson(doc.as<JsonObjectConst>(), err)) {
            sendError(req, 400, err);
            return;
        }

        if (!_hw->save()) {
            sendError(req, 500, F("Failed to save hardware configuration to flash"));
            return;
        }

        _logger->logInfo("Hardware", "Hardware profile updated (" + String(_hw->getBoardName()) + ")");
        _logger->persistNow();

        JsonDocument res;
        res["status"] = "ok";
        res["message"] = "Hardware profile saved successfully. Rebooting...";
        res["reboot_required"] = true;
        sendJson(req, 200, res);

        requestReboot(1500);
    });

    // --- POST /api/reboot ---
    _server.on("/api/reboot", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        _logger->logWarning("System", F("Reboot requested via web"));
        _logger->persistNow();
        _relay->saveStates();
        sendOk(req, F("Rebooting..."));
        requestReboot(1000);
    });

    // --- POST /api/factory-reset ---
    _server.on("/api/factory-reset", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        _logger->logCritical("System", F("Factory reset requested"));
        sendOk(req, F("Factory resetting..."));
        _storage->factoryReset();
        requestReboot(2000);
    });

    // --- POST /api/restore ---
    _server.on("/api/restore", HTTP_POST,
        [this](AsyncWebServerRequest* req) {
            finishEmptyOrTempBody(req, AUTH_ROLE_ADMIN);
        },
        NULL,
        [this](AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total) {
            TempBodyState* state = (index == 0)
                ? ensureTempBodyState(req)
                : (req ? static_cast<TempBodyState*>(req->_tempObject) : nullptr);
            if (!state) return;

            if (index == 0) {
                if (!isAuthorized(req, AUTH_ROLE_ADMIN)) {
                    state->handled = true;
                    return;
                }
            } else if (state->handled) {
                return;
            }

            // Cap restore payload to prevent memory exhaustion (max 32KB)
            if (total == 0 || total > 32768 || index + len > 32768) {
                state->body = String();
                state->handled = true;
                if (index == 0) {
                    sendError(req, total == 0 ? 400 : 413, total == 0 ? "Empty backup payload" : "Backup payload too large");
                }
                return;
            }

            // Accumulate body chunks across TCP fragmentation
            if (index == 0) {
                state->body.reserve(total + 1);
            }

            state->body.concat((const char*)data, len);

            // Once the full body has arrived, parse and restore
            if (index + len >= total) {
                String body = std::move(state->body);
                state->body = String();
                state->handled = true;

                bool success = false;

                if (body.length() > 0) {
                    JsonDocument doc;
                    DeserializationError err = deserializeJson(doc, body);
                    // Free the raw string buffer immediately to maximize heap for importAllConfig
                    body = String();

                    if (!err) {
                        // Format 1: wrapper with string config {"config": "..."}
                        if (doc.containsKey("config") && doc["config"].is<const char*>()) {
                            String cfgStr = doc["config"].as<String>();
                            doc.clear(); // Free outer document before parsing inner JSON string
                            success = _storage->importAllConfig(cfgStr);
                        }
                        // Format 2: wrapper with object config {"config": {...}}
                        else if (doc.containsKey("config") && doc["config"].is<JsonObject>()) {
                            success = _storage->importAllConfig(doc["config"].as<JsonObjectConst>());
                        }
                        // Format 3: direct backup object {"config.json": {...}, ...}
                        else if (doc.is<JsonObject>()) {
                            success = _storage->importAllConfig(doc.as<JsonObjectConst>());
                        }
                    }
                }

                if (success) {
                    _logger->logInfo("System", F("Config restored from backup"));
                    _logger->persistNow();
                    // Freeze further flash writes immediately so background loops (relayMgr, logger)
                    // cannot overwrite restored files during the 1000ms reboot window!
                    _storage->setWriteEnabled(false);
                    sendOk(req, F("Config restored. Rebooting..."));
                    requestReboot(1000);
                } else {
                    sendError(req, 400, F("Invalid config data or corrupted backup"));
                }
            }
        }
    );

    // --- POST /api/logs/clear ---
    _server.on("/api/logs/clear", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        _logger->clear();
        sendOk(req, F("Logs cleared"));
    });

    // --- POST /api/alert/test ---
    _server.on("/api/alert/test", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        if (!_remoteAlert) {
            sendError(req, 500, F("Remote alert service not initialized"));
            return;
        }
        String err;
        String mac = _wifi ? _wifi->getMAC() : "";
        if (_remoteAlert->sendTestAlert(_deviceName, mac, err)) {
            sendOk(req, F("Remote test alert dispatched"));
        } else {
            sendError(req, 400, err.length() > 0 ? err : F("Failed to send remote alert"));
        }
    });

    // -----------------------------------------------------------------------
    // POST /api/ota/upload  — HTTP firmware/filesystem upload
    // Accepts multipart with field "firmware" or "filesystem"
    // -----------------------------------------------------------------------
    static auto setOtaTempMarker = [](AsyncWebServerRequest* req, uint8_t code) {
        if (!req) return;
        if (!req->_tempObject) req->_tempObject = malloc(1);
        if (req->_tempObject) *static_cast<uint8_t*>(req->_tempObject) = code;
    };
    static auto peekOtaTempMarker = [](const AsyncWebServerRequest* req) -> uint8_t {
        return (req && req->_tempObject) ? *static_cast<const uint8_t*>(req->_tempObject) : 0;
    };
    static auto consumeOtaTempMarker = [](AsyncWebServerRequest* req) -> uint8_t {
        if (!req || !req->_tempObject) return 0;
        uint8_t code = *static_cast<uint8_t*>(req->_tempObject);
        free(req->_tempObject);
        req->_tempObject = nullptr;
        return code;
    };

    _server.on("/api/ota/upload", HTTP_POST,
        // Request handler — sends final response after upload completes
        [this](AsyncWebServerRequest* req) {
            uint8_t marker = consumeOtaTempMarker(req);
            bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
            if (marker == 3 || isAP) {
                sendError(req, 403, F("OTA upload is disabled in AP mode"));
                return;
            }
            if (marker == 2) {
                sendError(req, 409, F("Another OTA update is already in progress"));
                return;
            }
            if (marker == 1) {
                isAuthorized(req, AUTH_ROLE_ADMIN);
                return;
            }
            if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
            if (_ota->lastHttpUpdateOk()) {
                sendOk(req, F("Update complete. Rebooting..."));
                // Request reboot in 1 second via main loop so the async HTTP
                // response is fully sent before we reboot.
                requestReboot(1000);
            } else {
                sendError(req, 500, _ota->lastHttpError().length() > 0
                                    ? _ota->lastHttpError()
                                    : "Upload failed or no file received");
            }
        },
        // Upload handler — receives file chunks
        [this](AsyncWebServerRequest* req, const String& filename,
               size_t index, uint8_t* data, size_t len, bool final) {
            uint8_t existingMarker = peekOtaTempMarker(req);
            if (existingMarker == 1 || existingMarker == 2 || existingMarker == 3) {
                return;
            }
            bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
            if (isAP) {
                setOtaTempMarker(req, 3);
                return;
            }
            IPAddress clientIp = req->client() ? req->client()->remoteIP() : IPAddress(0, 0, 0, 0);
            String xrw = req->header("X-Requested-With");
            bool csrfOk = !isAuthConfigured() || (xrw == "SmartHome" || xrw == "SmartHomeCompanionApp");
            bool allowed = csrfOk && !isRateLimited(clientIp) &&
                           (!isAuthConfigured() || getRequestRole(req) >= AUTH_ROLE_ADMIN);
            if (!allowed) {
                setOtaTempMarker(req, 1);
                return;
            }
            // Determine type from filename extension or query param
            bool isFirmware = true;
            if (req->hasParam("type")) {
                isFirmware = (req->getParam("type")->value() != "fs");
            } else {
                String lower = filename;
                lower.toLowerCase();
                if (lower.indexOf("spiffs") >= 0 || lower.indexOf("littlefs") >= 0
                    || lower.indexOf("fs.bin") >= 0) {
                    isFirmware = false;
                }
            }

            // Get real content-length for Update.begin() sizing.
            // ESPAsyncWebServer doesn't pass total to the file upload cb directly,
            // so we read Content-Length from the request header.
            // On first chunk (index==0) this is used; subsequent chunks pass 0
            // as total so OTAManager knows to skip re-calling begin().
            size_t contentLen = 0;
            if (index == 0) {
                if (_ota && _ota->isUpdating()) {
                    setOtaTempMarker(req, 2);
                    return;
                }
                req->onDisconnect([this, req]() {
                    if (_ota) _ota->abortHttpUpload("Client disconnected during upload", req);
                });
                if (req->hasHeader("Content-Length")) {
                    contentLen = (size_t)req->getHeader("Content-Length")->value().toInt();
                }
                // Fallback: use UPDATE_SIZE_UNKNOWN (OTAManager handles this)
            }

            bool conflict = false;
            if (!_ota->handleHttpUpload(data, len, index, contentLen, isFirmware, final, req, &conflict)) {
                if (conflict) {
                    setOtaTempMarker(req, 2);
                } else {
                    Serial.println(F("[Web] HTTP OTA upload error"));
                }
            }
        }
    );

    // GET /api/ota/status  — poll update progress + firmware version (for verification)
    _server.on("/api/ota/status", HTTP_GET, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req)) return;
        JsonDocument doc;
        doc["updating"]   = _ota->isUpdating();
        doc["progress"]   = _ota->getProgress();
        doc["status"]     = _ota->getStatusString();
        doc["partition"]  = _ota->getRunningPartitionName();
        doc["ota_state"]  = _ota->getOtaStateString();
        doc["rollback_possible"] = _ota->isRollbackPossible();
        doc["last_ok"]    = _ota->lastHttpUpdateOk();
        doc["last_error"] = _ota->lastHttpError();
        doc["fw_version"] = FW_VERSION;
        doc["fw_date"]    = String(FW_BUILD_DATE) + " " + String(FW_BUILD_TIME);
        static String cachedMd5;
        if (cachedMd5.length() == 0) cachedMd5 = ESP.getSketchMD5();
        doc["fw_md5"]     = cachedMd5;
        doc["uptime_sec"] = millis() / 1000UL;
        sendJson(req, 200, doc);
    });

    // POST /api/ota/rollback — Manual rollback to previous partition
    _server.on("/api/ota/rollback", HTTP_POST, [this](AsyncWebServerRequest* req) {
        if (!isAuthorized(req, AUTH_ROLE_ADMIN)) return;
        if (!_ota->isRollbackPossible()) {
            sendError(req, 400, F("Rollback not possible: no previous valid firmware found"));
            return;
        }
        sendOk(req, F("Rollback confirmed. Rebooting into previous partition..."));
        _logger->logWarning("OTA", F("User triggered manual firmware rollback to alternate partition."));
        requestRollbackReboot(1000);
    });

    // --- 404 handler ---
    _server.onNotFound([this](AsyncWebServerRequest* req) {
        // In AP mode, redirect to captive portal
        if (_wifi->getState() == WIFI_ST_AP_MODE) {
            AsyncWebServerResponse* r = req->beginResponse_P(200, "text/html", PAGE_CAPTIVE);
            r->addHeader("Connection", "close");
            req->send(r);
        } else {
            sendError(req, 404, F("Not Found"));
        }
    });
}

// ============================================================================
// Captive Portal DNS redirect setup
// ============================================================================
void WebServerManager::setupCaptivePortal() {
    // Android captive portal detection
    _server.on("/generate_204", HTTP_GET, [](AsyncWebServerRequest* req) {
        req->redirect("/");
    });

    // Microsoft captive portal detection
    _server.on("/connecttest.txt", HTTP_GET, [](AsyncWebServerRequest* req) {
        req->redirect("/");
    });

    // Apple captive portal detection
    _server.on("/hotspot-detect.html", HTTP_GET, [](AsyncWebServerRequest* req) {
        req->redirect("/");
    });
}

// ============================================================================
// Response Helpers
// ============================================================================
void WebServerManager::sendJson(AsyncWebServerRequest* req, int code, const JsonDocument& doc) {
    AsyncResponseStream *response = req->beginResponseStream("application/json");
    response->setCode(code);
    response->addHeader("Connection", "close");
    serializeJson(doc, *response);
    req->send(response);
}

void WebServerManager::sendOk(AsyncWebServerRequest* req, const String& message) {
    JsonDocument doc;
    doc["status"] = "ok";
    doc["message"] = message;
    sendJson(req, 200, doc);
}

void WebServerManager::sendError(AsyncWebServerRequest* req, int code, const String& message) {
    JsonDocument doc;
    doc["status"] = "error";
    doc["message"] = message;
    sendJson(req, code, doc);
}

void WebServerManager::cleanTempObject(AsyncWebServerRequest* req) {
    if (req && req->_tempObject) {
        delete static_cast<TempBodyState*>(req->_tempObject);
        req->_tempObject = nullptr;
    }
}

void WebServerManager::finishEmptyOrTempBody(AsyncWebServerRequest* req, AuthRole requiredRole) {
    if (!req) return;
    bool bodyHandled = false;
    if (req->_tempObject) {
        TempBodyState* state = static_cast<TempBodyState*>(req->_tempObject);
        bodyHandled = state->handled;
        delete state;
        req->_tempObject = nullptr;
    }
    if (!bodyHandled) {
        if (!isAuthorized(req, requiredRole)) return;
        sendError(req, 400, F("Empty request body"));
    }
}

bool WebServerManager::authorizeAndCollectJson(AsyncWebServerRequest* req, AuthRole requiredRole,
                                               uint8_t* data, size_t len, size_t index, size_t total,
                                               JsonDocument& doc) {
    TempBodyState* state = (index == 0)
        ? ensureTempBodyState(req)
        : (req ? static_cast<TempBodyState*>(req->_tempObject) : nullptr);
    if (!state) return false;
    if (index == 0) {
        if (!isAuthorized(req, requiredRole)) {
            state->handled = true;
            return false;
        }
    } else if (state->handled) {
        return false;
    }
    return collectJsonBody(req, data, len, index, total, doc);
}

bool WebServerManager::collectJsonBody(AsyncWebServerRequest* req, uint8_t* data, size_t len, size_t index, size_t total, JsonDocument& doc) {
    TempBodyState* state = (index == 0)
        ? ensureTempBodyState(req)
        : (req ? static_cast<TempBodyState*>(req->_tempObject) : nullptr);
    if (!state) return false;

    if (total == 0 || total > 16384 || index + len > 16384) {
        state->body = String();
        state->handled = true;
        if (index == 0) {
            sendError(req, total == 0 ? 400 : 413, total == 0 ? "Empty request body" : "Payload too large");
        }
        return false;
    }

    // Fast path: entire body arrived in a single chunk
    if (index == 0 && len == total) {
        state->handled = true;
        DeserializationError err = deserializeJson(doc, (const char*)data, len);
        if (err) {
            SERIAL_PRINTF("[Web] JSON parse error on single chunk: %s\n", err.c_str());
            sendError(req, 400, F("Invalid JSON"));
            return false;
        }
        return true;
    }

    // Multi-chunk path: TCP fragmentation reassembly
    if (index == 0) {
        state->body.reserve(total + 1);
    }

    state->body.concat((const char*)data, len);

    if (index + len >= total) {
        DeserializationError err = deserializeJson(doc, state->body);
        state->body = String();
        state->handled = true;
        if (err) {
            SERIAL_PRINTF("[Web] JSON parse error on reassembled body: %s\n", err.c_str());
            sendError(req, 400, F("Invalid JSON"));
            return false;
        }
        return true;
    }

    return false; // Waiting for more chunks
}

bool WebServerManager::isRateLimited(const IPAddress& ip) {
    unsigned long now = millis();
    for (int i = 0; i < RATE_LIMIT_CACHE_SIZE; i++) {
        if (_rateLimits[i].ip == ip && _rateLimits[i].lockoutUntil != 0) {
            if ((long)(_rateLimits[i].lockoutUntil - now) > 0) {
                return true;
            }
            _rateLimits[i].failedCount = 0;
            _rateLimits[i].lockoutUntil = 0;
        }
    }
    return false;
}

void WebServerManager::recordFailedAttempt(const IPAddress& ip) {
    unsigned long now = millis();
    int emptySlot = -1;
    unsigned long maxAge = 0;
    int oldestSlot = 0;

    for (int i = 0; i < RATE_LIMIT_CACHE_SIZE; i++) {
        if (_rateLimits[i].ip == ip) {
            if (_rateLimits[i].lockoutUntil != 0 && (long)(now - _rateLimits[i].lockoutUntil) >= 0) {
                _rateLimits[i].failedCount = 0;
                _rateLimits[i].lockoutUntil = 0;
            }
            _rateLimits[i].failedCount++;
            _rateLimits[i].lastAttempt = now;
            if (_rateLimits[i].failedCount >= 5) {
                unsigned long lockUntil = now + (5 * 60 * 1000UL); // 5 min lockout
                if (lockUntil == 0) lockUntil = 1; // 0 is reserved for "not locked out"
                _rateLimits[i].lockoutUntil = lockUntil;
                if (_logger) {
                    _logger->logWarning("Security", "IP " + ip.toString() + " locked out (rate limit)");
                }
            }
            return;
        }
        if (_rateLimits[i].ip == IPAddress(0, 0, 0, 0) && emptySlot == -1) {
            emptySlot = i;
        }
        unsigned long age = now - _rateLimits[i].lastAttempt;
        if (age >= maxAge) {
            maxAge = age;
            oldestSlot = i;
        }
    }

    int slot = (emptySlot != -1) ? emptySlot : oldestSlot;
    _rateLimits[slot].ip = ip;
    _rateLimits[slot].failedCount = 1;
    _rateLimits[slot].lockoutUntil = 0;
    _rateLimits[slot].lastAttempt = now;
}

void WebServerManager::resetRateLimit(const IPAddress& ip) {
    for (int i = 0; i < RATE_LIMIT_CACHE_SIZE; i++) {
        if (_rateLimits[i].ip == ip) {
            _rateLimits[i].ip = IPAddress(0, 0, 0, 0);
            _rateLimits[i].failedCount = 0;
            _rateLimits[i].lockoutUntil = 0;
            _rateLimits[i].lastAttempt = 0;
            return;
        }
    }
}

String WebServerManager::sha256Hex(const String& input) {
    unsigned char hash[32];
#if defined(ESP8266)
    br_sha256_context ctx;
    br_sha256_init(&ctx);
    br_sha256_update(&ctx, (const void*)input.c_str(), input.length());
    br_sha256_out(&ctx, hash);
#else
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0); // 0 = SHA-256
    mbedtls_sha256_update(&ctx, (const unsigned char*)input.c_str(), input.length());
    mbedtls_sha256_finish(&ctx, hash);
    mbedtls_sha256_free(&ctx);
#endif

    char hex[65];
    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    hex[64] = '\0';
    return String(hex);
}

String WebServerManager::hashPasswordSalted(const String& pass) {
#if defined(ESP8266)
    uint32_t r1 = ESP.random();
    uint32_t r2 = ESP.random();
#else
    uint32_t r1 = esp_random();
    uint32_t r2 = esp_random();
#endif
    char salt[17];
    snprintf(salt, sizeof(salt), "%08lx%08lx", (unsigned long)r1, (unsigned long)r2);
    return String(F("$s2$")) + salt + "$" + sha256Hex(String(salt) + ":" + pass);
}

bool WebServerManager::verifyPasswordHash(const String& pass, const String& storedHash) {
    if (storedHash.startsWith("$s2$") && storedHash.length() == 85 && storedHash.charAt(20) == '$') {
        String salt = storedHash.substring(4, 20);
        String expected = storedHash.substring(21);
        return constantTimeCompare(sha256Hex(salt + ":" + pass), expected);
    }
    return constantTimeCompare(sha256Hex(pass), storedHash);
}

String WebServerManager::md5Hex(const String& input) {
#if defined(ESP8266)
    MD5Builder md5;
    md5.begin();
    md5.add(input);
    md5.calculate();
    return md5.toString();
#else
    unsigned char hash[16];
    mbedtls_md5_context ctx;
    mbedtls_md5_init(&ctx);
    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, (const unsigned char*)input.c_str(), input.length());
    mbedtls_md5_finish(&ctx, hash);
    mbedtls_md5_free(&ctx);

    char hex[33];
    for (int i = 0; i < 16; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    hex[32] = '\0';
    return String(hex);
#endif
}

bool WebServerManager::constantTimeCompare(const String& a, const String& b) {
    if (a.length() != b.length()) return false;
    volatile uint8_t result = 0;
    for (size_t i = 0; i < a.length(); i++) {
        result |= (a[i] ^ b[i]);
    }
    return result == 0;
}

bool WebServerManager::applyWifiOnboardingSettings(AsyncWebServerRequest* req, const String& deviceName,
                                                   bool hasAuthFields, bool webAuth, const String& webUser,
                                                   const String& webPass, bool updateWebAuthFlag,
                                                   const String& apPass, bool apPassClear) {
    bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
    bool authAlreadyConfigured = _webAuthEnabled &&
        (_webPasswordHash.length() > 0 || _webPassword.length() > 0);
    if (isAP && authAlreadyConfigured && hasAuthFields &&
        authenticateBasicCredentials(req) != AUTH_ROLE_ADMIN) {
        return false;
    }

    String dn = deviceName;
    dn.trim();
    if (!_storage || (dn.length() == 0 && !hasAuthFields && apPass.length() == 0 && !apPassClear)) return true;

    JsonDocument cfg;
    _storage->loadJson(PATH_CONFIG, cfg);
    if (dn.length() > 0) {
        cfg["device_name"] = dn;
        _deviceName = dn;
    }
    if (updateWebAuthFlag && (!webAuth || webPass.length() > 0 || authAlreadyConfigured)) {
        cfg["web_auth"] = webAuth;
        _webAuthEnabled = webAuth;
    }
    if (webUser.length() > 0) {
        String u = webUser;
        u.trim();
        if (u.length() == 0) u = "admin";
        cfg["web_user"] = u;
        _webUsername = u;
    }
    if (webPass.length() > 0) {
        _webPasswordHash = hashPasswordSalted(webPass);
        cfg["web_pass_hash"] = _webPasswordHash;
        cfg["ota_pass_md5"] = md5Hex(webPass);
        cfg.remove("web_pass");
        _webPassword = webPass;
        if (_ota && _ota->isArduinoOtaEnabled()) {
            _ota->setArduinoOtaEnabled(true, _wifi ? _wifi->getHostname() : "", webPass, false);
        }
    }
    if (apPassClear) {
        cfg.remove("ap_pass");
    } else if (apPass.length() >= 8 && apPass.length() <= 63) {
        cfg["ap_pass"] = apPass;
    }
    if (hasAuthFields) regenerateWsToken();
    _storage->saveJson(PATH_CONFIG, cfg);
    return true;
}

void WebServerManager::regenerateWsToken() {
#if defined(ESP8266)
    uint32_t rnd = ESP.random();
    uint32_t rnd2 = ESP.random();
#else
    uint32_t rnd = esp_random();
    uint32_t rnd2 = esp_random();
#endif
    String seed = String(rnd) + ":" + String(micros()) + ":" + _webUsername + ":" + _webPasswordHash;
    String guestSeed = String(rnd2) + ":" + String(micros()) + ":" + _guestUsername + ":" + _guestPasswordHash + ":guest";
    _wsToken = sha256Hex(seed);
    _wsGuestToken = sha256Hex(guestSeed);
}

bool WebServerManager::isAuthConfigured() const {
    return _webAuthEnabled && _webUsername.length() > 0 &&
           (_webPassword.length() > 0 || _webPasswordHash.length() > 0);
}

bool WebServerManager::isAuthEnabled() const {
    bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
    if (isAP) return false;
    return isAuthConfigured();
}

bool WebServerManager::verifyCredentials(const String& user, const String& pass) const {
    if (!isAuthConfigured()) return true;
    if (user.length() == 0) return false;

    // 1. Check Admin Tier
    if (constantTimeCompare(user, _webUsername)) {
        bool passMatch = false;
        if (_webPasswordHash.length() > 0) {
            passMatch = verifyPasswordHash(pass, _webPasswordHash);
        } else if (_webPassword.length() > 0) {
            passMatch = constantTimeCompare(pass, _webPassword);
        }
        if (passMatch) return true;
    }

    // 2. Check Family / Guest Tier
    if (_guestAuthEnabled && constantTimeCompare(user, _guestUsername)) {
        bool passMatch = false;
        if (_guestPasswordHash.length() > 0) {
            passMatch = verifyPasswordHash(pass, _guestPasswordHash);
        } else if (_guestPassword.length() > 0) {
            passMatch = constantTimeCompare(pass, _guestPassword);
        } else {
            // Guest password not set: username match is sufficient
            passMatch = true;
        }
        if (passMatch) return true;
    }

    return false;
}

bool WebServerManager::verifyWsToken(const String& token) const {
    if (!isAuthConfigured()) return true;
    if (token.length() < 32) return false;
    if (_wsToken.length() >= 32 && constantTimeCompare(token, _wsToken)) return true;
    if (_guestAuthEnabled && _wsGuestToken.length() >= 32 && constantTimeCompare(token, _wsGuestToken)) return true;
    return false;
}

String WebServerManager::escapeHtml(const String& input) {
    String out;
    out.reserve(input.length() + 8);
    for (size_t i = 0; i < input.length(); i++) {
        char c = input[i];
        switch (c) {
            case '&':  out += F("&amp;"); break;
            case '<':  out += F("&lt;"); break;
            case '>':  out += F("&gt;"); break;
            case '"':  out += F("&quot;"); break;
            case '\'': out += F("&#39;"); break;
            default:   out += c; break;
        }
    }
    return out;
}

static String decodeBase64(const String& input) {
    const char* b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    String out = "";
    int val = 0, valb = -8;
    for (size_t i = 0; i < input.length(); i++) {
        char c = input[i];
        if (c == '=') break;
        const char* p = strchr(b64chars, c);
        if (p) {
            val = (val << 6) + (p - b64chars);
            valb += 6;
            if (valb >= 0) {
                out += (char)((val >> valb) & 0xFF);
                valb -= 8;
            }
        }
    }
    return out;
}

AuthRole WebServerManager::authenticateBasicCredentials(AsyncWebServerRequest* req) const {
    String authHeader = req->header("Authorization");
    authHeader.trim();
    if (authHeader.length() > 6 && authHeader.substring(0, 6).equalsIgnoreCase("Basic ")) {
        String encoded = authHeader.substring(6);
        encoded.trim();
        // Decode Base64 credentials
        String credentials = decodeBase64(encoded);
        if (credentials.length() > 0) {
            int colonIdx = credentials.indexOf(':');
            String user, pass;
            if (colonIdx >= 0) {
                user = credentials.substring(0, colonIdx);
                pass = credentials.substring(colonIdx + 1);
            } else {
                user = credentials;
                pass = "";
            }

            // Check Admin credentials
            if (constantTimeCompare(user, _webUsername)) {
                bool passMatch = false;
                if (_webPasswordHash.length() > 0) {
                    passMatch = verifyPasswordHash(pass, _webPasswordHash);
                } else if (_webPassword.length() > 0) {
                    passMatch = constantTimeCompare(pass, _webPassword);
                }
                if (passMatch) return AUTH_ROLE_ADMIN;
            }

            // Check Guest / Family credentials
            if (_guestAuthEnabled && constantTimeCompare(user, _guestUsername)) {
                bool passMatch = false;
                if (_guestPasswordHash.length() > 0) {
                    passMatch = verifyPasswordHash(pass, _guestPasswordHash);
                } else if (_guestPassword.length() > 0) {
                    passMatch = constantTimeCompare(pass, _guestPassword);
                } else {
                    passMatch = true;
                }
                if (passMatch) return AUTH_ROLE_GUEST;
            }
        }
    }
    return AUTH_ROLE_NONE;
}

AuthRole WebServerManager::authenticateRequest(AsyncWebServerRequest* req) {
    bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
    String url = req->url();
    bool authConfigured = isAuthConfigured();
    bool isSetupRoute = (url == "/" || url == "/api/discovery" || url == "/api/status" ||
                         url == "/api/wifi/scan" ||
                         (!authConfigured && url == "/api/config/wifi") ||
                         url == "/generate_204" || url == "/connecttest.txt" || url == "/fwlink" ||
                         url == "/logout" || url == "/api/logout");

    // Zero-Trust in AP Mode: ONLY allow unauthenticated captive onboarding routes;
    // once Admin password protection is configured, require Admin Basic Auth for /api/config/wifi too.
    if (isAP && isSetupRoute) {
        return AUTH_ROLE_ADMIN;
    }

    // If authentication is disabled in regular mode
    if (!authConfigured) {
        if (!isAP) return AUTH_ROLE_ADMIN;
    }

    return authenticateBasicCredentials(req);
}

bool WebServerManager::isAuthorized(AsyncWebServerRequest* req, AuthRole requiredRole) {
    bool isAP = (_wifi && _wifi->getState() == WIFI_ST_AP_MODE);
    String url = req->url();
    bool authConfigured = isAuthConfigured();
    bool isSetupRoute = (url == "/" || url == "/api/discovery" || url == "/api/status" ||
                         url == "/api/wifi/scan" ||
                         (!authConfigured && url == "/api/config/wifi") ||
                         url == "/generate_204" || url == "/connecttest.txt" || url == "/fwlink" ||
                         url == "/logout" || url == "/api/logout");

    if (isAP && isSetupRoute) {
        return true;
    }

    if (!authConfigured) {
        if (!isAP) return true;
    }

    // CSRF Protection: Require X-Requested-With header on mutating requests
    String method = req->methodToString();
    if (method == "POST" || method == "PUT" || method == "DELETE") {
        String xrw = req->header("X-Requested-With");
        if (xrw != "SmartHome" && xrw != "SmartHomeCompanionApp") {
            sendError(req, 403, F("CSRF validation failed: missing X-Requested-With header"));
            return false;
        }
    }

    IPAddress clientIp = req->client() ? req->client()->remoteIP() : IPAddress(0, 0, 0, 0);
    if (isRateLimited(clientIp)) {
        sendError(req, 429, F("Too many failed attempts. Locked out for 5 minutes."));
        return false;
    }

    AuthRole role = authenticateRequest(req);
    if (role == AUTH_ROLE_NONE) {
        recordFailedAttempt(clientIp);
        AsyncWebServerResponse* r = req->beginResponse(
            401, "application/json",
            "{\"status\":\"error\",\"message\":\"Authentication required\"}"
        );
        r->addHeader("WWW-Authenticate", "Basic realm=\"SmartHome\"");
        r->addHeader("Connection", "close");
        req->send(r);
        return false;
    }

    resetRateLimit(clientIp);

    // Multi-User Privilege Tier Enforcement
    if (role >= requiredRole) {
        return true;
    }

    // Authenticated as Guest/Family, but attempting an Admin-only operation
    if (_logger) {
        _logger->logWarning("Security", "Forbidden: Guest user denied admin access to " + url);
    }
    sendError(req, 403, F("Forbidden: Admin privileges required"));
    return false;
}

AuthRole WebServerManager::getRequestRole(AsyncWebServerRequest* req) {
    return authenticateRequest(req);
}
