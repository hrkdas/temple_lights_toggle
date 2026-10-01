#pragma once

#include <Arduino.h>
#include <NimBLEDevice.h>

// ============================================================================
// TEMPLE LIGHTS: WIFI PROVISIONING & AUTONOMOUS NTP CLOCK SYNCHRONIZER
// ============================================================================

enum WifiState : uint8_t {
    TL_WIFI_STATE_IDLE = 0,
    TL_WIFI_STATE_SCANNING = 1,
    TL_WIFI_STATE_CONNECTING = 2,
    TL_WIFI_STATE_GOT_IP = 3,
    TL_WIFI_STATE_INTERNET_OK = 4,
    TL_WIFI_STATE_SAVED = 5,
    TL_WIFI_STATE_CONNECTED = 6,
    TL_WIFI_STATE_FAILED = 7,
    TL_WIFI_STATE_DISCONNECTED = 8
};

enum WifiReason : uint8_t {
    TL_WIFI_REASON_NONE = 0,
    TL_WIFI_REASON_AUTH = 1,
    TL_WIFI_REASON_NO_AP = 2,
    TL_WIFI_REASON_TIMEOUT = 3,
    TL_WIFI_REASON_NO_INTERNET = 4,
    TL_WIFI_REASON_NVS = 5,
    TL_WIFI_REASON_BUSY = 6
};

// Lifecycle & Loop Hooks
void wifiManagerInit(NimBLECharacteristic* pNotifyChar);
void wifiManagerTick(unsigned long nowMs);

// BLE Command Operations
void wifiManagerStartScan();
void wifiManagerConnect(const String& ssid, const String& psk, bool saveOnSuccess);
void wifiManagerForget();
void wifiManagerQueryStatus();
void wifiManagerTriggerNtp();
void wifiManagerSetTimezoneOffset(int16_t tzOffsetMin);
int16_t wifiManagerGetTimezoneOffset();
void wifiManagerApplyTimezone(int16_t tzOffsetMin);

// Status Queries
bool wifiManagerIsConnected();
bool wifiManagerIsInternetOk();
WifiState wifiManagerGetState();
String wifiManagerGetSsid();
String wifiManagerGetIp();
int8_t wifiManagerGetRssi();

// OTA Gating
void wifiManagerPauseForOta();
void wifiManagerResumeAfterOta();
