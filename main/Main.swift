// Main.swift
// Application entry point — initialises hardware, Matter stack, and runtime tasks.

//MARK: - LED Sync Callback

var globalLED: LED?

@_cdecl("update_local_led_shim")
func updateLocalLED(state: Bool) {
	globalLED?.enabled = state
}

//MARK: - Entrypoint

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

	while true { sleep(1) }
}
