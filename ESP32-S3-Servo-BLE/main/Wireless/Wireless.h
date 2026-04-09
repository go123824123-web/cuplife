#pragma once

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

// BLE GATT Server – matches existing iOS ServoController UUIDs exactly
// Service UUID:        59462F12-9543-9999-12C8-58B459A2712D
// Characteristic UUID: 33333333-2222-2222-1111-111100000000
// Command format: "servo:<angle>"  e.g. "servo:90"

void Wireless_Init(void);
