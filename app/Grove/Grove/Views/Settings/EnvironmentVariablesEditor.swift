// Views/Settings/EnvironmentVariablesEditor.swift
// Grove
//
// Name / value rows for the environment git runs with, used in Preferences and Repository Settings.

import SwiftUI

struct EnvironmentVariablesEditor: View {
    @Binding var variables: [EnvironmentVariable]

    var body: some View {
        if variables.isEmpty {
            Text("No variables.").foregroundStyle(Theme.textSecondary)
        }
        ForEach($variables) { $variable in
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Name", text: $variable.name, prompt: Text("NAME"))
                    .labelsHidden()
                    .font(.monoCaption)
                    .frame(maxWidth: 180)
                    .foregroundStyle(variable.isValid || variable.name.isEmpty ? Theme.textPrimary : Theme.danger)
                Text("=").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                TextField("Value", text: $variable.value, prompt: Text("value"))
                    .labelsHidden()
                    .font(.monoCaption)
                Button {
                    variables.removeAll { $0.id == variable.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.textSecondary)
                .help("Remove \(variable.name)")
            }
        }
        Button("Add Variable", systemImage: "plus") { variables.append(EnvironmentVariable()) }
    }
}

#Preview {
    @Previewable @State var variables = [EnvironmentVariable(name: "HUSKY", value: "0"),
                                         EnvironmentVariable(name: "JIRA_PROJECT", value: "GRV")]
    Form {
        Section("Environment Variables") { EnvironmentVariablesEditor(variables: $variables) }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 260)
}
