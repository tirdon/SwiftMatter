//MARK: - LED
final class LED: GPIO {
    private static let pin = GPIO_NUM_16

    var enabled: Bool = false {
        didSet {
            gpio_set_level(LED.pin, enabled ? 1 : 0)
        }
    }

    init() {
        gpio_reset_pin(LED.pin)
        gpio_set_direction(LED.pin, GPIO_MODE_OUTPUT)
        gpio_set_level(LED.pin, 0)

        _ = Unmanaged.passRetained(self)
    }
}

//MARK: - Button
final class Button {
    private static let pin = GPIO_NUM_17

    private let id: UInt16
    private let led: LED

    var buttonConfig = button_config_t()
    var buttonGpioConfig = button_gpio_config_t()
    var buttonHandle: button_handle_t? = nil

    init(endpoint id: UInt16, led: LED) {
        self.id = id
        self.led = led

        gpio_reset_pin(Button.pin)
        gpio_set_direction(Button.pin, GPIO_MODE_INPUT)
        gpio_set_intr_type(Button.pin, GPIO_INTR_DISABLE)

        buttonConfig.long_press_time = 2000
        buttonConfig.short_press_time = 10

        buttonGpioConfig.active_level = 1
        buttonGpioConfig.gpio_num = Int32(Button.pin.rawValue)

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

    /// Read interval in milliseconds.
    private static let readIntervalMs: UInt32 = 10_000

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
        print("DHT22 Task started")
        guard let param else { return }
        let dht = Unmanaged<DHT22Sensor>.fromOpaque(param).takeRetainedValue()
        var savedHumidity: Float = 0.0
        var savedTemperature: Float = 0.0

        while true {
            let res = dht_read_float_data(
                DHT_TYPE_AM2301, dht.gpio, &dht.humidity, &dht.temperature)

            if res == ESP_OK
                && (dht.humidity != savedHumidity
                    || dht.temperature != savedTemperature)
            {
                savedHumidity = dht.humidity
                savedTemperature = dht.temperature
                dht.update_temp()
                dht.update_humidity()
            }

            vTaskDelay(readIntervalMs * UInt32(configTICK_RATE_HZ) / 1000)
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
        if err != ESP_OK { print("DHT22 update_temp failed: \(err)") }
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
        if err != ESP_OK { print("DHT22 update_humidity failed: \(err)") }
    }
}

//MARK: - IR

final class IRSensor {
    enum NecResult {
        case frame(UInt32)
        case repeatCode
    }

    // NEC IR command codes
    private enum Command {
        static let powerOff: UInt8 = 0x01
        static let powerOn: UInt8 = 0x1a
    }

    // NEC protocol timing thresholds (microseconds)
    private enum Timing {
        static let leadLowMin: Int64 = 8_500
        static let leadLowMax: Int64 = 9_500
        static let repeatHighMin: Int64 = 2_000
        static let repeatHighMax: Int64 = 2_800
        static let frameHighMin: Int64 = 4_000
        static let frameHighMax: Int64 = 5_000
        static let bitLowMin: Int64 = 400
        static let bitLowMax: Int64 = 800
        static let bitHighThreshold: Int64 = 1_200
        static let pulseTimeout: Int64 = 20_000
    }

    /// Repeat timeout in microseconds (200ms).
    private static let repeatTimeoutUs: Int64 = 200_000
    /// Notify wait timeout in milliseconds.
    private static let notifyTimeoutMs: UInt32 = 300
    /// Debounce delay in milliseconds after decoding.
    private static let debounceMs: UInt32 = 1_000

    private let gpio: gpio_num_t = GPIO_NUM_0
    var taskHandle: TaskHandle_t? = nil

    let led: LED

    // GPIO ISR: fires on falling edge, notifies the IR task
    private static let gpioISR: gpio_isr_t = { arg in
        guard let arg else { return }
        let ir = Unmanaged<IRSensor>.fromOpaque(arg).takeUnretainedValue()
        guard let handle = ir.taskHandle else { return }

        gpio_intr_disable(ir.gpio)

        var xHigherPriorityTaskWoken: Int32 = 0
        vTaskNotifyGiveFromISR_shim(handle, &xHigherPriorityTaskWoken)
        portYIELD_FROM_ISR_shim(xHigherPriorityTaskWoken)
    }

    init(led: LED) {
        self.led = led
        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_INPUT)
        gpio_pullup_en(gpio)
        gpio_set_intr_type(gpio, GPIO_INTR_NEGEDGE)

        gpio_install_isr_service(0)
        gpio_isr_handler_add(gpio, IRSensor.gpioISR, Unmanaged.passUnretained(self).toOpaque())
        gpio_intr_disable(gpio)

        _ = Unmanaged.passRetained(self)
    }

    private func handleCommand(frame: UInt32, isRepeat: Bool = false) {
        let command = UInt8((frame >> 16) & 0xFF)

        switch command {
        case Command.powerOff:
            self.led.enabled = false
        case Command.powerOn:
            self.led.enabled = true
        default:
            break
        }
    }

    private static func readPulse(level: Int32, gpio: gpio_num_t) -> Int64 {
        let start = esp_timer_get_time()
        while gpio_get_level(gpio) == level {
            if esp_timer_get_time() - start > Timing.pulseTimeout { return -1 }
        }
        return esp_timer_get_time() - start
    }

    private static func decodeNecFrame(gpio: gpio_num_t) -> NecResult? {
        let leadingLow = readPulse(level: 0, gpio: gpio)
        if leadingLow < Timing.leadLowMin || leadingLow > Timing.leadLowMax { return nil }

        let leadingHigh = readPulse(level: 1, gpio: gpio)

        // Repeat code: 9ms LOW + ~2.25ms HIGH
        if leadingHigh >= Timing.repeatHighMin && leadingHigh <= Timing.repeatHighMax {
            _ = readPulse(level: 0, gpio: gpio)
            return .repeatCode
        }

        // Full frame: 9ms LOW + ~4.5ms HIGH
        if leadingHigh < Timing.frameHighMin || leadingHigh > Timing.frameHighMax { return nil }

        var code: UInt32 = 0
        for bit in 0..<32 {
            let low = readPulse(level: 0, gpio: gpio)
            if low < Timing.bitLowMin || low > Timing.bitLowMax { return nil }

            let high = readPulse(level: 1, gpio: gpio)
            if high > Timing.bitHighThreshold {
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
        print("IR Task started")

        guard let param else { return }
        let ir = Unmanaged<IRSensor>.fromOpaque(param).takeRetainedValue()

        ir.taskHandle = xTaskGetCurrentTaskHandle()

        var lastFrame: UInt32? = nil
        var lastSignalTime: Int64 = 0

        gpio_intr_enable(ir.gpio)

        while true {
            let notified = ulTaskNotifyTake_shim(
                1, notifyTimeoutMs * UInt32(configTICK_RATE_HZ) / 1000)

            if notified == 0 {
                lastFrame = nil
                gpio_intr_enable(ir.gpio)
                continue
            }

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

            vTaskDelay(debounceMs * UInt32(configTICK_RATE_HZ) / 1000)
            gpio_intr_enable(ir.gpio)
        }
    }
}

//MARK: - DS18B20

final class DS18B20Sensor {
    // 1-Wire ROM commands
    private enum ROM {
        static let skip: UInt8 = 0xCC
        static let convertT: UInt8 = 0x44
        static let readScratch: UInt8 = 0xBE
    }

    // 1-Wire timing constants (microseconds)
    private enum Timing {
        static let resetLow: Int64 = 480
        static let presenceWait: Int64 = 70
        static let presenceSlot: Int64 = 410
        static let writeBit1Low: Int64 = 6
        static let writeBit1High: Int64 = 64
        static let writeBit0Low: Int64 = 60
        static let writeBit0High: Int64 = 10
        static let readInitLow: Int64 = 3
        static let readSampleWait: Int64 = 10
        static let readSlotEnd: Int64 = 53
    }

    /// Conversion wait in milliseconds (DS18B20 12-bit resolution).
    private static let conversionMs: UInt32 = 800
    /// Read interval in milliseconds.
    private static let readIntervalMs: UInt32 = 10_000
    /// Scratchpad size in bytes.
    private static let scratchpadSize = 9

    private let gpio: gpio_num_t
    private var temperature: Float = 0.0
    private let temperatureId: UInt16

    init(endpoint t_id: UInt16, pin: gpio_num_t) {
        self.temperatureId = t_id
        self.gpio = pin

        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_INPUT_OUTPUT_OD)
        gpio_set_level(gpio, 1)

        _ = Unmanaged.passRetained(self)
    }

    private func delayUs(_ us: Int64) {
        let start = esp_timer_get_time()
        while (esp_timer_get_time() - start) < us {}
    }

    private func reset() -> Bool {
        gpio_set_level(gpio, 0)
        delayUs(Timing.resetLow)
        gpio_set_level(gpio, 1)
        delayUs(Timing.presenceWait)
        let presence = gpio_get_level(gpio) == 0
        delayUs(Timing.presenceSlot)
        return presence
    }

    private func writeBit(_ bit: Bool) {
        gpio_set_level(gpio, 0)
        if bit {
            delayUs(Timing.writeBit1Low)
            gpio_set_level(gpio, 1)
            delayUs(Timing.writeBit1High)
        } else {
            delayUs(Timing.writeBit0Low)
            gpio_set_level(gpio, 1)
            delayUs(Timing.writeBit0High)
        }
    }

    private func readBit() -> Bool {
        gpio_set_level(gpio, 0)
        delayUs(Timing.readInitLow)
        gpio_set_level(gpio, 1)
        delayUs(Timing.readSampleWait)
        let bit = gpio_get_level(gpio) == 1
        delayUs(Timing.readSlotEnd)
        return bit
    }

    private func writeByte(_ byte: UInt8) {
        var b = byte
        for _ in 0..<8 {
            writeBit((b & 0x01) == 1)
            b >>= 1
        }
    }

    private func readByte() -> UInt8 {
        var byte: UInt8 = 0
        for i in 0..<8 {
            if readBit() {
                byte |= (1 << i)
            }
        }
        return byte
    }

    private func crc8(_ data: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            var input = byte
            for _ in 0..<8 {
                let mix = (crc ^ input) & 0x01
                crc >>= 1
                if mix != 0 { crc ^= 0x8C }
                input >>= 1
            }
        }
        return crc
    }

    func readTemperature() -> Float? {
        if !reset() { return nil }
        writeByte(ROM.skip)
        writeByte(ROM.convertT)

        vTaskDelay(DS18B20Sensor.conversionMs * UInt32(configTICK_RATE_HZ) / 1000)

        if !reset() { return nil }
        writeByte(ROM.skip)
        writeByte(ROM.readScratch)

        var data: [UInt8] = []
        for _ in 0..<DS18B20Sensor.scratchpadSize {
            data.append(readByte())
        }

        if crc8(Array(data[0..<8])) != data[8] {
            return nil
        }

        let rawUInt16 = (UInt16(data[1]) << 8) | UInt16(data[0])
        let raw = Int16(bitPattern: rawUInt16)
        return Float(raw) / 16.0
    }

    static let ds18b20_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("DS18B20 Task started")
        guard let param else { return }
        let sensor = Unmanaged<DS18B20Sensor>.fromOpaque(param).takeRetainedValue()
        var savedTemperature: Float = -999.0

        while true {
            if let temp = sensor.readTemperature() {
                if temp != savedTemperature {
                    savedTemperature = temp
                    sensor.temperature = temp
                    sensor.update_temp()
                }
            }
            vTaskDelay(readIntervalMs * UInt32(configTICK_RATE_HZ) / 1000)
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
        if err != ESP_OK { print("DS18B20 update_temp failed: \(err)") }
    }
}

//MARK: - Maker Soil Moisture Sensor

final class MakerSoilMoistureSensor {
    /// 12-bit ADC maximum raw value.
    private static let adcMaxValue: Float = 4095.0
    /// Minimum change in percentage before reporting to Matter.
    private static let reportThreshold: Float = 1.0
    /// Read interval in milliseconds.
    private static let readIntervalMs: UInt32 = 10_000

    private let channel: adc1_channel_t
    private let moistureId: UInt16
    private var moisture: Float = 0.0

    init(endpoint m_id: UInt16, channel: adc1_channel_t) {
        self.moistureId = m_id
        self.channel = channel

        adc1_config_channel_atten(channel, ADC_ATTEN_DB_12)

        _ = Unmanaged.passRetained(self)
    }

    /// Convert raw ADC value (0 = wet, 4095 = dry) to moisture percentage.
    private static func rawToPercentage(_ rawValue: Int32) -> Float {
        let raw = Float(rawValue)
        let percentage = ((adcMaxValue - raw) / adcMaxValue) * 100.0
        return min(max(percentage, 0), 100)
    }

    static let moisture_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("MakerSoilMoisture Task started")
        guard let param else { return }
        let sensor = Unmanaged<MakerSoilMoistureSensor>.fromOpaque(param).takeRetainedValue()
        var savedMoisture: Float = -999.0

        while true {
            let rawValue = adc1_get_raw(sensor.channel)
            let percentage = rawToPercentage(rawValue)

            if abs(percentage - savedMoisture) >= reportThreshold {
                savedMoisture = percentage
                sensor.moisture = percentage
                sensor.updateMoisture()
            }

            vTaskDelay(readIntervalMs * UInt32(configTICK_RATE_HZ) / 1000)
        }
    }

    func updateMoisture() {
        var att_dataType: esp_matter_attr_val_t = esp_matter_nullable_uint16(
            .init(UInt16(self.moisture * 100.0)))
        let err = esp_matter.attribute.report_shim(
            UInt16(self.moistureId),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Id),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Attributes.MeasuredValue.Id),
            &att_dataType
        )
        if err != ESP_OK { print("MakerSoilMoisture update failed: \(err)") }
    }
}

//MARK: - IR Transmitter

final class IRTransmitter {
    // NEC protocol timing constants (microseconds)
    private enum Timing {
        static let carrierFrequency: Int64 = 38  // kHz
        static let carrierPeriodUs: Int64 = 26  // ~1/38kHz ≈ 26.3µs
        static let carrierDutyUs: Int64 = 9  // ~1/3 duty cycle

        static let leadLow: Int64 = 9_000  // 9ms leading pulse burst
        static let leadHigh: Int64 = 4_500  // 4.5ms space
        static let bitLow: Int64 = 562  // 562µs pulse burst
        static let bitHighOne: Int64 = 1_687  // 1.687ms space for '1'
        static let bitHighZero: Int64 = 562  // 562µs space for '0'

        static let repeatLeadLow: Int64 = 9_000  // 9ms leading pulse burst
        static let repeatLeadHigh: Int64 = 2_250  // 2.25ms space
        static let repeatBurst: Int64 = 562  // trailing burst
    }

    /// Minimum gap between consecutive transmissions (milliseconds).
    private static let txCooldownMs: UInt32 = 70

    private let gpio: gpio_num_t
    var taskHandle: TaskHandle_t? = nil

    /// Frame to transmit — set before notifying the task.
    private var pendingFrame: UInt32 = 0
    /// Number of repeat codes to send after the initial frame.
    private var pendingRepeatCount: UInt8 = 0

    init(pin: gpio_num_t) {
        self.gpio = pin

        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_OUTPUT)
        gpio_set_level(gpio, 0)

        _ = Unmanaged.passRetained(self)
    }

    // Low-level carrier / space helpers

    /// Emit 38 kHz carrier burst for the given duration (µs).
    private func carrierBurst(durationUs: Int64) {
        let start = esp_timer_get_time()
        while (esp_timer_get_time() - start) < durationUs {
            gpio_set_level(gpio, 1)
            delayUs(Timing.carrierDutyUs)
            gpio_set_level(gpio, 0)
            delayUs(Timing.carrierPeriodUs - Timing.carrierDutyUs)
        }
    }

    /// Hold the line low (space / mark-space) for the given duration (µs).
    private func space(durationUs: Int64) {
        gpio_set_level(gpio, 0)
        delayUs(durationUs)
    }

    private func delayUs(_ us: Int64) {
        let start = esp_timer_get_time()
        while (esp_timer_get_time() - start) < us {}
    }

    // NEC frame transmission

    /// Send a full 32-bit NEC frame (address, address inv, command, command inv).
    func sendFrame(_ frame: UInt32) {
        // Leading pulse burst + space
        carrierBurst(durationUs: Timing.leadLow)
        space(durationUs: Timing.leadHigh)

        // 32 data bits, LSB first
        for bit in 0..<32 {
            carrierBurst(durationUs: Timing.bitLow)
            if (frame >> UInt32(bit)) & 1 == 1 {
                space(durationUs: Timing.bitHighOne)
            } else {
                space(durationUs: Timing.bitHighZero)
            }
        }

        // Final stop burst
        carrierBurst(durationUs: Timing.bitLow)
        gpio_set_level(gpio, 0)
    }

    /// Send a NEC repeat code.
    func sendRepeat() {
        carrierBurst(durationUs: Timing.repeatLeadLow)
        space(durationUs: Timing.repeatLeadHigh)
        carrierBurst(durationUs: Timing.repeatBurst)
        gpio_set_level(gpio, 0)
    }

    /// Build a full NEC frame from an 8-bit address and 8-bit command, then send it.
    func sendCommand(address: UInt8, command: UInt8, repeatCount: UInt8 = 0) {
        let addressInv = ~address
        let commandInv = ~command

        let frame: UInt32 =
            UInt32(address)
            | (UInt32(addressInv) << 8)
            | (UInt32(command) << 16)
            | (UInt32(commandInv) << 24)

        sendFrame(frame)

        for _ in 0..<repeatCount {
            vTaskDelay(IRTransmitter.txCooldownMs * UInt32(configTICK_RATE_HZ) / 1000)
            sendRepeat()
        }
    }

    /// Enqueue a frame for the transmitter task to send.
    func enqueue(frame: UInt32, repeatCount: UInt8 = 0) {
        pendingFrame = frame
        pendingRepeatCount = repeatCount

        guard let handle = taskHandle else { return }
        ulTaskNotifyGive_shim(handle)
    }

    /// Enqueue an address + command for the transmitter task to send.
    func enqueueCommand(address: UInt8, command: UInt8, repeatCount: UInt8 = 0) {
        let addressInv = ~address
        let commandInv = ~command

        pendingFrame =
            UInt32(address)
            | (UInt32(addressInv) << 8)
            | (UInt32(command) << 16)
            | (UInt32(commandInv) << 24)
        pendingRepeatCount = repeatCount

        guard let handle = taskHandle else { return }
        ulTaskNotifyGive_shim(handle)
    }

    // FreeRTOS task

    static let ir_tx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("IR TX Task started")

        guard let param else { return }
        let tx = Unmanaged<IRTransmitter>.fromOpaque(param).takeRetainedValue()

        tx.taskHandle = xTaskGetCurrentTaskHandle()

        while true {
            // Block until notified
            let notified = ulTaskNotifyTake_shim(1, portMAX_DELAY)
            if notified == 0 { continue }

            let frame = tx.pendingFrame
            let repeats = tx.pendingRepeatCount

            tx.sendFrame(frame)

            for _ in 0..<repeats {
                vTaskDelay(txCooldownMs * UInt32(configTICK_RATE_HZ) / 1000)
                tx.sendRepeat()
            }
        }
    }
}
