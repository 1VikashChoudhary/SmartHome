# SmartHome Pro — Standalone ESP32 & ESP8266 Smart Home & Environmental Monitoring System

<p align="center">
  <img src="https://img.shields.io/badge/Standalone-No%20Home%20Assistant%20Required-00C853?style=for-the-badge&logo=homeassistant&logoColor=white" alt="Works Without Home Assistant" />
  <img src="https://img.shields.io/badge/Firmware-v1.1.0-blue?style=for-the-badge&logo=espressif&logoColor=white" alt="Firmware Version" />
  <img src="https://img.shields.io/badge/Architecture-ESP32%20%2B%20ESP8266%20Unified-orange?style=for-the-badge&logo=espressif&logoColor=white" alt="Dual Architecture" />
  <img src="https://img.shields.io/badge/Flutter-v3.29+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter App" />
  <img src="https://img.shields.io/badge/Security-RBAC%20%2B%20SHA--256-red?style=for-the-badge&logo=shield" alt="RBAC and SHA-256 Security" />
  <img src="https://img.shields.io/badge/Storage-Wear--Leveled%20NVS%20%2F%20EEPROM-green?style=for-the-badge&logo=databricks" alt="Wear-Leveled Storage" />
  <img src="https://img.shields.io/badge/OTA-Web%20OTA-purple?style=for-the-badge&logo=git" alt="Web OTA Support" />
  <img src="https://img.shields.io/badge/Tests-124%20Passed-success?style=for-the-badge&logo=checkmarx" alt="Automated Tests" />
</p>

> **100% Local & Standalone — Works Without Home Assistant, Cloud Servers, Raspberry Pi, or Subscriptions.**
> *(Optional Home Assistant MQTT Auto-Discovery is built in if you ever want to integrate later.)*

A standalone IoT smart home automation hub powered by a **single unified codebase** that runs seamlessly on both **ESP8266** (NodeMCU, Wemos D1 Mini) and **ESP32** (Dual-Core, DevKit, WROOM), accompanied by a cross-platform Flutter companion application (**Android, iOS, Windows, macOS**) and an embedded Obsidian Glassmorphism web dashboard served directly by each controller.

<p align="center">
  <a href="#pre-compiled-binaries--release-apks"><b>📥 Download Binaries &amp; APKs</b></a> &nbsp;•&nbsp;
  <a href="#-application-previews"><b>📸 Screenshots</b></a> &nbsp;•&nbsp;
  <a href="#key-features--pillars"><b>⚡ Key Features</b></a> &nbsp;•&nbsp;
  <a href="#first-time-setup-guide"><b>🚀 First-Time Setup</b></a> &nbsp;•&nbsp;
  <a href="#sponsor--support-the-project"><b>❤️ Sponsor</b></a>
</p>

### ✨ Why SmartHome Pro? (Highlights at a Glance)

| Pillar | What You Get Out of the Box |
| :--- | :--- |
| **🏠 Zero Hub / Zero Cloud** | Runs 100% locally on your Wi-Fi LAN — **no Home Assistant, no Raspberry Pi, no internet dependency, and no subscriptions**. |
| **🧩 Single Unified Firmware** | One codebase automatically adapts to both **ESP32** and **ESP8266** boards with ready-to-flash `.bin` releases. |
| **🛠️ Zero-Code Hardware Setup** | Remap **0–8 relays**, physical wall switches, I2C LCDs, buzzers, and multi-slot sensors (Climate, Light, Motion, Water Temp, Tank Level, Gas) live from the App or Web UI — **no reflashing required**. |
| **🚨 Autonomous Safety & Failsafe** | Hardware-level **Gas (MQ-2) & Over-Temperature** alarms (`GAS > TEMP > FAULT` priority) automatically lock failsafe relays OFF, sound the buzzer, display LCD warnings, send remote `ntfy`/webhook alerts, and trigger Android background emergency alarms. |
| **🤖 On-Device Automation** | Sensor-driven rules (e.g., auto-pump on tank level, auto-fan on temperature), daily/weekly calendar schedules, countdown timers, and physical wall-switch control that keep working **even if Wi-Fi goes down**. |
| **📱 Native Mobile & Desktop UX** | Cross-platform Flutter app (**Android, iOS, Windows, macOS**) with **Android Quick Settings Tiles**, **Native Android Device Controls**, Radar LAN Discovery, live WebSocket telemetry, and an embedded Web Dashboard. |
| **🛡️ Hardened Security & Web OTA** | Admin vs. Family/Guest RBAC, salted SHA-256 hashing, CSRF & brute-force rate limiting, encrypted mobile credential storage, and chip-verified Web OTA updates. |

> [!WARNING]
> **Important Safety & Legal Notice (Use at Your Own Risk):** This project is provided **"AS IS"** with **no warranties or guarantees** of any kind. Working with mains voltage (110V–240V AC), relays, and gas/temperature sensors carries serious risks of electric shock, fire, property damage, injury, or death. Sensor alerts and failsafe features are **not certified life-safety systems** and must never replace certified gas, smoke, or fire detectors. You assume **100% of the risk and responsibility** for wiring, flashing, hardware, and operation. See the full [Safety & Legal Disclaimer](#important-safety--legal-disclaimer) and [LICENSE](LICENSE).

---

## 📸 Application Previews

### 📱 Mobile Companion App (Android & iOS)

<p align="center">
  <img width="205" alt="Dashboard Overview" src="https://github.com/user-attachments/assets/4896cb89-680c-4455-80c4-27867d154c3d" />
  <img width="205" alt="Controllers Hub" src="https://github.com/user-attachments/assets/33891ebe-d684-4fe6-b303-6ebc8204471f" />
  <img width="205" alt="Device Control Panel" src="https://github.com/user-attachments/assets/ba1a7c33-74d9-45fb-80b9-5ed14e454b63" />
  <img width="205" alt="Sensor Telemetry" src="https://github.com/user-attachments/assets/04f339c2-68f1-487f-addf-e6205da2029a" />
</p>

<details>
<summary><b>Click to expand all 18 Mobile App screenshots</b></summary>
<br />
<p align="center">
  <img width="205" alt="Mobile Preview 5" src="https://github.com/user-attachments/assets/6f5b9b81-36fd-48ec-ba30-b2229d049ee3" />
  <img width="205" alt="Mobile Preview 6" src="https://github.com/user-attachments/assets/e26089af-42b2-4780-9d59-94e23f4713e7" />
  <img width="205" alt="Mobile Preview 7" src="https://github.com/user-attachments/assets/ff969e8f-42da-4d89-bcc6-d85d2e5ab343" />
  <img width="205" alt="Mobile Preview 8" src="https://github.com/user-attachments/assets/6db42a00-6a7c-4067-a9bc-e3311b0969ae" />
  <img width="205" alt="Mobile Preview 9" src="https://github.com/user-attachments/assets/6c7331db-26fa-4ffc-bbbb-e31001489794" />
  <img width="205" alt="Mobile Preview 10" src="https://github.com/user-attachments/assets/64575509-eed0-4453-8b68-d76d5028b8fd" />
  <img width="205" alt="Mobile Preview 11" src="https://github.com/user-attachments/assets/1f0ed785-a311-4e51-93ed-333691628d84" />
  <img width="205" alt="Mobile Preview 12" src="https://github.com/user-attachments/assets/5a6beae4-3962-46bd-9b28-8011a5913f56" />
  <img width="205" alt="Mobile Preview 13" src="https://github.com/user-attachments/assets/f27dd4bf-01f9-4b66-959e-34efdae7304b" />
  <img width="205" alt="Mobile Preview 14" src="https://github.com/user-attachments/assets/f7e2fcaf-b97c-4cf1-ab39-ebfd45b4e0c1" />
  <img width="205" alt="Mobile Preview 15" src="https://github.com/user-attachments/assets/204601e6-f098-4036-afb6-64e909f3341a" />
  <img width="205" alt="Mobile Preview 16" src="https://github.com/user-attachments/assets/b29c52e9-17b7-4a50-b308-e59c66ee3530" />
  <img width="205" alt="Mobile Preview 17" src="https://github.com/user-attachments/assets/21f63762-738b-42b4-92a1-bf930dcee536" />
  <img width="205" alt="Mobile Preview 18" src="https://github.com/user-attachments/assets/380e8d61-d665-47c0-b716-dc6b4f4402bb" />
</p>
</details>

### 🖥️ Desktop App & Embedded Web Dashboard (Windows, macOS & Browser)

<p align="center">
  <img width="49%" alt="Desktop Overview" src="https://github.com/user-attachments/assets/303214a4-d129-46ae-8d6d-b22f09791dcd" />
  <img width="49%" alt="Embedded Web Dashboard" src="https://github.com/user-attachments/assets/88787c85-3972-4400-8619-d331e969a251" />
</p>

<details>
<summary><b>Click to expand all 10 Desktop &amp; Web Dashboard screenshots</b></summary>
<br />
<p align="center">
  <img width="100%" alt="Desktop Preview 2" src="https://github.com/user-attachments/assets/9092e2a7-bd40-4685-a572-64bb7794dec9" />
  <img width="100%" alt="Desktop Preview 4" src="https://github.com/user-attachments/assets/2711502c-7c74-4fb1-8d95-2e6f6efcdd3c" />
  <img width="100%" alt="Desktop Preview 5" src="https://github.com/user-attachments/assets/73be02b2-68f7-4ef9-8e52-66b9b435acba" />
  <img width="100%" alt="Desktop Preview 6" src="https://github.com/user-attachments/assets/6b965d92-c7b3-4da5-8869-ba056a3a35d0" />
  <img width="100%" alt="Desktop Preview 7" src="https://github.com/user-attachments/assets/0178bfe3-2fa9-4570-a493-5fbd3c089c44" />
  <img width="100%" alt="Desktop Preview 8" src="https://github.com/user-attachments/assets/92e5e079-56b9-4e5d-8c1b-12426fd6206f" />
  <img width="100%" alt="Desktop Preview 9" src="https://github.com/user-attachments/assets/1ace099b-0f11-4d72-8e73-275876d043c2" />
  <img width="100%" alt="Desktop Preview 10" src="https://github.com/user-attachments/assets/9fcb466d-6268-47cd-83aa-7d166353bbe6" />
</p>
</details>

---

## Table of Contents

1. [Application Previews](#-application-previews)
2. [Key Features & Pillars](#key-features--pillars)
3. [Dual-Hardware Architecture Matrix (ESP8266 vs. ESP32)](#dual-hardware-architecture-matrix-esp8266-vs-esp32)
4. [System Architecture Diagram](#system-architecture-diagram)
5. [Multi-User Privilege Tiers (Admin vs. Guest)](#multi-user-privilege-tiers-admin-vs-guest)
6. [OTA Firmware Update Engine](#ota-firmware-update-engine)
7. [Decoupled Wear-Leveled State Storage](#decoupled-wear-leveled-state-storage)
8. [Hardware & Dynamic GPIO Template Engine](#hardware--dynamic-gpio-template-engine)
9. [Cross-Architecture Backup & Restore Engine](#cross-architecture-backup--restore-engine)
10. [Pre-Compiled Binaries & Release APKs](#pre-compiled-binaries--release-apks)
11. [REST API & WebSocket Specification](#rest-api--websocket-specification)
12. [Flutter Companion App](#flutter-companion-app)
13. [Compilation & Flashing Guide](#compilation--flashing-guide)
14. [First-Time Setup Guide](#first-time-setup-guide)
15. [Troubleshooting](#troubleshooting)
16. [Project Directory Layout](#project-directory-layout)
17. [Sponsor & Support the Project](#sponsor--support-the-project)
18. [Important Safety & Legal Disclaimer](#important-safety--legal-disclaimer)
19. [License](#license)

---

## Key Features & Pillars

* **100% Standalone (No Home Assistant or Cloud Needed)**: Every ESP controller hosts its own automation engine, schedules, web dashboard, and WebSocket server directly on your local Wi-Fi LAN. Works completely offline without external servers, Raspberry Pi hubs, or paid subscriptions.
* **Single Unified Codebase**: Runs on both ESP8266 and ESP32 without separate repositories or apps, with ESP32 dual-core thread safety across WebServer, Sensors, LCD, Buzzer, and Storage subsystems.
* **Non-Blocking Asynchronous Core**: Built on asynchronous networking (`ESPAsyncWebServer`, `ESPAsyncTCP` / `AsyncTCP`) and `millis()`-driven state managers without blocking main event loops.
* **TCP Packet Fragmentation Reassembly**: Employs dynamic stream buffering (`collectJsonBody`) across REST JSON endpoints, eliminating `IncompleteInput` or `Invalid JSON` parse errors caused by ESP8266 LWIP TCP MSS packet fragmentation.
* **Autonomous Safety & Failsafe Engine**: Hardware-level Gas (MQ-2) and Over-Temperature alarms with strict `GAS > TEMP > FAULT` priority, hysteresis & probe fault debouncing, active failsafe relay lockout (prevents timers/rules/schedules from re-energizing hazardous loads during an emergency), local buzzer & I2C LCD alerts, remote `ntfy` / webhook push alerts, and Android background safety monitoring.
* **On-Device Automation & Scheduling**: Built-in condition-action sensor rules (temperature, humidity, light, motion, water temp, tank level, gas), DST-safe calendar/repeating schedules with DS3231 RTC fallback, quick countdown timers, and physical wall-switch support.
* **Seamless Web OTA (ESP8266 & ESP32)**: Intuitive drag-and-drop web updater at `http://<device_ip>/update` with cross-chip binary verification, allowing 1-click updates over Wi-Fi without needing `esptool.py` or serial cables.
* **Decoupled Wear-Leveled Runtime State**: Rapid relay cycles and switch events are packed into bitmasks and stored in wear-leveled NVS (ESP32) or EEPROM (ESP8266), reserving LittleFS strictly for static JSON configurations to help reduce flash wear over time.
* **Multi-User Privilege Tiers (Admin vs. Family/Guest)**:
  * **Admin**: Complete system control, GPIO template editing, Wi-Fi credentials, backups, factory reset, and firmware updates.
  * **Family / Guest**: Clean restricted mode allowing switch toggling, sensor monitoring, alarm muting, and quick timers, while locking out hardware changes, network settings, and flashing.
* **Dynamic GPIO Template Engine**: Runtime configuration of relay channels (0 to 8 relays, including relayless Sensor Nodes), pin remapping, boot modes, active-HIGH/LOW polarities, and switch interlocking without reflashing.
* **Obsidian Glassmorphism Web Dashboard**: Single-page application embedded directly in PROGMEM with dark/light themes, SVG iconography, real-time WebSocket telemetry, gauge animations, and a symmetrical Settings grid.
* **Cross-Platform Flutter Companion App**: Single app for **Android, iOS, Windows, and macOS** controlling both ESP8266 and ESP32 units with radar discovery, live WebSocket telemetry, **Android Quick Settings Tiles & Native Device Controls**, safe chip-verified single-controller OTA, hub backup/migration, and encrypted credential storage.
* **Optional Home Assistant MQTT Auto-Discovery**: Automatic entity creation for all relays, temperature, humidity, gas sensors, alarms, and diagnostics whenever you choose to connect an MQTT broker.
* **Defense-in-Depth Security**: Open SoftAP only for first-time / reset onboarding (no automatic AP fallback when a configured router is offline — controllers retry every 2 minutes instead), optional custom `ap_pass`, IP brute-force rate limiting, global CSRF header enforcement, XSS escaping, salted SHA-256 password hashing, sanitized backup exports by default, and encrypted mobile storage.

---

## Dual-Hardware Architecture Matrix (ESP8266 vs. ESP32)

The firmware dynamically detects and adapts to the host silicon at compile-time and runtime:

| Feature | ESP8266 (NodeMCU / D1 Mini / ESP-12) | ESP32 (DevKit / WROOM / Dual-Core) |
| :--- | :--- | :--- |
| **Silicon Architecture** | Tensilica Xtensa L106 @ 80/160 MHz | Tensilica Xtensa Dual-Core LX6 @ 240 MHz |
| **Available RAM / Heap** | ~80 KB (35–45 KB Free Heap) | 520 KB (250–320 KB Free Heap) |
| **Flash Partition Scheme** | 4MB Flash (1MB SPIFFS/LittleFS, 1MB Code) | 4MB Custom Partition (`min_spiffs`: 2x 1.9MB OTA + 192KB LittleFS) |
| **Default Relay Channels** | **2 Channels** (0–8 relays via Custom DIY Mode) | **5 Channels** (0–8 relays via Custom DIY Mode) |
| **Pin Naming** | NodeMCU Pin Names (`D0`–`D8`, `A0`) | Standard GPIO numbers (`GPIO 0`–`39`) |
| **Analog Gas Sensor (MQ-2)** | Dedicated `A0` (10-bit ADC: `0`–`1023`) | Selectable ADC1 channels (12-bit ADC: `0`–`4095`) |
| **Buzzer Acoustic Alert** | Software Non-Blocking PWM Timer | LEDC Hardware PWM Timer Channels |
| **OTA Update Architecture** | Single-Slot Web OTA (`/update`) with safe reboot | Dual-Partition Rollback (`ota_0` / `ota_1`) with 30s stability check |
| **Runtime State Storage** | Wear-leveled EEPROM Bitmasks | Wear-leveled NVS Flash Engine |
| **Hardware Presets** | 2-CH Dual, 1-CH Mini, 3-CH Pro, 4-CH Quad, 8-CH Max, Sensor Node | 5-CH Standard, 1-CH Mini, 2-CH Dual, 4-CH Pro, 8-CH Max, Sensor Node |

---

## System Architecture Diagram

```mermaid
graph TB
    subgraph Firmware_Hub["Unified SmartHome Firmware (v1.1.0)"]
        direction TB
        subgraph Core_Services["Core & Communication Engines"]
            WS_SRV["AsyncWebServer & WebSockets<br/>(Port 80 /ws)"]
            MQTT_CL["AsyncMqttClient<br/>(Home Assistant Discovery)"]
            WIFI_MG["WifiManager<br/>(STA 2-min Retry + Setup AP)"]
            DNS_SRV["Captive Portal & mDNS<br/>(smarthome-XXXX.local)"]
        end

        subgraph Security_Layer["Security & Privilege Engine"]
            AUTH["Multi-Tier RBAC<br/>(Admin vs. Guest / Family)"]
            RATE_L["IP Rate Limiter & Brute-Force Defense"]
            CSRF_G["CSRF Guard & Header Enforcer"]
            SHA_H["Salted SHA-256 Cryptographic Hasher"]
        end

        subgraph Hardware_Controllers["Hardware Subsystem Managers"]
            RELAY_MG["RelayManager<br/>(0-8 Channels + Interlock)"]
            SENSOR_MG["SensorManager<br/>(DHT11/22, BME280/BMP280, AHT20/21/25, SHT30-35, SHT40-45, BH1750, PIR/LD2410/LD2420, DS18B20, HC-SR04P/JSN-SR04T, MQ-2..135/SGP40)"]
            BUZZER_MG["BuzzerManager<br/>(LEDC PWM or ESP8266 PWM)"]
            LCD_MG["LCDManager<br/>(16x2 / 20x4 I2C Auto-Rotation)"]
            TIME_MG["TimeManager<br/>(SNTP + RTC Fallback)"]
            RULE_MG["RuleManager & AlarmScheduler<br/>(Sensor Automation Engine)"]
            BTN_MG["ButtonManager<br/>(Unified Multi-Function Button)"]
            OTA_MG["OTAManager<br/>(Dual-Partition Rollback & Web OTA)"]
        end

        subgraph Storage_Layer["Decoupled Storage Architecture"]
            NVS_PART["Wear-Leveled State Storage<br/>• ESP32 NVS / ESP8266 EEPROM<br/>• Relay Bitmasks & Wall Switch Baselines"]
            FS_PART["LittleFS (Static Filesystem)<br/>• config.json & hardware.json<br/>• rules.json & alarms.json"]
            OTA_PART["Flash Partitions<br/>• Dual OTA Slots (ESP32)<br/>• Safe Web OTA (ESP8266)"]
        end
    end

    subgraph Client_Interfaces["Client Interfaces"]
        WEB_UI["Embedded Obsidian Web Dashboard<br/>(SPA in PROGMEM, WebSocket, REST)"]
        FLUTTER_APP["Unified Flutter Companion App<br/>(Android, iOS, Windows, macOS)"]
        HA_HUB["Home Assistant / Node-RED<br/>(MQTT Auto-Discovery)"]
    end

    Client_Interfaces <==> |REST HTTP & WebSockets| Core_Services
    Core_Services --> Security_Layer
    Security_Layer --> Hardware_Controllers
    Hardware_Controllers --> Storage_Layer
```

---

## Multi-User Privilege Tiers (Admin vs. Guest)

To meet the security needs of multi-user households and family homes, authentication is partitioned into distinct privilege tiers:

| Capability / Resource | Administrator Tier | Family / Guest Tier | Unauthenticated |
|:---|:---:|:---:|:---:|
| **Control Relays & Switches** | Full Access | Full Access | Blocked |
| **View Live Sensor Telemetry** | Full Access | Full Access | Blocked |
| **Set Quick Off-Timers** | Full Access | Full Access | Blocked |
| **Mute Alarm Buzzer** | Full Access | Full Access | Blocked |
| **View Logs & Diagnostics** | Full Access | Read-Only (Wi-Fi/MQTT redacted) | Blocked |
| **Hardware & GPIO Template Config** | Full Access | **403 Forbidden** | Blocked |
| **Wi-Fi & Network Configuration** | Full Access | **403 Forbidden** | Blocked |
| **MQTT IoT Broker Settings** | Full Access | **403 Forbidden** | Blocked |
| **System Backup & Restore** | Full Access | **403 Forbidden** | Blocked |
| **OTA Firmware Flashing** | Full Access | **403 Forbidden** | Blocked |
| **Reboot & Factory Reset** | Full Access | **403 Forbidden** | Blocked |
| **mDNS & HTTP Discovery** | Allowed | Allowed | Allowed (`/api/discovery`) |


---

## OTA Firmware Update Engine

### Web OTA via Browser (Easiest & Recommended)
Both ESP8266 and ESP32 feature an embedded drag-and-drop Web OTA page:
1. Navigate to: `http://<device_ip>/update`
2. Drop the corresponding `.bin` file from [`binaries/`](binaries/):
   - For ESP8266: `binaries/esp8266/SmartHome_ESP8266.bin`
   - For ESP32: `binaries/esp32/SmartHome_ESP32.bin`
3. Click **"Upload & Flash"**. The controller verifies the binary, flashes, and reboots in ~10 seconds.

---

## Decoupled Wear-Leveled State Storage

* **Wear-Leveling Mechanism**: Rapid switch toggles and relay activations write only to native wear-leveled NVS (ESP32) or EEPROM (ESP8266), helping reduce flash wear over time (actual flash lifespan depends on your specific hardware module and usage patterns).
* **LittleFS Flash Protection**: Static JSON configuration files (`config.json`, `hardware.json`, `rules.json`, `alarms.json`) are only touched when explicitly saving settings from the Web UI or Flutter App.
* **Power-Loss Recovery**: Boot states (`Restore Last`, `Always ON`, `Always OFF`) resolve physical switch baselines before initializing GPIOs, preventing boot chatter or relay flickering on power cycles.

---

## Hardware & Dynamic GPIO Template Engine

The firmware provides a two-mode GPIO Template and Hardware Profile engine accessible via both the **Obsidian Web Dashboard** and the **Flutter Companion App**:

### 1. Two Operational Modes
* **⚡ Smart Presets**: Instant one-click hardware profiles tuned to standard hardware configurations:
  * **ESP8266**: `1-CH Mini`, `2-CH Dual` (Default), `3-CH Pro`, `4-CH Quad`, `8-CH Max`, `Sensor Node` (0 relays).
  * **ESP32**: `1-CH Mini`, `2-CH Dual`, `4-CH Pro`, `5-CH Standard` (Default), `8-CH Max`, `Sensor Node` (0 relays).
* **🛠️ Custom DIY Mode**: Total configuration freedom with zero artificial board or relay limits:
  * **0 to 8 Relays**: Add or remove relay channels dynamically (`+ Add Channel` / `− Remove`) to match your exact hardware.
  * **Custom Wall Switches**: Pair any digital input pin with any relay channel in Toggle, Follow, Inverted Follow, Pushbutton, or Detached mode.
  * **Dynamic Multi-Instance Sensors**: Add or remove multiple sensors per group (`+ Add` / `− Remove` up to hardware GPIO, ADC1/A0, and I2C address availability) across **Climate** (DHT11, DHT22/AM2302/DHT21, BME280/BMP280, AHT20/AHT21/AHT25, SHT30/SHT31/SHT35, SHT40/SHT41/SHT45, DS18B20 — up to 4), **Light** (BH1750/BH1750FVI — up to 2), **Motion** (PIR HC-SR501/AM312, mmWave Radar LD2410/LD2420/RCWL-0516 — up to 6), **Water Temp Probe** (DS18B20 — up to 4), **Ultrasonic Tank Level** (HC-SR04P/US-100, HC-SR04, JSN-SR04T/AJ-SR04M — up to 4), and **Gas & Air Quality** (MQ-2/3/4/5/6/7/8/9/135 analog/digital & SGP40 I2C VOC — up to 4, keeping ESP8266 `A0` single-analog safe), plus Buzzer, LCD Display, and Status Button.
  * **Shared I2C Bus & 7-Bit Address Arbitration**: Connect multiple I2C devices (LCD1602/2004 `0x27`/`0x3F`, BME280/BMP280 `0x76`/`0x77`, AHT20/21/25 `0x38`, SHT30-35 & SHT40-45 `0x44`/`0x45`, BH1750 `0x23`/`0x5C`, SGP40 `0x59`) simultaneously on the same SDA/SCL bus with automatic next-free address selection and collision blocking.

### 2. Live GPIO Pin Allocation & Capability Matrix
Both Web Dashboard and Companion App include real-time pin capability matrices:
* **Free**: Available for new peripheral assignment (green).
* **In Use**: Shows exact peripheral assignment (e.g., `Relay 1`, `Switch 2`, `I2C SDA`).
* **Boot Strapping Badges**: Identifies boot pins (`GPIO 0, 2, 15` on ESP8266; `GPIO 0, 2, 12, 15` on ESP32) to prevent accidental pull-down/pull-up startup hangs.
* **Input-Only Protection**: Blocks input-only pins (ESP32 `GPIO 34–39`, ESP8266 `A0 / GPIO 17`) from being assigned to outputs (relays, buzzer, DHT data line, ultrasonic trig).
* **Real-Time Conflict Detection**: Highlights double-assignments in red with interactive resolution guidance before applying.

### Default Pin Configurations

#### ESP8266 Standard 2-CH Dual (NodeMCU)
| Peripheral | NodeMCU Pin | GPIO Number | Function / Notes |
|:---|:---:|:---:|:---|
| **Relay 1 Output** | `D6` | GPIO 12 | Active LOW trigger |
| **Relay 2 Output** | `D5` | GPIO 14 | Active LOW trigger |
| **Wall Switch 1** | `D7` | GPIO 13 | Toggle Rocker (Internal Pull-Up) |
| **Wall Switch 2** | `D0` | GPIO 16 | Toggle Rocker (External Pull-Up) |
| **Climate Sensor** | `—` | Disabled (`255`) | Add I2C (`BME280`/`BMP280`/`AHT20/21/25`/`SHT30-35`/`SHT40-45`) on shared `D2`/`D1` or 1-Wire DHT/DS18B20 in Custom DIY |
| **I2C SDA (LCD / Sensors)** | `D2` | GPIO 4 | Shared I2C Bus |
| **I2C SCL (LCD / Sensors)** | `D1` | GPIO 5 | Shared I2C Bus |
| **Acoustic Buzzer** | `D4` | GPIO 2 | Software PWM / Active LOW |
| **Gas Sensor (MQ-2)** | `A0` | ADC0 / GPIO 17 | Disabled by default — Analog Gas Reading (`0`–`1023`), enable in Hardware Config |
| **Multi-Button** | `D3` | GPIO 0 | Pull-up Button / AP Reset |

#### ESP32 Standard 5-CH Profile
| Peripheral | GPIO Number | Function / Notes |
|:---|:---:|:---:|
| **Relays 1 – 5 Outputs** | GPIO 16, 17, 18, 19, 23 | Active LOW triggers |
| **Wall Switches 1 – 5** | GPIO 13, 14, 27, 26, 25 | Toggle Rocker Inputs |
| **Climate Sensor (DHT22)** | GPIO 4 | Bidirectional 1-Wire |
| **I2C SDA & SCL** | GPIO 21 (SDA), GPIO 22 (SCL) | LCD1602 & I2C Sensors |
| **Gas Sensor (MQ-2)** | GPIO 34 (Analog), GPIO 35 (Digital) | Disabled by default — ADC1 (`0`–`4095`), enable in Hardware Config |
| **Acoustic Alarm Buzzer** | GPIO 5 | LEDC Hardware PWM Channel |
| **Multi-Function Button** | GPIO 33 | Multi-function button |

---

## Cross-Architecture Backup & Restore Engine

The backup & restore subsystem is designed for reliable configuration portability across architectures:

* **Architecture Conflict Protection**: Backups include metadata tags (`"_chip": "ESP8266"` or `"ESP32"`). If an ESP32 backup is restored onto an ESP8266, the engine safely detects the incompatible pin layout, preserves the valid ESP8266 hardware profile, and applies all device configurations (Wi-Fi networks, MQTT credentials, relay names, timers, alarms, rules, and LCD modes).
* **Compact Serialization**: Employs minified JSON serialization during export, reducing payload size by over **50%** (from ~7 KB to ~3 KB) to help reduce heap fragmentation on ESP8266.
* **TCP Multi-Chunk Assembly**: Restores sent via Web UI or Mobile App are buffered across fragmented packets and capped at 32 KB to prevent memory overflow.

---

## Pre-Compiled Binaries & Release APKs

All pre-compiled firmware binaries and mobile application packages are included directly in [`binaries/`](binaries/):

### 1. Embedded Firmware Binaries
| Board | File Path | Usage |
|:---|:---|:---|
| **ESP8266** | [`binaries/esp8266/SmartHome_ESP8266.bin`](binaries/esp8266/SmartHome_ESP8266.bin) | Web OTA update via `http://<ip>/update` (956 KB) |
| **ESP32** | [`binaries/esp32/SmartHome_ESP32.bin`](binaries/esp32/SmartHome_ESP32.bin) | Web OTA update via `http://<ip>/update` (1.82 MB) |
| **ESP32 (Full Flash)** | [`binaries/esp32/SmartHome_ESP32_merged_0x0.bin`](binaries/esp32/SmartHome_ESP32_merged_0x0.bin) | Serial flasher at offset `0x0` (4.00 MB) |

### 2. Flutter Companion App Release APKs
| Target Architecture | File Path | Size | Device Compatibility |
|:---|:---|:---:|:---|
| **ARM 64-bit** | [`binaries/app/app-arm64-v8a-release.apk`](binaries/app/app-arm64-v8a-release.apk) | **20.7 MB** | **All modern Android phones** (Samsung, Pixel, OnePlus, Xiaomi) |
| **ARM 32-bit** | [`binaries/app/app-armeabi-v7a-release.apk`](binaries/app/app-armeabi-v7a-release.apk) | **18.3 MB** | Older 32-bit Android phones |
| **x86_64** | [`binaries/app/app-x86_64-release.apk`](binaries/app/app-x86_64-release.apk) | **22.2 MB** | Android Emulators & ChromeOS |

---

## REST API & WebSocket Specification

### Core Endpoints

| Method | Endpoint | Access Tier | Description |
|:---|:---|:---:|:---|
| `GET` | `/api/status` | Family / Admin | Real-time sensor telemetry, relay states, system heap & uptime |
| `GET` | `/api/discovery` | Public | Lightweight discovery payload (`auth_required`, MAC, model, relays) |
| `POST` | `/api/relay` | Family / Admin | Toggle or set individual relay (`{"id": 0, "action": "toggle"}`) |
| `POST` | `/api/relay/all` | Family / Admin | Bulk control (`{"action": "on"}` or `{"action": "off"}`) |
| `POST` | `/api/relay/timer` | Family / Admin | Set quick off/on timer (`{"id": 0, "duration": 1800}`) |
| `POST` | `/api/config` | Admin | Update system parameters (Device Name, Timezone, Passwords) |
| `POST` | `/api/config/wifi` | Admin (or Fresh Setup) | Save Wi-Fi STA credentials & connect |
| `POST` | `/api/config/mqtt` | Admin | Configure Home Assistant MQTT IoT broker |
| `POST` | `/api/hardware` | Admin | Save dynamic GPIO pin mapping template |
| `GET` | `/api/backup` | Admin | Export sanitized system configuration JSON (`?sanitize=0` for full secrets) |
| `POST` | `/api/restore` | Admin | Restore system configuration JSON & reboot |
| `POST` | `/api/reboot` | Admin | Gracefully reboot controller |
| `POST` | `/api/factory-reset`| Admin | Delete LittleFS configs & revert to factory defaults |
| `GET` | `/api/logout` | Family / Admin | Invalidate session, evict browser HTTP auth headers |
| `WS` | `/ws` | Family / Admin | Real-time bi-directional telemetry broadcast socket |

---

## Flutter Companion App

The Flutter companion app (`app/`) provides unified control over all ESP8266 and ESP32 controllers on your local network:

* **Radar Discovery**: Automatically detects online controllers via mDNS (`_smarthome._tcp`) and intelligent subnet probing (`/api/discovery`) without manual IP configuration. Displays Amber badges for ESP8266 and Cyan badges for ESP32.
* **Architecture-Aware Hardware Editor**: Adapts pin dropdowns and preset templates dynamically based on whether the selected controller is ESP8266 or ESP32.
* **Android Quick Settings Tiles & Native Device Controls**: Toggle relays directly from Android's Quick Settings shade and system Device Controls, with configurable lockscreen protection.
* **Background Safety Monitor (Android)**: Monitors paired controllers in the background and triggers high-priority emergency alarms if Gas or Over-Temperature alerts fire.
* **Safe Single-Controller OTA**: Validates firmware binary headers and chip architecture before uploading, preventing accidental cross-flashing between ESP32 and ESP8266 boards.
* **Hub Migration**: One-click export of all paired controllers, room assignments, credentials, and custom icon sets in a single `.json` file.

### Running the App Locally:
```bash
cd app/
flutter pub get

# Run on connected smartphone or emulator:
flutter run

# Run automated test suite:
flutter test

# Build release APKs:
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols --split-per-abi --no-tree-shake-icons
```

---

## Compilation & Flashing Guide

### Automated 1-Click Build Script (Recommended)

The project includes an automated PowerShell build script [`build_firmware.ps1`](build_firmware.ps1) that compiles firmware and copies output binaries to `binaries/`:

```powershell
# Build for both ESP8266 and ESP32:
.\build_firmware.ps1

# Build for a specific target only:
.\build_firmware.ps1 -Target esp32
.\build_firmware.ps1 -Target esp8266
```

The script auto-detects the locally installed `arduino-cli`, compiles with the correct FQBN and partition scheme, and copies the resulting `.bin` files to `binaries/esp8266/` and `binaries/esp32/`.

### Manual Compilation via Arduino CLI

#### 1. For ESP8266 (NodeMCUv2 / 4MB):
```bash
arduino-cli compile --fqbn esp8266:esp8266:nodemcuv2 SmartHome.ino
```

#### 2. For ESP32 (4MB Flash with Dual OTA):
```bash
arduino-cli compile --fqbn espressif:esp32:esp32:PartitionScheme=min_spiffs SmartHome.ino
```

---

## First-Time Setup Guide

```mermaid
sequenceDiagram
    autonumber
    actor User as Installer / User
    participant ESP as ESP Controller
    participant Phone as Phone / PC Browser

    ESP->>ESP: First boot: No Wi-Fi credentials found
    ESP->>ESP: Launch Open Setup AP: "SmartHome-XXXX" (or custom ap_pass)
    ESP->>User: LCD displays Setup AP SSID
    User->>Phone: Connect to Wi-Fi "SmartHome-XXXX"
    Phone->>ESP: Captive Portal loads http://192.168.4.1
    Note over ESP,Phone: Unlock with Admin login first if resetting Wi-Fi with Admin Auth enabled
    User->>Phone: Enter Home Wi-Fi SSID, Password & optional Admin Password
    Phone->>ESP: POST /api/config/wifi
    ESP->>ESP: Connect to local network (retries every 2 min if router is offline)
    ESP->>User: LCD shows assigned IP (e.g. 192.168.29.66)
    User->>Phone: Navigate to http://192.168.29.66 or launch Flutter App
    User->>Phone: Settings > Security: Set/Manage Admin & Guest Passwords
    Phone->>ESP: POST /api/config (Credentials hashed & stored)
```

1. **Power On**: Power the controller via 5V/2A power supply.
2. **Join Hotspot**: Connect your smartphone or PC to `SmartHome-XXXX`. On a fresh flash or factory/Wi-Fi reset, the setup hotspot is **Open** (no password required—ideal for headless controllers without an LCD) unless you explicitly configure a custom `"ap_pass"`. Once Wi-Fi is configured, controllers never fall back to AP mode if your router goes offline; they retry connecting every 2 minutes until the router returns or you manually reset Wi-Fi via the physical button.
3. **Captive Portal**: Tap the *"Sign in to Wi-Fi network"* notification (or open `http://192.168.4.1`) and connect the controller to your home Wi-Fi network. If you performed a Wi-Fi-only reset with Admin Auth already enabled, enter your existing Admin credentials inline on the setup screen to unlock Wi-Fi scanning and saving.
4. **Access Dashboard**: Open `http://<device_ip>` or launch the Flutter companion app.
5. **Set Passwords**: Go to **Settings > Security & Privilege Tiers** and set your **Admin** and **Guest** passwords.

---

## Troubleshooting

### "Invalid JSON" error when saving settings on ESP8266
This was caused by TCP MSS body fragmentation in older builds. Flash the latest firmware binary ([`binaries/esp8266/SmartHome_ESP8266.bin`](binaries/esp8266/SmartHome_ESP8266.bin)) via `/update` which reassembles fragmented TCP packets seamlessly.

### Captive portal does not open automatically
If your phone previously connected to `SmartHome-XXXX` and dismissed the prompt (or tapped *"Use network anyway"*), tap **Forget** on `SmartHome-XXXX` in your phone's Wi-Fi settings and reconnect, or manually navigate to `http://192.168.4.1` in your browser while connected to the controller's Wi-Fi access point.

### Serial flasher fails with "Flash ID: 0" on ESP8266
On ESP8266, GPIO 0, 2, and 15 are hardware strapping pins. If attached peripherals pull these pins during serial flashing, bootloader handshake fails. **Use Web OTA (`http://<device_ip>/update`) instead**, which completely bypasses all serial pin strapping restrictions.

### Physical Multi-Button Functions (GPIO 33 / GPIO 0)
* **Hold 6–10 seconds**: Triggers a **Wi-Fi Reset** (clears saved Wi-Fi credentials and enters AP setup mode without losing relay or auth configs).
* **Hold 10–14 seconds**: Triggers a **Full Factory Reset** (wipes LittleFS configs & NVS state and reboots to factory defaults).

---

## Project Directory Layout

```text
SmartHome-Pro/
├── SmartHome.ino                  # Main Arduino firmware setup and main loop
├── Config.h                       # Global configuration constants and dual-chip pin definitions
├── WebPages.h                     # Embedded obsidian glassmorphism SPA dashboard in PROGMEM
├── WebServerManager.h / .cpp      # REST API endpoints, RBAC tiers, TCP reassembly, rate limiter
├── WebSocketManager.h / .cpp      # Real-time WebSocket event broadcaster
├── RelayManager.h / .cpp          # Multi-channel relay control, polarity, quick timers
├── SensorManager.h / .cpp         # DHT11/22, BME280/BMP280, AHT20/21/25, SHT30-35, SHT40-45, BH1750, PIR/LD2410/LD2420, DS18B20, HC-SR04P/JSN-SR04T, MQ-2..135/SGP40
├── HardwareManager.h / .cpp       # Dynamic GPIO template manager and pin safety catalogs
├── StorageManager.h / .cpp        # Decoupled wear-leveled NVS & LittleFS storage
├── OTAManager.h / .cpp            # Dual-partition rollback and Web OTA manager
├── WifiManager.h / .cpp           # Multi-AP Wi-Fi manager and captive portal
├── MqttManager.h / .cpp           # Home Assistant MQTT auto-discovery client
├── LCDManager.h / .cpp            # 16x2 / 20x4 I2C LCD screen auto-rotation and alert display
├── BuzzerManager.h / .cpp         # Acoustic alert patterns (LEDC PWM on ESP32, PWM on ESP8266)
├── ButtonManager.h / .cpp         # Multi-function button hardware debounce handler
├── EventLogger.h / .cpp           # Circular memory-buffered diagnostic event logger
├── Diagnostics.h / .cpp           # Hardware health, heap tracking, silicon diagnostics
├── TimeManager.h / .cpp           # SNTP network clock and DS3231 RTC fallback
├── AlarmScheduler.h / .cpp        # Scheduled calendar and delay event manager
├── RuleManager.h / .cpp           # Condition-action sensor automation engine
├── RemoteAlertManager.h / .cpp    # Async remote webhook & ntfy push alerts
├── build_firmware.ps1             # Automated 1-click firmware build script (ESP8266 + ESP32)
├── CHANGELOG.md                   # Release notes and version history
├── asset/                         # Project icon and branding assets
├── binaries/                      # Ready-to-flash binaries & release APKs
│   ├── esp8266/                   # Compiled SmartHome_ESP8266.bin & SmartHome.ino.bin for Web OTA
│   ├── esp32/                     # Compiled SmartHome_ESP32.bin, bootloader, partitions & merged 0x0 binary
│   └── app/                       # Release APKs (arm64-v8a, armeabi-v7a, x86_64)
└── app/                           # Flutter cross-platform companion app
    ├── pubspec.yaml               # Flutter dependencies and assets
    ├── lib/                       # Dart application source code
    │   └── presentation/screens/
    │       └── about_screen.dart  # About & Sponsorship screen (UPI + PayPal)
    └── test/                      # Automated unit and widget test suite (124 tests)
```

---

## Sponsor & Support the Project

If this project brings value to your home or DIY maker setup, consider sponsoring to fuel ongoing firmware development, hardware lab testing, and new features!

### 🇮🇳 India — UPI Payment (Zero Fee · Instant)

| UPI VPA ID | Supported Apps |
|:---|:---|
| **`1vikash@ybl`** | Google Pay · PhonePe · Paytm · BHIM · Cred · Amazon Pay |

### 🌍 International — PayPal

| PayPal | Link |
|:---|:---|
| **Vikash Choudhary** | [https://paypal.me/1vikash](https://paypal.me/1vikash) |



---

## Important Safety & Legal Disclaimer

> [!CAUTION]
> **READ CAREFULLY BEFORE BUILDING, FLASHING, OR USING THIS SOFTWARE.** By downloading, compiling, flashing, installing, or using any part of this project, you agree to the terms below and in [`LICENSE`](LICENSE).

1. **No Warranties or Guarantees ("AS IS"):** This firmware, companion application, pre-compiled binary set, and documentation are provided strictly **"AS IS"** without warranty, representation, or guarantee of any kind—express or implied. No guarantee is made regarding uptime, flash memory lifespan, OTA recovery, prevention of bricked devices, data retention, security against unauthorized access, or bug-free operation.
2. **High-Voltage & Electrical Hazard:** Connecting relays or DIY electronics to AC mains electricity (**110V–240V AC**) or high-current loads can cause **electric shock, fire, property damage, severe injury, or death**. You are solely responsible for proper electrical isolation, enclosures, fusing, wiring ratings, and compliance with all local electrical codes. If you are not qualified to work with mains electricity, consult a licensed electrician.
3. **Not Certified for Life-Safety or Hazard Prevention:** This project is **not certified** (no UL, CE, FCC, BIS, or safety certification). Gas sensors (e.g., MQ-2), temperature sensors, failsafe relay cutoffs, buzzers, webhooks, and mobile alerts are **best-effort informational features only** and **MUST NOT** be relied upon as a primary smoke, gas, fire, medical, security, or life-safety alarm system. Always install and maintain certified standalone safety detectors.
4. **Total Assumption of Risk & Zero Liability:** You assume **100% of the risk and responsibility** for any hardware selection, wiring, firmware flashing, network configuration, and operation. Under no circumstances shall the author or copyright holder be liable for any direct, indirect, incidental, special, consequential, or physical damages—including bricked microcontrollers, damaged appliances, flash wear, data loss, false or missed alarms, electrical fire, property damage, personal injury, or death—arising out of or related to the use or inability to use this project.

---

## License

Copyright © 2026 Vikash Choudhary. All rights reserved.

This project is released under the **[Personal Non-Commercial Source-Available License](LICENSE)**:
- **Permitted**: Free personal, private, non-commercial home use on your own hardware.
- **Prohibited**: Any code modification, derivative works, redistribution, or commercial/business use.
- **No Warranty**: Provided `"AS IS"` without warranty or liability of any kind. See [`LICENSE`](LICENSE) for full terms.
