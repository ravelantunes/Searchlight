//
//  SSHTunnelManager.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/28/24.

//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

enum SSHTunnelError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case portForwardingFailed
    case tunnelNotEstablished
    case invalidKeyPath

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "SSH connection failed: \(message)"
        case .authenticationFailed:
            return "SSH authentication failed. Check your key file."
        case .portForwardingFailed:
            return "Failed to establish port forwarding through SSH tunnel."
        case .tunnelNotEstablished:
            return "SSH tunnel is not established."
        case .invalidKeyPath:
            return "Invalid SSH key path. Please provide a valid path to your private key."
        }
    }
}

/// Manages SSH tunnel lifecycle for database connections
/// Uses system SSH command for maximum compatibility with all key types
class SSHTunnelManager {
    private let configuration: SSHTunnelConfiguration
    private let remoteHost: String
    private let remotePort: Int

    private var sshProcess: Process?
    private(set) var localPort: Int = 0
    private var securityScopedURL: URL?  // Keep URL alive to maintain security scope access
    private var tempKeyPath: String?  // Temporary key file path for SSH process

    init(sshConfig: SSHTunnelConfiguration, remoteHost: String, remotePort: Int) {
        self.configuration = sshConfig
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    /// Establishes the SSH tunnel and sets up port forwarding using system SSH
    func establishTunnel() async throws {
        print("Attempting to establish SSH tunnel")
        print("  SSH Host: \(configuration.host):\(configuration.port)")
        print("  SSH User: \(configuration.user)")
        print("  SSH Key: \(configuration.keyPath)")
        print("  Remote Target: \(remoteHost):\(remotePort)")

        // Find available local port
        self.localPort = try findAvailablePort()

        // Resolve security-scoped bookmark if available, otherwise use path
        let expandedKeyPath = try resolveKeyPath()

        // Build SSH command
        let arguments = [
            "-N",  // Don't execute remote command
            "-L", "\(localPort):\(remoteHost):\(remotePort)",  // Local port forwarding
            "-p", "\(configuration.port)",  // SSH port
            "-i", expandedKeyPath,  // Identity file (private key)
            "-o", "StrictHostKeyChecking=no",  // Don't ask about host key
            "-o", "UserKnownHostsFile=/dev/null",  // Don't save host key
            "-o", "ServerAliveInterval=60",  // Keep connection alive
            "-o", "ServerAliveCountMax=3",  // Number of keep-alive messages
            "\(configuration.user)@\(configuration.host)"
        ]

        // Note: For encrypted keys, SSH will prompt for passphrase via macOS Keychain
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            print("Launching ssh process...")
            try process.run()
            self.sshProcess = process

            // Give SSH a moment to establish the connection
            try await Task.sleep(nanoseconds: 2_000_000_000) // 5 seconds

            // Check if process is still running
            if !process.isRunning {
                let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("ssh tunnel process terminated: \(errorOutput)")
                throw SSHTunnelError.connectionFailed("ssh tunnel failed: \(errorOutput)")
            }

            // Verify the tunnel is working by checking if port is listening
            if try !isPortListening(port: localPort) {
                throw SSHTunnelError.portForwardingFailed
            }

            print("ssh tunnel port forwarding established on localhost:\(localPort)")
        } catch {
            print("Failed to establish ssh tunnel: \(error)")
            try? await closeTunnel()
            if let sshError = error as? SSHTunnelError {
                throw sshError
            }
            throw SSHTunnelError.connectionFailed(error.localizedDescription)
        }
    }

    /// Closes the SSH tunnel and cleans up resources
    func closeTunnel() async throws {

        if let process = sshProcess, process.isRunning {
            process.terminate()
            // Give it a moment to terminate gracefully
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Delete temporary key file
        if let tempPath = tempKeyPath {
            do {
                try FileManager.default.removeItem(atPath: tempPath)
            } catch {
                print("Failed to delete temp key: \(error.localizedDescription)")
            }
        }

        // Release security-scoped resource access
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
        }

        self.sshProcess = nil
        self.securityScopedURL = nil
        self.tempKeyPath = nil
        self.localPort = 0

        print("ssh tunnel closed")
    }

    /// Finds an available port for local forwarding
    private func findAvailablePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw SSHTunnelError.portForwardingFailed
        }
        defer { Darwin.close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // Let system assign a port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw SSHTunnelError.portForwardingFailed
        }

        var boundAddr = sockaddr_in()
        var boundAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socket, $0, &boundAddrLen)
            }
        }

        guard getsocknameResult == 0 else {
            throw SSHTunnelError.portForwardingFailed
        }

        return Int(UInt16(bigEndian: boundAddr.sin_port))
    }

    /// Checks if a port is listening
    private func isPortListening(port: Int) throws -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            return false
        }
        defer { Darwin.close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return connectResult == 0
    }

    /// Resolves the SSH key path using security-scoped bookmark if available
    /// Copies key to temp location so child SSH process can access it
    private func resolveKeyPath() throws -> String {
        // If we have a security-scoped bookmark, use it
        if let bookmarkData = configuration.keyBookmarkData {
            
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                print("ssh key file bookmark is stale, but attempting to use it anyway")
            }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to start accessing security-scoped resource")
                throw SSHTunnelError.invalidKeyPath
            }

            // CRITICAL: Store the URL to keep it alive and maintain security scope access
            self.securityScopedURL = url

            // Read key and copy to temp file
            let keyData = try Data(contentsOf: url)
            return try createTempKeyFile(from: keyData)
        }

        // Fall back to direct path
        // This is used when:
        // 1. Key is in Application Support (copied there because bookmark creation failed)
        // 2. User manually typed a path without using Browse button
        let expandedPath = NSString(string: configuration.keyPath).expandingTildeInPath
        print("Using direct key path: \(expandedPath)")

        // For keys in Application Support, we can use them directly
        if expandedPath.contains("/Library/Application Support/Searchlight/ssh-keys/") {
            print("Key is in Application Support, using directly")
            return expandedPath
        }

        // For other locations, read and copy to temp
        do {
            let keyData = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
            return try createTempKeyFile(from: keyData)
        } catch {
            print("Failed to read key file for ssh tunnel: \(error.localizedDescription)")
            throw SSHTunnelError.invalidKeyPath
        }
    }

    /// Creates a temporary key file from key data
    /// This is needed because SSH subprocess cannot access security-scoped resources
    private func createTempKeyFile(from keyData: Data) throws -> String {
        let tempDir = NSTemporaryDirectory()
        let tempKeyFilename = "ssh_key_\(UUID().uuidString)"
        let tempKeyPath = (tempDir as NSString).appendingPathComponent(tempKeyFilename)

        try keyData.write(to: URL(fileURLWithPath: tempKeyPath), options: [.atomic])

        // Set restrictive permissions (0600 - owner read/write only)
        let attributes = [FileAttributeKey.posixPermissions: 0o600]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: tempKeyPath)

        self.tempKeyPath = tempKeyPath
        print("Created temporary key file: \(tempKeyPath)")

        return tempKeyPath
    }

    deinit {
        // Synchronous cleanup - cannot use async in deinit
        if let process = sshProcess, process.isRunning {
            process.terminate()
        }

        // Delete temporary key file
        if let tempPath = tempKeyPath {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        // Release security-scoped resource access
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
}
