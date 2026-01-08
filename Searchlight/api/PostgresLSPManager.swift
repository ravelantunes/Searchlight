//
//  PostgresLSPManager.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/7/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import LanguageClient
import LanguageServerProtocol
import JSONRPC

enum PostgresLSPError: Error, LocalizedError {
    case binaryNotFound
    case processStartFailed(String)
    case connectionFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Postgres Language Server binary not found in app bundle."
        case .processStartFailed(let message):
            return "Failed to start language server: \(message)"
        case .connectionFailed(let message):
            return "Language server connection failed: \(message)"
        case .notConnected:
            return "Language server is not connected."
        }
    }
}

/// Connection state for the LSP
enum LSPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Manages the Postgres Language Server process lifecycle
@MainActor
class PostgresLSPManager: ObservableObject {
    @Published private(set) var state: LSPConnectionState = .disconnected
    @Published private(set) var diagnostics: [Diagnostic] = []

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var server: InitializingServer?
    private var eventTask: Task<Void, Never>?

    private var configDirectory: URL?
    private var documentVersion: Int = 0

    /// The virtual document URI used for the SQL editor
    /// Using a fixed URI since we have a single editor
    private let documentURI = "file:///searchlight/query.sql"

    /// Creates a temporary config file for the LSP
    private func createConfigFile(config: DatabaseConnectionConfiguration, tunnelPort: Int?) throws -> URL {
        let host = tunnelPort != nil ? "127.0.0.1" : config.host
        let port = tunnelPort ?? config.port

        // Build config as a proper JSON string to avoid escaping issues
        let configJSON = """
        {
          "$schema": "https://pg-language-server.com/0.18.0/schema.json",
          "db": {
            "host": "\(host)",
            "port": \(port),
            "username": "\(config.user)",
            "password": "\(config.password)",
            "database": "\(config.database)",
            "connTimeoutSecs": 10,
            "disableConnection": false
          },
          "linter": {
            "enabled": true,
            "rules": {
              "recommended": true
            }
          }
        }
        """

        guard let jsonData = configJSON.data(using: .utf8) else {
            throw PostgresLSPError.processStartFailed("Failed to encode config JSON")
        }

        // The LSP creates a Unix socket in the config directory.
        // Unix sockets have a max path length of ~104 chars on macOS.
        // Sandboxed apps can't write to /tmp, and the container temp path is too long.
        // Solution: Write config to container temp, then create a short symlink in /var/folders
        // that the sandbox can access, and pass the symlink path to the LSP.
        let shortId = String(UUID().uuidString.prefix(6))

        // Create the actual config directory in container temp (sandbox-writable)
        let actualDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pglsp-\(shortId)")
        try FileManager.default.createDirectory(at: actualDir, withIntermediateDirectories: true)

        // Write config file - must be named postgres-language-server.jsonc
        let configFile = actualDir.appendingPathComponent("postgres-language-server.jsonc")
        try jsonData.write(to: configFile)

        self.configDirectory = actualDir

        // Return the actual directory - the LSP will create its socket here
        // The path length issue is in the socket creation, not config reading
        // Let's try passing just the config file path directly
        return actualDir
    }

    /// Cleans up the temporary config directory
    private func cleanupConfigDirectory() {
        if let dir = configDirectory {
            try? FileManager.default.removeItem(at: dir)
            configDirectory = nil
        }
    }

    /// Locates the postgres-language-server binary in the app bundle
    private func findLSPBinary() -> URL? {
        // Look in Resources directory
        if let url = Bundle.main.url(forResource: "postgres-language-server", withExtension: nil) {
            return url
        }

        // Also check in Resources/Binaries subdirectory
        if let resourcePath = Bundle.main.resourcePath {
            let binaryPath = (resourcePath as NSString).appendingPathComponent("Binaries/postgres-language-server")
            if FileManager.default.fileExists(atPath: binaryPath) {
                return URL(fileURLWithPath: binaryPath)
            }
        }

        return nil
    }

    /// Starts the language server process and establishes connection
    /// - Parameters:
    ///   - config: The database connection configuration
    ///   - tunnelPort: Optional local port if SSH tunnel is active
    func start(config: DatabaseConnectionConfiguration, tunnelPort: Int?) async throws {
        // Stop any existing instance
        await stop()

        state = .connecting

        guard let binaryURL = findLSPBinary() else {
            state = .error("Binary not found")
            throw PostgresLSPError.binaryNotFound
        }

        // Create config file with database connection info
        let configDir: URL
        do {
            configDir = try createConfigFile(config: config, tunnelPort: tunnelPort)
        } catch {
            state = .error("Failed to create config: \(error.localizedDescription)")
            throw PostgresLSPError.processStartFailed("Failed to create config file: \(error.localizedDescription)")
        }

        print("[LSP] Starting Postgres Language Server...")
        print("[LSP] Binary: \(binaryURL.path)")
        print("[LSP] Config: \(configDir.path)")
        print("[LSP] Database: \(config.host):\(config.port)/\(config.database)")

        // Create pipes for communication
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Configure the process
        let lspProcess = Process()
        lspProcess.executableURL = binaryURL
        lspProcess.standardInput = stdin
        lspProcess.standardOutput = stdout
        lspProcess.standardError = stderr

        // The LSP creates a Unix socket at $HOME/Library/Caches/dev.supabase-community.pgls/pgls-socket-*
        // Unix sockets have a max path length of ~104 chars on macOS.
        // The sandboxed container path is too long (~120+ chars).
        //
        // Solution: Create a symlink from a short path to the container's cache directory.
        // The sandbox allows the subprocess to follow symlinks into allowed directories.
        let containerCaches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let lspCacheDir = containerCaches.appendingPathComponent("pgls")
        try? FileManager.default.createDirectory(at: lspCacheDir, withIntermediateDirectories: true)

        // Create a short symlink path: /tmp/slsp -> container caches
        // The symlink itself is short, but it points to the sandbox-allowed location
        let shortHomePath = "/tmp/slsp-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.removeItem(atPath: shortHomePath)

        // Create a fake HOME structure with symlinked Library/Caches
        let shortLibraryCaches = "\(shortHomePath)/Library/Caches"
        try? FileManager.default.createDirectory(atPath: "\(shortHomePath)/Library", withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(atPath: shortLibraryCaches, withDestinationPath: containerCaches.path)

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = shortHomePath
        // Enable verbose logging for debugging
        env["PGT_LOG_KIND"] = "trace"
        env["PGLS_LOG_KIND"] = "trace"
        lspProcess.environment = env

        print("[LSP] Short HOME: \(shortHomePath)")
        print("[LSP] Symlinked to: \(containerCaches.path)")

        // Set arguments with log path for detailed debugging
        lspProcess.arguments = [
            "lsp-proxy",
            "--config-path=\(configDir.path)",
            "--log-path=\(configDir.path)"
        ]
        print("[LSP] Log files will be written to: \(configDir.path)")

        // Handle process termination
        lspProcess.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                if self.state == .connected {
                    print("[LSP] Process terminated unexpectedly with code: \(process.terminationStatus)")
                    self.state = .error("Process terminated")
                }
            }
        }

        // Log stderr for debugging
        Task {
            for try await line in stderr.fileHandleForReading.bytes.lines {
                print("[LSP stderr] \(line)")
            }
        }

        do {
            try lspProcess.run()
            self.process = lspProcess
            print("[LSP] Process started with PID: \(lspProcess.processIdentifier)")
        } catch {
            cleanupConfigDirectory()
            state = .error(error.localizedDescription)
            throw PostgresLSPError.processStartFailed(error.localizedDescription)
        }

        // Create data channel for LSP communication
        let dataChannel = createDataChannel(stdin: stdin, stdout: stdout, process: lspProcess)

        // Create and initialize the LSP server connection
        do {
            try await initializeLSP(channel: dataChannel)
            state = .connected
            print("[LSP] Connected successfully")
        } catch {
            await stop()
            state = .error(error.localizedDescription)
            throw PostgresLSPError.connectionFailed(error.localizedDescription)
        }
    }

    /// Creates a DataChannel for LSP communication over stdin/stdout
    private func createDataChannel(stdin: Pipe, stdout: Pipe, process: Process) -> DataChannel {
        // Create async stream for reading stdout
        let (stream, continuation) = AsyncStream<Data>.makeStream()

        let handle = stdout.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                fileHandle.readabilityHandler = nil
                continuation.finish()
                return
            }
            continuation.yield(data)
        }

        // Write handler for stdin
        let writeHandler: DataChannel.WriteHandler = { data in
            // Keep process reference alive
            _ = process
            try stdin.fileHandleForWriting.write(contentsOf: data)
        }

        return DataChannel(writeHandler: writeHandler, dataSequence: stream)
    }

    /// Initializes the LSP protocol handshake
    private func initializeLSP(channel: DataChannel) async throws {
        // Create JSON-RPC connection with message framing
        let connection = JSONRPCServerConnection(dataChannel: channel)

        // Create initialize params provider
        let initializeParamsProvider: InitializingServer.InitializeParamsProvider = {
            InitializeParams(
                processId: Int(ProcessInfo.processInfo.processIdentifier),
                clientInfo: InitializeParams.ClientInfo(name: "Searchlight", version: "0.9"),
                locale: nil,
                rootPath: nil,
                rootUri: nil,
                initializationOptions: nil,
                capabilities: ClientCapabilities(
                    workspace: nil,
                    textDocument: TextDocumentClientCapabilities(
                        synchronization: TextDocumentSyncClientCapabilities(
                            dynamicRegistration: false,
                            willSave: false,
                            willSaveWaitUntil: false,
                            didSave: true
                        ),
                        completion: CompletionClientCapabilities(
                            dynamicRegistration: false,
                            completionItem: nil,
                            completionItemKind: nil,
                            contextSupport: true,
                            insertTextMode: nil,
                            completionList: nil
                        ),
                        hover: HoverClientCapabilities(
                            dynamicRegistration: false,
                            contentFormat: [.markdown, .plaintext]
                        ),
                        publishDiagnostics: PublishDiagnosticsClientCapabilities(
                            relatedInformation: true,
                            tagSupport: nil,
                            versionSupport: true,
                            codeDescriptionSupport: true,
                            dataSupport: true
                        )
                    ),
                    window: nil,
                    general: nil,
                    experimental: nil
                ),
                trace: .off,
                workspaceFolders: nil
            )
        }

        let initServer = InitializingServer(server: connection, initializeParamsProvider: initializeParamsProvider)
        self.server = initServer

        // Initialize the connection
        let _ = try await initServer.initializeIfNeeded()

        // Start monitoring server events (for diagnostics, etc.)
        self.eventTask = Task { [weak self] in
            for await event in initServer.eventSequence {
                await self?.handleServerEvent(event)
            }
        }
    }

    /// Handle events from the LSP server
    private func handleServerEvent(_ event: ServerEvent) {
        switch event {
        case .notification(let notification):
            switch notification {
            case .textDocumentPublishDiagnostics(let params):
                print("[LSP] Diagnostics for \(params.uri): \(params.diagnostics.count) items")
                self.diagnostics = params.diagnostics
            case .windowLogMessage(let params):
                print("[LSP] Server log [\(params.type)]: \(params.message)")
            case .windowShowMessage(let params):
                print("[LSP] Server message [\(params.type)]: \(params.message)")
            default:
                break
            }
        case .request(_, let request):
            print("[LSP] Server request: \(request)")
        case .error(let error):
            print("[LSP] Error: \(error)")
        }
    }

    /// Gets the server for making LSP requests
    var lspServer: InitializingServer? {
        return server
    }

    // MARK: - Document Synchronization

    /// Opens a document in the language server
    /// Call this when the editor becomes active
    func openDocument(text: String) async throws {
        guard let server = server else {
            throw PostgresLSPError.notConnected
        }

        documentVersion = 1
        diagnostics = []

        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(
                uri: documentURI,
                languageId: "sql",
                version: documentVersion,
                text: text
            )
        )

        try await server.textDocumentDidOpen(params)
        print("[LSP] Document opened")
    }

    /// Updates the document content in the language server
    /// Call this when the text changes (debounced)
    func updateDocument(text: String) async throws {
        guard let server = server else {
            throw PostgresLSPError.notConnected
        }

        documentVersion += 1

        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(
                uri: documentURI,
                version: documentVersion
            ),
            contentChanges: [
                .init(range: nil, rangeLength: nil, text: text)
            ]
        )

        try await server.textDocumentDidChange(params)
    }

    /// Closes the document in the language server
    /// Call this when the editor closes
    func closeDocument() async throws {
        guard let server = server else {
            return // Not an error to close when not connected
        }

        let params = DidCloseTextDocumentParams(
            textDocument: TextDocumentIdentifier(uri: documentURI)
        )

        try await server.textDocumentDidClose(params)
        diagnostics = []
        print("[LSP] Document closed")
    }

    // MARK: - LSP Requests

    /// Request completions at the given position
    /// - Parameters:
    ///   - line: 0-indexed line number
    ///   - character: 0-indexed character position
    /// - Returns: Completion items or nil if unavailable
    func requestCompletions(line: Int, character: Int) async throws -> [CompletionItem] {
        guard let server = server else {
            throw PostgresLSPError.notConnected
        }

        let params = CompletionParams(
            textDocument: TextDocumentIdentifier(uri: documentURI),
            position: Position(line: line, character: character),
            context: CompletionContext(triggerKind: .invoked, triggerCharacter: nil)
        )

        let response: CompletionResponse = try await server.completion(params)

        switch response {
        case .optionA(let items):
            return items
        case .optionB(let list):
            return list.items
        case .none:
            return []
        }
    }

    /// Request hover information at the given position
    /// - Parameters:
    ///   - line: 0-indexed line number
    ///   - character: 0-indexed character position
    /// - Returns: Hover information or nil if unavailable
    func requestHover(line: Int, character: Int) async throws -> Hover? {
        guard let server = server else {
            throw PostgresLSPError.notConnected
        }

        let params = TextDocumentPositionParams(
            textDocument: TextDocumentIdentifier(uri: documentURI),
            position: Position(line: line, character: character)
        )

        return try await server.hover(params)
    }

    /// Stops the language server process
    func stop() async {
        // Cancel event monitoring
        eventTask?.cancel()
        eventTask = nil

        if let server = server {
            // Try to send shutdown/exit gracefully
            do {
                try await server.shutdownAndExit()
            } catch {
                print("[LSP] Graceful shutdown failed: \(error)")
            }
        }

        // Terminate process if still running
        if let process = process, process.isRunning {
            process.terminate()
            // Give it time to terminate
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if process.isRunning {
                // Force kill if still running
                kill(process.processIdentifier, SIGKILL)
            }
        }

        // Close pipes
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        self.process = nil
        self.server = nil
        self.stdinPipe = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil

        // Clean up temporary config directory
        cleanupConfigDirectory()

        state = .disconnected
        print("[LSP] Stopped")
    }

    /// Restarts the language server with the same configuration
    func restart(config: DatabaseConnectionConfiguration, tunnelPort: Int?) async throws {
        await stop()
        try await start(config: config, tunnelPort: tunnelPort)
    }

    deinit {
        // Synchronous cleanup
        eventTask?.cancel()
        if let process = process, process.isRunning {
            process.terminate()
        }
    }
}
