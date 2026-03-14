//MARK: - LED
final class LED: GPIO {
    var enabled: Bool = false {
        didSet {
            gpio_set_level(GPIO_NUM_10, enabled ? 1 : 0)
            // gpio_set_level(GPIO_NUM_9, enabled ? 1 : 0)
        }
    }

    init() {
        gpio_reset_pin(GPIO_NUM_10)
        gpio_set_direction(GPIO_NUM_10, GPIO_MODE_OUTPUT)
        gpio_set_level(GPIO_NUM_10, 0)

        // gpio_reset_pin(GPIO_NUM_9)
        // gpio_set_direction(GPIO_NUM_9, GPIO_MODE_OUTPUT)
        // gpio_set_level(GPIO_NUM_9, 0)

        _ = Unmanaged.passRetained(self)
    }
}

//MARK: - Button
final class Button {
    private let id: UInt16
    private let led: LED

    var buttonConfig = button_config_t()
    var buttonGpioConfig = button_gpio_config_t()
    var buttonHandle: button_handle_t? = nil

    init(endpoint id: UInt16, led: LED) {
        self.id = id
        self.led = led

        gpio_reset_pin(GPIO_NUM_21)
        gpio_set_direction(GPIO_NUM_21, GPIO_MODE_INPUT)
        gpio_set_intr_type(GPIO_NUM_21, GPIO_INTR_DISABLE)

        buttonConfig.long_press_time = 2000
        buttonConfig.short_press_time = 10

        buttonGpioConfig.active_level = 1
        buttonGpioConfig.gpio_num = 21

        // dht_read_float_data()

        _ = Unmanaged.passRetained(self)
    }

    func update() {

        var att_dataType: esp_matter_attr_val_t = esp_matter_bool(!led.enabled)

        _ = esp_matter.attribute.update_shim(
            UInt16(self.id),
            UInt32(chip.app.Clusters.OnOff.Id),
            UInt32(chip.app.Clusters.OnOff.Attributes.OnOff.Id),
            &att_dataType
        )
    }
}

//MARK: - DHT22
final class DHT22Sensor {
    private let gpio = GPIO_NUM_4
    private var temperature: Float = 0.0
    private var humidity: Float = 0.0

    private let humidityId: UInt16
    private let temperatureId: UInt16

    init(humidityEndpoint h_id: UInt16, temperatureEndpoint t_id: UInt16) {

        self.humidityId = h_id
        self.temperatureId = t_id

        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_OUTPUT)
        gpio_set_level(gpio, 0)
        gpio_set_direction(gpio, GPIO_MODE_INPUT_OUTPUT_OD)
        gpio_set_level(gpio, 1)
        gpio_set_intr_type(gpio, GPIO_INTR_DISABLE)
        gpio_set_level(gpio, 0)

        _ = Unmanaged.passRetained(self)
    }

    static let dht_rx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("task started")
        guard let param else { return }
        let dht = Unmanaged<DHT22Sensor>.fromOpaque(param).takeRetainedValue()
        var saved_state_humi: Float = 0.0
        var saved_state_temp: Float = 0.0
        while true {
            let res = dht_read_float_data(
                DHT_TYPE_AM2301, dht.gpio, &dht.humidity, &dht.temperature)

            if res == ESP_OK
                && (dht.humidity != saved_state_humi
                    || dht.temperature != saved_state_temp)
            {
                // print("Humidity: \(dht.humidity)  Temp: \(dht.temperature)\n")
                saved_state_humi = dht.humidity
                saved_state_temp = dht.temperature

                dht.update_temp()
                dht.update_humidity()

            } else {
                // print("Humidity: \(dht.humidity)  Temp: \(dht.temperature)\n")
                // print("Could not read data from sensor: \(res)\n")
            }
            vTaskDelay(1_000_000 * UInt32(configTICK_RATE_HZ) / 1000)
        }
    }

    func update_temp() {

        var att_dataType: esp_matter_attr_val_t = esp_matter_nullable_int16(
            .init(Int16(self.temperature * 100.0)))
        let err = esp_matter.attribute.report_shim(
            UInt16(self.temperatureId),
            UInt32(chip.app.Clusters.TemperatureMeasurement.Id),
            UInt32(chip.app.Clusters.TemperatureMeasurement.Attributes.MeasuredValue.Id),
            &att_dataType
        )
        if err != ESP_OK { print("update_temp failed: \(err)") }
    }

    func update_humidity() {
        var att_dataType: esp_matter_attr_val_t = esp_matter_nullable_uint16(
            .init(UInt16(self.humidity * 100.0)))
        let err = esp_matter.attribute.report_shim(
            UInt16(self.humidityId),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Id),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Attributes.MeasuredValue.Id),
            &att_dataType
        )
        if err != ESP_OK { print("update_temp failed: \(err)") }
    }
}

//MARK: - IR
enum NecResult {
    case frame(UInt32)  // Full 32-bit NEC frame decoded
    case repeatCode     // Repeat burst (button held)
}

final class IRSensor {
    private let gpio: gpio_num_t = GPIO_NUM_0
    // private let endpointId: UInt16
    // private let led: LED
    var taskHandle: TaskHandle_t? = nil

    // GPIO ISR: fires on falling edge, notifies the IR task
    private static let gpioISR: gpio_isr_t = { arg in
        guard let arg else { return }
        let ir = Unmanaged<IRSensor>.fromOpaque(arg).takeUnretainedValue()
        guard let handle = ir.taskHandle else { return }

        // Disable interrupt until the task re-enables it after decoding
        gpio_intr_disable(ir.gpio)

        var xHigherPriorityTaskWoken: Int32 = 0
        vTaskNotifyGiveFromISR_shim(handle, &xHigherPriorityTaskWoken)
        portYIELD_FROM_ISR_shim(xHigherPriorityTaskWoken)
    }

    init() {
        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_INPUT)
        gpio_pullup_en(gpio)
        gpio_set_intr_type(gpio, GPIO_INTR_NEGEDGE)

        // Install GPIO ISR service and attach handler
        gpio_install_isr_service(0)
        gpio_isr_handler_add(gpio, IRSensor.gpioISR, Unmanaged.passUnretained(self).toOpaque())
        gpio_intr_disable(gpio)  // Will be enabled once the task is ready

        _ = Unmanaged.passRetained(self)
    }

    // private func setSwitchState(_ enabled: Bool) {
    //     var att_dataType: esp_matter_attr_val_t = esp_matter_bool(enabled)
    //     let err = esp_matter.attribute.update_shim(
    //         endpointId,
    //         UInt32(chip.app.Clusters.OnOff.Id),
    //         UInt32(chip.app.Clusters.OnOff.Attributes.OnOff.Id),
    //         &att_dataType
    //     )

    //     if err != ESP_OK { print("ir update failed: \(err)") }
    // }

    private func handleCommand(frame: UInt32, isRepeat: Bool = false) {
        let address = UInt8(frame & 0xFF)  // identifies the specific device
        let command = UInt8((frame >> 16) & 0xFF)  // identifies the command

        if !isRepeat {
            print(
                "IR TSOP38238: frame=0x\(String(frame, radix: 16)) address=0x\(String(address, radix: 16)) command=0x\(String(command, radix: 16))"
            )
        }

        switch command {
        case 0x1:  // Common NEC "Power" key
            // let nextState = !led.enabled
            // setSwitchState(nextState)
            // print("IR TSOP38238: POWER command -> switch \(nextState ? \"ON\" : \"OFF\")")
            print("IR TSOP38238: POWER command -> switch ON/OFF.\(isRepeat ? " (repeat)" : "")")
        default:
            print("IR TSOP38238: unhandled command 0x\(String(command, radix: 16))\(isRepeat ? " (repeat)" : "")")
        }
    }

    private static func readPulse(level: Int32, gpio: gpio_num_t, timeoutUs: Int64 = 20_000)
        -> Int64
    {
        let start = esp_timer_get_time()
        while gpio_get_level(gpio) == level {
            if esp_timer_get_time() - start > timeoutUs { return -1 }
        }
        return esp_timer_get_time() - start
    }

    private static func decodeNecFrame(gpio: gpio_num_t) -> NecResult? {
        let leadingLow = readPulse(level: 0, gpio: gpio)
        if leadingLow < 8_500 || leadingLow > 9_500 { return nil }

        let leadingHigh = readPulse(level: 1, gpio: gpio)

        // Repeat code: 9ms LOW + 2.25ms HIGH (instead of 4.5ms)
        if leadingHigh >= 2_000 && leadingHigh <= 2_800 {
            // Wait for the trailing 562µs LOW burst to finish
            _ = readPulse(level: 0, gpio: gpio)
            return .repeatCode
        }

        // Full frame: 9ms LOW + 4.5ms HIGH
        if leadingHigh < 4_000 || leadingHigh > 5_000 { return nil }

        var code: UInt32 = 0
        for bit in 0..<32 {
            let low = readPulse(level: 0, gpio: gpio)
            if low < 400 || low > 800 { return nil }

            let high = readPulse(level: 1, gpio: gpio)
            if high > 1_200 {
                code |= (UInt32(1) << UInt32(bit))
            }
        }

        return .frame(code)
    }

    private static func isValidNec(_ frame: UInt32) -> Bool {
        let address = UInt8(frame & 0xFF)
        let addressInv = UInt8((frame >> 8) & 0xFF)
        let command = UInt8((frame >> 16) & 0xFF)
        let commandInv = UInt8((frame >> 24) & 0xFF)

        return (address ^ addressInv) == 0xFF && (command ^ commandInv) == 0xFF
    }

    static let ir_rx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("IR Task started, waiting for signals...")

        guard let param else { return }
        let ir = Unmanaged<IRSensor>.fromOpaque(param).takeRetainedValue()

        // Store our own task handle so the ISR can notify us
        ir.taskHandle = xTaskGetCurrentTaskHandle()
        print("TSOP38238 receiver task started (ISR + notify mode).")

        var lastFrame: UInt32? = nil
        var lastSignalTime: Int64 = 0
        let repeatTimeoutUs: Int64 = 200_000  // 200ms

        // Enable the GPIO interrupt now that we're ready to receive
        gpio_intr_enable(ir.gpio)

        while true {
            // Block until the ISR wakes us (falling edge on IR pin)
            // Timeout after 300ms to clear stale lastFrame
            let notified = ulTaskNotifyTake_shim(1, 300 * UInt32(configTICK_RATE_HZ) / 1000)

            if notified == 0 {
                // Timeout — no IR activity, clear stale state
                lastFrame = nil
                gpio_intr_enable(ir.gpio)
                continue
            }

            // ISR disabled the interrupt for us; decode the NEC frame via bit-banging
            guard let result = decodeNecFrame(gpio: ir.gpio) else {
                gpio_intr_enable(ir.gpio)
                continue
            }

            let now = esp_timer_get_time()

            switch result {
            case .frame(let frame):
                guard isValidNec(frame) else {
                    gpio_intr_enable(ir.gpio)
                    continue
                }
                lastFrame = frame
                lastSignalTime = now
                ir.handleCommand(frame: frame)

            case .repeatCode:
                if let frame = lastFrame,
                   (now - lastSignalTime) < repeatTimeoutUs
                {
                    lastSignalTime = now
                    ir.handleCommand(frame: frame, isRepeat: true)
                } else {
                    lastFrame = nil
                }
            }

            // Short debounce, then re-enable interrupt for next signal
            vTaskDelay(50 * UInt32(configTICK_RATE_HZ) / 1000)
            gpio_intr_enable(ir.gpio)
        }
    }

}
