// Domain/CI/SystemCIRunNotifier.swift
// Grove
//
// "CI #12 failed" in Notification Center; clicking it opens the run.

import AppKit
import GroveKit
import UserNotifications

final class SystemCIRunNotifier: NSObject, CIRunNotifying, UNUserNotificationCenterDelegate {

    private static let pathKey = "repositoryPath"
    private static let runKey = "runID"

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notify(_ run: CIRun, repositoryPath: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(run.workflowName) #\(run.number) \(Self.outcome(run.status))"
        let repository = URL(fileURLWithPath: repositoryPath).lastPathComponent
        content.subtitle = run.branch.map { "\(repository) \u{00B7} \($0)" } ?? repository
        content.body = run.title
        content.sound = .default
        content.userInfo = [Self.pathKey: repositoryPath, Self.runKey: run.id]
        center.add(UNNotificationRequest(identifier: "ci-run-\(run.id)-\(run.attempt)", content: content, trigger: nil))
    }

    nonisolated static func outcome(_ status: CIRunStatus) -> String {
        switch status {
        case .success: "passed"
        case .failure: "failed"
        case .cancelled: "was cancelled"
        case .skipped: "was skipped"
        case .queued, .inProgress, .neutral: "finished"
        }
    }

    // Shown even while Grove is frontmost: the run usually finishes while another tab is up.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let path = info[Self.pathKey] as? String, let runID = info[Self.runKey] as? Int else { return }
        await MainActor.run {
            NSApp.activate()
            CIRunWatcher.shared.reveal(runID: runID, in: path)
        }
    }
}

extension GroveAppDelegate {
    /// Claims the notification delegate at launch, so a click that launched Grove still reaches it.
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = CIRunWatcher.shared
    }
}
