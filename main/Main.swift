//MARK: - Entrypoint

var globalLED: LED?

@_cdecl("update_local_led_shim")
func updateLocalLED(state: Bool) {
	globalLED?.enabled = state
}

//MARK: - Attribute Poller

/// Periodically reads the OnOff attribute from all bound devices
/// to keep the local LED state in sync even if a subscription drops.
final class AttributePoller {
	/// How often to poll (seconds).
	private let intervalSec: UInt32

	/// Local endpoint whose bindings we read from.
	private let endpointId: UInt16

	init(endpoint: UInt16, pollIntervalSec: UInt32 = 30) {
		self.endpointId = endpoint
		self.intervalSec = pollIntervalSec
	}

	static let pollTask: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
		guard let param else { vTaskDelete(nil); return }
		let poller = Unmanaged<AttributePoller>.fromOpaque(param).takeUnretainedValue()

		// Wait for Matter + subscriptions to be established first
		vTaskDelay(msToTicks(10_000))
		print("[Poller] Attribute polling started (every \(poller.intervalSec)s)")

		while true {
			esp_matter.client.read_bound_device_onoff_shim(poller.endpointId)
			vTaskDelay(msToTicks(poller.intervalSec * 1000))
		}
	}

	func start() {
		xTaskCreate(
			AttributePoller.pollTask,
			"attr_poll",
			4096,
			Unmanaged.passUnretained(self).toOpaque(),
			2,
			nil
		)
	}
}

@_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	globalLED = LED()

	let rootNode = Matter.Node(name: "Irrigation Controller")
	rootNode.identifyHandler = { print("identify") }

	let switchEndpoint = Matter.SwitchClientEndpoint(rootNode: rootNode)

	let button = Button(endpoint: switchEndpoint.id)
	let ir = IRSensor(endpoint: switchEndpoint.id)

	rootNode.addEndpoint(switchEndpoint)

	if esp_matter.client.init_client_callbacks_shim() != ESP_OK {
		fatalError("Failed to initialize Matter client callbacks")
	}

	// Configure OpenThread for ESP32-C6 native 802.15.4 radio.
	// Must be called before esp_matter::start() so the Matter stack
	// can initialise the OpenThread platform layer.
	// set_openthread_platform_config_native_shim()

	let app = Matter.Application()
	app.rootNode = rootNode
	app.switchEndpointId = switchEndpoint.id
	app.start()

	// Wait for Matter platform layer (including system clock) to fully initialize
	while !esp_matter.is_started() {
		vTaskDelay(msToTicks(100))
	}

	button.start()
	ir.start()

	// Start periodic attribute polling (reads bound device state every 30s)
	let poller = AttributePoller(endpoint: switchEndpoint.id, pollIntervalSec: 30)
	poller.start()

	while true { sleep(1) }
}
