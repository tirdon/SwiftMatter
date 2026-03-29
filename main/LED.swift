// MARK: - LED

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
