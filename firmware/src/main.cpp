#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
#include <Update.h>
#include <sys/time.h>
#include <time.h>
#include <esp_bt.h>
#include <esp_ota_ops.h>

// ============================================================================
// HARDWARE & ANIMATION CONFIG
// ============================================================================
#define LED_PIN                   4
#define NUM_LEDS                  150   // 2.5m × 60 LEDs/m

#define ANIM_ON_DURATION_MS       1000   // Center-out ON total duration
#define ANIM_ON_PROP_MS            650   // Propagation time from center to ends
#define ANIM_ON_FADE_MS            350   // Per-LED fade rise time

#define ANIM_OFF_DURATION_MS      1000   // Center-out OFF total duration
#define ANIM_OFF_PROP_MS           650   // Propagation time from center to ends
#define ANIM_OFF_FADE_MS           350   // Per-LED fade fall time

#define ANIM_CROSSFADE_MS         1000   // Smooth mode / color transition total duration
#define ANIM_CROSSFADE_PROP_MS     650   // Center-out wave propagation for mode switch
#define ANIM_CROSSFADE_FADE_MS     350   // Per-LED smootherstep blend duration
#define ANIM_BREATHING_PERIOD_MS  3000   // Gentle idle breathing cycle
#define ANIM_BREATHING_DEPTH      0.06f  // 6% subtle breathing depth (0.94 - 1.00)
#define ANIM_FRAME_MS               20   // ~50 FPS target frame timing

#define MAX_SCHEDULES             16
#define MAX_LOGS                  20

// ============================================================================
// BLE & FIRMWARE CONFIG
// ============================================================================
#define FIRMWARE_VERSION    "1.2.0"
#define DEVICE_NAME         "Temple Lights"
#define SERVICE_UUID        "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
#define CHARACTERISTIC_UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567891"

// Boturo Go High-Speed BLE OTA Protocol
#define OTA_SERVICE_UUID    "f71a0001-2c98-4a7b-a7f9-5e8fbc2d0100"
#define OTA_CONTROL_UUID    "f71a0002-2c98-4a7b-a7f9-5e8fbc2d0100"
#define OTA_DATA_UUID       "f71a0003-2c98-4a7b-a7f9-5e8fbc2d0100"
#define OTA_STATUS_UUID     "f71a0004-2c98-4a7b-a7f9-5e8fbc2d0100"

static const uint8_t OTA_OP_START = 0x01;
static const uint8_t OTA_OP_END   = 0x02;

static const uint8_t OTA_ST_START_OK = 0x10;
static const uint8_t OTA_ST_ACK      = 0x11;
static const uint8_t OTA_ST_DONE     = 0x12;
static const uint8_t OTA_ST_ERROR    = 0x13;

static const uint32_t OTA_ACK_WINDOW_PACKETS = 16;
static const size_t   OTA_WRITE_BUFFER_BYTES = 8192;

static const uint8_t OTA_ERR_BAD_START   = 0x01;
static const uint8_t OTA_ERR_BEGIN_FAIL  = 0x02;
static const uint8_t OTA_ERR_NOT_ACTIVE  = 0x03;
static const uint8_t OTA_ERR_END_FAIL    = 0x04;
static const uint8_t OTA_ERR_SHORT_FRAME = 0x05;
static const uint8_t OTA_ERR_ORDER       = 0x06;
static const uint8_t OTA_ERR_WRITE_FAIL  = 0x07;
static const uint8_t OTA_ERR_TIMEOUT     = 0x08;

// ============================================================================
// STRUCTS (SCHEDULE & LOG)
// ============================================================================
struct ScheduleItem {
    char id[36];
    char name[36];
    bool isEnabled;
    bool hasTurnOn;
    uint8_t turnOnHour;
    uint8_t turnOnMinute;
    bool hasTurnOff;
    uint8_t turnOffHour;
    uint8_t turnOffMinute;
    uint8_t repeatDaysMask; // Bit 1=Mon, Bit 2=Tue, ..., Bit 7=Sun
    uint8_t targetMode;     // Mode to activate (0..3)
    uint8_t targetBrightness;
    uint8_t targetR;
    uint8_t targetG;
    uint8_t targetB;
    char lastTriggeredKey[24];
};

struct LightLogItem {
    uint32_t id;
    bool isOn;
    uint8_t mode;
    uint8_t brightness;
    uint32_t epoch;
    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    uint32_t durationSec;
    char source[24];
};

// ============================================================================
// STATE & ANIMATION BUFFERS (persisted in NVS)
// ============================================================================
struct RgbColor {
    uint8_t r, g, b;
};

enum AnimType {
    ANIM_NONE = 0,
    ANIM_CENTER_ON,
    ANIM_CENTER_OFF,
    ANIM_CROSSFADE
};

static uint8_t currentMode = 0;       // 0=warm all, 1=warm middle, 2=white all, 3=custom RGB
static uint8_t brightness  = 255;     // Target user brightness (0–255)
static uint8_t customR = 255, customG = 147, customB = 41;
static uint8_t activeBrightness = 255; // Preserved brightness for ON transitions

static float currentBrightness = 255.0f; // Slew-interpolated brightness for hardware output
static uint8_t targetBrightness = 255;

static RgbColor currentLeds[NUM_LEDS];
static RgbColor startLeds[NUM_LEDS];
static RgbColor targetLeds[NUM_LEDS];
static RgbColor renderedLeds[NUM_LEDS];

static AnimType currentAnim = ANIM_NONE;
static unsigned long animStartMs = 0;
static unsigned long animDurationMs = 0;
static unsigned long lastAnimFrameMs = 0;
static unsigned long breathingBaseMs = 0;

static Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);
static Preferences prefs;

// BLE runtime
static bool deviceConnected = false;
static uint16_t activeConnHandle = 0;
static bool hasActiveConn = false;
static NimBLEServer* pBleServer = nullptr;
static NimBLECharacteristic* pCharacteristic = nullptr;
static NimBLECharacteristic* pOtaControlChar = nullptr;
static NimBLECharacteristic* pOtaDataChar = nullptr;
static NimBLECharacteristic* pOtaStatusChar = nullptr;

// Boturo Go High-Speed OTA Runtime
static bool otaInProgress = false;
static uint32_t otaExpectedFirmwareSize = 0;
static uint32_t otaWrittenBytes = 0;
static uint32_t otaExpectedChunkIndex = 0;
static unsigned long otaLastPacketMs = 0;
static uint8_t otaWriteBuffer[OTA_WRITE_BUFFER_BYTES];
static size_t otaWriteBufferLen = 0;
static const esp_partition_t* otaTargetPartition = nullptr;

// Non-blocking OTA frame queue (decouples BLE ISR from flash writes)
static const uint16_t OTA_RX_MAX_FRAME_SIZE = 540;
static const uint8_t OTA_RX_QUEUE_CAPACITY = 32;
static const uint8_t OTA_RX_KIND_CONTROL = 1;
static const uint8_t OTA_RX_KIND_DATA = 2;

struct OtaRxFrame {
    uint8_t kind;
    uint16_t len;
    uint8_t raw[OTA_RX_MAX_FRAME_SIZE];
};

static OtaRxFrame sOtaRxQueue[OTA_RX_QUEUE_CAPACITY];
static volatile uint8_t sOtaRxHead = 0;
static volatile uint8_t sOtaRxTail = 0;
static portMUX_TYPE sOtaRxMux = portMUX_INITIALIZER_UNLOCKED;

// Time & Scheduler runtime
static bool timeIsSynchronized = false;
static ScheduleItem schedules[MAX_SCHEDULES];
static int scheduleCount = 0;

static LightLogItem lightLogs[MAX_LOGS];
static int lightLogCount = 0;
static uint32_t nextLogId = 1;
static unsigned long lastTurnOnEpoch = 0;

// Autonomous Countdown Timer
static bool autoOffTimerActive = false;
static unsigned long autoOffTimerStartMs = 0;
static int autoOffTimerDurationSec = 0;

// Loop evaluation timers
static unsigned long lastScheduleEvalMs = 0;
static unsigned long lastTimerTickMs = 0;

// Debounced NVS write for live brightness/color adjustments
static bool stateDirty = false;
static unsigned long lastStateChangeMs = 0;
static bool logsDirty = false;
static unsigned long lastLogsChangeMs = 0;

// Preset colors
static const uint8_t WARM_R = 255, WARM_G = 147, WARM_B = 41;
static const uint8_t WHITE_R = 255, WHITE_G = 255, WHITE_B = 255;

// Forward declarations
float get_normalized_center_dist(int i, int totalLeds = NUM_LEDS);
float ease_smootherstep(float t);
float get_breathing_factor(unsigned long now);
void compute_target_colors(uint8_t mode, uint8_t r, uint8_t g, uint8_t b, RgbColor* out);
void render_frame(unsigned long now);
void start_center_on_animation();
void start_center_off_animation();
void start_crossfade_animation();
void update_animation(unsigned long now);
void notify_state();
void record_light_log(bool isOn, const char* source = "BLE App");
void save_schedules_to_nvs();
void load_schedules_from_nvs();
void save_logs_to_nvs();
void load_logs_from_nvs();
void send_schedule_hydration_to_app();
void send_logs_hydration_to_app();

// ============================================================================
// NVS PERSISTENCE FOR STATE
// ============================================================================
void save_state() {
    prefs.begin("tl", false);
    prefs.putUChar("mode", currentMode);
    prefs.putUChar("bright", brightness);
    prefs.putUChar("r", customR);
    prefs.putUChar("g", customG);
    prefs.putUChar("b", customB);
    prefs.end();
}

void load_state() {
    prefs.begin("tl", true);
    currentMode = prefs.getUChar("mode", 0);
    brightness  = prefs.getUChar("bright", 255);
    customR     = prefs.getUChar("r", 255);
    customG     = prefs.getUChar("g", 147);
    customB     = prefs.getUChar("b", 41);
    prefs.end();
    if (currentMode > 3) currentMode = 0;
    targetBrightness = brightness;
    activeBrightness = (brightness > 0) ? brightness : 255;
    currentBrightness = (float)brightness;
}

// ============================================================================
// NVS PERSISTENCE FOR SCHEDULES & LOGS
// ============================================================================
void load_schedules_from_nvs() {
    prefs.begin("tl_sched", false);
    scheduleCount = prefs.getInt("count", 0);
    if (scheduleCount < 0) scheduleCount = 0;
    if (scheduleCount > MAX_SCHEDULES) scheduleCount = MAX_SCHEDULES;

    for (int i = 0; i < scheduleCount; i++) {
        String key = "s_" + String(i);
        prefs.getBytes(key.c_str(), &schedules[i], sizeof(ScheduleItem));
    }
    prefs.end();
    Serial.printf("[NVS] Loaded %d schedules\n", scheduleCount);
}

void save_schedules_to_nvs() {
    prefs.begin("tl_sched", false);
    prefs.putInt("count", scheduleCount);

    for (int i = 0; i < scheduleCount; i++) {
        String key = "s_" + String(i);
        prefs.putBytes(key.c_str(), &schedules[i], sizeof(ScheduleItem));
    }
    for (int i = scheduleCount; i < MAX_SCHEDULES; i++) {
        String key = "s_" + String(i);
        if (prefs.isKey(key.c_str())) {
            prefs.remove(key.c_str());
        }
    }
    prefs.end();
    Serial.printf("[NVS] Saved %d schedules\n", scheduleCount);
}

void load_logs_from_nvs() {
    prefs.begin("tl_logs", false);
    lightLogCount = prefs.getInt("count", 0);
    if (lightLogCount < 0) lightLogCount = 0;
    if (lightLogCount > MAX_LOGS) lightLogCount = MAX_LOGS;
    nextLogId = prefs.getUInt("next_id", 1);
    lastTurnOnEpoch = prefs.getULong("last_on", 0);

    for (int i = 0; i < lightLogCount; i++) {
        String key = "l_" + String(i);
        prefs.getBytes(key.c_str(), &lightLogs[i], sizeof(LightLogItem));
    }
    prefs.end();
    Serial.printf("[NVS] Loaded %d logs\n", lightLogCount);
}

void save_logs_to_nvs() {
    prefs.begin("tl_logs", false);
    prefs.putInt("count", lightLogCount);
    prefs.putUInt("next_id", nextLogId);
    prefs.putULong("last_on", lastTurnOnEpoch);

    for (int i = 0; i < lightLogCount; i++) {
        String key = "l_" + String(i);
        prefs.putBytes(key.c_str(), &lightLogs[i], sizeof(LightLogItem));
    }
    for (int i = lightLogCount; i < MAX_LOGS; i++) {
        String key = "l_" + String(i);
        if (prefs.isKey(key.c_str())) {
            prefs.remove(key.c_str());
        }
    }
    prefs.end();
}

void record_light_log(bool isOn, const char* source) {
    time_t now = time(NULL);
    struct tm tmInfo;
    localtime_r(&now, &tmInfo);

    uint32_t durationSec = 0;
    if (isOn) {
        lastTurnOnEpoch = (uint32_t)now;
    } else {
        if (lastTurnOnEpoch > 0 && (uint32_t)now >= lastTurnOnEpoch) {
            durationSec = (uint32_t)now - lastTurnOnEpoch;
        }
        lastTurnOnEpoch = 0;
    }

    LightLogItem item;
    memset(&item, 0, sizeof(item));
    item.id = nextLogId++;
    item.isOn = isOn;
    item.mode = currentMode;
    item.brightness = brightness;
    item.epoch = (uint32_t)now;
    item.year = tmInfo.tm_year + 1900;
    item.month = tmInfo.tm_mon + 1;
    item.day = tmInfo.tm_mday;
    item.hour = tmInfo.tm_hour;
    item.minute = tmInfo.tm_min;
    item.second = tmInfo.tm_sec;
    item.durationSec = durationSec;
    strncpy(item.source, source, sizeof(item.source) - 1);

    // Rolling ring buffer: newest first at index 0
    if (lightLogCount < MAX_LOGS) {
        for (int i = lightLogCount; i > 0; i--) {
            lightLogs[i] = lightLogs[i - 1];
        }
        lightLogs[0] = item;
        lightLogCount++;
    } else {
        for (int i = MAX_LOGS - 1; i > 0; i--) {
            lightLogs[i] = lightLogs[i - 1];
        }
        lightLogs[0] = item;
    }

    // Debounce NVS flash writing so log persistence never stalls live animations
    logsDirty = true;
    lastLogsChangeMs = millis();

    // Push live log event to connected app
    if (deviceConnected && pCharacteristic != nullptr) {
        String logPkt = "{\"type\":\"log\",\"id\":\"" + String(item.id) +
                        "\",\"on\":" + String(item.isOn ? "true" : "false") +
                        ",\"mode\":" + String(item.mode) +
                        ",\"bright\":" + String(item.brightness) +
                        ",\"epoch\":" + String(item.epoch) +
                        ",\"y\":" + String(item.year) +
                        ",\"mon\":" + String(item.month) +
                        ",\"d\":" + String(item.day) +
                        ",\"h\":" + String(item.hour) +
                        ",\"m\":" + String(item.minute) +
                        ",\"s\":" + String(item.second) +
                        ",\"dur\":" + String(item.durationSec) +
                        ",\"src\":\"" + String(item.source) + "\"}";
        pCharacteristic->setValue((uint8_t*)logPkt.c_str(), logPkt.length());
        pCharacteristic->notify();
    }
}

// ============================================================================
// LED CONTROL & ANIMATION ENGINE
// ============================================================================
float get_normalized_center_dist(int i, int totalLeds) {
    if (totalLeds <= 1) return 0.0f;
    float center = (totalLeds - 1) * 0.5f;
    if (totalLeds % 2 == 0) {
        float rawDist = fabsf((float)i - center);
        float d = (rawDist >= 0.5f) ? (rawDist - 0.5f) : 0.0f;
        float maxD = center - 0.5f;
        return (maxD > 0.0f) ? (d / maxD) : 0.0f;
    } else {
        float maxDist = center;
        return (maxDist > 0.0f) ? (fabsf((float)i - center) / maxDist) : 0.0f;
    }
}

float ease_smootherstep(float t) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

float get_breathing_factor(unsigned long now) {
    unsigned long elapsed = now - breathingBaseMs;
    float phase = (float)(elapsed % ANIM_BREATHING_PERIOD_MS) * (2.0f * 3.14159265f / (float)ANIM_BREATHING_PERIOD_MS);
    return 1.0f - (ANIM_BREATHING_DEPTH * 0.5f * (1.0f - cosf(phase)));
}

void compute_target_colors(uint8_t mode, uint8_t r, uint8_t g, uint8_t b, RgbColor* out) {
    int midStart = (int)((NUM_LEDS * 0.20f) + 0.5f);
    int midEnd   = NUM_LEDS - 1 - midStart;

    switch (mode) {
        case 0:  // Mode 0: all warm white (2.5m)
            for (int i = 0; i < NUM_LEDS; i++)
                out[i] = { WARM_R, WARM_G, WARM_B };
            break;

        case 1:  // Mode 1: middle 1.5m warm white, rest off
            for (int i = 0; i < NUM_LEDS; i++) {
                if (i >= midStart && i <= midEnd)
                    out[i] = { WARM_R, WARM_G, WARM_B };
                else
                    out[i] = { 0, 0, 0 };
            }
            break;

        case 2:  // Mode 2: all pure white (2.5m)
            for (int i = 0; i < NUM_LEDS; i++)
                out[i] = { WHITE_R, WHITE_G, WHITE_B };
            break;

        case 3:  // Mode 3: custom RGB (2.5m)
            for (int i = 0; i < NUM_LEDS; i++)
                out[i] = { r, g, b };
            break;

        default:
            for (int i = 0; i < NUM_LEDS; i++)
                out[i] = { WARM_R, WARM_G, WARM_B };
            break;
    }
}

void render_frame(unsigned long now) {
    if (brightness == 0 && currentAnim == ANIM_NONE && currentBrightness <= 0.01f) {
        strip.clear();
        strip.show();
        for (int i = 0; i < NUM_LEDS; i++) {
            renderedLeds[i] = { 0, 0, 0 };
        }
        return;
    }

    float bFactor = 1.0f;
    if (currentAnim == ANIM_NONE && brightness > 0) {
        bFactor = get_breathing_factor(now);
    } else if (currentAnim == ANIM_CROSSFADE) {
        // Continuous gentle breathing during crossfade ensures zero brightness popping
        bFactor = get_breathing_factor(now);
    }

    float effBright = currentBrightness * bFactor;
    if (effBright < 0.0f) effBright = 0.0f;
    if (effBright > 255.0f) effBright = 255.0f;
    float brightMult = effBright / 255.0f;

    for (int i = 0; i < NUM_LEDS; i++) {
        uint8_t r = (uint8_t)(currentLeds[i].r * brightMult + 0.5f);
        uint8_t g = (uint8_t)(currentLeds[i].g * brightMult + 0.5f);
        uint8_t b = (uint8_t)(currentLeds[i].b * brightMult + 0.5f);
        renderedLeds[i] = { r, g, b };
        strip.setPixelColor(i, r, g, b);
    }
    strip.show();
}

void start_center_on_animation() {
    if (targetBrightness == 0) {
        targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
    }
    brightness = targetBrightness;
    activeBrightness = targetBrightness;
    currentBrightness = (float)targetBrightness;

    compute_target_colors(currentMode, customR, customG, customB, targetLeds);

    // If strip was previously dark, startLeds will be black; if already illuminated, it blends seamlessly
    for (int i = 0; i < NUM_LEDS; i++) {
        startLeds[i] = currentLeds[i];
    }

    currentAnim = ANIM_CENTER_ON;
    animStartMs = millis();
    animDurationMs = ANIM_ON_DURATION_MS;
}

void start_center_off_animation() {
    if (brightness > 0) activeBrightness = brightness;
    targetBrightness = 0;
    brightness = 0;

    // Preserve true unscaled base colors so fade collapse is physically consistent
    for (int i = 0; i < NUM_LEDS; i++) {
        startLeds[i] = currentLeds[i];
        targetLeds[i] = { 0, 0, 0 };
    }

    currentAnim = ANIM_CENTER_OFF;
    animStartMs = millis();
    animDurationMs = ANIM_OFF_DURATION_MS;
}

void start_crossfade_animation() {
    if (brightness == 0) {
        start_center_on_animation();
        return;
    }
    targetBrightness = brightness;
    activeBrightness = brightness;

    compute_target_colors(currentMode, customR, customG, customB, targetLeds);

    for (int i = 0; i < NUM_LEDS; i++) {
        startLeds[i] = currentLeds[i];
    }

    currentAnim = ANIM_CROSSFADE;
    animStartMs = millis();
    animDurationMs = ANIM_CROSSFADE_MS;
}

void update_animation(unsigned long now) {
    if (now - lastAnimFrameMs < ANIM_FRAME_MS) return; // ~50 FPS target
    lastAnimFrameMs = now;

    if (currentAnim == ANIM_CROSSFADE) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < NUM_LEDS; i++) {
            float dNorm = get_normalized_center_dist(i);
            float startT = dNorm * (float)ANIM_CROSSFADE_PROP_MS;

            if (finished || (float)elapsed >= startT + (float)ANIM_CROSSFADE_FADE_MS) {
                currentLeds[i] = targetLeds[i];
            } else if ((float)elapsed <= startT) {
                currentLeds[i] = startLeds[i];
            } else {
                float u = ((float)elapsed - startT) / (float)ANIM_CROSSFADE_FADE_MS;
                float s = ease_smootherstep(u);
                uint8_t r = (uint8_t)(startLeds[i].r + (targetLeds[i].r - startLeds[i].r) * s + 0.5f);
                uint8_t g = (uint8_t)(startLeds[i].g + (targetLeds[i].g - startLeds[i].g) * s + 0.5f);
                uint8_t b = (uint8_t)(startLeds[i].b + (targetLeds[i].b - startLeds[i].b) * s + 0.5f);
                currentLeds[i] = { r, g, b };
            }
        }

        // Smooth brightness tracking during mode transition if brightness target shifted
        if (fabsf(currentBrightness - (float)targetBrightness) > 0.5f) {
            currentBrightness += ((float)targetBrightness - currentBrightness) * 0.20f;
        } else {
            currentBrightness = (float)targetBrightness;
        }

        if (finished) {
            for (int i = 0; i < NUM_LEDS; i++) {
                currentLeds[i] = targetLeds[i];
            }
            currentAnim = ANIM_NONE;
        }
    }
    else if (currentAnim == ANIM_CENTER_ON) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < NUM_LEDS; i++) {
            float dNorm = get_normalized_center_dist(i);
            float startT = dNorm * (float)ANIM_ON_PROP_MS;

            if (finished || (float)elapsed >= startT + (float)ANIM_ON_FADE_MS) {
                currentLeds[i] = targetLeds[i];
            } else if ((float)elapsed <= startT) {
                currentLeds[i] = startLeds[i];
            } else {
                float u = ((float)elapsed - startT) / (float)ANIM_ON_FADE_MS;
                float s = ease_smootherstep(u);
                uint8_t r = (uint8_t)(startLeds[i].r + (targetLeds[i].r - startLeds[i].r) * s + 0.5f);
                uint8_t g = (uint8_t)(startLeds[i].g + (targetLeds[i].g - startLeds[i].g) * s + 0.5f);
                uint8_t b = (uint8_t)(startLeds[i].b + (targetLeds[i].b - startLeds[i].b) * s + 0.5f);
                currentLeds[i] = { r, g, b };
            }
        }

        if (finished) {
            for (int i = 0; i < NUM_LEDS; i++) {
                currentLeds[i] = targetLeds[i];
            }
            currentAnim = ANIM_NONE;
            breathingBaseMs = now;
        }
    }
    else if (currentAnim == ANIM_CENTER_OFF) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < NUM_LEDS; i++) {
            float dNorm = get_normalized_center_dist(i);
            float startT = dNorm * (float)ANIM_OFF_PROP_MS;

            if (finished || (float)elapsed >= startT + (float)ANIM_OFF_FADE_MS) {
                currentLeds[i] = { 0, 0, 0 };
            } else if ((float)elapsed <= startT) {
                currentLeds[i] = startLeds[i];
            } else {
                float u = ((float)elapsed - startT) / (float)ANIM_OFF_FADE_MS;
                float s = ease_smootherstep(u);
                float factor = 1.0f - s;
                uint8_t r = (uint8_t)(startLeds[i].r * factor + 0.5f);
                uint8_t g = (uint8_t)(startLeds[i].g * factor + 0.5f);
                uint8_t b = (uint8_t)(startLeds[i].b * factor + 0.5f);
                currentLeds[i] = { r, g, b };
            }
        }

        if (finished) {
            for (int i = 0; i < NUM_LEDS; i++) {
                currentLeds[i] = { 0, 0, 0 };
                renderedLeds[i] = { 0, 0, 0 };
            }
            currentAnim = ANIM_NONE;
            currentBrightness = 0.0f;
            strip.clear();
            strip.show();
            return;
        }
    }
    else if (currentAnim == ANIM_NONE) {
        // Smooth brightness slew tracking
        if (fabsf(currentBrightness - (float)targetBrightness) > 0.5f) {
            currentBrightness += ((float)targetBrightness - currentBrightness) * 0.20f;
        } else {
            currentBrightness = (float)targetBrightness;
        }
    }

    render_frame(now);
}

// ============================================================================
// BLE NOTIFY & HYDRATION
// ============================================================================
void notify_state() {
    if (!deviceConnected || pCharacteristic == nullptr) return;

    String pkt = "{\"type\":\"state\",\"mode\":" + String(currentMode) +
                 ",\"bright\":" + String(brightness) +
                 ",\"r\":" + String(customR) +
                 ",\"g\":" + String(customG) +
                 ",\"b\":" + String(customB) +
                 ",\"ver\":\"" + String(FIRMWARE_VERSION) + "\"}";
    pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
    pCharacteristic->notify();
}

// ============================================================================
// BOTURO GO HIGH-SPEED OTA ENGINE IMPLEMENTATION
// ============================================================================
static bool otaEnqueueRxFrame(uint8_t kind, const uint8_t *data, size_t len) {
    if (data == nullptr || len == 0 || len > OTA_RX_MAX_FRAME_SIZE) return false;
    portENTER_CRITICAL(&sOtaRxMux);
    const uint8_t nextHead = (sOtaRxHead + 1) & (OTA_RX_QUEUE_CAPACITY - 1);
    if (nextHead == sOtaRxTail) {
        portEXIT_CRITICAL(&sOtaRxMux);
        return false;
    }
    OtaRxFrame &slot = sOtaRxQueue[sOtaRxHead];
    slot.kind = kind;
    slot.len = (uint16_t)len;
    memcpy(slot.raw, data, len);
    sOtaRxHead = nextHead;
    portEXIT_CRITICAL(&sOtaRxMux);
    return true;
}

static bool otaPopRxFrame(OtaRxFrame &out) {
    portENTER_CRITICAL(&sOtaRxMux);
    if (sOtaRxTail == sOtaRxHead) {
        portEXIT_CRITICAL(&sOtaRxMux);
        return false;
    }
    out = sOtaRxQueue[sOtaRxTail];
    sOtaRxTail = (sOtaRxTail + 1) & (OTA_RX_QUEUE_CAPACITY - 1);
    portEXIT_CRITICAL(&sOtaRxMux);
    return true;
}

static void otaClearRxQueue() {
    portENTER_CRITICAL(&sOtaRxMux);
    sOtaRxHead = 0;
    sOtaRxTail = 0;
    portEXIT_CRITICAL(&sOtaRxMux);
}

static uint32_t readU32LE(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

void otaMarkAppValid() {
    const esp_partition_t *running = esp_ota_get_running_partition();
    if (!running) return;
    esp_ota_img_states_t state = ESP_OTA_IMG_UNDEFINED;
    if (esp_ota_get_state_partition(running, &state) == ESP_OK) {
        if (state == ESP_OTA_IMG_PENDING_VERIFY) {
            esp_ota_mark_app_valid_cancel_rollback();
            Serial.println("[OTA] Image verified & rollback canceled");
        }
    }
}

void otaNotifyBytes(const uint8_t* data, size_t len) {
    if (pOtaStatusChar == nullptr || !deviceConnected) return;
    pOtaStatusChar->setValue((uint8_t*)data, len);
    pOtaStatusChar->notify();
}

void otaNotifyStartOk() {
    uint8_t p[1] = { OTA_ST_START_OK };
    otaNotifyBytes(p, sizeof(p));
}

void otaNotifyAck(uint32_t chunkIndex) {
    uint8_t p[5];
    p[0] = OTA_ST_ACK;
    p[1] = (uint8_t)(chunkIndex & 0xFF);
    p[2] = (uint8_t)((chunkIndex >> 8) & 0xFF);
    p[3] = (uint8_t)((chunkIndex >> 16) & 0xFF);
    p[4] = (uint8_t)((chunkIndex >> 24) & 0xFF);
    otaNotifyBytes(p, sizeof(p));
}

void otaNotifyDone() {
    uint8_t p[1] = { OTA_ST_DONE };
    otaNotifyBytes(p, sizeof(p));
}

void otaNotifyError(uint8_t errCode) {
    uint8_t p[2] = { OTA_ST_ERROR, errCode };
    otaNotifyBytes(p, sizeof(p));
}

void otaEnableHighSpeedBle() {
    NimBLEDevice::setMTU(517);
    if (pBleServer != nullptr && hasActiveConn) {
        pBleServer->updateConnParams(activeConnHandle, 6, 6, 0, 200); // 7.5ms interval
    }
    esp_bt_sleep_disable();
}

void otaRestoreNormalBle() {
    if (pBleServer != nullptr && hasActiveConn) {
        pBleServer->updateConnParams(activeConnHandle, 24, 48, 0, 500); // 30-60ms interval
    }
    esp_bt_sleep_enable();
}

bool otaFlushWriteBuffer() {
    if (otaWriteBufferLen == 0) return true;
    size_t written = Update.write(otaWriteBuffer, otaWriteBufferLen);
    if (written != otaWriteBufferLen) {
        Serial.printf("[OTA] Flash write failure: %u of %u. Err: %d\n", (unsigned)written, (unsigned)otaWriteBufferLen, Update.getError());
        otaNotifyError(OTA_ERR_WRITE_FAIL);
        Update.abort();
        otaInProgress = false;
        otaRestoreNormalBle();
        return false;
    }
    otaWriteBufferLen = 0;
    return true;
}

bool otaAppendToWriteBuffer(const uint8_t* data, size_t len) {
    if (len == 0) return true;
    size_t offset = 0;
    while (offset < len) {
        if (otaWriteBufferLen == OTA_WRITE_BUFFER_BYTES) {
            if (!otaFlushWriteBuffer()) return false;
        }
        size_t spaceLeft = OTA_WRITE_BUFFER_BYTES - otaWriteBufferLen;
        size_t copyLen = (spaceLeft < (len - offset)) ? spaceLeft : (len - offset);
        memcpy(otaWriteBuffer + otaWriteBufferLen, data + offset, copyLen);
        otaWriteBufferLen += copyLen;
        offset += copyLen;
        if (otaWriteBufferLen == OTA_WRITE_BUFFER_BYTES) {
            if (!otaFlushWriteBuffer()) return false;
        }
    }
    return true;
}

void otaAbortSession() {
    if (otaInProgress) {
        Serial.println("[OTA] Aborting session; keeping current firmware");
        Update.abort();
        otaInProgress = false;
    }
    otaWriteBufferLen = 0;
    otaRestoreNormalBle();
    otaClearRxQueue();
}

void otaHandleControlFrame(const uint8_t* data, size_t len) {
    if (data == nullptr || len == 0) return;
    const uint8_t op = data[0];

    if (op == OTA_OP_START) {
        if (len < 5) {
            otaNotifyError(OTA_ERR_BAD_START);
            return;
        }
        const uint32_t fwSize = readU32LE(data + 1);
        if (fwSize == 0) {
            otaNotifyError(OTA_ERR_BAD_START);
            return;
        }

        otaMarkAppValid();
        otaEnableHighSpeedBle();

        if (otaInProgress) {
            Update.abort();
        }

        otaTargetPartition = esp_ota_get_next_update_partition(nullptr);
        if (otaTargetPartition == nullptr) {
            Serial.println("[OTA] No OTA target partition found!");
            otaNotifyError(OTA_ERR_BEGIN_FAIL);
            otaRestoreNormalBle();
            return;
        }

        if (!Update.begin(fwSize, U_FLASH)) {
            Serial.printf("[OTA] Update.begin failed! Err: %d\n", Update.getError());
            otaNotifyError(OTA_ERR_BEGIN_FAIL);
            otaRestoreNormalBle();
            return;
        }

        otaInProgress = true;
        otaExpectedFirmwareSize = fwSize;
        otaWrittenBytes = 0;
        otaExpectedChunkIndex = 0;
        otaWriteBufferLen = 0;
        otaLastPacketMs = millis();

        // Clear LED strip during OTA to minimize power and flash latency
        currentAnim = ANIM_NONE;
        strip.clear();
        strip.show();

        Serial.printf("[OTA] START accepted: fwSize=%u bytes\n", (unsigned)fwSize);
        otaNotifyStartOk();
        return;
    }

    if (op == OTA_OP_END) {
        if (!otaInProgress) {
            otaNotifyError(OTA_ERR_NOT_ACTIVE);
            return;
        }
        if (otaWrittenBytes != otaExpectedFirmwareSize) {
            Serial.printf("[OTA] END size mismatch: written=%u expected=%u\n", (unsigned)otaWrittenBytes, (unsigned)otaExpectedFirmwareSize);
            otaNotifyError(OTA_ERR_END_FAIL);
            otaAbortSession();
            return;
        }

        if (!otaFlushWriteBuffer()) return;

        if (!Update.end(true) || !Update.isFinished()) {
            Serial.printf("[OTA] Update.end failed! Err: %d\n", Update.getError());
            otaNotifyError(OTA_ERR_END_FAIL);
            otaAbortSession();
            return;
        }

        const esp_partition_t *bootPartition = esp_ota_get_boot_partition();
        if (bootPartition == nullptr || bootPartition->address != otaTargetPartition->address) {
            Serial.println("[OTA] Boot partition verification mismatch!");
            otaNotifyError(OTA_ERR_END_FAIL);
            otaAbortSession();
            return;
        }

        otaInProgress = false;
        otaRestoreNormalBle();
        otaNotifyDone();
        record_light_log(false, "OTA Firmware Update");
        Serial.println("[OTA] Update successful & verified! Rebooting in 2500ms...");
        delay(2500);
        ESP.restart();
        return;
    }
}

void otaHandleDataFrame(const uint8_t* data, size_t len) {
    if (data == nullptr || len <= 4 || !otaInProgress) return;

    otaLastPacketMs = millis();
    const uint32_t chunkIndex = readU32LE(data);
    const uint8_t* payload = data + 4;
    const size_t payloadLen = len - 4;

    // Duplicate chunk from retransmit window
    if (chunkIndex < otaExpectedChunkIndex) {
        const bool isWindowEnd = (((uint64_t)chunkIndex + 1ULL) % (uint64_t)OTA_ACK_WINDOW_PACKETS) == 0ULL;
        const bool isFinalChunk = (otaExpectedChunkIndex > 0 && (chunkIndex + 1U) == otaExpectedChunkIndex && otaWrittenBytes >= otaExpectedFirmwareSize);
        if (isWindowEnd || isFinalChunk) {
            otaNotifyAck(chunkIndex);
        }
        return;
    }

    // Out of order chunk
    if (chunkIndex != otaExpectedChunkIndex) {
        Serial.printf("[OTA] Out-of-order chunk: got %u, expected %u\n", (unsigned)chunkIndex, (unsigned)otaExpectedChunkIndex);
        otaNotifyError(OTA_ERR_ORDER);
        return;
    }

    if (otaWrittenBytes + payloadLen > otaExpectedFirmwareSize) {
        Serial.println("[OTA] Chunk overflows expected firmware size!");
        otaNotifyError(OTA_ERR_WRITE_FAIL);
        otaAbortSession();
        return;
    }

    if (!otaAppendToWriteBuffer(payload, payloadLen)) return;

    otaWrittenBytes += payloadLen;
    otaExpectedChunkIndex++;

    const bool isWindowEnd = (((uint64_t)chunkIndex + 1ULL) % (uint64_t)OTA_ACK_WINDOW_PACKETS) == 0ULL;
    const bool isFinalChunk = otaWrittenBytes >= otaExpectedFirmwareSize;
    if (isWindowEnd || isFinalChunk) {
        otaNotifyAck(chunkIndex);
    }
}

void processOtaCommandQueue() {
    OtaRxFrame frame;
    uint8_t processed = 0;
    while (processed < 24 && otaPopRxFrame(frame)) {
        if (frame.kind == OTA_RX_KIND_CONTROL) {
            otaHandleControlFrame(frame.raw, frame.len);
        } else if (frame.kind == OTA_RX_KIND_DATA) {
            otaHandleDataFrame(frame.raw, frame.len);
        }
        processed++;
    }
}

void send_schedule_hydration_to_app() {
    if (!deviceConnected || pCharacteristic == nullptr) return;

    notify_state();
    delay(40);

    // Timer telemetry
    if (autoOffTimerActive) {
        unsigned long elapsedSec = (millis() - autoOffTimerStartMs) / 1000UL;
        if (elapsedSec < (unsigned long)autoOffTimerDurationSec) {
            unsigned long rem = autoOffTimerDurationSec - elapsedSec;
            String timerPkt = "{\"type\":\"timer_sync\",\"active\":true,\"duration\":" +
                              String(autoOffTimerDurationSec) + ",\"remaining\":" + String(rem) + "}";
            pCharacteristic->setValue((uint8_t*)timerPkt.c_str(), timerPkt.length());
            pCharacteristic->notify();
        } else {
            autoOffTimerActive = false;
        }
    } else {
        String timerPkt = "{\"type\":\"timer_sync\",\"active\":false,\"duration\":0,\"remaining\":0}";
        pCharacteristic->setValue((uint8_t*)timerPkt.c_str(), timerPkt.length());
        pCharacteristic->notify();
    }
    delay(40);

    // Schedule hydration start
    String startPkt = "{\"type\":\"sched_start\",\"count\":" + String(scheduleCount) + "}";
    pCharacteristic->setValue((uint8_t*)startPkt.c_str(), startPkt.length());
    pCharacteristic->notify();
    delay(40);

    for (int i = 0; i < scheduleCount; i++) {
        const ScheduleItem& s = schedules[i];

        String daysStr = "[";
        bool first = true;
        for (int d = 1; d <= 7; d++) {
            if (s.repeatDaysMask & (1 << d)) {
                if (!first) daysStr += ",";
                daysStr += String(d);
                first = false;
            }
        }
        daysStr += "]";

        String pkt = "{\"type\":\"sched\",\"idx\":" + String(i) +
                     ",\"total\":" + String(scheduleCount) +
                     ",\"id\":\"" + String(s.id) + "\"" +
                     ",\"name\":\"" + String(s.name) + "\"" +
                     ",\"en\":" + String(s.isEnabled ? "true" : "false") +
                     ",\"on_en\":" + String(s.hasTurnOn ? "true" : "false") +
                     ",\"on_h\":" + String(s.turnOnHour) +
                     ",\"on_m\":" + String(s.turnOnMinute) +
                     ",\"off_en\":" + String(s.hasTurnOff ? "true" : "false") +
                     ",\"off_h\":" + String(s.turnOffHour) +
                     ",\"off_m\":" + String(s.turnOffMinute) +
                     ",\"days\":" + daysStr +
                     ",\"tgt_mode\":" + String(s.targetMode) +
                     ",\"tgt_bright\":" + String(s.targetBrightness) +
                     ",\"tgt_r\":" + String(s.targetR) +
                     ",\"tgt_g\":" + String(s.targetG) +
                     ",\"tgt_b\":" + String(s.targetB) + "}";

        pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
        pCharacteristic->notify();
        delay(40);
    }

    String endPkt = "{\"type\":\"sched_end\",\"count\":" + String(scheduleCount) + "}";
    pCharacteristic->setValue((uint8_t*)endPkt.c_str(), endPkt.length());
    pCharacteristic->notify();
    delay(40);
}

void send_logs_hydration_to_app() {
    if (!deviceConnected || pCharacteristic == nullptr) return;

    String startPkt = "{\"type\":\"logs_start\",\"count\":" + String(lightLogCount) + "}";
    pCharacteristic->setValue((uint8_t*)startPkt.c_str(), startPkt.length());
    pCharacteristic->notify();
    delay(40);

    for (int i = 0; i < lightLogCount; i++) {
        const LightLogItem& l = lightLogs[i];
        String pkt = "{\"type\":\"log\",\"idx\":" + String(i) +
                     ",\"total\":" + String(lightLogCount) +
                     ",\"id\":\"" + String(l.id) + "\"" +
                     ",\"on\":" + String(l.isOn ? "true" : "false") +
                     ",\"mode\":" + String(l.mode) +
                     ",\"bright\":" + String(l.brightness) +
                     ",\"epoch\":" + String(l.epoch) +
                     ",\"y\":" + String(l.year) +
                     ",\"mon\":" + String(l.month) +
                     ",\"d\":" + String(l.day) +
                     ",\"h\":" + String(l.hour) +
                     ",\"m\":" + String(l.minute) +
                     ",\"s\":" + String(l.second) +
                     ",\"dur\":" + String(l.durationSec) +
                     ",\"src\":\"" + String(l.source) + "\"}";
        pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
        pCharacteristic->notify();
        delay(40);
    }

    String endPkt = "{\"type\":\"logs_end\"}";
    pCharacteristic->setValue((uint8_t*)endPkt.c_str(), endPkt.length());
    pCharacteristic->notify();
    delay(40);
}

// ============================================================================
// LIGHTWEIGHT JSON EXTRACTORS
// ============================================================================
String extract_json_string(const String& json, const String& key) {
    String search = "\"" + key + "\"";
    int idx = json.indexOf(search);
    if (idx == -1) return "";
    int colon = json.indexOf(':', idx + search.length());
    if (colon == -1) return "";
    int quoteStart = json.indexOf('\"', colon + 1);
    if (quoteStart == -1) return "";
    int quoteEnd = json.indexOf('\"', quoteStart + 1);
    if (quoteEnd == -1) return "";
    return json.substring(quoteStart + 1, quoteEnd);
}

int extract_json_int(const String& json, const String& key, int defaultVal = -1) {
    String search = "\"" + key + "\"";
    int idx = json.indexOf(search);
    if (idx == -1) return defaultVal;
    int colon = json.indexOf(':', idx + search.length());
    if (colon == -1) return defaultVal;
    int start = colon + 1;
    while (start < (int)json.length() && (json[start] == ' ' || json[start] == '\"')) start++;
    int end = start;
    while (end < (int)json.length() && (isdigit(json[end]) || json[end] == '-')) end++;
    if (start == end) return defaultVal;
    return json.substring(start, end).toInt();
}

bool extract_json_bool(const String& json, const String& key, bool defaultVal = false) {
    String search = "\"" + key + "\"";
    int idx = json.indexOf(search);
    if (idx == -1) return defaultVal;
    int colon = json.indexOf(':', idx + search.length());
    if (colon == -1) return defaultVal;
    int start = colon + 1;
    while (start < (int)json.length() && json[start] == ' ') start++;
    if (json.substring(start).startsWith("true")) return true;
    if (json.substring(start).startsWith("false")) return false;
    return defaultVal;
}

uint8_t extract_repeat_days_mask(const String& json) {
    int idx = json.indexOf("\"days\"");
    if (idx == -1) return 0xFE; // Default all 7 days
    int start = json.indexOf("[", idx);
    int end = json.indexOf("]", start);
    if (start == -1 || end == -1) return 0xFE;

    String daysStr = json.substring(start + 1, end);
    uint8_t mask = 0;
    for (int i = 0; i < (int)daysStr.length(); i++) {
        char c = daysStr[i];
        if (c >= '1' && c <= '7') {
            mask |= (1 << (c - '0'));
        }
    }
    return mask == 0 ? 0xFE : mask;
}

// ============================================================================
// COMMAND HANDLER
// ============================================================================
void handle_command(const String& json) {
    String cmd = extract_json_string(json, "cmd");
    Serial.printf("[BLE] Command: %s\n", cmd.c_str());

    // 1. LED State Controls
    if (cmd == "set_mode") {
        int m = extract_json_int(json, "mode", -1);
        if (m >= 0 && m <= 3) {
            bool wasOff = (brightness == 0);
            currentMode = m;
            if (wasOff) {
                targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
                brightness = targetBrightness;
                start_center_on_animation();
                record_light_log(true, "App Mode Change");
            } else {
                start_crossfade_animation();
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            notify_state();
            Serial.printf("[LED] Mode → %d\n", currentMode);
        }
        return;
    }

    if (cmd == "set_bright") {
        int v = extract_json_int(json, "val", -1);
        if (v >= 0 && v <= 255) {
            if (v == 0) {
                if (brightness > 0 || currentBrightness > 0.5f) {
                    start_center_off_animation();
                }
            } else {
                if (brightness == 0) {
                    targetBrightness = v;
                    brightness = v;
                    activeBrightness = v;
                    start_center_on_animation();
                } else {
                    targetBrightness = v;
                    activeBrightness = v;
                    brightness = v;
                }
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            notify_state();
        }
        return;
    }

    if (cmd == "set_rgb") {
        int r = extract_json_int(json, "r", -1);
        int g = extract_json_int(json, "g", -1);
        int b = extract_json_int(json, "b", -1);
        if (r >= 0 && g >= 0 && b >= 0) {
            customR = constrain(r, 0, 255);
            customG = constrain(g, 0, 255);
            customB = constrain(b, 0, 255);
            currentMode = 3;  // Auto-switch to custom RGB mode
            if (brightness == 0) {
                targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
                brightness = targetBrightness;
                start_center_on_animation();
            } else {
                start_crossfade_animation();
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            notify_state();
        }
        return;
    }

    if (cmd == "on") {
        // Switch ON: advance to next mode and loop among the 3 preset states
        if (currentMode >= 2) {
            currentMode = 0;
        } else {
            currentMode++;
        }
        targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
        brightness = targetBrightness;
        start_center_on_animation();
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        record_light_log(true, "App Turn ON");
        Serial.printf("[LED] Power ON → Mode %d (Brightness %d)\n", currentMode, brightness);
        return;
    }

    if (cmd == "next_mode") {
        if (currentMode >= 2) {
            currentMode = 0;
        } else {
            currentMode++;
        }
        bool wasOff = (brightness == 0);
        if (wasOff) {
            targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
            brightness = targetBrightness;
            start_center_on_animation();
            record_light_log(true, "App Next Mode");
        } else {
            start_crossfade_animation();
        }
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        Serial.printf("[LED] Next mode → %d\n", currentMode);
        return;
    }

    if (cmd == "off") {
        if (brightness > 0 || currentBrightness > 0.5f) {
            start_center_off_animation();
            record_light_log(false, "App Manual OFF");
        }
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        return;
    }

    if (cmd == "get_state") {
        notify_state();
        return;
    }

    // 2. Time Synchronization: {"cmd":"time","y":2026,"mon":9,"d":21,"h":11,"m":30,"s":0,"epoch":...}
    if (cmd == "time") {
        int y = extract_json_int(json, "y", 0);
        int mon = extract_json_int(json, "mon", 0);
        int d = extract_json_int(json, "d", 0);
        int h = extract_json_int(json, "h", 0);
        int m = extract_json_int(json, "m", 0);
        int s = extract_json_int(json, "s", 0);
        int w = extract_json_int(json, "w", 1);
        uint32_t epoch = (uint32_t)extract_json_int(json, "epoch", 0);

        struct tm tmInfo;
        memset(&tmInfo, 0, sizeof(tmInfo));

        if (y >= 2024 && mon >= 1 && mon <= 12 && d >= 1 && d <= 31) {
            tmInfo.tm_year = y - 1900;
            tmInfo.tm_mon = mon - 1;
            tmInfo.tm_mday = d;
            tmInfo.tm_hour = h;
            tmInfo.tm_min = m;
            tmInfo.tm_sec = s;
            tmInfo.tm_wday = (w % 7);
            tmInfo.tm_isdst = -1;
        } else if (epoch > 1700000000) {
            time_t ep = (time_t)epoch;
            localtime_r(&ep, &tmInfo);
            y = tmInfo.tm_year + 1900;
            mon = tmInfo.tm_mon + 1;
            d = tmInfo.tm_mday;
            h = tmInfo.tm_hour;
            m = tmInfo.tm_min;
            s = tmInfo.tm_sec;
        }

        time_t t = mktime(&tmInfo);
        struct timeval tv = { .tv_sec = t, .tv_usec = 0 };
        settimeofday(&tv, NULL);
        timeIsSynchronized = true;

        Serial.printf("[Clock] Synchronized to %04d-%02d-%02d %02d:%02d:%02d\n", y, mon, d, h, m, s);

        if (deviceConnected && pCharacteristic != nullptr) {
            String ack = "{\"type\":\"time_synced\",\"epoch\":" + String((uint32_t)t) + "}";
            pCharacteristic->setValue((uint8_t*)ack.c_str(), ack.length());
            pCharacteristic->notify();
        }
        return;
    }

    // 3. Schedules Hydration & CRUD
    if (cmd == "get_scheds" || cmd == "sync") {
        send_schedule_hydration_to_app();
        return;
    }

    if (cmd == "save_sched") {
        String id = extract_json_string(json, "id");
        if (id.isEmpty()) return;

        int targetIdx = -1;
        for (int i = 0; i < scheduleCount; i++) {
            if (strcmp(schedules[i].id, id.c_str()) == 0) {
                targetIdx = i;
                break;
            }
        }

        if (targetIdx == -1) {
            if (scheduleCount < MAX_SCHEDULES) {
                targetIdx = scheduleCount++;
            } else {
                targetIdx = MAX_SCHEDULES - 1;
            }
        }

        ScheduleItem& item = schedules[targetIdx];
        strncpy(item.id, id.c_str(), sizeof(item.id) - 1);
        String name = extract_json_string(json, "name");
        strncpy(item.name, name.isEmpty() ? "Temple Schedule" : name.c_str(), sizeof(item.name) - 1);
        item.isEnabled = extract_json_bool(json, "en", true);
        item.hasTurnOn = extract_json_bool(json, "on_en", true);
        item.turnOnHour = extract_json_int(json, "on_h", 18);
        item.turnOnMinute = extract_json_int(json, "on_m", 0);
        item.hasTurnOff = extract_json_bool(json, "off_en", true);
        item.turnOffHour = extract_json_int(json, "off_h", 6);
        item.turnOffMinute = extract_json_int(json, "off_m", 0);
        item.repeatDaysMask = extract_repeat_days_mask(json);
        item.targetMode = extract_json_int(json, "tgt_mode", 0);
        item.targetBrightness = extract_json_int(json, "tgt_bright", 255);
        item.targetR = extract_json_int(json, "tgt_r", 255);
        item.targetG = extract_json_int(json, "tgt_g", 147);
        item.targetB = extract_json_int(json, "tgt_b", 41);
        memset(item.lastTriggeredKey, 0, sizeof(item.lastTriggeredKey));

        save_schedules_to_nvs();
        send_schedule_hydration_to_app();
        return;
    }

    if (cmd == "toggle_sched") {
        String id = extract_json_string(json, "id");
        bool en = extract_json_bool(json, "en", true);
        for (int i = 0; i < scheduleCount; i++) {
            if (strcmp(schedules[i].id, id.c_str()) == 0) {
                schedules[i].isEnabled = en;
                save_schedules_to_nvs();
                break;
            }
        }
        return;
    }

    if (cmd == "del_sched") {
        String id = extract_json_string(json, "id");
        int found = -1;
        for (int i = 0; i < scheduleCount; i++) {
            if (strcmp(schedules[i].id, id.c_str()) == 0) {
                found = i;
                break;
            }
        }
        if (found != -1) {
            for (int i = found; i < scheduleCount - 1; i++) {
                schedules[i] = schedules[i + 1];
            }
            scheduleCount--;
            save_schedules_to_nvs();
            send_schedule_hydration_to_app();
        }
        return;
    }

    // 4. Auto Turn-Off Countdown Timer
    if (cmd == "timer") {
        int sec = extract_json_int(json, "sec", 900);
        if (sec > 0) {
            autoOffTimerDurationSec = sec;
            autoOffTimerStartMs = millis();
            autoOffTimerActive = true;
            if (brightness == 0) {
                brightness = (activeBrightness > 0) ? activeBrightness : 255;
                start_center_on_animation();
                save_state();
                notify_state();
                record_light_log(true, "Auto-Off Timer");
            }
            if (deviceConnected && pCharacteristic != nullptr) {
                String timerPkt = "{\"type\":\"timer_started\",\"sec\":" + String(sec) +
                                  ",\"remaining\":" + String(sec) + "}";
                pCharacteristic->setValue((uint8_t*)timerPkt.c_str(), timerPkt.length());
                pCharacteristic->notify();
            }
            Serial.printf("[Timer] Auto-off countdown started for %d seconds\n", sec);
        }
        return;
    }

    if (cmd == "timer_cancel") {
        autoOffTimerActive = false;
        if (deviceConnected && pCharacteristic != nullptr) {
            String timerPkt = "{\"type\":\"timer_canceled\"}";
            pCharacteristic->setValue((uint8_t*)timerPkt.c_str(), timerPkt.length());
            pCharacteristic->notify();
        }
        Serial.println("[Timer] Auto-off countdown canceled");
        return;
    }

    // 5. Activity Logs Hydration & Clear
    if (cmd == "get_logs") {
        send_logs_hydration_to_app();
        return;
    }

    if (cmd == "clear_logs") {
        lightLogCount = 0;
        save_logs_to_nvs();
        if (deviceConnected && pCharacteristic != nullptr) {
            String ack = "{\"type\":\"logs_cleared\"}";
            pCharacteristic->setValue((uint8_t*)ack.c_str(), ack.length());
            pCharacteristic->notify();
        }
        return;
    }

    // 6. Over-The-Air (OTA) is handled via dedicated high-speed Boturo Go GATT service

    Serial.printf("[BLE] Unknown command: %s\n", cmd.c_str());
}

// ============================================================================
// BLE CALLBACKS
// ============================================================================
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        deviceConnected = true;
        pBleServer = pServer;
        hasActiveConn = true;
        activeConnHandle = desc->conn_handle;
        Serial.printf("[BLE] Companion app connected (handle=%d)\n", activeConnHandle);
    }

    void onDisconnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        deviceConnected = false;
        hasActiveConn = false;
        if (otaInProgress) {
            Serial.println("[OTA] Disconnected during update -> Aborting");
            otaAbortSession();
        }
        Serial.println("[BLE] Disconnected → Resuming advertising");
        NimBLEDevice::startAdvertising();
    }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic* pChar) override {
        uint8_t buf[5] = { currentMode, brightness, customR, customG, customB };
        pChar->setValue(buf, 5);
    }

    void onWrite(NimBLECharacteristic* pChar) override {
        std::string val = pChar->getValue();
        if (val.empty()) return;

        size_t braceIdx = val.find('{');
        if (braceIdx != std::string::npos) {
            handle_command(String(val.substr(braceIdx).c_str()));
            return;
        }

        // Fast 2-byte binary packet for live brightness: [0x42 ('B'), brightness (0..255)]
        if (val.length() == 2 && (uint8_t)val[0] == 0x42) {
            uint8_t v = (uint8_t)val[1];
            if (v == 0) {
                if (brightness > 0 || currentBrightness > 0.5f) {
                    start_center_off_animation();
                }
            } else {
                if (brightness == 0) {
                    targetBrightness = v;
                    brightness = v;
                    activeBrightness = v;
                    start_center_on_animation();
                } else {
                    targetBrightness = v;
                    activeBrightness = v;
                    brightness = v;
                }
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            return;
        }

        // Single-byte shortcut: bytes 0..3 set mode directly
        if (val.length() == 1) {
            uint8_t b = (uint8_t)val[0];
            if (b <= 3) {
                bool wasOff = (brightness == 0);
                currentMode = b;
                if (wasOff) {
                    targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
                    brightness = targetBrightness;
                    start_center_on_animation();
                    record_light_log(true, "App Byte Mode");
                } else {
                    start_crossfade_animation();
                }
                stateDirty = true;
                lastStateChangeMs = millis();
                notify_state();
            }
            return;
        }
    }
};

class OtaControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar) override {
        std::string val = pChar->getValue();
        if (val.empty()) return;
        otaEnqueueRxFrame(OTA_RX_KIND_CONTROL, (const uint8_t*)val.data(), val.length());
    }
};

class OtaDataCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar) override {
        std::string val = pChar->getValue();
        if (val.empty()) return;
        otaEnqueueRxFrame(OTA_RX_KIND_DATA, (const uint8_t*)val.data(), val.length());
    }
};

// ============================================================================
// AUTONOMOUS BACKGROUND EVALUATION (SCHEDULES & TIMER)
// ============================================================================
void evaluate_schedules() {
    if (!timeIsSynchronized) return;

    time_t now = time(NULL);
    struct tm tmInfo;
    localtime_r(&now, &tmInfo);

    int curHour = tmInfo.tm_hour;
    int curMin  = tmInfo.tm_min;
    int curDay  = tmInfo.tm_wday == 0 ? 7 : tmInfo.tm_wday; // 1=Mon .. 7=Sun

    for (int i = 0; i < scheduleCount; i++) {
        ScheduleItem& s = schedules[i];
        if (!s.isEnabled) continue;
        if (!(s.repeatDaysMask & (1 << curDay))) continue;

        // Turn ON trigger
        if (s.hasTurnOn && curHour == s.turnOnHour && curMin == s.turnOnMinute) {
            char key[24];
            snprintf(key, sizeof(key), "ON_%d_%02d_%02d", tmInfo.tm_mday, curHour, curMin);
            if (strcmp(s.lastTriggeredKey, key) != 0) {
                strncpy(s.lastTriggeredKey, key, sizeof(s.lastTriggeredKey) - 1);
                currentMode = s.targetMode;
                targetBrightness = s.targetBrightness > 0 ? s.targetBrightness : 255;
                brightness = targetBrightness;
                if (s.targetMode == 3) {
                    customR = (s.targetR > 0 || s.targetG > 0 || s.targetB > 0) ? s.targetR : 255;
                    customG = s.targetG;
                    customB = s.targetB;
                }
                start_center_on_animation();
                save_state();
                notify_state();
                record_light_log(true, s.name);
                Serial.printf("[Sched] ⏰ Triggered ON: %s (Mode %d, Bright %d)\n", s.name, currentMode, brightness);
            }
        }

        // Turn OFF trigger
        if (s.hasTurnOff && curHour == s.turnOffHour && curMin == s.turnOffMinute) {
            char key[24];
            snprintf(key, sizeof(key), "OFF_%d_%02d_%02d", tmInfo.tm_mday, curHour, curMin);
            if (strcmp(s.lastTriggeredKey, key) != 0) {
                strncpy(s.lastTriggeredKey, key, sizeof(s.lastTriggeredKey) - 1);
                if (brightness > 0 || currentBrightness > 0.5f) {
                    start_center_off_animation();
                }
                save_state();
                notify_state();
                record_light_log(false, s.name);
                Serial.printf("[Sched] ⏰ Triggered OFF: %s\n", s.name);
            }
        }
    }
}

void evaluate_auto_off_timer() {
    if (!autoOffTimerActive) return;

    unsigned long elapsedSec = (millis() - autoOffTimerStartMs) / 1000UL;
    if (elapsedSec >= (unsigned long)autoOffTimerDurationSec) {
        autoOffTimerActive = false;
        if (brightness > 0 || currentBrightness > 0.5f) {
            start_center_off_animation();
        }
        save_state();
        notify_state();
        record_light_log(false, "Timer Auto-Off");
        Serial.println("[Timer] ⏰ Auto-off countdown expired → Turned OFF lights");

        if (deviceConnected && pCharacteristic != nullptr) {
            String donePkt = "{\"type\":\"timer_done\"}";
            pCharacteristic->setValue((uint8_t*)donePkt.c_str(), donePkt.length());
            pCharacteristic->notify();
        }
    }
}

// ============================================================================
// SETUP & MAIN LOOP
// ============================================================================
void setup() {
    Serial.begin(115200);
    delay(100);
    Serial.println();
    Serial.println("==========================================");
    Serial.println("    Temple Lights — BLE Smart RGB Strip   ");
    Serial.println("==========================================");

    // Cancel rollback and mark boot image valid if booted after an OTA update
    otaMarkAppValid();

    load_state();
    load_schedules_from_nvs();
    load_logs_from_nvs();

    // Power-cycle mode advancement (0 -> 1 -> 2 -> 0)
    // Always remember the last state from NVS and cycle to next mode
    uint8_t lastMode = currentMode;
    if (lastMode >= 2) {
        currentMode = 0;
    } else {
        currentMode = lastMode + 1;
    }
    brightness = 255; // Ensure 100% brightness on power cycle
    targetBrightness = 255;
    activeBrightness = 255;
    currentBrightness = 255.0f;
    save_state();     // Persist immediately so subsequent boots advance from here

    Serial.printf("[Boot] Last Mode: %d -> Active Mode: %d | Brightness: %d\n",
                  lastMode, currentMode, brightness);

    record_light_log(true, "Power Cycle Boot");

    // Initialize NimBLE Server FIRST so radio setup does not block animation
    NimBLEDevice::init(DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setMTU(517);

    pBleServer = NimBLEDevice::createServer();
    pBleServer->setCallbacks(new ServerCallbacks());

    // 1. Primary Temple Lights Control Service
    NimBLEService* pService = pBleServer->createService(SERVICE_UUID);
    pCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR |
        NIMBLE_PROPERTY::READ  | NIMBLE_PROPERTY::NOTIFY
    );
    pCharacteristic->setCallbacks(new CharacteristicCallbacks());

    uint8_t initBuf[5] = { currentMode, brightness, customR, customG, customB };
    pCharacteristic->setValue(initBuf, 5);
    pService->start();

    // 2. Dedicated Boturo Go High-Speed OTA Service
    NimBLEService* pOtaService = pBleServer->createService(OTA_SERVICE_UUID);
    pOtaControlChar = pOtaService->createCharacteristic(
        OTA_CONTROL_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    pOtaControlChar->setCallbacks(new OtaControlCallbacks());

    pOtaDataChar = pOtaService->createCharacteristic(
        OTA_DATA_UUID,
        NIMBLE_PROPERTY::WRITE_NR
    );
    pOtaDataChar->setCallbacks(new OtaDataCallbacks());

    pOtaStatusChar = pOtaService->createCharacteristic(
        OTA_STATUS_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ
    );
    pOtaStatusChar->setValue(std::string("FW:") + std::string(FIRMWARE_VERSION));
    pOtaService->start();

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(SERVICE_UUID);
    pAdv->addServiceUUID(OTA_SERVICE_UUID);
    pAdv->setScanResponse(true);
    pAdv->start();

    Serial.printf("[BLE] Advertising as '%s'\n", DEVICE_NAME);
    Serial.printf("[BLE] Service:     %s\n", SERVICE_UUID);
    Serial.printf("[BLE] OTA Service: %s\n", OTA_SERVICE_UUID);
    Serial.println("[BLE] Ready. Waiting for app connection...");

    // Initialize LED strip at full 255 scale and start Center-Out Bloom animation
    strip.begin();
    strip.setBrightness(255);
    start_center_on_animation();
}

void loop() {
    // Process high-speed OTA command queue
    processOtaCommandQueue();

    // If OTA firmware flash is active, dedicate CPU to flash operations
    if (otaInProgress) {
        if (millis() - otaLastPacketMs > 15000) {
            Serial.println("[OTA] Timeout waiting for packets -> Aborting");
            otaNotifyError(OTA_ERR_TIMEOUT);
            otaAbortSession();
        }
        delay(2);
        return;
    }

    unsigned long now = millis();

    // High-priority 50 FPS animation engine
    update_animation(now);

    // Evaluate autonomous schedules every 1 second
    if (now - lastScheduleEvalMs >= 1000) {
        lastScheduleEvalMs = now;
        evaluate_schedules();
    }

    // Evaluate auto-off countdown timer every 500ms
    if (now - lastTimerTickMs >= 500) {
        lastTimerTickMs = now;
        evaluate_auto_off_timer();
    }

    // Debounced NVS write for live brightness/mode updates (1000ms after last change)
    if (stateDirty && (now - lastStateChangeMs >= 1000)) {
        stateDirty = false;
        save_state();
        Serial.printf("[NVS] Debounced state saved (bright=%d, mode=%d)\n", brightness, currentMode);
    }

    // Debounced NVS write for light session logs (1000ms after last change)
    if (logsDirty && (now - lastLogsChangeMs >= 1000)) {
        logsDirty = false;
        save_logs_to_nvs();
        Serial.printf("[NVS] Debounced logs saved (count=%d)\n", lightLogCount);
    }

    // Dynamic yield: short yield when animating or breathing to maximize smoothness, 10ms when completely off
    delay((currentAnim != ANIM_NONE || brightness > 0) ? 2 : 10);
}
