/*
 * ============================================================================
 * WebSocketManager.h — AsyncWebSocket Real-time Updates
 * ============================================================================
 */

#ifndef WEBSOCKET_MANAGER_H
#define WEBSOCKET_MANAGER_H

#include <Arduino.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include "Config.h"

class WebSocketManager {
public:
    WebSocketManager();

    void begin(AsyncWebServer& server);
    void loop();
    void setEnabled(bool enabled);
    bool isEnabled() const;
    void disconnectAll();

    // Broadcast JSON to all connected clients
    void broadcastUpdate(const String& json);
    void broadcastRelayChange(uint8_t index, bool state);
    void broadcastRelayTimer(uint8_t index, bool active, bool targetState, uint32_t remainingSec);
    void broadcastAlarm(const String& type, bool active);
    void broadcastToast(const String& message, const String& level);

    uint8_t getClientCount();

    // Authentication
    typedef bool (*WsAuthValidatorCallback)(const IPAddress& clientIp, const String& user, const String& pass, const String& token);
    void setAuthentication(const String& user, const String& pass);
    void setAuthValidator(WsAuthValidatorCallback cb);

    // Set the live-status provider. Status is sent only to clients which
    // explicitly subscribe; it is never broadcast continuously by default.
    void setDataProvider(String (*cb)());

private:
    struct StatusSubscription {
        uint32_t clientId;
        unsigned long intervalMs;
        unsigned long lastSent;
        bool active;
        bool authenticated;
    };

    AsyncWebSocket _ws;
    String (*_dataProvider)();
    WsAuthValidatorCallback _authValidator;
    bool _enabled;
    StatusSubscription _subscriptions[MAX_WS_CLIENTS];

    void onEvent(AsyncWebSocket* server, AsyncWebSocketClient* client,
                 AwsEventType type, void* arg, uint8_t* data, size_t len);

    static WebSocketManager* _instance;
    static void _onEvent(AsyncWebSocket* server, AsyncWebSocketClient* client,
                         AwsEventType type, void* arg, uint8_t* data, size_t len);

    void handleMessage(AsyncWebSocketClient* client, uint8_t* data, size_t len);
    void sendToAuthenticated(const String& json);
    void cleanupClients();
    StatusSubscription* subscriptionFor(uint32_t clientId, bool create = false);
    void removeSubscription(uint32_t clientId);
};

#endif // WEBSOCKET_MANAGER_H
