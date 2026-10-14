import AppKit
import SwiftUI

/// The About tab in Settings: version and build, author, source repository and credits.
/// The repository link is the app's only link; scripts/audit.sh pins it to this one address.
struct AboutPane: View {
    static let repository = "github.com/mdjhnson/claude-usage-monitor"
    static let repositoryURL = URL(string: "https://github.com/mdjhnson/claude-usage-monitor")!
    static let author = "Matt (mdjhnson)"

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
}
