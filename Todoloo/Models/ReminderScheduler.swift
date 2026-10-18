import Foundation
import SwiftUI
import UserNotifications
import OSLog

struct TaskReminder: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let fireDate: Date

    var body: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: start)
        return "Starts at \(TodoItem.timeLabel((components.hour ?? 0) * 60 + (components.minute ?? 0))) · in 15 minutes"
    }

    func request() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["start": start.timeIntervalSince1970, "fire": fireDate.timeIntervalSince1970]
        // An absolute UTC trigger disambiguates the repeated hour when daylight saving ends.
        // The app reconciles local task times again when the Mac's time zone changes or it reopens.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.calendar = utc
        components.timeZone = utc.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    func matches(_ existing: UNNotificationRequest) -> Bool {
        let desired = request()
        return existing.identifier == id
            && existing.content.title == desired.content.title
            && existing.content.body == desired.content.body
            && (existing.content.userInfo["fire"] as? Double) == fireDate.timeIntervalSince1970
            && (existing.content.userInfo["start"] as? Double) == start.timeIntervalSince1970
            && (existing.trigger as? UNCalendarNotificationTrigger)?.dateComponents
                == (desired.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            && existing.trigger?.repeats == false
    }
}

@MainActor
final class ReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var bannersEnabled = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var scheduledIDs: Set<String> = []
    @Published private(set) var testStatus: String?
    let isPreview: Bool
    private var center: UNUserNotificationCenter?
    private var latestPlans: [TaskReminder] = []
    private var revision = 0
    private var worker: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.todoloo.app", category: "Reminders")

    override init() {
        isPreview = ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        super.init()
        logger.debug("Reminder scheduler initialized; preview: \(self.isPreview)")
        if !isPreview {
            let center = UNUserNotificationCenter.current()
            self.center = center
            center.delegate = self
        }
    }

    // One worker drains the newest snapshot so a slow add cannot outlive a later deletion/reschedule.
    func update(_ plans: [TaskReminder]) {
        logger.debug("Updating reminders: \(plans.count) plans, worker active: \(self.worker != nil)")
        latestPlans = plans
        revision += 1
        guard worker == nil, !isPreview else { return }
        worker = Task {
            // Coalesce quick typing and picker edits into one update to the system notification service.
            try? await Task.sleep(for: .milliseconds(250))
            var handledRevision: Int
            repeat {
                handledRevision = revision
                await reconcile(latestPlans)
            } while handledRevision != revision
            worker = nil
        }
    }

    private func reconcile(_ plans: [TaskReminder]) async {
        guard let center else { return }
        logger.debug("Reading notification settings")
        if errorMessage != nil { errorMessage = nil }
        var settings = await center.notificationSettings()
        logger.debug("Notification authorization: \(settings.authorizationStatus.rawValue)")
        if settings.authorizationStatus == .notDetermined && !plans.isEmpty {
            logger.debug("Requesting notification authorization")
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { errorMessage = "Couldn’t enable reminders: \(error.localizedDescription)" }
            settings = await center.notificationSettings()
        }
        if authorization != settings.authorizationStatus { authorization = settings.authorizationStatus }
        let canShowBanners = settings.alertSetting == .enabled && settings.alertStyle != .none
        if bannersEnabled != canShowBanners { bannersEnabled = canShowBanners }
        let allowed = authorization == .authorized || authorization == .provisional
        let desired = allowed ? plans.filter { $0.fireDate > .now } : []
        let desiredIDs = Set(desired.map(\.id))
        let pending = await center.pendingNotificationRequests()
        let pendingByID = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { _, newer in newer })
        let plansByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        let stale = pending.filter { $0.identifier.hasPrefix("todoloo.task.") && !desiredIDs.contains($0.identifier) }.map(\.identifier)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        // Clear old delivered reminders after a task is completed, removed, or rescheduled.
        let delivered = await center.deliveredNotifications()
        let obsoleteDelivered = delivered.filter {
            let notification = $0
            guard notification.request.identifier.hasPrefix("todoloo.task.") else { return false }
            guard let plan = plansByID[notification.request.identifier] else { return true }
            return (notification.request.content.userInfo["start"] as? Double) != plan.start.timeIntervalSince1970
        }.map { $0.request.identifier }
        if !obsoleteDelivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: obsoleteDelivered) }
        for plan in desired {
            if let existing = pendingByID[plan.id], plan.matches(existing) {
                continue
            }
            do { try await center.add(plan.request()) }
            catch { errorMessage = "Couldn’t schedule a reminder: \(error.localizedDescription)" }
        }
        let registeredIDs = Set(await center.pendingNotificationRequests().map(\.identifier))
        if scheduledIDs != registeredIDs { scheduledIDs = registeredIDs }
    }

    func sendTestReminder() async {
        guard let center, authorization == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Todoloo reminders are ready"
        content.body = "Your scheduled tasks will remind you 15 minutes before they start."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "todoloo.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            testStatus = "Test reminder scheduled in 5 seconds."
        } catch {
            testStatus = "Couldn’t send the test: \(error.localizedDescription)"
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
