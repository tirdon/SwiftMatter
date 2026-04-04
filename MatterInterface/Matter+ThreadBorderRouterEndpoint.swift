// Matter+ThreadBorderRouterEndpoint.swift
// Thread Border Router endpoint backed by GenericOpenThreadBorderRouterDelegate.

extension Matter {
    /// Thread Border Router endpoint — creates the TBR delegate, management
    /// cluster, and PAN_CHANGE feature via the C++ shim (required because
    /// GenericOpenThreadBorderRouterDelegate is a C++ template class).
    final class ThreadBorderRouterEndpoint: Endpoint {
        init(rootNode: Node) {
            guard let ep = create_thread_border_router_endpoint_shim(
                rootNode.innerNode.node
            ) else {
                fatalError("Failed to create Thread Border Router endpoint")
            }
            let endpointId = esp_matter.endpoint.get_id(
                ep.assumingMemoryBound(to: esp_matter.endpoint_t.self)
            )
            super.init(rootNode: rootNode, endpoint: endpointId)
        }
    }
}
