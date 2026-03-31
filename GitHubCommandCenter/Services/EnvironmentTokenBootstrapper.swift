import Foundation

struct EnvironmentTokenBootstrapper {
    private let keychain: KeychainService
    private let environment: [String: String]
    private let searchRoots: [URL]
    private let fileManager: FileManager

    init(
        keychain: KeychainService = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchRoots: [URL] = Self.defaultSearchRoots(bundle: .main),
        fileManager: FileManager = .default
    ) {
        self.keychain = keychain
        self.environment = environment
        self.searchRoots = searchRoots
        self.fileManager = fileManager
    }

    @discardableResult
    func preloadIfNeeded() -> Bool {
        do {
            let savedToken = try keychain.loadToken()
            if let savedToken, !savedToken.isEmpty {
                return false
            }

            guard let preload = tokenToPreload() else {
                return false
            }

            try keychain.saveToken(preload.token)
            return true
        } catch {
            return false
        }
    }

    private func tokenToPreload() -> (source: String, token: String)? {
        if let token = normalizedToken(from: environment["GITHUB_TOKEN"]) {
            return ("GITHUB_TOKEN", token)
        }

        if let token = normalizedToken(from: environment["GH_TOKEN"]) {
            return ("GH_TOKEN", token)
        }

        let envFiles = candidateEnvFiles()
        for fileURL in envFiles {
            guard
                fileManager.fileExists(atPath: fileURL.path),
                let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                let token = tokenFromEnvFile(contents)
            else {
                continue
            }

            return (fileURL.lastPathComponent, token)
        }

        return nil
    }

    private func candidateEnvFiles() -> [URL] {
        var seenPaths = Set<String>()
        var files: [URL] = []

        for directoryPath in searchDirectoryPaths() {
            for fileName in [".env.local", ".env"] {
                let filePath = (directoryPath as NSString).appendingPathComponent(fileName)
                let standardizedPath = (filePath as NSString).standardizingPath
                if seenPaths.insert(standardizedPath).inserted {
                    files.append(URL(fileURLWithPath: standardizedPath, isDirectory: false))
                }
            }
        }

        return files
    }

    private func searchDirectoryPaths() -> [String] {
        var seenPaths = Set<String>()
        var directories: [String] = []

        for root in searchRoots {
            var directoryPath = normalizedDirectoryPath(for: root)

            while true {
                if seenPaths.insert(directoryPath).inserted {
                    directories.append(directoryPath)
                }

                let parentPath = (directoryPath as NSString).deletingLastPathComponent
                if parentPath.isEmpty || parentPath == directoryPath {
                    break
                }
                directoryPath = parentPath
            }
        }

        return directories
    }

    private func normalizedDirectoryPath(for root: URL) -> String {
        let standardizedPath = (root.path as NSString).standardizingPath
        if URL(fileURLWithPath: standardizedPath).pathExtension == "app" {
            return (standardizedPath as NSString).deletingLastPathComponent
        }
        if root.hasDirectoryPath {
            return standardizedPath
        }
        return (standardizedPath as NSString).deletingLastPathComponent
    }

    private func tokenFromEnvFile(_ contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let normalizedLine =
                line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                : line

            guard let equalsIndex = normalizedLine.firstIndex(of: "=") else {
                continue
            }

            let key = String(normalizedLine[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            guard key == "GITHUB_TOKEN" || key == "GH_TOKEN" else {
                continue
            }

            let rawValue = String(normalizedLine[normalizedLine.index(after: equalsIndex)...])
            if let token = normalizedToken(from: rawValue) {
                return token
            }
        }

        return nil
    }

    private func normalizedToken(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let firstCharacter = trimmedValue.first, firstCharacter == "\"" || firstCharacter == "'" {
            return quotedToken(in: trimmedValue, quote: firstCharacter)
        }

        let uncommentedValue: String
        if let commentRange = trimmedValue.range(of: " #") {
            uncommentedValue = String(trimmedValue[..<commentRange.lowerBound])
        } else {
            uncommentedValue = trimmedValue
        }

        let token = uncommentedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func quotedToken(in value: String, quote: Character) -> String? {
        var token = ""
        var isEscaping = false

        for character in value.dropFirst() {
            if isEscaping {
                token.append(character)
                isEscaping = false
                continue
            }

            if quote == "\"", character == "\\" {
                isEscaping = true
                continue
            }

            if character == quote {
                return token.isEmpty ? nil : token
            }

            token.append(character)
        }

        return token.isEmpty ? nil : token
    }

    /// Search roots for `.env.local` / `.env`, in priority order.
    ///
    /// Debug builds set `DevEnvSearchRoot` in Info.plist to `$(SRCROOT)` so repo-root env files are found
    /// even when the process working directory and app bundle live under DerivedData.
    static func defaultSearchRoots(bundle: Bundle = .main) -> [URL] {
        var roots: [URL] = []

        if let plistPath = bundle.object(forInfoDictionaryKey: "DevEnvSearchRoot") as? String {
            let trimmed = plistPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                roots.append(URL(fileURLWithPath: trimmed, isDirectory: true))
            }
        }

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let bundleParent = bundle.bundleURL.deletingLastPathComponent()

        roots.append(currentDirectory)
        roots.append(bundleParent)

        return roots
    }
}
