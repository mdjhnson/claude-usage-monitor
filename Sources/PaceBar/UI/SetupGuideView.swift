import AppKit
import SwiftUI

/// Walks someone through installing Claude Code and signing in, or through renewing an expired
/// login. PaceBar only copies the command and opens Terminal; the person pastes and runs it.
struct SetupGuideView: View {
    let need: SetupNeed
    let isChecking: Bool
    let textColor: Color
    let onCheckNow: () -> Void

    @State private var copied = false

    /// The only app PaceBar ever opens. Fixed path, no URL handling.
    static let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    /// Where Claude Code's native installer puts the binary, relative to the home folder.
    static let installedBinary = ".local/bin/claude"
    /// Copied to the pasteboard for the person to run. PaceBar never fetches it.
    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash && ~/.local/bin/claude"

    static var claudeInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/" + installedBinary)
    }

    static func command(for need: SetupNeed, claudeInstalled: Bool) -> String {
        if claudeInstalled { return "~/" + installedBinary }
        switch need {
        case .signIn: return installCommand
        // Installed some other way (npm, Homebrew), so it should be on PATH.
        case .renew: return "claude"
        }
    }

    var body: some View {
        let installed = Self.claudeInstalled
        let command = Self.command(for: need, claudeInstalled: installed)

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(need == .signIn ? "Connect your Claude account" : "Renew your Claude sign-in")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.95))
                Text(need == .signIn
                     ? "PaceBar reads your usage through Claude Code, Claude's command-line app. The Claude desktop app doesn't share its sign-in, so this needs a one-time setup."
                     : "Your Claude Code sign-in has expired. Starting Claude Code renews it.")
                    .font(.system(size: 11))
                    .foregroundStyle(textColor.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(1) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Copy the command and open Terminal.")
                    Button(action: { copyAndOpenTerminal(command) }) {
                        Label(copied ? "Copied. Opening Terminal…" : "Copy & Open Terminal",
                              systemImage: copied ? "checkmark" : "terminal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.55))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.25)))
                }
            }
            step(2) {
                Text(installed || need == .renew
                     ? "In Terminal, paste with ⌘V and press Return to start Claude Code."
                     : "In Terminal, paste with ⌘V and press Return. It installs Claude Code, then starts it.")
            }
            switch need {
            case .signIn:
                step(3) {
                    Text("Follow its prompts. Choose “Claude account with subscription” and sign in with the account you use in the Claude app.")
                }
                step(4) { Text("When it says “Login successful”, you can close Terminal.") }
                step(5) {
                    Text("macOS then asks to let “security” use “Claude Code-credentials”. Enter your Mac password and click **Always Allow**.")
                }
            case .renew:
                step(3) { Text("Type **/usage** and press Return. Once your usage shows, the sign-in is renewed.") }
                step(4) { Text("Close Terminal.") }
            }

            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text(isChecking ? "Checking…" : "PaceBar continues on its own when you're done.")
                    .font(.system(size: 10))
                    .foregroundStyle(textColor.opacity(0.45))
                Spacer()
                Button("Check now", action: onCheckNow)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(textColor.opacity(isChecking ? 0.3 : 0.8))
                    .disabled(isChecking)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    private func step(_ number: Int, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(textColor.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.1)))
            content()
                .font(.system(size: 11))
                .foregroundStyle(textColor.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyAndOpenTerminal(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        NSWorkspace.shared.openApplication(at: Self.terminalURL, configuration: NSWorkspace.OpenConfiguration())
        Task {
            try? await Task.sleep(for: .seconds(4))
            copied = false
        }
    }
}
