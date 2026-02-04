import Foundation
import NIOCore

/// Coordinates multiple trackers with tier support.
public actor TrackerManager {
    private let tiers: [[String]]
    private let group: EventLoopGroup
    private var lastResponse: AnnounceResponse?
    private var announceInterval: Int = 1800

    public init(tiers: [[String]], group: EventLoopGroup) {
        self.tiers = tiers
        self.group = group
    }

    /// Convenience: create from TorrentInfo.
    public init(info: TorrentInfo, group: EventLoopGroup) {
        var tiers = info.announceList
        if tiers.isEmpty, let url = info.announceURL {
            tiers = [[url]]
        }
        self.tiers = tiers
        self.group = group
    }

    /// Announce to all tracker tiers concurrently and aggregate peers.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        var allPeers: [(String, UInt16)] = []
        var maxInterval = 300
        var successCount = 0

        // Flatten all trackers for maximum concurrency during debug/initial phase
        let allTrackers = tiers.flatMap { $0 }
        
        await withTaskGroup(of: AnnounceResponse?.self) { group in
            for urlString in allTrackers {
                group.addTask {
                    do {
                        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                            let tracker = HTTPTracker(announceURL: urlString)
                            return try await tracker.announce(params: params)
                        } else if urlString.hasPrefix("udp://") {
                             guard let components = URLComponents(string: urlString),
                                   let host = components.host,
                                   let port = components.port else { return nil }
                             let tracker = UDPTracker(host: host, port: port, group: self.group)
                             return try await tracker.announce(params: params)
                        } else {
                            return nil
                        }
                    } catch {
                        print("DEBUG: Tracker \(urlString) failed: \(error)")
                        return nil
                    }
                }
            }
            
            for await response in group {
                if let response = response {
                    successCount += 1
                    allPeers.append(contentsOf: response.peers)
                    print("DEBUG: Tracker SUCCESS! Got \(response.peers.count) peers from one tracker (Total so far: \(allPeers.count))")
                    maxInterval = max(maxInterval, response.interval)
                }
            }
        }
        
        if successCount > 0 {
            print("DEBUG: Announce success. Got peers from \(successCount) trackers. Total peers: \(allPeers.count)")
            return AnnounceResponse(interval: maxInterval, seeders: 0, leechers: 0, peers: allPeers)
        } else {
            throw TrackerError.connectionFailed
        }
    }

    public func getInterval() -> Int {
        announceInterval
    }
}
