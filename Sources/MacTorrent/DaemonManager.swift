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
        
        // Check if a daemon is already running
        if await checkExistingDaemon() {
            print("DEBUG: Found existing daemon, reusing it")
            isRunning = true
            return
        }
        
        // If not responding, ensure we kill any zombie processes (as admin)
        await killExistingDaemon()
        
        // Create config directory if needed
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Create settings.json if needed
        let settingsPath = configDir.appendingPathComponent("settings.json")
        if !FileManager.default.fileExists(atPath: settingsPath.path) {
            try createDefaultSettings(at: settingsPath)
        }
        
        print("DEBUG: Requesting admin privileges to start daemon...")
        
        // Construct the command
        // Using a fixed log path for easier debugging
        let logPath = "/tmp/transmission-daemon.log"
        
        // Ensure log file exists and specific permissions are set if needed (optional)
        // But for now, we just overwrite.
        
        let cmdArgs = [
            "'\(daemonPath)'",
            "--foreground",
            "--config-dir '\(configDir.path)'",
            "--config-dir '\(configDir.path)'",
            "--peerport \(peerPort)", // -P / --peerport is for peers
            "--download-dir '\(downloadDir.path)'",
            "--watch-dir '\(downloadDir.path)'",
            "--log-level=info",
            "--rpc-bind-address 127.0.0.1",
            "--port \(rpcPort)", // -p / --port is for RPC
            "--allowed 127.0.0.1",
            "--no-auth",
            "--logfile '\(logPath)'" // Explicit format for native logging if supported, or via redirection below
        ]
        
        // We redirect both stdout and stderr to the log file
        let command = "\(cmdArgs.joined(separator: " ")) > '\(logPath)' 2>&1 & echo $!"
        
        print("DEBUG: Launching daemon with command: \(command)")
        
        let scriptSource = "do shell script \"\(command)\" with administrator privileges"
        
        let success = await MainActor.run { () -> Bool in
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    print("DEBUG: AppleScript error: \(error)")
                    self.lastError = DaemonError.scriptError(error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error")
                    return false
                }
                
                if let pidStr = result.stringValue {
                    print("DEBUG: Daemon started as root, PID: \(pidStr)")
                }
                return true
            }
            return false
        }
        
        if success {
            self.isRunning = true
            // Wait for RPC to be ready
            try await waitForRPC()
            print("DEBUG: RPC is ready!")
        } else {
            throw lastError ?? DaemonError.notRunning
        }
    }
    
    /// Check if an existing daemon is already running and responding.
    private func checkExistingDaemon() async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(rpcPort)/transmission/rpc")!
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
        
        let scriptSource = "do shell script \"pkill -9 transmission-daemon\" with administrator privileges"
        
        _ = await MainActor.run {
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                 _ = script.executeAndReturnError(&errorInfo)
                 if let error = errorInfo {
                     print("DEBUG: pkill error (might be none running): \(error)")
                 } else {
                     print("DEBUG: Killed existing daemons")
                 }
            }
            return true
        }
        
        // Wait a moment for process to fully die
        try? await Task.sleep(for: .milliseconds(1000))
    }
    
    /// Wait for RPC to become available.
    private func waitForRPC(timeout: TimeInterval = 45) async throws {
        print("DEBUG: Waiting for RPC to become available...")
        
        let deadline = Date().addingTimeInterval(timeout)
        let url = URL(string: "http://127.0.0.1:\(rpcPort)/transmission/rpc")!
        var attempts = 0
        
        while Date() < deadline {
            attempts += 1
            
            // Fast fail if we can't find the process anymore
            // Note: Since we use sudo, we can't easily check the PID owner, but pgrep helps
            /*
            let checkProcess = Process()
            checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            checkProcess.arguments = ["transmission-daemon"]
            try? checkProcess.run()
            checkProcess.waitUntilExit()
            if checkProcess.terminationStatus != 0 {
                print("DEBUG: transmission-daemon process seems to have died.")
                throw DaemonError.notRunning
            }
            */
            
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 2
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    print("DEBUG: RPC response code: \(http.statusCode)")
                    if http.statusCode == 409 || http.statusCode == 200 {
                        // 409 means RPC is ready (needs session-id), 200 means auth disabled/ready
                        print("DEBUG: RPC ready after \(attempts) attempts")
                        return
                    }
                }
            } catch {
                print("DEBUG: RPC attempt \(attempts) failed: \(error.localizedDescription)")
            }
            try await Task.sleep(for: .milliseconds(1000))
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
    case scriptError(String)
    
    var errorDescription: String? {
        switch self {
        case .rpcNotReady: return "Daemon RPC not responding"
        case .notRunning: return "Daemon is not running"
        case .scriptError(let msg): return "Script error: \(msg)"
        }
    }
}
