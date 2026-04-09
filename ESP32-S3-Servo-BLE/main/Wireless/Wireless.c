// BLE GATT Server for Servo Control
//Advertises as "Servo-BLE", accepts "servo:<angle>" commands via BLE write
// UUID matches iOS ServoController app exactly (zero iOS-side changes needed)

#include "Wireless.h"
#include "Servo_Driver.h"

#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_main.h"
#include "esp_gatt_common_api.h"
#include "esp_system.h"
#include <stdlib.h>

static const char *TAG = "BLE_SERVO";

// ─── UUIDs (must match iOS ServoController) ────────────────────────────────
#define GATTS_SERVICE_UUID   0x59462F12   // only used as tag; full UUID below
#define GATTS_NUM_HANDLE     4

// 128-bit service UUID: 59462F12-9543-9999-12C8-58B459A2712D
static uint8_t svc_uuid128[16] = {
    0x2D, 0x71, 0xA2, 0x59, 0xB4, 0x58, 0xC8, 0x12,
    0x99, 0x99, 0x43, 0x95, 0x12, 0x2F, 0x46, 0x59
};

// 128-bit characteristic UUID: 33333333-2222-2222-1111-111100000000
static uint8_t chr_uuid128[16] = {
    0x00, 0x00, 0x00, 0x00, 0x11, 0x11, 0x11, 0x11,
    0x22, 0x22, 0x22, 0x22, 0x33, 0x33, 0x33, 0x33
};

// ─── GATT handles ──────────────────────────────────────────────────────────
static uint16_t s_gatts_if      = ESP_GATT_IF_NONE;
static uint16_t s_service_handle = 0;
static uint16_t s_char_handle    = 0;
static uint16_t s_conn_id        = 0xFFFF;

// ─── Advertisement data ────────────────────────────────────────────────────
static const char *DEVICE_NAME = "Servo-BLE";

static esp_ble_adv_params_t adv_params = {
    .adv_int_min       = 0x20,
    .adv_int_max       = 0x40,
    .adv_type          = ADV_TYPE_IND,
    .own_addr_type     = BLE_ADDR_TYPE_PUBLIC,
    .channel_map       = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

// ─── Command parser ────────────────────────────────────────────────────────
static void handle_ble_command(const uint8_t *data, uint16_t len)
{
    // Expect "servo:<angle>" e.g. "servo:90"
    char buf[32] = {0};
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    memcpy(buf, data, len);
    buf[len] = '\0';

    ESP_LOGI(TAG, "BLE rx: %s", buf);

    if (strncmp(buf, "servo:", 6) == 0) {
        int angle = atoi(buf + 6);
        Servo_SetAngle(angle);
    }
}

// ─── GAP callback ──────────────────────────────────────────────────────────
static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
        esp_ble_gap_start_advertising(&adv_params);
        break;
    case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
        if (param->adv_start_cmpl.status != ESP_BT_STATUS_SUCCESS)
            ESP_LOGE(TAG, "Advertising start failed");
        else
            ESP_LOGI(TAG, "Advertising started as \"%s\"", DEVICE_NAME);
        break;
    default:
        break;
    }
}

// ─── GATTS callback ────────────────────────────────────────────────────────
static void gatts_event_handler(esp_gatts_cb_event_t event,
                                esp_gatt_if_t gatts_if,
                                esp_ble_gatts_cb_param_t *param)
{
    switch (event) {

    case ESP_GATTS_REG_EVT: {
        s_gatts_if = gatts_if;
        ESP_LOGI(TAG, "GATTS reg, app_id=%d", param->reg.app_id);

        // Set device name and start advertising
        esp_ble_gap_set_device_name(DEVICE_NAME);

        esp_ble_adv_data_t adv_data = {
            .set_scan_rsp        = false,
            .include_name        = true,
            .include_txpower     = false,
            .min_interval        = 0x0006,
            .max_interval        = 0x0010,
            .appearance          = 0x00,
            .manufacturer_len    = 0,
            .p_manufacturer_data = NULL,
            .service_data_len    = 0,
            .p_service_data      = NULL,
            .service_uuid_len    = 0,
            .p_service_uuid      = NULL,
            .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
        };
        esp_ble_gap_config_adv_data(&adv_data);

        // Create service with 128-bit UUID
        esp_gatt_srvc_id_t svc_id = {
            .is_primary = true,
            .id = {
                .inst_id = 0,
                .uuid = {
                    .len = ESP_UUID_LEN_128,
                },
            },
        };
        memcpy(svc_id.id.uuid.uuid.uuid128, svc_uuid128, 16);
        esp_ble_gatts_create_service(gatts_if, &svc_id, GATTS_NUM_HANDLE);
        break;
    }

    case ESP_GATTS_CREATE_EVT: {
        s_service_handle = param->create.service_handle;
        esp_ble_gatts_start_service(s_service_handle);

        // Add writable characteristic
        esp_bt_uuid_t chr_uuid = {
            .len = ESP_UUID_LEN_128,
        };
        memcpy(chr_uuid.uuid.uuid128, chr_uuid128, 16);

        esp_gatt_char_prop_t prop = ESP_GATT_CHAR_PROP_BIT_WRITE |
                                    ESP_GATT_CHAR_PROP_BIT_WRITE_NR;
        esp_attr_value_t char_val = {
            .attr_max_len = 32,
            .attr_len     = 0,
            .attr_value   = NULL,
        };
        esp_ble_gatts_add_char(s_service_handle, &chr_uuid, ESP_GATT_PERM_WRITE,
                               prop, &char_val, NULL);
        break;
    }

    case ESP_GATTS_ADD_CHAR_EVT:
        s_char_handle = param->add_char.attr_handle;
        ESP_LOGI(TAG, "Characteristic added, handle=0x%04x", s_char_handle);
        break;

    case ESP_GATTS_CONNECT_EVT:
        s_conn_id = param->connect.conn_id;
        ESP_LOGI(TAG, "Client connected, conn_id=%d", s_conn_id);
        // Stop advertising while connected
        esp_ble_gap_stop_advertising();
        break;

    case ESP_GATTS_DISCONNECT_EVT:
        s_conn_id = 0xFFFF;
        ESP_LOGI(TAG, "Client disconnected, restarting advertising");
        esp_ble_gap_start_advertising(&adv_params);
        break;

    case ESP_GATTS_WRITE_EVT:
        if (!param->write.is_prep) {
            handle_ble_command(param->write.value, param->write.len);
            // Send response if needed
            if (param->write.need_rsp) {
                esp_ble_gatts_send_response(gatts_if, param->write.conn_id,
                                            param->write.trans_id,
                                            ESP_GATT_OK, NULL);
            }
        }
        break;

    default:
        break;
    }
}

// ─── Public init ───────────────────────────────────────────────────────────
void Wireless_Init(void)
{
    // NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Release classic BT memory (we only use BLE)
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));

    // Init BT controller
    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ret = esp_bt_controller_init(&bt_cfg);
    if (ret) { ESP_LOGE(TAG, "bt controller init failed: %s", esp_err_to_name(ret)); return; }

    ret = esp_bt_controller_enable(ESP_BT_MODE_BLE);
    if (ret) { ESP_LOGE(TAG, "bt controller enable failed: %s", esp_err_to_name(ret)); return; }

    ret = esp_bluedroid_init();
    if (ret) { ESP_LOGE(TAG, "bluedroid init failed: %s", esp_err_to_name(ret)); return; }

    ret = esp_bluedroid_enable();
    if (ret) { ESP_LOGE(TAG, "bluedroid enable failed: %s", esp_err_to_name(ret)); return; }

    ESP_ERROR_CHECK(esp_ble_gap_register_callback(gap_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(gatts_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(0));
    ESP_ERROR_CHECK(esp_ble_gatt_set_local_mtu(512));

    ESP_LOGI(TAG, "BLE GATT Server initialized");
}
