import Foundation

/// The text of one skill before it is stored: a name, one line saying what it is for, and the steps.
struct SkillDraft: Equatable, Sendable {
    var name: String
    var description: String
    var body: String
}

/// Why a skill's text was refused. The words are shown to the user.
enum SkillIssue: Error, Equatable, LocalizedError {
    case badName, reservedName, emptyDescription, descriptionTooLong, emptyBody, bodyTooLong, noFrontMatter

    var errorDescription: String? {
        switch self {
        case .badName:
            "The name must use lowercase letters, digits and single hyphens, like trip-planner, in 64 characters or fewer."
        case .reservedName:
            "A skill that comes with the app already has that name."
        case .emptyDescription:
            "The skill needs a description of what it is for."
        case .descriptionTooLong:
            "The description is too long. Keep it to \(SkillLibraryLogic.descriptionLimit) characters or fewer."
        case .emptyBody:
            "The skill has no steps."
        case .bodyTooLong:
            "The steps are too long. Keep them to \(SkillLibraryLogic.bodyLimit) characters or fewer."
        case .noFrontMatter:
            "This is not a SKILL.md file. It must start with a --- block that has a name and a description."
        }
    }
}

extension Skill.Source {
    var label: String {
        switch self {
        case .bundled: "Built in"
        case .hub: "AnyRouter hub"
        case .imported: "Imported from a URL"
        case .proposed: "Proposed by the model"
        }
    }
}

/// The rules for the skills the user owns (agent design 4.2, unit K2): what a skill may contain, how a SKILL.md reads,
/// and which skills a chat offers. Skill text is untrusted data. Only the name and the one-line description reach the
/// system message, so both are checked here, before anything is stored.
enum SkillLibraryLogic {
    static let nameLimit = 64
    static let descriptionLimit = 300
    static let bodyLimit = 8_000

    /// The draft trimmed and checked. The description is folded to one line: it sits in the index as `- name: description`,
    /// and a second line there would read as an instruction of the app.
    static func validate(_ draft: SkillDraft) throws -> SkillDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isKebabCase(name) else { throw SkillIssue.badName }
        guard !SkillLogic.bundled.contains(where: { $0.name == name }) else { throw SkillIssue.reservedName }
        let description = draft.description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !description.isEmpty else { throw SkillIssue.emptyDescription }
        guard description.count <= descriptionLimit else { throw SkillIssue.descriptionTooLong }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw SkillIssue.emptyBody }
        guard body.count <= bodyLimit else { throw SkillIssue.bodyTooLong }
        return SkillDraft(name: name, description: description, body: body)
    }

    /// Lowercase ASCII letters and digits in groups split by single hyphens, 1 to 64 characters.
    static func isKebabCase(_ name: String) -> Bool {
        guard name.count <= nameLimit else { return false }
        return name.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { group in
            !group.isEmpty && group.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
        }
    }

    /// A SKILL.md file: `name` and `description` from its front matter, then the steps. Other keys, such as a tool
    /// list, are ignored: a skill never grants a tool.
    static func parse(_ text: String) throws -> SkillDraft {
        guard let parsed = frontMatter(text) else { throw SkillIssue.noFrontMatter }
        return try validate(SkillDraft(
            name: parsed.fields["name"] ?? "", description: parsed.fields["description"] ?? "", body: parsed.body))
    }

    /// A skill from a hub item: the front matter of its body when it has one, else the item's own description.
    /// The hub slug is the name.
    static func hubDraft(slug: String, description: String?, body: String) throws -> SkillDraft {
        let parsed = frontMatter(body)
        return try validate(SkillDraft(
            name: slug, description: parsed?.fields["description"] ?? description ?? "", body: parsed?.body ?? body))
    }

    /// The lines of a `---` block at the top, read as the YAML a SKILL.md uses (plain, quoted and folded values, and
    /// indented continuation lines), and what follows it. Nil when the text has no block or the block never closes.
    static func frontMatter(_ raw: String) -> (fields: [String: String], body: String)? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingPrefix("\u{FEFF}")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        var entries: [(key: String, parts: [String])] = []
        for line in lines[1..<end] {
            if line.first?.isWhitespace == true {
                if !entries.isEmpty { entries[entries.count - 1].parts.append(line.trimmingCharacters(in: .whitespaces)) }
            } else if let colon = line.firstIndex(of: ":") {
                entries.append((
                    String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                    [String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)]))
            }
        }
        let fields = Dictionary(entries.map { ($0.key, value(of: $0.parts)) }, uniquingKeysWith: { first, _ in first })
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }

    /// One value from its parts: the text after the colon and the indented lines under it, joined by spaces. A `>` or `|`
    /// marker only says how the lines are folded, so it is dropped.
    private static func value(of parts: [String]) -> String {
        let marker = parts[0].hasPrefix(">") || parts[0].hasPrefix("|")
        let joined = (marker ? Array(parts.dropFirst()) : parts).filter { !$0.isEmpty }.joined(separator: " ")
        guard joined.count >= 2, let quote = joined.first, quote == "\"" || quote == "'", joined.last == quote else { return joined }
        return String(joined.dropFirst().dropLast())
    }

    /// The bundled skills, then the stored skills that are switched on. A stored skill with a name that is already taken
    /// is left out, so a name means one skill. `nil` (the store could not be read) is the bundled skills alone.
    static func active(_ stored: [Skill]?) -> [Skill] {
        guard let stored else { return SkillLogic.bundled }
        var taken = Set(SkillLogic.bundled.map(\.name))
        return SkillLogic.bundled + stored.filter { taken.insert($0.name).inserted }
    }
}
