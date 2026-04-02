// MARK: - SPI

/// SPI master driver for device-to-device communication without WiFi/Matter.
///
/// Uses ESP-IDF SPI master driver via C shims. Supports full-duplex transfers,
/// send-only, receive-only, and a FreeRTOS polling task for periodic exchanges.
final class SPIDevice {
    static let maxTransferSize: Int32 = 4096

    private var handle: UnsafeMutableRawPointer? = nil
    private let host: Int32

    /// Poll interval in milliseconds for the FreeRTOS task.
    private static let pollIntervalMs: UInt32 = 1_000

    /// Callback invoked on the polling task when data is received.
    /// Parameters: pointer to received buffer, length.
    var onReceive: ((UnsafePointer<UInt8>, Int) -> Void)? = nil

    /// Transmit buffer set before notifying the task.
    private var pendingTx: (UnsafePointer<UInt8>, Int)? = nil
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

    /// Send a command byte, then read a response.
    func command(
        _ cmd: UInt8, response: UnsafeMutablePointer<UInt8>,
        responseLength: Int
    ) -> esp_err_t {
        var cmdByte = cmd
        let err = send(&cmdByte, length: 1)
        if err != ESP_OK { return err }
        return receive(response, length: responseLength)
    }

    /// Enqueue data for the polling task to transmit on the next cycle.
    func enqueue(tx: UnsafePointer<UInt8>, length: Int) {
        pendingTx = (tx, length)
        guard let handle = taskHandle else { return }
        xTaskNotifyGive_shim(handle)
    }

    // MARK: - FreeRTOS Task

    static let spi_poll_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("SPI Task started")
        guard let param else { return }
        let spi = Unmanaged<SPIDevice>.fromOpaque(param).takeUnretainedValue()

        spi.taskHandle = xTaskGetCurrentTaskHandle()

        while true {
            let notified = ulTaskNotifyTake_shim(1, msToTicks(pollIntervalMs))

            if notified != 0, let (txBuf, txLen) = spi.pendingTx {
                // Allocate rx buffer on the stack-ish area for the response
                let rxBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: txLen)
                let err = spi.transfer(tx: txBuf, rx: rxBuf, length: txLen)
                if err == ESP_OK {
                    spi.onReceive?(UnsafePointer(rxBuf), txLen)
                } else {
                    print("SPI transfer failed: \(err)")
                }
                rxBuf.deallocate()
                spi.pendingTx = nil
            }

            vTaskDelay(msToTicks(pollIntervalMs))
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
