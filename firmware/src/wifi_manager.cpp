#include "wifi_manager.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <esp_sntp.h>
#include <sys/time.h>
#include <time.h>

// Forward declarations from main.cpp
extern bool timeIsSynchronized;
extern void record_light_log(bool state, const char* trigger);
extern void evaluate_schedules();

// ============================================================================
// CONSTANTS & TUNABLES
// ============================================================================
static const char* WIFI_PREF_NS       = "tl_wifi";
static const char* KEY_SSID          = "ssid";
static const char* KEY_PSK           = "psk";
static const char* KEY_CONFIGURED    = "cfg";
static const char* KEY_TZ_MIN        = "tz_min";

static const uint32_t WIFI_CONNECT_TIMEOUT_MS = 20000;
static const uint32_t WIFI_SCAN_TIMEOUT_MS    = 12000;
static const uint32_t WIFI_HTTP_PROBE_TIMEOUT = 5000;
static const uint32_t NTP_PERIODIC_SYNC_MS    = 12UL * 3600UL * 1000UL; // 12 hours

static const char* INTERNET_PROBE_URL = "http://clients3.google.com/generate_204";
static const char* NTP_SERVER_1       = "pool.ntp.org";
static const char* NTP_SERVER_2       = "time.google.com";
static const char* NTP_SERVER_3       = "time.cloudflare.com";

// ============================================================================
// INTERNAL STATE
// ============================================================================
static NimBLECharacteristic* s_pNotifyChar = nullptr;

static WifiState  s_state        = TL_WIFI_STATE_IDLE;
static WifiReason s_lastReason   = TL_WIFI_REASON_NONE;

static String     s_ssid         = "";
static String     s_psk          = "";
static bool       s_saveOnSuccess = true;
static bool       s_hasSavedCreds = false;
static int16_t    s_tzOffsetMin  = 330; // Default: +05:30 (IST)

static unsigned long s_phaseStartMs    = 0;
static unsigned long s_lastNtpSyncMs   = 0;
static bool          s_otaPaused       = false;
static bool          s_ntpInFlight     = false;
static unsigned long s_ntpStartMs      = 0;

// ============================================================================
// HELPER NOTIFIER
// ============================================================================
static void notifyJson(const String& jsonStr) {
    if (s_pNotifyChar != nullptr && s_pNotifyChar->getSubscribedCount() > 0) {
        s_pNotifyChar->setValue((uint8_t*)jsonStr.c_str(), jsonStr.length());
        s_pNotifyChar->notify();
    }
}

static const char* reasonToString(WifiReason r) {
    switch (r) {
        case TL_WIFI_REASON_AUTH:        return "auth";
        case TL_WIFI_REASON_NO_AP:       return "no_ap";
        case TL_WIFI_REASON_TIMEOUT:     return "timeout";
        case TL_WIFI_REASON_NO_INTERNET: return "no_internet";
        case TL_WIFI_REASON_NVS:         return "nvs";
        case TL_WIFI_REASON_BUSY:        return "busy";
        case TL_WIFI_REASON_NONE:
        default:                         return "none";
    }
}

static const char* stateToString(WifiState s) {
    switch (s) {
        case TL_WIFI_STATE_SCANNING:     return "scanning";
        case TL_WIFI_STATE_CONNECTING:   return "connecting";
        case TL_WIFI_STATE_GOT_IP:       return "got_ip";
        case TL_WIFI_STATE_INTERNET_OK:  return "internet_ok";
        case TL_WIFI_STATE_SAVED:        return "saved";
        case TL_WIFI_STATE_CONNECTED:    return "connected";
        case TL_WIFI_STATE_FAILED:       return "failed";
        case TL_WIFI_STATE_DISCONNECTED: return "disconnected";
        case TL_WIFI_STATE_IDLE:
        default:                         return "idle";
    }
}

static void emitWifiStatus(WifiState state, WifiReason reason) {
    s_state = state;
    s_lastReason = reason;

    String ip = (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
    int8_t rssi = (WiFi.status() == WL_CONNECTED) ? (int8_t)WiFi.RSSI() : 0;

    String payload = "{\"type\":\"wifi_status\",\"state\":\"" + String(stateToString(state)) +
                     "\",\"reason\":\"" + String(reasonToString(reason)) +
                     "\",\"ssid\":\"" + s_ssid +
                     "\",\"ip\":\"" + ip +
                     "\",\"rssi\":" + String(rssi) + "}";
    notifyJson(payload);
    Serial.printf("[WiFi] Status -> state=%s, reason=%s, ip=%s, rssi=%d\n",
                  stateToString(state), reasonToString(reason), ip.c_str(), (int)rssi);
}

// ============================================================================
// NVS STORAGE OPERATIONS
// ============================================================================
static bool loadCredsFromNvs() {
    Preferences prefs;
    if (!prefs.begin(WIFI_PREF_NS, true)) {
        wifiManagerApplyTimezone(330);
        return false;
    }
    s_tzOffsetMin = prefs.getShort(KEY_TZ_MIN, 330);
    wifiManagerApplyTimezone(s_tzOffsetMin);

    bool cfg = prefs.getBool(KEY_CONFIGURED, false);
    if (!cfg) {
        prefs.end();
        s_hasSavedCreds = false;
        return false;
    }
    s_ssid = prefs.getString(KEY_SSID, "");
    s_psk  = prefs.getString(KEY_PSK, "");
    prefs.end();

    s_hasSavedCreds = (s_ssid.length() > 0);
    return s_hasSavedCreds;
}

static bool saveCredsToNvs(const String& ssid, const String& psk) {
    Preferences prefs;
    if (!prefs.begin(WIFI_PREF_NS, false)) {
        return false;
    }
    bool ok = true;
    ok &= (prefs.putString(KEY_SSID, ssid) > 0);
    ok &= (prefs.putString(KEY_PSK, psk) >= 0);
    ok &= prefs.putBool(KEY_CONFIGURED, true);
    ok &= prefs.putShort(KEY_TZ_MIN, s_tzOffsetMin);
    prefs.end();
    s_hasSavedCreds = ok;
    return ok;
}

static void wipeCredsFromNvs() {
    Preferences prefs;
    if (prefs.begin(WIFI_PREF_NS, false)) {
        prefs.clear();
        prefs.end();
    }
    s_hasSavedCreds = false;
    s_ssid = "";
    s_psk = "";
}

// ============================================================================
// HTTP 204 INTERNET PROBE
// ============================================================================
static bool probeInternetReachability() {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }
    HTTPClient http;
    http.setTimeout(WIFI_HTTP_PROBE_TIMEOUT);
    http.setReuse(false);

    if (!http.begin(INTERNET_PROBE_URL)) {
        Serial.println("[WiFi] HTTP probe begin() failed");
        return false;
    }

    int httpCode = http.GET();
    http.end();

    Serial.printf("[WiFi] Internet probe returned HTTP %d\n", httpCode);
    return (httpCode == 204 || httpCode == 200);
}

// ============================================================================
// SNTP / NTP TIME SYNCHRONIZATION
// ============================================================================
static void startSntpFetch() {
    if (WiFi.status() != WL_CONNECTED) {
        return;
    }
    Serial.println("[NTP] Initializing SNTP client for Mumbai time sync...");
    sntp_stop();

    char tzBuf[32];
    if (s_tzOffsetMin == 330) {
        snprintf(tzBuf, sizeof(tzBuf), "IST-5:30");
    } else {
        int h = abs(s_tzOffsetMin) / 60;
        int m = abs(s_tzOffsetMin) % 60;
        char sign = (s_tzOffsetMin >= 0) ? '-' : '+';
        snprintf(tzBuf, sizeof(tzBuf), "UTC%c%d:%02d", sign, h, m);
    }
    configTzTime(tzBuf, NTP_SERVER_1, NTP_SERVER_2, NTP_SERVER_3);

    s_ntpInFlight = true;
    s_ntpStartMs = millis();
}

static void checkSntpProgress() {
    if (!s_ntpInFlight) return;

    if (sntp_get_sync_status() == SNTP_SYNC_STATUS_COMPLETED) {
        time_t nowEp = time(nullptr);
        sntp_stop();
        s_ntpInFlight = false;

        if (nowEp >= 1704067200UL) { // Jan 1, 2024 sanity boundary
            struct timeval tv = { .tv_sec = nowEp, .tv_usec = 0 };
            settimeofday(&tv, NULL);
            timeIsSynchronized = true;
            s_lastNtpSyncMs = millis();

            struct tm tmLocal;
            localtime_r(&nowEp, &tmLocal);

            Serial.printf("[NTP] Synchronized! UTC Epoch=%u -> Mumbai Local: %04d-%02d-%02d %02d:%02d:%02d (tz=%+d min)\n",
                          (uint32_t)nowEp,
                          tmLocal.tm_year + 1900, tmLocal.tm_mon + 1, tmLocal.tm_mday,
                          tmLocal.tm_hour, tmLocal.tm_min, tmLocal.tm_sec,
                          s_tzOffsetMin);

            record_light_log(true, "WiFi NTP Synced");

            // Notify companion app
            String ntpPkt = "{\"type\":\"ntp_synced\",\"epoch\":" + String((uint32_t)nowEp) +
                            ",\"tz_min\":" + String(s_tzOffsetMin) + "}";
            notifyJson(ntpPkt);

            // Re-evaluate schedules immediately with authoritative clock
            evaluate_schedules();
        } else {
            Serial.printf("[NTP] Completed but epoch %u failed sanity\n", (uint32_t)nowEp);
        }
        return;
    }

    if (millis() - s_ntpStartMs > 8000) {
        Serial.println("[NTP] Fetch timed out after 8s");
        sntp_stop();
        s_ntpInFlight = false;
    }
}

// ============================================================================
// LIFECYCLE & TICK
// ============================================================================
void wifiManagerInit(NimBLECharacteristic* pNotifyChar) {
    s_pNotifyChar = pNotifyChar;
    s_state = TL_WIFI_STATE_IDLE;
    s_lastReason = TL_WIFI_REASON_NONE;

    WiFi.persistent(false);
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);

    if (loadCredsFromNvs()) {
        Serial.printf("[WiFi] Stored credentials found for SSID: '%s'. Auto-connecting on boot...\n", s_ssid.c_str());
        s_saveOnSuccess = false;
        WiFi.mode(WIFI_STA);
        WiFi.begin(s_ssid.c_str(), s_psk.c_str());
        s_state = TL_WIFI_STATE_CONNECTING;
        s_phaseStartMs = millis();
    } else {
        Serial.println("[WiFi] No saved credentials. Operating in offline BLE mode.");
    }
}

void wifiManagerTick(unsigned long nowMs) {
    if (s_otaPaused) return;

    // Check in-flight SNTP fetch
    checkSntpProgress();

    // Periodic NTP refresh every 12 hours when connected
    if (s_state == TL_WIFI_STATE_CONNECTED && (nowMs - s_lastNtpSyncMs >= NTP_PERIODIC_SYNC_MS)) {
        s_lastNtpSyncMs = nowMs;
        startSntpFetch();
    }

    switch (s_state) {
        case TL_WIFI_STATE_SCANNING: {
            int16_t scanCount = WiFi.scanComplete();
            if (scanCount == WIFI_SCAN_RUNNING) {
                if (nowMs - s_phaseStartMs > WIFI_SCAN_TIMEOUT_MS) {
                    WiFi.scanDelete();
                    Serial.println("[WiFi] Scan timed out");
                    emitWifiStatus(s_hasSavedCreds ? TL_WIFI_STATE_DISCONNECTED : TL_WIFI_STATE_IDLE, TL_WIFI_REASON_TIMEOUT);
                }
                return;
            }
            if (scanCount == WIFI_SCAN_FAILED) {
                WiFi.scanDelete();
                Serial.println("[WiFi] Scan failed");
                emitWifiStatus(s_hasSavedCreds ? TL_WIFI_STATE_DISCONNECTED : TL_WIFI_STATE_IDLE, TL_WIFI_REASON_TIMEOUT);
                return;
            }

            // Stream results to app
            uint8_t total = (scanCount > 255) ? 255 : (uint8_t)scanCount;
            Serial.printf("[WiFi] Scan finished: %d networks found\n", (int)total);

            for (uint8_t i = 0; i < total; i++) {
                String apSsid = WiFi.SSID(i);
                int32_t rssi = WiFi.RSSI(i);
                wifi_auth_mode_t auth = WiFi.encryptionType(i);
                String authStr = "WPA2";
                if (auth == WIFI_AUTH_OPEN) authStr = "OPEN";
                else if (auth == WIFI_AUTH_WEP) authStr = "WEP";
                else if (auth == WIFI_AUTH_WPA_PSK) authStr = "WPA";
                else if (auth == WIFI_AUTH_WPA3_PSK) authStr = "WPA3";

                String itemPkt = "{\"type\":\"wifi_scan_item\",\"idx\":" + String(i) +
                                 ",\"total\":" + String(total) +
                                 ",\"ssid\":\"" + apSsid +
                                 "\",\"rssi\":" + String((int)rssi) +
                                 ",\"auth\":\"" + authStr + "\"}";
                notifyJson(itemPkt);
                delay(6); // 6ms yield between notifications for NimBLE TX buffer drain
            }

            String donePkt = "{\"type\":\"wifi_scan_done\",\"count\":" + String(total) + "}";
            notifyJson(donePkt);

            WiFi.scanDelete();
            emitWifiStatus(s_hasSavedCreds ? TL_WIFI_STATE_DISCONNECTED : TL_WIFI_STATE_IDLE, TL_WIFI_REASON_NONE);
            break;
        }

        case TL_WIFI_STATE_CONNECTING: {
            wl_status_t st = WiFi.status();
            if (st == WL_CONNECTED) {
                IPAddress ip = WiFi.localIP();
                if ((uint32_t)ip != 0) {
                    Serial.printf("[WiFi] Associated & IP acquired: %s\n", ip.toString().c_str());
                    emitWifiStatus(TL_WIFI_STATE_GOT_IP, TL_WIFI_REASON_NONE);

                    // Perform HTTP 204 internet verification
                    bool internetOk = probeInternetReachability();
                    if (internetOk) {
                        emitWifiStatus(TL_WIFI_STATE_INTERNET_OK, TL_WIFI_REASON_NONE);
                        if (s_saveOnSuccess) {
                            saveCredsToNvs(s_ssid, s_psk);
                            emitWifiStatus(TL_WIFI_STATE_SAVED, TL_WIFI_REASON_NONE);
                        }
                        emitWifiStatus(TL_WIFI_STATE_CONNECTED, TL_WIFI_REASON_NONE);
                        // Trigger immediate NTP clock synchronization
                        startSntpFetch();
                    } else {
                        Serial.println("[WiFi] Internet check failed -> no internet access");
                        emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_NO_INTERNET);
                    }
                }
                return;
            }

            if (st == WL_CONNECT_FAILED) {
                Serial.println("[WiFi] Authentication failed");
                emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_AUTH);
                return;
            }

            if (st == WL_NO_SSID_AVAIL) {
                Serial.println("[WiFi] Target SSID not found");
                emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_NO_AP);
                return;
            }

            if (nowMs - s_phaseStartMs > WIFI_CONNECT_TIMEOUT_MS) {
                Serial.println("[WiFi] Association timeout");
                emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_TIMEOUT);
            }
            break;
        }

        case TL_WIFI_STATE_CONNECTED: {
            // Check for connection loss
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("[WiFi] Connection lost -> reconnecting...");
                emitWifiStatus(TL_WIFI_STATE_DISCONNECTED, TL_WIFI_REASON_NONE);
                if (s_hasSavedCreds) {
                    WiFi.reconnect();
                    s_state = TL_WIFI_STATE_CONNECTING;
                    s_phaseStartMs = nowMs;
                }
            }
            break;
        }

        default:
            break;
    }
}

// ============================================================================
// BLE COMMAND HANDLERS
// ============================================================================
void wifiManagerStartScan() {
    if (s_otaPaused) {
        notifyJson("{\"type\":\"wifi_status\",\"state\":\"failed\",\"reason\":\"busy\"}");
        return;
    }
    Serial.println("[WiFi] Starting 2.4 GHz asynchronous AP scan...");
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(false, true);

    int16_t kick = WiFi.scanNetworks(true, false);
    if (kick == WIFI_SCAN_FAILED) {
        Serial.println("[WiFi] scanNetworks() failed to start");
        emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_TIMEOUT);
        return;
    }

    s_state = TL_WIFI_STATE_SCANNING;
    s_phaseStartMs = millis();
    emitWifiStatus(TL_WIFI_STATE_SCANNING, TL_WIFI_REASON_NONE);
}

void wifiManagerConnect(const String& ssid, const String& psk, bool saveOnSuccess) {
    if (s_otaPaused) return;

    if (ssid.length() == 0 || ssid.length() > 32 || psk.length() > 64) {
        emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_AUTH);
        return;
    }

    s_ssid = ssid;
    s_psk = psk;
    s_saveOnSuccess = saveOnSuccess;

    Serial.printf("[WiFi] Connect requested: SSID='%s', save=%d\n", s_ssid.c_str(), (int)saveOnSuccess);

    WiFi.disconnect(false, true);
    delay(50);
    WiFi.mode(WIFI_STA);
    WiFi.begin(s_ssid.c_str(), s_psk.c_str());

    s_state = TL_WIFI_STATE_CONNECTING;
    s_phaseStartMs = millis();
    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
}

void wifiManagerForget() {
    Serial.println("[WiFi] Forget network requested -> clearing NVS & disconnecting");
    wipeCredsFromNvs();
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);
    emitWifiStatus(TL_WIFI_STATE_IDLE, TL_WIFI_REASON_NONE);
}

void wifiManagerQueryStatus() {
    emitWifiStatus(s_state, s_lastReason);
}

void wifiManagerTriggerNtp() {
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("[NTP] Manual sync triggered from companion app");
        startSntpFetch();
    } else {
        Serial.println("[NTP] Cannot sync -> WiFi not connected");
        notifyJson("{\"type\":\"wifi_status\",\"state\":\"disconnected\",\"reason\":\"no_ap\"}");
    }
}

void wifiManagerApplyTimezone(int16_t tzOffsetMin) {
    s_tzOffsetMin = tzOffsetMin;
    char tzBuf[32];
    if (tzOffsetMin == 330) {
        // Mumbai / Indian Standard Time: UTC+05:30 (no DST)
        snprintf(tzBuf, sizeof(tzBuf), "IST-5:30");
    } else {
        int h = abs(tzOffsetMin) / 60;
        int m = abs(tzOffsetMin) % 60;
        char sign = (tzOffsetMin >= 0) ? '-' : '+';
        snprintf(tzBuf, sizeof(tzBuf), "UTC%c%d:%02d", sign, h, m);
    }
    setenv("TZ", tzBuf, 1);
    tzset();
    Serial.printf("[Clock] System timezone active: %s (%+d min%s)\n",
                  tzBuf, tzOffsetMin, (tzOffsetMin == 330 ? " / Mumbai IST" : ""));
}

void wifiManagerSetTimezoneOffset(int16_t tzOffsetMin) {
    s_tzOffsetMin = tzOffsetMin;
    Preferences prefs;
    if (prefs.begin(WIFI_PREF_NS, false)) {
        prefs.putShort(KEY_TZ_MIN, tzOffsetMin);
        prefs.end();
    }
    wifiManagerApplyTimezone(tzOffsetMin);
}

int16_t wifiManagerGetTimezoneOffset() {
    return s_tzOffsetMin;
}

bool wifiManagerIsConnected() {
    return (s_state == TL_WIFI_STATE_CONNECTED && WiFi.status() == WL_CONNECTED);
}

bool wifiManagerIsInternetOk() {
    return (s_state == TL_WIFI_STATE_CONNECTED);
}

WifiState wifiManagerGetState() {
    return s_state;
}

String wifiManagerGetSsid() {
    return s_ssid;
}

String wifiManagerGetIp() {
    return (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
}

int8_t wifiManagerGetRssi() {
    return (WiFi.status() == WL_CONNECTED) ? (int8_t)WiFi.RSSI() : 0;
}

void wifiManagerPauseForOta() {
    Serial.println("[WiFi] Pausing WiFi manager for high-speed BLE OTA flash");
    s_otaPaused = true;
    if (s_ntpInFlight) {
        sntp_stop();
        s_ntpInFlight = false;
    }
}

void wifiManagerResumeAfterOta() {
    Serial.println("[WiFi] Resuming WiFi manager after OTA");
    s_otaPaused = false;
}
