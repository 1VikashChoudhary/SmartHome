/*
 * ============================================================================
 * RemoteAlertManager.cpp — Optional Away-from-Home Push Alert Dispatcher
 * ============================================================================
 */

#include "RemoteAlertManager.h"
#include <ArduinoJson.h>

#if defined(ESP32)
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#else
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#endif

#if defined(ESP32)
namespace {
class AlertMutexGuard {
public:
    explicit AlertMutexGuard(SemaphoreHandle_t mtx) : _mtx(mtx) {
        if (_mtx) xSemaphoreTakeRecursive(_mtx, portMAX_DELAY);
    }
    ~AlertMutexGuard() {
        if (_mtx) xSemaphoreGiveRecursive(_mtx);
    }
private:
    SemaphoreHandle_t _mtx;
};
} // namespace

void RemoteAlertManager::ensureMutex() const {
    if (!_alertMutex) {
        _alertMutex = xSemaphoreCreateRecursiveMutex();
    }
}
#define ALERT_LOCK() ensureMutex(); AlertMutexGuard _alertLockGuard(_alertMutex)
#else
#define ALERT_LOCK() ((void)0)
#endif

namespace {

constexpr unsigned long kAlertCooldownMs = 60000UL;

struct AlertDispatchJob {
    String url;
    String token;
    String title;
    String body;
    String contentType;
    bool isHttps;
    RemoteAlertManager* owner;
};

bool isNtfyEndpoint(const String& url) {
    String lower = url;
    lower.toLowerCase();
    return lower.indexOf("ntfy.") >= 0 || lower.indexOf("/ntfy") >= 0;
}

int performHttpPost(const String& url, const String& token,
                    const String& title, const String& body,
                    const String& contentType, bool isHttps) {
#if defined(ESP32)
    HTTPClient http;
    int code = -1;
    if (isHttps) {
        WiFiClientSecure client;
        client.setInsecure(); // Allow user-supplied HTTPS webhook / self-hosted ntfy certs
        client.setTimeout(5000);
        if (http.begin(client, url)) {
            http.setTimeout(5000);
            http.addHeader("Content-Type", contentType);
            http.addHeader("Title", title);
            http.addHeader("Priority", "urgent");
            http.addHeader("Tags", "rotating_light,warning");
            if (token.length() > 0) {
                http.addHeader("Authorization", "Bearer " + token);
            }
            code = http.POST((uint8_t*)body.c_str(), body.length());
            http.end();
        }
    } else {
        WiFiClient client;
        client.setTimeout(4000);
        if (http.begin(client, url)) {
            http.setTimeout(4000);
            http.addHeader("Content-Type", contentType);
            http.addHeader("Title", title);
            http.addHeader("Priority", "urgent");
            http.addHeader("Tags", "rotating_light,warning");
            if (token.length() > 0) {
                http.addHeader("Authorization", "Bearer " + token);
            }
            code = http.POST((uint8_t*)body.c_str(), body.length());
            http.end();
        }
    }
    return code;
#else
    (void)isHttps;
    WiFiClient client;
    client.setTimeout(1500);
    HTTPClient http;
    http.setTimeout(2500);
    int code = -1;
    if (http.begin(client, url)) {
        http.addHeader("Content-Type", contentType);
        http.addHeader("Title", title);
        http.addHeader("Priority", "urgent");
        http.addHeader("Tags", "rotating_light,warning");
        if (token.length() > 0) {
            http.addHeader("Authorization", "Bearer " + token);
        }
        code = http.POST(body);
        http.end();
    }
    return code;
#endif
}

#if defined(ESP32)
void alertDispatchTask(void* param) {
    AlertDispatchJob* job = static_cast<AlertDispatchJob*>(param);
    if (job) {
        int code = performHttpPost(job->url, job->token, job->title,
                                   job->body, job->contentType, job->isHttps);
        SERIAL_PRINTF("[RemoteAlert] Webhook POST -> HTTP %d\n", code);
        if (job->owner) {
            job->owner->finishDispatch();
        }
        delete job;
    }
    vTaskDelete(nullptr);
}
#endif

} // namespace

RemoteAlertManager::RemoteAlertManager()
    : _storage(nullptr),
      _logger(nullptr),
      _enabled(false),
      _url(""),
      _token(""),
      _inFlight(false),
      _lastGasSentMs(0),
      _lastTempSentMs(0),
      _lastFaultSentMs(0),
      _pendingEsp8266Job(nullptr)
#if defined(ESP32)
      , _alertMutex(nullptr)
#endif
{}

void RemoteAlertManager::begin(StorageManager& storage, EventLogger& logger) {
#if defined(ESP32)
    ensureMutex();
#endif
    _storage = &storage;
    _logger = &logger;
    loadConfig();
}

void RemoteAlertManager::finishDispatch() {
    ALERT_LOCK();
    _inFlight = false;
}

bool RemoteAlertManager::isEnabled() const {
    ALERT_LOCK();
    return _enabled;
}

String RemoteAlertManager::getUrl() const {
    ALERT_LOCK();
    return _url;
}

bool RemoteAlertManager::hasToken() const {
    ALERT_LOCK();
    return _token.length() > 0;
}

void RemoteAlertManager::loop() {
#if !defined(ESP32)
    if (!_pendingEsp8266Job) return;
    AlertDispatchJob* job = static_cast<AlertDispatchJob*>(_pendingEsp8266Job);
    _pendingEsp8266Job = nullptr;
    if (job) {
        if (WiFi.status() == WL_CONNECTED) {
            int code = performHttpPost(job->url, job->token, job->title,
                                       job->body, job->contentType, job->isHttps);
            if (code >= 200 && code < 300) {
                if (_logger) _logger->logInfo("Alert", "Remote push sent (HTTP " + String(code) + ")");
            } else {
                String warn = "Webhook returned HTTP " + String(code);
                if (_logger) _logger->logWarning("Alert", warn);
            }
        }
        delete job;
    }
    _inFlight = false;
#endif
}

bool RemoteAlertManager::isHttpsSupported() {
#if defined(ESP32)
    return true;
#else
    return false;
#endif
}

bool RemoteAlertManager::validateUrl(const String& url, bool enabled, String& outError) {
    if (url.length() == 0) {
        if (enabled) {
            outError = F("Enter a webhook or ntfy URL before enabling remote alerts");
            return false;
        }
        return true;
    }
    if (url.length() > 192) {
        outError = F("Webhook URL cannot exceed 192 characters");
        return false;
    }
    for (size_t i = 0; i < url.length(); i++) {
        char c = url[i];
        if ((unsigned char)c <= 0x20 || c == '"' || c == '\\') {
            outError = F("Webhook URL contains invalid whitespace or characters");
            return false;
        }
    }
    String lower = url;
    lower.toLowerCase();
    bool isHttp = lower.startsWith("http://");
    bool isHttps = lower.startsWith("https://");
    if (!isHttp && !isHttps) {
        outError = F("Webhook URL must start with http:// or https://");
        return false;
    }
    if (isHttps && !isHttpsSupported()) {
        outError = F("HTTPS webhooks require ESP32; use local http:// URL or MQTT on ESP8266");
        return false;
    }
    return true;
}

void RemoteAlertManager::loadConfig() {
    if (!_storage) return;
    JsonDocument cfg;
    if (_storage->loadJson(PATH_CONFIG, cfg)) {
        ALERT_LOCK();
        _enabled = cfg["alert_webhook_en"] | false;
        _url = cfg["alert_webhook_url"] | "";
        _url.trim();
        _token = cfg["alert_webhook_token"] | "";
        String err;
        if (!validateUrl(_url, _enabled, err)) {
            _enabled = false;
        }
    }
}

void RemoteAlertManager::applyConfig(bool enabled, const String& url,
                                     bool hasToken, const String& token, bool clearToken) {
    ALERT_LOCK();
    _enabled = enabled;
    _url = url;
    _url.trim();
    if (clearToken) {
        _token = "";
    } else if (hasToken && token.length() > 0) {
        _token = token;
    }
}

void RemoteAlertManager::toConfigJson(JsonObject& obj) const {
    ALERT_LOCK();
    obj["alert_webhook_en"] = _enabled;
    obj["alert_webhook_url"] = _url;
    obj["alert_webhook_token_set"] = (_token.length() > 0);
    obj["alert_https_supported"] = isHttpsSupported();
}

void RemoteAlertManager::notifyAlarm(const String& deviceName, const String& mac,
                                     const char* alarmType, const String& detailMsg) {
    String title;
    {
        ALERT_LOCK();
        if (!_enabled || _url.length() < 8) return;
        unsigned long now = millis();
        unsigned long* lastPtr = nullptr;
        if (strcmp(alarmType, "gas") == 0) lastPtr = &_lastGasSentMs;
        else if (strcmp(alarmType, "temperature") == 0) lastPtr = &_lastTempSentMs;
        else lastPtr = &_lastFaultSentMs;

        if (*lastPtr != 0 && (unsigned long)(now - *lastPtr) < kAlertCooldownMs) {
            return;
        }

        title = "[" + deviceName + "] ";
        if (strcmp(alarmType, "gas") == 0) title += "GAS / SMOKE ALARM";
        else if (strcmp(alarmType, "temperature") == 0) title += "HIGH TEMPERATURE ALARM";
        else title += "SENSOR FAULT ALERT";

        String err;
        if (dispatch(deviceName, mac, alarmType, title, detailMsg, false, err)) {
            *lastPtr = now;
        }
    }
}

bool RemoteAlertManager::sendTestAlert(const String& deviceName, const String& mac, String& outError) {
    ALERT_LOCK();
    if (_url.length() < 8) {
        outError = F("Configure and save a webhook / ntfy URL first");
        return false;
    }
    String title = "[" + deviceName + "] Test Remote Alert";
    String msg = "Test push alert from SmartHome controller (" + mac + "). Emergency delivery verified.";
    return dispatch(deviceName, mac, "test", title, msg, true, outError);
}

bool RemoteAlertManager::dispatch(const String& deviceName, const String& mac,
                                  const String& alarmType, const String& title,
                                  const String& message, bool isTest, String& outError) {
    if (WiFi.status() != WL_CONNECTED) {
        outError = F("Controller Wi-Fi is not connected");
        return false;
    }

    String urlSnap;
    String tokenSnap;
    {
        ALERT_LOCK();
        urlSnap = _url;
        tokenSnap = _token;
        String valErr;
        if (!validateUrl(urlSnap, true, valErr)) {
            outError = valErr;
            return false;
        }

        String lower = urlSnap;
        lower.toLowerCase();
        bool isHttps = lower.startsWith("https://");

        String contentType = "application/json";
        String body;
        if (isNtfyEndpoint(urlSnap)) {
            contentType = "text/plain";
            body = message;
        } else {
            JsonDocument doc;
            doc["event"] = isTest ? "test" : "alarm";
            doc["alarm"] = alarmType;
            doc["active"] = true;
            doc["device"] = deviceName;
            doc["mac"] = mac;
            doc["title"] = title;
            doc["message"] = message;
            serializeJson(doc, body);
        }

#if defined(ESP32)
        if (_inFlight) {
            outError = F("Another alert webhook request is already in progress");
            return false;
        }
        _inFlight = true;
        AlertDispatchJob* job = new AlertDispatchJob{
            urlSnap, tokenSnap, title, body, contentType, isHttps, this
        };
        if (!job || xTaskCreate(alertDispatchTask, "alert_post", 12288, job, 1, nullptr) != pdPASS) {
            _inFlight = false;
            delete job;
            outError = F("Failed to schedule background alert task");
            return false;
        }
#else
        if (_inFlight || _pendingEsp8266Job != nullptr) {
            outError = F("Another alert webhook request is already in progress");
            return false;
        }
        AlertDispatchJob* job = new AlertDispatchJob{
            urlSnap, tokenSnap, title, body, contentType, false, this
        };
        if (!job) {
            outError = F("Out of memory queuing remote alert");
            return false;
        }
        _inFlight = true;
        _pendingEsp8266Job = job;
#endif
    }

    if (_logger) _logger->logInfo("Alert", "Queued remote push: " + title);
    return true;
}
