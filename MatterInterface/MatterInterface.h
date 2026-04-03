//===----------------------------------------------------------------------===//
//
// Shim functions bridging Embedded Swift to ESP-IDF C/C++ APIs.
// Wraps WiFi, HTTP, SPI, and FreeRTOS macros that Swift cannot call directly.
//
//===----------------------------------------------------------------------===//

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// FreeRTOS notification shims (macros not visible to Swift)
uint32_t ulTaskNotifyTake_shim(int32_t xClearCountOnExit,
                               uint32_t xTicksToWait);
void vTaskNotifyGiveFromISR_shim(uint64_t xTaskToNotify,
                                 int32_t *pxHigherPriorityTaskWoken);
void portYIELD_FROM_ISR_shim(int32_t xHigherPriorityTaskWoken);
void xTaskNotifyGive_shim(uint64_t xTaskToNotify);

// SPI master shims
esp_err_t spi_bus_init_shim(int32_t host, int32_t mosi_pin, int32_t miso_pin,
                            int32_t sclk_pin, int32_t max_transfer_sz);
esp_err_t spi_add_device_shim(int32_t host, int32_t cs_pin,
                              int32_t clock_speed_hz, int32_t mode,
                              int32_t queue_size, void **out_handle);
esp_err_t spi_transfer_shim(void *handle, const uint8_t *tx_data,
                            uint8_t *rx_data, size_t length);
esp_err_t spi_remove_device_shim(void *handle);
esp_err_t spi_bus_free_shim(int32_t host);

// WiFi station shims
esp_err_t wifi_init_sta_shim(const char *ssid, const char *password);
bool wifi_is_connected_shim(void);
void printStationIP(void);

// HTTP client shim
esp_err_t http_post_shim(const char *url, const char *post_data, int data_len,
                         int *out_status_code);

// JSON formatting shim (Embedded Swift lacks reliable Float formatting)
int snprintf_sensor_json_shim(char *buf, int buf_size, float temperature,
                              float humidity, float soil_moisture);

#ifdef __cplusplus
}
#endif
