import Foundation

struct AgentLaunchDirectoryPreset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    var path: String
    var icon: String

    init(id: UUID = UUID(), label: String, path: String, icon: String = "") {
        self.id = id
        self.label = label
        self.path = path
        self.icon = DirectoryPresetIcon.sanitized(icon)
    }

    var displayLabel: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }

        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastPathComponent.isEmpty ? "Folder" : lastPathComponent
    }

    var fileURL: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    func directoryExists(fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    fileprivate func normalizedForStorage() -> AgentLaunchDirectoryPreset {
        AgentLaunchDirectoryPreset(id: id, label: label, path: path, icon: icon)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case path
        case icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        path = try container.decode(String.self, forKey: .path)
        icon = DirectoryPresetIcon.sanitized(try container.decodeIfPresent(String.self, forKey: .icon) ?? "")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(path, forKey: .path)
        try container.encode(DirectoryPresetIcon.sanitized(icon), forKey: .icon)
    }
}

enum DirectoryPresetIcon {
    static let maximumCharacterCount = 3

    static func sanitized(_ icon: String) -> String {
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIcon.isEmpty else {
            return ""
        }

        let characters = Array(trimmedIcon)
        if characters.first?.containsEmojiStyleScalar == true {
            return String(characters.prefix(1))
        }

        return String(characters.prefix(maximumCharacterCount))
    }

    static func displayValue(icon: String, fallbackSource: String) -> String {
        let sanitizedIcon = sanitized(icon)
        return sanitizedIcon.isEmpty ? automaticValue(fallbackSource: fallbackSource) : sanitizedIcon
    }

    static func automaticValue(fallbackSource: String) -> String {
        let source = fallbackSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return "F"
        }

        let words = iconWords(from: source)
        if words.count > 1 {
            let initials = words
                .prefix(maximumCharacterCount)
                .compactMap(\.first)
                .map { String($0) }
                .joined()
            return initials.uppercased()
        }

        return String(source.prefix(maximumCharacterCount)).uppercased()
    }

    private static func iconWords(from source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .flatMap(camelCaseWords)
    }

    private static func camelCaseWords(from word: String) -> [String] {
        var words: [String] = []
        var currentWord = ""
        var previousWasLowercase = false

        for character in word {
            let characterString = String(character)
            let isUppercase = characterString.rangeOfCharacter(from: .uppercaseLetters) != nil
            let isLowercase = characterString.rangeOfCharacter(from: .lowercaseLetters) != nil

            if isUppercase, previousWasLowercase, !currentWord.isEmpty {
                words.append(currentWord)
                currentWord = characterString
            } else {
                currentWord.append(character)
            }

            previousWasLowercase = isLowercase
        }

        if !currentWord.isEmpty {
            words.append(currentWord)
        }

        return words
    }
}

enum DirectoryPresetSelection {
    static func toggled(
        currentSelection: AgentLaunchDirectoryPreset.ID?,
        selectedPresetID: AgentLaunchDirectoryPreset.ID
    ) -> AgentLaunchDirectoryPreset.ID? {
        currentSelection == selectedPresetID ? nil : selectedPresetID
    }
}

struct AgentPresetConfiguration: Codable, Equatable, Sendable {
    var directoryPresets: [AgentLaunchDirectoryPreset]
    var enabledAgentIDs: [AgentLauncher.ID]

    static let `default` = AgentPresetConfiguration(
        directoryPresets: [],
        enabledAgentIDs: [.codex, .claude]
    )

    func normalized() -> AgentPresetConfiguration {
        var seenPresetIDs = Set<UUID>()
        let normalizedPresets = directoryPresets
            .map { $0.normalizedForStorage() }
            .filter { seenPresetIDs.insert($0.id).inserted }
            .prefix(AgentPresetStore.maximumDirectoryPresets)

        var seenAgentIDs = Set<AgentLauncher.ID>()
        let normalizedAgentIDs = enabledAgentIDs
            .filter { AgentLauncher.ID.allCases.contains($0) }
            .filter { seenAgentIDs.insert($0).inserted }
            .prefix(AgentPresetStore.maximumVisibleAgents)

        return AgentPresetConfiguration(
            directoryPresets: Array(normalizedPresets),
            enabledAgentIDs: Array(normalizedAgentIDs)
        )
    }
}

private extension Character {
    var containsEmojiStyleScalar: Bool {
        String(self).unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.generalCategory == .otherSymbol
        }
    }
}

@MainActor
final class AgentPresetStore: ObservableObject {
    static let shared = AgentPresetStore()
    nonisolated static let maximumDirectoryPresets = 3
    nonisolated static let maximumVisibleAgents = 3

    private static let configurationKey = "AgentPresetConfiguration.v1"

    private let userDefaults: UserDefaults

    @Published private(set) var configuration: AgentPresetConfiguration {
        didSet {
            save(configuration)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        configuration = Self.load(from: userDefaults)
    }

    var directoryPresets: [AgentLaunchDirectoryPreset] {
        configuration.directoryPresets
    }

    var enabledAgentIDs: [AgentLauncher.ID] {
        configuration.enabledAgentIDs
    }

    var enabledLaunchers: [AgentLauncher] {
        AgentLauncher.launchers(for: enabledAgentIDs)
    }

    func addDirectoryPreset(label: String, path: String, icon: String = "") {
        guard configuration.directoryPresets.count < Self.maximumDirectoryPresets else {
            return
        }

        var updatedConfiguration = configuration
        updatedConfiguration.directoryPresets.append(
            AgentLaunchDirectoryPreset(label: label, path: path, icon: icon)
        )
        configuration = updatedConfiguration.normalized()
    }

    func updateDirectoryPreset(_ preset: AgentLaunchDirectoryPreset) {
        var updatedConfiguration = configuration
        guard let index = updatedConfiguration.directoryPresets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }

        updatedConfiguration.directoryPresets[index] = preset
        configuration = updatedConfiguration.normalized()
    }

    func removeDirectoryPreset(id: AgentLaunchDirectoryPreset.ID) {
        var updatedConfiguration = configuration
        updatedConfiguration.directoryPresets.removeAll { $0.id == id }
        configuration = updatedConfiguration.normalized()
    }

    func moveDirectoryPreset(from sourceIndex: Int, to destinationIndex: Int) {
        var updatedConfiguration = configuration
        guard updatedConfiguration.directoryPresets.indices.contains(sourceIndex),
              updatedConfiguration.directoryPresets.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let preset = updatedConfiguration.directoryPresets.remove(at: sourceIndex)
        updatedConfiguration.directoryPresets.insert(preset, at: destinationIndex)
        configuration = updatedConfiguration.normalized()
    }

    func setAgent(_ agentID: AgentLauncher.ID, isEnabled: Bool) {
        var enabledIDs = configuration.enabledAgentIDs

        if isEnabled {
            guard !enabledIDs.contains(agentID), enabledIDs.count < Self.maximumVisibleAgents else {
                return
            }
            enabledIDs.append(agentID)
        } else {
            enabledIDs.removeAll { $0 == agentID }
        }

        configuration = AgentPresetConfiguration(
            directoryPresets: configuration.directoryPresets,
            enabledAgentIDs: enabledIDs
        ).normalized()
    }

    func loadConfiguration(_ configuration: AgentPresetConfiguration) {
        self.configuration = configuration.normalized()
    }

    private static func load(from userDefaults: UserDefaults) -> AgentPresetConfiguration {
        guard let data = userDefaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(AgentPresetConfiguration.self, from: data) else {
            return .default
        }

        return configuration.normalized()
    }

    private func save(_ configuration: AgentPresetConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration.normalized()) else {
            return
        }

        userDefaults.set(data, forKey: Self.configurationKey)
    }
}
