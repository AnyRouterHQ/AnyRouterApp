import SwiftUI

/// The Tools row of the composer's + menu: this chat's switch, then one submenu per source group with the same source
/// and tool switches as Settings › Integrations.
struct ComposerToolsMenu: View {
    @Bindable var model: ChatViewModel
    @Environment(AppState.self) private var app

    var body: some View {
        let registry = app.tools
        let modelSource = model.model?.source
        let groups = ToolMenuLogic.groups(sources: registry.menuSources, tools: registry.tools) {
            registry.isOn($0, modelSource: modelSource)
        }
        Menu {
            // The root's GreenSwitchStyle forces a switch, which a menu cannot draw: each toggle came out as a titled row
            // and two blank checkmark rows. The automatic style is the menu's own checkmark row.
            Toggle("Use tools in this chat", isOn: Binding(
                get: { model.toolsEnabled },
                set: { model.setToolsEnabled($0) }
            ))
            .toggleStyle(.automatic)
            .accessibilityIdentifier("composer.tools-toggle")
            if model.toolsEnabled {
                Section {
                    ForEach(groups) { group in
                        Menu {
                            ForEach(group.sources) { entry in sourceSection(entry, titled: group.sources.count > 1) }
                        } label: {
                            Label { Text(group.title) } icon: { ToolSourceIcon(icon: group.icon) }
                            Text(ToolMenuLogic.countText(group.onCount))
                        }
                        .accessibilityIdentifier("composer.tool-group.\(group.id)")
                    }
                }
            }
        } label: {
            Label("Tools", systemImage: "puzzlepiece.extension")
            Text(ToolMenuLogic.summary(chatOn: model.toolsEnabled, groups: groups))
        }
        .accessibilityIdentifier("composer.tools")
    }

    private func sourceSection(_ entry: ToolMenuSource, titled: Bool) -> some View {
        let registry = app.tools
        let title = OfflineLogic.sourceTitle("Use \(entry.source.title) tools",
                                             needsNetwork: entry.source.id != ToolSourceCatalog.device.id,
                                             isOffline: app.network.isOffline)
        return Section {
            Toggle(title, isOn: Binding(get: { entry.isOn }, set: { registry.setSource(entry.source, on: $0) }))
                .toggleStyle(.automatic)
                .accessibilityIdentifier("composer.tool-source.\(entry.id)")
            ForEach(entry.tools) { tool in
                Toggle(tool.title, isOn: Binding(get: { tool.isOn }, set: { registry.setTool(tool.id, on: $0) }))
                    .toggleStyle(.automatic)
                    .disabled(!entry.isOn)
                    .accessibilityIdentifier("composer.tool.\(tool.id)")
            }
        } header: {
            if titled { Text(entry.source.title) }
        }
    }
}
