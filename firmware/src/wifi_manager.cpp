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

// Legacy single-slot keys (for backward compatibility migration)
static const char* KEY_LEGACY_SSID    = "ssid";
static const char* KEY_LEGACY_PSK     = "psk";
static const char* KEY_LEGACY_CFG     = "cfg";

// Dual-slot keys (Slot 1 & Slot 2)
static const char* KEY_SSID_1         = "ssid_1";
static const char* KEY_PSK_1          = "psk_1";
static const char* KEY_CFG_1          = "cfg_1";

static const char* KEY_SSID_2         = "ssid_2";
static const char* KEY_PSK_2          = "psk_2";
static const char* KEY_CFG_2          = "cfg_2";

static const char* KEY_ACT_SLOT       = "act_slot";
static const char* KEY_TZ_MIN         = "tz_min";

static const uint32_t WIFI_CONNECT_TIMEOUT_MS  = 18000;
static const uint32_t WIFI_SCAN_TIMEOUT_MS     = 12000;
static const uint32_t WIFI_HTTP_PROBE_TIMEOUT  = 5000;
static const uint32_t NTP_PERIODIC_SYNC_MS     = 12UL * 3600UL * 1000UL; // 12 hours
static const uint32_t FAILBACK_CHECK_INTERVAL_MS = 30UL * 60UL * 1000UL; // 30 mins

static const char* INTERNET_PROBE_URL = "http://clients3.google.com/generate_204";
static const char* NTP_SERVER_1       = "pool.ntp.org";
static const char* NTP_SERVER_2       = "time.google.com";
static const char* NTP_SERVER_3       = "time.cloudflare.com";

// ============================================================================
// INTERNAL STATE
// ============================================================================
struct WifiSlot {
    String ssid = "";
    String psk = "";
    bool configured = false;
    uint8_t failCount = 0;
};

static NimBLECharacteristic* s_pNotifyChar = nullptr;

static WifiState  s_state        = TL_WIFI_STATE_IDLE;
static WifiReason s_lastReason   = TL_WIFI_REASON_NONE;

static WifiSlot   s_slots[2];     // Index 0 = Slot 1 (Primary), Index 1 = Slot 2 (Backup)
static uint8_t    s_activeSlot   = 0; // 0=none, 1=slot 1, 2=slot 2
static uint8_t    s_targetSlot   = 1; // 1 or 2 (slot currently attempting connection)

static uint8_t    s_pendingSlot    = 1;
static String     s_pendingSsid    = "";
static String     s_pendingPsk     = "";
static bool       s_saveOnSuccess  = false;
static int16_t    s_tzOffsetMin    = 330; // Default: +05:30 (IST)

static unsigned long s_phaseStartMs       = 0;
static unsigned long s_lastNtpSyncMs      = 0;
static unsigned long s_lastFailbackCheckMs = 0;
static unsigned long s_backoffEndMs       = 0;
static uint8_t       s_backoffCycle       = 0;

static bool          s_otaPaused          = false;
static bool          s_ntpInFlight        = false;
static unsigned long s_ntpStartMs         = 0;

// Exponential moving average for smooth signal display
static int8_t        s_smoothedRssi       = 0;

// ============================================================================
// HELPER NOTIFIER & STRINGIFIERS
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
        case TL_WIFI_STATE_BACKOFF:      return "backoff";
        case TL_WIFI_STATE_IDLE:
        default:                         return "idle";
    }
}

static void emitWifiStatus(WifiState state, WifiReason reason) {
    s_state = state;
    s_lastReason = reason;

    String ip = (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
    int8_t rawRssi = (WiFi.status() == WL_CONNECTED) ? (int8_t)WiFi.RSSI() : 0;
    if (rawRssi != 0) {
        s_smoothedRssi = (s_smoothedRssi == 0) ? rawRssi : (int8_t)(0.7f * rawRssi + 0.3f * s_smoothedRssi);
    } else {
        s_smoothedRssi = 0;
    }

    String curSsid = "";
    if (s_activeSlot >= 1 && s_activeSlot <= 2 && s_slots[s_activeSlot - 1].configured) {
        curSsid = s_slots[s_activeSlot - 1].ssid;
    } else if (s_targetSlot >= 1 && s_targetSlot <= 2 && s_slots[s_targetSlot - 1].configured) {
        curSsid = s_slots[s_targetSlot - 1].ssid;
    } else if (s_pendingSsid.length() > 0) {
        curSsid = s_pendingSsid;
    }

    // 100% backward compatible root fields + new dual-slot topology
    String payload = "{\"type\":\"wifi_status\",\"state\":\"" + String(stateToString(state)) +
                     "\",\"reason\":\"" + String(reasonToString(reason)) +
                     "\",\"ssid\":\"" + curSsid +
                     "\",\"ip\":\"" + ip +
                     "\",\"rssi\":" + String((int)s_smoothedRssi) +
                     ",\"active_slot\":" + String((int)s_activeSlot) +
                     ",\"slots\":[" +
                     "{\"slot\":1,\"ssid\":\"" + s_slots[0].ssid + "\",\"configured\":" + (s_slots[0].configured ? "true" : "false") + ",\"active\":" + (s_activeSlot == 1 ? "true" : "false") + "}," +
                     "{\"slot\":2,\"ssid\":\"" + s_slots[1].ssid + "\",\"configured\":" + (s_slots[1].configured ? "true" : "false") + ",\"active\":" + (s_activeSlot == 2 ? "true" : "false") + "}" +
                     "]}";
    notifyJson(payload);
    Serial.printf("[WiFi] Status -> state=%s, reason=%s, slot=%d, ssid='%s', ip=%s, rssi=%d\n",
                  stateToString(state), reasonToString(reason), (int)s_activeSlot, curSsid.c_str(), ip.c_str(), (int)s_smoothedRssi);
}

// ============================================================================
// NVS STORAGE OPERATIONS & BACKWARD COMPATIBILITY
// ============================================================================
static bool loadCredsFromNvs() {
    Preferences prefs;
    if (!prefs.begin(WIFI_PREF_NS, false)) {
        wifiManagerApplyTimezone(330);
        return false;
    }
    s_tzOffsetMin = prefs.getShort(KEY_TZ_MIN, 330);
    wifiManagerApplyTimezone(s_tzOffsetMin);

    s_slots[0].configured = prefs.getBool(KEY_CFG_1, false);
    if (s_slots[0].configured) {
        s_slots[0].ssid = prefs.getString(KEY_SSID_1, "");
        s_slots[0].psk  = prefs.getString(KEY_PSK_1, "");
    }

    s_slots[1].configured = prefs.getBool(KEY_CFG_2, false);
    if (s_slots[1].configured) {
        s_slots[1].ssid = prefs.getString(KEY_SSID_2, "");
        s_slots[1].psk  = prefs.getString(KEY_PSK_2, "");
    }

    // Backward compatibility: If no new slot configured, check for legacy keys
    if (!s_slots[0].configured && !s_slots[1].configured) {
        bool legacyCfg = prefs.getBool(KEY_LEGACY_CFG, false);
        if (legacyCfg) {
            String legSsid = prefs.getString(KEY_LEGACY_SSID, "");
            String legPsk  = prefs.getString(KEY_LEGACY_PSK, "");
            if (legSsid.length() > 0) {
                prefs.putString(KEY_SSID_1, legSsid);
                prefs.putString(KEY_PSK_1, legPsk);
                prefs.putBool(KEY_CFG_1, true);
                prefs.putUChar(KEY_ACT_SLOT, 1);
                prefs.remove(KEY_LEGACY_SSID);
                prefs.remove(KEY_LEGACY_PSK);
                prefs.remove(KEY_LEGACY_CFG);

                s_slots[0].ssid = legSsid;
                s_slots[0].psk  = legPsk;
                s_slots[0].configured = true;
                Serial.printf("[WiFi] Backward-compat migration: Legacy SSID '%s' migrated to Slot 1\n", legSsid.c_str());
            }
        }
    }

    s_activeSlot = prefs.getUChar(KEY_ACT_SLOT, 0);
    if (s_activeSlot == 1 && !s_slots[0].configured) s_activeSlot = 0;
    if (s_activeSlot == 2 && !s_slots[1].configured) s_activeSlot = 0;

    prefs.end();

    if (s_activeSlot == 0) {
        if (s_slots[0].configured) s_targetSlot = 1;
        else if (s_slots[1].configured) s_targetSlot = 2;
        else s_targetSlot = 1;
    } else {
        s_targetSlot = s_activeSlot;
    }

    return (s_slots[0].configured || s_slots[1].configured);
}

static bool saveSlotCredsToNvs(uint8_t slot, const String& ssid, const String& psk) {
    if (slot != 1 && slot != 2) slot = 1;
    uint8_t idx = slot - 1;

    Preferences prefs;
    if (!prefs.begin(WIFI_PREF_NS, false)) return false;

    bool ok = true;
    if (slot == 1) {
        ok &= (prefs.putString(KEY_SSID_1, ssid) > 0);
        ok &= (prefs.putString(KEY_PSK_1, psk) >= 0);
        ok &= prefs.putBool(KEY_CFG_1, true);
    } else {
        ok &= (prefs.putString(KEY_SSID_2, ssid) > 0);
        ok &= (prefs.putString(KEY_PSK_2, psk) >= 0);
        ok &= prefs.putBool(KEY_CFG_2, true);
    }
    prefs.putUChar(KEY_ACT_SLOT, slot);
    prefs.putShort(KEY_TZ_MIN, s_tzOffsetMin);
    prefs.end();

    if (ok) {
        s_slots[idx].ssid = ssid;
        s_slots[idx].psk = psk;
        s_slots[idx].configured = true;
        s_slots[idx].failCount = 0;
        s_activeSlot = slot;
        Serial.printf("[WiFi] Saved Slot %d: SSID='%s'\n", (int)slot, ssid.c_str());
    }
    return ok;
}

static void wipeSlotCredsFromNvs(uint8_t slot) {
    Preferences prefs;
    if (prefs.begin(WIFI_PREF_NS, false)) {
        if (slot == 0 || slot == 1) {
            prefs.remove(KEY_SSID_1);
            prefs.remove(KEY_PSK_1);
            prefs.remove(KEY_CFG_1);
            s_slots[0].ssid = "";
            s_slots[0].psk = "";
            s_slots[0].configured = false;
            s_slots[0].failCount = 0;
        }
        if (slot == 0 || slot == 2) {
            prefs.remove(KEY_SSID_2);
            prefs.remove(KEY_PSK_2);
            prefs.remove(KEY_CFG_2);
            s_slots[1].ssid = "";
            s_slots[1].psk = "";
            s_slots[1].configured = false;
            s_slots[1].failCount = 0;
        }
        if (slot == 0 || s_activeSlot == slot) {
            if (slot == 1 && s_slots[1].configured) {
                s_activeSlot = 2;
                prefs.putUChar(KEY_ACT_SLOT, 2);
            } else if (slot == 2 && s_slots[0].configured) {
                s_activeSlot = 1;
                prefs.putUChar(KEY_ACT_SLOT, 1);
            } else {
                s_activeSlot = 0;
                prefs.remove(KEY_ACT_SLOT);
            }
        }
        prefs.end();
    }
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

            String ntpPkt = "{\"type\":\"ntp_synced\",\"epoch\":" + String((uint32_t)nowEp) +
                            ",\"tz_min\":" + String(s_tzOffsetMin) + "}";
            notifyJson(ntpPkt);

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
// LIFECYCLE & NON-BLOCKING TICK STATE MACHINE
// ============================================================================
void wifiManagerInit(NimBLECharacteristic* pNotifyChar) {
    s_pNotifyChar = pNotifyChar;
    s_state = TL_WIFI_STATE_IDLE;
    s_lastReason = TL_WIFI_REASON_NONE;
    s_activeSlot = 0;

    WiFi.persistent(false);
    WiFi.disconnect(true, false); // Do not erase AP config in NVS
    WiFi.mode(WIFI_OFF);

    if (loadCredsFromNvs()) {
        uint8_t initialSlot = (s_targetSlot == 2 && s_slots[1].configured) ? 2 : 1;
        s_targetSlot = initialSlot;
        Serial.printf("[WiFi] Stored credentials found for Slot %d: '%s'. Auto-connecting on boot...\n",
                      (int)initialSlot, s_slots[initialSlot - 1].ssid.c_str());
        s_saveOnSuccess = false;
        WiFi.mode(WIFI_STA);
        WiFi.begin(s_slots[initialSlot - 1].ssid.c_str(), s_slots[initialSlot - 1].psk.c_str());
        s_state = TL_WIFI_STATE_CONNECTING;
        s_phaseStartMs = millis();
    } else {
        Serial.println("[WiFi] No saved credentials. Operating in offline BLE mode.");
    }
}

void wifiManagerTick(unsigned long nowMs) {
    if (s_otaPaused) return;

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
                    emitWifiStatus(WiFi.status() == WL_CONNECTED ? TL_WIFI_STATE_CONNECTED : TL_WIFI_STATE_DISCONNECTED, TL_WIFI_REASON_TIMEOUT);
                }
                return;
            }
            if (scanCount == WIFI_SCAN_FAILED) {
                WiFi.scanDelete();
                Serial.println("[WiFi] Scan failed");
                emitWifiStatus(WiFi.status() == WL_CONNECTED ? TL_WIFI_STATE_CONNECTED : TL_WIFI_STATE_DISCONNECTED, TL_WIFI_REASON_TIMEOUT);
                return;
            }

            // Stream results to app
            uint8_t total = (scanCount > 255) ? 255 : (uint8_t)scanCount;
            Serial.printf("[WiFi] Scan finished: %d networks found\n", (int)total);

            bool foundSlot1 = false;
            bool foundSlot2 = false;

            for (uint8_t i = 0; i < total; i++) {
                String apSsid = WiFi.SSID(i);
                int32_t rssi = WiFi.RSSI(i);
                wifi_auth_mode_t auth = WiFi.encryptionType(i);
                String authStr = "WPA2";
                if (auth == WIFI_AUTH_OPEN) authStr = "OPEN";
                else if (auth == WIFI_AUTH_WEP) authStr = "WEP";
                else if (auth == WIFI_AUTH_WPA_PSK) authStr = "WPA";
                else if (auth == WIFI_AUTH_WPA3_PSK) authStr = "WPA3";

                if (s_slots[0].configured && apSsid.equals(s_slots[0].ssid)) foundSlot1 = true;
                if (s_slots[1].configured && apSsid.equals(s_slots[1].ssid)) foundSlot2 = true;

                String itemPkt = "{\"type\":\"wifi_scan_item\",\"idx\":" + String(i) +
                                 ",\"total\":" + String(total) +
                                 ",\"ssid\":\"" + apSsid +
                                 "\",\"rssi\":" + String((int)rssi) +
                                 ",\"auth\":\"" + authStr + "\"}";
                notifyJson(itemPkt);
                delay(6);
            }

            String donePkt = "{\"type\":\"wifi_scan_done\",\"count\":" + String(total) + "}";
            notifyJson(donePkt);
            WiFi.scanDelete();

            if (WiFi.status() == WL_CONNECTED) {
                s_state = TL_WIFI_STATE_CONNECTED;
                emitWifiStatus(TL_WIFI_STATE_CONNECTED, TL_WIFI_REASON_NONE);
            } else {
                // Pre-connect intelligence: connect immediately to the slot seen in the air!
                if (foundSlot1 && s_slots[0].configured) {
                    Serial.println("[WiFi] Scan confirmed Slot 1 in air -> connecting to Slot 1");
                    s_targetSlot = 1;
                    WiFi.mode(WIFI_STA);
                    WiFi.begin(s_slots[0].ssid.c_str(), s_slots[0].psk.c_str());
                    s_state = TL_WIFI_STATE_CONNECTING;
                    s_phaseStartMs = nowMs;
                    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
                } else if (foundSlot2 && s_slots[1].configured) {
                    Serial.println("[WiFi] Scan confirmed Slot 2 in air -> connecting to Slot 2");
                    s_targetSlot = 2;
                    WiFi.mode(WIFI_STA);
                    WiFi.begin(s_slots[1].ssid.c_str(), s_slots[1].psk.c_str());
                    s_state = TL_WIFI_STATE_CONNECTING;
                    s_phaseStartMs = nowMs;
                    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
                } else if (s_slots[0].configured || s_slots[1].configured) {
                    s_state = TL_WIFI_STATE_DISCONNECTED;
                    emitWifiStatus(TL_WIFI_STATE_DISCONNECTED, TL_WIFI_REASON_NONE);
                } else {
                    s_state = TL_WIFI_STATE_IDLE;
                    emitWifiStatus(TL_WIFI_STATE_IDLE, TL_WIFI_REASON_NONE);
                }
            }
            break;
        }

        case TL_WIFI_STATE_CONNECTING: {
            wl_status_t st = WiFi.status();
            if (st == WL_CONNECTED) {
                IPAddress ip = WiFi.localIP();
                if ((uint32_t)ip != 0) {
                    Serial.printf("[WiFi] Associated & IP acquired on Slot %d: %s\n", (int)s_targetSlot, ip.toString().c_str());
                    emitWifiStatus(TL_WIFI_STATE_GOT_IP, TL_WIFI_REASON_NONE);

                    // Perform HTTP 204 internet verification (with one retry)
                    bool internetOk = probeInternetReachability();
                    if (!internetOk) {
                        delay(600);
                        internetOk = probeInternetReachability();
                    }

                    if (internetOk) {
                        emitWifiStatus(TL_WIFI_STATE_INTERNET_OK, TL_WIFI_REASON_NONE);
                        s_activeSlot = s_targetSlot;
                        s_slots[s_targetSlot - 1].failCount = 0;
                        s_backoffCycle = 0;

                        if (s_saveOnSuccess && s_pendingSsid.length() > 0) {
                            saveSlotCredsToNvs(s_targetSlot, s_pendingSsid, s_pendingPsk);
                            s_pendingSsid = "";
                            s_pendingPsk = "";
                            emitWifiStatus(TL_WIFI_STATE_SAVED, TL_WIFI_REASON_NONE);
                        }
                        emitWifiStatus(TL_WIFI_STATE_CONNECTED, TL_WIFI_REASON_NONE);
                        startSntpFetch();
                    } else {
                        Serial.printf("[WiFi] Internet check failed on Slot %d\n", (int)s_targetSlot);
                        s_slots[s_targetSlot - 1].failCount++;
                        uint8_t altSlot = (s_targetSlot == 1) ? 2 : 1;
                        if (s_slots[altSlot - 1].configured && s_slots[altSlot - 1].failCount == 0) {
                            Serial.printf("[WiFi] Failover: Switching from Slot %d to Slot %d ('%s')...\n",
                                          (int)s_targetSlot, (int)altSlot, s_slots[altSlot - 1].ssid.c_str());
                            WiFi.disconnect(false, false);
                            s_targetSlot = altSlot;
                            WiFi.begin(s_slots[altSlot - 1].ssid.c_str(), s_slots[altSlot - 1].psk.c_str());
                            s_state = TL_WIFI_STATE_CONNECTING;
                            s_phaseStartMs = nowMs;
                            emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
                        } else {
                            emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_NO_INTERNET);
                            s_state = TL_WIFI_STATE_BACKOFF;
                            s_backoffEndMs = nowMs + 15000;
                        }
                    }
                }
                return;
            }

            bool failed = false;
            WifiReason reason = TL_WIFI_REASON_NONE;
            if (st == WL_CONNECT_FAILED) {
                Serial.printf("[WiFi] Auth failed on Slot %d\n", (int)s_targetSlot);
                failed = true;
                reason = TL_WIFI_REASON_AUTH;
            } else if (st == WL_NO_SSID_AVAIL) {
                Serial.printf("[WiFi] SSID not found on Slot %d\n", (int)s_targetSlot);
                failed = true;
                reason = TL_WIFI_REASON_NO_AP;
            } else if (nowMs - s_phaseStartMs > WIFI_CONNECT_TIMEOUT_MS) {
                Serial.printf("[WiFi] Timeout on Slot %d\n", (int)s_targetSlot);
                failed = true;
                reason = TL_WIFI_REASON_TIMEOUT;
            }

            if (failed) {
                s_slots[s_targetSlot - 1].failCount++;
                WiFi.disconnect(false, false);

                uint8_t altSlot = (s_targetSlot == 1) ? 2 : 1;
                if (s_slots[altSlot - 1].configured && s_slots[altSlot - 1].failCount == 0) {
                    Serial.printf("[WiFi] Failover: Switching from Slot %d to Slot %d ('%s')...\n",
                                  (int)s_targetSlot, (int)altSlot, s_slots[altSlot - 1].ssid.c_str());
                    s_targetSlot = altSlot;
                    WiFi.mode(WIFI_STA);
                    WiFi.begin(s_slots[altSlot - 1].ssid.c_str(), s_slots[altSlot - 1].psk.c_str());
                    s_state = TL_WIFI_STATE_CONNECTING;
                    s_phaseStartMs = nowMs;
                    emitWifiStatus(TL_WIFI_STATE_CONNECTING, reason);
                } else {
                    s_slots[0].failCount = 0;
                    s_slots[1].failCount = 0;
                    emitWifiStatus(TL_WIFI_STATE_FAILED, reason);

                    uint32_t delayMs = 15000 + (s_backoffCycle * 15000);
                    if (delayMs > 120000) delayMs = 120000;
                    s_backoffEndMs = nowMs + delayMs;
                    s_backoffCycle++;
                    s_state = TL_WIFI_STATE_BACKOFF;
                    Serial.printf("[WiFi] Both slots unavailable -> entering backoff (%u ms, cycle %d)\n", delayMs, (int)s_backoffCycle);
                }
            }
            break;
        }

        case TL_WIFI_STATE_BACKOFF: {
            if (nowMs >= s_backoffEndMs) {
                uint8_t pickSlot = s_slots[0].configured ? 1 : (s_slots[1].configured ? 2 : 0);
                if (pickSlot > 0) {
                    s_targetSlot = pickSlot;
                    Serial.printf("[WiFi] Backoff expired -> retrying Slot %d ('%s')...\n",
                                  (int)s_targetSlot, s_slots[s_targetSlot - 1].ssid.c_str());
                    WiFi.mode(WIFI_STA);
                    WiFi.begin(s_slots[s_targetSlot - 1].ssid.c_str(), s_slots[s_targetSlot - 1].psk.c_str());
                    s_state = TL_WIFI_STATE_CONNECTING;
                    s_phaseStartMs = nowMs;
                    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
                } else {
                    s_state = TL_WIFI_STATE_IDLE;
                }
            }
            break;
        }

        case TL_WIFI_STATE_DISCONNECTED: {
            // Auto-reconnect after brief quiet period without blocking
            if (s_slots[0].configured || s_slots[1].configured) {
                s_state = TL_WIFI_STATE_BACKOFF;
                s_backoffEndMs = nowMs + 3000;
            } else {
                s_state = TL_WIFI_STATE_IDLE;
            }
            break;
        }

        case TL_WIFI_STATE_CONNECTED: {
            if (WiFi.status() != WL_CONNECTED) {
                Serial.printf("[WiFi] Connection lost on Slot %d -> initiating failover/reconnect...\n", (int)s_activeSlot);
                emitWifiStatus(TL_WIFI_STATE_DISCONNECTED, TL_WIFI_REASON_NONE);
                s_slots[s_targetSlot - 1].failCount++;
                uint8_t altSlot = (s_targetSlot == 1) ? 2 : 1;
                if (s_slots[altSlot - 1].configured) {
                    s_targetSlot = altSlot;
                }
                WiFi.mode(WIFI_STA);
                WiFi.begin(s_slots[s_targetSlot - 1].ssid.c_str(), s_slots[s_targetSlot - 1].psk.c_str());
                s_state = TL_WIFI_STATE_CONNECTING;
                s_phaseStartMs = nowMs;
                emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
                return;
            }

            // Failback Hysteresis: If currently on Backup Slot 2, passively test if Primary Slot 1 is back
            if (s_activeSlot == 2 && s_slots[0].configured && (nowMs - s_lastFailbackCheckMs >= FAILBACK_CHECK_INTERVAL_MS)) {
                s_lastFailbackCheckMs = nowMs;
                Serial.println("[WiFi] Active on Backup Slot 2 -> running background scan to check Primary Slot 1 presence...");
                WiFi.scanNetworks(true, false);
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
    if (s_state == TL_WIFI_STATE_SCANNING) {
        Serial.println("[WiFi] Scan already in progress");
        return;
    }
    Serial.println("[WiFi] Starting 2.4 GHz asynchronous AP scan (non-destructive)...");
    WiFi.mode(WIFI_STA);
    // Non-destructive: DO NOT disconnect or erase AP config!

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

void wifiManagerConnect(uint8_t slot, const String& ssid, const String& psk, bool saveOnSuccess) {
    if (s_otaPaused) return;
    if (slot != 1 && slot != 2) slot = 1;

    if (ssid.length() == 0 || ssid.length() > 32 || psk.length() > 64) {
        emitWifiStatus(TL_WIFI_STATE_FAILED, TL_WIFI_REASON_AUTH);
        return;
    }

    s_pendingSlot = slot;
    s_pendingSsid = ssid;
    s_pendingPsk = psk;
    s_saveOnSuccess = saveOnSuccess;
    s_targetSlot = slot;
    s_backoffCycle = 0;
    s_slots[slot - 1].failCount = 0;

    Serial.printf("[WiFi] Connect requested: Slot %d, SSID='%s', save=%d\n", (int)slot, ssid.c_str(), (int)saveOnSuccess);

    WiFi.disconnect(false, false);
    delay(30);
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid.c_str(), psk.c_str());

    s_state = TL_WIFI_STATE_CONNECTING;
    s_phaseStartMs = millis();
    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
}

void wifiManagerConnect(const String& ssid, const String& psk, bool saveOnSuccess) {
    wifiManagerConnect(1, ssid, psk, saveOnSuccess);
}

void wifiManagerSwitchSlot(uint8_t slot) {
    if (s_otaPaused) return;
    if (slot != 1 && slot != 2) return;
    if (!s_slots[slot - 1].configured) {
        Serial.printf("[WiFi] Cannot switch to Slot %d -> not configured\n", (int)slot);
        return;
    }

    Serial.printf("[WiFi] Manual switch requested -> Slot %d ('%s')\n", (int)slot, s_slots[slot - 1].ssid.c_str());
    s_targetSlot = slot;
    s_saveOnSuccess = false;
    s_pendingSsid = "";
    s_pendingPsk = "";
    s_slots[slot - 1].failCount = 0;
    s_backoffCycle = 0;

    WiFi.disconnect(false, false);
    delay(30);
    WiFi.mode(WIFI_STA);
    WiFi.begin(s_slots[slot - 1].ssid.c_str(), s_slots[slot - 1].psk.c_str());

    s_state = TL_WIFI_STATE_CONNECTING;
    s_phaseStartMs = millis();
    emitWifiStatus(TL_WIFI_STATE_CONNECTING, TL_WIFI_REASON_NONE);
}

void wifiManagerForget(uint8_t slot) {
    Serial.printf("[WiFi] Forget network requested -> Slot %d\n", (int)slot);
    wipeSlotCredsFromNvs(slot);
    if (slot == 0 || s_activeSlot == 0) {
        WiFi.disconnect(true, false);
        WiFi.mode(WIFI_OFF);
        s_state = TL_WIFI_STATE_IDLE;
        emitWifiStatus(TL_WIFI_STATE_IDLE, TL_WIFI_REASON_NONE);
    } else {
        wifiManagerSwitchSlot(s_activeSlot);
    }
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
    if (s_activeSlot >= 1 && s_activeSlot <= 2 && s_slots[s_activeSlot - 1].configured) {
        return s_slots[s_activeSlot - 1].ssid;
    }
    return "";
}

String wifiManagerGetIp() {
    return (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
}

int8_t wifiManagerGetRssi() {
    return (WiFi.status() == WL_CONNECTED) ? (int8_t)WiFi.RSSI() : 0;
}

uint8_t wifiManagerGetActiveSlot() {
    return s_activeSlot;
}

String wifiManagerGetSlotSsid(uint8_t slot) {
    if (slot == 1) return s_slots[0].ssid;
    if (slot == 2) return s_slots[1].ssid;
    return "";
}

bool wifiManagerIsSlotConfigured(uint8_t slot) {
    if (slot == 1) return s_slots[0].configured;
    if (slot == 2) return s_slots[1].configured;
    return false;
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
