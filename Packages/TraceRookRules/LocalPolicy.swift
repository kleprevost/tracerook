import Foundation
import TraceRookContracts

public struct PolicyContext: Sendable {
    public let cwd: String
    public let projectRoot: String
    public let home: String
    public let deploymentTask: Bool
    public let repeatedDenial: Bool
    public init(cwd: String, projectRoot: String? = nil, home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                deploymentTask: Bool = false, repeatedDenial: Bool = false) {
        self.cwd = cwd; self.projectRoot = projectRoot ?? cwd; self.home = home
        self.deploymentTask = deploymentTask; self.repeatedDenial = repeatedDenial
    }
}
public struct PolicyAssessment: Sendable {
    public let evidence: [RuleEvidence]
    public let inspectionComplete: Bool
    public var severity: Severity { evidence.max(by: { $0.severity.score < $1.severity.score })?.severity ?? .low }
    public var catastrophic: Bool { evidence.contains { $0.catastrophic && $0.severity == .critical } }
}

/// Deliberately bounded shell inspection, not a shell interpreter or sandbox.
/// Dynamic execution and unsupported grammar are reviewable uncertainty. Critical
/// matches require concrete operation, source/destination and scope evidence.
public enum LocalPolicy {
    public static let version = "2.0.0"
    public static func evaluate(tool: String, input: JSONValue, context: PolicyContext) -> PolicyAssessment {
        evaluate(tool: tool, input: input, context: context, depth: 0)
    }
    private static func evaluate(tool: String, input: JSONValue, context: PolicyContext, depth: Int) -> PolicyAssessment {
        guard depth < 4 else { return PolicyAssessment(evidence: [.init(ruleID: "TR-INSPECTION-INCOMPLETE", severity: .high, summary: "Nested execution exceeds inspection bound")], inspectionComplete: false) }
        var evidence: [RuleEvidence] = [], complete = true
        func add(_ id: String, _ severity: Severity, _ message: String, catastrophic: Bool = false) {
            if !evidence.contains(where: { $0.ruleID == id }) { evidence.append(.init(ruleID: id, severity: severity, summary: message, catastrophic: catastrophic)) }
        }
        func inspectFile(_ path: String, content: String?, mutation: Bool, deletion: Bool = false) {
            if sensitive(path) { add("TR-SENSITIVE-READ", .high, "Sensitive credential path referenced") }
            if dotenv(path) { add("TR-DOTENV-ACCESS", .high, "Private environment file referenced") }
            if securityPath(path) && mutation {
                if deletion || content.map(disablesHooks) == true {
                    add("TR-POLICY-TAMPER", .critical, "Concrete security-hook removal or disable operation", catastrophic: true)
                } else { add("TR-SECURITY-CONFIG", .high, "Security configuration mutation requires review") }
            }
        }
        switch tool.lowercased() {
        case "bash", "shell", "exec_command", "shell_command":
            guard let command = input["command"]?.string, !command.isEmpty, command.utf8.count <= 65_536 else {
                return PolicyAssessment(evidence: [.init(ruleID: "TR-INSPECTION-INCOMPLETE", severity: .high, summary: "Executable input cannot be inspected")], inspectionComplete: false)
            }
            let scan = ShellInspection.scan(command)
            complete = scan.complete
            var workingDirectory = context.cwd
            var credentialSources: Set<Int> = [], uploadSinks: Set<Int> = []
            var directCredentialTransfer = false, fetches = false, executesInput = false
            for (commandIndex, originalTokens) in scan.commands.enumerated() {
                var tokens = originalTokens
                var wrappers = 0
                while let word = tokens.first {
                    let wrapper = URL(fileURLWithPath: word.value).lastPathComponent.lowercased()
                    if wrapper == "sudo" || wrapper == "doas" { add("TR-PRIV-ESC", .high, "Privilege elevation requested") }
                    if word.value.contains("=") && !word.dynamic { tokens.removeFirst(); wrappers += 1 }
                    else if ["sudo", "doas", "env", "command", "time", "nohup"].contains(wrapper) {
                        tokens.removeFirst(); wrappers += 1
                        while let option = tokens.first, option.value.hasPrefix("-") {
                            if ["-u", "-g", "--user", "--group"].contains(option.value) && tokens.count > 1 { tokens.removeFirst(2) }
                            else if ["--", "-n", "-E", "-i", "--ignore-environment"].contains(option.value) { tokens.removeFirst() }
                            else { complete = false; break }
                        }
                    } else { break }
                    if wrappers > 8 { complete = false; break }
                }
                guard let first = tokens.first else { continue }
                let name = URL(fileURLWithPath: first.value).lastPathComponent.lowercased()
                let arguments = Array(tokens.dropFirst())
                let values = arguments.map(\.value)
                if ["sudo", "doas"].contains(name) { add("TR-PRIV-ESC", .high, "Privilege elevation requested") }
                if ["sh", "bash", "zsh", "fish", "eval", "python", "python3", "ruby", "perl", "node", "osascript", "xargs"].contains(name) {
                    executesInput = true
                    if !values.isEmpty { complete = false }
                    if ["sh", "bash", "zsh"].contains(name), let index = values.firstIndex(of: "-c"), arguments.count == index + 2, !arguments[index + 1].dynamic {
                        let nested = evaluate(tool: "Bash", input: .object(["command": .string(arguments[index + 1].value)]),
                            context: .init(cwd: workingDirectory, projectRoot: context.projectRoot, home: context.home, deploymentTask: context.deploymentTask), depth: depth + 1)
                        for item in nested.evidence { add(item.ruleID, item.severity, item.summary, catastrophic: item.catastrophic) }
                    }
                }
                if name == "cd" {
                    if arguments.count == 1, !arguments[0].dynamic, let path = canonical(arguments[0], cwd: workingDirectory, home: context.home) { workingDirectory = path }
                    else { complete = false }
                }
                let reader = ["cat", "head", "tail", "less", "more", "sed", "awk", "grep", "cp", "scp", "rsync", "tar", "zip"].contains(name)
                if reader {
                    for token in arguments where !token.value.hasPrefix("-") {
                        if sensitive(token.value) { credentialSources.insert(commandIndex); inspectFile(token.value, content: nil, mutation: false) }
                        if dotenv(token.value) { inspectFile(token.value, content: nil, mutation: false) }
                    }
                }
                if ["curl", "wget"].contains(name) {
                    fetches = true
                    let external = values.contains { outbound($0) }
                    let sendsBody = values.contains { ["-d", "--data", "--data-binary", "--data-raw", "--data-urlencode", "-F", "--form", "-T", "--upload-file"].contains($0) || $0.hasPrefix("--data=") || $0.hasPrefix("--data-binary=") || $0.hasPrefix("--upload-file=") || ($0.hasPrefix("-d") && $0.count > 2) }
                    if external && sendsBody { add("TR-UNKNOWN-EGRESS", .high, "External upload or data submission requested") }
                    if external && sendsBody {
                        for (index, token) in arguments.enumerated() {
                            let uploadOptions = ["-d", "--data", "--data-binary", "--data-urlencode", "-F", "--form", "-T", "--upload-file"]
                            let previous = index > 0 ? arguments[index - 1].value : ""
                            let optionValue = uploadOptions.contains(previous) || token.value.hasPrefix("--data-binary=") || token.value.hasPrefix("--upload-file=") || token.value.hasPrefix("--data=")
                            if optionValue && !token.dynamic {
                                if token.value == "@-" || token.value == "-" { uploadSinks.insert(commandIndex) }
                                if (token.value.hasPrefix("@") || ["-T", "--upload-file"].contains(previous) || token.value.hasPrefix("--upload-file=")) && sensitive(token.value) { directCredentialTransfer = true }
                            }
                        }
                    }
                }
                if ["scp", "rsync"].contains(name), values.contains(where: { $0.contains(":") && !$0.hasPrefix("/") }) {
                    directCredentialTransfer = directCredentialTransfer || arguments.contains { !$0.dynamic && sensitive($0.value) }
                    add("TR-UNKNOWN-EGRESS", .high, "Remote transfer requested")
                }
                if name == "aws", values.prefix(2) == ["s3", "cp"], values.contains(where: { $0.hasPrefix("s3://") }) {
                    directCredentialTransfer = directCredentialTransfer || arguments.contains { !$0.dynamic && sensitive($0.value) }
                    add("TR-UNKNOWN-EGRESS", .high, "Object-storage transfer requested")
                }
                if name == "rm" {
                    let recursive = values.contains { $0 == "--recursive" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.lowercased().contains("r")) }
                    for token in arguments where !token.value.hasPrefix("-") {
                        inspectFile(token.value, content: nil, mutation: true, deletion: true)
                        if recursive {
                            guard !token.dynamic, let path = canonical(token, cwd: workingDirectory, home: context.home) else { complete = false; continue }
                            let root = canonical(ShellWord(value: context.projectRoot), cwd: context.cwd, home: context.home) ?? context.projectRoot
                            let outside = path != root && !path.hasPrefix(root + "/")
                            let userOrSystem = path == "/" || path == context.home || path.hasPrefix(context.home + "/") || ["/Users", "/etc", "/System", "/Library", "/usr", "/private/etc"].contains(where: { path == $0 || path.hasPrefix($0 + "/") })
                            if outside && userOrSystem { add("TR-DESTRUCT-OUTSIDE", .critical, "Recursive deletion targets user or system data outside project scope", catastrophic: true) }
                            else if outside { add("TR-DESTRUCT-OUTSIDE", .high, "Recursive deletion outside project scope requires review") }
                        }
                    }
                }
                if name == "launchctl", values.contains(where: { ["bootout", "disable", "unload", "remove", "kill"].contains($0) }),
                   values.contains(where: { $0.lowercased().contains("com.tracerook.agent") }) {
                    add("TR-POLICY-TAMPER", .critical, "TraceRook service disable operation", catastrophic: true)
                }
                if ["chmod", "chown"].contains(name), values.contains(where: { securityPath($0) || $0.hasPrefix("/etc/") || $0.hasPrefix("/System/") }) {
                    add("TR-SECURITY-CONFIG", .high, "Security-sensitive ownership or permission change")
                }
                if name == "base64" || (name == "openssl" && values.contains("base64")) {
                    if scan.commands.count > 1 { add("TR-ENCODED-COMMAND", .high, "Encoded pipeline requires inspection") }
                }
                if !context.deploymentTask && ((name == "git" && values.contains("push") && values.contains(where: { $0 == "--force" || $0 == "-f" || $0 == "--force-with-lease" })) ||
                    (["npm", "pnpm", "cargo", "docker", "gh", "wrangler", "vercel", "terraform"].contains(name) && values.contains(where: { ["publish", "deploy", "push", "apply", "release"].contains($0) }))) {
                    add("TR-PUBLISH-DEPLOY", .high, "Publishing or deployment is outside observed task scope")
                }
                // Redirection is concrete only when the target is literal.
                for index in arguments.indices where [">", ">>"].contains(arguments[index].value) && arguments[index].operatorToken {
                    if index + 1 < arguments.count {
                        let target = arguments[index + 1]
                        if target.dynamic { complete = false }
                        else { inspectFile(target.value, content: ["printf", "echo"].contains(name) ? values.prefix(index).joined(separator: " ") : nil, mutation: true) }
                    } else { complete = false }
                }
            }
            let pipelineTransfer = credentialSources.contains { source in
                uploadSinks.contains { sink in source < sink && (source..<sink).allSatisfy { scan.pipelineEdges.contains($0) } }
            }
            if directCredentialTransfer || pipelineTransfer { add("TR-CRED-EXFIL", .critical, "Credential source feeds an outbound transfer", catastrophic: true) }
            if fetches && executesInput && !scan.pipelineEdges.isEmpty { add("TR-REMOTE-EXEC", .high, "Remote content feeds an execution pipeline") }
        case "read", "read_file":
            if let path = input["file_path"]?.string ?? input["path"]?.string { inspectFile(path, content: nil, mutation: false) } else { complete = false }
        case "write", "write_file", "edit", "multiedit":
            guard let path = input["file_path"]?.string ?? input["path"]?.string else { complete = false; break }
            inspectFile(path, content: input["content"]?.string ?? input["new_string"]?.string, mutation: true)
            if tool.lowercased() == "multiedit", case .array(let edits) = input["edits"] {
                for edit in edits { inspectFile(path, content: edit["new_string"]?.string, mutation: true) }
            }
        case "apply_patch":
            guard let patch = input["command"]?.string ?? input.string, patch.hasPrefix("*** Begin Patch"), patch.utf8.count <= 65_536 else { complete = false; break }
            let lines = patch.components(separatedBy: "\n")
            var found = false
            for (index, line) in lines.enumerated() {
                for prefix in ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "] where line.hasPrefix(prefix) {
                    found = true
                    let following = lines.dropFirst(index + 1).prefix(while: { !$0.hasPrefix("*** ") }).filter { $0.hasPrefix("+") }.map { String($0.dropFirst()) }.joined(separator: "\n")
                    inspectFile(String(line.dropFirst(prefix.count)), content: following, mutation: true, deletion: prefix.contains("Delete"))
                }
            }
            complete = found && patch.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("*** End Patch")
        default: complete = false
        }
        if context.repeatedDenial { add("TR-REPEAT-DENIED", .high, "Another denied action was proposed in this session") }
        if !complete { add("TR-INSPECTION-INCOMPLETE", .high, "Action contains unsupported or dynamic syntax; review required") }
        return PolicyAssessment(evidence: evidence, inspectionComplete: complete)
    }
    private static func sensitive(_ text: String) -> Bool {
        let value = text.lowercased()
        if value.hasSuffix(".pub") || value.contains(".env.example") { return false }
        return [".ssh/id_", ".aws/credentials", "application_default_credentials.json", ".git-credentials", ".netrc", ".npmrc", ".ssh/"].contains(where: value.contains)
    }
    private static func dotenv(_ text: String) -> Bool {
        let file = URL(fileURLWithPath: text).lastPathComponent
        return file == ".env" || (file.hasPrefix(".env.") && ![".env.example", ".env.sample", ".env.template"].contains(file))
    }
    private static func securityPath(_ text: String) -> Bool {
        let value = text.lowercased()
        return value.contains(".claude/settings") || value.contains(".codex/hooks") || value.contains(".codex/config.toml") ||
            value.contains("tracerook") && (value.contains("launchagents") || value.contains("application support"))
    }
    private static func disablesHooks(_ text: String) -> Bool {
        text.range(of: #"(?i)"disableAllHooks"\s*:\s*true|"hooks"\s*:\s*\{\s*\}|"hooks"\s*:\s*\[\s*\]"#, options: .regularExpression) != nil
    }
    private static func outbound(_ text: String) -> Bool {
        guard let url = URL(string: text), ["http", "https", "ftp", "sftp"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else { return false }
        return !["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
    private static func canonical(_ word: ShellWord, cwd: String, home: String) -> String? {
        guard !word.dynamic, !word.value.contains("\0"), !word.value.contains("*") else { return nil }
        var path = word.value
        if word.tildeExpansion && (path == "~" || path.hasPrefix("~/")) { path = home + path.dropFirst() }
        if !path.hasPrefix("/") { path = cwd + "/" + path }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private struct ShellWord {
    var value: String
    var dynamic = false
    var operatorToken = false
    var tildeExpansion = true
}
private enum ShellInspection {
    struct Scan { let commands: [[ShellWord]]; let pipelineEdges: Set<Int>; let complete: Bool }
    static func scan(_ input: String) -> Scan {
        var commands: [[ShellWord]] = [], current: [ShellWord] = [], word = ""
        var pipelineEdges: Set<Int> = []
        var dynamic = false, tilde = true, quote: Character?, escape = false, started = false, complete = true, comment = false
        func flush() {
            if started { current.append(ShellWord(value: word, dynamic: dynamic, tildeExpansion: tilde)) }
            word = ""; started = false; dynamic = false; tilde = true
        }
        func finish(pipeline: Bool = false) {
            flush(); if !current.isEmpty {
                commands.append(current); current = []
                if pipeline { pipelineEdges.insert(commands.count - 1) }
            }
        }
        let characters = Array(input); var index = 0
        while index < characters.count {
            let character = characters[index]; index += 1
            if comment { if character == "\n" { comment = false; finish() }; continue }
            if escape { word.append(character); started = true; escape = false; continue }
            if character == "\\" && quote != "'" { escape = true; started = true; continue }
            if let active = quote {
                if character == active { quote = nil }
                else { word.append(character); if active == "\"" && ["$", "`"].contains(character) { dynamic = true; complete = false } }
                continue
            }
            if character == "'" || character == "\"" { if !started { tilde = false }; quote = character; started = true; continue }
            if character == "#" && !started { comment = true; continue }
            if [";", "|", "&", "\n"].contains(character) {
                let paired = index < characters.count && characters[index] == character && ["|", "&"].contains(character)
                if paired { index += 1 }
                finish(pipeline: character == "|" && !paired); continue
            }
            if character == " " || character == "\t" { flush(); continue }
            if character == ">" || character == "<" {
                flush()
                var operation = String(character)
                if index < characters.count && characters[index] == character {
                    index += 1; operation.append(character)
                    if character == "<" { complete = false }
                }
                current.append(ShellWord(value: operation, operatorToken: true)); continue
            }
            if ["$", "`", "(", ")", "{", "}"].contains(character) { dynamic = true; complete = false }
            word.append(character); started = true
            if current.count > 512 || commands.count > 128 { complete = false; break }
        }
        if quote != nil || escape { complete = false }
        finish()
        return Scan(commands: commands, pipelineEdges: pipelineEdges, complete: complete)
    }
}
