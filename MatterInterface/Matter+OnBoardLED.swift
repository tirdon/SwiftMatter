// Matter+OnBoardLED.swift
// On-board status LED (active-low on GPIO 15).

extension Matter {
    final class OnBoardLED: GPIO {
        private static let pin = GPIO_NUM_15

        var enabled: Bool = true {
            didSet {
                gpio_set_level(OnBoardLED.pin, enabled ? 1 : 0)
            }
        }

        init() {
            gpio_reset_pin(OnBoardLED.pin)
            gpio_set_direction(OnBoardLED.pin, GPIO_MODE_OUTPUT)
            self.enabled = false
        }
    }
}
