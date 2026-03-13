enum Matter {}

extension Matter {
    final class Node {
        var identifyHandler: (() -> Void)?
        var endpoints: [Endpoint] = []

        func addEndpoint(_ endpoint: Endpoint) {
            endpoints.append(endpoint)
        }

        var innerNode: RootNode!

        init(name: String = " ") {
            let err = nvs_flash_init()
            if err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND {
                nvs_flash_erase()
                nvs_flash_init()
            }

            // For now, leak the object, to be able to use local variables to declare
            // it. We don't expect this object to be created and destroyed repeatedly.
            _ = Unmanaged.passRetained(self)

            let root = RootNode(
                name: name,
                attribute: self.eventHandler,
                identify: { _, _, _, _ in self.identifyHandler?() }
            )
            guard let root else { fatalError("Failed to setup root node.") }
            self.innerNode = root
        }

        private func eventHandler(
            type: MatterAttributeEventType,
            endpoint: __idf_main.Endpoint,
            cluster: __idf_main.Cluster,
            attribute: UInt32,
            value: UnsafeMutablePointer<esp_matter_attr_val_t>?
        ) {

            guard type == .didSet else { return }
            guard let e = self.endpoints.first(where: { $0.id == endpoint.eid }) else { return }

            switch value?.pointee.type {
            case ESP_MATTER_VAL_TYPE_BOOLEAN, ESP_MATTER_VAL_TYPE_NULLABLE_BOOLEAN:
                let value: Int = Int((value?.pointee.val.b ?? false) ? 1 : 0)
                guard let a = Matter.Endpoint.Attribute(cluster: cluster, attribute: attribute)
                else { return }
                e.eventHandler?(Matter.Endpoint.Event(type: type, attribute: a, value: value))
            default: break
            }
        }
    }
}

extension Matter {
    class Endpoint {
        var eventHandler: ((Matter.Endpoint.Event) -> Void)?
        var id: UInt16 = 0

        init(rootNode: Matter.Node, endpoint id: UInt16) {
            self.id = id
            // self.node = node
            _ = Unmanaged.passRetained(self)
        }

        enum Attribute {
            case onOff
            case dht22update
            case unknown(UInt32)

            init?(cluster: Cluster, attribute aid: UInt32) {
                if cluster.as(OnOffControl.self) != nil {
                    switch aid {
                    case OnOffControl.onOff.rawValue: self = .onOff
                    default: self = .unknown(aid)
                    }
                } else {
                    self = .unknown(aid)
                }
            }
        }

        struct Event {
            let type: MatterAttributeEventType
            let attribute: Attribute
            let value: Int
        }
    }
}
