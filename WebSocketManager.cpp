/*
 * ============================================================================
 * WebSocketManager.cpp — AsyncWebSocket Implementation
 * ============================================================================
 */

#include "WebSocketManager.h"

namespace {
bool isClientWritable(AsyncWebSocketClient* client) {
    return client &&
           client->canSend() &&
           !client->queueIsFull() &&
           client->client() &&
           client->client()->canSend() &&
           client->client()->space() > 512;
}
} // namespace

WebSocketManager* WebSocketManager::_instance = nullptr;

WebSocketManager::WebSocketManager()
    : _ws("/ws"), _dataProvider(nullptr), _authValidator(nullptr), _enabled(true) {
    _instance = this;
    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        _subscriptions[i] = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
    }
}

void WebSocketManager::begin(AsyncWebServer& server) {
    _ws.onEvent(_onEvent);
    server.addHandler(&_ws);
    Serial.println(F("[WS] WebSocket handler registered at /ws"));
}

void WebSocketManager::loop() {
    if (!_enabled) return;
    unsigned long now = millis();

    // Cleanup disconnected clients periodically (every 5 seconds)
    static unsigned long lastCleanup = 0;
    if (now - lastCleanup >= 5000) {
        lastCleanup = now;
        cleanupClients();
    }

    if (_ws.count() == 0 || !_dataProvider) return;

    bool hasDueSubscriber = false;
    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        StatusSubscription& sub = _subscriptions[i];
        if (sub.clientId == 0) continue;
        AsyncWebSocketClient* client = _ws.client(sub.clientId);
        if (!client || client->status() != WS_CONNECTED) {
            sub = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
            continue;
        }
        if (!sub.active || !sub.authenticated) continue;
        if (!isClientWritable(client)) continue;
        if (now - sub.lastSent >= sub.intervalMs) {
            hasDueSubscriber = true;
            break;
        }
    }

    // Build one bounded status document only when at least one client is due.
    if (!hasDueSubscriber) return;
    String data = _dataProvider();
    if (data.length() == 0) return;

    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        StatusSubscription& sub = _subscriptions[i];
        if (!sub.active || !sub.authenticated || now - sub.lastSent < sub.intervalMs) continue;
        AsyncWebSocketClient* client = _ws.client(sub.clientId);
        if (!client || client->status() != WS_CONNECTED) {
            sub = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
            continue;
        }
        if (!isClientWritable(client)) continue;
        client->text(data);
        sub.lastSent = now;
    }
}

void WebSocketManager::sendToAuthenticated(const String& json) {
    if (!_enabled || _ws.count() == 0) return;
    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        StatusSubscription& sub = _subscriptions[i];
        if (sub.clientId == 0) continue;
        AsyncWebSocketClient* client = _ws.client(sub.clientId);
        if (!client || client->status() != WS_CONNECTED) {
            sub = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
            continue;
        }
        if (!sub.active || !sub.authenticated) continue;
        if (isClientWritable(client)) {
            client->text(json);
        }
    }
}

void WebSocketManager::broadcastUpdate(const String& json) {
    sendToAuthenticated(json);
}

void WebSocketManager::broadcastRelayChange(uint8_t index, bool state) {
    if (!_enabled) return;
    if (_ws.count() == 0) return;

    JsonDocument doc;
    doc["type"] = "relay";
    doc["id"] = index;
    doc["state"] = state;

    String json;
    serializeJson(doc, json);
    sendToAuthenticated(json);
}

void WebSocketManager::broadcastRelayTimer(uint8_t index, bool active, bool targetState, uint32_t remainingSec) {
    if (!_enabled) return;
    if (_ws.count() == 0) return;

    JsonDocument doc;
    doc["type"] = "relay_timer";
    doc["id"] = index;
    doc["timer_active"] = active;
    doc["timer_target"] = targetState;
    doc["timer_remaining"] = remainingSec;

    String json;
    serializeJson(doc, json);
    sendToAuthenticated(json);
}

void WebSocketManager::broadcastAlarm(const String& type, bool active) {
    if (!_enabled) return;
    if (_ws.count() == 0) return;

    JsonDocument doc;
    doc["type"] = "alarm";
    doc["alarm"] = type;
    doc["active"] = active;

    String json;
    serializeJson(doc, json);
    sendToAuthenticated(json);
}

void WebSocketManager::broadcastToast(const String& message, const String& level) {
    if (!_enabled) return;
    if (_ws.count() == 0) return;

    JsonDocument doc;
    doc["type"] = "toast";
    doc["msg"] = message;
    doc["level"] = level;

    String json;
    serializeJson(doc, json);
    sendToAuthenticated(json);
}

uint8_t WebSocketManager::getClientCount() {
    return _ws.count();
}

void WebSocketManager::setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
        disconnectAll();
    }
}

bool WebSocketManager::isEnabled() const {
    return _enabled;
}

void WebSocketManager::disconnectAll() {
    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        _subscriptions[i] = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
    }
    _ws.closeAll();
}

void WebSocketManager::setAuthentication(const String& user, const String& pass) {
    if (user.length() > 0 && pass.length() > 0) {
        _ws.setAuthentication(user.c_str(), pass.c_str());
        SERIAL_PRINTF("[WS] Authentication enabled for user '%s'\n", user.c_str());
    } else {
        _ws.setAuthentication("", "");
        Serial.println(F("[WS] Authentication disabled"));
    }
}

void WebSocketManager::setAuthValidator(WsAuthValidatorCallback cb) {
    _authValidator = cb;
}

void WebSocketManager::setDataProvider(String (*cb)()) {
    _dataProvider = cb;
}

// ============================================================================
// Event Handler
// ============================================================================
void WebSocketManager::_onEvent(AsyncWebSocket* server, AsyncWebSocketClient* client,
                                 AwsEventType type, void* arg, uint8_t* data, size_t len) {
    if (_instance) _instance->onEvent(server, client, type, arg, data, len);
}

void WebSocketManager::onEvent(AsyncWebSocket* server, AsyncWebSocketClient* client,
                                AwsEventType type, void* arg, uint8_t* data, size_t len) {
    switch (type) {
        case WS_EVT_CONNECT: {
            // Configure keepalive and TCP RX timeout so roamed zombie sockets
            // do not linger waiting for lwIP retransmission timeouts.
            client->keepAlivePeriod(10);
            if (client->client()) {
                client->client()->setRxTimeout(25);
                client->client()->setNoDelay(true);
            }
            IPAddress newIp = client->remoteIP();
            for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
                uint32_t oldId = _subscriptions[i].clientId;
                if (oldId == 0 || oldId == client->id()) continue;
                AsyncWebSocketClient* oldClient = _ws.client(oldId);
                if (!oldClient) {
                    _subscriptions[i] = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
                    continue;
                }
                if (oldClient->remoteIP() == newIp &&
                    (!oldClient->client() || !oldClient->client()->canSend() || oldClient->client()->space() < 512)) {
                    _subscriptions[i] = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
                    if (oldClient->client()) oldClient->client()->close(true);
                }
            }
            _ws.cleanupClients(MAX_WS_CLIENTS);
            SERIAL_PRINTF("[WS] Client #%lu connected from %s\n",
                          (unsigned long)client->id(), newIp.toString().c_str());
            subscriptionFor(client->id(), true);
            break;
        }

        case WS_EVT_DISCONNECT:
            SERIAL_PRINTF("[WS] Client #%lu disconnected\n", (unsigned long)client->id());
            removeSubscription(client->id());
            break;

        case WS_EVT_DATA: {
            AwsFrameInfo* info = reinterpret_cast<AwsFrameInfo*>(arg);
            // Reject fragmented/non-text frames. The protocol is intentionally
            // tiny so a malformed client cannot consume controller resources.
            if (info && info->final && info->index == 0 && info->len == len &&
                info->opcode == WS_TEXT) {
                handleMessage(client, data, len);
            }
            break;
        }

        case WS_EVT_PONG:
        case WS_EVT_ERROR:
            break;
    }
}

void WebSocketManager::handleMessage(AsyncWebSocketClient* client, uint8_t* data, size_t len) {
    if (!client || !data || len == 0 || len > 512) return;

    JsonDocument doc;
    if (deserializeJson(doc, data, len)) return;
    const char* type = doc["type"] | "";
    const char* stream = doc["stream"] | "";
    if (strcmp(stream, "status") != 0) return;

    StatusSubscription* sub = subscriptionFor(client->id(), true);
    if (!sub) return;

    if (strcmp(type, "unsubscribe") == 0) {
        sub->active = false;
        sub->authenticated = false;
        return;
    }
    if (strcmp(type, "subscribe") != 0) return;

    if (_authValidator) {
        String user = doc["user"] | "";
        String pass = doc["pass"] | "";
        String token = doc["token"] | "";
        IPAddress clientIp = client->remoteIP();
        if (!_authValidator(clientIp, user, pass, token)) {
            sub->active = false;
            sub->authenticated = false;
            client->text("{\"type\":\"auth_error\",\"auth_required\":true,\"message\":\"Authentication required\"}");
            client->close(4001, "Unauthorized");
            SERIAL_PRINTF("[WS] Client #%lu rejected: authentication required\n", (unsigned long)client->id());
            return;
        }
    }

    unsigned long requested = doc["interval_ms"] | WS_STATUS_MIN_INTERVAL;
    sub->intervalMs = constrain(requested, WS_STATUS_MIN_INTERVAL, WS_STATUS_MAX_INTERVAL);
    sub->lastSent = millis() - sub->intervalMs; // Send the first update promptly.
    sub->active = true;
    sub->authenticated = true;
    SERIAL_PRINTF("[WS] Client #%lu subscribed to status (%lums)\n", (unsigned long)client->id(), sub->intervalMs);
}

void WebSocketManager::cleanupClients() {
    _ws.cleanupClients(MAX_WS_CLIENTS);
}

WebSocketManager::StatusSubscription* WebSocketManager::subscriptionFor(uint32_t clientId, bool create) {
    StatusSubscription* empty = nullptr;
    StatusSubscription* oldest = nullptr;
    for (uint8_t i = 0; i < MAX_WS_CLIENTS; i++) {
        if (_subscriptions[i].clientId == clientId) return &_subscriptions[i];
        if (_subscriptions[i].clientId != 0) {
            AsyncWebSocketClient* c = _ws.client(_subscriptions[i].clientId);
            if (!c || c->status() != WS_CONNECTED) {
                _subscriptions[i] = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
            }
        }
        if (_subscriptions[i].clientId == 0 && !empty) {
            empty = &_subscriptions[i];
        }
        if (!oldest || _subscriptions[i].lastSent < oldest->lastSent) {
            oldest = &_subscriptions[i];
        }
    }
    if (!create) return nullptr;
    StatusSubscription* target = empty ? empty : oldest;
    if (!target) return nullptr;
    *target = {clientId, WS_STATUS_MIN_INTERVAL, 0, false, false};
    return target;
}

void WebSocketManager::removeSubscription(uint32_t clientId) {
    StatusSubscription* sub = subscriptionFor(clientId);
    if (sub) *sub = {0, WS_STATUS_MIN_INTERVAL, 0, false, false};
}
