# Changelog

All notable changes to the SmartHome (ESP32 + ESP8266 Unified Firmware & Flutter Companion App) project are documented in this file.

## [1.1.0] - 2026-11-19 — Unified Multi-Sensor, Concurrency & Security Hardening Edition

### Added
- **Unified ESP32 + ESP8266 Architecture**: Single firmware codebase supporting up to 8 relays and multi-instance sensors (`Climate x4`, `Light x2`, `Motion x6`, `Water Probe x4`, `Ultrasonic Tank x4`, `Gas/SGP40 VOC x4`).
- **Safe-by-Default Firmware OTA**: Single-controller OTA default in the companion app with ESP32/ESP8266 chip-magic verification and gated same-chip batch mode.
- **Sensor Pin Guide & Smart Auto-Pick**: Hardware Configurator guides users away from boot-strapping/wake pins (`D4/GPIO 2`, `D8/GPIO 15`, `D0/GPIO 16`) with live per-slot warnings.
- **Personal Non-Commercial Source-Available License**: Added root `LICENSE` file for personal home use without modification or commercial redistribution.

### Fixed & Hardened
- **ESP32 Dual-Core Thread Safety**: Added FreeRTOS synchronization across `Diagnostics`, `LCDManager` (deferred Core 1 I2C writes), `TimeManager`, `BuzzerManager`, `SensorManager`, `HardwareManager`, `MqttManager`, `WifiManager`, `WebSocketManager`, and `StorageManager`.
- **Safety & Failsafe Integrity**: Latched failsafe relays OFF during active Gas/Temp alarms, added `1.5°C` temperature alarm hysteresis, prevented low-threshold MQ-2 permanent latching, required 3 consecutive failures before DS18B20 probe fault, and prevented boot-time false firing of `BELOW` automation rules before first sensor sample.
- **Security Hardening**: Enforced `X-Requested-With` CSRF validation on mutating API routes even when `web_auth` is disabled, added rate limiting and role-scoped WS token rotation on `/api/logout`, stored `ota_pass_md5` only when `arduino_ota` is enabled, sanitized outbound webhook headers against CRLF injection, hardened SSRF validation and TLS handshake timeout in `RemoteAlertManager`, and fixed Android `MainActivity` lockscreen flag persistence and `SafetyMonitorService` lockout loops.

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
