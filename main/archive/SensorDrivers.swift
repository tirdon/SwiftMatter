// SensorDrivers.swift (ARCHIVED — not compiled)
//
// Contains sensor and transmitter drivers for hardware not currently in use.
// Preserved for reference. To re-enable, move the desired class back into
// main/PhysicalDevices.swift and add the corresponding Matter endpoint
// in SwitchEndpoint.swift.

// MARK: - DHT22

final class DHT22Sensor {
    // DHT22 protocol timing (microseconds)
    private enum Timing {
        static let startLow: Int64 = 20_000  // Pull low >= 18ms to start
        static let responseTimeout: Int64 = 100  // Max wait for DHT response phases
        static let bitLowTimeout: Int64 = 65  // Max ~50us LOW per data bit
        static let bitHighTimeout: Int64 = 80  // Max ~70us HIGH per data bit
    }

    /// Read interval in milliseconds.
    private static let readIntervalMs: UInt32 = 10_000

    private let gpio: gpio_num_t = GPIO_NUM_4
    private var temperature: Float = 0.0
    private var humidity: Float = 0.0

    private let humidityId: UInt16
    private let temperatureId: UInt16

    init(humidityEndpoint h_id: UInt16, temperatureEndpoint t_id: UInt16) {
        self.humidityId = h_id
        self.temperatureId = t_id

        gpio_reset_pin(gpio)
        gpio_set_direction(gpio, GPIO_MODE_INPUT_OUTPUT_OD)
        gpio_set_level(gpio, 1)

        _ = Unmanaged.passRetained(self)
    }

    /// Wait for pin to reach expected level. Returns wait duration in microseconds, or -1 on timeout.
    private func awaitPin(_ level: Int32, timeout: Int64) -> Int64 {
        let start = esp_timer_get_time()
        while gpio_get_level(gpio) != level {
            if esp_timer_get_time() - start > timeout { return -1 }
        }
        return esp_timer_get_time() - start
    }

    /// Read one byte (8 bits, MSB first). Returns nil on timeout.
    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        for i in 0..<8 {
            let lowDur = awaitPin(1, timeout: Timing.bitLowTimeout)
            if lowDur < 0 { return nil }
            let highDur = awaitPin(0, timeout: Timing.bitHighTimeout)
            if highDur < 0 { return nil }
            if highDur > lowDur {
                byte |= (1 << UInt8(7 - i))
            }
        }
        return byte
    }

    /// Read humidity and temperature from the DHT22 sensor.
    func readData() -> (humidity: Float, temperature: Float)? {
        // Send start signal: pull LOW for >= 18ms, then release
        gpio_set_direction(gpio, GPIO_MODE_OUTPUT_OD)
        gpio_set_level(gpio, 0)
        delayUs(Timing.startLow)
        gpio_set_level(gpio, 1)

        // Switch to input and wait for DHT response
        gpio_set_direction(gpio, GPIO_MODE_INPUT)
        // Phase B: wait for DHT to pull LOW
        if awaitPin(0, timeout: Timing.responseTimeout) < 0 { return nil }
        // Phase C: DHT pulls LOW ~80us, wait for HIGH
        if awaitPin(1, timeout: Timing.responseTimeout) < 0 { return nil }
        // Phase D: DHT releases ~80us, wait for LOW (first data bit start)
        if awaitPin(0, timeout: Timing.responseTimeout) < 0 { return nil }

        // Read 5 bytes (40 bits)
        guard let b0 = readByte(),
            let b1 = readByte(),
            let b2 = readByte(),
            let b3 = readByte(),
            let b4 = readByte()
        else {
            gpio_set_direction(gpio, GPIO_MODE_INPUT_OUTPUT_OD)
            gpio_set_level(gpio, 1)
            return nil
        }

        // Restore idle state
        gpio_set_direction(gpio, GPIO_MODE_INPUT_OUTPUT_OD)
        gpio_set_level(gpio, 1)

        // Verify checksum
        if b4 != UInt8((UInt16(b0) + UInt16(b1) + UInt16(b2) + UInt16(b3)) & 0xFF) {
            return nil
        }

        // Parse humidity: bytes 0-1, value / 10.0
        let rawHumidity = (UInt16(b0) << 8) | UInt16(b1)
        let h = Float(rawHumidity) / 10.0

        // Parse temperature: bytes 2-3, value / 10.0, bit 15 = sign
        let rawTemp = (UInt16(b2) << 8) | UInt16(b3)
        var t = Float(rawTemp & 0x7FFF) / 10.0
        if rawTemp & 0x8000 != 0 { t = -t }

        return (h, t)
    }

    static let dht_rx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("DHT22 Task started")
        guard let param else { return }
        let dht = Unmanaged<DHT22Sensor>.fromOpaque(param).takeUnretainedValue()
        var savedHumidity: Float = 0.0
        var savedTemperature: Float = 0.0
        var updateCount = 0

        while true {
            if let reading = dht.readData() {
                if reading.humidity != savedHumidity
                    || reading.temperature != savedTemperature
                {
                    savedHumidity = reading.humidity
                    savedTemperature = reading.temperature
                    dht.humidity = reading.humidity
                    dht.temperature = reading.temperature
                    dht.update_temp()
                    dht.update_humidity()
                }
            }
            if updateCount < 5 {
                vTaskDelay(msToTicks(500))
                updateCount += 1
            } else { vTaskDelay(msToTicks(readIntervalMs)) }
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

// MARK: - DS18B20

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

        vTaskDelay(msToTicks(DS18B20Sensor.conversionMs))

        if !reset() { return nil }
        writeByte(ROM.skip)
        writeByte(ROM.readScratch)

        var data = [UInt8](repeating: 0, count: DS18B20Sensor.scratchpadSize)
        for i in 0..<DS18B20Sensor.scratchpadSize {
            data[i] = readByte()
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
        let sensor = Unmanaged<DS18B20Sensor>.fromOpaque(param).takeUnretainedValue()
        var savedTemperature: Float = -999.0

        while true {
            if let temp = sensor.readTemperature() {
                if temp != savedTemperature {
                    savedTemperature = temp
                    sensor.temperature = temp
                    sensor.update_temp()
                }
            }
            vTaskDelay(msToTicks(readIntervalMs))
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

// MARK: - Maker Soil Moisture Sensor

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
        let sensor = Unmanaged<MakerSoilMoistureSensor>.fromOpaque(param).takeUnretainedValue()
        var savedMoisture: Float = -999.0

        while true {
            let rawValue = adc1_get_raw(sensor.channel)
            let percentage = rawToPercentage(rawValue)

            if abs(percentage - savedMoisture) >= reportThreshold {
                savedMoisture = percentage
                sensor.moisture = percentage
                sensor.updateMoisture()
            }

            vTaskDelay(msToTicks(readIntervalMs))
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

// MARK: - IR Transmitter

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

    /// Build a full NEC frame from an 8-bit address and 8-bit command.
    private static func buildNecFrame(address: UInt8, command: UInt8) -> UInt32 {
        UInt32(address)
            | (UInt32(~address) << 8)
            | (UInt32(command) << 16)
            | (UInt32(~command) << 24)
    }

    /// Build a full NEC frame from an 8-bit address and 8-bit command, then send it.
    func sendCommand(address: UInt8, command: UInt8, repeatCount: UInt8 = 0) {
        sendFrame(Self.buildNecFrame(address: address, command: command))

        for _ in 0..<repeatCount {
            vTaskDelay(msToTicks(IRTransmitter.txCooldownMs))
            sendRepeat()
        }
    }

    /// Enqueue a frame for the transmitter task to send.
    func enqueue(frame: UInt32, repeatCount: UInt8 = 0) {
        pendingFrame = frame
        pendingRepeatCount = repeatCount

        guard let handle = taskHandle else { return }
        xTaskNotifyGive_shim(handle)
    }

    /// Enqueue an address + command for the transmitter task to send.
    func enqueueCommand(address: UInt8, command: UInt8, repeatCount: UInt8 = 0) {
        pendingFrame = Self.buildNecFrame(address: address, command: command)
        pendingRepeatCount = repeatCount

        guard let handle = taskHandle else { return }
        xTaskNotifyGive_shim(handle)
    }

    // FreeRTOS task

    static let ir_tx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        print("IR TX Task started")

        guard let param else { return }
        let tx = Unmanaged<IRTransmitter>.fromOpaque(param).takeUnretainedValue()

        tx.taskHandle = xTaskGetCurrentTaskHandle()

        while true {
            // Block until notified
            let notified = ulTaskNotifyTake_shim(1, portMAX_DELAY)
            if notified == 0 { continue }

            let frame = tx.pendingFrame
            let repeats = tx.pendingRepeatCount

            tx.sendFrame(frame)

            for _ in 0..<repeats {
                vTaskDelay(msToTicks(txCooldownMs))
                tx.sendRepeat()
            }
        }
    }
}

// MARK: - Archived Matter Endpoints

extension Matter {
    final class DHT22_tempEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.temperature_sensor.get_device_type_id()
        }

        init(rootNode: Node) {
            var t_config = esp_matter.endpoint.temperature_sensor.config_t()
            t_config.temperature_measurement.max_measured_value = .init(125_00)
            t_config.temperature_measurement.min_measured_value = .init(-40_00)
            t_config.temperature_measurement.measured_value = .init(101_00)

            let endpoint = esp_matter.endpoint.temperature_sensor.create(
                rootNode.innerNode.node,
                &t_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

extension Matter {
    final class DHT22_humidityEndpoint: Endpoint {
        static var deviceTypeId: UInt32 { esp_matter.endpoint.humidity_sensor.get_device_type_id() }

        init(rootNode: Node) {
            var h_config = esp_matter.endpoint.humidity_sensor.config_t()
            h_config.relative_humidity_measurement.max_measured_value = .init(100_00)
            h_config.relative_humidity_measurement.min_measured_value = .init(0)
            h_config.relative_humidity_measurement.measured_value = .init(0)

            let endpoint = esp_matter.endpoint.humidity_sensor.create(
                rootNode.innerNode.node,
                &h_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

extension Matter {
    final class SoilMoistureEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.dimmable_light.get_device_type_id()
        }

        init(rootNode: Node) {
            var l_config = esp_matter.endpoint.dimmable_light.config_t()
            l_config.level_control_lighting.max_level = .init(100)
            l_config.level_control_lighting.min_level = .init(0)
            l_config.level_control.on_level = .init(80)
            l_config.level_control.current_level = .init(80)

            let endpoint = esp_matter.endpoint.dimmable_light.create(
                rootNode.innerNode.node,
                &l_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}
