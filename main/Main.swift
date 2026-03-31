//MARK: - Entrypoint

var globalLED: LED!

@_cdecl("update_local_led_shim")
func updateLocalLED(state: Bool) {
	globalLED?.enabled = state
}

@_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	let err = nvs_flash_init()
	if err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND {
		nvs_flash_erase()
		nvs_flash_init()
	}

	globalLED = LED()

	let rootNode = Matter.Node(name: "Irrigation Controller")
	rootNode.identifyHandler = { print("identify") }

	let switchEndpoint = Matter.SwitchEndpoint(rootNode: rootNode)

	let button = Button(endpoint: switchEndpoint.id, led: globalLED)

	rootNode.addEndpoint(switchEndpoint)

	if esp_matter.client.init_client_callbacks_shim() != ESP_OK {
		fatalError("Failed to initialize Matter client callbacks")
	}

	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	button.start()

	while true { sleep(1) }
}
