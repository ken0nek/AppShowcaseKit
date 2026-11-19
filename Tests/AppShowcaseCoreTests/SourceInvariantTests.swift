import Foundation
import Testing

/// Reads the package's own sources. Both rules here are broken by a line that
/// compiles and passes every behavioral test, so only reading the line finds it.
@Suite("Source invariants")
struct SourceInvariantTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil),
            "\(directory.path) is missing"
        )
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func codeLines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
    }

    @Test("the core target imports Foundation and nothing else")
    func coreImportsOnlyFoundation() throws {
        let files = try swiftFiles(in: Self.sources.appendingPathComponent("AppShowcaseCore"))
        try #require(!files.isEmpty)

        for file in files {
            let imports = try codeLines(of: file).filter {
                $0.hasPrefix("import ") || $0.contains(" import ")
            }
            #expect(
                imports.allSatisfy { $0 == "import Foundation" },
                "\(file.lastPathComponent) imports \(imports)"
            )
        }
    }

    /// Each of these would need a declared reason in the privacy manifest, and
    /// all three manifests declare none.
    @Test("no target calls an API that needs a declared reason")
    func noRequiredReasonAPI() throws {
        let banned = [
            "UserDefaults", "odificationDate", "creationDate", "attributesOfItem",
            "systemUptime", "mach_absolute_time", "volumeAvailableCapacity",
            "systemFreeSize", "activeInputModes",
        ]
        let files = try swiftFiles(in: Self.sources)
        try #require(!files.isEmpty)

        for file in files {
            for line in try codeLines(of: file) {
                let hits = banned.filter { line.contains($0) }
                #expect(hits.isEmpty, "\(file.lastPathComponent): \(line)")
            }
        }
    }
}
