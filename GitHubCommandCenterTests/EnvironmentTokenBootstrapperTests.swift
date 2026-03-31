import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite
struct EnvironmentTokenBootstrapperTests {
    @Test
    func preloadIfNeeded_environmentVariableSavesTokenToKeychain() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: ["GITHUB_TOKEN": "ghp_from_env"],
            searchRoots: []
        )

        #expect(bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == "ghp_from_env")
    }

    @Test
    func preloadIfNeeded_existingKeychainTokenIsPreserved() throws {
        let service = makeService()
        try service.saveToken("ghp_existing")
        defer { try? service.deleteToken() }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: ["GITHUB_TOKEN": "ghp_from_env"],
            searchRoots: []
        )

        #expect(!bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == "ghp_existing")
    }

    @Test
    func preloadIfNeeded_envFileInAncestorDirectoryIsLoaded() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedDirectory =
            rootDirectory
            .appendingPathComponent("build/DerivedData/Build/Products/Debug", isDirectory: true)

        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "GITHUB_TOKEN=ghp_from_file\n".write(
            to: rootDirectory.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: [:],
            searchRoots: [nestedDirectory]
        )

        #expect(bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == "ghp_from_file")
    }

    @Test
    func preloadIfNeeded_envFileParsesExportedQuotedToken() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try "export GITHUB_TOKEN=\"ghp_from_quoted_file\" # local token\n".write(
            to: rootDirectory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: [:],
            searchRoots: [rootDirectory]
        )

        #expect(bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == "ghp_from_quoted_file")
    }

    @Test
    func preloadIfNeeded_ignoresUnterminatedQuotedToken() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try "export GITHUB_TOKEN=\"ghp_missing_quote\n".write(
            to: rootDirectory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: [:],
            searchRoots: [rootDirectory]
        )

        #expect(!bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == nil)
    }

    @Test
    func defaultSearchRoots_putsDevEnvSearchRootFromPlistFirst() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let devRootDir = base.appendingPathComponent("repo_root", isDirectory: true)
        try FileManager.default.createDirectory(at: devRootDir, withIntermediateDirectories: true)

        let bundleURL = base.appendingPathComponent("Test.bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let devRoot = devRootDir.path
        let plist: [String: Any] = ["CFBundleIdentifier": "test.bundle", "DevEnvSearchRoot": devRoot]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: base) }

        let bundle = try #require(Bundle(url: bundleURL))
        let roots = EnvironmentTokenBootstrapper.defaultSearchRoots(bundle: bundle)

        #expect(roots.count >= 1)
        #expect(roots[0].standardizedFileURL.path == devRootDir.standardizedFileURL.path)
    }

    @Test
    func defaultSearchRoots_omitsDevRootWhenPlistEmptyOrMissing() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = base.appendingPathComponent("Test.bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": "test.bundle",
            "DevEnvSearchRoot": "  \n  ",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: base) }

        let bundle = try #require(Bundle(url: bundleURL))
        let roots = EnvironmentTokenBootstrapper.defaultSearchRoots(bundle: bundle)

        // Expected roots: current working directory and the bundle's parent directory.
        #expect(roots.count == 2)
    }

    @Test
    func preloadIfNeeded_respectsConfiguredSearchDepthLimit() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executablePath =
            rootDirectory
            .appendingPathComponent(
                "Build/Products/Debug/GitHubCommandCenter.app/Contents/MacOS/GitHubCommandCenter",
                isDirectory: false
            )

        try FileManager.default.createDirectory(
            at: executablePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "GITHUB_TOKEN=ghp_depth_limited\n".write(
            to: rootDirectory.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: [:],
            searchRoots: [executablePath],
            searchDepthLimit: 3
        )

        let preloaded = bootstrapper.preloadIfNeeded()

        #expect(preloaded == false)
        #expect(try service.loadToken() == nil)
    }

    @Test
    func preloadIfNeeded_envFileInAncestorDirectoryIsLoadedFromExecutableLikePath() throws {
        let service = makeService()
        defer { try? service.deleteToken() }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executablePath =
            rootDirectory
            .appendingPathComponent(
                "Build/Products/Debug/GitHubCommandCenter.app/Contents/MacOS/GitHubCommandCenter",
                isDirectory: false
            )

        try FileManager.default.createDirectory(
            at: executablePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "GITHUB_TOKEN=ghp_from_executable_path\n".write(
            to: rootDirectory.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let bootstrapper = EnvironmentTokenBootstrapper(
            keychain: service,
            environment: [:],
            searchRoots: [executablePath]
        )

        #expect(bootstrapper.preloadIfNeeded())
        #expect(try service.loadToken() == "ghp_from_executable_path")
    }

    private func makeService() -> KeychainService {
        KeychainService(serviceName: "com.githubcommandcenter.tests.\(UUID().uuidString)")
    }
}
