import Foundation
import CloudKit

struct Message: Identifiable, Equatable, Comparable {
    let id: String
    let text: String
    let role: Role
    let timestamp: Date
    let senderDevice: String
    let modelID: String?

    enum Role: String, Codable {
        case user
        case assistant
    }

    var isUser: Bool { role == .user }

    var isFromCurrentDevice: Bool {
        senderDevice == Self.currentDeviceName
    }

    static var currentDeviceName: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    static func < (lhs: Message, rhs: Message) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}

// MARK: - CloudKit Conversion

extension Message {
    static let recordType = "Message"

    static func from(record: CKRecord) -> Message {
        let roleString = record["role"] as? String ?? Role.user.rawValue
        return Message(
            id: record.recordID.recordName,
            text: record["text"] as? String ?? "",
            role: Role(rawValue: roleString) ?? .user,
            timestamp: record["timestamp"] as? Date ?? Date(),
            senderDevice: record["senderDevice"] as? String ?? "unknown",
            modelID: record["modelID"] as? String
        )
    }

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record["text"] = text as CKRecordValue
        record["role"] = role.rawValue as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        record["senderDevice"] = senderDevice as CKRecordValue
        if let modelID { record["modelID"] = modelID as CKRecordValue }
        return record
    }
}

// MARK: - Conversion to API Format

extension Message {
    func toChatCompletionMessage() -> ChatCompletionMessage {
        ChatCompletionMessage(role: role.rawValue, content: text)
    }
}
