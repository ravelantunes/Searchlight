//
//  ConnectionSection.swift
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

/// Connection configuration section with host, port, database, credentials, and SSL
struct ConnectionSection: View {
    @Binding var host: String
    @Binding var port: Int?
    @Binding var database: String
    @Binding var username: String
    @Binding var password: String
    @Binding var useSSL: Bool

    var body: some View {
        VStack(spacing: 0) {
            FormTextField(label: "Host", text: $host, placeholder: "localhost", showDivider: true)
            FormNumberField(label: "Port", value: $port, placeholder: "5432", showDivider: true)
            FormTextField(label: "Database", text: $database, placeholder: "postgres", showDivider: true)
            FormTextField(label: "Username", text: $username, placeholder: "postgres", showDivider: true)
            FormTextField(label: "Password", text: $password, placeholder: "Enter password", showDivider: true, isSecure: true)

            FormFieldRow(label: "Use SSL", showDivider: false) {
                Toggle("", isOn: $useSSL)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

#Preview {
    GroupedSectionView(title: "Connection") {
        ConnectionSection(
            host: .constant("localhost"),
            port: .constant(5432),
            database: .constant("mydb"),
            username: .constant("postgres"),
            password: .constant(""),
            useSSL: .constant(true)
        )
    }
    .padding()
    .frame(width: 450)
}
