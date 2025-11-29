import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import UIKit

// MARK: - Notification Manager
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var fcmToken: String?
    @Published var isNotificationsEnabled = false

    private let db = Firestore.firestore()

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isNotificationsEnabled = granted
                if granted {
                    print("🟢 [NOTIFICATIONS] Permission granted")
                    self.registerForRemoteNotifications()
                } else {
                    print("🔴 [NOTIFICATIONS] Permission denied: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    private func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Token Management

    func saveFCMToken(_ token: String) {
        self.fcmToken = token
        let currentUser = UserIdentityManager.shared.currentUserName

        // Save token to Firestore for this user
        let tokenData: [String: Any] = [
            "token": token,
            "user": currentUser,
            "updatedAt": FieldValue.serverTimestamp(),
            "platform": "iOS"
        ]

        db.collection("deviceTokens").document(currentUser).setData(tokenData) { error in
            if let error = error {
                print("🔴 [NOTIFICATIONS] Failed to save token: \(error.localizedDescription)")
            } else {
                print("🟢 [NOTIFICATIONS] Token saved for \(currentUser)")
            }
        }
    }

    // MARK: - Send Notifications (via Firestore trigger)
    // These methods create notification documents that Cloud Functions will process

    func notifyEventCreated(event: CalendarEvent) {
        let currentUser = UserIdentityManager.shared.currentUserName

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "event_created",
                "title": "New Event",
                "body": "\(currentUser) created a new event: \(event.title)",
                "recipient": recipient,
                "sender": currentUser,
                "eventId": event.id ?? "",
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued event created notification for both users")
    }

    func notifyEventEdited(event: CalendarEvent) {
        let currentUser = UserIdentityManager.shared.currentUserName

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "event_edited",
                "title": "Event Updated",
                "body": "\(currentUser) updated the event: \(event.title)",
                "recipient": recipient,
                "sender": currentUser,
                "eventId": event.id ?? "",
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued event edited notification for both users")
    }

    func notifyEventReminder(event: CalendarEvent, hoursUntil: Int) {
        // Schedule reminder for both users
        let reminderText = hoursUntil == 24 ? "tomorrow" : "in 2 hours"

        for user in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "event_reminder",
                "title": "Event Reminder",
                "body": "\(event.title) is \(reminderText)",
                "recipient": user,
                "sender": "System",
                "eventId": event.id ?? "",
                "scheduledFor": event.date.addingTimeInterval(TimeInterval(-hoursUntil * 3600)),
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("scheduledNotifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Scheduled event reminders for both users")
    }

    func notifyPhotosAdded(count: Int, location: String, eventId: String? = nil) {
        let currentUser = UserIdentityManager.shared.currentUserName

        let photoText = count == 1 ? "photo was" : "photos were"
        let body: String

        if let eventId = eventId, !eventId.isEmpty {
            body = "\(count) \(photoText) added to \(location) by \(currentUser)"
        } else {
            body = "\(count) \(photoText) added to the gallery by \(currentUser)"
        }

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "photos_added",
                "title": "New Photos",
                "body": body,
                "recipient": recipient,
                "sender": currentUser,
                "photoCount": count,
                "eventId": eventId ?? "",
                "isEventPhoto": eventId != nil && !eventId!.isEmpty,
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued photos added notification for both users")
    }

    func notifyVoiceMemoCreated(memo: VoiceMessage) {
        let currentUser = UserIdentityManager.shared.currentUserName

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "voice_memo_created",
                "title": "New Voice Memo",
                "body": "\(currentUser) recorded a new voice memo: \(memo.title)",
                "recipient": recipient,
                "sender": currentUser,
                "memoId": memo.id ?? "",
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued voice memo notification for both users")
    }

    // MARK: - Wishlist Notifications

    func notifyWishAdded(item: WishListItem, category: String) {
        let currentUser = UserIdentityManager.shared.currentUserName

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "wish_added",
                "title": "New Wish Added",
                "body": "\(currentUser) added '\(item.title)' to \(category)",
                "recipient": recipient,
                "sender": currentUser,
                "wishId": item.id ?? "",
                "category": category,
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued wish added notification for both users")
    }

    func notifyWishPlanned(item: WishListItem, plannedDate: Date) {
        let currentUser = UserIdentityManager.shared.currentUserName
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: plannedDate)

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "wish_planned",
                "title": "Wish Planned",
                "body": "\(currentUser) scheduled '\(item.title)' for \(dateString)",
                "recipient": recipient,
                "sender": currentUser,
                "wishId": item.id ?? "",
                "plannedDate": plannedDate,
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued wish planned notification for both users")
    }

    func notifyWishCompleted(item: WishListItem) {
        let currentUser = UserIdentityManager.shared.currentUserName

        // Send to both users
        for recipient in ["Ahmad", "Luisa"] {
            let notification: [String: Any] = [
                "type": "wish_completed",
                "title": "Wish Completed! 🎉",
                "body": "\(currentUser) completed '\(item.title)'",
                "recipient": recipient,
                "sender": currentUser,
                "wishId": item.id ?? "",
                "category": item.category,
                "createdAt": FieldValue.serverTimestamp(),
                "processed": false
            ]

            db.collection("notifications").addDocument(data: notification)
        }
        print("🔔 [NOTIFICATIONS] Queued wish completed notification for both users")
    }

    // MARK: - Schedule Local Reminders for Events

    func scheduleEventReminders(for event: CalendarEvent) {
        guard let eventId = event.id else { return }

        let center = UNUserNotificationCenter.current()

        // Remove any existing reminders for this event
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(eventId)-1day",
            "\(eventId)-2hours"
        ])

        // 1 day before
        let oneDayBefore = event.date.addingTimeInterval(-24 * 60 * 60)
        if oneDayBefore > Date() {
            scheduleLocalNotification(
                identifier: "\(eventId)-1day",
                title: "Event Tomorrow",
                body: "\(event.title) is tomorrow",
                date: oneDayBefore
            )
        }

        // 2 hours before
        let twoHoursBefore = event.date.addingTimeInterval(-2 * 60 * 60)
        if twoHoursBefore > Date() {
            scheduleLocalNotification(
                identifier: "\(eventId)-2hours",
                title: "Event Soon",
                body: "\(event.title) is in 2 hours",
                date: twoHoursBefore
            )
        }

        print("🔔 [NOTIFICATIONS] Scheduled local reminders for event: \(event.title)")
    }

    private func scheduleLocalNotification(identifier: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔴 [NOTIFICATIONS] Failed to schedule: \(error.localizedDescription)")
            }
        }
    }

    func cancelEventReminders(for eventId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "\(eventId)-1day",
            "\(eventId)-2hours"
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        print("🔔 [NOTIFICATIONS] User tapped notification: \(userInfo)")
        completionHandler()
    }
}

// MARK: - MessagingDelegate
extension NotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🟢 [NOTIFICATIONS] FCM Token: \(token)")
        saveFCMToken(token)
    }
}
