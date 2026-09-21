# Temple Lights Toggle

A unified repository containing both the **Flutter Companion Mobile App** and the **ESP32 BLE Firmware** for the autonomous WS2812B RGB Temple Light Controller.

---

## Repository Structure

```text
temple_lights_toggle/
├── android/, ios/, macos/, ...   # Flutter platform runner projects
├── assets/
│   ├── firmware/                 # Bundled OTA firmware.bin installed with APK
│   └── icons/                    # App SVGs and vector assets
├── firmware/                     # ESP32 PlatformIO project
│   ├── include/                  # C++ headers
│   ├── lib/                      # PlatformIO libraries
│   ├── src/
│   │   └── main.cpp              # ESP32 BLE, WS2812B driver, NVS, & OTA engine
│   ├── test/                     # PlatformIO unit tests
│   ├── partitions_ota.csv        # Dual-OTA (app0/app1) flash partition table
│   └── platformio.ini            # PlatformIO environment & board configuration
├── lib/                          # Flutter Dart source code (Riverpod, BLE transport, UI)
├── test/                         # Flutter unit and contract tests
├── pubspec.yaml                  # Flutter package & asset configuration
└── TEMPLE_LIGHTS_FULL_CONTEXT.md # Comprehensive architectural reference
```

---

## 1. Flutter Companion Mobile App

### Features
- **Auto-Connect**: Scans for `"Temple Lights"` BLE peripheral and reconnects automatically.
- **Lighting Controls**: Quick toggle, mode switching (Warm White, Center Glow, Pure White), RGB color picker, and brightness slider.
- **Autonomous Schedules**: Configure up to 16 schedules stored directly in ESP32 NVS.
- **Flash Activity Logs**: Read and sync the last 20 events recorded on device flash.
- **In-App BLE OTA Firmware Updater**: Flash the ESP32 wirelessly over BLE from the APK with real-time transfer progress, speed, and status animations.

### Getting Started
```bash
# Get Flutter dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK (bundles assets/firmware/firmware.bin)
flutter build apk --release
```

---

## 2. ESP32 Firmware (`firmware/`)

### Specifications
- **Microcontroller**: NodeMCU-32S (ESP32-WROOM-32, 4MB Flash)
- **LED Type**: WS2812B Addressable RGB LED Strip (GPIO 4)
- **Flash Partitioning**: `partitions_ota.csv` with dual 1.9MB app partitions (`app0` / `app1`) for atomic fail-safe OTA updates.
- **BLE Service UUID**: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- **Control Characteristic UUID**: `a1b2c3d4-e5f6-7890-abcd-ef1234567891`
- **OTA Data Characteristic UUID**: `a1b2c3d4-e5f6-7890-abcd-ef1234567892`

### Building & Flashing
```bash
cd firmware

# Compile firmware
pio run

# First-time flash via USB (writes partition table and initial image)
pio run --target upload

# Copy compiled binary to Flutter assets for OTA bundling
cp .pio/build/nodemcu-32s/firmware.bin ../assets/firmware/firmware.bin
```

---

## License
Private repository — All rights reserved.
