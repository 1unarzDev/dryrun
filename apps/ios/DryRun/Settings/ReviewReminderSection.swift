import SwiftUI

/// Embedded in the existing settings/review forms; no additional sheet or setup prerequisite.
struct ReviewReminderSection: View {
    @Environment(AppModel.self) private var model
    @State private var reminder = ReviewReminderModel()
    @State private var chosenDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    var body: some View {
        let l = model.localizer
        Section(l("reminder.title")) {
            Text(l("reminder.optional")).font(.footnote)
            if let date = reminder.scheduledDate {
                LabeledContent(l("reminder.current")) { Text(date, format: .dateTime.year().month().day().hour().minute()) }
            }
            DatePicker(l("reminder.date"), selection: $chosenDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            Button(l("reminder.schedule")) {
                Task { await reminder.schedule(at: chosenDate, title: l("reminder.notificationTitle"), body: l("reminder.notificationBody")) }
            }.disabled(reminder.isWorking).accessibilityIdentifier("review.scheduleReminder")
            if reminder.scheduledDate != nil {
                Button(l("reminder.cancel"), role: .destructive) { reminder.cancel() }
                    .disabled(reminder.isWorking).accessibilityIdentifier("review.cancelReminder")
            }
            if reminder.isWorking { ProgressView() }
            if let key = reminder.messageKey { Text(l(key)).font(.footnote).accessibilityIdentifier("review.reminderStatus") }
        }
        .task { await reminder.refresh(); if let existing = reminder.scheduledDate { chosenDate = existing } }
    }
}
