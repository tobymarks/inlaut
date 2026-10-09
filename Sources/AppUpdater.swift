import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns scheduling, version comparison, signature verification and
/// installation. This adapter only connects its state to the menu/settings.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    #if DEBUG
    let isEnabled = false
    #else
    let isEnabled = true
    #endif
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published var isBusy = false {
        didSet {
            guard !isBusy else { return }
            if let install = pendingInstall {
                pendingInstall = nil
                install()
            } else if deferredPresentation {
                deferredPresentation = false
                controller.checkForUpdates(nil)
            }
        }
    }
    private var controller: SPUStandardUpdaterController!
    private var pendingInstall: (() -> Void)?
    private var deferredPresentation = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                 updaterDelegate: self, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        // Tests and development builds must not replace themselves with a
        // public release or change the user's update preferences.
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isEnabled else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBusy { throw EngineError("Please finish the dictation first.") }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy else { return false }
        pendingInstall = installHandler
        return true
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        !isBusy
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        deferredPresentation = !handleShowingUpdate
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        deferredPresentation = false
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button(updater.availableVersion.map { String(localized: "Update to \($0) Available …") }
               ?? String(localized: "Check for Updates …")) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates || updater.isBusy)
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            ))
            .disabled(!updater.isEnabled)
            CheckForUpdatesButton(updater: updater)
        } header: {
            Text("Updates")
        } footer: {
            Text(updater.isEnabled
                 ? "Checks for new versions daily. You start the download and installation yourself. No dictations are ever sent."
                 : "Updates are disabled in this development build.")
                .foregroundStyle(.secondary)
        }
    }
}
