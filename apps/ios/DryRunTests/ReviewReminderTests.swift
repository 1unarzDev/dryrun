import XCTest
@testable import DryRun

@MainActor
private final class ReminderSchedulerFake: ReviewReminderScheduling {
    var date: Date?
    var failure: ReviewReminderError?
    var writes = 0
    var cancellations = 0
    func pendingDate() async -> Date? { date }
    func schedule(at date: Date, title: String, body: String, isCurrent: @escaping @MainActor () -> Bool) async throws {
        writes += 1
        if let failure { throw failure }
        self.date = date
    }
    func cancel() { cancellations += 1; date = nil }
}

@MainActor
private final class SuspendedNotificationAccess: ReviewNotificationAccess {
    var date: Date?
    var suspendAdd = false
    var authorization: CheckedContinuation<Void, Never>?
    var addition: CheckedContinuation<Void, Never>?
    var writes = 0
    var cancellations = 0
    func pendingDate() async -> Date? { date }
    func authorize() async throws {
        if !suspendAdd { await withCheckedContinuation { authorization = $0 } }
    }
    func add(at date: Date, title: String, body: String) async throws {
        writes += 1
        if suspendAdd { await withCheckedContinuation { addition = $0 } }
        self.date = date
    }
    func cancel() { cancellations += 1; date = nil }
}

/// Authored native tests; they do not verify the system authorization dialog or notification delivery.
@MainActor
final class ReviewReminderTests: XCTestCase {
    func testScopeChangeDuringAuthorizationIsRejectedBeforeViewCancellation() async {
        let access = SuspendedNotificationAccess()
        let scheduler = LocalReviewReminderScheduler(access: access)
        var currentScope = "personal"
        let task = Task {
            try await scheduler.schedule(at: Date().addingTimeInterval(3600), title: "Review", body: "Plan",
                                         isCurrent: { currentScope == "personal" })
        }
        while access.authorization == nil { await Task.yield() }
        currentScope = "example"
        access.authorization?.resume()
        do { try await task.value; XCTFail("Changed scope must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(access.writes, 0)
        XCTAssertEqual(access.cancellations, 0)
    }

    func testScopeCancellationDuringAuthorizationPreservesExistingReminder() async {
        let access = SuspendedNotificationAccess()
        let existing = Date(timeIntervalSince1970: 2_000_000_000)
        access.date = existing
        let scheduler = LocalReviewReminderScheduler(access: access)
        let task = Task { try await scheduler.schedule(at: existing.addingTimeInterval(3600), title: "Review", body: "Plan") }
        while access.authorization == nil { await Task.yield() }
        task.cancel()
        access.authorization?.resume()
        do { try await task.value; XCTFail("Cancelled scope must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(access.writes, 0)
        XCTAssertEqual(access.cancellations, 0)
        XCTAssertEqual(access.date, existing)
    }

    func testScopeCancellationDuringAddRemovesLateRequest() async {
        let access = SuspendedNotificationAccess(); access.suspendAdd = true
        let scheduler = LocalReviewReminderScheduler(access: access)
        let task = Task { try await scheduler.schedule(at: Date().addingTimeInterval(3600), title: "Review", body: "Plan") }
        while access.addition == nil { await Task.yield() }
        task.cancel()
        access.addition?.resume()
        do { try await task.value; XCTFail("Cancelled scope must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertNil(access.date)
        XCTAssertEqual(access.cancellations, 1)
    }

    func testDeleteDuringAuthorizationCannotScheduleLateReminder() async {
        let access = SuspendedNotificationAccess()
        let scheduler = LocalReviewReminderScheduler(access: access)
        let task = Task { try await scheduler.schedule(at: Date().addingTimeInterval(3600), title: "Review", body: "Plan") }
        while access.authorization == nil { await Task.yield() }
        scheduler.cancel() // Same shared scheduler called by successful Delete Everything.
        access.authorization?.resume()
        do { try await task.value; XCTFail("Deleted request must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(access.writes, 0)
        XCTAssertNil(access.date)
    }

    func testDeleteDuringAddRemovesLatePendingRequest() async {
        let access = SuspendedNotificationAccess(); access.suspendAdd = true
        let scheduler = LocalReviewReminderScheduler(access: access)
        let task = Task { try await scheduler.schedule(at: Date().addingTimeInterval(3600), title: "Review", body: "Plan") }
        while access.addition == nil { await Task.yield() }
        scheduler.cancel()
        access.addition?.resume()
        do { try await task.value; XCTFail("Deleted request must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(access.writes, 1)
        XCTAssertEqual(access.cancellations, 2)
        XCTAssertNil(access.date)
    }

    func testOpeningReviewOnlyReadsExistingReminder() async {
        let scheduler = ReminderSchedulerFake()
        scheduler.date = Date(timeIntervalSince1970: 2_000_000_000)
        let model = ReviewReminderModel(scheduler: scheduler)
        await model.refresh()
        XCTAssertEqual(model.scheduledDate, scheduler.date)
        XCTAssertEqual(scheduler.writes, 0)
        XCTAssertEqual(scheduler.cancellations, 0)
    }

    func testDeniedChangeRetainsExistingReminderAndReportsFailure() async {
        let scheduler = ReminderSchedulerFake()
        let existing = Date(timeIntervalSince1970: 2_000_000_000)
        scheduler.date = existing
        let model = ReviewReminderModel(scheduler: scheduler)
        await model.refresh()
        scheduler.failure = .permissionDenied
        await model.schedule(at: existing.addingTimeInterval(3600), title: "Review your plan", body: "Review recorded information")
        XCTAssertEqual(model.scheduledDate, existing)
        XCTAssertEqual(model.messageKey, "reminder.denied")
        XCTAssertFalse(model.isWorking)
    }

    func testExplicitScheduleAndCancelUpdateRecordedState() async {
        let scheduler = ReminderSchedulerFake()
        let model = ReviewReminderModel(scheduler: scheduler)
        let selected = Date(timeIntervalSince1970: 2_000_000_000)
        await model.schedule(at: selected, title: "Review your plan", body: "Review recorded information")
        XCTAssertEqual(model.scheduledDate, selected)
        XCTAssertEqual(scheduler.writes, 1)
        model.cancel()
        XCTAssertNil(model.scheduledDate)
        XCTAssertEqual(scheduler.cancellations, 1)
        XCTAssertEqual(model.messageKey, "reminder.removed")
    }
}
