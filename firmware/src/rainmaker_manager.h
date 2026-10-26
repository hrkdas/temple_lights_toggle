#pragma once

#include <Arduino.h>

// ============================================================================
// TEMPLE LIGHTS: ESP RAINMAKER & GOOGLE HOME UNIFIED CLOUD CONTROLLER
// ============================================================================

// Lifecycle hooks
void rainmakerManagerInit(const char* deviceName);
void rainmakerManagerTick(unsigned long nowMs);

// State Synchronization (Hardware / BLE / Schedules -> RainMaker & Google Home)
void rainmakerManagerReportState(bool is_on, uint8_t brightness, uint8_t r, uint8_t g, uint8_t b, int kelvin, int presetIdx);
void rainmakerManagerUpdateDeviceName(const char* newName);

// OTA Protection Gates
void rainmakerManagerPauseForOta();
void rainmakerManagerResumeAfterOta();

// Query Helpers
bool rainmakerManagerIsRunning();
bool rainmakerManagerIsCloudConnected();
const char* rainmakerManagerGetNodeId();
