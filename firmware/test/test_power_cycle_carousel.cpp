#include <cassert>
#include <iostream>
#include <vector>
#include <cstdint>
#include <cstring>

// Simulate Firmware Preset & State Structures from main.cpp
#define MAX_PRESETS 16

struct MockPreset {
    char name[24];
    uint8_t brightness;
    bool cycleEnabled;
};

static MockPreset presets[MAX_PRESETS];
static int presetCount = 5;
static uint16_t cycleBitmask = 0x07;
static uint8_t activePresetIndex = 0;
static uint8_t currentMode = 0;

// Mock NVS Key-Value storage
struct MockNVS {
    uint8_t mode = 0;
    uint8_t preset = 0;
    bool hasPresetKey = false;
} nvs;

void mock_save_state() {
    nvs.mode = currentMode;
    nvs.preset = activePresetIndex;
    nvs.hasPresetKey = true;
}

void mock_load_state() {
    currentMode = nvs.mode;
    if (nvs.hasPresetKey) {
        activePresetIndex = nvs.preset;
    } else {
        activePresetIndex = currentMode; // Legacy fallback
    }
    if (currentMode > 3) currentMode = 0;
}

void mock_activate_preset(uint8_t idx) {
    if (idx >= presetCount) idx = 0;
    activePresetIndex = idx;
    currentMode = (idx < 3) ? idx : 3;
}

uint8_t mock_get_next_cycle_preset(uint8_t current) {
    if (presetCount <= 1) return 0;
    for (int step = 1; step <= presetCount; step++) {
        uint8_t candidate = (current + step) % presetCount;
        if (presets[candidate].cycleEnabled) {
            return candidate;
        }
    }
    return (current + 1) % presetCount;
}

void mock_power_cycle_boot() {
    mock_load_state();
    if (activePresetIndex >= presetCount) {
        activePresetIndex = 0;
    }
    uint8_t lastPreset = activePresetIndex;
    uint8_t nextPreset = mock_get_next_cycle_preset(lastPreset);
    mock_activate_preset(nextPreset);
    mock_save_state();
}

void init_factory_presets() {
    presetCount = 5;
    cycleBitmask = 0x07;
    strcpy(presets[0].name, "Warm White");  presets[0].cycleEnabled = true;
    strcpy(presets[1].name, "Center Warm"); presets[1].cycleEnabled = true;
    strcpy(presets[2].name, "Pure White");  presets[2].cycleEnabled = true;
    strcpy(presets[3].name, "Pillar Halo"); presets[3].cycleEnabled = false;
    strcpy(presets[4].name, "Aarti Fire");  presets[4].cycleEnabled = false;
    activePresetIndex = 0;
    currentMode = 0;
    nvs = MockNVS();
    mock_save_state();
}

int main() {
    std::cout << "[CHECK] Starting Temple Lights Power-Cycle Mode Iteration Verification..." << std::endl;

    // Test 1: Factory default presets (0, 1, 2 enabled; 3, 4 disabled)
    init_factory_presets();
    assert(activePresetIndex == 0);

    mock_power_cycle_boot();
    assert(activePresetIndex == 1);
    assert(currentMode == 1);

    mock_power_cycle_boot();
    assert(activePresetIndex == 2);
    assert(currentMode == 2);

    mock_power_cycle_boot();
    // From 2: 3 (false), 4 (false), wraps to 0 (true!)
    assert(activePresetIndex == 0);
    assert(currentMode == 0);
    std::cout << "  ✓ Test 1: Factory 3-mode cyclic wrap (0 -> 1 -> 2 -> 0) verified." << std::endl;

    // Test 2: User creates a new Mode (Preset 5) with cycleEnabled = true
    presetCount = 6;
    strcpy(presets[5].name, "Puja Evening Special");
    presets[5].cycleEnabled = true;
    cycleBitmask |= (1 << 5);

    // Boot from 0 -> 1 -> 2 -> 5 -> 0 -> 1 -> 2 -> 5
    init_factory_presets();
    presetCount = 6;
    strcpy(presets[5].name, "Puja Evening Special");
    presets[5].cycleEnabled = true;
    cycleBitmask |= (1 << 5);

    mock_power_cycle_boot(); // 0 -> 1
    assert(activePresetIndex == 1);
    mock_power_cycle_boot(); // 1 -> 2
    assert(activePresetIndex == 2);
    mock_power_cycle_boot(); // 2 -> 5 (skips 3, 4)
    assert(activePresetIndex == 5);
    assert(currentMode == 3); // Legacy mode is squashed to 3, but activePresetIndex is preserved as 5!
    assert(nvs.preset == 5);  // Critical: Flash remembers preset 5!

    mock_power_cycle_boot(); // 5 -> (5+1)%6 = 0!
    assert(activePresetIndex == 0);
    assert(currentMode == 0);
    assert(nvs.preset == 0);
    std::cout << "  ✓ Test 2: User created preset 5 iterates and cleanly wraps back (2 -> 5 -> 0) without getting stuck!" << std::endl;

    // Test 3: Multiple power cycles around the ring
    std::vector<uint8_t> sequence;
    for (int i = 0; i < 8; i++) {
        mock_power_cycle_boot();
        sequence.push_back(activePresetIndex);
    }
    // Expected cycle: 1, 2, 5, 0, 1, 2, 5, 0
    std::vector<uint8_t> expected = { 1, 2, 5, 0, 1, 2, 5, 0 };
    assert(sequence == expected);
    std::cout << "  ✓ Test 3: 8 consecutive power cycles strictly follow 1 -> 2 -> 5 -> 0 -> 1 -> 2 -> 5 -> 0." << std::endl;

    // Test 4: All presets enabled (0, 1, 2, 3, 4, 5)
    for (int i = 0; i < presetCount; i++) presets[i].cycleEnabled = true;
    activePresetIndex = 0;
    mock_save_state();

    std::vector<uint8_t> allSeq;
    for (int i = 0; i < 12; i++) {
        mock_power_cycle_boot();
        allSeq.push_back(activePresetIndex);
    }
    std::vector<uint8_t> expectedAll = { 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0 };
    assert(allSeq == expectedAll);
    std::cout << "  ✓ Test 4: All 6 presets enabled iterate sequentially: 1 -> 2 -> 3 -> 4 -> 5 -> 0." << std::endl;

    // Test 5: Legacy NVS migration (where "preset" key does not exist yet)
    nvs.hasPresetKey = false;
    nvs.mode = 2; // Old firmware shut down in mode 2
    mock_power_cycle_boot();
    // Adopts mode 2, advances to next enabled preset (Preset 3)
    assert(activePresetIndex == 3);
    assert(nvs.hasPresetKey == true);
    std::cout << "  ✓ Test 5: Legacy NVS flash without 'preset' key safely migrates and continues." << std::endl;

    // Test 6: Fallback when no presets are cycle-enabled
    for (int i = 0; i < presetCount; i++) presets[i].cycleEnabled = false;
    activePresetIndex = 2;
    mock_save_state();
    mock_power_cycle_boot();
    // Fallback: (2 + 1) % 6 = 3
    assert(activePresetIndex == 3);
    std::cout << "  ✓ Test 6: Fallback when all flags disabled advances cyclically within active presetCount." << std::endl;

    std::cout << "[SUCCESS] All Power-Cycle carousel tests passed flawlessly!" << std::endl;
    return 0;
}
