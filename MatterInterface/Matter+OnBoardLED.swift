// Matter+OnBoardLED.swift
// On-board status LED (active-low on GPIO).

extension Matter {
    final class OnBoardLED: GPIO {
        // #if CONFIG_IDF_TARGET == esp32c3
        private static let pin = GPIO_NUM_8
        // #else
        // private static let pin = GPIO_NUM_15
        // #endif

        var enabled: Bool = true {
            didSet {
                gpio_set_level(OnBoardLED.pin, enabled ? 0 : 1)
            }
        }

        init() {
            gpio_reset_pin(OnBoardLED.pin)
            gpio_set_direction(OnBoardLED.pin, GPIO_MODE_OUTPUT)
            gpio_set_level(OnBoardLED.pin, 0)
        }
    }
}
