//
//  SSHTunnelSection.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/3/26.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI
import AppKit

/// SSH Tunnel configuration section with toggle and expandable fields
struct SSHTunnelSection: View {
    @Binding var useSSHTunnel: Bool
    @Binding var sshHost: String
    @Binding var sshPort: Int?
    @Binding var sshUser: String
    @Binding var sshKeyPath: String
    @Binding var sshKeyBookmarkData: Data?

    var body: some View {
        VStack(spacing: 0) {
            // Toggle row
            FormFieldRow(label: "SSH Tunnel", showDivider: useSSHTunnel) {
                Toggle("", isOn: $useSSHTunnel.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // Expandable SSH fields
            if useSSHTunnel {
                VStack(spacing: 0) {
                    FormTextField(label: "SSH Host", text: $sshHost, placeholder: "ssh.example.com", showDivider: true)
                    FormNumberField(label: "SSH Port", value: $sshPort, placeholder: "22", showDivider: true)
                    FormTextField(label: "SSH User", text: $sshUser, placeholder: "username", showDivider: true)

                    // SSH Key row with browse button
                    FormFieldRow(label: "SSH Key", showDivider: false) {
                        HStack(spacing: Spacing.xs) {
                            TextField("~/.ssh/id_rsa", text: $sshKeyPath)
                                .textFieldStyle(.plain)

                            Button("Browse...") {
                                selectSSHKeyFile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func selectSSHKeyFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select SSH Private Key File"
        panel.begin { response in
            if response == .OK, let url = panel.url {

                // Try to create a bookmark first (works for most locations)
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    self.sshKeyBookmarkData = bookmarkData
                    self.sshKeyPath = url.path
                    print("Created security-scoped bookmark for SSH key: \(url.path)")
                    return
                } catch {
                    print("Bookmark creation failed (likely protected location like .ssh)")
                    print("Will copy key to app's Application Support directory instead")
                }

                // Bookmark failed (e.g., .ssh directory) - copy key to Application Support
                do {
                    // Read the key file (we have temporary access from file picker)
                    let keyData = try Data(contentsOf: url)
                    print("Read SSH key: \(keyData.count) bytes")

                    // Get Application Support directory
                    let fileManager = FileManager.default
                    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                        print("Failed to get Application Support directory")
                        return
                    }

                    // Create Searchlight/ssh-keys directory
                    let sshKeysDir = appSupport.appendingPathComponent("Searchlight/ssh-keys", isDirectory: true)
                    try fileManager.createDirectory(at: sshKeysDir, withIntermediateDirectories: true, attributes: nil)

                    // Copy key with original filename
                    let originalFilename = url.lastPathComponent
                    let copiedKeyURL = sshKeysDir.appendingPathComponent(originalFilename)

                    // Write key to Application Support
                    try keyData.write(to: copiedKeyURL, options: [.atomic])

                    // Set restrictive permissions (0600 - owner read/write only)
                    let attributes = [FileAttributeKey.posixPermissions: 0o600]
                    try fileManager.setAttributes(attributes, ofItemAtPath: copiedKeyURL.path)

                    // Store the copied path (no bookmark needed - it's in our app directory)
                    self.sshKeyPath = copiedKeyURL.path
                    self.sshKeyBookmarkData = nil

                } catch {
                    print("Failed to copy SSH key: \(error.localizedDescription)")
                    self.sshKeyPath = url.path
                    self.sshKeyBookmarkData = nil
                }
            }
        }
    }
}

#Preview {
    GroupedSectionView(title: "Security") {
        FormFieldRow(label: "Use SSL", showDivider: true) {
            Toggle("", isOn: .constant(true))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        SSHTunnelSection(
            useSSHTunnel: .constant(true),
            sshHost: .constant("ssh.example.com"),
            sshPort: .constant(22),
            sshUser: .constant("admin"),
            sshKeyPath: .constant("~/.ssh/id_rsa"),
            sshKeyBookmarkData: .constant(nil)
        )
    }
    .padding()
    .frame(width: 450)
}
