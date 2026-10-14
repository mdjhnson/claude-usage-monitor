import AppKit
import SwiftUI

/// The About tab in Settings: version and build, update check, author, source repository and credits.
/// Its two links, the repository and its latest release, are fixed addresses that scripts/audit.sh
/// pins. The release link never comes from GitHub's response.
struct AboutPane: View {
    static let repository = "github.com/mdjhnson/claude-usage-monitor"
    static let repositoryURL = URL(string: "https://github.com/mdjhnson/claude-usage-monitor")!
    static let releasesURL = URL(string: "https://github.com/mdjhnson/claude-usage-monitor/releases/latest")!
    static let author = "Matt (mdjhnson)"

    @Bindable var settings: SettingsStore
    let updates: UpdateChecker

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "dev" }
    private var build: String { info["CFBundleVersion"] as? String ?? "0" }
    /// Written into the built Info.plist by build.sh; absent in `swift run` builds.
    private var commit: String? { info["PaceBarCommit"] as? String }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PaceBar")
                        .font(.title2.weight(.semibold))
                    Text("Shows your Claude usage limits in the menu bar, and whether you're using them faster or slower than a steady pace.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }

        Section("Build") {
            LabeledContent("Version", value: version)
            LabeledContent("Build", value: build)
            if let commit {
                LabeledContent("Commit") {
                    Text(commit)
                        .monospaced()
                        .textSelection(.enabled)
                }
            }
        }

        updatesSection

        Section {
            LabeledContent("Made by", value: Self.author)
            LabeledContent("Source") {
                Link(Self.repository, destination: Self.repositoryURL)
            }
            LabeledContent("License", value: "MIT")
        } header: {
            Text("About")
        } footer: {
            Text("Pacing model, quips, theme presets and visual design follow TokenEater by AThevon (MIT).")
                .foregroundStyle(.secondary)
        }
    }

    private var updatesSection: some View {
        Section {
            LabeledContent {
                Button("Check for Updates") { updates.check() }
                    .disabled(updates.state == .checking)
            } label: {
                updateStatus
            }
            if let version = updates.updateAvailable {
                LabeledContent("PaceBar \(version.description)") {
                    Link("Download", destination: Self.releasesURL)
                }
            }
            Toggle("Check automatically once a week", isOn: $settings.autoCheckUpdates)
                .onChange(of: settings.autoCheckUpdates) { updates.checkIfDue() }
        } header: {
            Text("Updates")
        } footer: {
            Text("Checking asks api.github.com for the latest release's version number. It sends no account data or token. PaceBar never downloads or installs updates itself.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch updates.state {
            case .idle:
                Text("PaceBar \(version)")
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .upToDate:
                Text("PaceBar \(version) is up to date")
            case .available(let latest):
                Text("PaceBar \(latest.description) is available")
                    .foregroundStyle(.orange)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = settings.lastUpdateCheck {
                Text("Last checked \(Format.age(since: last, now: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
