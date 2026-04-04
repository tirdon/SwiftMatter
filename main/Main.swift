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

	// --- Matter Node ---
	// The root node represents this device on the Matter fabric.
	let rootNode = Matter.Node(name: "Thread Border Router")
	rootNode.identifyHandler = {
		print("identify: Thread Border Router")
	}

	_ = Matter.SwitchEndpoint(rootNode: rootNode)

	// --- Thread Border Router Endpoint ---
	// Creates the TBR delegate (KVS-backed), ThreadBorderRouterManagement
	// cluster, and enables the PAN_CHANGE feature.
	let tbrEndpoint = Matter.ThreadBorderRouterEndpoint(rootNode: rootNode)
	rootNode.addEndpoint(tbrEndpoint)

	// --- OpenThread Platform Setup ---
	// Register VFS eventfd — required by the OpenThread border router
	// discovery delegate before esp_openthread_border_router_init().
	register_eventfd_shim()

	// Configure OpenThread for ESP32-C6 native 802.15.4 radio.
	// Must be called before esp_matter::start() so the Matter stack
	// knows how to initialise the OpenThread platform layer.
	set_openthread_platform_config_native_shim()

	// --- Start Matter ---
	// WiFi connectivity callback in Matter.Application initialises the
	// border router agent once an IP is acquired.
	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	while true { sleep(1) }
}
