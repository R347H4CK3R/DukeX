import SwiftUI

struct LaunchPlanView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: XemuLaunchPlan

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    Label(plan.gameName, systemImage: "opticaldisc")
                }

                Section("JIT") {
                    Label(plan.universalJITEnabled ? "Universal.js" : "Disabled",
                          systemImage: plan.universalJITEnabled ? "bolt.horizontal.circle.fill" : "bolt.slash")
                }

                Section("Config") {
                    Text(plan.configURL.lastPathComponent)
                    Text(plan.configURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Arguments") {
                    Text(plan.commandLine)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Launch Ready")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
