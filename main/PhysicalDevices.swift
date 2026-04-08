// PhysicalDevices.swift
// Hardware drivers for active peripherals: LED, Button, IR Sensor.

//MARK: - LED

final class LED: GPIO {
    static let pin = GPIO_NUM_22
    private static let groundPin = GPIO_NUM_16
    var enabled: Bool = false {
        didSet {
            gpio_set_level(LED.pin, enabled ? 1 : 0)
        }
    }

    init() {
        gpio_reset_pin(LED.pin)
        gpio_reset_pin(LED.groundPin)
        gpio_set_direction(LED.pin, GPIO_MODE_OUTPUT)
        gpio_set_direction(LED.groundPin, GPIO_MODE_OUTPUT)
        gpio_set_level(LED.pin, 0)
        gpio_set_level(LED.groundPin, 0)

        _ = Unmanaged.passRetained(self)
    }
}

//MARK: - Button

final class Button {
    private static let pin = GPIO_NUM_1
    private static let pollIntervalMs: UInt32 = 10
    private static let debounceMs: UInt32 = 30

    private let id: UInt16

    init(endpoint id: UInt16) {
        self.id = id

        gpio_reset_pin(Button.pin)
        gpio_set_direction(Button.pin, GPIO_MODE_INPUT)
        gpio_set_pull_mode(Button.pin, GPIO_PULLUP_ONLY)
        gpio_set_intr_type(Button.pin, GPIO_INTR_DISABLE)

        _ = Unmanaged.passRetained(self)
    }

    static let buttonTask: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
        guard let param else {
            vTaskDelete(nil)
            return
        }

        let button = Unmanaged<Button>.fromOpaque(param).takeUnretainedValue()

        // Let Matter platform layer fully initialize before accepting presses
        vTaskDelay(msToTicks(5000))

        var lastLevel = gpio_get_level(Button.pin)

        while true {
            let level = gpio_get_level(Button.pin)
            if level != lastLevel {
                vTaskDelay(msToTicks(Button.debounceMs))
                let settledLevel = gpio_get_level(Button.pin)
                lastLevel = settledLevel

                if settledLevel == 0 {
                    button.handlePress()

                    while gpio_get_level(Button.pin) == 0 {
                        vTaskDelay(msToTicks(Button.pollIntervalMs))
                    }
                    lastLevel = 1
                }
            }

            vTaskDelay(msToTicks(Button.pollIntervalMs))
        }
    }

    func start() {
        xTaskCreate(
            Button.buttonTask,
            "button_task",
            8192,
            Unmanaged.passUnretained(self).toOpaque(),
            4,
            nil
        )
    }

    private func handlePress() {
        send_command(to: self.id, with: chip.app.Clusters.OnOff.Commands.Toggle.Id)
    }
}

//MARK: - IR Sensor (NEC Receiver)

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

    private let gpio: gpio_num_t = GPIO_NUM_2
    var taskHandle: TaskHandle_t? = nil

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

    private let id: UInt16

    init(endpoint id: UInt16) {
        self.id = id
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
            send_command(to: self.id, with: chip.app.Clusters.OnOff.Commands.Off.Id)
        case Command.powerOn:
            send_command(to: self.id, with: chip.app.Clusters.OnOff.Commands.On.Id)
        default:
            print("[TBR/IR] Unknown command: \(command)")
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
        print("[TBR/IR] IR Task started")

        guard let param else { return }
        let ir = Unmanaged<IRSensor>.fromOpaque(param).takeUnretainedValue()

        ir.taskHandle = xTaskGetCurrentTaskHandle()

        var lastFrame: UInt32? = nil
        var lastSignalTime: Int64 = 0

        gpio_intr_enable(ir.gpio)

        while true {
            let notified = ulTaskNotifyTake_shim(1, msToTicks(notifyTimeoutMs))

            var shouldDebounce = false

            if notified == 0 {
                lastFrame = nil
            } else if let result = decodeNecFrame(gpio: ir.gpio) {
                let now = esp_timer_get_time()

                switch result {
                case .frame(let frame):
                    if isValidNec(frame) {
                        lastFrame = frame
                        lastSignalTime = now
                        ir.handleCommand(frame: frame)
                        shouldDebounce = true
                    }

                case .repeatCode:
                    if let frame = lastFrame,
                        (now - lastSignalTime) < repeatTimeoutUs
                    {
                        lastSignalTime = now
                        ir.handleCommand(frame: frame, isRepeat: true)
                        shouldDebounce = true
                    } else {
                        lastFrame = nil
                    }
                }
            }

            if shouldDebounce {
                vTaskDelay(msToTicks(debounceMs))
            }
            gpio_intr_enable(ir.gpio)
        }
    }

    func start() {
        xTaskCreate(
            IRSensor.ir_rx_task,
            "ir_rx_task",
            4096,
            Unmanaged.passUnretained(self).toOpaque(),
            3,
            nil
        )
    }
}
