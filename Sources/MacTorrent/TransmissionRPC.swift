import Foundation

/// Transmission RPC client for communicating with the daemon.
actor TransmissionRPC {
    private let baseURL: URL
    private var sessionId: String?
    
    init(port: Int = 9091) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/transmission/rpc")!
    }
    
    // MARK: - Torrent Operations
    
    /// Add a torrent from a magnet link or URL.
    func addTorrent(url: String) async throws -> Int {
        let result: AddTorrentResponse = try await call(
            method: "torrent-add",
            arguments: ["filename": url]
        )
        return result.torrentAdded?.id ?? result.torrentDuplicate?.id ?? 0
    }
    
    /// Add a torrent from .torrent file data.
    func addTorrent(data: Data) async throws -> Int {
        let metainfo = data.base64EncodedString()
        let result: AddTorrentResponse = try await call(
            method: "torrent-add",
            arguments: ["metainfo": metainfo]
        )
        return result.torrentAdded?.id ?? result.torrentDuplicate?.id ?? 0
    }
    
    /// Get status of all torrents.
    func getTorrents() async throws -> [TorrentInfo] {
        let result: TorrentsResponse = try await call(
            method: "torrent-get",
            arguments: [
                "fields": [
                    "id", "name", "status", "percentDone", "totalSize",
                    "downloadedEver", "uploadedEver", "rateDownload", "rateUpload",
                    "eta", "peersConnected", "peersGettingFromUs", "peersSendingToUs",
                    "error", "errorString", "addedDate", "isFinished", "hashString",
                    "uploadRatio", "downloadDir", "creator", "dateCreated",
                    "pieceCount", "pieceSize", "leftUntilDone", "sizeWhenDone",
                    "trackerStats", "peers", "files", "fileStats"
                ]
            ]
        )
        return result.torrents
    }
    
    /// Get detailed info for a single torrent.
    func getTorrentDetails(id: Int) async throws -> TorrentInfo? {
        let result: TorrentsResponse = try await call(
            method: "torrent-get",
            arguments: [
                "ids": [id],
                "fields": [
                    "id", "name", "status", "percentDone", "totalSize",
                    "downloadedEver", "uploadedEver", "rateDownload", "rateUpload",
                    "eta", "peersConnected", "peersGettingFromUs", "peersSendingToUs",
                    "error", "errorString", "addedDate", "isFinished", "hashString",
                    "uploadRatio", "downloadDir", "creator", "dateCreated",
                    "pieceCount", "pieceSize", "leftUntilDone", "sizeWhenDone",
                    "trackerStats", "peers", "files", "fileStats"
                ]
            ]
        )
        return result.torrents.first
    }
    
    /// Start (resume) torrents.
    func startTorrents(ids: [Int]) async throws {
        let _: EmptyResponse = try await call(
            method: "torrent-start",
            arguments: ["ids": ids]
        )
    }
    
    /// Stop (pause) torrents.
    func stopTorrents(ids: [Int]) async throws {
        let _: EmptyResponse = try await call(
            method: "torrent-stop",
            arguments: ["ids": ids]
        )
    }
    
    /// Remove torrents.
    func removeTorrents(ids: [Int], deleteData: Bool = false) async throws {
        let _: EmptyResponse = try await call(
            method: "torrent-remove",
            arguments: [
                "ids": ids,
                "delete-local-data": deleteData
            ]
        )
    }
    
    // MARK: - Session
    
    /// Get session statistics.
    func getSessionStats() async throws -> SessionStats {
        try await call(method: "session-stats", arguments: [:])
    }
    
    // MARK: - RPC Implementation
    
    private func call<T: Decodable>(method: String, arguments: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "X-Transmission-Session-Id")
        }
        
        let body: [String: Any] = [
            "method": method,
            "arguments": arguments
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            // Handle 409 - need session ID
            if http.statusCode == 409 {
                if let newSessionId = http.value(forHTTPHeaderField: "X-Transmission-Session-Id") {
                    self.sessionId = newSessionId
                    return try await call(method: method, arguments: arguments)
                }
            }
            
            guard http.statusCode == 200 else {
                throw RPCError.httpError(http.statusCode)
            }
        }
        
        let wrapper = try JSONDecoder().decode(RPCResponse<T>.self, from: data)
        
        guard wrapper.result == "success" else {
            throw RPCError.rpcError(wrapper.result)
        }
        
        guard let result = wrapper.arguments else {
            throw RPCError.noArguments
        }
        
        return result
    }
}

// MARK: - Response Types

struct RPCResponse<T: Decodable>: Decodable {
    let result: String
    let arguments: T?
}

struct AddTorrentResponse: Decodable {
    let torrentAdded: TorrentRef?
    let torrentDuplicate: TorrentRef?
    
    struct TorrentRef: Decodable {
        let id: Int
        let name: String
        let hashString: String
    }
    
    private enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
        case torrentDuplicate = "torrent-duplicate"
    }
}

struct TorrentsResponse: Decodable {
    let torrents: [TorrentInfo]
}

struct TorrentInfo: Decodable, Identifiable {
    let id: Int
    let name: String
    let status: Int
    let percentDone: Double
    let totalSize: Int64
    let downloadedEver: Int64
    let uploadedEver: Int64
    let rateDownload: Int64
    let rateUpload: Int64
    let eta: Int
    let peersConnected: Int
    let peersGettingFromUs: Int?
    let peersSendingToUs: Int?
    let error: Int
    let errorString: String
    let addedDate: Int
    let isFinished: Bool
    let hashString: String
    let uploadRatio: Double?
    let downloadDir: String?
    let creator: String?
    let dateCreated: Int?
    let pieceCount: Int?
    let pieceSize: Int64?
    let leftUntilDone: Int64?
    let sizeWhenDone: Int64?
    let trackerStats: [TrackerStat]?
    let peers: [PeerInfo]?
    let files: [FileInfo]?
    let fileStats: [FileStat]?
    
    var statusText: String {
        switch status {
        case 0: return "Paused"
        case 1: return "Queued"
        case 2: return "Verifying"
        case 3: return "Queued"
        case 4: return "Downloading"
        case 5: return "Queued"
        case 6: return "Seeding"
        default: return "Unknown"
        }
    }
    
    var isDownloading: Bool { status == 4 }
    var isPaused: Bool { status == 0 }
    var isSeeding: Bool { status == 6 }
    
    var ratio: Double { uploadRatio ?? 0 }
    var seeders: Int { peersSendingToUs ?? 0 }
    var leechers: Int { peersGettingFromUs ?? 0 }
}

struct TrackerStat: Decodable, Identifiable, Equatable, Hashable {
    let id: Int
    let host: String
    let announce: String
    let lastAnnounceSucceeded: Bool
    let lastAnnounceTime: Int
    let nextAnnounceTime: Int
    let seederCount: Int
    let leecherCount: Int
    let lastScrapeSucceeded: Bool?
}

struct PeerInfo: Decodable, Identifiable, Equatable, Hashable {
    var id: String { "\(address):\(port)" }
    let address: String
    let port: Int
    let clientName: String
    let progress: Double
    let rateToClient: Int64
    let rateToPeer: Int64
    let flagStr: String
    let isEncrypted: Bool
    let isUTP: Bool
}

struct FileInfo: Decodable, Equatable, Hashable {
    let name: String
    let length: Int64
    let bytesCompleted: Int64
}

struct FileStat: Decodable, Equatable, Hashable {
    let wanted: Bool
    let priority: Int
}


struct SessionStats: Decodable {
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let torrentCount: Int
    let activeTorrentCount: Int
    let pausedTorrentCount: Int
}

struct EmptyResponse: Decodable {}

enum RPCError: LocalizedError {
    case httpError(Int)
    case rpcError(String)
    case noArguments
    
    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error: \(code)"
        case .rpcError(let msg): return "RPC error: \(msg)"
        case .noArguments: return "No response arguments"
        }
    }
}
