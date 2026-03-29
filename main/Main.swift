/// Thread Border Router — ESP32-C6
///
/// Bridges a Thread mesh network (IEEE 802.15.4) to the IP network (WiFi).
/// The ESP32-C6's dual radios (WiFi + 802.15.4) make it a natural TBR host.
///
/// Thread networking, border routing, NAT64, and SRP are managed by the
/// ESP-Matter / OpenThread platform layer. This file initialises the Matter
/// node, starts the stack, and runs diagnostic monitoring tasks.
///
/// Required sdkconfig additions (on top of the existing defaults):
///
///   # OpenThread core
///   CONFIG_OPENTHREAD_ENABLED=y
///   CONFIG_OPENTHREAD_BORDER_ROUTER=y
///
///   # Thread Border Router features
///   CONFIG_OPENTHREAD_DNS64=y
///   CONFIG_OPENTHREAD_SRP_SERVER=y
///   CONFIG_OPENTHREAD_NAT64=y
///
///   # 802.15.4 radio
///   CONFIG_IEEE802154_ENABLED=y
///
///   # Thread network commissioning via Matter
///   CONFIG_ENABLE_THREAD_NETWORK_COMMISSIONING=y

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

// MARK: - Switch Endpoint

extension Matter {
    final class SwitchEndpoint: Endpoint {
        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_plug_in_unit.config_t()
            config.on_off.on_off = false

            let endpoint = esp_matter.endpoint.on_off_plug_in_unit.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            // Binding cluster lets controllers bind this endpoint to remote devices
            var bindingConfig = esp_matter.cluster.binding.config_t()
            esp_matter.cluster.binding.create(
                endpoint,
                &bindingConfig,
                UInt8(esp_matter.CLUSTER_FLAG_SERVER.rawValue)
            )
            print("[TBR] Binding cluster added")

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

// MARK: - Entry Point

@_cdecl("app_main")
func main() -> Never {

    print("Thread Border Router starting on ESP32-C6")

    let led = LED()

    // --- Matter Node ---
    // The root node represents this device on the Matter fabric.
    // NVS is initialised inside Matter.Node.init().
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
        }
    }

    // Configure OpenThread for ESP32-C6 native 802.15.4 radio.
    // Must be called before esp_matter::start() so the Matter stack
    // knows how to initialise the OpenThread platform layer.
    set_openthread_platform_config_native_shim()

    // Register client callbacks for sending commands and subscribing to
    // bound remote Thread devices. Must be called before esp_matter::start().
    init_client_callbacks_shim(switchEndpoint.id, { onOff, ctx in
        guard let ctx else { return }
        let led = Unmanaged<LED>.fromOpaque(ctx).takeUnretainedValue()
        led.enabled = onOff
        print("[TBR] Remote device: \(onOff ? "ON" : "OFF")")
    }, Unmanaged.passUnretained(led).toOpaque())

    let app = Matter.Application()
    app.rootNode = rootNode
    app.start()

    // Button on GPIO 0 — toggles LED, local endpoint, and bound remote devices
    startButtonTask(gpio: GPIO_NUM_0, endpointId: switchEndpoint.id, led: led)

    while true { sleep(1) }
}
