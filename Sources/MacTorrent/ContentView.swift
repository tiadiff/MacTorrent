import SwiftUI

struct ContentView: View {
    @State private var torrentManager = TorrentManager()
    @State private var selectedTorrent: TorrentDisplayItem?
    @State private var showingRemoveAlert = false
    @State private var torrentToRemove: TorrentDisplayItem?
    @State private var searchText = ""

    var filteredTorrents: [TorrentDisplayItem] {
        if searchText.isEmpty {
            return torrentManager.torrents
        }
        return torrentManager.torrents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Deselect on bg tap
                        selectedTorrent = nil
                    }

                if filteredTorrents.isEmpty {
                    if torrentManager.torrents.isEmpty {
                        ContentUnavailableView(
                            "No Torrents",
                            systemImage: "arrow.down.circle",
                            description: Text("Click + to add a torrent")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredTorrents) { torrent in
                                TorrentCardView(
                                    torrent: torrent,
                                    isSelected: selectedTorrent?.id == torrent.id
                                )
                                .onTapGesture {
                                    selectedTorrent = torrent
                                }
                                .contextMenu {
                                    contextMenuItems(for: torrent)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 55) // Explicit padding instead of safeAreaInset
                        .padding(.bottom, 60)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatsBarView(manager: torrentManager)
            }
            // Title handled by window
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await addTestTorrent() }
                        } label: {
                            Label("Add Big Buck Bunny (Test)", systemImage: "hare")
                        }
                        Divider()
                        Button {
                            Task { await torrentManager.pauseAll() }
                        } label: {
                            Label("Pause All", systemImage: "pause.fill")
                        }
                        Button {
                            Task { await torrentManager.resumeAll() }
                        } label: {
                            Label("Resume All", systemImage: "play.fill")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    
                    // Daemon Status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(daemonStatusColor)
                            .frame(width: 8, height: 8)
                        Text(daemonStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: openTorrent) {
                        Label("Add Torrent", systemImage: "plus")
                    }
                }
            }
            .ignoresSafeArea(.all, edges: .top) // Allow flowing under toolbar, handled by padding
        }
        .frame(minWidth: 400, minHeight: 300)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .alert("Remove Torrent", isPresented: $showingRemoveAlert) {
            Button("Keep Files", role: .destructive) {
                if let torrent = torrentToRemove {
                    Task { await torrentManager.removeTorrent(torrent, deleteData: false) }
                    torrentToRemove = nil
                }
            }
            Button("Delete Files", role: .destructive) {
                if let torrent = torrentToRemove {
                    Task { await torrentManager.removeTorrent(torrent, deleteData: true) }
                    torrentToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {
                torrentToRemove = nil
            }
        } message: {
            Text("Remove '\(torrentToRemove?.name ?? "")'?")
        }
        .alert("Error", isPresented: $torrentManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(torrentManager.errorMessage ?? "Unknown error")
        }
    }
    
    @ViewBuilder
    private func contextMenuItems(for torrent: TorrentDisplayItem) -> some View {
        if torrent.state == .paused {
            Button {
                Task { await torrentManager.resumeTorrent(torrent) }
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
        } else {
            Button {
                Task { await torrentManager.pauseTorrent(torrent) }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            torrentToRemove = torrent
            showingRemoveAlert = true
        } label: {
            Label("Remove…", systemImage: "trash")
        }
    }
    
    // ... existing openTorrent/addTestTorrent/handleDrop methods remain same ...
    // Note: To be safe, I will include them to ensure contiguous block if needed,
    // but the diff tool allows matching parts. 
    // I will target specific blocks to minimize error.
    
    private func openTorrent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select .torrent files"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                Task { await torrentManager.addTorrent(from: url) }
            }
        }
    }
    
    private func addTestTorrent() async {
        let bbb = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337"
        if let url = URL(string: bbb) {
            await torrentManager.addTorrent(from: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        await torrentManager.addTorrent(from: url)
                    }
                }
            }
        }
        return true
    }

    private var daemonStatusColor: Color {
        switch torrentManager.daemonStatus {
        case .running: return .green
        case .starting: return .yellow
        case .stopped: return .gray
        case .failed: return .red
        }
    }
    
    private var daemonStatusText: String {
        switch torrentManager.daemonStatus {
        case .running: return "Connected"
        case .starting: return "Starting..."
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Stats Bar

struct StatsBarView: View {
    let manager: TorrentManager
    
    var totalDownload: Int64 {
        manager.torrents.reduce(0) { $0 + $1.downloadSpeed }
    }
    
    var totalUpload: Int64 {
        manager.torrents.reduce(0) { $0 + $1.uploadSpeed }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Label("\(manager.torrents.count)", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
                .font(.caption)
            
            Spacer()
            
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(totalDownload > 0 ? .blue : .secondary)
                    Text(formatSpeed(totalDownload))
                }
                
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(totalUpload > 0 ? .green : .secondary)
                    Text(formatSpeed(totalUpload))
                }
            }
            .font(.callout.monospacedDigit())
            .fontWeight(.bold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    func formatSpeed(_ bytes: Int64) -> String {
        if bytes == 0 { return "0" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }
}

// MARK: - Torrent Card (Juicy)

struct TorrentCardView: View {
    let torrent: TorrentDisplayItem
    let isSelected: Bool
    
    @State private var hover = false
    
    var body: some View {
        VStack(spacing: 6) { // Reduced spacing
            // Top Row: Name and State Icon
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(torrent.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        statusBadge
                        Text(torrent.sizeString)
                            .foregroundStyle(.secondary)
                        
                        if torrent.peers > 0 {
                             Text("• \(torrent.peers) peers")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 12))
                }
                
                Spacer()
                
                // Progress Circle for compact glance
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    Circle()
                        .trim(from: 0, to: torrent.progress)
                        .stroke(stateColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                }
            }
            
            // Middle: Progress Bar (Linear)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary.opacity(0.5))
                        .frame(height: 4) // Smaller bar
                    
                    Capsule()
                        .fill(LinearGradient(colors: [stateColor, stateColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * torrent.progress, height: 4)
                        .animation(.spring, value: torrent.progress)
                }
            }
            .frame(height: 4)
            
            // Bottom Row: Speeds and Peers
            HStack {
                if torrent.state == .downloading {
                    Label(torrent.speedString, systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                } else if torrent.state == .seeding {
                    Label(formatBytes(torrent.uploadSpeed), systemImage: "arrow.up")
                        .foregroundStyle(.green)
                } else {
                    Text(torrent.state.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(torrent.progressString)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
            
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .scaleEffect(hover ? 1.01 : 1.0)
        .animation(.snappy(duration: 0.15), value: hover)
        .onHover { isHovering in
            hover = isHovering
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        Text(torrent.state.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(stateColor.opacity(0.2))
            .foregroundStyle(stateColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
    
    private var stateColor: Color {
        switch torrent.state {
        case .downloading: return .blue
        case .seeding: return .green
        case .paused: return .orange
        case .verifying: return .yellow
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}



#Preview {
    ContentView()
}
