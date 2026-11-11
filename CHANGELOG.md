# Changelog

All notable changes to the ESP32 SmartHome project are documented in this file.

## [1.0.5] - 2026-11-04 — Security Edition

### Security
- **Per-device MAC-based AP password**: Each device generates a unique WPA2 password `SmartHome@<Last4MAC>!` — no more universal default password
- **Constant-time password comparison**: XOR-accumulator verification wired into the HTTP auth flow to prevent timing attacks
- **ArduinoOTA dynamic password**: Removed static `smarthome_ota` — now syncs with the web admin password
- **CSRF server-side enforcement**: Server validates `X-Requested-With` header on all POST/PUT/DELETE requests (HTTP 403 on failure)
- **Encrypted credential storage**: Flutter app stores device passwords in Android EncryptedSharedPreferences / iOS Keychain
- **SHA-256 password hashing**: Web admin password stored as a hash in `config.json` — not plaintext
- **Enhanced firmware validation**: OTA uploads verified against ESP32 image header structure beyond magic byte
- **IP rate limiter**: 5 failed login attempts → 5-minute lockout per IP (HTTP 429)
- **AP zero-trust isolation**: Only onboarding endpoints allowed in AP mode; OTA/backup/reset require auth
- **WebSocket authentication**: WS handshake requires valid credentials when web auth is enabled
- **Backup secret redaction**: WiFi/MQTT/admin passwords exported as `__REDACTED__`; preserved on import
- **XSS sanitization**: `escapeHtml()` applied to all dynamic content in the web dashboard
- **CSRF client headers**: Web dashboard and Flutter app send `X-Requested-With` on all requests

### Added
- LCD displays AP hotspot SSID and WPA2 password during setup mode
- ArduinoOTA runtime enable/disable toggle via web dashboard and Flutter app
- Config backup restore from JSON file (web dashboard and Flutter app)
- Flutter companion app: device tools panel with maintenance controls

### Fixed
- Fixed `_logger->logWarn()` → `logWarning()` compilation error
- Fixed `activeColor` deprecation → `activeThumbColor` in Flutter 3.31+
- Fixed unauthenticated OTA upload and backup download endpoints in Flutter app
- Fixed BootStateMode enum alignment (0: Restore Last, 1: Always ON, 2: Always OFF)

## [1.0.4] - 2026-10-xx

### Added
- Sensor automation rule engine with anti-flapping hysteresis
- One-shot relay countdown timers (5m, 10m, 30m, 1h, 2h, custom)
- Batch OTA firmware update screen in Flutter app
- iOS-style luxury segmented selectors in relay config and automations

### Fixed
- Live hardware configuration display sync with ESP32 flash
- System navigation bar overlap in Flutter app

## [1.0.3] - 2026-10-xx

### Added
- Flutter companion app with mDNS discovery
- Real-time WebSocket communication
- Dark/light theme with glassmorphism design

## [1.0.0] - 2026-09-xx

### Added
- Initial release
- 5-relay smart home control with wall switch interrupt support
- DHT22 temperature/humidity + MQ2 gas sensing
- Embedded web dashboard SPA
- Home Assistant MQTT auto-discovery
- LCD1602 I2C display with page rotation
- Multi-function button (page cycle, backlight, WiFi reset, factory reset)
- LittleFS persistent storage with wear leveling
- Alarm scheduler with cron-like events
- NTP time sync with optional DS3231 RTC fallback
- Captive portal WiFi setup
