import Foundation
import SwiftUI
import Combine

/// ViewModel for managing torrents via Transmission daemon.
@MainActor
@Observable
class TorrentManager {
    var torrents: [TorrentDisplayItem] = []
    var isLoading = false
    var errorMessage: String?
    var showError = false
    var daemonStatus: DaemonStatus = .starting
    
    private let rpc = TransmissionRPC()
    private var pollTask: Task<Void, Never>?
    
    init() {
        // Start daemon and polling when initialized
        Task { @MainActor in
            await startDaemonAndPolling()
        }
    }
    
    /// Start the daemon and begin polling for updates.
    private func startDaemonAndPolling() async {
        print("DEBUG: TorrentManager - startDaemonAndPolling")
        do {
            try await DaemonManager.shared.start()
            print("DEBUG: Daemon started successfully, beginning polling")
            daemonStatus = .running
            startPolling()
        } catch {
            print("DEBUG: Daemon start failed: \(error)")
            daemonStatus = .stopped
            errorMessage = "Failed to start daemon: \(error.localizedDescription)"
            showError = true
        }
    }
    
    /// Start periodic polling for torrent status.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.updateTorrents()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    /// Fetch latest torrent status from daemon.
    func updateTorrents() async {
        do {
            let infos = try await rpc.getTorrents()
            let newTorrents = infos.map { TorrentDisplayItem(from: $0) }
            
            // Update if different (default Equatable now checks all fields)
            if torrents != newTorrents {
                torrents = newTorrents
            }
        } catch {
            print("DEBUG: Poll error: \(error)")
        }
    }
    
    /// Add a torrent from a URL (magnet link or .torrent file URL).
    func addTorrent(from url: URL) async {
        print("DEBUG: addTorrent called with URL: \(url)")
        do {
            if url.isFileURL {
                print("DEBUG: Loading .torrent file data")
                let data = try Data(contentsOf: url)
                let id = try await rpc.addTorrent(data: data)
                print("DEBUG: Added torrent file, ID: \(id)")
            } else {
                print("DEBUG: Adding magnet/URL: \(url.absoluteString)")
                let id = try await rpc.addTorrent(url: url.absoluteString)
                print("DEBUG: Added torrent, ID: \(id)")
            }
            await updateTorrents()
        } catch {
            print("DEBUG: Failed to add torrent: \(error)")
            errorMessage = "Failed to add torrent: \(error.localizedDescription)"
            showError = true
        }
    }
    
    /// Pause a torrent.
    func pauseTorrent(_ item: TorrentDisplayItem) async {
        do {
            try await rpc.stopTorrents(ids: [item.id])
            await updateTorrents()
        } catch {
            errorMessage = "Failed to pause: \(error.localizedDescription)"
        }
    }
    
    /// Resume a torrent.
    func resumeTorrent(_ item: TorrentDisplayItem) async {
        do {
            try await rpc.startTorrents(ids: [item.id])
            await updateTorrents()
        } catch {
            errorMessage = "Failed to resume: \(error.localizedDescription)"
        }
    }
    
    /// Remove a torrent.
    func removeTorrent(_ item: TorrentDisplayItem, deleteData: Bool = false) async {
        do {
            try await rpc.removeTorrents(ids: [item.id], deleteData: deleteData)
            await updateTorrents()
        } catch {
            errorMessage = "Failed to remove: \(error.localizedDescription)"
        }
    }
    
    /// Pause all torrents.
    func pauseAll() async {
        let ids = torrents.map(\.id)
        guard !ids.isEmpty else { return }
        try? await rpc.stopTorrents(ids: ids)
        await updateTorrents()
    }
    
    /// Resume all torrents.
    func resumeAll() async {
        let ids = torrents.map(\.id)
        guard !ids.isEmpty else { return }
        try? await rpc.startTorrents(ids: ids)
        await updateTorrents()
    }
}

/// UI model for displaying a torrent.
struct TorrentDisplayItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let progress: Double
    let state: TorrentState
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let downloaded: Int64
    let uploaded: Int64
    let totalSize: Int64
    let peers: Int
    let eta: Int
    let hash: String
    let ratio: Double
    let downloadDir: String?
    let addedDate: Date
    let trackers: [TrackerStat]?
    let peers_list: [PeerInfo]?
    let files: [FileInfo]?
    
    init(from info: TorrentInfo) {
        self.id = info.id
        self.name = info.name.removingPercentEncoding ?? info.name
        self.progress = info.percentDone
        self.downloaded = info.downloadedEver
        self.uploaded = info.uploadedEver
        self.totalSize = info.totalSize
        self.downloadSpeed = info.rateDownload
        self.uploadSpeed = info.rateUpload
        self.peers = info.peersConnected
        self.eta = info.eta
        self.hash = info.hashString
        self.ratio = info.uploadRatio ?? 0
        self.downloadDir = info.downloadDir
        self.addedDate = Date(timeIntervalSince1970: TimeInterval(info.addedDate))
        self.trackers = info.trackerStats
        self.peers_list = info.peers
        self.files = info.files
        
        switch info.status {
        case 0: self.state = .paused
        case 1, 2: self.state = .verifying
        case 3, 4: self.state = .downloading
        case 5, 6: self.state = .seeding
        default: self.state = .paused
        }
    }
    
    var progressString: String {
        String(format: "%.1f%%", progress * 100)
    }
    
    var speedString: String {
        if downloadSpeed > 0 {
            return "↓ \(ByteCountFormatter.string(fromByteCount: downloadSpeed, countStyle: .file))/s"
        } else if uploadSpeed > 0 {
            return "↑ \(ByteCountFormatter.string(fromByteCount: uploadSpeed, countStyle: .file))/s"
        }
        return "—"
    }
    
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var etaString: String {
        guard eta > 0 else { return "—" }
        let hours = eta / 3600
        let minutes = (eta % 3600) / 60
        let seconds = eta % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
    
    var addedDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: addedDate)
    }
    
    // Let compiler synthesize Hashable/Equatable to ensure all fields are compared
    // ensuring SwiftUI detects changes in progress/speed.
}


enum TorrentState: String, CaseIterable {
    case paused = "Paused"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case verifying = "Verifying"
}

enum DaemonStatus {
    case starting
    case running
    case stopped
    case failed
}
