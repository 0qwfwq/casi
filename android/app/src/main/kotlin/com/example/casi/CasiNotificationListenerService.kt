package com.example.casi

import android.app.Notification
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

class CasiNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val PREFS_NAME = "casi_notifications"
        private const val KEY_NOTIFICATIONS = "captured_notifications"
        private const val MAX_NOTIFICATIONS = 100
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val packageName = sbn.packageName ?: return

        // Skip our own notifications and system UI
        if (packageName == "com.example.casi") return
        if (packageName == "android" || packageName == "com.android.systemui") return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        // Skip empty notifications
        if (title.isBlank() && text.isBlank()) return

        // Build notification JSON
        val notifJson = JSONObject().apply {
            put("packageName", packageName)
            put("title", title)
            put("text", text)
            put("bigText", bigText)
            put("subText", subText)
            put("timestamp", sbn.postTime)
            put("key", sbn.key ?: "")
            put("category", notification.category ?: "")
        }

        saveNotification(notifJson)
    }

    private fun saveNotification(notifJson: JSONObject) {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val existing = prefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"

        val array = try {
            JSONArray(existing)
        } catch (e: Exception) {
            JSONArray()
        }

        // Deduplicate: skip if same package+title+text already exists within last 5 minutes
        val newPkg = notifJson.optString("packageName")
        val newTitle = notifJson.optString("title")
        val newText = notifJson.optString("text")
        val newTimestamp = notifJson.optLong("timestamp")
        val fiveMinutes = 5 * 60 * 1000L

        for (i in 0 until array.length()) {
            val existing_item = array.optJSONObject(i) ?: continue
            if (existing_item.optString("packageName") == newPkg &&
                existing_item.optString("title") == newTitle &&
                existing_item.optString("text") == newText &&
                (newTimestamp - existing_item.optLong("timestamp")) < fiveMinutes) {
                return // Duplicate, skip
            }
        }

        array.put(notifJson)

        // Trim to max size (keep most recent)
        while (array.length() > MAX_NOTIFICATIONS) {
            array.remove(0)
        }

        prefs.edit().putString(KEY_NOTIFICATIONS, array.toString()).apply()
    }
}
