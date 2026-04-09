#pragma once

#include "esp_err.h"
#include <stdint.h>

// Servo connected to GPIO1, uses LEDC_TIMER_1 + LEDC_CHANNEL_1
// (LEDC_TIMER_0 / CHANNEL_0 is taken by LCD backlight on GPIO5)

#define SERVO_GPIO          1
#define SERVO_LEDC_TIMER    LEDC_TIMER_1
#define SERVO_LEDC_CHANNEL  LEDC_CHANNEL_1
#define SERVO_FREQ_HZ       50      // Standard servo: 50 Hz (20 ms period)
#define SERVO_RESOLUTION    LEDC_TIMER_14_BIT  // 0~16383

// Pulse width mapping (µs) → typical SG90 / MG90S
#define SERVO_MIN_PULSE_US  500
#define SERVO_MAX_PULSE_US  2500

extern int g_servo_angle;  // current angle 0~180, readable by LVGL

void Servo_Init(void);
void Servo_SetAngle(int angle);  // angle: 0~180
