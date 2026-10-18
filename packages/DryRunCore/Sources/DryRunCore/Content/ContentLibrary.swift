import Foundation

public struct ContentManifest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var contentVersion: String
    public var generatedAt: String
    public var reviewState: String
    public var note: String?
    public var domains: [String]
    public var locales: [String]
}

public struct ContentLoadIssue: Sendable, Hashable, CustomStringConvertible {
    public var path: String
    public var message: String
    public var description: String { "\(path): \(message)" }
}

/// Bundled, versioned content: locale packs, sources, and public region packs.
/// Scenario packs are loaded separately via `ScenarioLibrary` (simulation lane).
/// Loading is strict for the manifest and locale packs (the app cannot explain anything without them)
/// and tolerant for optional public packs (issues are reported, never silently swallowed).
public struct ContentLibrary: Sendable {
    public var root: URL
    public var manifest: ContentManifest
    public var localeManifest: LocaleManifest?
    public var tables: [String: [String: [String: String]]]
    public var sources: [SourceRef]
    public var regionPacks: [RegionPack]
    public var issues: [ContentLoadIssue]

    public var contentVersion: String { manifest.contentVersion }

    public func localizer(for locale: String) -> Localizer {
        Localizer(locale: locale, tables: tables, manifest: localeManifest, sourceLocale: localeManifest?.sourceLocale ?? "en")
    }

    public func source(_ id: String) -> SourceRef? { sources.first { $0.id == id } }

    /// Statewide resources plus resources for this region, deterministic order.
    public func resources(forRegion regionID: String) -> [PublicResource] {
        guard PublicDataPolicy.isAllowedRegionID(regionID) else { return [] }
        var order: [String] = []
        var byID: [String: PublicResource] = [:]
        for pack in regionPacks {
            for r in pack.resources where r.regionIDs.contains(regionID) || r.regionIDs.contains("tx-statewide") {
                if byID[r.id] == nil { order.append(r.id) }
                // Later validated packs are newer precedence than the bundled
                // baseline, while preserving the first-seen display order.
                byID[r.id] = r
            }
        }
        return order.compactMap { byID[$0] }
    }

    public func region(_ id: String) -> RegionInfo? {
        regionPacks.lazy.flatMap(\.regions).first { $0.id == id }
    }

    public static func load(from root: URL) throws -> ContentLibrary {
        let fm = FileManager.default
        let decoder = DryRunJSON.decoder()
        let manifest = try decoder.decode(ContentManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        var issues: [ContentLoadIssue] = []

        let localesDir = root.appendingPathComponent("locales")
        var localeManifest: LocaleManifest?
        let lmURL = localesDir.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: lmURL.path) {
            do { localeManifest = try decoder.decode(LocaleManifest.self, from: Data(contentsOf: lmURL)) }
            catch { issues.append(ContentLoadIssue(path: "locales/manifest.json", message: "\(error)")) }
        } else {
            issues.append(ContentLoadIssue(path: "locales/manifest.json", message: "missing; all translations treated as draft"))
        }

        var tables: [String: [String: [String: String]]] = [:]
        for locale in manifest.locales {
            let dir = localesDir.appendingPathComponent(locale)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files.sorted() where file.hasSuffix(".json") {
                let domain = String(file.dropLast(5))
                let table = try decoder.decode([String: String].self, from: Data(contentsOf: dir.appendingPathComponent(file)))
                tables[locale, default: [:]][domain] = table
            }
        }
        guard tables["en"] != nil else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "English source locale pack missing"])
        }

        var sources: [SourceRef] = []
        let sourcesURL = root.appendingPathComponent("sources/sources.json")
        if let data = try? Data(contentsOf: sourcesURL) {
            if let list = try? decoder.decode([SourceRef].self, from: data) { sources = list }
            else if let wrapped = try? decoder.decode(SourceList.self, from: data) { sources = wrapped.sources }
            else { issues.append(ContentLoadIssue(path: "sources/sources.json", message: "could not decode")) }
        }

        var packs: [RegionPack] = []
        let regionsDir = root.appendingPathComponent("regions")
        if let files = try? fm.contentsOfDirectory(atPath: regionsDir.path) {
            for file in files.sorted() where file.hasSuffix(".json") {
                do { packs.append(try decoder.decode(RegionPack.self, from: Data(contentsOf: regionsDir.appendingPathComponent(file)))) }
                catch { issues.append(ContentLoadIssue(path: "regions/\(file)", message: "\(error)")) }
            }
        }

        return ContentLibrary(root: root, manifest: manifest, localeManifest: localeManifest, tables: tables,
                              sources: sources, regionPacks: packs, issues: issues)
    }

    private struct SourceList: Decodable { var sources: [SourceRef] }
}
