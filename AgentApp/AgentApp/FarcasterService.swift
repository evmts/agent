import Foundation

// Stub Farcaster service - not connecting to backend
class FarcasterService {
    static func createTestService() -> FarcasterService? {
        return nil
    }

    func getCasts(limit: Int) async throws -> [Any] {
        return []
    }

    func postCast(text: String) async throws -> String {
        throw FarcasterError.notConfigured
    }

    func likeCast(castHash: String, authorFid: UInt64) async throws -> String {
        throw FarcasterError.notConfigured
    }

    func convertToFarcasterPosts(_ casts: [Any]) -> [FarcasterPost] {
        return []
    }
}

enum FarcasterError: Error {
    case notConfigured
}
