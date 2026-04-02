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

	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	button.start()
	ir.start()

	while true { sleep(1) }
}
