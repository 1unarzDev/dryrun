import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor
protocol ReviewReminderScheduling {
    func pendingDate() async -> Date?
    func schedule(at date: Date, title: String, body: String, isCurrent: @escaping @MainActor () -> Bool) async throws
    func cancel()
}

enum ReviewReminderError: Error { case permissionDenied, invalidDate }

/// Injectable system boundary so delete-during-authorization/add can be tested without a permission dialog.
@MainActor
protocol ReviewNotificationAccess {
    func pendingDate() async -> Date?
    func authorize() async throws
    func add(at date: Date, title: String, body: String) async throws
    func cancel()
}

@MainActor
struct SystemReviewNotificationAccess: ReviewNotificationAccess {
    static let identifier = "dryrun.review-plan"
    private let center = UNUserNotificationCenter.current()

    func pendingDate() async -> Date? {
        let identifier = Self.identifier
        return await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let trigger = requests.first(where: { $0.identifier == identifier })?.trigger as? UNCalendarNotificationTrigger
                continuation.resume(returning: trigger?.nextTriggerDate())
            }
        }
    }

    func authorize() async throws {
        let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
        }
        if status == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw ReviewReminderError.permissionDenied }
        } else if status != .authorized && status != .provisional && status != .ephemeral {
            throw ReviewReminderError.permissionDenied
        }
    }

    func add(at date: Date, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        // No userInfo, contact, medical, address, geometry, account or public-service request.
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        guard let next = trigger.nextTriggerDate(), next > Date() else { throw ReviewReminderError.invalidDate }
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

/// Shared across forms and Delete Everything. An old permission/add callback cannot resurrect a deleted reminder.
@MainActor
final class LocalReviewReminderScheduler: ReviewReminderScheduling {
    static let shared = LocalReviewReminderScheduler()
    private let access: any ReviewNotificationAccess
    private var generation = 0
    private var isScheduling = false

    init(access: any ReviewNotificationAccess = SystemReviewNotificationAccess()) { self.access = access }
    func pendingDate() async -> Date? { await access.pendingDate() }
    func schedule(at date: Date, title: String, body: String, isCurrent: @escaping @MainActor () -> Bool = { true }) async throws {
        guard !isScheduling, isCurrent(), !Task.isCancelled else { throw CancellationError() }
        guard date > Date(), date.timeIntervalSince1970.isFinite else { throw ReviewReminderError.invalidDate }
        isScheduling = true; defer { isScheduling = false }
        generation += 1
        let ticket = generation
        try await access.authorize()
        guard ticket == generation, !Task.isCancelled, isCurrent() else { throw CancellationError() }
        do { try await access.add(at: date, title: title, body: body) }
        catch {
            if ticket != generation || Task.isCancelled { access.cancel() }
            throw error
        }
        guard ticket == generation, !Task.isCancelled, isCurrent() else { access.cancel(); throw CancellationError() }
    }
    func cancel() { generation += 1; access.cancel() }
}

/// Read-only refresh never requests permission or schedules work. Writes happen only from an explicit control.
@MainActor
@Observable
final class ReviewReminderModel {
    private let scheduler: any ReviewReminderScheduling
    private(set) var scheduledDate: Date?
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private var generation = 0

    init(scheduler: any ReviewReminderScheduling = LocalReviewReminderScheduler.shared) { self.scheduler = scheduler }
    func refresh() async {
        let ticket = generation
        let pending = await scheduler.pendingDate()
        if ticket == generation { scheduledDate = pending }
    }

    func schedule(at date: Date, title: String, body: String, isCurrent: @escaping @MainActor () -> Bool = { true }) async {
        guard !isWorking, isCurrent(), !Task.isCancelled else { return }
        generation += 1
        isWorking = true; defer { isWorking = false }
        do {
            try await scheduler.schedule(at: date, title: title, body: body, isCurrent: isCurrent)
            guard !Task.isCancelled, isCurrent() else { return }
            scheduledDate = await scheduler.pendingDate()
            guard !Task.isCancelled, isCurrent() else { return }
            messageKey = "reminder.saved"
        } catch ReviewReminderError.permissionDenied { messageKey = "reminder.denied" }
        catch ReviewReminderError.invalidDate { messageKey = "reminder.invalidDate" }
        catch { messageKey = "reminder.failed" }
        guard !Task.isCancelled, isCurrent() else { return }
        if messageKey != "reminder.saved" { scheduledDate = await scheduler.pendingDate() }
    }

    func cancel() {
        guard !isWorking else { return }
        generation += 1
        scheduler.cancel(); scheduledDate = nil; messageKey = "reminder.removed"
    }
}
