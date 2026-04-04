//MARK: - Entrypoint

var globalLED: LED!

@_cdecl("update_local_led_shim")
func updateLocalLED(state: Bool) {
	globalLED?.enabled = state
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
	set_openthread_platform_config_native_shim()

	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	// Wait for Matter platform layer (including system clock) to fully initialize
	while !esp_matter.is_started() {
		vTaskDelay(msToTicks(100))
	}

	button.start()
	ir.start()

	while true { sleep(1) }
}
