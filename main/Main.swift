// MARK: - Helpers

/// Convert milliseconds to FreeRTOS ticks.
func msToTicks(_ ms: UInt32) -> UInt32 {
    ms * UInt32(configTICK_RATE_HZ) / 1000
}

// MARK: - Configuration

/// SPI pin assignments (adjust for your wiring)
let spiHost: Int32 = 2  // SPI2_HOST
let spiMOSI = GPIO_NUM_7
let spiMISO = GPIO_NUM_6
let spiSCLK = GPIO_NUM_5
let spiCS   = GPIO_NUM_4

/// WiFi credentials (defined as C globals for safe pointer passing)
let wifiSSID = "Boy1212  2.4G"
let wifiPassword = "0620380499"

/// Server endpoint
let kServerURL = "http://192.168.1.100:8080/api/sensors"

/// How often to read SPI and post (milliseconds)
let sensorReadIntervalMs: UInt32 = 60_000  // 1 minute

/// Retry interval on HTTP failure (milliseconds)
let httpRetryIntervalMs: UInt32 = 300_000  // 5 minutes

// MARK: - Global State

/// Latest sensor reading, updated by SPI task, read by upload task.
var latestSensorData: SensorData? = nil

// MARK: - Entry Point

@_cdecl("app_main")
func main() -> Never {
    print("Irrigation Sensor Gateway - Embedded Swift")

    // Initialize NVS (required for WiFi)
    var nvsErr = nvs_flash_init()
    if nvsErr == ESP_ERR_NVS_NO_FREE_PAGES
        || nvsErr == ESP_ERR_NVS_NEW_VERSION_FOUND {
        nvs_flash_erase()
        nvsErr = nvs_flash_init()
    }

    // Connect to WiFi
    wifiSSID.withCString { ssid in
        wifiPassword.withCString { pass in
            let err = wifi_init_sta_shim(ssid, pass)
            if err == ESP_OK {
                print("WiFi connected")
                printStationIP()
            } else {
                print("WiFi initial connection timed out, will keep retrying...")
            }
        }
    }

    // Initialize SPI
    let spi = SPIDevice(
        host: spiHost,
        mosi: spiMOSI, miso: spiMISO, sclk: spiSCLK, cs: spiCS,
        clockHz: 1_000_000, mode: 0
    )

    // Set up SPI receive callback
    spi.onReceive = { buffer, length in
        if let data = SensorData(from: buffer, length: length) {
            latestSensorData = data
            print("SPI rx: T=\(data.temperature) H=\(data.humidity) SM=\(data.soilMoisture)")
        }
    }

    // Start SPI polling task
    spi.start()

    // Start HTTP upload task
    xTaskCreate(
        uploadTask,
        "upload_task",
        8192,
        nil,
        4,
        nil
    )

    // Main task sleeps forever
    while true { sleep(1) }
}

// MARK: - Upload Task

let uploadTask: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    print("Upload task started")

    // Wait for initial sensor data
    vTaskDelay(msToTicks(5000))

    while true {
        if let data = latestSensorData {
            if wifi_is_connected_shim() {
                let bufferSize = 128
                let jsonBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
                let written = data.writeJSON(to: jsonBuffer, capacity: bufferSize)

                var success = false
                if written > 0 && written < bufferSize {
                    var statusCode: Int32 = 0
                    kServerURL.withCString { url in
                        let err = http_post_shim(url, jsonBuffer, Int32(written), &statusCode)
                        if err == ESP_OK && statusCode >= 200 && statusCode < 300 {
                            print("POST success (status \(statusCode))")
                            success = true
                        } else {
                            print("POST failed (err=\(err), status=\(statusCode))")
                        }
                    }
                }
                jsonBuffer.deallocate()

                if success {
                    vTaskDelay(msToTicks(sensorReadIntervalMs))
                } else {
                    print("Upload failed, retrying in 5 minutes...")
                    vTaskDelay(msToTicks(httpRetryIntervalMs))
                }
            } else {
                print("No WiFi connection, waiting 5 minutes...")
                vTaskDelay(msToTicks(httpRetryIntervalMs))
            }
        } else {
            vTaskDelay(msToTicks(5000))
        }
    }
}
