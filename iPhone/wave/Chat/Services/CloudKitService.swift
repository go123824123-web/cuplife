import Foundation
import CloudKit

final class CloudKitService: Sendable {
    static let shared = CloudKitService()

    private let container: CKContainer
    private let database: CKDatabase

    private init() {
        container = CKContainer.default()
        database = container.privateCloudDatabase
    }

    // MARK: - Account

    func checkAccountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Fetch

    func fetchMessages() async throws -> [Message] {
        let query = CKQuery(
            recordType: Message.recordType,
            predicate: NSPredicate(value: true)
        )

        do {
            let (results, _) = try await database.records(
                matching: query,
                resultsLimit: 200
            )

            return results.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return Message.from(record: record)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet (first launch, no messages sent)
            return []
        }
    }

    // MARK: - Send

    func sendMessage(text: String, role: Message.Role, modelID: String? = nil) async throws -> Message {
        let message = Message(
            id: UUID().uuidString,
            text: text,
            role: role,
            timestamp: Date(),
            senderDevice: Message.currentDeviceName,
            modelID: modelID
        )

        let record = message.toCKRecord()
        let savedRecord = try await database.save(record)
        return Message.from(record: savedRecord)
    }

    // MARK: - Delete

    func deleteMessage(id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await database.deleteRecord(withID: recordID)
    }

    // MARK: - Delete All

    func deleteAllMessages() async throws {
        let messages = try await fetchMessages()
        let recordIDs = messages.map { CKRecord.ID(recordName: $0.id) }

        guard !recordIDs.isEmpty else { return }

        let operation = CKModifyRecordsOperation(
            recordsToSave: nil,
            recordIDsToDelete: recordIDs
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    // MARK: - Subscription

    func subscribeToChanges() async throws {
        let subscriptionID = "message-changes"

        let existing = try? await database.subscription(for: subscriptionID)
        if existing != nil { return }

        let subscription = CKQuerySubscription(
            recordType: Message.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        _ = try await database.save(subscription)
    }
}
