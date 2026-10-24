#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
#include <Update.h>
#include <sys/time.h>
#include <time.h>
#include <esp_bt.h>
#include <esp_ota_ops.h>
#include "wifi_manager.h"

// ============================================================================
// HARDWARE & ANIMATION CONFIG
// ============================================================================
#define LED_PIN                   4
#define MAX_LEDS                  600   // Max buffer capacity (up to 10m @ 60 LEDs/m)
#define DEFAULT_NUM_LEDS          150   // 2.5m × 60 LEDs/m default

// Global runtime hardware & animation settings (persisted in NVS "tl")
static uint16_t numLeds = DEFAULT_NUM_LEDS;
static uint16_t maxCurrentMa = 3000;    // 3A default safety budget
static uint8_t transitionStyle = 0;    // 0=Center-Out, 1=Linear Sweep, 2=Instant Fade
static uint8_t ambientStyle = 1;       // 0=Solid, 1=Breathing, 2=Diya Flicker
static uint8_t ambientDepth = 6;       // 6% depth

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
#define ANIM_FRAME_MS               20   // ~50 FPS target frame timing

#define MAX_SCHEDULES             16
#define MAX_LOGS                  20

// ============================================================================
// BLE & FIRMWARE CONFIG
// ============================================================================
#define FIRMWARE_VERSION    "1.3.0"
#define DEFAULT_DEVICE_NAME "Temple Lights"

static char defaultDeviceName[32] = DEFAULT_DEVICE_NAME;
static char activeDeviceName[36] = DEFAULT_DEVICE_NAME;
static char macSuffixStr[8] = "";

// Primary Service & Control Characteristic (Matched to hardware 95d6fedc-cac3-48e2-8221-f534a2782704)
#define SERVICE_UUID            "95d6fedc-cac3-48e2-8221-f534a2782704"
#define CHARACTERISTIC_UUID     "0ddad461-e5e3-457b-a173-da66bd52bf4d"

// Dedicated Temple Lights High-Speed OTA Service & Characteristics
#define OTA_SERVICE_UUID        "95d6fedc-cac3-48e2-8221-f534a2782710"
#define OTA_CONTROL_UUID        "0ddad461-e5e3-457b-a173-da66bd52bf4e"
#define OTA_DATA_UUID           "0ddad461-e5e3-457b-a173-da66bd52bf4f"
#define OTA_STATUS_UUID         "0ddad461-e5e3-457b-a173-da66bd52bf50"


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

struct ModeConfig {
    char name[24];
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t style;      // 0 = Full Strip, 1 = Center Focus (1.5m)
    uint8_t brightness; // 1..255
};

static const ModeConfig FACTORY_DEFAULT_MODES[3] = {
    { "Warm White",  255, 147, 41,  0, 255 },
    { "Center Warm", 255, 147, 41,  1, 255 },
    { "Pure White",  255, 255, 255, 0, 255 }
};

static ModeConfig defaultModes[3] = {
    { "Warm White",  255, 147, 41,  0, 255 },
    { "Center Warm", 255, 147, 41,  1, 255 },
    { "Pure White",  255, 255, 255, 0, 255 }
};

// ============================================================================
// DYNAMIC PRESETS & MULTI-SEGMENT RANGE CONFIG
// ============================================================================
#define MAX_PRESETS               16
#define MAX_SEGMENTS_PER_PRESET   8
#define MAX_ACTIVE_SEGMENTS       16

struct FirmwareLedSegment {
    uint16_t start;       // 0-indexed start LED
    uint16_t count;       // Number of LEDs in range
    uint8_t r;            // Segment base Red (0..255)
    uint8_t g;            // Segment base Green (0..255)
    uint8_t b;            // Segment base Blue (0..255)
    uint8_t brightness;   // Segment brightness multiplier (0..255)
    uint8_t effect;       // 0=Solid, 1=Breathe, 2=Diya, 3=Twinkle, 4=Embers, 5=Aurora, 6=Rainbow
    uint8_t speed;        // Effect frequency/speed multiplier (1..10)
    char name[16];

    FirmwareLedSegment() : start(0), count(0), r(255), g(147), b(41), brightness(255), effect(0), speed(5) {
        name[0] = '\0';
    }

    FirmwareLedSegment(uint16_t s, uint16_t c, uint8_t red, uint8_t green, uint8_t blue, uint8_t br, uint8_t fx, uint8_t spd, const char* n = "")
        : start(s), count(c), r(red), g(green), b(blue), brightness(br), effect(fx), speed(spd) {
        if (n != nullptr) {
            strncpy(name, n, sizeof(name) - 1);
            name[sizeof(name) - 1] = '\0';
        } else {
            name[0] = '\0';
        }
    }
};

struct FirmwarePreset {
    char name[24];
    uint8_t brightness;     // 1..255
    uint8_t transitionStyle;// 0..6
    uint8_t ambientStyle;   // 0..6
    uint8_t ambientDepth;   // 0..30 (%)
    bool cycleEnabled;      // Participates in physical power-cycle toggle
    uint8_t r;              // Global/Fallback RGB
    uint8_t g;
    uint8_t b;
    uint8_t segmentCount;
    FirmwareLedSegment segments[MAX_SEGMENTS_PER_PRESET];
};

static FirmwarePreset presets[MAX_PRESETS];
static int presetCount = 3;
static uint8_t activePresetIndex = 0;
static uint16_t cycleBitmask = 0x07; // By default, presets 0, 1, 2 participate in wall toggle

static FirmwareLedSegment activeSegments[MAX_ACTIVE_SEGMENTS];
static int activeSegmentCount = 0;

enum AnimType {
    ANIM_NONE = 0,
    ANIM_CENTER_ON,
    ANIM_CENTER_OFF,
    ANIM_CROSSFADE,
    ANIM_IDENTIFY,
    ANIM_HW_TEST
};

static uint8_t currentMode = 0;       // 0=warm all, 1=warm middle, 2=white all, 3=custom RGB
static uint8_t brightness  = 255;     // Target user brightness (0–255)
static uint8_t customR = 255, customG = 147, customB = 41;
static uint8_t activeBrightness = 255; // Preserved brightness for ON transitions

static float currentBrightness = 255.0f; // Slew-interpolated brightness for hardware output
static uint8_t targetBrightness = 255;

static RgbColor currentLeds[MAX_LEDS];
static RgbColor startLeds[MAX_LEDS];
static RgbColor targetLeds[MAX_LEDS];
static RgbColor renderedLeds[MAX_LEDS];

static AnimType currentAnim = ANIM_NONE;
static unsigned long animStartMs = 0;
static unsigned long animDurationMs = 0;
static unsigned long lastAnimFrameMs = 0;
static unsigned long breathingBaseMs = 0;

static Adafruit_NeoPixel strip(MAX_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);
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


// Temple Lights High-Speed OTA Runtime
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
bool timeIsSynchronized = false;
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
float get_normalized_center_dist(int i, int totalLeds);
float get_normalized_spatial_dist(int i, int totalLeds);
float ease_smootherstep(float t);
float get_ambient_factor(unsigned long now);
void compute_target_colors(uint8_t mode, uint8_t r, uint8_t g, uint8_t b, RgbColor* out);
void render_frame(unsigned long now);
void start_center_on_animation();
void start_center_off_animation();
void start_crossfade_animation();
void start_hw_test_animation();
void update_animation(unsigned long now);
void notify_state();
void record_light_log(bool isOn, const char* source = "BLE App");
void save_schedules_to_nvs();
void load_schedules_from_nvs();
void save_logs_to_nvs();
void load_logs_from_nvs();
void send_schedule_hydration_to_app();
void send_logs_hydration_to_app();
void save_modes_to_nvs();
void load_modes_from_nvs();
void reset_modes_to_defaults();
void send_modes_hydration_to_app();
void save_presets_to_nvs();
void load_presets_from_nvs();
void reset_presets_to_defaults();
void send_presets_hydration_to_app();
uint8_t get_next_cycle_preset(uint8_t current);
void activate_preset(uint8_t idx);
int extract_json_segments(const String& json, FirmwareLedSegment* outSegments, int maxSegments);
void evaluate_schedules();
void save_hw_config();
void save_anim_config();
void load_hw_and_anim_config();

// ============================================================================
// NVS PERSISTENCE FOR STATE & HARDWARE
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

void save_hw_config() {
    prefs.begin("tl", false);
    prefs.putUShort("leds", numLeds);
    prefs.putUShort("max_ma", maxCurrentMa);
    prefs.end();
}

void save_anim_config() {
    prefs.begin("tl", false);
    prefs.putUChar("trans_st", transitionStyle);
    prefs.putUChar("amb_st", ambientStyle);
    prefs.putUChar("amb_dp", ambientDepth);
    prefs.end();
}

void load_hw_and_anim_config() {
    prefs.begin("tl", true);
    numLeds         = prefs.getUShort("leds", DEFAULT_NUM_LEDS);
    maxCurrentMa    = prefs.getUShort("max_ma", 3000);
    transitionStyle = prefs.getUChar("trans_st", 0);
    ambientStyle    = prefs.getUChar("amb_st", 1);
    ambientDepth    = prefs.getUChar("amb_dp", 6);
    prefs.end();

    if (numLeds == 0 || numLeds > MAX_LEDS) numLeds = DEFAULT_NUM_LEDS;
    if (maxCurrentMa == 0) maxCurrentMa = 3000;
    if (transitionStyle > 2) transitionStyle = 0;
    if (ambientStyle > 2) ambientStyle = 1;
    if (ambientDepth == 0 || ambientDepth > 30) ambientDepth = 6;

    strip.updateLength(numLeds);
    Serial.printf("[NVS] Loaded HW Config: %d LEDs, Max %d mA | Anim: trans=%d, amb=%d, depth=%d%%\n",
                  numLeds, maxCurrentMa, transitionStyle, ambientStyle, ambientDepth);
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
// NVS PERSISTENCE FOR DEFAULT MODES
// ============================================================================
void load_modes_from_nvs() {
    prefs.begin("tl_modes", true);
    for (int i = 0; i < 3; i++) {
        String key = "m_" + String(i);
        if (prefs.isKey(key.c_str())) {
            prefs.getBytes(key.c_str(), &defaultModes[i], sizeof(ModeConfig));
            defaultModes[i].name[sizeof(defaultModes[i].name) - 1] = '\0';
            if (defaultModes[i].brightness == 0) defaultModes[i].brightness = 255;
            if (defaultModes[i].style > 1) defaultModes[i].style = 0;
        }
    }
    prefs.end();
    Serial.println("[NVS] Loaded default modes");
}

void save_modes_to_nvs() {
    prefs.begin("tl_modes", false);
    for (int i = 0; i < 3; i++) {
        String key = "m_" + String(i);
        prefs.putBytes(key.c_str(), &defaultModes[i], sizeof(ModeConfig));
    }
    prefs.end();
    Serial.println("[NVS] Saved default modes");
}

void reset_modes_to_defaults() {
    memcpy(defaultModes, FACTORY_DEFAULT_MODES, sizeof(defaultModes));
    save_modes_to_nvs();
    Serial.println("[NVS] Reset default modes to factory defaults");
}

// ============================================================================
// NVS PERSISTENCE FOR DYNAMIC PRESETS (>3 MODES & MULTI-SEGMENT RANGES)
// ============================================================================
void load_presets_from_nvs() {
    prefs.begin("tl_presets", false);
    if (!prefs.isKey("p_count")) {
        // Auto-migration from legacy tl_modes!
        Serial.println("[NVS] Migrating legacy modes to tl_presets...");
        presetCount = 5;

        // Preset 0: Full Warm
        strncpy(presets[0].name, defaultModes[0].name, sizeof(presets[0].name) - 1);
        presets[0].name[sizeof(presets[0].name) - 1] = '\0';
        presets[0].brightness = defaultModes[0].brightness;
        presets[0].transitionStyle = 0;
        presets[0].ambientStyle = 1;
        presets[0].ambientDepth = 6;
        presets[0].cycleEnabled = true;
        presets[0].r = defaultModes[0].r;
        presets[0].g = defaultModes[0].g;
        presets[0].b = defaultModes[0].b;
        presets[0].segmentCount = 0;

        // Preset 1: Center Focus 1.5m
        strncpy(presets[1].name, defaultModes[1].name, sizeof(presets[1].name) - 1);
        presets[1].name[sizeof(presets[1].name) - 1] = '\0';
        presets[1].brightness = defaultModes[1].brightness;
        presets[1].transitionStyle = 0;
        presets[1].ambientStyle = 1;
        presets[1].ambientDepth = 6;
        presets[1].cycleEnabled = true;
        presets[1].r = defaultModes[1].r;
        presets[1].g = defaultModes[1].g;
        presets[1].b = defaultModes[1].b;
        presets[1].segmentCount = 0;

        // Preset 2: Pure White
        strncpy(presets[2].name, defaultModes[2].name, sizeof(presets[2].name) - 1);
        presets[2].name[sizeof(presets[2].name) - 1] = '\0';
        presets[2].brightness = defaultModes[2].brightness;
        presets[2].transitionStyle = 0;
        presets[2].ambientStyle = 1;
        presets[2].ambientDepth = 6;
        presets[2].cycleEnabled = true;
        presets[2].r = defaultModes[2].r;
        presets[2].g = defaultModes[2].g;
        presets[2].b = defaultModes[2].b;
        presets[2].segmentCount = 0;

        // Preset 3: Pillar Base (1-6) & Apex (100-105)
        strncpy(presets[3].name, "Pillar & Halo", sizeof(presets[3].name) - 1);
        presets[3].name[sizeof(presets[3].name) - 1] = '\0';
        presets[3].brightness = 255;
        presets[3].transitionStyle = 3; // Convergence
        presets[3].ambientStyle = 2;    // Diya Flame Flutter
        presets[3].ambientDepth = 8;
        presets[3].cycleEnabled = false;
        presets[3].r = 255; presets[3].g = 180; presets[3].b = 0;
        presets[3].segmentCount = 2;
        presets[3].segments[0] = { 0, 6, 255, 147, 41, 255, 0, 5, "Base 1-6" };
        uint16_t endStart = (numLeds >= 106) ? 100 : (numLeds > 6 ? numLeds - 6 : 0);
        presets[3].segments[1] = { endStart, 6, 255, 255, 255, 255, 2, 5, "Apex 100-105" };

        // Preset 4: Sacred Aarti Fire Embers
        strncpy(presets[4].name, "Aarti Fire Embers", sizeof(presets[4].name) - 1);
        presets[4].name[sizeof(presets[4].name) - 1] = '\0';
        presets[4].brightness = 240;
        presets[4].transitionStyle = 4; // Sparkle ignition
        presets[4].ambientStyle = 4;    // Sacred amber embers
        presets[4].ambientDepth = 10;
        presets[4].cycleEnabled = false;
        presets[4].r = 255; presets[4].g = 120; presets[4].b = 20;
        presets[4].segmentCount = 1;
        presets[4].segments[0] = { 0, (uint16_t)numLeds, 255, 120, 20, 255, 4, 5, "Sacred Fire" };

        cycleBitmask = 0x07; // presets 0, 1, 2 enabled for power cycle
        prefs.putInt("p_count", presetCount);
        prefs.putUShort("cycle_mask", cycleBitmask);
        for (int i = 0; i < presetCount; i++) {
            String k = "p_" + String(i);
            prefs.putBytes(k.c_str(), &presets[i], sizeof(FirmwarePreset));
        }
        prefs.end();
        Serial.println("[NVS] Migration to tl_presets completed.");
        return;
    }

    presetCount = prefs.getInt("p_count", 3);
    if (presetCount < 1) presetCount = 1;
    if (presetCount > MAX_PRESETS) presetCount = MAX_PRESETS;
    cycleBitmask = prefs.getUShort("cycle_mask", 0x07);

    for (int i = 0; i < presetCount; i++) {
        String k = "p_" + String(i);
        if (prefs.isKey(k.c_str())) {
            prefs.getBytes(k.c_str(), &presets[i], sizeof(FirmwarePreset));
            presets[i].name[sizeof(presets[i].name) - 1] = '\0';
        }
    }
    // Backward compatibility: ensure factory standard presets 0, 1, 2 always use
    // full strip / algorithmic styling and never retain stale segment overrides
    for (int i = 0; i < 3 && i < presetCount; i++) {
        presets[i].segmentCount = 0;
    }
    prefs.end();
    Serial.printf("[NVS] Loaded %d presets from tl_presets (cycleMask=0x%02X)\n", presetCount, cycleBitmask);
}

void save_presets_to_nvs() {
    prefs.begin("tl_presets", false);
    prefs.putInt("p_count", presetCount);
    prefs.putUShort("cycle_mask", cycleBitmask);
    for (int i = 0; i < presetCount; i++) {
        String k = "p_" + String(i);
        prefs.putBytes(k.c_str(), &presets[i], sizeof(FirmwarePreset));
    }
    for (int i = presetCount; i < MAX_PRESETS; i++) {
        String k = "p_" + String(i);
        if (prefs.isKey(k.c_str())) prefs.remove(k.c_str());
    }
    prefs.end();
    Serial.printf("[NVS] Saved %d presets to tl_presets\n", presetCount);
}

void reset_presets_to_defaults() {
    prefs.begin("tl_presets", false);
    prefs.clear();
    prefs.end();
    load_presets_from_nvs();
    Serial.println("[NVS] Reset presets to factory defaults");
}

uint8_t get_next_cycle_preset(uint8_t current) {
    if (presetCount <= 1) return 0;
    // Inspect next enabled preset in power-cycle carousel
    for (int step = 1; step <= presetCount; step++) {
        uint8_t candidate = (current + step) % presetCount;
        if (presets[candidate].cycleEnabled) {
            return candidate;
        }
    }
    // Fallback: advance cyclically within active count
    return (current + 1) % ((presetCount > 3) ? 3 : presetCount);
}

void activate_preset(uint8_t idx) {
    if (idx >= presetCount) idx = 0;
    activePresetIndex = idx;
    currentMode = (idx < 3) ? idx : 3;
    const auto& p = presets[idx];
    targetBrightness = (p.brightness > 0) ? p.brightness : 255;
    brightness = targetBrightness;
    activeBrightness = targetBrightness;
    currentBrightness = (float)brightness;
    transitionStyle = p.transitionStyle;
    ambientStyle = p.ambientStyle;
    ambientDepth = p.ambientDepth;

    if (idx < 3) {
        activeSegmentCount = 0; // Factory modes 0, 1, 2 use full-strip / center algorithmic logic
    } else {
        activeSegmentCount = p.segmentCount;
        for (int s = 0; s < activeSegmentCount; s++) {
            activeSegments[s] = p.segments[s];
        }
    }
    customR = p.r; customG = p.g; customB = p.b;
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

float get_normalized_spatial_dist(int i, int totalLeds) {
    if (totalLeds <= 1) return 0.0f;
    switch (transitionStyle) {
        case 1: // Sunrise Flow (Left to Right)
            return (float)i / (float)(totalLeds - 1);
        case 2: // Uniform Smooth Fade
            return 0.0f;
        case 3: // Sunset Cascade (Right to Left)
            return 1.0f - ((float)i / (float)(totalLeds - 1));
        case 4: // Dual Convergence (Ends moving to center)
            return 1.0f - get_normalized_center_dist(i, totalLeds);
        case 5: // Sparkle Ignition (Pseudo-random hash)
            return (float)((i * 37 + 13) % 100) / 100.0f;
        case 6: // Segment Domino (step quantize)
            return (float)((i * 5) / totalLeds) * 0.20f;
        case 0: // Center-Out Dawn
        default:
            return get_normalized_center_dist(i, totalLeds);
    }
}

static float diyaCurrentFactor = 1.0f;
static float diyaTargetFactor = 1.0f;
static unsigned long lastDiyaUpdateMs = 0;

float get_ambient_factor(unsigned long now) {
    if (ambientStyle == 0) return 1.0f; // Static Solid

    if (ambientStyle == 1) { // Gentle Breathing
        unsigned long elapsed = now - breathingBaseMs;
        float phase = (float)(elapsed % ANIM_BREATHING_PERIOD_MS) * (2.0f * 3.14159265f / (float)ANIM_BREATHING_PERIOD_MS);
        float depth = (float)ambientDepth / 100.0f;
        return 1.0f - (depth * 0.5f * (1.0f - cosf(phase)));
    }

    if (ambientStyle == 2) { // Sacred Diya / Candle Flame Flutter
        if (now - lastDiyaUpdateMs >= 50) {
            lastDiyaUpdateMs = now;
            float depth = (float)ambientDepth / 100.0f;
            float r1 = (float)(esp_random() % 1000) / 1000.0f;
            float r2 = (float)(esp_random() % 1000) / 1000.0f;
            float flameVal = (r1 * 0.7f + r2 * 0.3f);
            diyaTargetFactor = 1.0f - (depth * flameVal);
        }
        // Smooth exponential moving average low-pass filter (25% per 20ms frame)
        diyaCurrentFactor += (diyaTargetFactor - diyaCurrentFactor) * 0.25f;
        return diyaCurrentFactor;
    }

    if (ambientStyle == 3) { // Starlight Twinkle
        float depth = (float)ambientDepth / 100.0f;
        float phase = (float)(now % 1800) * (2.0f * 3.14159265f / 1800.0f);
        return 1.0f - (depth * 0.35f * (1.0f - sinf(phase)));
    }

    if (ambientStyle == 4) { // Sacred Amber Embers
        unsigned long elapsed = now - breathingBaseMs;
        float depth = (float)ambientDepth / 100.0f;
        float slowWave = 0.5f * (1.0f + sinf((float)(elapsed % 4200) * (2.0f * 3.14159265f / 4200.0f)));
        float fastPulse = 0.5f * (1.0f + sinf((float)(elapsed % 950) * (2.0f * 3.14159265f / 950.0f)));
        return 1.0f - (depth * (0.6f * slowWave + 0.4f * fastPulse));
    }

    if (ambientStyle == 5) { // Aurora Flow
        unsigned long elapsed = now - breathingBaseMs;
        float depth = (float)ambientDepth / 100.0f;
        float wave = 0.5f * (1.0f + sinf((float)(elapsed % 5000) * (2.0f * 3.14159265f / 5000.0f)));
        return 1.0f - (depth * 0.5f * wave);
    }

    if (ambientStyle == 6) { // Rainbow Cycle
        return 1.0f;
    }

    return 1.0f;
}

void compute_target_colors(uint8_t mode, uint8_t r, uint8_t g, uint8_t b, RgbColor* out) {
    if (activeSegmentCount > 0) {
        // Multi-Segment arbitrary selection mode!
        for (int i = 0; i < numLeds; i++) {
            out[i] = { 0, 0, 0 }; // Unassigned LEDs remain off
        }
        for (int s = 0; s < activeSegmentCount; s++) {
            const auto& seg = activeSegments[s];
            int sEnd = seg.start + seg.count;
            if (sEnd > numLeds) sEnd = numLeds;
            float sBright = (float)seg.brightness / 255.0f;
            for (int i = seg.start; i < sEnd; i++) {
                out[i] = {
                    (uint8_t)(seg.r * sBright + 0.5f),
                    (uint8_t)(seg.g * sBright + 0.5f),
                    (uint8_t)(seg.b * sBright + 0.5f)
                };
            }
        }
        return;
    }

    int midStart = (int)((numLeds * 0.20f) + 0.5f);
    int midEnd   = numLeds - 1 - midStart;

    if (mode < 3) {
        const ModeConfig& cfg = defaultModes[mode];
        if (cfg.style == 1) { // Center focus (60% active center, ends off)
            for (int i = 0; i < numLeds; i++) {
                if (i >= midStart && i <= midEnd)
                    out[i] = { cfg.r, cfg.g, cfg.b };
                else
                    out[i] = { 0, 0, 0 };
            }
        } else { // Full strip
            for (int i = 0; i < numLeds; i++) {
                out[i] = { cfg.r, cfg.g, cfg.b };
            }
        }
        return;
    }

    if (mode == 3) { // Mode 3: custom RGB
        for (int i = 0; i < numLeds; i++)
            out[i] = { r, g, b };
        return;
    }

    // Dynamic preset index >= 4
    if (mode < presetCount) {
        const auto& p = presets[mode];
        if (p.segmentCount > 0) {
            for (int i = 0; i < numLeds; i++) out[i] = { 0, 0, 0 };
            for (int s = 0; s < p.segmentCount; s++) {
                const auto& seg = p.segments[s];
                int sEnd = seg.start + seg.count;
                if (sEnd > numLeds) sEnd = numLeds;
                float sBright = (float)seg.brightness / 255.0f;
                for (int i = seg.start; i < sEnd; i++) {
                    out[i] = {
                        (uint8_t)(seg.r * sBright + 0.5f),
                        (uint8_t)(seg.g * sBright + 0.5f),
                        (uint8_t)(seg.b * sBright + 0.5f)
                    };
                }
            }
            return;
        } else {
            for (int i = 0; i < numLeds; i++) out[i] = { p.r, p.g, p.b };
            return;
        }
    }

    for (int i = 0; i < numLeds; i++)
        out[i] = { WARM_R, WARM_G, WARM_B };
}

// 256-entry Gamma 2.2 Perceptual Color Correction Lookup Table
static const uint8_t GAMMA_TABLE_22[256] = {
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   2,   2,   2,   2,   2,   2,   3,   3,   3,   3,   4,   4,   4,
    5,   5,   5,   5,   6,   6,   6,   7,   7,   7,   8,   8,   8,   9,   9,   10,
    10,  11,  11,  11,  12,  12,  13,  13,  14,  14,  15,  15,  16,  17,  17,  18,
    18,  19,  20,  20,  21,  21,  22,  23,  23,  24,  25,  25,  26,  27,  28,  28,
    29,  30,  31,  32,  32,  33,  34,  35,  36,  37,  37,  38,  39,  40,  41,  42,
    43,  44,  45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,
    60,  61,  62,  63,  64,  65,  67,  68,  69,  70,  71,  73,  74,  75,  76,  78,
    79,  80,  82,  83,  84,  86,  87,  88,  90,  91,  93,  94,  96,  97,  98, 100,
   101, 103, 104, 106, 107, 109, 111, 112, 114, 115, 117, 119, 120, 122, 124, 125,
   127, 129, 131, 132, 134, 136, 138, 140, 142, 143, 145, 147, 149, 151, 153, 155,
   157, 159, 161, 163, 165, 167, 170, 172, 174, 176, 178, 180, 183, 185, 187, 190,
   192, 194, 197, 199, 201, 204, 206, 209, 211, 213, 216, 218, 221, 223, 226, 228,
   231, 234, 236, 239, 241, 244, 247, 249, 252, 255
};

void render_frame(unsigned long now) {
    if (brightness == 0 && currentAnim == ANIM_NONE && currentBrightness <= 0.01f) {
        strip.clear();
        strip.show();
        for (int i = 0; i < numLeds; i++) {
            renderedLeds[i] = { 0, 0, 0 };
        }
        return;
    }

    float bFactor = 1.0f;
    if (currentAnim == ANIM_NONE && brightness > 0) {
        bFactor = get_ambient_factor(now);
    } else if (currentAnim == ANIM_CROSSFADE) {
        bFactor = get_ambient_factor(now);
    }

    float effBright = currentBrightness * bFactor;
    if (effBright < 0.0f) effBright = 0.0f;
    if (effBright > 255.0f) effBright = 255.0f;
    float brightMult = effBright / 255.0f;

    // Adaptive Software Current Limiter (PSU Brownout Protection)
    if (maxCurrentMa > 0 && brightMult > 0.01f) {
        uint32_t sumRgb = 0;
        for (int i = 0; i < numLeds; i++) {
            sumRgb += currentLeds[i].r + currentLeds[i].g + currentLeds[i].b;
        }
        // Base system: ~120mA (ESP32 CPU + BLE radio) + 1mA quiescent per WS2812B IC
        float baseMa = 120.0f + (float)numLeds * 1.0f;
        // Peak LED consumption: 50mA per LED at full RGB white
        float ledFullMa = ((float)sumRgb / ((float)numLeds * 3.0f * 255.0f)) * ((float)numLeds * 50.0f);
        float estTotalMa = baseMa + (ledFullMa * brightMult);

        if (estTotalMa > (float)maxCurrentMa) {
            float availableForLeds = (float)maxCurrentMa - baseMa;
            if (availableForLeds < 50.0f) availableForLeds = 50.0f;
            float safetyMult = availableForLeds / (ledFullMa * brightMult);
            if (safetyMult < 1.0f) {
                brightMult *= safetyMult;
            }
        }
    }

    for (int i = 0; i < numLeds; i++) {
        uint8_t r = (uint8_t)(currentLeds[i].r * brightMult + 0.5f);
        uint8_t g = (uint8_t)(currentLeds[i].g * brightMult + 0.5f);
        uint8_t b = (uint8_t)(currentLeds[i].b * brightMult + 0.5f);
        renderedLeds[i] = { r, g, b };
        strip.setPixelColor(i, GAMMA_TABLE_22[r], GAMMA_TABLE_22[g], GAMMA_TABLE_22[b]);
    }
    // Clear any extra pixels if previously longer
    for (int i = numLeds; i < MAX_LEDS; i++) {
        strip.setPixelColor(i, 0, 0, 0);
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
    for (int i = 0; i < numLeds; i++) {
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
    for (int i = 0; i < numLeds; i++) {
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

    for (int i = 0; i < numLeds; i++) {
        startLeds[i] = currentLeds[i];
    }

    currentAnim = ANIM_CROSSFADE;
    animStartMs = millis();
    animDurationMs = ANIM_CROSSFADE_MS;
}

void start_identify_animation() {
    currentAnim = ANIM_IDENTIFY;
    animStartMs = millis();
    animDurationMs = 1500;
}

void start_hw_test_animation() {
    currentAnim = ANIM_HW_TEST;
    animStartMs = millis();
    animDurationMs = 3500;
}

void update_animation(unsigned long now) {
    if (now - lastAnimFrameMs < ANIM_FRAME_MS) return; // ~50 FPS target
    lastAnimFrameMs = now;

    if (currentAnim == ANIM_CROSSFADE) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < numLeds; i++) {
            float dNorm = get_normalized_spatial_dist(i, numLeds);
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
            for (int i = 0; i < numLeds; i++) {
                currentLeds[i] = targetLeds[i];
            }
            currentAnim = ANIM_NONE;
        }
    }
    else if (currentAnim == ANIM_CENTER_ON) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < numLeds; i++) {
            float dNorm = get_normalized_spatial_dist(i, numLeds);
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
            for (int i = 0; i < numLeds; i++) {
                currentLeds[i] = targetLeds[i];
            }
            currentAnim = ANIM_NONE;
            breathingBaseMs = now;
        }
    }
    else if (currentAnim == ANIM_CENTER_OFF) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        for (int i = 0; i < numLeds; i++) {
            float dNorm = get_normalized_spatial_dist(i, numLeds);
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
            for (int i = 0; i < numLeds; i++) {
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
    else if (currentAnim == ANIM_IDENTIFY) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        if (finished) {
            currentAnim = ANIM_NONE;
            compute_target_colors(currentMode, customR, customG, customB, currentLeds);
            currentBrightness = (float)brightness;
            render_frame(now);
            return;
        }

        // 3 pulses over 1500ms (500ms period: 250ms ON radiant gold, 250ms OFF)
        bool flashOn = ((elapsed % 500) < 250);
        for (int i = 0; i < numLeds; i++) {
            currentLeds[i] = flashOn ? RgbColor{ 255, 200, 80 } : RgbColor{ 0, 0, 0 };
        }
        currentBrightness = flashOn ? 255.0f : 0.0f;
        render_frame(now);
        return;
    }
    else if (currentAnim == ANIM_HW_TEST) {
        unsigned long elapsed = now - animStartMs;
        bool finished = (elapsed >= animDurationMs);

        if (finished) {
            currentAnim = ANIM_NONE;
            compute_target_colors(currentMode, customR, customG, customB, currentLeds);
            currentBrightness = (float)brightness;
            render_frame(now);
            return;
        }

        // Strip alignment & visual diagnostic:
        // Index 0: RED (Start)
        // Index numLeds/2: GREEN (Center)
        // Index numLeds-1: BLUE (End)
        // Rest: Dim warm amber so all LEDs light up
        int midIdx = numLeds / 2;
        for (int i = 0; i < numLeds; i++) {
            if (i == 0) {
                currentLeds[i] = { 255, 0, 0 };
            } else if (i == midIdx) {
                currentLeds[i] = { 0, 255, 0 };
            } else if (i == numLeds - 1) {
                currentLeds[i] = { 0, 0, 255 };
            } else {
                currentLeds[i] = { 40, 20, 5 };
            }
        }
        currentBrightness = 255.0f;
        render_frame(now);
        return;
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
                 ",\"ver\":\"" + String(FIRMWARE_VERSION) + "\"" +
                 ",\"name\":\"" + String(activeDeviceName) + "\"" +
                 ",\"mac\":\"" + String(macSuffixStr) + "\"" +
                 ",\"leds\":" + String(numLeds) +
                 ",\"max_ma\":" + String(maxCurrentMa) +
                 ",\"trans\":" + String(transitionStyle) +
                 ",\"amb\":" + String(ambientStyle) +
                 ",\"depth\":" + String(ambientDepth) +
                 ",\"preset\":" + String(activePresetIndex) +
                 ",\"segs\":" + String(activeSegmentCount) +
                 ",\"cycle_mask\":" + String(cycleBitmask) + "}";
    pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
    pCharacteristic->notify();
}

// ============================================================================
// TEMPLE LIGHTS HIGH-SPEED OTA ENGINE IMPLEMENTATION
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
    wifiManagerResumeAfterOta();
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
        wifiManagerPauseForOta();
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

void send_modes_hydration_to_app() {
    if (!deviceConnected || pCharacteristic == nullptr) return;

    for (int i = 0; i < 3; i++) {
        const ModeConfig& m = defaultModes[i];
        String pkt = "{\"type\":\"mode_cfg\",\"idx\":" + String(i) +
                     ",\"name\":\"" + String(m.name) + "\"" +
                     ",\"r\":" + String(m.r) +
                     ",\"g\":" + String(m.g) +
                     ",\"b\":" + String(m.b) +
                     ",\"style\":" + String(m.style) +
                     ",\"bright\":" + String(m.brightness) + "}";
        pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
        pCharacteristic->notify();
        delay(35);
    }

    String endPkt = "{\"type\":\"modes_end\"}";
    pCharacteristic->setValue((uint8_t*)endPkt.c_str(), endPkt.length());
    pCharacteristic->notify();
    delay(35);
}

void send_presets_hydration_to_app() {
    if (!deviceConnected || pCharacteristic == nullptr) return;

    for (int i = 0; i < presetCount; i++) {
        const auto& p = presets[i];
        String pkt = "{\"type\":\"preset_item\",\"idx\":" + String(i) +
                     ",\"total\":" + String(presetCount) +
                     ",\"name\":\"" + String(p.name) + "\"" +
                     ",\"bright\":" + String(p.brightness) +
                     ",\"trans\":" + String(p.transitionStyle) +
                     ",\"amb\":" + String(p.ambientStyle) +
                     ",\"depth\":" + String(p.ambientDepth) +
                     ",\"cycle\":" + String(p.cycleEnabled ? "true" : "false") +
                     ",\"r\":" + String(p.r) +
                     ",\"g\":" + String(p.g) +
                     ",\"b\":" + String(p.b) +
                     ",\"segs\":[";
        for (int s = 0; s < p.segmentCount; s++) {
            if (s > 0) pkt += ",";
            const auto& seg = p.segments[s];
            pkt += "{\"start\":" + String(seg.start) +
                   ",\"count\":" + String(seg.count) +
                   ",\"r\":" + String(seg.r) +
                   ",\"g\":" + String(seg.g) +
                   ",\"b\":" + String(seg.b) +
                   ",\"bright\":" + String(seg.brightness) +
                   ",\"fx\":" + String(seg.effect) +
                   ",\"spd\":" + String(seg.speed);
            if (strlen(seg.name) > 0) {
                pkt += ",\"name\":\"" + String(seg.name) + "\"";
            }
            pkt += "}";
        }
        pkt += "]}";
        pCharacteristic->setValue((uint8_t*)pkt.c_str(), pkt.length());
        pCharacteristic->notify();
        delay(35);
    }

    String endPkt = "{\"type\":\"presets_end\",\"count\":" + String(presetCount) +
                    ",\"cycle_mask\":" + String(cycleBitmask) + "}";
    pCharacteristic->setValue((uint8_t*)endPkt.c_str(), endPkt.length());
    pCharacteristic->notify();
    delay(35);
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

int extract_json_segments(const String& json, FirmwareLedSegment* outSegments, int maxSegments) {
    int count = 0;
    int segsIdx = json.indexOf("\"segs\"");
    if (segsIdx == -1) return 0;
    int arrayStart = json.indexOf('[', segsIdx);
    if (arrayStart == -1) return 0;
    int arrayEnd = json.indexOf(']', arrayStart);
    if (arrayEnd == -1) {
        // Resilient fallback: parse up to end of buffer if closing bracket is at frame boundary
        arrayEnd = json.length();
    }

    int objStart = json.indexOf('{', arrayStart);
    while (objStart != -1 && objStart < arrayEnd && count < maxSegments) {
        int objEnd = json.indexOf('}', objStart);
        if (objEnd == -1) {
            if (objStart < arrayEnd) objEnd = arrayEnd;
            else break;
        }
        String obj = json.substring(objStart, objEnd + 1);

        int sVal = extract_json_int(obj, "start", -1);
        if (sVal == -1) sVal = extract_json_int(obj, "s", 0);
        outSegments[count].start = (sVal < 0) ? 0 : sVal;

        int cVal = extract_json_int(obj, "count", -1);
        if (cVal == -1) cVal = extract_json_int(obj, "c", 1);
        outSegments[count].count = (cVal < 1) ? 1 : cVal;

        outSegments[count].r = extract_json_int(obj, "r", 255);
        outSegments[count].g = extract_json_int(obj, "g", 147);
        outSegments[count].b = extract_json_int(obj, "b", 41);

        int brVal = extract_json_int(obj, "bright", -1);
        if (brVal == -1) brVal = extract_json_int(obj, "br", 255);
        outSegments[count].brightness = constrain(brVal, 0, 255);

        outSegments[count].effect = extract_json_int(obj, "fx", 0);
        outSegments[count].speed = extract_json_int(obj, "spd", 5);

        String nameStr = extract_json_string(obj, "name");
        if (nameStr.length() > 0) {
            strncpy(outSegments[count].name, nameStr.c_str(), sizeof(outSegments[count].name) - 1);
            outSegments[count].name[sizeof(outSegments[count].name) - 1] = '\0';
        } else {
            snprintf(outSegments[count].name, sizeof(outSegments[count].name),
                     "Seg %d-%d", outSegments[count].start + 1,
                     outSegments[count].start + outSegments[count].count);
        }

        // Clamp securely to physical strip LED count
        if (outSegments[count].start >= numLeds) {
            outSegments[count].start = (numLeds > 0) ? numLeds - 1 : 0;
        }
        if (outSegments[count].start + outSegments[count].count > numLeds) {
            outSegments[count].count = numLeds - outSegments[count].start;
        }

        count++;
        objStart = json.indexOf('{', objEnd + 1);
    }
    return count;
}

// ============================================================================
// COMMAND HANDLER
// ============================================================================
void handle_command(const String& json) {
    String cmd = extract_json_string(json, "cmd");
    Serial.printf("[BLE] Command: %s\n", cmd.c_str());

    // 1. LED State Controls
    if (cmd == "set_preset") {
        int idx = extract_json_int(json, "idx", -1);
        if (idx >= 0 && idx < presetCount) {
            bool wasOff = (brightness == 0);
            activate_preset(idx);
            if (wasOff) {
                start_center_on_animation();
                record_light_log(true, "App Preset Select");
            } else {
                start_crossfade_animation();
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            notify_state();
            Serial.printf("[Preset] Active → %d ('%s')\n", idx, presets[idx].name);
        }
        return;
    }

    if (cmd == "get_presets") {
        send_presets_hydration_to_app();
        return;
    }

    if (cmd == "save_preset") {
        int idx = extract_json_int(json, "idx", -1);
        if (idx >= 0 && idx < MAX_PRESETS) {
            if (idx >= presetCount) {
                presetCount = idx + 1;
            }
            FirmwarePreset& p = presets[idx];
            String nameStr = extract_json_string(json, "name");
            if (nameStr.length() > 0) {
                strncpy(p.name, nameStr.c_str(), sizeof(p.name) - 1);
                p.name[sizeof(p.name) - 1] = '\0';
            }
            p.brightness = extract_json_int(json, "bright", 255);
            p.transitionStyle = extract_json_int(json, "trans", 0);
            p.ambientStyle = extract_json_int(json, "amb", 1);
            p.ambientDepth = extract_json_int(json, "depth", 6);
            p.cycleEnabled = extract_json_bool(json, "cycle", true);
            p.r = extract_json_int(json, "r", 255);
            p.g = extract_json_int(json, "g", 147);
            p.b = extract_json_int(json, "b", 41);

            int segCount = extract_json_segments(json, p.segments, MAX_SEGMENTS_PER_PRESET);
            p.segmentCount = segCount;

            save_presets_to_nvs();

            if (idx < 3) {
                strncpy(defaultModes[idx].name, p.name, sizeof(defaultModes[idx].name) - 1);
                defaultModes[idx].brightness = p.brightness;
                defaultModes[idx].r = p.r;
                defaultModes[idx].g = p.g;
                defaultModes[idx].b = p.b;
                save_modes_to_nvs();
            }

            if (idx == activePresetIndex) {
                activate_preset(idx);
                start_crossfade_animation();
                notify_state();
            }

            send_presets_hydration_to_app();
            Serial.printf("[Preset] Saved Preset %d ('%s', %d segs, cycle=%d)\n",
                          idx, p.name, p.segmentCount, p.cycleEnabled ? 1 : 0);
        }
        return;
    }

    if (cmd == "set_segs") {
        activeSegmentCount = extract_json_segments(json, activeSegments, MAX_ACTIVE_SEGMENTS);
        currentMode = 3;
        start_crossfade_animation();
        notify_state();
        Serial.printf("[Segment] Live configured %d segments\n", activeSegmentCount);
        return;
    }

    if (cmd == "set_cycle") {
        cycleBitmask = (uint16_t)extract_json_int(json, "mask", 0x07);
        for (int i = 0; i < presetCount; i++) {
            presets[i].cycleEnabled = (cycleBitmask & (1 << i)) != 0;
        }
        save_presets_to_nvs();
        send_presets_hydration_to_app();
        Serial.printf("[Cycle] Mask updated: 0x%02X\n", cycleBitmask);
        return;
    }

    if (cmd == "reset_presets") {
        reset_presets_to_defaults();
        activate_preset(0);
        start_crossfade_animation();
        notify_state();
        send_presets_hydration_to_app();
        return;
    }

    if (cmd == "set_mode") {
        int m = extract_json_int(json, "mode", -1);
        if (m >= 0 && m <= 3) {
            bool wasOff = (brightness == 0);
            activeSegmentCount = 0; // Clear segment overrides for standard modes
            currentMode = m;
            if (m < 3) {
                targetBrightness = (defaultModes[m].brightness > 0) ? defaultModes[m].brightness : 255;
                activeBrightness = targetBrightness;
                if (!wasOff) brightness = targetBrightness;
            } else {
                targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
            }
            if (wasOff) {
                brightness = targetBrightness;
                start_center_on_animation();
                record_light_log(true, "App Mode Change");
            } else {
                start_crossfade_animation();
            }
            stateDirty = true;
            lastStateChangeMs = millis();
            notify_state();
            Serial.printf("[LED] Mode → %d (segments cleared)\n", currentMode);
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
            activeSegmentCount = 0; // Clear segment overrides for full strip custom RGB
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
            Serial.printf("[LED] RGB → (%d,%d,%d) Mode 3 (segments cleared)\n", customR, customG, customB);
        }
        return;
    }

    if (cmd == "on") {
        uint8_t nextMode = get_next_cycle_preset(currentMode);
        activate_preset(nextMode);
        start_center_on_animation();
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        record_light_log(true, "App Turn ON");
        Serial.printf("[LED] Power ON → Mode %d (Brightness %d)\n", currentMode, brightness);
        return;
    }

    if (cmd == "next_mode") {
        uint8_t nextMode = get_next_cycle_preset(currentMode);
        activate_preset(nextMode);
        bool wasOff = (currentBrightness <= 0.5f);
        if (wasOff) {
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

    // 1b. Multi-Device Identity & Naming Commands
    if (cmd == "set_name") {
        String newName = extract_json_string(json, "name");
        newName.trim();
        if (newName.length() > 0 && newName.length() <= 32) {
            strncpy(activeDeviceName, newName.c_str(), sizeof(activeDeviceName) - 1);
            activeDeviceName[sizeof(activeDeviceName) - 1] = '\0';
            prefs.begin("tl", false);
            prefs.putString("dev_name", activeDeviceName);
            prefs.end();
            NimBLEDevice::setDeviceName(activeDeviceName);
            notify_state();
            Serial.printf("[BLE] Device name updated to '%s'\n", activeDeviceName);
        }
        return;
    }

    if (cmd == "reset_name") {
        strncpy(activeDeviceName, defaultDeviceName, sizeof(activeDeviceName) - 1);
        activeDeviceName[sizeof(activeDeviceName) - 1] = '\0';
        prefs.begin("tl", false);
        if (prefs.isKey("dev_name")) {
            prefs.remove("dev_name");
        }
        prefs.end();
        NimBLEDevice::setDeviceName(activeDeviceName);
        notify_state();
        Serial.printf("[BLE] Device name reset to default '%s'\n", activeDeviceName);
        return;
    }

    if (cmd == "identify") {
        start_identify_animation();
        Serial.println("[BLE] Triggered Identify / Blink animation");
        return;
    }

    // 1c. Hardware & LED Count Configuration: {"cmd":"set_hw_config","leds":180,"max_ma":3000}
    if (cmd == "set_hw_config") {
        int newLeds = extract_json_int(json, "leds", -1);
        int newMaxMa = extract_json_int(json, "max_ma", -1);
        bool changed = false;

        if (newLeds >= 10 && newLeds <= MAX_LEDS) {
            numLeds = (uint16_t)newLeds;
            strip.updateLength(numLeds);
            strip.clear();
            strip.show();
            compute_target_colors(currentMode, customR, customG, customB, currentLeds);
            changed = true;
            Serial.printf("[HW] Active LEDs updated to %d\n", numLeds);
        }
        if (newMaxMa >= 500 && newMaxMa <= 15000) {
            maxCurrentMa = (uint16_t)newMaxMa;
            changed = true;
            Serial.printf("[HW] Max current safety budget set to %d mA\n", maxCurrentMa);
        }
        if (changed) {
            save_hw_config();
            render_frame(millis());
            notify_state();
        }
        return;
    }

    // 1d. Animation & Sacred Aura Configuration: {"cmd":"set_anim_config","trans":1,"ambient":2,"depth":8}
    if (cmd == "set_anim_config") {
        int newTrans = extract_json_int(json, "trans", -1);
        int newAmb = extract_json_int(json, "ambient", -1);
        int newDepth = extract_json_int(json, "depth", -1);
        bool changed = false;

        if (newTrans >= 0 && newTrans <= 2) {
            transitionStyle = (uint8_t)newTrans;
            changed = true;
        }
        if (newAmb >= 0 && newAmb <= 2) {
            ambientStyle = (uint8_t)newAmb;
            changed = true;
        }
        if (newDepth >= 1 && newDepth <= 30) {
            ambientDepth = (uint8_t)newDepth;
            changed = true;
        }
        if (changed) {
            save_anim_config();
            render_frame(millis());
            notify_state();
            Serial.printf("[ANIM] Config updated: trans=%d, amb=%d, depth=%d%%\n", transitionStyle, ambientStyle, ambientDepth);
        }
        return;
    }

    // 1e. Hardware Diagnostic Test: {"cmd":"hw_test"}
    if (cmd == "hw_test") {
        start_hw_test_animation();
        Serial.println("[HW] Triggered strip alignment check");
        return;
    }

    // 2. Time Synchronization: {"cmd":"time","y":2026,"mon":9,"d":21,"h":11,"m":30,"s":0,"epoch":...}
    if (cmd == "time") {
        int tzMin = extract_json_int(json, "tz_min", -9999);
        if (tzMin >= -720 && tzMin <= 720) {
            wifiManagerSetTimezoneOffset((int16_t)tzMin);
        } else {
            wifiManagerApplyTimezone(wifiManagerGetTimezoneOffset());
        }

        uint32_t epoch = (uint32_t)extract_json_int(json, "epoch", 0);
        int y = extract_json_int(json, "y", 0);
        int mon = extract_json_int(json, "mon", 0);
        int d = extract_json_int(json, "d", 0);
        int h = extract_json_int(json, "h", 0);
        int m = extract_json_int(json, "m", 0);
        int s = extract_json_int(json, "s", 0);
        int w = extract_json_int(json, "w", 1);

        time_t t = 0;
        if (epoch > 1700000000) {
            t = (time_t)epoch;
        } else if (y >= 2024 && mon >= 1 && mon <= 12 && d >= 1 && d <= 31) {
            struct tm tmInfo;
            memset(&tmInfo, 0, sizeof(tmInfo));
            tmInfo.tm_year = y - 1900;
            tmInfo.tm_mon = mon - 1;
            tmInfo.tm_mday = d;
            tmInfo.tm_hour = h;
            tmInfo.tm_min = m;
            tmInfo.tm_sec = s;
            tmInfo.tm_wday = (w % 7);
            tmInfo.tm_isdst = -1;
            t = mktime(&tmInfo);
        }

        if (t > 1700000000) {
            struct timeval tv = { .tv_sec = t, .tv_usec = 0 };
            settimeofday(&tv, NULL);
            timeIsSynchronized = true;

            struct tm tmLocal;
            localtime_r(&t, &tmLocal);

            Serial.printf("[Clock] Synchronized to %04d-%02d-%02d %02d:%02d:%02d (Mumbai IST)\n",
                          tmLocal.tm_year + 1900, tmLocal.tm_mon + 1, tmLocal.tm_mday,
                          tmLocal.tm_hour, tmLocal.tm_min, tmLocal.tm_sec);

            if (deviceConnected && pCharacteristic != nullptr) {
                String ack = "{\"type\":\"time_synced\",\"epoch\":" + String((uint32_t)t) + "}";
                pCharacteristic->setValue((uint8_t*)ack.c_str(), ack.length());
                pCharacteristic->notify();
            }

            evaluate_schedules();
        }
        return;
    }

    // 2b. WiFi Provisioning & Autonomous Network Clock
    if (cmd == "wifi_scan") {
        wifiManagerStartScan();
        return;
    }
    if (cmd == "wifi_connect") {
        String ssid = extract_json_string(json, "ssid");
        String psk = extract_json_string(json, "psk");
        bool save = extract_json_bool(json, "save", true);
        wifiManagerConnect(ssid, psk, save);
        return;
    }
    if (cmd == "wifi_forget") {
        wifiManagerForget();
        return;
    }
    if (cmd == "wifi_status") {
        wifiManagerQueryStatus();
        return;
    }
    if (cmd == "ntp_sync") {
        wifiManagerTriggerNtp();
        return;
    }

    // 3. Schedules Hydration & CRUD
    if (cmd == "get_scheds" || cmd == "sync") {
        send_schedule_hydration_to_app();
        if (cmd == "sync") {
            send_modes_hydration_to_app();
        }
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
        evaluate_schedules();
        return;
    }

    if (cmd == "toggle_sched") {
        String id = extract_json_string(json, "id");
        bool en = extract_json_bool(json, "en", true);
        for (int i = 0; i < scheduleCount; i++) {
            if (strcmp(schedules[i].id, id.c_str()) == 0) {
                schedules[i].isEnabled = en;
                save_schedules_to_nvs();
                evaluate_schedules();
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
            evaluate_schedules();
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

    // 6. Default Boot Modes Management
    if (cmd == "get_modes") {
        send_modes_hydration_to_app();
        return;
    }

    if (cmd == "save_mode") {
        int idx = extract_json_int(json, "idx", -1);
        if (idx >= 0 && idx < 3) {
            String name = extract_json_string(json, "name");
            int r = extract_json_int(json, "r", defaultModes[idx].r);
            int g = extract_json_int(json, "g", defaultModes[idx].g);
            int b = extract_json_int(json, "b", defaultModes[idx].b);
            int style = extract_json_int(json, "style", defaultModes[idx].style);
            int bright = extract_json_int(json, "bright", defaultModes[idx].brightness);

            if (!name.isEmpty()) {
                strncpy(defaultModes[idx].name, name.c_str(), sizeof(defaultModes[idx].name) - 1);
                defaultModes[idx].name[sizeof(defaultModes[idx].name) - 1] = '\0';
            }
            defaultModes[idx].r = constrain(r, 0, 255);
            defaultModes[idx].g = constrain(g, 0, 255);
            defaultModes[idx].b = constrain(b, 0, 255);
            defaultModes[idx].style = (style == 1) ? 1 : 0;
            defaultModes[idx].brightness = constrain(bright, 1, 255);

            save_modes_to_nvs();

            // If currently running this mode, live-update the LEDs
            if (currentMode == idx && (brightness > 0 || currentBrightness > 0.5f)) {
                targetBrightness = defaultModes[idx].brightness;
                brightness = targetBrightness;
                activeBrightness = targetBrightness;
                start_crossfade_animation();
                notify_state();
            }

            send_modes_hydration_to_app();
            Serial.printf("[Mode] Saved Mode %d ('%s', rgb=%d,%d,%d, style=%d, bright=%d)\n",
                          idx, defaultModes[idx].name, defaultModes[idx].r, defaultModes[idx].g, defaultModes[idx].b,
                          defaultModes[idx].style, defaultModes[idx].brightness);
        }
        return;
    }

    if (cmd == "reset_modes") {
        reset_modes_to_defaults();
        if (currentMode < 3 && (brightness > 0 || currentBrightness > 0.5f)) {
            targetBrightness = defaultModes[currentMode].brightness;
            brightness = targetBrightness;
            activeBrightness = targetBrightness;
            start_crossfade_animation();
            notify_state();
        }
        send_modes_hydration_to_app();
        Serial.println("[Mode] Restored factory default modes");
        return;
    }

    // 7. Over-The-Air (OTA) is handled via high-speed characteristics under primary SERVICE_UUID

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
        if (currentAnim == ANIM_IDENTIFY || currentAnim == ANIM_HW_TEST) {
            currentAnim = ANIM_NONE;
            compute_target_colors(currentMode, customR, customG, customB, currentLeds);
            currentBrightness = (float)brightness;
            render_frame(millis());
        }
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
                activeSegmentCount = 0; // Clear segment overrides for direct mode shortcut
                currentMode = b;
                if (b < 3) {
                    targetBrightness = (defaultModes[b].brightness > 0) ? defaultModes[b].brightness : 255;
                    activeBrightness = targetBrightness;
                    if (!wasOff) brightness = targetBrightness;
                } else {
                    targetBrightness = (activeBrightness > 0) ? activeBrightness : 255;
                }
                if (wasOff) {
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
static bool bootScheduleEvaluated = false;

bool is_schedule_in_range(const ScheduleItem& s, int curDay, int curHour, int curMin) {
    if (!s.isEnabled || !s.hasTurnOn || !s.hasTurnOff) return false;

    int onMins  = s.turnOnHour * 60 + s.turnOnMinute;
    int offMins = s.turnOffHour * 60 + s.turnOffMinute;
    int curMins = curHour * 60 + curMin;

    if (onMins == offMins) return false;

    if (onMins < offMins) {
        // Same-day schedule (e.g. 18:30 to 21:00)
        bool dayMatches = (s.repeatDaysMask & (1 << curDay)) != 0;
        return dayMatches && (curMins >= onMins && curMins < offMins);
    } else {
        // Overnight schedule (e.g. 18:00 to 06:00)
        if (curMins >= onMins) {
            // Started today before midnight
            return (s.repeatDaysMask & (1 << curDay)) != 0;
        } else if (curMins < offMins) {
            // Started yesterday before midnight
            int prevDay = (curDay == 1) ? 7 : (curDay - 1);
            return (s.repeatDaysMask & (1 << prevDay)) != 0;
        }
        return false;
    }
}

static void activate_scheduled_mode(ScheduleItem& s, const char* reason) {
    currentMode = s.targetMode;
    targetBrightness = s.targetBrightness > 0 ? s.targetBrightness : 255;
    brightness = targetBrightness;
    if (s.targetMode == 3) {
        customR = (s.targetR > 0 || s.targetG > 0 || s.targetB > 0) ? s.targetR : 255;
        customG = s.targetG;
        customB = s.targetB;
    }
    if (currentAnim == ANIM_NONE && brightness > 0 && currentBrightness > 0.5f) {
        start_crossfade_animation();
    } else {
        start_center_on_animation();
    }
    save_state();
    notify_state();
    record_light_log(true, s.name);
    Serial.printf("[Sched] ⏰ Activated schedule (%s): %s (Mode %d, Bright %d)\n",
                  reason, s.name, currentMode, brightness);
}

void evaluate_schedules() {
    if (!timeIsSynchronized) return;

    time_t now = time(NULL);
    struct tm tmInfo;
    localtime_r(&now, &tmInfo);

    int curHour = tmInfo.tm_hour;
    int curMin  = tmInfo.tm_min;
    int curDay  = tmInfo.tm_wday == 0 ? 7 : tmInfo.tm_wday; // 1=Mon .. 7=Sun

    bool isBootCheck = !bootScheduleEvaluated;

    for (int i = 0; i < scheduleCount; i++) {
        ScheduleItem& s = schedules[i];
        if (!s.isEnabled) continue;

        int onMins  = s.turnOnHour * 60 + s.turnOnMinute;
        int offMins = s.turnOffHour * 60 + s.turnOffMinute;
        int curMins = curHour * 60 + curMin;

        // Determine session key day (accounting for overnight schedules starting yesterday)
        int startDay = curDay;
        if (s.hasTurnOff && onMins > offMins && curMins < offMins) {
            startDay = (curDay == 1) ? 7 : (curDay - 1);
        }

        char onKey[24];
        snprintf(onKey, sizeof(onKey), "ON_%d_%02d_%02d", startDay, s.turnOnHour, s.turnOnMinute);

        char offKey[24];
        snprintf(offKey, sizeof(offKey), "OFF_%d_%02d_%02d", tmInfo.tm_mday, curHour, curMin);

        // 1. Turn OFF trigger (when scheduled off time is reached)
        if (s.hasTurnOff && curHour == s.turnOffHour && curMin == s.turnOffMinute) {
            if (strcmp(s.lastTriggeredKey, offKey) != 0) {
                strncpy(s.lastTriggeredKey, offKey, sizeof(s.lastTriggeredKey) - 1);
                if (brightness > 0 || currentBrightness > 0.5f) {
                    start_center_off_animation();
                }
                save_state();
                notify_state();
                record_light_log(false, s.name);
                Serial.printf("[Sched] ⏰ Triggered OFF: %s\n", s.name);
            }
            continue;
        }

        // 2. Turn ON & Range Check
        if (s.hasTurnOn) {
            bool inRange = s.hasTurnOff ? is_schedule_in_range(s, curDay, curHour, curMin) : false;
            bool exactMinute = (curHour == s.turnOnHour && curMin == s.turnOnMinute && (s.repeatDaysMask & (1 << curDay)));

            // Activate if in range and (session not triggered yet OR this is the first boot evaluation),
            // OR if the exact start minute matched.
            if ((inRange && (strcmp(s.lastTriggeredKey, onKey) != 0 || isBootCheck)) ||
                (exactMinute && strcmp(s.lastTriggeredKey, onKey) != 0)) {
                strncpy(s.lastTriggeredKey, onKey, sizeof(s.lastTriggeredKey) - 1);
                activate_scheduled_mode(s, isBootCheck ? "Boot In-Range" : "Scheduled");
            }
        }
    }

    bootScheduleEvaluated = true;
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
    load_hw_and_anim_config();
    load_modes_from_nvs();
    load_presets_from_nvs();
    load_schedules_from_nvs();
    load_logs_from_nvs();

    // Power-cycle mode advancement through cycle-enabled presets
    uint8_t lastMode = currentMode;
    uint8_t nextMode = get_next_cycle_preset(lastMode);
    currentMode = nextMode;
    activate_preset(currentMode);
    save_state();     // Persist immediately so subsequent boots advance from here

    Serial.printf("[Boot] Last Mode: %d -> Active Mode: %d | Brightness: %d\n",
                  lastMode, currentMode, brightness);

    record_light_log(true, "Power Cycle Boot");

    // Dynamic Device Identity: Derive default name from Bluetooth MAC address suffix
    uint8_t baseMac[6];
    esp_read_mac(baseMac, ESP_MAC_BT);
    snprintf(macSuffixStr, sizeof(macSuffixStr), "%02X%02X", baseMac[4], baseMac[5]);
    snprintf(defaultDeviceName, sizeof(defaultDeviceName), "Temple Lights %s", macSuffixStr);

    prefs.begin("tl", true);
    String savedName = "";
    if (prefs.isKey("dev_name")) {
        savedName = prefs.getString("dev_name", "");
    }
    prefs.end();

    if (savedName.length() > 0) {
        strncpy(activeDeviceName, savedName.c_str(), sizeof(activeDeviceName) - 1);
        activeDeviceName[sizeof(activeDeviceName) - 1] = '\0';
    } else {
        strncpy(activeDeviceName, defaultDeviceName, sizeof(activeDeviceName) - 1);
        activeDeviceName[sizeof(activeDeviceName) - 1] = '\0';
    }

    // Initialize NimBLE Server FIRST so radio setup does not block animation
    NimBLEDevice::init(activeDeviceName);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setMTU(517);

    pBleServer = NimBLEDevice::createServer();
    pBleServer->setCallbacks(new ServerCallbacks());

    // 1. Primary Temple Lights Service (Lighting Control, Telemetry, Schedules, Logs)
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

    // 2. Dedicated High-Speed OTA Service (Isolated GATT Service matching Boturo Go architecture)
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

    // Clean, standard-compliant advertising: Only advertise primary SERVICE_UUID
    // (Flags 3B + 128-bit UUID 18B = 21B <= 31B max; Name in scan response)
    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(SERVICE_UUID);
    pAdv->setScanResponse(true);
    pAdv->start();

    Serial.printf("[BLE] Advertising as '%s'\n", activeDeviceName);
    Serial.printf("[BLE] Primary Service: %s\n", SERVICE_UUID);
    Serial.printf("[BLE] OTA Service:     %s\n", OTA_SERVICE_UUID);
    Serial.println("[BLE] Ready. Waiting for app connection...");

    // Initialize LED strip at full 255 scale and start Center-Out Bloom animation
    strip.begin();
    strip.setBrightness(255);
    start_center_on_animation();

    // Initialize WiFi Provisioner & Autonomous NTP Clock Engine
    wifiManagerInit(pCharacteristic);
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

    // Drive non-blocking WiFi manager & autonomous SNTP clock engine
    wifiManagerTick(now);

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
