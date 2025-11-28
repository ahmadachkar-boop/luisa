const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

/**
 * Cloud Function: Send push notification when a notification document is created
 * Listens to the 'notifications' collection
 */
exports.sendPushNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const snap = event.data;
  if (!snap) {
    console.log("No data associated with the event");
    return null;
  }

  const notification = snap.data();
  const notificationId = event.params.notificationId;

  console.log(`Processing notification ${notificationId}:`, notification);

  // Skip if already processed
  if (notification.processed) {
    console.log("Notification already processed, skipping");
    return null;
  }

  try {
    // Get the recipient's FCM token
    const recipient = notification.recipient;
    const tokenDoc = await db.collection("deviceTokens").doc(recipient).get();

    if (!tokenDoc.exists) {
      console.log(`No device token found for ${recipient}`);
      await snap.ref.update({processed: true, error: "No device token"});
      return null;
    }

    const tokenData = tokenDoc.data();
    const fcmToken = tokenData.token;

    if (!fcmToken) {
      console.log(`Empty FCM token for ${recipient}`);
      await snap.ref.update({processed: true, error: "Empty token"});
      return null;
    }

    // Build the FCM message
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        type: notification.type || "",
        eventId: notification.eventId || "",
        memoId: notification.memoId || "",
        sender: notification.sender || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      token: fcmToken,
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    // Send the notification
    const response = await messaging.send(message);
    console.log(`Successfully sent notification to ${recipient}:`, response);

    // Mark as processed
    await snap.ref.update({processed: true, sentAt: FieldValue.serverTimestamp()});

    return response;
  } catch (error) {
    console.error(`Error sending notification to ${notification.recipient}:`, error);
    await snap.ref.update({processed: true, error: error.message});
    return null;
  }
});

/**
 * Cloud Function: Process scheduled notifications
 * Runs every 15 minutes to check for notifications that should be sent
 */
exports.processScheduledNotifications = onSchedule("every 15 minutes", async (event) => {
  const now = Timestamp.now();

  try {
    // Query for scheduled notifications that are due
    const query = await db.collection("scheduledNotifications")
        .where("processed", "==", false)
        .where("scheduledFor", "<=", now)
        .get();

    console.log(`Found ${query.size} scheduled notifications to process`);

    const batch = db.batch();

    query.forEach((doc) => {
      const notification = doc.data();

      // Copy to notifications collection to trigger sendPushNotification
      const newNotificationRef = db.collection("notifications").doc();
      batch.set(newNotificationRef, {
        type: notification.type,
        title: notification.title,
        body: notification.body,
        recipient: notification.recipient,
        sender: notification.sender,
        eventId: notification.eventId || "",
        createdAt: FieldValue.serverTimestamp(),
        processed: false,
      });

      // Mark scheduled notification as processed
      batch.update(doc.ref, {processed: true});
    });

    if (query.size > 0) {
      await batch.commit();
      console.log(`Processed ${query.size} scheduled notifications`);
    }

    return null;
  } catch (error) {
    console.error("Error processing scheduled notifications:", error);
    return null;
  }
});

/**
 * Cloud Function: Clean up old notifications (older than 30 days)
 * Runs daily at midnight
 */
exports.cleanupOldNotifications = onSchedule({
  schedule: "every day 00:00",
  timeZone: "America/New_York",
}, async (event) => {
  const thirtyDaysAgo = Timestamp.fromDate(
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
  );

  try {
    // Delete old notifications
    const oldNotifications = await db.collection("notifications")
        .where("createdAt", "<", thirtyDaysAgo)
        .get();

    const oldScheduled = await db.collection("scheduledNotifications")
        .where("createdAt", "<", thirtyDaysAgo)
        .get();

    const batch = db.batch();

    oldNotifications.forEach((doc) => batch.delete(doc.ref));
    oldScheduled.forEach((doc) => batch.delete(doc.ref));

    const totalDeleted = oldNotifications.size + oldScheduled.size;

    if (totalDeleted > 0) {
      await batch.commit();
      console.log(`Cleaned up ${totalDeleted} old notifications`);
    }

    return null;
  } catch (error) {
    console.error("Error cleaning up notifications:", error);
    return null;
  }
});
