package com.example.casi

import android.service.notification.NotificationListenerService

// This service is intentionally left empty!
// By simply registering and binding this service in the AndroidManifest,
// Android grants our MainActivity permission to access MediaSessionManager.getActiveSessions().
class CasiNotificationListenerService : NotificationListenerService() {
    
    override fun onListenerConnected() {
        super.onListenerConnected()
    }
    
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
    }
}