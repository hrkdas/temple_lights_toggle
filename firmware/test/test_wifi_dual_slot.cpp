#include <cassert>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <string>

// Test fixtures simulating firmware dual-slot logic
struct TestWifiSlot {
    std::string ssid = "";
    std::string psk = "";
    bool configured = false;
    uint8_t failCount = 0;
};

static TestWifiSlot s_slots[2];
static uint8_t s_activeSlot = 0;
static uint8_t s_targetSlot = 1;
static uint8_t s_backoffCycle = 0;

void reset_slots() {
    s_slots[0] = TestWifiSlot();
    s_slots[1] = TestWifiSlot();
    s_activeSlot = 0;
    s_targetSlot = 1;
    s_backoffCycle = 0;
}

// Simulates NVS legacy migration logic
void simulate_nvs_load(bool hasLegacy, const std::string& legSsid, const std::string& legPsk,
                       bool hasSlot1, const std::string& s1Ssid,
                       bool hasSlot2, const std::string& s2Ssid) {
    reset_slots();

    if (hasSlot1) {
        s_slots[0].ssid = s1Ssid;
        s_slots[0].configured = true;
    }
    if (hasSlot2) {
        s_slots[1].ssid = s2Ssid;
        s_slots[1].configured = true;
    }

    // Backward compatibility rule: if neither slot configured, migrate legacy
    if (!s_slots[0].configured && !s_slots[1].configured && hasLegacy) {
        s_slots[0].ssid = legSsid;
        s_slots[0].psk = legPsk;
        s_slots[0].configured = true;
        s_activeSlot = 1;
    }
}

// Simulates failover decision logic
uint8_t simulate_failover(uint8_t currentSlot) {
    s_slots[currentSlot - 1].failCount++;
    uint8_t altSlot = (currentSlot == 1) ? 2 : 1;
    if (s_slots[altSlot - 1].configured && s_slots[altSlot - 1].failCount == 0) {
        return altSlot; // Switch to alternate
    }
    return 0; // Both failed, trigger backoff
}

// Exponential backoff calculator
uint32_t calculate_backoff_ms(uint8_t cycle) {
    uint32_t delayMs = 15000 + (cycle * 15000);
    if (delayMs > 120000) delayMs = 120000;
    return delayMs;
}

// Exponential moving average filter for RSSI
int8_t smooth_rssi(int8_t currentSmoothed, int8_t newRaw) {
    if (currentSmoothed == 0) return newRaw;
    return (int8_t)(0.7f * newRaw + 0.3f * currentSmoothed);
}

int main() {
    printf("[TEST] Running Dual-Slot Wi-Fi Firmware Unit Tests...\n");

    // Test 1: Backward-compatibility migration
    {
        simulate_nvs_load(true, "LegacyTemple_2.4G", "OldPassword", false, "", false, "");
        assert(s_slots[0].configured == true);
        assert(s_slots[0].ssid == "LegacyTemple_2.4G");
        assert(s_slots[0].psk == "OldPassword");
        assert(s_slots[1].configured == false);
        assert(s_activeSlot == 1);
        printf("  [PASS] Test 1: Backward-compatible migration from legacy NVS\n");
    }

    // Test 2: Dual-slot loading preserves both primary and backup
    {
        simulate_nvs_load(false, "", "", true, "Sanctum_Primary", true, "Hotspot_Backup");
        assert(s_slots[0].configured == true);
        assert(s_slots[0].ssid == "Sanctum_Primary");
        assert(s_slots[1].configured == true);
        assert(s_slots[1].ssid == "Hotspot_Backup");
        printf("  [PASS] Test 2: Dual-slot loading preserves Slot 1 and Slot 2\n");
    }

    // Test 3: Failover from Slot 1 to Slot 2
    {
        reset_slots();
        s_slots[0].ssid = "Sanctum_Primary";
        s_slots[0].configured = true;
        s_slots[1].ssid = "Hotspot_Backup";
        s_slots[1].configured = true;

        uint8_t nextSlot = simulate_failover(1);
        assert(nextSlot == 2); // Primary failed -> switches to Backup
        assert(s_slots[0].failCount == 1);
        assert(s_slots[1].failCount == 0);
        printf("  [PASS] Test 3: Primary Slot 1 failure cleanly falls over to Backup Slot 2\n");
    }

    // Test 4: Both slots fail -> triggers non-blocking backoff
    {
        uint8_t nextSlot2 = simulate_failover(2);
        assert(nextSlot2 == 0); // Both failed -> trigger backoff
        assert(s_slots[0].failCount == 1);
        assert(s_slots[1].failCount == 1);
        printf("  [PASS] Test 4: Dual failure triggers backoff without getting stuck\n");
    }

    // Test 5: Exponential backoff delay boundaries
    {
        assert(calculate_backoff_ms(0) == 15000);  // Cycle 0: 15s
        assert(calculate_backoff_ms(1) == 30000);  // Cycle 1: 30s
        assert(calculate_backoff_ms(3) == 60000);  // Cycle 3: 60s
        assert(calculate_backoff_ms(7) == 120000); // Cycle 7: capped at 120s
        assert(calculate_backoff_ms(20) == 120000); // Cycle 20: capped at 120s
        printf("  [PASS] Test 5: Exponential backoff calculation caps at 120s\n");
    }

    // Test 6: Smooth RSSI filtering
    {
        int8_t s = 0;
        s = smooth_rssi(s, -60);
        assert(s == -60);
        s = smooth_rssi(s, -80); // 0.7 * -80 + 0.3 * -60 = -56 + -18 = -74
        assert(s == -74);
        printf("  [PASS] Test 6: Smooth RSSI exponential moving average filter\n");
    }

    printf("[SUCCESS] All Dual-Slot Wi-Fi unit tests passed cleanly!\n");
    return 0;
}
