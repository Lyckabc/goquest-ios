import BackgroundTasks
import Foundation
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "BGSync")

/// Coordinates `BGAppRefreshTask` registration + scheduling for the calendar
/// sync feature. The actual sync logic lives in `CalendarSyncService`; this
/// type only deals with the OS-level scheduling lifecycle.
///
/// Flow:
///   1. `register()` is called once at app launch, before
///      `UIApplication.applicationDidFinishLaunching` returns.
///   2. When the user enables sync (or hits Sync now), `scheduleNextRefresh()`
///      submits a request for ~1h later.
///   3. The system fires `runRefresh(task:)` at its discretion (battery,
///      network, foreground recency); the handler chains the next request.
///
/// Apple guarantees neither cadence nor wall-clock accuracy — BGAppRefreshTask
/// is a best-effort, ~30s-budgeted slot. For deterministic updates we will
/// later add a silent-push path (Phase B) and treat BG refresh as the safety
/// net for users who disable push.
@MainActor
final class BackgroundCalendarSync {
    static let shared = BackgroundCalendarSync()

    static let taskIdentifier = "home.toji.goquest.calendar-sync"
    private let minimumInterval: TimeInterval = 60 * 60 // 1 hour
    private var didRegister = false

    /// MUST be called before app finish-launching returns.
    func register() {
        guard !didRegister else { return }
        didRegister = true
        let ok = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.runRefresh(task: refresh)
            }
        }
        log.info("BGTaskScheduler register: \(ok, privacy: .public)")
    }

    /// Submits the next refresh request. Idempotent — replaces any pending
    /// request for the same identifier.
    func scheduleNextRefresh() {
        guard CalendarSyncService.shared.prefs.isEnabled else {
            log.info("scheduleNextRefresh: sync disabled, skipping")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("BGAppRefreshTaskRequest submitted earliestBeginDate=\(request.earliestBeginDate?.description ?? "?", privacy: .public)")
        } catch {
            log.error("BGTaskScheduler.submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancel any pending refresh — called when the user toggles sync off so
    /// we do not silently wake the network later.
    func cancelPendingRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        log.info("cancelled pending refresh")
    }

    // MARK: - Task handler

    private func runRefresh(task: BGAppRefreshTask) async {
        // Always chain the next refresh first — if our sync hangs or the
        // system cancels us early, the queue still has a successor.
        scheduleNextRefresh()

        let started = Date()
        let syncTask = Task { [weak self] () -> Int in
            guard self != nil else { return 0 }
            return try await CalendarSyncService.shared.syncAllWorkspaces()
        }
        task.expirationHandler = {
            log.error("BG refresh expired by system, cancelling sync")
            syncTask.cancel()
        }

        do {
            let count = try await syncTask.value
            let dt = Date().timeIntervalSince(started)
            log.info("BG refresh synced \(count, privacy: .public) workspaces in \(dt, privacy: .public)s")
            task.setTaskCompleted(success: true)
        } catch is CancellationError {
            task.setTaskCompleted(success: false)
        } catch {
            log.error("BG refresh failed: \(error.localizedDescription, privacy: .public)")
            task.setTaskCompleted(success: false)
        }
    }
}
