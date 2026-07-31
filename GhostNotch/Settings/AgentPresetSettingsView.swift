import AppKit
import SwiftUI

struct AgentPresetSettingsView: View {
    @ObservedObject var store: AgentPresetStore

    var body: some View {
        Form {
            Section("Directory Presets") {
                if store.directoryPresets.isEmpty {
                    Text("Add up to three folders for quick agent launches.")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(store.directoryPresets.enumerated()), id: \.element.id) { index, preset in
                    DirectoryPresetRow(
                        index: index,
                        preset: preset,
                        canMoveUp: index > 0,
                        canMoveDown: index < store.directoryPresets.count - 1,
                        onUpdate: store.updateDirectoryPreset,
                        onRemove: { store.removeDirectoryPreset(id: preset.id) },
                        onMoveUp: { store.moveDirectoryPreset(from: index, to: index - 1) },
                        onMoveDown: { store.moveDirectoryPreset(from: index, to: index + 1) }
                    )
                }

                Button("Add Folder...") {
                    addFolder()
                }
                .disabled(store.directoryPresets.count >= AgentPresetStore.maximumDirectoryPresets)
            }

            Section("Agents") {
                Text("Choose up to three agents for the hover launcher.")
                    .foregroundStyle(.secondary)

                ForEach(AgentLauncher.all) { launcher in
                    Toggle(
                        launcher.displayName,
                        isOn: Binding(
                            get: { store.enabledAgentIDs.contains(launcher.id) },
                            set: { store.setAgent(launcher.id, isEnabled: $0) }
                        )
                    )
                    .disabled(
                        !store.enabledAgentIDs.contains(launcher.id) &&
                            store.enabledAgentIDs.count >= AgentPresetStore.maximumVisibleAgents
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
    }

    private func addFolder() {
        guard let url = chooseDirectory() else {
            return
        }

        store.addDirectoryPreset(
            label: url.lastPathComponent.isEmpty ? "Folder" : url.lastPathComponent,
            path: url.path
        )
    }
}

private struct DirectoryPresetRow: View {
    let index: Int
    let preset: AgentLaunchDirectoryPreset
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onUpdate: (AgentLaunchDirectoryPreset) -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(
                    "Label",
                    text: Binding(
                        get: { preset.label },
                        set: { update(label: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

                TextField(
                    "Icon",
                    text: Binding(
                        get: { preset.icon },
                        set: { update(icon: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)

                Text(preset.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Choose...") {
                    chooseReplacementDirectory()
                }

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .help("Move up")

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .help("Move down")

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove folder")
            }

            iconHelpText

            if !preset.directoryExists() {
                Text("Folder cannot be found. It will not appear in hover quick launch.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var iconHelpText: some View {
        let sanitizedIcon = DirectoryPresetIcon.sanitized(preset.icon)
        if sanitizedIcon.isEmpty {
            Text("Icon: emoji or 1-3 characters. Blank uses Auto: \(automaticIcon).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Icon: emoji or 1-3 characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var automaticIcon: String {
        DirectoryPresetIcon.automaticValue(fallbackSource: preset.displayLabel)
    }

    private func update(label: String? = nil, path: String? = nil, icon: String? = nil) {
        var updatedPreset = preset
        if let label {
            updatedPreset.label = label
        }
        if let path {
            updatedPreset.path = path
        }
        if let icon {
            updatedPreset.icon = DirectoryPresetIcon.sanitized(icon)
        }
        onUpdate(updatedPreset)
    }

    private func chooseReplacementDirectory() {
        guard let url = chooseDirectory() else {
            return
        }

        update(path: url.path)
    }
}

@MainActor private func chooseDirectory() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Choose"

    return panel.runModal() == .OK ? panel.url : nil
}
