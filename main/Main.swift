@_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	// Root Matter node owns the device identity and the endpoint tree.
	let rootNode = Matter.Node()
	// Keep identify handling visible during commissioning and fabric discovery.
	rootNode.identifyHandler = { print("identify") }

	// Create the main switch endpoint before starting the Matter stack.
	let switchEndpoint = Matter.SwitchEndpoint(rootNode: rootNode)
	rootNode.addEndpoint(switchEndpoint)

	// Start the Matter stack after the node and endpoints are registered.
	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	// Keep the task alive; the device work happens in callbacks and FreeRTOS tasks.
	while true { sleep(1) }
}
