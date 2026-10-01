#include <cassert>
#include <cstring>
#include <cstdio>
#include <cstdlib>

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
    uint8_t targetMode;
    uint8_t targetBrightness;
    uint8_t targetR;
    uint8_t targetG;
    uint8_t targetB;
    char lastTriggeredKey[24];
};

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

void get_tz_string(int16_t tzOffsetMin, char* out, size_t outLen) {
    if (tzOffsetMin == 330) {
        snprintf(out, outLen, "IST-5:30");
    } else {
        int h = abs(tzOffsetMin) / 60;
        int m = abs(tzOffsetMin) % 60;
        char sign = (tzOffsetMin >= 0) ? '-' : '+';
        snprintf(out, outLen, "UTC%c%d:%02d", sign, h, m);
    }
}

int main() {
    printf("[CHECK] Starting Temple Lights schedule range & timezone self-check...\n");

    // 1. Mumbai Timezone String Verification
    char tz[32];
    get_tz_string(330, tz, sizeof(tz));
    assert(strcmp(tz, "IST-5:30") == 0);
    printf("  ✓ Mumbai timezone is POSIX 'IST-5:30' (UTC+05:30)\n");

    get_tz_string(0, tz, sizeof(tz));
    assert(strcmp(tz, "UTC-0:00") == 0);
    get_tz_string(-300, tz, sizeof(tz));
    assert(strcmp(tz, "UTC+5:00") == 0);

    // 2. Same-Day Schedule: 18:30 to 21:00, Daily (Mask: all days 1..7)
    ScheduleItem s1;
    memset(&s1, 0, sizeof(s1));
    s1.isEnabled = true;
    s1.hasTurnOn = true;
    s1.turnOnHour = 18;
    s1.turnOnMinute = 30;
    s1.hasTurnOff = true;
    s1.turnOffHour = 21;
    s1.turnOffMinute = 0;
    s1.repeatDaysMask = 0xFE; // Bits 1..7 set (1<<1 | 1<<2 | ... | 1<<7)

    // Tests for s1
    assert(!is_schedule_in_range(s1, 1, 18, 29)); // 1 min before -> false
    assert(is_schedule_in_range(s1, 1, 18, 30));  // exact on -> true
    assert(is_schedule_in_range(s1, 1, 19, 45));  // middle -> true (e.g. boot at 19:45)
    assert(is_schedule_in_range(s1, 1, 20, 59));  // 1 min before off -> true
    assert(!is_schedule_in_range(s1, 1, 21, 0));  // exact off -> false
    assert(!is_schedule_in_range(s1, 1, 22, 0));  // after off -> false
    assert(!is_schedule_in_range(s1, 1, 14, 0));  // afternoon boot -> false
    printf("  ✓ Same-day schedule boundaries & middle-range boot check passed\n");

    // 3. Overnight Midnight-Crossing Schedule: 18:00 to 06:00, Daily
    ScheduleItem s2;
    memset(&s2, 0, sizeof(s2));
    s2.isEnabled = true;
    s2.hasTurnOn = true;
    s2.turnOnHour = 18;
    s2.turnOnMinute = 0;
    s2.hasTurnOff = true;
    s2.turnOffHour = 6;
    s2.turnOffMinute = 0;
    s2.repeatDaysMask = 0xFE; // Every day

    assert(!is_schedule_in_range(s2, 3, 17, 59)); // Before on
    assert(is_schedule_in_range(s2, 3, 18, 0));   // Exact on
    assert(is_schedule_in_range(s2, 3, 23, 59));  // Just before midnight
    assert(is_schedule_in_range(s2, 4, 0, 0));    // Midnight next day
    assert(is_schedule_in_range(s2, 4, 2, 30));   // 2:30 AM (boot during night)
    assert(is_schedule_in_range(s2, 4, 5, 59));   // Just before off
    assert(!is_schedule_in_range(s2, 4, 6, 0));   // Off
    assert(!is_schedule_in_range(s2, 4, 12, 0));  // Noon
    printf("  ✓ Overnight midnight-crossing schedule (18:00 -> 06:00) passed\n");

    // 4. Day-Specific Overnight Schedule: Saturday night only (Day 6)
    // 20:00 Saturday to 04:00 Sunday
    ScheduleItem s3;
    memset(&s3, 0, sizeof(s3));
    s3.isEnabled = true;
    s3.hasTurnOn = true;
    s3.turnOnHour = 20;
    s3.turnOnMinute = 0;
    s3.hasTurnOff = true;
    s3.turnOffHour = 4;
    s3.turnOffMinute = 0;
    s3.repeatDaysMask = (1 << 6); // Saturday only

    assert(is_schedule_in_range(s3, 6, 21, 30));  // Saturday night -> true
    assert(is_schedule_in_range(s3, 7, 2, 0));    // Sunday 2 AM (started Saturday) -> true
    assert(!is_schedule_in_range(s3, 7, 21, 30)); // Sunday night -> false
    assert(!is_schedule_in_range(s3, 1, 2, 0));   // Monday 2 AM -> false
    printf("  ✓ Day-of-week overnight mask shift (Saturday -> Sunday AM) passed\n");

    // 5. Disabled Schedule
    s1.isEnabled = false;
    assert(!is_schedule_in_range(s1, 1, 19, 45));
    printf("  ✓ Disabled schedule correctly ignored\n");

    printf("\n[SUCCESS] All 15 schedule range & Mumbai timezone checks passed!\n");
    return 0;
}
