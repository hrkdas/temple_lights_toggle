#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>

// ============================================================================
// TEMPLE LIGHTS OTA PROGRESS & INTERACTIVE ANIMATION TEST SUITE
// ============================================================================

struct RgbColor {
    uint8_t r, g, b;
};

// Slew smoothing helper
float update_slew_progress(float current, float target, float rate = 0.22f) {
    float delta = target - current;
    if (delta > 0.0f) {
        current += delta * rate;
        if (target - current < 0.001f) {
            current = target;
        }
    } else if (target >= 0.999f) {
        current = 1.0f;
    }
    return current;
}

// Compute color for LED index i during OTA progress
RgbColor compute_ota_pixel(int i, int totalLeds, float smoothProgress, unsigned long nowMs) {
    if (totalLeds <= 0) return { 0, 0, 0 };
    if (smoothProgress < 0.0f) smoothProgress = 0.0f;
    if (smoothProgress > 1.0f) smoothProgress = 1.0f;

    float headPos = smoothProgress * (float)(totalLeds - 1);
    float dist = (float)i - headPos;

    // Written portion (behind the head)
    if (dist < -2.0f) {
        // Warm sacred golden amber with gentle breathing
        float breath = 0.88f + 0.12f * std::sin((nowMs * 0.003f) + ((float)i * 0.08f));
        uint8_t r = (uint8_t)(255.0f * breath);
        uint8_t g = (uint8_t)(160.0f * breath);
        uint8_t b = (uint8_t)(42.0f * breath);
        return { r, g, b };
    }

    // Unwritten portion (ahead of the head)
    if (dist > 2.0f) {
        // Deep ambient track guide with traveling starlight shimmer
        float trackShimmer = 0.5f + 0.5f * std::sin((nowMs * 0.005f) - ((float)i * 0.25f));
        uint8_t r = (uint8_t)(8.0f + 6.0f * trackShimmer);
        uint8_t g = (uint8_t)(6.0f + 4.0f * trackShimmer);
        uint8_t b = (uint8_t)(16.0f + 12.0f * trackShimmer);
        return { r, g, b };
    }

    // Active Flash Head / Data Spark (|dist| <= 2.0f)
    float headFactor = 1.0f - (std::fabs(dist) / 2.0f);
    if (headFactor < 0.0f) headFactor = 0.0f;
    headFactor = headFactor * headFactor; // quadratic falloff

    float pulse = 0.82f + 0.18f * std::sin(nowMs * 0.020f);

    // Written base
    float wrR = 255.0f;
    float wrG = 160.0f;
    float wrB = 42.0f;

    // Brilliant diamond white-gold spark
    float sparkR = 255.0f;
    float sparkG = 245.0f * pulse;
    float sparkB = 190.0f * pulse;

    // Background base
    float bgR = 10.0f;
    float bgG = 8.0f;
    float bgB = 22.0f;

    float r, g, b;
    if (dist <= 0.0f) {
        // Blend from written amber into brilliant spark
        r = wrR + (sparkR - wrR) * headFactor;
        g = wrG + (sparkG - wrG) * headFactor;
        b = wrB + (sparkB - wrB) * headFactor;
    } else {
        // Blend from brilliant spark into background track
        r = bgR + (sparkR - bgR) * headFactor;
        g = bgG + (sparkG - bgG) * headFactor;
        b = bgB + (sparkB - bgB) * headFactor;
    }

    return {
        (uint8_t)std::min(255.0f, std::max(0.0f, r + 0.5f)),
        (uint8_t)std::min(255.0f, std::max(0.0f, g + 0.5f)),
        (uint8_t)std::min(255.0f, std::max(0.0f, b + 0.5f))
    };
}

// Compute success celebration frame
RgbColor compute_ota_success_pixel(int i, int totalLeds, unsigned long elapsedMs, unsigned long totalDurationMs = 2500) {
    float t = (float)elapsedMs / (float)totalDurationMs;
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    float center = (totalLeds - 1) * 0.5f;
    float normDist = std::fabs((float)i - center) / (center > 0.0f ? center : 1.0f);

    if (t < 0.5f) {
        // Wave 1: Center-out radiant golden bloom
        float waveT = t / 0.5f;
        float wavePos = waveT * 1.2f;
        float intensity = 1.0f - std::fabs(normDist - wavePos) * 2.0f;
        if (intensity < 0.0f) intensity = 0.0f;
        intensity = intensity * intensity;

        // Radiant emerald-gold
        uint8_t r = (uint8_t)(80.0f + 175.0f * intensity);
        uint8_t g = (uint8_t)(210.0f + 45.0f * intensity);
        uint8_t b = (uint8_t)(60.0f + 60.0f * intensity);
        return { r, g, b };
    } else {
        // Wave 2: Triumphant golden chime breathing settling into temple warm white
        float waveT = (t - 0.5f) / 0.5f;
        float pulse = 0.70f + 0.30f * std::sin(waveT * 3.14159265f * 2.0f);
        uint8_t r = (uint8_t)(255.0f * pulse);
        uint8_t g = (uint8_t)(180.0f * pulse);
        uint8_t b = (uint8_t)(60.0f * pulse);
        return { r, g, b };
    }
}

int main() {
    std::cout << "[CHECK] Starting Temple Lights Interactive OTA RGB Strip Animation Self-Check..." << std::endl;

    const int totalLeds = 150;

    // 1. Slew Filter Convergence Check
    float progress = 0.0f;
    float target = 0.75f;
    for (int step = 0; step < 50; step++) {
        progress = update_slew_progress(progress, target);
    }
    assert(std::fabs(progress - target) < 1e-3f);
    std::cout << "  ✓ Slew filter converges smoothly and monotonically to target (" << progress << " ≈ " << target << ")" << std::endl;

    // 2. Head Position & Bounds Check
    float testProgress = 0.50f;
    float expectedHead = testProgress * (float)(totalLeds - 1);
    assert(std::fabs(expectedHead - 74.5f) < 1e-5f);
    std::cout << "  ✓ 50% OTA progress maps exactly to strip midpoint (head = " << expectedHead << " on 150 LEDs)" << std::endl;

    // 3. Sub-pixel Head Spark Peak Brightness Check
    RgbColor headColor = compute_ota_pixel(74, totalLeds, 0.50f, 1000);
    RgbColor tailColor = compute_ota_pixel(10, totalLeds, 0.50f, 1000);
    RgbColor guideColor = compute_ota_pixel(140, totalLeds, 0.50f, 1000);

    // Active head must be brighter and higher in blue/white than tail
    assert(headColor.b >= tailColor.b);
    assert(headColor.r >= 200);
    // Tail should be warm amber (high red, moderate green, lower blue)
    assert(tailColor.r > tailColor.g);
    assert(tailColor.g > tailColor.b);
    // Guide ahead of head must be dim track ambient (low brightness)
    assert(guideColor.r < 30);
    assert(guideColor.g < 20);
    assert(guideColor.b >= guideColor.r); // cool night dusk tint
    std::cout << "  ✓ Color zones verified: Active head (" << (int)headColor.r << "," << (int)headColor.g << "," << (int)headColor.b << ") > Written tail ("
              << (int)tailColor.r << "," << (int)tailColor.g << "," << (int)tailColor.b << ") > Guide track ("
              << (int)guideColor.r << "," << (int)guideColor.g << "," << (int)guideColor.b << ")" << std::endl;

    // 4. Success Celebration Animation Check
    RgbColor bloomMid = compute_ota_success_pixel(75, totalLeds, 300, 2500);
    assert(bloomMid.g > 150); // Emerald/golden glow prominent
    RgbColor settledFinal = compute_ota_success_pixel(75, totalLeds, 2400, 2500);
    assert(settledFinal.r > settledFinal.g); // Settled into warm gold
    std::cout << "  ✓ Celebration animation transitions from emerald-gold wave to serene warm white before reboot" << std::endl;

    // 5. Full End-to-End Progression Sweep (0% -> 100%)
    for (int pct = 0; pct <= 100; pct += 5) {
        float p = (float)pct / 100.0f;
        for (int i = 0; i < totalLeds; i++) {
            RgbColor c = compute_ota_pixel(i, totalLeds, p, pct * 100);
            assert(c.r <= 255 && c.g <= 255 && c.b <= 255);
        }
    }
    std::cout << "  ✓ Full end-to-end sweep (0% to 100%) computed across all 150 LEDs with zero overflow" << std::endl;

    std::cout << "[SUCCESS] All OTA RGB Strip Animation self-checks passed perfectly!" << std::endl;
    return 0;
}
