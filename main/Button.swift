// Button.swift
// GPIO button polling task — reads a button and toggles an on/off endpoint.

// MARK: - Toggle

func toggleOnOff(endpointId: UInt16) {
    var val = esp_matter_attr_val_t()
    let clusterId = chip.app.Clusters.OnOff.Id
    let attrId = chip.app.Clusters.OnOff.Attributes.OnOff.Id
    guard esp_matter.attribute.get_val_shim(endpointId, clusterId, attrId, &val) == ESP_OK else { return }
    val.val.b = !val.val.b
    esp_matter.attribute.update_shim(endpointId, clusterId, attrId, &val)
}

// MARK: - Button Task

private struct ButtonTaskParams {
    let gpio: gpio_num_t
    let endpointId: UInt16
    let ledPtr: UnsafeMutableRawPointer
}

func startButtonTask(gpio: gpio_num_t, endpointId: UInt16, led: LED) {
    gpio_reset_pin(gpio)
    gpio_set_direction(gpio, GPIO_MODE_INPUT)
    gpio_set_pull_mode(gpio, GPIO_PULLUP_ONLY)

    let params = UnsafeMutablePointer<ButtonTaskParams>.allocate(capacity: 1)
    params.initialize(to: ButtonTaskParams(
        gpio: gpio,
        endpointId: endpointId,
        ledPtr: Unmanaged.passUnretained(led).toOpaque()
    ))

    xTaskCreate_shim({ arg in
        guard let arg else { return }
        let p = arg.assumingMemoryBound(to: ButtonTaskParams.self)
        let led = Unmanaged<LED>.fromOpaque(p.pointee.ledPtr).takeUnretainedValue()
        var last: Int32 = 1
        while true {
            let cur = gpio_get_level(p.pointee.gpio)
            if cur == 0 && last == 1 {
                vTaskDelay_ms_shim(50)
                if gpio_get_level(p.pointee.gpio) == 0 {
                    led.enabled.toggle()
                    toggleOnOff(endpointId: p.pointee.endpointId)
                    send_bound_toggle_shim(p.pointee.endpointId)
                    print("[Button] Toggled endpoint + bound devices")
                    while gpio_get_level(p.pointee.gpio) == 0 {
                        vTaskDelay_ms_shim(20)
                    }
                }
            }
            last = cur
            vTaskDelay_ms_shim(20)
        }
    }, "button", 4096, params, 5)

    print("[TBR] Button task started")
}
