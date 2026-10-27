#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
#include <cstring>

struct RgbColor {
    uint8_t r, g, b;
};

struct TestFirmwareLedSegment {
    uint16_t start;
    uint16_t count;
    uint8_t r, g, b;
    uint8_t brightness;
    uint8_t effect;
    uint8_t speed;
    uint8_t stride;
    uint8_t offset;
    char name[16];

    TestFirmwareLedSegment()
        : start(0), count(0), r(255), g(147), b(41), brightness(255), effect(0), speed(5), stride(1), offset(0) {
        name[0] = '\0';
    }

    TestFirmwareLedSegment(uint16_t s, uint16_t c, uint8_t red, uint8_t green, uint8_t blue, uint8_t br, uint8_t fx, uint8_t spd, uint8_t str = 1, uint8_t off = 0, const char* n = "")
        : start(s), count(c), r(red), g(green), b(blue), brightness(br), effect(fx), speed(spd), stride(str > 0 ? str : 1), offset(off) {
        if (n != nullptr) {
            strncpy(name, n, sizeof(name) - 1);
            name[sizeof(name) - 1] = '\0';
        } else {
            name[0] = '\0';
        }
    }
};

void compute_strided_colors(int numLeds, const std::vector<TestFirmwareLedSegment>& segs, RgbColor* out) {
    for (int i = 0; i < numLeds; i++) {
        out[i] = { 0, 0, 0 };
    }
    for (const auto& seg : segs) {
        int sEnd = seg.start + seg.count;
        if (sEnd > numLeds) sEnd = numLeds;
        float sBright = (float)seg.brightness / 255.0f;
        for (int i = seg.start; i < sEnd; i++) {
            if (seg.stride > 1 && ((i - seg.start) % seg.stride) != seg.offset) {
                continue;
            }
            out[i] = {
                (uint8_t)(seg.r * sBright + 0.5f),
                (uint8_t)(seg.g * sBright + 0.5f),
                (uint8_t)(seg.b * sBright + 0.5f)
            };
        }
    }
}

int main() {
    std::cout << "[CHECK] Running Strided Pattern & Alternate Mode Self-Tests..." << std::endl;

    const int totalLeds = 150;
    RgbColor leds[totalLeds];

    // 1. Dual-Color Alternate Interleaving (Odd: Gold, Even: Blue)
    TestFirmwareLedSegment segOdd(0, totalLeds, 255, 180, 0, 255, 0, 5, 2, 0, "Odd Gold");
    TestFirmwareLedSegment segEven(0, totalLeds, 0, 120, 255, 255, 0, 5, 2, 1, "Even Blue");

    assert(segOdd.stride == 2 && segOdd.offset == 0);
    assert(segEven.stride == 2 && segEven.offset == 1);

    std::vector<TestFirmwareLedSegment> dualSegments = { segOdd, segEven };
    compute_strided_colors(totalLeds, dualSegments, leds);

    for (int i = 0; i < totalLeds; i++) {
        if (i % 2 == 0) {
            // Human Odd LED (#1, #3, #5... -> 0-index 0, 2, 4...)
            assert(leds[i].r == 255);
            assert(leds[i].g == 180);
            assert(leds[i].b == 0);
        } else {
            // Human Even LED (#2, #4, #6... -> 0-index 1, 3, 5...)
            assert(leds[i].r == 0);
            assert(leds[i].g == 120);
            assert(leds[i].b == 255);
        }
    }
    std::cout << "  ✓ Verified Dual-Color Alternate Interleaving across 150 LEDs (Odd=Gold, Even=Blue)" << std::endl;

    // 2. Solo Alternate Phase (Odd only, Even muted/dark)
    std::vector<TestFirmwareLedSegment> soloOdd = { segOdd };
    compute_strided_colors(totalLeds, soloOdd, leds);
    for (int i = 0; i < totalLeds; i++) {
        if (i % 2 == 0) {
            assert(leds[i].r == 255 && leds[i].g == 180 && leds[i].b == 0);
        } else {
            assert(leds[i].r == 0 && leds[i].g == 0 && leds[i].b == 0);
        }
    }
    std::cout << "  ✓ Verified Solo Alternate Phase (Odd active, Even completely dark)" << std::endl;

    // 3. Stride = 1 Contiguous Segment Backward Compatibility
    TestFirmwareLedSegment fullStrip(0, totalLeds, 255, 147, 41, 255, 0, 5, 1, 0, "Full Strip");
    compute_strided_colors(totalLeds, { fullStrip }, leds);
    for (int i = 0; i < totalLeds; i++) {
        assert(leds[i].r == 255 && leds[i].g == 147 && leds[i].b == 41);
    }
    std::cout << "  ✓ Verified 100% Backward Compatibility with Stride = 1 Contiguous Strip" << std::endl;

    std::cout << "[SUCCESS] All native strided pattern self-checks passed flawlessly!" << std::endl;
    return 0;
}
