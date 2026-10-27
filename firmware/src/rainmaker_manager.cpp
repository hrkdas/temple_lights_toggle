#include "rainmaker_manager.h"
#include <RMaker.h>
#include <esp_rmaker_user_mapping.h>
#include <esp_rmaker_mqtt.h>
#include <esp_rmaker_factory.h>
#include <esp_rmaker_core.h>
#include <WiFi.h>
#include <math.h>

// Forward declarations & externs from main.cpp
extern uint8_t brightness;
extern uint8_t activeBrightness;
extern uint8_t currentMode;
extern uint8_t customR;
extern uint8_t customG;
extern uint8_t customB;
extern int activeSegmentCount;
extern bool stateDirty;
extern unsigned long lastStateChangeMs;

extern void activate_preset(uint8_t idx);
extern void start_center_on_animation();
extern void start_center_off_animation();
extern void start_crossfade_animation();
extern void notify_state();
extern void record_light_log(bool state, const char* trigger);
extern bool wifiManagerIsConnected();
extern bool wifiManagerIsInternetOk();

// ============================================================================
// INTERNAL STATE
// ============================================================================
static Node s_node;
static LightBulb* s_pLight = nullptr;
static bool s_isInitialized = false;
static bool s_isStarted = false;
static bool s_otaPaused = false;
static unsigned long s_lastInitCheckMs = 0;
static unsigned long s_lastReportMs = 0;

// State cache for RainMaker params
static bool s_cachedPower = true;
static int  s_cachedBrightness = 100;
static int  s_cachedHue = 30;
static int  s_cachedSaturation = 80;
static int  s_cachedCct = 2700;

// Claiming & MQTT Diagnostics
static int  s_claimState = 0; // 0=unknown/reset, 1=started, 2=success, 3=failed
static bool s_isClaimed = false;

// Flag to prevent echo loops when RainMaker itself writes values
static bool s_inRainmakerCallback = false;
static unsigned long s_lastCloudWriteMs = 0;

static void rmaker_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data) {
    if (event_base == RMAKER_EVENT) {
        switch (event_id) {
            case RMAKER_EVENT_INIT_DONE:
                Serial.println("[RMAKER] Event: Core Initialized");
                break;
            case RMAKER_EVENT_CLAIM_STARTED:
                Serial.println("[RMAKER] Event: Device Claiming Started");
                s_claimState = 1;
                break;
            case RMAKER_EVENT_CLAIM_SUCCESSFUL:
                Serial.println("[RMAKER] Event: Device Claiming Successful");
                s_claimState = 2;
                s_isClaimed = true;
                break;
            case RMAKER_EVENT_CLAIM_FAILED:
                Serial.println("[RMAKER] Event: Device Claiming Failed");
                s_claimState = 3;
                break;
            case RMAKER_EVENT_USER_NODE_MAPPING_DONE:
                Serial.printf("[RMAKER] Event: User-Node Mapping Done on Node (User: %s)\n",
                              event_data ? (char*)event_data : "none");
                break;
            default:
                break;
        }
    }
}

// ============================================================================
// COLOR CONVERSIONS (HSV -> RGB & KELVIN -> RGB)
// ============================================================================

static void hsvToRgb(int h, int s, int v, uint8_t &r, uint8_t &g, uint8_t &b) {
    float hf = (float)(h % 360) / 60.0f;
    float sf = (float)constrain(s, 0, 100) / 100.0f;
    float vf = (float)constrain(v, 0, 100) / 100.0f;

    int i = (int)floor(hf);
    float f = hf - i;
    float p = vf * (1.0f - sf);
    float q = vf * (1.0f - sf * f);
    float t = vf * (1.0f - sf * (1.0f - f));

    float rf = 0, gf = 0, bf = 0;
    switch (i) {
        case 0: rf = vf; gf = t;  bf = p;  break;
        case 1: rf = q;  gf = vf; bf = p;  break;
        case 2: rf = p;  gf = vf; bf = t;  break;
        case 3: rf = p;  gf = q;  bf = vf; break;
        case 4: rf = t;  gf = p;  bf = vf; break;
        default:rf = vf; gf = p;  bf = q;  break;
    }

    r = (uint8_t)constrain((int)round(rf * 255.0f), 0, 255);
    g = (uint8_t)constrain((int)round(gf * 255.0f), 0, 255);
    b = (uint8_t)constrain((int)round(bf * 255.0f), 0, 255);
}

static void rgbToHsv(uint8_t r, uint8_t g, uint8_t b, int &h, int &s, int &v) {
    float rf = (float)r / 255.0f;
    float gf = (float)g / 255.0f;
    float bf = (float)b / 255.0f;

    float maxVal = fmaxf(rf, fmaxf(gf, bf));
    float minVal = fminf(rf, fminf(gf, bf));
    float delta = maxVal - minVal;

    v = (int)round(maxVal * 100.0f);

    if (maxVal < 0.0001f || delta < 0.0001f) {
        s = 0;
        h = 0;
        return;
    }

    s = (int)round((delta / maxVal) * 100.0f);

    float hf = 0.0f;
    if (rf >= maxVal) {
        hf = (gf - bf) / delta;
    } else if (gf >= maxVal) {
        hf = 2.0f + (bf - rf) / delta;
    } else {
        hf = 4.0f + (rf - gf) / delta;
    }

    hf *= 60.0f;
    if (hf < 0.0f) hf += 360.0f;
    h = (int)round(hf) % 360;
}

// Tanner Helland Planckian Blackbody Locus Algorithm (2000K to 6500K)
static void kelvinToRgb(int kelvin, uint8_t &r, uint8_t &g, uint8_t &b) {
    float temp = (float)constrain(kelvin, 2000, 6500) / 100.0f;

    // Red
    float rf = 255.0f;
    if (temp > 66.0f) {
        float r_calc = temp - 60.0f;
        rf = 329.698727446f * pow(r_calc, -0.1332047592f);
    }

    // Green
    float gf = 0.0f;
    if (temp <= 66.0f) {
        gf = 99.4708025861f * log(temp) - 161.1195681661f;
    } else {
        float g_calc = temp - 60.0f;
        gf = 288.1221695283f * pow(g_calc, -0.0755148492f);
    }

    // Blue
    float bf = 0.0f;
    if (temp >= 66.0f) {
        bf = 255.0f;
    } else if (temp > 19.0f) {
        float b_calc = temp - 10.0f;
        bf = 138.5177312231f * log(b_calc) - 305.0447927307f;
    }

    r = (uint8_t)constrain((int)round(rf), 0, 255);
    g = (uint8_t)constrain((int)round(gf), 0, 255);
    b = (uint8_t)constrain((int)round(bf), 0, 255);
}

// Approximate closest Kelvin given RGB
static int rgbToKelvinEstimate(uint8_t r, uint8_t g, uint8_t b) {
    if (r == 255 && g < 160 && b < 70) return 2200; // Warm Amber / Diya
    if (r == 255 && g < 195 && b < 140) return 2700; // Warm White
    if (r >= 240 && g >= 210 && b > 180 && b < 240) return 4000; // Natural
    if (r >= 235 && g >= 235 && b >= 240) return 6500; // Pure White
    return 2700;
}

// ============================================================================
// RAINMAKER WRITE CALLBACK (Incoming Commands from Google Home / RainMaker Cloud)
// ============================================================================
static void rainmakerWriteCallback(Device *device, Param *param, const param_val_t val, void *priv_data, write_ctx_t *ctx) {
    if (!device || !param) return;

    const char* paramName = param->getParamName();
    Serial.printf("[RMAKER] Incoming write for param: %s\n", paramName);

    s_inRainmakerCallback = true;

    if (strcmp(paramName, ESP_RMAKER_DEF_POWER_NAME) == 0) {
        bool targetPower = val.val.b;
        s_cachedPower = targetPower;
        Serial.printf("[RMAKER] Power -> %s\n", targetPower ? "ON" : "OFF");

        if (targetPower) {
            if (brightness == 0) {
                brightness = (activeBrightness > 0) ? activeBrightness : 255;
                start_center_on_animation();
                record_light_log(true, "Google Home ON");
            }
        } else {
            if (brightness > 0) {
                start_center_off_animation();
                record_light_log(false, "Google Home OFF");
            }
        }
        param->updateAndReport(val);
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
    }
    else if (strcmp(paramName, ESP_RMAKER_DEF_BRIGHTNESS_NAME) == 0) {
        int percent = constrain(val.val.i, 0, 100);
        s_cachedBrightness = percent;
        uint8_t scaledBright = (uint8_t)map(percent, 0, 100, 0, 255);
        Serial.printf("[RMAKER] Brightness -> %d%% (%d/255)\n", percent, scaledBright);

        if (scaledBright == 0) {
            if (brightness > 0) {
                start_center_off_animation();
            }
        } else {
            bool wasOff = (brightness == 0);
            activeBrightness = scaledBright;
            brightness = scaledBright;
            if (wasOff) {
                start_center_on_animation();
            } else {
                start_crossfade_animation();
            }
        }
        param->updateAndReport(val);
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
    }
    else if (strcmp(paramName, ESP_RMAKER_DEF_HUE_NAME) == 0) {
        s_cachedHue = constrain(val.val.i, 0, 360);
        uint8_t r, g, b;
        hsvToRgb(s_cachedHue, s_cachedSaturation, 100, r, g, b);
        activeSegmentCount = 0; // Clear segments for full strip color
        customR = r; customG = g; customB = b;
        currentMode = 3; // Custom RGB mode

        if (brightness == 0) {
            brightness = (activeBrightness > 0) ? activeBrightness : 255;
            start_center_on_animation();
        } else {
            start_crossfade_animation();
        }
        param->updateAndReport(val);
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        Serial.printf("[RMAKER] Hue -> %d (RGB: %d,%d,%d)\n", s_cachedHue, r, g, b);
    }
    else if (strcmp(paramName, ESP_RMAKER_DEF_SATURATION_NAME) == 0) {
        s_cachedSaturation = constrain(val.val.i, 0, 100);
        uint8_t r, g, b;
        hsvToRgb(s_cachedHue, s_cachedSaturation, 100, r, g, b);
        activeSegmentCount = 0;
        customR = r; customG = g; customB = b;
        currentMode = 3;

        if (brightness == 0) {
            brightness = (activeBrightness > 0) ? activeBrightness : 255;
            start_center_on_animation();
        } else {
            start_crossfade_animation();
        }
        param->updateAndReport(val);
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        Serial.printf("[RMAKER] Saturation -> %d%% (RGB: %d,%d,%d)\n", s_cachedSaturation, r, g, b);
    }
    else if (strcmp(paramName, ESP_RMAKER_DEF_CCT_NAME) == 0) {
        s_cachedCct = constrain(val.val.i, 2000, 6500);
        uint8_t r, g, b;
        kelvinToRgb(s_cachedCct, r, g, b);
        activeSegmentCount = 0;
        customR = r; customG = g; customB = b;
        currentMode = 3;

        if (brightness == 0) {
            brightness = (activeBrightness > 0) ? activeBrightness : 255;
            start_center_on_animation();
        } else {
            start_crossfade_animation();
        }
        param->updateAndReport(val);
        stateDirty = true;
        lastStateChangeMs = millis();
        notify_state();
        Serial.printf("[RMAKER] CCT -> %dK (RGB: %d,%d,%d)\n", s_cachedCct, r, g, b);
    }

    s_lastCloudWriteMs = millis();
    s_inRainmakerCallback = false;
}

// ============================================================================
// LIFECYCLE & TICK
// ============================================================================

void rainmakerManagerInit(const char* deviceName) {
    if (s_isInitialized) return;

    Serial.println("[RMAKER] Initializing ESP RainMaker Node & LightBulb Device...");

    // Configure RainMaker
    RMaker.setTimeSync(false); // We already manage autonomous NTP clock in wifi_manager
    esp_event_handler_register(RMAKER_EVENT, ESP_EVENT_ANY_ID, &rmaker_event_handler, NULL);
    s_node = RMaker.initNode(deviceName ? deviceName : "Temple Lights", "LightBulb");

    // Standard LightBulb device
    s_pLight = new LightBulb("Light", nullptr, (brightness > 0));
    if (!s_pLight) {
        Serial.println("[RMAKER] ERROR: Failed to allocate LightBulb device");
        return;
    }

    s_pLight->addCb(rainmakerWriteCallback);

    // Register Google Home Trait parameters
    s_pLight->addBrightnessParam((int)map(brightness, 0, 255, 0, 100));
    s_pLight->addHueParam(30);
    s_pLight->addSaturationParam(80);
    s_pLight->addCCTParam(2700);

    // Add device to node
    s_node.addDevice(*s_pLight);

    s_isInitialized = true;
    Serial.println("[RMAKER] LightBulb device registered. Ready to start when internet is verified.");
}

void rainmakerManagerTick(unsigned long nowMs) {
    if (s_otaPaused) return;

    // Check internet connection and start RainMaker cloud task
    if (!s_isStarted && wifiManagerIsInternetOk()) {
        if (nowMs - s_lastInitCheckMs > 3000) {
            s_lastInitCheckMs = nowMs;
            if (!s_isInitialized) {
                rainmakerManagerInit("Temple Lights");
            }
            if (s_isInitialized) {
                Serial.println("[RMAKER] Internet verified. Starting ESP RainMaker cloud agent...");
                esp_err_t err = RMaker.start();
                if (err == ESP_OK) {
                    s_isStarted = true;
                    Serial.println("[RMAKER] RainMaker cloud agent running successfully.");
                } else {
                    Serial.printf("[RMAKER] RMaker.start() returned error 0x%X\n", err);
                }
            }
        }
    }
}

// ============================================================================
// STATE SYNCHRONIZATION (Hardware/BLE/Schedules -> RainMaker Cloud)
// ============================================================================
void rainmakerManagerReportState(bool is_on, uint8_t bright, uint8_t r, uint8_t g, uint8_t b, int kelvin, int presetIdx) {
    if (!s_isStarted || !s_pLight || s_otaPaused || s_inRainmakerCallback) return;

    // Debounce state reporting to avoid flooding MQTT
    unsigned long now = millis();
    if (now - s_lastReportMs < 150) return;
    if (now - s_lastCloudWriteMs < 500) return; // Prevent echo loop from recent cloud write
    s_lastReportMs = now;

    int brightPercent = (int)map(bright, 0, 255, 0, 100);

    s_pLight->updateAndReportParam(ESP_RMAKER_DEF_POWER_NAME, is_on);
    s_pLight->updateAndReportParam(ESP_RMAKER_DEF_BRIGHTNESS_NAME, brightPercent);

    if (kelvin >= 2000 && kelvin <= 6500) {
        s_pLight->updateAndReportParam(ESP_RMAKER_DEF_CCT_NAME, kelvin);
    } else {
        int h = 0, s = 0, v = 0;
        rgbToHsv(r, g, b, h, s, v);
        s_pLight->updateAndReportParam(ESP_RMAKER_DEF_HUE_NAME, h);
        s_pLight->updateAndReportParam(ESP_RMAKER_DEF_SATURATION_NAME, s);
        int estK = rgbToKelvinEstimate(r, g, b);
        s_pLight->updateAndReportParam(ESP_RMAKER_DEF_CCT_NAME, estK);
    }
}

void rainmakerManagerUpdateDeviceName(const char* newName) {
    if (!s_pLight || !newName || strlen(newName) == 0) return;
    s_pLight->updateAndReportParam(ESP_RMAKER_DEF_NAME_PARAM, newName);
    Serial.printf("[RMAKER] Device name updated in cloud: %s\n", newName);
}

// ============================================================================
// OTA GATES
// ============================================================================
void rainmakerManagerPauseForOta() {
    s_otaPaused = true;
    if (s_isStarted) {
        Serial.println("[RMAKER] Pausing RainMaker cloud tasks for high-speed BLE OTA");
        RMaker.stop();
        s_isStarted = false;
    }
}

void rainmakerManagerResumeAfterOta() {
    s_otaPaused = false;
    Serial.println("[RMAKER] Resuming RainMaker after BLE OTA");
}

bool rainmakerManagerIsRunning() {
    return s_isStarted && !s_otaPaused;
}

bool rainmakerManagerIsCloudConnected() {
    return s_isStarted && !s_otaPaused && esp_rmaker_is_mqtt_connected();
}

bool rainmakerManagerIsDeviceClaimed() {
    if (s_isClaimed) return true;
    if (esp_rmaker_is_mqtt_connected()) {
        s_isClaimed = true;
        return true;
    }
    size_t certLen = esp_rmaker_factory_get_size("client_cert");
    if (certLen > 0) {
        s_isClaimed = true;
        return true;
    }
    return false;
}

int rainmakerManagerGetClaimState() {
    return s_claimState;
}

int rainmakerManagerGetMapState() {
    return (int)esp_rmaker_user_node_mapping_get_state();
}

const char* rainmakerManagerGetNodeId() {
    return esp_rmaker_get_node_id();
}

bool rainmakerManagerMapUser(const char* userId, const char* secretKey) {
    if (!userId || strlen(userId) == 0) return false;
    if (!esp_rmaker_is_mqtt_connected()) {
        Serial.println("[RMAKER] Cannot map user: MQTT is offline. Verify claiming and internet connection.");
        return false;
    }
    Serial.printf("[RMAKER] Triggering user-node mapping: user=%s, key=%s\n", userId, secretKey ? secretKey : "");
    esp_err_t err = esp_rmaker_start_user_node_mapping((char*)userId, (char*)(secretKey ? secretKey : ""));
    if (err == ESP_OK) {
        Serial.println("[RMAKER] User-node mapping workflow successfully triggered.");
        return true;
    } else {
        Serial.printf("[RMAKER] esp_rmaker_start_user_node_mapping error: 0x%X\n", err);
        return false;
    }
}
