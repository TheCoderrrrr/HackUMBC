import Foundation

/// Saved presets exported by `backend/scripts/export_demo.py` (FRONTEND.md §7).
enum DemoPreset: String, Codable, CaseIterable, Sendable {
    case original
    case retirePlusTwo = "retire-plus-two"
    case contributionPlusOne = "contribution-plus-one"
}

/// `manifest.json` in the offline bundle.
struct DemoManifest: Codable, Sendable {
    struct Entry: Codable, Sendable {
        enum Kind: String, Codable, Sendable { case standard, demonstration }
        var profileID: String
        var presetID: DemoPreset
        var filename: String
        var profileHash: String
        var inputHash: String
        var kind: Kind
        var baseProfileID: String?

        enum CodingKeys: String, CodingKey {
            case filename, kind
            case profileID = "profile_id"
            case presetID = "preset_id"
            case profileHash = "profile_hash"
            case inputHash = "input_hash"
            case baseProfileID = "base_profile_id"
        }
    }

    var schemaVersion: String
    var modelVersion: String
    var policyVersion: String
    var profilesFile: String
    var defaultProfileIDs: [String]
    var artifacts: [Entry]

    enum CodingKeys: String, CodingKey {
        case artifacts
        case schemaVersion = "schema_version"
        case modelVersion = "model_version"
        case policyVersion = "policy_version"
        case profilesFile = "profiles_file"
        case defaultProfileIDs = "default_profile_ids"
    }
}

/// One saved evaluation file, e.g. `morgan-original.json`.
struct DemoArtifact: Codable, Sendable {
    var profileID: String
    var profileHash: String
    var schemaVersion: String
    var modelVersion: String
    var policyVersion: String
    var scenario: API.Scenario?
    var evaluation: API.Evaluation

    enum CodingKeys: String, CodingKey {
        case scenario, evaluation
        case profileID = "profile_id"
        case profileHash = "profile_hash"
        case schemaVersion = "schema_version"
        case modelVersion = "model_version"
        case policyVersion = "policy_version"
    }
}

enum DemoRepositoryError: Error, Equatable {
    /// `Resources/Demo/` has not been added to the app yet.
    case bundleMissing
    /// A file is missing, unreadable, or does not match the contract.
    case corrupt(file: String)
    /// The bundle was exported for a different schema version.
    case incompatibleVersion(found: String)
    /// No saved artifact exists for this profile and preset.
    case notFound(profileID: String, preset: DemoPreset)
}

/// Loads bundled profiles and exact saved artifacts. No interpolation, rules, or calculations.
final class DemoRepository {
    private let bundle: Bundle
    private var cachedManifest: DemoManifest?
    private var cachedProfiles: [String: API.FinancialProfile]?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isAvailable: Bool { url(for: "manifest.json") != nil }

    func manifest() throws -> DemoManifest {
        if let cachedManifest { return cachedManifest }
        let manifest: DemoManifest = try decode("manifest.json")
        guard manifest.schemaVersion == API.schemaVersion else {
            throw DemoRepositoryError.incompatibleVersion(found: manifest.schemaVersion)
        }
        cachedManifest = manifest
        return manifest
    }

    /// Every bundled profile, including the `morgan-cash-security` demonstration variant.
    func profiles() throws -> [String: API.FinancialProfile] {
        if let cachedProfiles { return cachedProfiles }
        let file: API.DemoProfiles = try decode(try manifest().profilesFile)
        let byID = Dictionary(file.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cachedProfiles = byID
        return byID
    }

    /// Profiles shown in the normal customer picker, in manifest order.
    func defaultProfiles() throws -> [API.FinancialProfile] {
        let all = try profiles()
        return try manifest().defaultProfileIDs.compactMap { all[$0] }
    }

    func artifact(profileID: String, preset: DemoPreset = .original) throws -> DemoArtifact {
        let manifest = try manifest()
        guard let entry = manifest.artifacts.first(where: { $0.profileID == profileID && $0.presetID == preset }) else {
            throw DemoRepositoryError.notFound(profileID: profileID, preset: preset)
        }
        let artifact: DemoArtifact = try decode(entry.filename)
        guard artifact.schemaVersion == manifest.schemaVersion,
              artifact.evaluation.schemaVersion == manifest.schemaVersion else {
            throw DemoRepositoryError.incompatibleVersion(found: artifact.schemaVersion)
        }
        guard artifact.profileID == profileID, artifact.evaluation.profileID == profileID,
              artifact.profileHash == entry.profileHash, artifact.evaluation.inputHash == entry.inputHash else {
            throw DemoRepositoryError.corrupt(file: entry.filename)
        }
        return artifact
    }

    private func decode<T: Decodable>(_ filename: String) throws -> T {
        guard let url = url(for: filename) else {
            throw filename == "manifest.json" ? DemoRepositoryError.bundleMissing : DemoRepositoryError.corrupt(file: filename)
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw DemoRepositoryError.corrupt(file: filename)
        }
    }

    /// Xcode's synchronized folders may copy `Resources/Demo/*` to the bundle root.
    private func url(for filename: String) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        for subdirectory in ["Resources/Demo", "Demo", nil] as [String?] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
}
