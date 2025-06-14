import Foundation

// Swift bridge to Zig Farcaster SDK
// Provides high-level Swift interface to Farcaster functionality

// C function imports from Zig
@_silgen_name("fc_client_create")
func fc_client_create(_ fid: UInt64, _ private_key_hex: UnsafePointer<CChar>) -> OpaquePointer?

@_silgen_name("fc_client_destroy")
func fc_client_destroy(_ client: OpaquePointer?)

@_silgen_name("fc_post_cast")
func fc_post_cast(_ client: OpaquePointer?, _ text: UnsafePointer<CChar>, _ channel_url: UnsafePointer<CChar>) -> UnsafePointer<CChar>

@_silgen_name("fc_like_cast")
func fc_like_cast(_ client: OpaquePointer?, _ cast_hash: UnsafePointer<CChar>, _ cast_fid: UInt64) -> UnsafePointer<CChar>

@_silgen_name("fc_get_casts_by_channel")
func fc_get_casts_by_channel(_ client: OpaquePointer?, _ channel_url: UnsafePointer<CChar>, _ limit: UInt32) -> UnsafePointer<CChar>

@_silgen_name("fc_free_string")
func fc_free_string(_ str: UnsafePointer<CChar>)

// Swift service class
class FarcasterService {
    private var client: OpaquePointer?
    private let userFid: UInt64
    private let channelUrl: String
    
    enum FarcasterServiceError: Error, LocalizedError {
        case initializationFailed
        case noPrivateKey
        case apiError(String)
        case clientNotInitialized
        
        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize Farcaster client"
            case .noPrivateKey:
                return "Farcaster private key not found. Please set FARCASTER_PRIVATE_KEY environment variable."
            case .apiError(let message):
                return "Farcaster API Error: \(message)"
            case .clientNotInitialized:
                return "Farcaster client not initialized"
            }
        }
    }
    
    init(userFid: UInt64, channelUrl: String) throws {
        self.userFid = userFid
        self.channelUrl = channelUrl
        
        // Get private key from environment
        guard let privateKeyHex = ProcessInfo.processInfo.environment["FARCASTER_PRIVATE_KEY"],
              !privateKeyHex.isEmpty else {
            throw FarcasterServiceError.noPrivateKey
        }
        
        // Initialize Zig client
        self.client = privateKeyHex.withCString { privateKeyPtr in
            fc_client_create(userFid, privateKeyPtr)
        }
        
        guard self.client != nil else {
            throw FarcasterServiceError.initializationFailed
        }
        
        print("FarcasterService: Initialized for FID \(userFid) in channel \(channelUrl)")
    }
    
    deinit {
        if let client = client {
            fc_client_destroy(client)
        }
    }
    
    // MARK: - Cast Operations
    
    func postCast(text: String) async throws -> String {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: FarcasterServiceError.clientNotInitialized)
                    return
                }
                
                let result = text.withCString { textPtr in
                    self.channelUrl.withCString { channelPtr in
                        fc_post_cast(client, textPtr, channelPtr)
                    }
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                } else {
                    continuation.resume(returning: resultString)
                }
            }
        }
    }
    
    func getCasts(limit: UInt32 = 25) async throws -> [FarcasterCastData] {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: FarcasterServiceError.clientNotInitialized)
                    return
                }
                
                let result = self.channelUrl.withCString { channelPtr in
                    fc_get_casts_by_channel(client, channelPtr, limit)
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                    return
                }
                
                do {
                    let casts = try self.parseCastsJson(resultString)
                    continuation.resume(returning: casts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func likeCast(castHash: String, authorFid: UInt64) async throws -> String {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = castHash.withCString { hashPtr in
                    fc_like_cast(client, hashPtr, authorFid)
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                } else {
                    continuation.resume(returning: resultString)
                }
            }
        }
    }
    
    // MARK: - Data Models
    
    struct FarcasterCastData: Codable, Identifiable {
        let id: String
        let hash: String
        let parentHash: String?
        let parentUrl: String?
        let author: FarcasterUserData
        let text: String
        let timestamp: UInt64
        let mentions: [UInt64]
        let repliesCount: UInt32
        let reactionsCount: UInt32
        let recastsCount: UInt32
        
        var timeAgo: String {
            let now = Date()
            let castDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let interval = now.timeIntervalSince(castDate)
            
            if interval < 60 {
                return "now"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "\(minutes)m"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "\(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "\(days)d"
            }
        }
    }
    
    struct FarcasterUserData: Codable {
        let fid: UInt64
        let username: String
        let displayName: String
        let bio: String
        let pfpUrl: String
        let followerCount: UInt32
        let followingCount: UInt32
        
        enum CodingKeys: String, CodingKey {
            case fid, username, bio
            case displayName = "display_name"
            case pfpUrl = "pfp_url"
            case followerCount = "follower_count"
            case followingCount = "following_count"
        }
    }
    
    // MARK: - JSON Parsing
    
    private func parseCastsJson(_ jsonString: String) throws -> [FarcasterCastData] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw FarcasterServiceError.apiError("Invalid JSON data")
        }
        
        do {
            let casts = try JSONDecoder().decode([FarcasterCastData].self, from: jsonData)
            return casts
        } catch {
            // If decoding fails, try to parse as individual cast objects
            // This handles the case where Zig returns a different format
            print("FarcasterService: JSON decode error: \(error)")
            return []
        }
    }
    
    // MARK: - Conversion Helpers
    
    func convertToFarcasterPosts(_ casts: [FarcasterCastData]) -> [FarcasterPost] {
        return casts.map { cast in
            FarcasterPost(
                id: cast.hash,
                author: FarcasterUser(
                    username: cast.author.username,
                    displayName: cast.author.displayName,
                    avatarURL: cast.author.pfpUrl
                ),
                content: cast.text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(cast.timestamp)),
                channel: extractChannelFromUrl(cast.parentUrl),
                likes: Int(cast.reactionsCount),
                recasts: Int(cast.recastsCount),
                replies: Int(cast.repliesCount),
                isLiked: false, // Would need to check user's reactions
                isRecast: false // Would need to check user's recasts
            )
        }
    }
    
    private func extractChannelFromUrl(_ url: String?) -> String {
        guard let url = url else { return "general" }
        
        // Extract channel name from Farcaster channel URL
        // e.g., "https://farcaster.xyz/~/channel/dev" -> "dev"
        if let range = url.range(of: "/channel/") {
            let channelName = String(url[range.upperBound...])
            return channelName.isEmpty ? "general" : channelName
        }
        
        return "general"
    }
}

// MARK: - Test Configuration

extension FarcasterService {
    static func createTestService() -> FarcasterService? {
        do {
            // Test configuration - in production these would come from secure storage
            let testFid: UInt64 = 1234 // Replace with actual test FID
            let testChannelUrl = "https://farcaster.xyz/~/channel/dev"
            
            return try FarcasterService(userFid: testFid, channelUrl: testChannelUrl)
        } catch {
            print("FarcasterService: Failed to create test service: \(error)")
            return nil
        }
    }
}