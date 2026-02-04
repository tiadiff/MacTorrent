import Foundation
import os

/// Manages the transmission-daemon process lifecycle.
@MainActor
class DaemonManager: ObservableObject {
    static let shared = DaemonManager()
    
    @Published var isRunning = false
    @Published var lastError: Error?
    
    private var daemonProcess: Process?
    private let logger = Logger(subsystem: "com.example.MacTorrent", category: "Daemon")
    
    // Configuration
    let rpcPort: Int = 9091
    let peerPort: Int = 51413
    var configDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MacTorrent/transmission")
    }
    var downloadDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
    
    /// Path to the daemon binary (bundled in app or system)
    private var daemonPath: String {
        // First try bundled version inside app
        if let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "transmission-daemon") {
            return bundlePath
        }
        // Try Helpers folder
        if let resourcePath = Bundle.main.resourcePath {
            let helpersPath = (resourcePath as NSString).deletingLastPathComponent + "/Helpers/transmission-daemon"
            if FileManager.default.fileExists(atPath: helpersPath) {
                return helpersPath
            }
        }
        // Fallback to system path
        return "/usr/local/bin/transmission-daemon"
    }
    
    private init() {}
    
    /// Start the daemon, reusing existing one if available.
    func start() async throws {
        print("DEBUG: DaemonManager.start() called")
        
        // Check if a daemon is already running (from previous session or manually)
        if await checkExistingDaemon() {
            print("DEBUG: Found existing daemon, reusing it")
            isRunning = true
            return
        }
        
        guard !isRunning else {
            print("DEBUG: Daemon already marked as running")
            return
        }
        
        // Create config directory if needed
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Create settings.json if needed
        let settingsPath = configDir.appendingPathComponent("settings.json")
        if !FileManager.default.fileExists(atPath: settingsPath.path) {
            try createDefaultSettings(at: settingsPath)
        }
        
        // Start daemon
        let process = Process()
        process.executableURL = URL(fileURLWithPath: daemonPath)
        process.arguments = [
            "--foreground",
            "--config-dir", configDir.path,
            "--port", String(peerPort),
            "--download-dir", downloadDir.path,
            "--watch-dir", downloadDir.path,
            "--log-level=info"
        ]
        
        // Capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.logger.debug("daemon: \(output)")
            }
        }
        
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.logger.info("Daemon terminated")
            }
        }
        
        do {
            try process.run()
            self.daemonProcess = process
            self.isRunning = true
            print("DEBUG: Daemon process started, PID: \(process.processIdentifier)")
            
            // Wait for RPC to be ready
            try await waitForRPC()
            print("DEBUG: RPC is ready!")
        } catch {
            print("DEBUG: Failed to start daemon: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Check if an existing daemon is already running and responding.
    private func checkExistingDaemon() async -> Bool {
        let url = URL(string: "http://localhost:\(rpcPort)/transmission/rpc")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 409 {
                print("DEBUG: Existing daemon found and responding")
                return true
            }
        } catch {
            print("DEBUG: No existing daemon found: \(error.localizedDescription)")
        }
        return false
    }
    
    /// Stop the daemon gracefully.
    func stop() {
        guard let process = daemonProcess, isRunning else { return }
        
        logger.info("Stopping daemon...")
        process.interrupt() // SIGINT for graceful shutdown
        daemonProcess = nil
        isRunning = false
    }
    
    /// Kill any existing daemon processes.
    private func killExistingDaemon() async {
        print("DEBUG: Killing any existing transmission-daemon processes...")
        
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-9", "transmission-daemon"]
        
        do {
            try killProcess.run()
            killProcess.waitUntilExit()
            // Wait a moment for process to fully die
            try await Task.sleep(for: .milliseconds(500))
            print("DEBUG: Killed existing daemon (if any)")
        } catch {
            print("DEBUG: pkill failed (no daemon was running): \(error.localizedDescription)")
        }
    }
    
    /// Wait for RPC to become available.
    private func waitForRPC(timeout: TimeInterval = 15) async throws {
        print("DEBUG: Waiting for RPC to become available...")
        
        // Give daemon a moment to start up
        try await Task.sleep(for: .seconds(1))
        
        let deadline = Date().addingTimeInterval(timeout)
        let url = URL(string: "http://localhost:\(rpcPort)/transmission/rpc")!
        var attempts = 0
        
        while Date() < deadline {
            attempts += 1
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 2
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    print("DEBUG: RPC response code: \(http.statusCode)")
                    if http.statusCode == 409 {
                        // 409 means RPC is ready (needs session-id)
                        print("DEBUG: RPC ready after \(attempts) attempts")
                        return
                    }
                }
            } catch {
                print("DEBUG: RPC attempt \(attempts) failed: \(error.localizedDescription)")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        
        print("DEBUG: RPC timeout after \(attempts) attempts")
        throw DaemonError.rpcNotReady
    }
    
    /// Create default settings.json
    private func createDefaultSettings(at path: URL) throws {
        let settings: [String: Any] = [
            "rpc-enabled": true,
            "rpc-port": rpcPort,
            "rpc-whitelist-enabled": false,
            "rpc-authentication-required": false,
            "download-dir": downloadDir.path,
            "port-forwarding-enabled": true, // UPnP!
            "dht-enabled": true,
            "pex-enabled": true,
            "lpd-enabled": true,
            "utp-enabled": true,
            "peer-port": peerPort,
            "peer-port-random-on-start": false,
            "encryption": 1, // Prefer encrypted
            "speed-limit-down-enabled": false,
            "speed-limit-up-enabled": false
        ]
        
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: path)
        logger.info("Created default settings at \(path.path)")
    }
}

enum DaemonError: LocalizedError {
    case rpcNotReady
    case notRunning
    
    var errorDescription: String? {
        switch self {
        case .rpcNotReady: return "Daemon RPC not responding"
        case .notRunning: return "Daemon is not running"
        }
    }
}
