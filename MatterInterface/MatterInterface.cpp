//===----------------------------------------------------------------------===//
//
// Shim implementations bridging Embedded Swift to ESP-IDF C/C++ APIs.
//
//===----------------------------------------------------------------------===//

#include "MatterInterface.h"

#include <cstdint>
#include <cstdio>
#include <cstring>

#include "driver/spi_master.h"
#include "esp_event.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"

static const char *TAG = "shims";

// ============================================================
// WiFi
// ============================================================

#define WIFI_CONNECTED_BIT BIT0

static EventGroupHandle_t s_wifi_event_group = NULL;

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data) {
  if (event_base == WIFI_EVENT) {
    if (event_id == WIFI_EVENT_STA_START) {
      esp_wifi_connect();
    } else if (event_id == WIFI_EVENT_STA_DISCONNECTED) {
      ESP_LOGW(TAG, "WiFi disconnected, reconnecting...");
      esp_wifi_connect();
      xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
  } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
    xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
  }
}

extern "C" esp_err_t wifi_init_sta_shim(const char *ssid,
                                        const char *password) {
  s_wifi_event_group = xEventGroupCreate();

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_create_default_wifi_sta();

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));

  esp_event_handler_instance_t instance_any_id;
  esp_event_handler_instance_t instance_got_ip;
  ESP_ERROR_CHECK(esp_event_handler_instance_register(
      WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL,
      &instance_any_id));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(
      IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL,
      &instance_got_ip));

  wifi_config_t wifi_config = {};
  strncpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid) - 1);
  strncpy((char *)wifi_config.sta.password, password,
          sizeof(wifi_config.sta.password) - 1);
  wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
  ESP_ERROR_CHECK(esp_wifi_start());

  ESP_LOGI(TAG, "wifi_init_sta finished, waiting for connection...");

  EventBits_t bits =
      xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT, pdFALSE,
                          pdFALSE, pdMS_TO_TICKS(15000));

  if (bits & WIFI_CONNECTED_BIT) {
    ESP_LOGI(TAG, "Connected to WiFi");
    return ESP_OK;
  }
  ESP_LOGW(TAG, "WiFi connection timeout (will keep retrying in background)");
  return ESP_ERR_TIMEOUT;
}

extern "C" bool wifi_is_connected_shim(void) {
  if (!s_wifi_event_group)
    return false;
  return (xEventGroupGetBits(s_wifi_event_group) & WIFI_CONNECTED_BIT) != 0;
}

extern "C" void printStationIP(void) {
  esp_netif_ip_info_t ip_info;
  esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (netif && esp_netif_get_ip_info(netif, &ip_info) == ESP_OK) {
    printf("IP address: " IPSTR "\n", IP2STR(&ip_info.ip));
  }
}

// ============================================================
// HTTP POST
// ============================================================

extern "C" esp_err_t http_post_shim(const char *url, const char *post_data,
                                    int data_len, int *out_status_code) {
  esp_http_client_config_t config = {};
  config.url = url;
  config.method = HTTP_METHOD_POST;
  config.timeout_ms = 10000;

  esp_http_client_handle_t client = esp_http_client_init(&config);
  if (!client)
    return ESP_FAIL;

  esp_http_client_set_header(client, "Content-Type", "application/json");
  esp_http_client_set_post_field(client, post_data, data_len);

  esp_err_t err = esp_http_client_perform(client);
  if (err == ESP_OK) {
    int status = esp_http_client_get_status_code(client);
    if (out_status_code)
      *out_status_code = status;
    ESP_LOGI(TAG, "HTTP POST status=%d, content_length=%lld", status,
             esp_http_client_get_content_length(client));
  } else {
    ESP_LOGE(TAG, "HTTP POST failed: %s", esp_err_to_name(err));
  }

  esp_http_client_cleanup(client);
  return err;
}

// ============================================================
// JSON formatting
// ============================================================

extern "C" int snprintf_sensor_json_shim(char *buf, int buf_size,
                                         float temperature, float humidity,
                                         float soil_moisture) {
  return snprintf(
      buf, buf_size,
      "{\"temperature\":%.2f,\"humidity\":%.2f,\"soil_moisture\":%.2f}",
      temperature, humidity, soil_moisture);
}

// ============================================================
// FreeRTOS notification shims
// ============================================================

extern "C" {

uint32_t ulTaskNotifyTake_shim(int32_t xClearCountOnExit,
                               uint32_t xTicksToWait) {
  return ulTaskNotifyTake((BaseType_t)xClearCountOnExit,
                          (TickType_t)xTicksToWait);
}

void vTaskNotifyGiveFromISR_shim(uint64_t xTaskToNotify,
                                 int32_t *pxHigherPriorityTaskWoken) {
  vTaskNotifyGiveFromISR((TaskHandle_t)xTaskToNotify,
                         (BaseType_t *)pxHigherPriorityTaskWoken);
}

void portYIELD_FROM_ISR_shim(int32_t xHigherPriorityTaskWoken) {
  if (xHigherPriorityTaskWoken) {
    portYIELD_FROM_ISR();
  }
}

void xTaskNotifyGive_shim(uint64_t xTaskToNotify) {
  xTaskNotifyGive((TaskHandle_t)xTaskToNotify);
}

} // extern "C"

// ============================================================
// SPI master shims
// ============================================================

extern "C" esp_err_t spi_bus_init_shim(int32_t host, int32_t mosi_pin,
                                       int32_t miso_pin, int32_t sclk_pin,
                                       int32_t max_transfer_sz) {
  spi_bus_config_t bus_cfg = {};
  bus_cfg.mosi_io_num = mosi_pin;
  bus_cfg.miso_io_num = miso_pin;
  bus_cfg.sclk_io_num = sclk_pin;
  bus_cfg.quadwp_io_num = -1;
  bus_cfg.quadhd_io_num = -1;
  bus_cfg.max_transfer_sz = max_transfer_sz;
  return spi_bus_initialize((spi_host_device_t)host, &bus_cfg, SPI_DMA_CH_AUTO);
}

extern "C" esp_err_t spi_add_device_shim(int32_t host, int32_t cs_pin,
                                         int32_t clock_speed_hz, int32_t mode,
                                         int32_t queue_size,
                                         void **out_handle) {
  spi_device_interface_config_t dev_cfg = {};
  dev_cfg.clock_speed_hz = clock_speed_hz;
  dev_cfg.mode = mode;
  dev_cfg.spics_io_num = cs_pin;
  dev_cfg.queue_size = queue_size;
  return spi_bus_add_device((spi_host_device_t)host, &dev_cfg,
                            (spi_device_handle_t *)out_handle);
}

extern "C" esp_err_t spi_transfer_shim(void *handle, const uint8_t *tx_data,
                                       uint8_t *rx_data, size_t length) {
  spi_transaction_t trans = {};
  trans.length = length * 8; // length in bits
  trans.tx_buffer = tx_data;
  trans.rx_buffer = rx_data;
  return spi_device_transmit((spi_device_handle_t)handle, &trans);
}

extern "C" esp_err_t spi_remove_device_shim(void *handle) {
  return spi_bus_remove_device((spi_device_handle_t)handle);
}

extern "C" esp_err_t spi_bus_free_shim(int32_t host) {
  return spi_bus_free((spi_host_device_t)host);
}
