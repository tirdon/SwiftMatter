// Matter.swift
// High-level Matter node and endpoint types used by the application layer.

// MARK: - Matter Namespace

enum Matter {}

// MARK: - Node

extension Matter {
    final class Node {
        var identifyHandler: (() -> Void)?
        var endpoints: [Endpoint] = []
        var innerNode: RootNode!

        init(name: String = " ") {
            _ = Unmanaged.passRetained(self)

            guard
                let root = RootNode(
                    name: name,
                    attribute: self.eventHandler,
                    identify: { _, _, _, _ in self.identifyHandler?() }
                )
            else {
                fatalError("Failed to setup root node.")
            }
            self.innerNode = root
        }

        func addEndpoint(_ endpoint: Endpoint) {
            endpoints.append(endpoint)
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
                let intValue = Int((value?.pointee.val.b ?? false) ? 1 : 0)
                guard let a = Matter.Endpoint.Attribute(cluster: cluster, attribute: attribute)
                else { return }
                e.eventHandler?(Matter.Endpoint.Event(type: type, attribute: a, value: intValue))
            default:
                break
            }
        }
    }
}

// MARK: - Endpoint

extension Matter {
    class Endpoint {
        var eventHandler: ((Event) -> Void)?
        let id: UInt16

        init(rootNode: Matter.Node, endpoint id: UInt16) {
            self.id = id
            _ = Unmanaged.passRetained(self)
        }

        enum Attribute {
            case onOff
            case levelControl
            case unknown(UInt32)

            init?(cluster: Cluster, attribute aid: UInt32) {
                if cluster.as(OnOffControl.self) != nil {
                    switch aid {
                    case OnOffControl.onOff.rawValue: self = .onOff
                    default: self = .unknown(aid)
                    }
                } else if cluster.as(LevelControl.self) != nil {
                    switch aid {
                    case LevelControl.currentLevel.rawValue: self = .levelControl
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
