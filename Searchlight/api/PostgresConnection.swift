//
//  PostgresConnection.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/28/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import PostgresKit
import CryptoKit

// This class was originally named PostgresConnectionManager (since it is managing a pool of connections) but I renamed to PostgresConnection to make the name less redundant with ConnectionsManager.
// Ideally this class is all we would need, but since changing databases requires to create new connection (and the PostgresConnectionSource requires the database as an argument) the ConnectionsManager
// helps handling multiple PostgresConnection for different databases.
class PostgresConnection {

    private let configuration: DatabaseConnectionConfiguration
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let connectionPool: EventLoopGroupConnectionPool<PostgresConnectionSource>
    private var sshTunnelManager: SSHTunnelManager?

    init(configuration: DatabaseConnectionConfiguration) async throws {
        self.configuration = configuration
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        // Establish SSH tunnel if configured
        let connectionHost: String
        let connectionPort: Int

        if let sshConfig = configuration.sshTunnel, sshConfig.enabled {
            print("SSH tunnel enabled, establishing tunnel...")
            let tunnelManager = SSHTunnelManager(
                sshConfig: sshConfig,
                remoteHost: configuration.host,
                remotePort: configuration.port
            )
            try await tunnelManager.establishTunnel()
            self.sshTunnelManager = tunnelManager

            // Connect to localhost using the tunnel's local port
            connectionHost = "127.0.0.1"
            connectionPort = tunnelManager.localPort
            print("SSH tunnel established on localhost:\(connectionPort)")
        } else {
            // Direct connection without SSH tunnel
            connectionHost = configuration.host
            connectionPort = configuration.port
        }

        // Disabling certificate validation so it can work out of the box with certain hosts (ie.: AWS RDS)
        // TODO: make this optional instead of the default
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none

        // Map our internal config struct into the NIO config
        let postgresNIOSqlConfiguration = SQLPostgresConfiguration(
            hostname: connectionHost,
            port: connectionPort,
            username: configuration.user,
            password: configuration.password,
            database: configuration.database,
            tls: configuration.ssl ? .require(try! NIOSSLContext(configuration: tlsConfig)) : .disable
        )
        
        let connectionSource = PostgresConnectionSource(sqlConfiguration: postgresNIOSqlConfiguration)
        connectionPool = EventLoopGroupConnectionPool(
            source: connectionSource,
            maxConnectionsPerEventLoop: 2,
            on: eventLoopGroup
        )
    }
    
    deinit {
        // Close SSH tunnel if established
        if let tunnel = sshTunnelManager {
            Task {
                try? await tunnel.closeTunnel()
            }
        }

        do {
            connectionPool.shutdownGracefully { error in
                if let error {
                    print("Failed to shutdown connection pool: \(error)")
                }
            }
            try eventLoopGroup.syncShutdownGracefully()
        } catch {
            print("Failed to shutdown EventLoopGroup: \(error)")
        }
    }
    
    func testConnection() async throws {
        let testResult = try await query(query: "SELECT version()")
        let version = try testResult[0]["version"].decode((String).self)
        print("Version: \(version)")
    }
    
    func query(query: String) async throws -> [PostgresRandomAccessRow] {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                connectionPool.withConnection { connection -> EventLoopFuture<PostgresQueryResult> in
                    return connection.query(query)
                }.whenComplete { result in
                    switch result {
                    case .success(let queryResult):
                        continuation.resume(returning: queryResult.rows.map { $0.makeRandomAccess() })
                    case .failure(let error):
                        print("TODO: error handling")
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let error as PSQLError {
            // TODO create an Error implementation
            switch error.code {
            case .sslUnsupported:
                throw NSError(domain: "postgres-mac-client", code: 1, userInfo: [NSLocalizedDescriptionKey: "SSL is not supported. Try unchecking the Use SSL checkbox in the configuration."])
            case .server:
                throw NSError(domain: "postgres-mac-client", code: 1, userInfo: [NSLocalizedDescriptionKey: error.serverInfo![.message]!])
            case .connectionError:
                throw NSError(domain: "postgres-mac-client", code: 1, userInfo: [NSLocalizedDescriptionKey: "Check your hostname and port."])
            default:
                throw error
            }
        } catch let postgresError as PostgresNIO.PostgresError {
            switch postgresError {
            case .server(let serverError):
                serverError.fields.forEach { print($0) }
                
                let errorColumn = serverError.fields[PostgresMessage.Error.Field.columnName]
                let message = serverError.fields[PostgresMessage.Error.Field.message]
                
                if let message = message {
                    throw SearchlightAPIError(description: message, columnName: errorColumn)
                }
            default:
                throw postgresError
            }
                    
            throw postgresError
        } catch {
            // TODO: parse error
            throw error
        }
    }
}
