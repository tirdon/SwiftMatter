final class LED: GPIO {
    var enabled: Bool = false {
        didSet {
            gpio_set_level(GPIO_NUM_10, enabled ? 1 : 0)
            gpio_set_level(GPIO_NUM_9, enabled ? 1 : 0)
        }
    }

    init() {
        gpio_reset_pin(GPIO_NUM_10)
        gpio_set_direction(GPIO_NUM_10, GPIO_MODE_OUTPUT)
        gpio_set_level(GPIO_NUM_10, 0)

        gpio_reset_pin(GPIO_NUM_9)
        gpio_set_direction(GPIO_NUM_9, GPIO_MODE_OUTPUT)
        gpio_set_level(GPIO_NUM_9, 0)

        _ = Unmanaged.passRetained(self)
    }
}

final class Button {
    private let id: UInt16
    private let led: LED

    func update() {

        var att_dataType: esp_matter_attr_val_t = esp_matter_bool(!led.enabled)

        _ = esp_matter.attribute.update_shim(
            UInt16(self.id),
            UInt32(chip.app.Clusters.OnOff.Id),
            UInt32(chip.app.Clusters.OnOff.Attributes.OnOff.Id),
            &att_dataType
        )
    }

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

    var buttonConfig = button_config_t()

    var buttonGpioConfig = button_gpio_config_t()

    var buttonHandle: button_handle_t? = nil
}

final class DHT22Sensor {
    let gpio = GPIO_NUM_4
    var temperature: Float = 0.0
    var humidity: Float = 0.0

    let humidityId: UInt16
    let temperatureId: UInt16

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
        let dht = Unmanaged<DHT22Sensor>.fromOpaque(param).takeUnretainedValue()
        var saved_state_humi: Float = 0.0
        var saved_state_temp: Float = 0.0
        while true {
            let res = dht_read_float_data(
                DHT_TYPE_AM2301, dht.gpio, &dht.humidity, &dht.temperature)

            if res == ESP_OK && (dht.humidity != saved_state_humi
                || dht.temperature != saved_state_temp)
            {
                print("Humidity: \(dht.humidity)  Temp: \(dht.temperature)\n")
                saved_state_humi = dht.humidity
                saved_state_temp = dht.temperature

                dht.update_temp(val: Int16(saved_state_temp * 100))
                dht.update_humidity(val: UInt16(saved_state_humi * 100))

            } else if dht.humidity != saved_state_humi && dht.temperature != saved_state_temp {
                print("Fail but, Humidity: \(dht.humidity)  Temp: \(dht.temperature)\n")
                // saved_state_humi = dht.humidity
                // saved_state_temp = dht.temperature
            } else {
                // print("Humidity: \(dht.humidity)  Temp: \(dht.temperature)\n")
                // print("Could not read data from sensor: \(res.description)\n")
            }
            vTaskDelay(10000 / UInt32(configTICK_RATE_HZ))
            // vTaskDelay(1000)
        }
    }

    func update_temp(val: Int16) {
        var att_dataType: esp_matter_attr_val_t = esp_matter_int16(val)
        _ = esp_matter.attribute.update_shim(
            UInt16(self.temperatureId),
            UInt32(chip.app.Clusters.TemperatureMeasurement.Id),
            UInt32(chip.app.Clusters.TemperatureMeasurement.Attributes.MeasuredValue.Id),
            &att_dataType
        )
    }

    func update_humidity(val: UInt16) {
        var att_dataType: esp_matter_attr_val_t = esp_matter_uint16(val)
        _ = esp_matter.attribute.update_shim(
            UInt16(self.humidityId),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Id),
            UInt32(chip.app.Clusters.RelativeHumidityMeasurement.Attributes.MeasuredValue.Id),
            &att_dataType
        )
    }
}

final class IRSensor {

    init() {  // rmt_init

    }

}
// rx = receive, tx = transmit
let ir_rx_task: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    print("IR Task started, waiting for signals...")
    var recv_cfg = rmt_receive_config_t()
    recv_cfg.signal_range_min_ns = 1_250
    recv_cfg.signal_range_max_ns = 12_000_000

    // rmt_receive(rx_chan, raw_symbols, MemoryLayout<raw_symbols>.stride, &recv_cfg)

    while true {
        let evt = rmt_rx_done_event_data_t()
        // if (xQueueReceive(valve.button_queue, &att_dataType, portMAX_DELAY) == pdPASS) {
        // }
    }
}
