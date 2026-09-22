# Temple Lights — Comprehensive Project Context & Implementation Reference

> **Project**: ESP32 BLE Autonomous WS2812B RGB Temple Light Controller & Companion Flutter Mobile App  
> **Workspace (Flutter)**: `/Users/hrk/StudioProjects/temple_lights_toggle`  
> **Workspace (ESP32)**: `/Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple`  
> **Firmware Board**: NodeMCU-32S (ESP32-WROOM-32, 4MB Flash)  
> **Partition Table**: `min_spiffs.csv` (Dual ~1.9MB OTA Partitions `ota_0` & `ota_1`)  
> **LED Strip**: 2.5–3.0 Meters WS2812B (60 LEDs/m = 150–180 LEDs) on **GPIO 4**  
> **Design Language**: Serene Luxury Light UI Theme (Warm Ivory Alabaster, Pure White, Saffron Amber & Temple Gold)

---

## Table of Contents

1. [Tagged Markdown Files Index](#1-tagged-markdown-files-index)
2. [Executive Summary & Conversation Timeline](#2-executive-summary--conversation-timeline)
3. [Hardware Architecture & Electrical Specifications](#3-hardware-architecture--electrical-specifications)
4. [Lighting Modes & Autonomous Power-Cycle Boot Logic](#4-lighting-modes--autonomous-power-cycle-boot-logic)
5. [ESP32 Firmware Deep Dive (`esp_rgb_strip_temple`)](#5-esp32-firmware-deep-dive-esp_rgb_strip_temple)
6. [Dual-OTA Firmware Architecture & ESP32 Partition Table](#6-dual-ota-firmware-architecture--esp32-partition-table)
7. [BLE Protocol, Wire Contract & Command Dictionary](#7-ble-protocol-wire-contract--command-dictionary)
8. [Companion Flutter Mobile Application (`temple_lights_toggle`)](#8-companion-flutter-mobile-application-temple_lights_toggle)
9. [Serene Luxury Light UI Theme System](#9-serene-luxury-light-ui-theme-system)
10. [End-to-End BLE Over-The-Air (OTA) Update System](#10-end-to-end-ble-over-the-air-ota-update-system)
11. [Autonomous Edge Subsystems (RTC, Schedules, Timers, Logs)](#11-autonomous-edge-subsystems-rtc-schedules-timers-logs)
12. [Verification, Static Analysis & Build Results](#12-verification-static-analysis--build-results)
13. [Deployment, Flashing & Operation Guide](#13-deployment-flashing--operation-guide)

---

## 1. Tagged Markdown Files Index

Below is the complete registry of all markdown documents, implementation plans, walkthroughs, and reference contexts generated throughout the project lifecycle:

| File / Artifact Link | Location | Role & Contents |
| :--- | :--- | :--- |
| [**`walkthrough.md` (OTA)**](file:///Users/hrk/.gemini/antigravity/brain/7f6e3289-b93c-49df-b99a-ce079619908a/walkthrough.md) | `<brain>/7f6e3289-b93c-49df-b99a-ce079619908a/walkthrough.md` | Verification walkthrough for the BLE OTA firmware update feature, partition changes, and animated progress screen. |
| [**`implementation_plan.md` (OTA)**](file:///Users/hrk/.gemini/antigravity/brain/7f6e3289-b93c-49df-b99a-ce079619908a/implementation_plan.md) | `<brain>/7f6e3289-b93c-49df-b99a-ce079619908a/implementation_plan.md` | Technical design and implementation plan for dual-OTA partitions, GATT chunk streaming, and APK bundling. |
| [**`walkthrough.md` (Core)**](file:///Users/hrk/.gemini/antigravity/brain/d982b863-b6c8-4390-82c5-9d6a179865dc/walkthrough.md) | `<brain>/d982b863-b6c8-4390-82c5-9d6a179865dc/walkthrough.md` | Core walkthrough covering initial firmware capabilities, Flutter app architecture, and Serene Luxury Light UI. |
| [**`temple_lights_context.md`**](file:///Users/hrk/.gemini/antigravity/brain/d982b863-b6c8-4390-82c5-9d6a179865dc/temple_lights_context.md) | `<brain>/d982b863-b6c8-4390-82c5-9d6a179865dc/temple_lights_context.md` | Dedicated system artifact replica for immediate rendering inside the AI workspace environment. |
| [**`agent.md`**](file:///Users/hrk/.gemini/antigravity/brain/d982b863-b6c8-4390-82c5-9d6a179865dc/.agents/agents/flutter-writer/agent.md) | `<brain>/d982b863-b6c8-4390-82c5-9d6a179865dc/.agents/agents/flutter-writer/agent.md` | Subagent definition specification used to generate Flutter project source files in parallel. |
| [**`README.md` (Flutter)**](file:///Users/hrk/StudioProjects/temple_lights_toggle/README.md) | `/Users/hrk/StudioProjects/temple_lights_toggle/README.md` | Base project documentation for the `temple_lights_toggle` companion Flutter repository. |
| [**`TEMPLE_LIGHTS_FULL_CONTEXT.md` (ESP32)**](file:///Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/TEMPLE_LIGHTS_FULL_CONTEXT.md) | `/Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/TEMPLE_LIGHTS_FULL_CONTEXT.md` | Single-source-of-truth reference file stored inside the ESP32 firmware project. |
| [**`TEMPLE_LIGHTS_FULL_CONTEXT.md` (Flutter)**](file:///Users/hrk/StudioProjects/temple_lights_toggle/TEMPLE_LIGHTS_FULL_CONTEXT.md) | `/Users/hrk/StudioProjects/temple_lights_toggle/TEMPLE_LIGHTS_FULL_CONTEXT.md` | This document: comprehensive single-source-of-truth reference file stored inside the Flutter app project. |

---

## 2. Executive Summary & Conversation Timeline

### 2.1 Initial Requirements & Autonomous Hardware Control
The user requested an ESP32 firmware solution to drive addressable WS2812B RGB LEDs with 3 primary lighting modes:
1. **Mode 0**: Warm White (`RGB: 255, 147, 41`) across the full strip at 100% brightness.
2. **Mode 1**: Center 1.5 meters glowing Warm White at 100% brightness; outer ends completely OFF ($R=0, G=0, B=0$).
3. **Mode 2**: Pure White (`RGB: 255, 255, 255`) across the full strip at 100% brightness.
4. **Power-Cycle Cycling**: When power/battery is disconnected and reconnected, the system must automatically advance to the next mode in order ($0 \to 1 \to 2 \to 0$) and persist its state across reboots using Non-Volatile Storage (NVS).

### 2.2 BLE Communication & Feature Parity
The user requested to analyze the BLE architecture of `/Users/hrk/Documents/PlatformIO/Projects/esp_motor_toggle` and port its communication structure to the Temple Lights firmware:
- Peripheral advertised name: `"Temple Lights"`.
- BLE GATT service UUID: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`.
- Control/Status characteristic UUID: `a1b2c3d4-e5f6-7890-abcd-ef1234567891` (`READ | WRITE | WRITE_WITHOUT_RESPONSE | NOTIFY`).
- Controls: Continuous brightness dimming (0–100%), custom 24-bit RGB selection, power toggle (OFF), time synchronization, autonomous scheduling, auto-off timers, and persistent flash logs.

### 2.3 Companion Flutter App Creation
A companion Flutter mobile application was created at `/Users/hrk/StudioProjects/temple_lights_toggle`:
- Architecture: Flutter Riverpod, `flutter_reactive_ble`, SharedPreferences, HapticFeedback, and GoogleFonts.
- Features: Auto-connect BLE state machine, manual peripheral scanner, tactile porcelain dial, countdown auto-off timer, autonomous scheduler, flash activity logs, and settings sheet.

### 2.4 Serene Luxury Light UI Theme Transformation
The UI was transformed from an industrial dark theme to a bespoke **Serene Luxury Light UI Theme** tailored for temple ambiance:
- Palette: Warm Ivory Alabaster background (`0xFFF9F7F2`), Pure White surface cards (`0xFFFFFFFF`), micro-borders (`0xFFEAE4D6`), warm ambient gold shadows (`0xFF3B2E1E` @ 4% opacity), Sacred Saffron Amber (`0xFFD97706`), Deep Temple Gold (`0xFFB45309`), and Obsidian Slate typography (`0xFF1C1917`).
- Porcelain dial button with radiant golden halo, 36 concentric tick markers, and tactile tap feedback.
- 100% high-contrast readability across all components, Cupertino pickers, sliders, and modal sheets.

### 2.5 End-to-End Over-The-Air (OTA) Firmware Update Feature
The user requested: *"i want to add ota update feature, via fimware.bin file which will be installed inside the apk only, so make the changes end to end in the app as well as in the esp code, also make sure you add a progess animated page in the app to show update progress"*.
- **Firmware Changes**:
  - Partition table upgraded to `min_spiffs.csv` (dual ~1.9MB `ota_0` and `ota_1` partitions).
  - Added Arduino `<Update.h>` integration with partition verification and MD5 validation.
  - Added dedicated OTA data characteristic: `OTA_CHAR_UUID` = `a1b2c3d4-e5f6-7890-abcd-ef1234567892`.
  - Added commands: `ota_begin`, `ota_end`, and `ota_abort`.
  - Telemetry now advertises `"ver":"1.1.0"`. Background animations and scheduling are paused during flashing for maximum CPU priority.
- **Flutter App Changes**:
  - Packaged [`assets/firmware/firmware.bin`](file:///Users/hrk/StudioProjects/temple_lights_toggle/assets/firmware/firmware.bin) directly inside the APK assets.
  - Added `crypto: ^3.0.6` for binary MD5 hash calculation.
  - Added `OtaProgressState` and `OtaNotifier` (`otaProgressProvider`) managing handshake, flow-controlled 256-byte chunk streaming, integrity check, and reboot reconnection.
  - Designed [`OtaUpdateScreen`](file:///Users/hrk/StudioProjects/temple_lights_toggle/lib/features/ota/ota_update_screen.dart) with golden radial halo, circular progress ring, real-time speed (KB/s), ETA countdown, and 4-phase progression timeline.
  - Added "ESP32 Firmware OTA" card in Settings sheet.
  - Added 9 automated OTA unit/contract tests in `test/ota_contract_test.dart` (all 17/17 tests passing).

---

## 3. Hardware Architecture & Electrical Specifications

### 3.1 Bill of Materials & Pinout
| Component | Specification | Connection / Pin |
| :--- | :--- | :--- |
| **Microcontroller** | NodeMCU-32S (ESP32-WROOM-32, 4MB Flash) | Micro-USB / 5V DC Supply |
| **LED Strip** | WS2812B RGB Addressable Strip | 5V DC External Supply |
| **Length & Density** | 2.5m (150 LEDs) to 3.0m (180 LEDs) | Data In $\to$ ESP32 **GPIO 4** |
| **Current Consumption** | ~60mA per LED at full white (9.0A–10.8A max) | 5V 10A–12A DC Power Supply |
| **Common Ground** | Essential: GND of ESP32 connected to LED GND | Common Ground Plane |

### 3.2 Physical LED Index Mapping (150-LED Strip Configuration)
$$\text{Total LEDs} = 150\,\text{LEDs (indices } 0 \text{ to } 149\text{)}$$
$$\text{Middle 1.5m} = 90\,\text{LEDs (indices } 30 \text{ to } 119\text{)}$$
$$\text{Left Margin} = 30\,\text{LEDs (indices } 0 \text{ to } 29\text{)}$$
$$\text{Right Margin} = 30\,\text{LEDs (indices } 120 \text{ to } 149\text{)}$$

---

## 4. Lighting Modes & Autonomous Power-Cycle Boot Logic

### 4.1 Editable Default Boot Modes (Persisted in NVS `"tl_modes"`)
All 3 default boot modes are fully editable from the dedicated **Modes** tab, saved into the ESP32's NVS flash, and loaded on boot:

- **Mode 0 (Default: All Warm White)**:
  - Default Name: `"Warm White"`
  - Default Color: Warm White $\to$ $R=255, G=147, B=41$
  - Default Style: `0` (Full Strip, all $150$ LEDs)
  - Configurable Brightness: $1 \dots 255$ (Default: $255$ / 100%)
- **Mode 1 (Default: Center Warm White)**:
  - Default Name: `"Center Warm"`
  - Default Color: Warm White $\to$ $R=255, G=147, B=41$
  - Default Style: `1` (Center Focus 1.5m, middle $90$ LEDs $30 \le i \le 119$; outer $60$ LEDs turned **OFF**)
  - Configurable Brightness: $1 \dots 255$ (Default: $255$ / 100%)
- **Mode 2 (Default: All Pure White)**:
  - Default Name: `"Pure White"`
  - Default Color: Pure White $\to$ $R=255, G=255, B=255$
  - Default Style: `0` (Full Strip, all $150$ LEDs)
  - Configurable Brightness: $1 \dots 255$ (Default: $255$ / 100%)
- **Mode 3 (Custom RGB & App Live Color)**:
  - Color: Arbitrary user-defined 24-bit RGB $(R, G, B)$
  - Range: All LEDs (2.5m)
  - Brightness: Controllable 0–100% via BLE
- **Power State OFF (`is_on = false` or `brightness = 0`)**:
  - All LEDs cleared to black ($R=0, G=0, B=0$)
  - Preserves prior mode, brightness, & color in NVS for seamless re-powering.

### 4.2 Power-Cycle Boot Mode Advancing & Hardware Cycle Sync
To satisfy the battery/wall disconnect-and-reconnect cycle requirement:
1. At boot, the ESP32 loads `defaultModes[3]` from `"tl_modes"` and `currentMode` from `"tl"` in NVS:
   ```cpp
   uint8_t lastMode = currentMode;
   if (lastMode >= 2) {
       currentMode = 0;
   } else {
       currentMode = lastMode + 1;
   }
   brightness = (defaultModes[currentMode].brightness > 0) ? defaultModes[currentMode].brightness : 255;
   targetBrightness = brightness;
   activeBrightness = brightness;
   currentBrightness = (float)brightness;
   save_state();
   ```
2. Cycles deterministically: $0 \to 1 \to 2 \to 0$, automatically adopting the custom color, zone style, and brightness configured for that mode.
3. Hardware toggle `{"cmd":"next_mode"}` advances $(currentMode + 1) \bmod 3$ with smooth crossfade and brightness slew.
4. Requires zero Wi-Fi, Bluetooth, or cloud connection to operate autonomously.

---

## 5. ESP32 Firmware Deep Dive (`esp_rgb_strip_temple`)

Source: [`/Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/src/main.cpp`](file:///Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/src/main.cpp)  
Config: [`/Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/platformio.ini`](file:///Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/platformio.ini)

### 5.1 Architecture Highlights
- **Framework**: Arduino on Espressif32 (`NodeMCU-32S`).
- **BLE Stack**: `NimBLE-Arduino` v1.4.3 (low RAM, 512 MTU negotiation).
- **LED Driver**: `Adafruit NeoPixel` v1.10.7 configured for `NEO_GRB + NEO_KHZ800`.
- **NVS Namespaces**:
  - `"tl"`: Operational state (mode, brightness, custom RGB).
  - `"tl_modes"`: Editable 3 default boot modes (name, RGB, style, brightness).
  - `"tl_sched"`: Autonomous schedule entries (up to 16 schedules).
  - `"tl_logs"`: Circular buffer of device activity logs (up to 20 entries).

### 5.2 Multi-Task FreeRTOS & Main Loop Execution
1. **NimBLE Callbacks (`ServerCallbacks`, `CharacteristicCallbacks`, `OtaCharacteristicCallbacks`)**:
   - Manages connection/disconnection and resumes advertising.
   - Parses JSON commands and fast 2-byte binary packets (`[0x42, val]`).
   - Receives raw 256-byte firmware binary chunks on `OTA_CHAR_UUID` and writes them directly to flash via `Update.write()`.
2. **Main Loop `loop()` Execution Flow**:
   - **OTA Flash Protection Guard**: If `otaInProgress == true`, normal loop tasks (animations, schedules, timers) are bypassed to dedicate 100% CPU to flash write throughput. Aborts if chunk inactivity exceeds 30 seconds.
   - **50 FPS Smooth Premium Animation Engine**: Fully compliant with the 2.5m animation specification. Features dynamic center distance normalization for any LED count (even and odd), C2 Quintic Smootherstep easing (zero boundary jerk), 1000ms Center-Out ON light wave expansion, 1000ms Center-Out OFF collapsing dark wave, 1000ms seamless crossfades, smooth brightness tracking with no stepping, and a subtle 3000ms 6% organic breathing glow when idle.
   - **Autonomous Schedule Engine**: Evaluates every 1000ms against POSIX local time.
   - **Auto-Off Timer Engine**: Evaluates countdown every 500ms.
   - **Debounced NVS Writer**: Commits brightness/color changes to flash 1000ms after user stops adjusting sliders.

---

## 6. Dual-OTA Firmware Architecture & ESP32 Partition Table

To enable safe, atomic wireless firmware flashing, the ESP32 partition table was upgraded in [`platformio.ini`](file:///Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple/platformio.ini):

```ini
[env:nodemcu-32s]
platform = espressif32
board = nodemcu-32s
framework = arduino
board_build.partitions = min_spiffs.csv
monitor_speed = 115200
lib_deps = 
	adafruit/Adafruit NeoPixel@^1.10.7
	h2zero/NimBLE-Arduino@^1.4.1
```

### Partition Scheme Layout (`min_spiffs.csv` — 4MB Flash)
| Partition | Type | SubType | Flash Offset | Partition Size | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `nvs` | `data` | `nvs` | `0x009000` | `0x005000` (20 KB) | Non-Volatile Storage for settings, schedules, logs |
| `otadata` | `data` | `ota` | `0x00E000` | `0x002000` (8 KB) | Boot partition selector & rollback flags |
| **`app0`** | `app` | **`ota_0`** | `0x010000` | `0x1E0000` (~1.9 MB) | Primary OTA Application Slot |
| **`app1`** | `app` | **`ota_1`** | `0x1F0000` | `0x1E0000` (~1.9 MB) | Secondary OTA Application Slot |
| `spiffs` | `data` | `spiffs` | `0x3D0000` | `0x020000` (128 KB) | File storage |
| `coredump`| `data` | `coredump`| `0x3F0000` | `0x010000` (64 KB) | Crash diagnostic storage |

**Safety Guarantee**: The firmware is compiled to 642,161 bytes (~32.7% of the 1.9MB partition limit). The active running partition is never overwritten. If an update is interrupted, the ESP32 aborts and remains on its current valid firmware.

---

## 7. BLE Protocol, Wire Contract & Command Dictionary

### 7.1 GATT Service & Characteristic Specifications
- **Hardware Primary Service UUID**: `95d6fedc-cac3-48e2-8221-f534a2782704` (Hardware Aligned Primary & High-Speed OTA)
  - **Light Control Characteristic UUID**: `0ddad461-e5e3-457b-a173-da66bd52bf4d` (`READ | WRITE | WRITE_WITHOUT_RESPONSE | NOTIFY`)
  - **OTA Control Characteristic UUID**: `0ddad461-e5e3-457b-a173-da66bd52bf4e` (`WRITE | WRITE_WITHOUT_RESPONSE`)
  - **OTA Data Characteristic UUID**: `0ddad461-e5e3-457b-a173-da66bd52bf4f` (`WRITE_WITHOUT_RESPONSE`)
  - **OTA Status Characteristic UUID**: `0ddad461-e5e3-457b-a173-da66bd52bf50` (`READ | NOTIFY`)
- **Legacy Service UUID**: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
  - **Legacy Control**: `a1b2c3d4-e5f6-7890-abcd-ef1234567891`
  - **Legacy OTA Control**: `a1b2c3d4-e5f6-7890-abcd-ef1234567892`
  - **Legacy OTA Data**: `a1b2c3d4-e5f6-7890-abcd-ef1234567893`
  - **Legacy OTA Status**: `a1b2c3d4-e5f6-7890-abcd-ef1234567894`

### 7.2 Telemetry Notification Formats

#### 1. Fast Binary Telemetry (5 Bytes)
Pushed on rapid state changes:
$$\text{Byte 0: Mode} \quad (0, 1, 2, 3)$$
$$\text{Byte 1: Brightness} \quad (0 \text{ to } 255)$$
$$\text{Byte 2: Red} \quad (0 \text{ to } 255)$$
$$\text{Byte 3: Green} \quad (0 \text{ to } 255)$$
$$\text{Byte 4: Blue} \quad (0 \text{ to } 255)$$

#### 2. JSON State Telemetry
```json
{
  "type": "state",
  "mode": 0,
  "bright": 255,
  "r": 255,
  "g": 147,
  "b": 41,
  "ver": "1.1.0"
}
```

#### 3. OTA Status Telemetry
```json
{
  "type": "ota_ack",
  "status": "ready" | "progress" | "success" | "error" | "aborted",
  "msg": "ESP32 ready for firmware chunks",
  "bytes": 262144,
  "pct": 40
}
```

### 7.3 Command Dictionary

| Command | Payload Example | Action |
| :--- | :--- | :--- |
| **Set Mode** | `{"cmd":"set_mode","mode":1}` | Switches to requested mode, powers ON strip, notifies clients. |
| **Next Mode** | `{"cmd":"next_mode"}` | Advances $(mode + 1) \bmod 4$, powers ON strip, notifies clients. |
| **Fast Brightness** | `[0x42, val]` | Sub-millisecond instant LED brightness update. |
| **Set Brightness** | `{"cmd":"set_bright","val":180}` | Scales NeoPixel strip brightness (0–255). |
| **Set Custom RGB** | `{"cmd":"set_rgb","r":255,"g":180,"b":0}` | Sets RGB color, switches mode to 3, renders strip. |
| **Power OFF** | `{"cmd":"off"}` | Center-off bloom animation, turns off strip, records OFF log. |
| **Query State** | `{"cmd":"get_state"}` | Pushes current state telemetry including `"ver":"1.1.0"`. |
| **Time Sync** | `{"cmd":"time","epoch":1726915000}` | Synchronizes ESP32 POSIX clock using `settimeofday()`. |
| **Start Timer** | `{"cmd":"timer","sec":1800}` | Starts countdown auto-off timer. |
| **Cancel Timer** | `{"cmd":"timer_cancel"}` | Cancels running timer. |
| **Save Schedule** | `{"cmd":"save_sched", ...}` | Saves autonomous schedule entry into NVS. |
| **Toggle Sched** | `{"cmd":"toggle_sched","id":"sc1","en":false}`| Toggles schedule active state in NVS. |
| **Delete Sched** | `{"cmd":"del_sched","id":"sc1"}` | Deletes schedule from NVS. |
| **Get Schedules**| `{"cmd":"get_scheds"}` | Hydrates app with all saved schedules. |
| **Get Modes**    | `{"cmd":"get_modes"}` | Hydrates app with 3 default modes (`mode_cfg` + `modes_end`). |
| **Save Mode**    | `{"cmd":"save_mode","idx":0,...}` | Commits customized mode (name, RGB, style, brightness) to `"tl_modes"`. |
| **Reset Modes**  | `{"cmd":"reset_modes"}` | Restores factory default modes in NVS and updates LEDs. |
| **Get Logs**     | `{"cmd":"get_logs"}` | Hydrates app with stored activity logs. |
| **Clear Logs**   | `{"cmd":"clear_logs"}` | Clears all activity logs in NVS. |
| **OTA Begin**    | `{"cmd":"ota_begin","size":642161,"md5":"..."}` | Initializes flash partition, sets MD5, prepares ESP32. |
| **OTA Chunk**    | Binary byte array (256B) on `OTA_CHAR_UUID` | Streams raw firmware chunks via `Update.write()`. |
| **OTA End**      | `{"cmd":"ota_end"}` | Verifies checksum, marks partition bootable, reboots ESP32. |
| **OTA Abort**    | `{"cmd":"ota_abort"}` | Cancels update, rolls back flash, leaves current partition intact. |

---

## 8. Companion Flutter Mobile Application (`temple_lights_toggle`)

Source: [`/Users/hrk/StudioProjects/temple_lights_toggle`](file:///Users/hrk/StudioProjects/temple_lights_toggle)

### 8.1 Directory Structure
```
lib/
├── app.dart                                # MaterialApp entrypoint & theme binding
├── main.dart                               # Root main(), system UI overlay styling
├── contract/
│   └── light_contract.dart                 # BLE UUIDs & packet encoders (Lighting + OTA)
├── transport/
│   ├── ble_client.dart                     # Reactive BLE client & state machine
│   └── scanner.dart                        # RSSI-sorted BLE peripheral scanner
├── domain/
│   ├── models.dart                         # Immutable models (LightState, OtaProgressState, etc.)
│   └── providers.dart                      # Riverpod state providers (Session, Lights, Sched, OTA)
├── core/
│   ├── haptics.dart                        # Rich tactile haptic engine
│   ├── kv_store.dart                       # SharedPreferences local cache
│   ├── log.dart                            # In-memory ring buffer logging
│   └── permissions.dart                    # Cross-platform Bluetooth permission handler
├── ui/
│   ├── theme.dart                          # Serene Luxury Light UI theme definition
│   ├── motion.dart                         # Smooth route transition animations
│   └── widgets/
│       ├── auto_off_timer_widget.dart      # Auto-off timer controller with Cupertino wheel
│       ├── connection_card.dart            # Live BLE telemetry card
│       ├── light_dial_button.dart          # Porcelain radiant dial button
│       ├── radar_sweep.dart                # Animated scanner radar
│       ├── signal_bars.dart                # 4-bar RSSI signal meter
│       └── status_pill.dart                # Compact status indicators
└── features/
    ├── home/
    │   └── lights_screen.dart              # Main lighting control dashboard
    ├── modes/
    │   └── modes_screen.dart               # Dedicated 3 Default Boot Modes editor & visualizer
    ├── ota/
    │   └── ota_update_screen.dart          # Animated Serene Luxury Light OTA update screen
    ├── schedule/
    │   ├── schedule_screen.dart            # Autonomous schedule manager (with Mode/RGB/Bright)
    │   └── schedule_editor_sheet.dart      # Schedule creation/editing modal
    ├── logs/
    │   └── logs_screen.dart                # Flash activity logs inspector
    ├── scanner/
    │   └── device_sheet.dart               # BLE discovery & connection modal
    ├── settings/
    │   └── settings_sheet.dart             # Settings, OTA updater tile & UUID overrides
    └── shell/
        └── main_nav_shell.dart             # 4-tab persistent navigation shell (Lights, Modes, Sched, Logs)
```

---

## 9. Serene Luxury Light UI Theme System

### 9.1 Design Tokens (`lib/ui/theme.dart`)
```dart
class AppTheme {
  // Surfaces & Backgrounds
  static const Color background    = Color(0xFFF9F7F2); // Warm Ivory Alabaster
  static const Color surface       = Color(0xFFFFFFFF); // Pure Crisp White
  static const Color surfaceRaised = Color(0xFFF4F0E8); // Warm Sand Tint
  static const Color surfaceGlow   = Color(0xFFFFF8E7); // Candlelight Glow Tint

  // Micro-Borders & Dividers
  static const Color border        = Color(0xFFEAE4D6); // Warm Alabaster Border
  static const Color borderBright  = Color(0xFFD9D0BE); // Defined Card Border

  // Sacred Color Accents
  static const Color amber         = Color(0xFFD97706); // Sacred Saffron Amber
  static const Color gold          = Color(0xFFB45309); // Deep Temple Gold
  static const Color warmGold      = Color(0xFFF59E0B); // Radiant Gold
  static const Color warmWhite     = Color(0xFFFFF3D6); // Warm Candlelight White
  static const Color pureWhite     = Color(0xFFFFFFFF); // Pure Pristine White

  // Status & Utility Accents
  static const Color green         = Color(0xFF059669); // Forest Emerald (Active)
  static const Color red           = Color(0xFFDC2626); // Crimson Red (Error/Off)
  static const Color orange        = Color(0xFFEA580C); // Deep Orange

  // High-Contrast Typography
  static const Color textPrimary   = Color(0xFF1C1917); // Obsidian Slate (87% contrast)
  static const Color textSecondary = Color(0xFF78716C); // Warm Medium Gray
  static const Color textMuted     = Color(0xFFA8A29E); // Soft Stone Gray
}
```

---

## 10. End-to-End BLE Over-The-Air (OTA) Update System

### 10.1 APK Bundled Asset Pipeline
- PlatformIO compiles the ESP32 binary to `.pio/build/nodemcu-32s/firmware.bin` (642 KB).
- The binary is packaged into [`assets/firmware/firmware.bin`](file:///Users/hrk/StudioProjects/temple_lights_toggle/assets/firmware/firmware.bin).
- Configured in `pubspec.yaml`:
  ```yaml
  flutter:
    uses-material-design: true
    assets:
      - assets/icons/
      - assets/firmware/
  ```
- Bundled into the final APK under `assets/flutter_assets/assets/firmware/firmware.bin`.

### 10.2 State Machine Flow (`OtaNotifier`)
```
[IDLE] 
  │ User taps "Start Firmware Update"
  ▼
[LOADING_ASSET] 
  │ Loads bundled firmware.bin via rootBundle
  │ Computes MD5 checksum & total byte size
  ▼
[PREPARING] 
  │ Dispatches: {"cmd":"ota_begin","size":642161,"md5":"..."}
  │ ESP32 prepares flash partition & turns OFF LEDs
  │ Awaits: {"type":"ota_ack","status":"ready"}
  ▼
[TRANSFERRING] 
  │ Streams 256-byte chunks to OTA_CHAR_UUID with writeWithResponse
  │ Computes live Speed (KB/s), ETA (seconds), and Progress (%)
  │ Repeats until bytesWritten == totalBytes
  ▼
[VERIFYING] 
  │ Dispatches: {"cmd":"ota_end"}
  │ ESP32 validates flash checksum & marks partition bootable
  │ Awaits: {"type":"ota_ack","status":"success"}
  ▼
[REBOOTING] 
  │ ESP32 restarts automatically via ESP.restart()
  │ Phone plays power-up haptic and waits for reboot
  ▼
[COMPLETED]
  │ Status turns green; user taps "Return to Lights"
```

### 10.3 Animated OTA Update Screen Features
1. **Pulsing Radiant Halo**: Animated ambient gold aura with smooth sinusoidal intensity modulation.
2. **Circular Progress Ring**: Clean high-contrast ring tracking exact percentage completion.
3. **Performance Metrics Card**: Live readout of Transferred data (`KB / KB`), Speed (`KB/s`), and Time Remaining (`ETA`).
4. **4-Stage Progression Timeline**:
   - `Package & Handshake`
   - `Flash Transmission`
   - `Integrity Check`
   - `Device Reboot`
5. **Safety Guard & Dialogs**: Clear warning notice to keep phone nearby, with safe cancellation modal.

---

## 11. Autonomous Edge Subsystems (RTC, Schedules, Timers, Logs)

1. **POSIX RTC Synchronization**: Phone syncs local epoch upon connection; ESP32 maintains accurate local time via internal RTC.
2. **Autonomous Schedule Engine**: Stores up to 16 schedules in NVS namespace `"tl_sched"`. Evaluates hour, minute, and weekday bitmask every 1 second to trigger ON/OFF autonomously with custom mode (0–3), custom RGB color (`tgt_r`, `tgt_g`, `tgt_b`), and target brightness (1–255).
3. **Countdown Auto-Off Timer**: Counts down locally in flash RAM and shuts down lights when reaching zero with source `"timer"`.
4. **Circular Flash Activity Logs**: Stores the last 20 events in NVS namespace `"tl_logs"` recording timestamp, action (`ON`, `OFF`, `MODE_CHG`), source (`ble`, `sched`, `timer`, `boot`), and runtime duration.

---

## 12. Verification, Static Analysis & Build Results

### 12.1 PlatformIO Firmware Build
```bash
cd /Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple && pio run
```
* **Status**: **SUCCESS** (3.10s)
* **Flash Usage**: 32.7% (642,161 bytes used from 1,966,080 bytes under `min_spiffs.csv`)
* **RAM Usage**: 12.4% (40,544 bytes used from 327,680 bytes)

### 12.2 Flutter Static Analysis
```bash
cd /Users/hrk/StudioProjects/temple_lights_toggle && flutter analyze
```
* **Status**: **No issues found!** (0 errors, 0 warnings, 0 lints)

### 12.3 Flutter Automated Test Suite
```bash
cd /Users/hrk/StudioProjects/temple_lights_toggle && flutter test
```
* **Status**: **All 17 tests passed!**
  * LightBleUuids target detection & OTA UUID verification
  * All light control command encoders (`set_mode`, `set_bright`, `fast_bright`, `set_rgb`, `off`, `timer`, etc.)
  * OTA command encoders (`ota_begin`, `ota_end`, `ota_abort`)
  * OtaProgressState calculations (progress fraction, speed, ETA, formatting, phase flags)
  * LightSchedule evaluation & persistence roundtrip serialization
  * LightLogEntry parsing & telemetry decoding
  * AutoOffTimerState calculation logic
  * LightState power and human-readable mode names

### 12.4 Android Debug APK Compilation
```bash
cd /Users/hrk/StudioProjects/temple_lights_toggle && flutter build apk --debug
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep firmware.bin
```
* **Status**: **SUCCESS** (6.6s build)
* **Verified Asset in APK**: `648672 bytes -> assets/flutter_assets/assets/firmware/firmware.bin`

---

## 13. Deployment, Flashing & Operation Guide

### 13.1 Initial USB Flash (Dual-OTA Partition Setup)
> [!IMPORTANT]
> Because `platformio.ini` updates the partition table to `min_spiffs.csv`, the ESP32 must be flashed once via USB cable so PlatformIO can write the new partition table:
```bash
cd /Users/hrk/Documents/PlatformIO/Projects/esp_rgb_strip_temple
pio run --target upload
```

### 13.2 Subsequent Wireless OTA Updates
1. When newer firmware is compiled, copy `.pio/build/nodemcu-32s/firmware.bin` into `assets/firmware/firmware.bin` in the Flutter project.
2. Build or run the Flutter application:
   ```bash
   cd /Users/hrk/StudioProjects/temple_lights_toggle
   flutter run
   ```
3. In the app:
   - Connect to **Temple Lights**.
   - Open **Settings** (gear icon on top right).
   - Tap **Open Firmware Updater** on the ESP32 Firmware OTA card.
   - Tap **Start Firmware Update**.
   - Watch the animated progress ring stream chunks, verify checksum, and reboot the device automatically!

---
*Comprehensive reference document compiled for the Temple Lights project.*
