import AppKit
import SwiftUI

/// The About tab in Settings: version and build, update check, author, source repository and credits.
/// Its two links, the repository and the staff download page, are fixed addresses that
/// scripts/audit.sh pins. The download link never comes from GitHub's response.
struct AboutPane: View {
    static let repository = "github.com/mdjhnson/claude-usage-monitor"
    static let repositoryURL = URL(string: "https://github.com/mdjhnson/claude-usage-monitor")!
    /// PaceBar's page on the staff site, which needs a Campus Outreach sign-in. The DMG lives there,
    /// not on GitHub, so it isn't a public download.
    static let downloadURL = URL(string: "https://staff-services.serve.campusoutreach.org/tools/pacebar")!
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
                    .disabled(updates.activity == .checking)
            } label: {
                updateStatus
            }
            if let version = updates.updateAvailable {
                LabeledContent("PaceBar \(version.description)") {
                    Link("Download", destination: Self.downloadURL)
                }
            }
            Toggle("Check automatically once a week", isOn: $settings.autoCheckUpdates)
                .onChange(of: settings.autoCheckUpdates) { updates.start() }
        } header: {
            Text("Updates")
        } footer: {
            Text("Checking asks api.github.com for the latest release's version number. It sends no account data or token. PaceBar never downloads or installs updates itself.")
                .foregroundStyle(.secondary)
        }
    }

    /// The version as the update check compares it, so the two never disagree.
    private var comparedVersion: String { updates.current?.description ?? version }

    private var updateStatus: some View {
        // Redrawn each minute so "Last checked" keeps up while Settings stays open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 2) {
                switch updates.activity {
                case .checking:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .idle:
                    if let latest = updates.updateAvailable {
                        Text("PaceBar \(latest.description) is available")
                            .foregroundStyle(.orange)
                    } else if updates.latest != nil {
                        Text("PaceBar \(comparedVersion) is up to date")
                    } else {
                        Text("PaceBar \(comparedVersion)")
                    }
                }
                if let last = settings.lastUpdateCheck {
                    Text("Last checked \(Format.age(since: last, now: context.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
