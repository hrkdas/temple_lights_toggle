# Temple Lights Toggle 🪔✨

[![License: MIT](https://img.shields.io/badge/License-MIT-amber.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.24.0-02569B?logo=flutter)](https://flutter.dev)
[![PlatformIO](https://img.shields.io/badge/PlatformIO-Espressif32-orange?logo=platformio)](https://platformio.org)
[![ESP32](https://img.shields.io/badge/ESP32-NodeMCU--32S-red?logo=espressif)](https://www.espressif.com)
[![BLE GATT](https://img.shields.io/badge/BLE-GATT%20NimBLE-blue)](https://github.com/h2zero/NimBLE-Arduino)

An open-source, dual-system project combining an **ESP32 BLE autonomous WS2812B RGB LED controller** with a companion **Flutter mobile app** featuring Serene Luxury UI, autonomous scheduling, flash activity logging, and **in-app over-the-air (OTA) firmware flashing**.

---

## 📑 Table of Contents
1. [Overview](#-overview)
2. [Key Features](#-key-features)
3. [Hardware Bill of Materials & Wiring](#-hardware-bill-of-materials--wiring)
4. [Repository Architecture](#-repository-architecture)
5. [ESP32 Firmware Guide (`firmware/`)](#-esp32-firmware-guide-firmware)
6. [Flutter Mobile App Guide](#-flutter-mobile-app-guide)
7. [BLE Wire Protocol & GATT Dictionary](#-ble-wire-protocol--gatt-dictionary)
8. [In-App BLE OTA Firmware Updates](#-in-app-ble-ota-firmware-updates)
9. [Step-by-Step Operating Guide](#-step-by-step-operating-guide)
10. [Troubleshooting & FAQs](#-troubleshooting--faqs)
11. [License](#-license)

---

## 🌟 Overview

Temple Lights was designed to illuminate home shrines and temple sanctuaries with warm, ambient lighting. The system operates in two synergistic ways:

1. **Standalone Autonomous Mode (No Phone Needed)**: When plugged into wall power, the ESP32 drives the LED strip instantly. Toggling wall power or unplugging and replugging the power cord advances the lighting preset through Non-Volatile Storage (NVS) memory ($0 \to 1 \to 2 \to 0$).
2. **Smart Companion App Mode (BLE)**: Connect seamlessly with Android or iOS to fine-tune brightness, customize RGB colors, manage up to 16 autonomous weekly on/off schedules, inspect flash event history, and flash new ESP32 firmware updates wirelessly over BLE.

---

## ⚡ Key Features

- **Autonomous Power-Cycle Mode Switching**: Cycles through presets (Warm White $\to$ Center 1.5m Glow $\to$ Pure White) simply by toggling the physical power switch.
- **Serene Luxury Light UI**: Warm amber and gold palette, typography inspired by temple tranquility, interactive glowing circular light dial, and tactile haptic feedback.
- **Fast Auto-Connect BLE**: Zero-friction background scanning that identifies and locks onto `"Temple Lights"` automatically.
- **On-Device Weekly Schedules**: Stores up to 16 time-based schedules in ESP32 flash memory that execute independently of whether a phone is connected.
- **Hardware POSIX Time Sync**: The app quietly synchronizes the ESP32 internal real-time clock (RTC) upon every connection.
- **Circular Flash Event Log**: Flash-persisted record of the last 20 operations (`ON`, `OFF`, `MODE_CHG`, `SCHEDULE_TRIG`, `BOOT`).
- **In-App Dual-Partition OTA Updates**: Bundled firmware binary in the APK flashed over BLE with chunk streaming, checksum verification, and atomic partition rollback protection.

---

## 🔌 Hardware Bill of Materials & Wiring

### Bill of Materials (BOM)
| Component | Specification | Quantity | Purpose |
| :--- | :--- | :--- | :--- |
| **Microcontroller** | NodeMCU-32S (ESP32-WROOM-32, 4MB Flash) | 1 | Runs NimBLE, NVS, and LED animation logic |
| **Addressable LEDs** | WS2812B 5V RGB LED Strip (60 LEDs/m) | 2.5m – 3.0m (150–180 LEDs) | Primary lighting element |
| **Power Supply (PSU)** | 5V DC 3A–5A Power Adapter | 1 | Powers both ESP32 and LED strip |
| **Capacitor** | 1000 µF / 16V Electrolytic | 1 | Smooths power spikes and prevents LED brownout |
| **Resistor** | 330 Ω to 470 Ω (1/4 W) | 1 | Protects the WS2812B data input from voltage transients |

### Wiring Schematic

```text
              +5V Power Supply (5V 3A-5A)
                   │             │
                   ├──[ + ]──────┼─────────> WS2812B Strip +5V
                   │  1000µF     │
                   ├──[ - ]──────┼─────────> ESP32 VIN / 5V
                   │  Capacitor  │
     GND (Common) ─┴─────────────┼─────────> WS2812B Strip GND
                                 ├─────────> ESP32 GND
                                 │
     ESP32 GPIO 4 ──[ 330Ω Resistor ]──────> WS2812B Strip DIN (Data In)
```

> [!IMPORTANT]
> **Common Ground**: Always ensure the ESP32 `GND` and WS2812B `GND` are tied together. A missing common ground will cause flickering or random color glitches.

---

## 📁 Repository Architecture

The project is maintained as a monorepo containing both the Flutter companion app and the ESP32 PlatformIO firmware:

```text
temple_lights_toggle/
├── android/                      # Android native platform files (permissions, Gradle)
├── assets/
│   ├── firmware/
│   │   └── firmware.bin          # Compiled ESP32 binary bundled directly inside the APK
│   └── icons/                    # Vector logos & app icons
├── firmware/                     # ESP32 PlatformIO Project
│   ├── include/                  # C++ headers
│   ├── lib/                      # PlatformIO libraries
│   ├── src/
│   │   └── main.cpp              # ESP32 application (NimBLE, NeoPixelBus/FastLED, NVS, OTA)
│   ├── test/                     # PlatformIO firmware unit tests
│   ├── partitions_ota.csv        # Custom dual-app flash partition table (1.9MB app0/app1)
│   └── platformio.ini            # PlatformIO build configuration for NodeMCU-32S
├── ios/                          # iOS platform files & Info.plist permissions
├── lib/                          # Flutter source code
│   ├── app.dart                  # App root widget & theme binding
│   ├── contract/                 # BLE UUIDs, packet encodings, & OTA constants
│   ├── core/                     # Haptics, permissions, logging, local storage
│   ├── domain/                   # Data models & Riverpod state providers
│   ├── features/
│   │   ├── home/                 # Main control screen with glowing light dial
│   │   ├── modes/                # Mode selector (Warm White, Center Glow, Pure White, Custom)
│   │   ├── ota/                  # Animated in-app BLE OTA firmware flashing screen
│   │   ├── scanner/              # BLE device scanner & connection sheet
│   │   ├── schedule/             # 16-slot autonomous schedule editor
│   │   └── settings/             # Settings, firmware info, & logs viewer
│   ├── transport/                # NimBLE transport client & OTA chunking pipeline
│   └── ui/                       # Design tokens, amber/gold palette, and animations
├── test/                         # Flutter widget & BLE contract unit tests
├── pubspec.yaml                  # Flutter package & asset manifest
├── LICENSE                       # Open-source MIT License
├── README.md                     # This documentation
└── TEMPLE_LIGHTS_FULL_CONTEXT.md # Comprehensive architectural reference
```

---

## 🛠️ ESP32 Firmware Guide (`firmware/`)

The firmware is developed with [PlatformIO](https://platformio.org/) using the Arduino core for ESP32 and [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) for high-performance, low-memory Bluetooth LE.

### 1. Prerequisites
- Install [Visual Studio Code](https://code.visualstudio.com/) with the **PlatformIO IDE** extension, OR install PlatformIO Core CLI:
  ```bash
  pip install -U platformio
  ```

### 2. Dual-OTA Partition Configuration
The firmware uses `partitions_ota.csv` to allocate two symmetric 1.9 MB flash partitions (`app0` and `app1`):
```csv
# Name,   Type, SubType, Offset,  Size, Flags
nvs,      data, nvs,     0x9000,  0x5000,
otadata,  data, ota,     0xe000,  0x2000,
app0,     app,  ota_0,   0x10000, 0x1F0000,
app1,     app,  ota_1,   0x200000,0x1F0000,
spiffs,   data, spiffs,  0x3F0000,0x10000,
```

### 3. Initial USB Flash
Connect the ESP32 to your computer via micro-USB.

```bash
# Navigate to firmware directory
cd firmware

# Compile firmware
pio run

# Flash firmware and partition table via USB
pio run --target upload

# Open serial monitor (115200 baud)
pio device monitor -b 115200
```

> [!NOTE]
> The initial flash **must** be executed via USB cable so PlatformIO can partition the flash memory according to `partitions_ota.csv`. All future updates can then be flashed wirelessly through the mobile app.

### 4. Updating the Bundled OTA Binary
Whenever you make changes to the firmware and wish to bundle it into the Flutter APK:
```bash
cd firmware
pio run
cp .pio/build/nodemcu-32s/firmware.bin ../assets/firmware/firmware.bin
```

---

## 📱 Flutter Mobile App Guide

The companion mobile app is built with Flutter and Riverpod.

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.24.0`)
- Android Studio / Xcode for platform toolchains

### 2. Bluetooth & Location Permissions
- **Android**: Handled automatically via `permission_handler` for `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and fine location (required on Android 11 and below).
- **iOS**: `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` are configured in `ios/Runner/Info.plist`.

### 3. Run & Test
```bash
# Fetch dependencies
flutter pub get

# Run unit and contract tests (27 tests)
flutter test

# Run app on connected phone or emulator
flutter run

# Build release APK (bundles assets/firmware/firmware.bin)
flutter build apk --release
```
The compiled APK will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📡 BLE Wire Protocol & GATT Dictionary

Communication between phone and ESP32 occurs over Bluetooth Low Energy (BLE) using structured JSON packets for control, and binary chunks for OTA updates.

### BLE GATT Services & Characteristics

| Service / Characteristic | UUID | Permissions | Description |
| :--- | :--- | :--- | :--- |
| **Primary Lighting Service** | `95d6fedc-cac3-48e2-8221-f534a2782704` | — | Primary GATT Service |
| **Control Characteristic** | `0ddad461-e5e3-457b-a173-da66bd52bf4d` | `READ \| WRITE \| NOTIFY` | Bidirectional JSON command channel |
| **Dedicated OTA Service** | `95d6fedc-cac3-48e2-8221-f534a2782710` | — | High-Speed Wireless Flashing Service |
| **OTA Control Characteristic** | `0ddad461-e5e3-457b-a173-da66bd52bf4e` | `WRITE \| NOTIFY` | OTA session management (`ota_begin`, `ota_end`) |
| **OTA Data Characteristic** | `0ddad461-e5e3-457b-a173-da66bd52bf4f` | `WRITE_NO_RESP \| WRITE` | 256-byte binary firmware stream |
| **OTA Status Characteristic** | `0ddad461-e5e3-457b-a173-da66bd52bf50` | `READ \| NOTIFY` | Flash offset ACK and error status |

---

### JSON Command Dictionary (Sent to Control Characteristic)

#### 1. Power State
```json
{"cmd": "state", "val": 1}  // 1 = ON, 0 = OFF
```

#### 2. Preset Mode Selection
```json
{"cmd": "mode", "val": 0}   // 0 = Warm White, 1 = Center Glow (1.5m), 2 = Pure White, 3 = Custom RGB
```

#### 3. Custom RGB Color
```json
{"cmd": "color", "r": 255, "g": 180, "b": 50}
```

#### 4. Brightness
```json
{"cmd": "brightness", "val": 200}  // 1 to 255
```

#### 5. POSIX Clock Synchronization
```json
{"cmd": "time", "epoch": 1726915000}
```

#### 6. Autonomous Weekly Schedule Configuration
```json
{
  "cmd": "sched",
  "id": 0,
  "enabled": true,
  "action": 1,
  "hour": 6,
  "min": 30,
  "days": 127,
  "mode": 0,
  "r": 255,
  "g": 147,
  "b": 41,
  "brightness": 255
}
```
*Note: `days` is a bitmask where Bit 0 = Sunday, Bit 1 = Monday ... Bit 6 = Saturday (`127` = All Days).*

#### 7. Fetch Device Activity Logs
```json
{"cmd": "get_logs"}
```

---

## 🚀 In-App BLE OTA Firmware Updates

The Flutter app includes a built-in firmware updater with real-time transfer progress, speed calculations (KB/s), ETA countdown, and animated status visualizers.

```text
┌────────────────────────────────────────────────────────┐
│               Phone (Flutter Companion App)            │
└────────────────────────────────────────────────────────┘
                           │
       1. Read bundled firmware.bin from APK assets
       2. Calculate MD5 checksum & byte length
                           │
                           ▼
              OTA Control Characteristic
     Write: {"cmd":"ota_begin","size":654189,"md5":"..."}
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│               ESP32 (NodeMCU-32S)                      │
│ - Erases target OTA flash partition (app0 or app1)     │
│ - Switches LEDs OFF to preserve flash write stability  │
│ - Notifies: {"status":"ready","chunk_size":256}        │
└────────────────────────────────────────────────────────┘
                           │
                           ▼
              OTA Data Characteristic
     Streams 256-byte binary chunks with writeWithResponse
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│               ESP32 (NodeMCU-32S)                      │
│ - Writes binary bytes directly to flash partition      │
│ - Emits progress notification: {"status":"progress"}   │
└────────────────────────────────────────────────────────┘
                           │
                           ▼
              OTA Control Characteristic
     Write: {"cmd":"ota_end"}
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│               ESP32 (NodeMCU-32S)                      │
│ - Validates binary size & MD5 checksum against flash   │
│ - Calls esp_ota_set_boot_partition()                   │
│ - Reboots automatically into upgraded firmware!        │
└────────────────────────────────────────────────────────┘
```

> [!TIP]
> **Atomic Rollback Guarantee**: The active partition is never overwritten. If Bluetooth disconnects mid-transfer, the ESP32 aborts the write and reboots safely into its existing, working firmware.

---

## 📖 Step-by-Step Operating Guide

### 1. Powering On & Wall Switch Preset Cycling
1. Plug the 5V power adapter into wall power.
2. The LED strip illuminates immediately in **Mode 0 (Full Warm White)**.
3. Turn the wall switch **OFF and back ON within 5 seconds**: The strip advances to **Mode 1 (Center Focus 1.5m Glow)**.
4. Turn the wall switch **OFF and back ON again**: The strip advances to **Mode 2 (Pure White)**.
5. The ESP32 persists this state in NVS so it always remembers where it left off.

### 2. Connecting the Companion App
1. Open the **Temple Lights** mobile app on Android or iOS.
2. Ensure Bluetooth is enabled.
3. The app scans for `"Temple Lights"` and connects automatically.
4. The circular Light Dial turns warm amber with a subtle breathing glow when connected.

### 3. Setting Autonomous Daily Schedules
1. Tap the **Schedules** tab in the bottom navigation.
2. Tap **Add Schedule** (e.g., Morning Aarti at 06:30 AM, Evening Aarti at 07:00 PM).
3. Choose the target action (Turn ON / Turn OFF), mode, color, and active days of the week.
4. Tap **Save Schedule**. The rule is transmitted to the ESP32 and saved to flash memory.

### 4. Performing an In-App OTA Firmware Update
1. Open the **Settings** sheet in the mobile app.
2. Scroll to the **ESP32 Firmware OTA** card and tap **Open Firmware Updater**.
3. The screen displays the current device version and the bundled APK version.
4. Tap **Begin Wireless Update**.
5. Keep your phone within 3 meters of the ESP32 until the transfer animation reaches 100% and the device reboots.

---

## ❓ Troubleshooting & FAQs

### Why does the ESP32 reboot when the LEDs turn on?
- **Root Cause**: WS2812B LED strips draw up to 50–60 mA per LED at full white. 150 LEDs can draw upwards of 3.5 Amps. If your 5V supply cannot deliver this current, the voltage drops below 2.7V, causing an ESP32 brownout reboot.
- **Fix**: Use a 5V 4A or 5V 5A regulated power supply, and connect a 1000 µF electrolytic capacitor across the 5V and GND rail near the LED strip input.

### The app displays "Scanning..." but does not connect.
- Ensure Bluetooth and Location services are enabled on your smartphone.
- Verify that another smartphone is not currently connected to the ESP32 (NimBLE handles one active peer connection at a time).
- Unplug the ESP32 for 2 seconds and plug it back in.

### The LED colors are jittery or flickering random colors.
- Ensure the **ESP32 Ground and the LED strip Ground are connected together**.
- Insert a **330 Ω resistor** in series between ESP32 GPIO 4 and the LED Strip DIN pin.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

```text
Copyright (c) 2026 Hrithik Das

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
...
```

---

<p align="center">
  Crafted with care for peaceful sanctuaries 🪔
</p>
