#include "Servo_Driver.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include <stdio.h>

static const char *TAG = "SERVO";

int g_servo_angle = 90;  // default center position

// Convert angle (0~180) to LEDC duty
// Period = 1,000,000 / 50 Hz = 20,000 µs
// Resolution 14-bit → 16384 ticks = 20000 µs
// 1 tick = 20000 / 16384 ≈ 1.2207 µs
static uint32_t angle_to_duty(int angle)
{
    if (angle < 0)   angle = 0;
    if (angle > 180) angle = 180;

    uint32_t period_us = 1000000 / SERVO_FREQ_HZ;           // 20000 µs
    uint32_t max_duty  = (1 << SERVO_RESOLUTION) - 1;       // 16383

    uint32_t pulse_us = SERVO_MIN_PULSE_US +
                        (uint32_t)(angle) * (SERVO_MAX_PULSE_US - SERVO_MIN_PULSE_US) / 180;

    uint32_t duty = (uint32_t)((uint64_t)pulse_us * max_duty / period_us);
    return duty;
}

void Servo_Init(void)
{
    // Timer config
    ledc_timer_config_t timer_conf = {
        .speed_mode      = LEDC_LOW_SPEED_MODE,
        .duty_resolution = SERVO_RESOLUTION,
        .timer_num       = SERVO_LEDC_TIMER,
        .freq_hz         = SERVO_FREQ_HZ,
        .clk_cfg         = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_conf));

    // Channel config
    ledc_channel_config_t ch_conf = {
        .gpio_num   = SERVO_GPIO,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel    = SERVO_LEDC_CHANNEL,
        .timer_sel  = SERVO_LEDC_TIMER,
        .duty       = angle_to_duty(g_servo_angle),
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ch_conf));

    ESP_LOGI(TAG, "Servo init OK on GPIO%d, angle=%d", SERVO_GPIO, g_servo_angle);
}

void Servo_SetAngle(int angle)
{
    if (angle < 0)   angle = 0;
    if (angle > 180) angle = 180;

    g_servo_angle = angle;
    uint32_t duty = angle_to_duty(angle);

    ledc_set_duty(LEDC_LOW_SPEED_MODE, SERVO_LEDC_CHANNEL, duty);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, SERVO_LEDC_CHANNEL);

    ESP_LOGI(TAG, "Servo angle=%d, duty=%lu", angle, duty);
}
