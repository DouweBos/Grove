// Domain/PlistStore.swift
// Grove
//
// Generic plist read/write utility for persisting Codable types
// to ~/Library/Application Support/Grove/.

import Foundation
import os

// MARK: - PlistStore

/// Reads and writes `Codable` values as XML property lists in the
/// application support directory.
enum PlistStore {

    /// The directory where Grove stores its plist files.
    static let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Grove")
    }()

    /// Loads a `Decodable` value from a plist file.
    ///
    /// - Returns: The decoded value, or `nil` if the file does not exist.
    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = appSupportURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(type, from: data)
        } catch {
            Logger.repositoryManager.error("PlistStore: failed to load \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Saves an `Encodable` value to a plist file using an atomic write.
    ///
    /// Creates the application support directory if it does not exist.
    static func save<T: Encodable>(_ value: T, to filename: String) {
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(value)
            let url = appSupportURL.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.repositoryManager.error("PlistStore: failed to save \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
