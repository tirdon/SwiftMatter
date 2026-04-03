// MARK: - SPI

/// SPI master driver for device-to-device communication.
///
/// Uses ESP-IDF SPI master driver via C shims. Supports full-duplex transfers,
/// send-only, receive-only, and a FreeRTOS polling task for periodic reads.
final class SPIDevice {
    static let maxTransferSize: Int32 = 4096

    private var handle: UnsafeMutableRawPointer? = nil
    private let host: Int32

    /// Poll interval in milliseconds for the FreeRTOS task.
    static var pollIntervalMs: UInt32 = 1_000

    /// Callback invoked on the polling task when data is received.
    /// Parameters: pointer to received buffer, length.
    var onReceive: ((UnsafePointer<UInt8>, Int) -> Void)? = nil

    var taskHandle: TaskHandle_t? = nil

    init(
        host: Int32, mosi: gpio_num_t, miso: gpio_num_t, sclk: gpio_num_t,
        cs: gpio_num_t, clockHz: Int32 = 1_000_000, mode: Int32 = 0
    ) {
        self.host = host

        var err = spi_bus_init_shim(
            host, Int32(mosi.rawValue),
            Int32(miso.rawValue), Int32(sclk.rawValue),
            SPIDevice.maxTransferSize)
        if err != ESP_OK {
            print("SPI bus init failed: \(err)")
        }

        err = spi_add_device_shim(
            host, Int32(cs.rawValue), clockHz, mode, 7,
            &handle)
        if err != ESP_OK {
            print("SPI add device failed: \(err)")
        }

        _ = Unmanaged.passRetained(self)
    }

    // MARK: - Transfer API

    /// Full-duplex transfer: send and receive simultaneously.
    func transfer(
        tx: UnsafePointer<UInt8>?, rx: UnsafeMutablePointer<UInt8>?,
        length: Int
    ) -> esp_err_t {
        guard let handle else { return ESP_ERR_INVALID_STATE }
        return spi_transfer_shim(handle, tx, rx, length)
    }

    /// Send data, discard received bytes.
    func send(_ data: UnsafePointer<UInt8>, length: Int) -> esp_err_t {
        return transfer(tx: data, rx: nil, length: length)
    }

    /// Receive data (transmits zeros on MOSI).
    func receive(
        _ buffer: UnsafeMutablePointer<UInt8>,
        length: Int
    ) -> esp_err_t {
        return transfer(tx: nil, rx: buffer, length: length)
    }

    // MARK: - FreeRTOS Task

    /// Polling task that periodically reads sensor data from SPI slave.
    static let spi_poll_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("SPI Task started")
        guard let param else { return }
        let spi = Unmanaged<SPIDevice>.fromOpaque(param).takeUnretainedValue()
        spi.taskHandle = xTaskGetCurrentTaskHandle()

        let rxSize = SensorData.wireSize
        let rxBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: rxSize)

        while true {
            vTaskDelay(msToTicks(pollIntervalMs))

            let err = spi.receive(rxBuf, length: rxSize)
            if err == ESP_OK {
                spi.onReceive?(UnsafePointer(rxBuf), rxSize)
            } else {
                print("SPI receive failed: \(err)")
            }
        }
    }

    func start() {
        xTaskCreate(
            SPIDevice.spi_poll_task,
            "spi_task",
            4096,
            Unmanaged.passUnretained(self).toOpaque(),
            5,
            nil
        )
    }

    func remove() {
        if let handle {
            spi_remove_device_shim(handle)
            self.handle = nil
        }
        spi_bus_free_shim(host)
    }
}
