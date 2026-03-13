extension Matter {
    class OnBoardLED: GPIO {
        var enabled: Bool = true {
            didSet {
                gpio_set_level(GPIO_NUM_8, enabled ? 0 : 1) // Active low
            }
        }

        init() {
            gpio_reset_pin(GPIO_NUM_8)
            gpio_set_direction(GPIO_NUM_8, GPIO_MODE_OUTPUT)
            gpio_set_level(GPIO_NUM_8, 0)
        }
    }
}