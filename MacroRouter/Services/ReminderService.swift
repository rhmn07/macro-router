import Foundation
import UserNotifications
import MacroCore

/// Local notifications at meal times listing what to eat, for the days left in the current week.
enum ReminderService {
    private static let prefix = "meal-"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func schedule(week: WeekPlan?, settings: ReminderSettings, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard settings.enabled, let week else { return }

        let calendar = Calendar.current
        for (day, plan) in week.days.enumerated() {
            for meal in plan.meals ?? [] where !meal.items.isEmpty && !week.isEaten(day: day, slot: meal.slot) {
                let minutes = settings.minutes(for: meal.slot)
                guard let date = calendar.date(byAdding: .minute, value: minutes, to: week.date(ofDay: day)),
                      date > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(meal.slot.emoji) \(meal.slot.displayName): \(MealRecipe.name(for: meal))"
                content.body = meal.items.map { "\($0.pieceText ?? GroceryList.formatWeight(grams: $0.grams)) \($0.ingredient.shortName.lowercased())" }
                    .joined(separator: ", ")
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let request = UNNotificationRequest(identifier: "\(prefix)\(week.id)-\(day)-\(meal.slot.rawValue)",
                                                    content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
            }
        }
    }
}
