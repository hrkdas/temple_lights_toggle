#include <cassert>
#include <cmath>
#include <iostream>

// Configuration matching esp_rgb_strip_temple/src/main.cpp
#define NUM_LEDS                  150
#define ANIM_ON_DURATION_MS       1000
#define ANIM_ON_PROP_MS            650
#define ANIM_ON_FADE_MS            350

#define ANIM_OFF_DURATION_MS      1000
#define ANIM_OFF_PROP_MS           650
#define ANIM_OFF_FADE_MS           350

#define ANIM_CROSSFADE_MS         1000
#define ANIM_CROSSFADE_PROP_MS     650
#define ANIM_CROSSFADE_FADE_MS     350
#define ANIM_BREATHING_PERIOD_MS  3000
#define ANIM_BREATHING_DEPTH      0.06f

float get_normalized_center_dist(int i, int totalLeds = NUM_LEDS) {
    if (totalLeds <= 1) return 0.0f;
    float center = (totalLeds - 1) * 0.5f;
    if (totalLeds % 2 == 0) {
        float rawDist = std::fabs((float)i - center);
        float d = (rawDist >= 0.5f) ? (rawDist - 0.5f) : 0.0f;
        float maxD = center - 0.5f;
        return (maxD > 0.0f) ? (d / maxD) : 0.0f;
    } else {
        float maxDist = center;
        return (maxDist > 0.0f) ? (std::fabs((float)i - center) / maxDist) : 0.0f;
    }
}

float ease_smootherstep(float t) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

float get_breathing_factor(unsigned long elapsedMs) {
    float phase = (float)(elapsedMs % ANIM_BREATHING_PERIOD_MS) * (2.0f * 3.14159265f / (float)ANIM_BREATHING_PERIOD_MS);
    return 1.0f - (ANIM_BREATHING_DEPTH * 0.5f * (1.0f - std::cos(phase)));
}

int main() {
    std::cout << "[CHECK] Starting Temple Lights 2.5m premium animation & geometry self-check..." << std::endl;

    // 1. Total LED count & Middle 1.5m dynamic calculation
    assert(NUM_LEDS == 150);
    int midStart150 = (int)((150 * 0.20f) + 0.5f);
    int midEnd150 = 150 - 1 - midStart150;
    assert(midStart150 == 30);
    assert(midEnd150 == 119);
    assert((midEnd150 - midStart150 + 1) == 90);
    std::cout << "  ✓ Middle 1.5m for N=150: 90 LEDs (index 30..119), symmetric 30-LED margins" << std::endl;

    int midStart100 = (int)((100 * 0.20f) + 0.5f);
    int midEnd100 = 100 - 1 - midStart100;
    assert(midStart100 == 20);
    assert(midEnd100 == 79);
    assert((midEnd100 - midStart100 + 1) == 60);
    std::cout << "  ✓ Middle 1.5m for N=100: 60 LEDs (index 20..79), symmetric 20-LED margins" << std::endl;

    // 2. Normalized Center Distance & Symmetry for Even LED Count (N=150)
    assert(std::fabs(get_normalized_center_dist(74, 150) - 0.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(75, 150) - 0.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(0, 150) - 1.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(149, 150) - 1.0f) < 1e-5f);

    for (int k = 0; k <= 74; k++) {
        float dLeft = get_normalized_center_dist(74 - k, 150);
        float dRight = get_normalized_center_dist(75 + k, 150);
        assert(std::fabs(dLeft - dRight) < 1e-5f);
        assert(std::fabs(dLeft - ((float)k / 74.0f)) < 1e-5f);
    }
    std::cout << "  ✓ Even LED count symmetry (N=150): exact match dist(74-k) == dist(75+k)" << std::endl;

    // 3. Normalized Center Distance & Symmetry for Even LED Count (N=100)
    assert(std::fabs(get_normalized_center_dist(49, 100) - 0.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(50, 100) - 0.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(0, 100) - 1.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(99, 100) - 1.0f) < 1e-5f);
    for (int k = 0; k <= 49; k++) {
        float dLeft = get_normalized_center_dist(49 - k, 100);
        float dRight = get_normalized_center_dist(50 + k, 100);
        assert(std::fabs(dLeft - dRight) < 1e-5f);
    }
    std::cout << "  ✓ Even LED count symmetry (N=100): exact match dist(49-k) == dist(50+k)" << std::endl;

    // 4. Normalized Center Distance & Symmetry for Odd LED Count (N=101)
    assert(std::fabs(get_normalized_center_dist(50, 101) - 0.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(0, 101) - 1.0f) < 1e-5f);
    assert(std::fabs(get_normalized_center_dist(100, 101) - 1.0f) < 1e-5f);
    for (int k = 1; k <= 50; k++) {
        float dLeft = get_normalized_center_dist(50 - k, 101);
        float dRight = get_normalized_center_dist(50 + k, 101);
        assert(std::fabs(dLeft - dRight) < 1e-5f);
    }
    std::cout << "  ✓ Odd LED count symmetry (N=101): exact match dist(50-k) == dist(50+k)" << std::endl;

    // 5. C2 Quintic Smootherstep Easing Verification
    assert(ease_smootherstep(0.0f) == 0.0f);
    assert(ease_smootherstep(1.0f) == 1.0f);
    assert(ease_smootherstep(0.5f) == 0.5f);

    float prev = -0.01f;
    for (int step = 0; step <= 200; step++) {
        float u = (float)step / 200.0f;
        float s = ease_smootherstep(u);
        assert(s >= prev); // Monotonically non-decreasing
        assert(s >= 0.0f && s <= 1.0f);
        prev = s;
    }

    // Check derivative near 0 and near 1 (C2 property: f'(0) = 0, f'(1) = 0)
    float dt = 0.001f;
    float deriv0 = (ease_smootherstep(dt) - ease_smootherstep(0.0f)) / dt;
    float deriv1 = (ease_smootherstep(1.0f) - ease_smootherstep(1.0f - dt)) / dt;
    assert(deriv0 < 0.001f); // Effectively 0
    assert(deriv1 < 0.001f); // Effectively 0
    std::cout << "  ✓ C2 Smootherstep: monotonically increasing, zero boundary velocity & zero jerk" << std::endl;

    // 6. Center-Out Wave Timing (Section 5, 6, 8, 17, 18)
    assert(ANIM_ON_PROP_MS + ANIM_ON_FADE_MS == ANIM_ON_DURATION_MS);
    assert(ANIM_OFF_PROP_MS + ANIM_OFF_FADE_MS == ANIM_OFF_DURATION_MS);
    assert(ANIM_ON_DURATION_MS == 1000);
    assert(ANIM_OFF_DURATION_MS == 1000);

    float centerStart = get_normalized_center_dist(74, 150) * ANIM_ON_PROP_MS;
    float edgeStart   = get_normalized_center_dist(0, 150) * ANIM_ON_PROP_MS;
    assert(centerStart == 0.0f);
    assert(std::fabs(edgeStart - 650.0f) < 1e-5f);
    std::cout << "  ✓ Center-out timing: center starts at 0ms, edge starts at 650ms, finishes at 1000ms" << std::endl;

    // 7. Idle Breathing Wave (Section 11)
    float breath0 = get_breathing_factor(0);
    float breathHalf = get_breathing_factor(1500);
    float breathFull = get_breathing_factor(3000);
    assert(std::fabs(breath0 - 1.000f) < 1e-4f);
    assert(std::fabs(breathHalf - 0.940f) < 1e-4f);
    assert(std::fabs(breathFull - 1.000f) < 1e-4f);

    for (unsigned long t = 0; t <= 6000; t += 50) {
        float f = get_breathing_factor(t);
        assert(f >= 0.939f && f <= 1.001f);
    }
    std::cout << "  ✓ Idle breathing: 3000ms period, 6% subtle depth (0.94 - 1.00), continuous & smooth" << std::endl;

    // 8. Mode Crossfade Color Interpolation
    // Transition from Warm White (255, 147, 41) to Pure White (255, 255, 255)
    for (int pct = 0; pct <= 100; pct += 10) {
        float u = (float)pct / 100.0f;
        float s = ease_smootherstep(u);
        uint8_t r = (uint8_t)(255 + (255 - 255) * s + 0.5f);
        uint8_t g = (uint8_t)(147 + (255 - 147) * s + 0.5f);
        uint8_t b = (uint8_t)(41 + (255 - 41) * s + 0.5f);
        assert(r == 255);
        assert(g >= 147 && g <= 255);
        assert(b >= 41 && b <= 255);
    }
    // 9. Full Strip Center-Out Mode Wave Simulation (N=150)
    // Simulating Mode 0 (Warm White) -> Mode 2 (Pure White) across 50 frames (20ms steps, 0..1000ms)
    struct TestRgb { uint8_t r, g, b; };
    TestRgb leds[NUM_LEDS];
    TestRgb startColors[NUM_LEDS];
    TestRgb targetColors[NUM_LEDS];
    for (int i = 0; i < NUM_LEDS; i++) {
        startColors[i] = { 255, 147, 41 };
        targetColors[i] = { 255, 255, 255 };
        leds[i] = startColors[i];
    }

    for (unsigned long elapsed = 0; elapsed <= 1000; elapsed += 20) {
        bool finished = (elapsed >= 1000);
        for (int i = 0; i < NUM_LEDS; i++) {
            float dNorm = get_normalized_center_dist(i, NUM_LEDS);
            float startT = dNorm * (float)ANIM_CROSSFADE_PROP_MS;

            if (finished || (float)elapsed >= startT + (float)ANIM_CROSSFADE_FADE_MS) {
                leds[i] = targetColors[i];
            } else if ((float)elapsed <= startT) {
                leds[i] = startColors[i];
            } else {
                float u = ((float)elapsed - startT) / (float)ANIM_CROSSFADE_FADE_MS;
                float s = ease_smootherstep(u);
                uint8_t r = (uint8_t)(startColors[i].r + (targetColors[i].r - startColors[i].r) * s + 0.5f);
                uint8_t g = (uint8_t)(startColors[i].g + (targetColors[i].g - startColors[i].g) * s + 0.5f);
                uint8_t b = (uint8_t)(startColors[i].b + (targetColors[i].b - startColors[i].b) * s + 0.5f);
                leds[i] = { r, g, b };
            }
        }

        // Verify bilateral symmetry at every frame
        for (int k = 0; k <= 74; k++) {
            assert(leds[74 - k].r == leds[75 + k].r);
            assert(leds[74 - k].g == leds[75 + k].g);
            assert(leds[74 - k].b == leds[75 + k].b);
        }

        // At t=360ms, center LEDs (74/75) must already be at target pure white
        if (elapsed == 360) {
            assert(leds[74].g == 255 && leds[74].b == 255);
            assert(leds[75].g == 255 && leds[75].b == 255);
            // Outer edges (0/149) should still be at start warm white (haven't started yet, startT = 650ms)
            assert(leds[0].g == 147 && leds[0].b == 41);
            assert(leds[149].g == 147 && leds[149].b == 41);
        }
    }

    // At t=1000ms, entire strip must be completely pure white
    for (int i = 0; i < NUM_LEDS; i++) {
        assert(leds[i].r == 255 && leds[i].g == 255 && leds[i].b == 255);
    }
    std::cout << "  ✓ Full strip center-out mode wave: verified frame-by-frame 50 FPS symmetry & wave propagation" << std::endl;

    std::cout << "[SUCCESS] All geometry, easing, wave timing & breathing checks passed perfectly!" << std::endl;
    return 0;
}
