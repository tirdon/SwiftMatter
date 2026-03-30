// MARK: - Entry Point

@_cdecl("app_main")
func main() -> Never {

    print("Thread Border Router starting on ESP32-C6")

    // --- System Initialisation ---
    // NVS is required for event loop and Matter.
    var err = nvs_flash_init()
    if err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND {
        nvs_flash_erase()
        err = nvs_flash_init()
    }

    // Essential ESP-IDF initialization for networking and events.
    esp_event_loop_create_default()

    let led = LED()

    // --- Matter Node ---
    // The root node represents this device on the Matter fabric.
    let rootNode = Matter.Node(name: "Thread Border Router")
    rootNode.identifyHandler = {
        print("identify: Thread Border Router")
    }

    let switchEndpoint = Matter.SwitchEndpoint(rootNode: rootNode)
    rootNode.addEndpoint(switchEndpoint)

    // Handle on/off events from fabric (Home app toggle) → LED
    switchEndpoint.eventHandler = { event in
        if case .onOff = event.attribute {
            led.enabled = event.value != 0
            print("[Switch] \(led.enabled ? "ON" : "OFF")")
        } else if case .levelControl = event.attribute {
            print("[Switch] Brightness: \(event.value)")
        }
    }

    // Register VFS eventfd — required by the OpenThread border router
    // discovery delegate before esp_openthread_border_router_init().
    register_eventfd_shim()

    // Configure OpenThread for ESP32-C6 native 802.15.4 radio.
    // Must be called before esp_matter::start() so the Matter stack
    // knows how to initialise the OpenThread platform layer.

    set_openthread_platform_config_native_shim()

    // Register client callbacks for sending commands and subscribing to
    // bound remote Thread devices. Must be called before esp_matter::start().
    init_client_callbacks_shim(
        switchEndpoint.id,
        { onOff, ctx in
            guard let ctx else { return }
            let led = Unmanaged<LED>.fromOpaque(ctx).takeUnretainedValue()
            led.enabled = onOff
            print("[TBR] Remote device: \(onOff ? "ON" : "OFF")")
        }, Unmanaged.passUnretained(led).toOpaque())

    // Create TBR endpoint after starting Matter stack
    create_thread_border_router_endpoint_shim(rootNode.innerNode.node)

    let app = Matter.Application()
    app.rootNode = rootNode
    app.start()

    // Button on GPIO 0 — toggles LED, local endpoint, and bound remote devices
    startButtonTask(gpio: GPIO_NUM_0, endpointId: switchEndpoint.id, led: led)

    while true { sleep(1) }
}
