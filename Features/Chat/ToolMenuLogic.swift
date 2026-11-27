import Foundation

/// One tool switch in the composer's Tools menu.
struct ToolMenuItem: Identifiable, Equatable {
    /// `RegisteredTool.id`, the key `ToolRegistry.setTool` takes.
    var id: String
    var title: String
    var isOn: Bool
}

/// A source's switch and the switches of its tools.
struct ToolMenuSource: Identifiable, Equatable {
    var source: ToolSource
    var isOn: Bool
    var tools: [ToolMenuItem]

    var id: String { source.id }
    /// Tools the model is offered: the source is on and the tool is on.
    var onCount: Int { isOn ? tools.filter(\.isOn).count : 0 }
}

/// One submenu under Tools: "On this device", "AnyRouter" (with the web services that need no account), or a custom server.
struct ToolMenuGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var icon: ToolSource.Icon
    var sources: [ToolMenuSource]

    var onCount: Int { sources.reduce(0) { $0 + $1.onCount } }
}

/// The Tools submenu of the composer's + menu, built from the same sources and switches as Settings › Integrations.
enum ToolMenuLogic {
    /// `sources` in Settings order; `isOn` is the registry's answer for the chat's model.
    static func groups(sources: [ToolSource], tools: [RegisteredTool], isOn: (ToolSource) -> Bool) -> [ToolMenuGroup] {
        var groups: [ToolMenuGroup] = []
        for source in sources {
            let entry = ToolMenuSource(
                source: source, isOn: isOn(source),
                tools: tools.filter { belongs($0, to: source) }.map { ToolMenuItem(id: $0.id, title: $0.title, isOn: $0.enabled) })
            let anyRouter = ToolSourceCatalog.anyRouter
            let inAnyRouter = source.group == .web || source.group == .anyRouter
            let key = inAnyRouter ? anyRouter.id : source.id
            if let index = groups.firstIndex(where: { $0.id == key }) {
                // AnyRouter's own tools come before the web services grouped with it.
                if source.id == anyRouter.id { groups[index].sources.insert(entry, at: 0) } else { groups[index].sources.append(entry) }
            } else {
                groups.append(ToolMenuGroup(
                    id: key, title: inAnyRouter ? anyRouter.title : source.title,
                    icon: inAnyRouter ? anyRouter.icon : source.icon, sources: [entry]))
            }
        }
        return groups
    }

    /// Built-in tools are the device's, except `web_search`, which runs on AnyRouter. MCP tools go with their server.
    static func belongs(_ tool: RegisteredTool, to source: ToolSource) -> Bool {
        switch tool.source {
        case .builtIn:
            let owner = tool.name == WebSearchBinding.name ? ToolSourceCatalog.anyRouter.id : ToolSourceCatalog.device.id
            return source.id == owner
        case .mcp(let serverID, _):
            return source.server?.id == serverID
        }
    }

    /// The secondary line of a menu row: "5 on".
    static func countText(_ count: Int) -> String { "\(count) on" }

    /// The secondary line of the Tools row: "Off" while the chat's switch is off, else how many tools are on.
    static func summary(chatOn: Bool, groups: [ToolMenuGroup]) -> String {
        chatOn ? countText(groups.reduce(0) { $0 + $1.onCount }) : "Off"
    }
}
