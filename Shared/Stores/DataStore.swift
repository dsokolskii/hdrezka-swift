import Foundation
import CloudKit

protocol DataStore: Actor {
    
    associatedtype D
    
    /// Saves object to store.
    /// - Parameter current: Object to save.
    func save(_ current: D) async throws

    /// Loads object from store.
    /// - Returns: Saved object or nil.
    func load() async throws -> D?
}

actor CloudKitDataStore<T: Codable & Equatable>: DataStore {
    
    /// CloudKit container for data operations.
    private let container: CKContainer?

    /// CloudKit database for record storage.
    private let database: CKDatabase?

    /// Type name for CKRecord storage.
    private let recordType: String

    /// Identifier for the CloudKit record.
    private let recordID: CKRecord.ID

    /// Local fallback storage when CloudKit is not configured.
    private let fallbackURL: URL

    /**
     Initializes data store for CloudKit operations.
     - Parameters:
       - containerIdentifier: Container identifier for CloudKit.
       - databaseScope: Database scope for CloudKit (default .private).
       - recordType: Type name for CKRecord.
       - recordName: Unique record name.
     */
    init(containerIdentifier: String = ConstantsApi.iCloudKey,
         databaseScope: CKDatabase.Scope = .private,
         recordType: String,
         recordName: String) {
        self.recordType = recordType
        self.recordID = CKRecord.ID(recordName: recordName)

        let fallbackDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fallbackURL = fallbackDirectory
            .appendingPathComponent("rezka-player", isDirectory: true)
            .appendingPathComponent("\(recordType)-\(recordName).json", isDirectory: false)

        if containerIdentifier.isEmpty {
            self.container = nil
            self.database = nil
        } else {
            let container = CKContainer(identifier: containerIdentifier)
            self.container = container
            self.database = container.database(with: databaseScope)
        }
    }

    /**
     Saves object to CloudKit record.
     - Parameter current: Object to save.
     */
    func save(_ current: T) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(current)

        guard let database else {
            try saveLocally(data)
            return
        }

        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["data"] = data
        
        do {
            try await database.deleteRecord(withID: recordID)
            _ = try await database.save(record)
        } catch {
            print(error.localizedDescription)
            try saveLocally(data)
        }
    }

    /**
     Loads object from CloudKit record.
     - Returns: Decoded object or nil if absent.
     */
    func load() async throws -> T? {
        guard let database else {
            return try loadLocally()
        }
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["data"] as? Data else {
                return nil
            }
            let decoder = JSONDecoder()
            let current = try decoder.decode(T.self, from: data)
            return current
        } catch {
            return try loadLocally()
        }
    }

    private func saveLocally(_ data: Data) throws {
        let directory = fallbackURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fallbackURL, options: .atomic)
    }

    private func loadLocally() throws -> T? {
        guard FileManager.default.fileExists(atPath: fallbackURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fallbackURL)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
