package com.example.casi

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.provider.Settings
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "casi.launcher/media"
    private val APP_CHANNEL = "casi.launcher/apps"
    private val NOTIF_CHANNEL = "casi.launcher/notifications"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- Notifications Channel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotifications" -> {
                    val prefs = getSharedPreferences("casi_notifications", MODE_PRIVATE)
                    val json = prefs.getString("captured_notifications", "[]") ?: "[]"
                    result.success(json)
                }
                "clearNotifications" -> {
                    val prefs = getSharedPreferences("casi_notifications", MODE_PRIVATE)
                    prefs.edit().putString("captured_notifications", "[]").apply()
                    result.success(null)
                }
                "isNotificationAccessGranted" -> {
                    val componentName = ComponentName(this, CasiNotificationListenerService::class.java)
                    val flat = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val enabled = flat != null && flat.contains(componentName.flattenToString())
                    result.success(enabled)
                }
                "getActiveNotifications" -> {
                    val service = CasiNotificationListenerService.instance
                    if (service != null) {
                        result.success(service.getActiveNotifs())
                    } else {
                        result.success("[]")
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                        if (intent != null) {
                            startActivity(intent)
                            @Suppress("DEPRECATION")
                            overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            when (call.method) {
                "getMetadata" -> {
                    val controller = getActiveMediaController()
                    if (controller == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val metadata = controller.metadata
                    val playbackState = controller.playbackState

                    val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                    val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
                    val position = playbackState?.position ?: 0L
                    val packageName = controller.packageName

                    // Convert Bitmap Album Art to ByteArray for Flutter
                    var albumArtBytes: ByteArray? = null
                    val bitmap = metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                        ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
                    
                    if (bitmap != null) {
                        val stream = ByteArrayOutputStream()
                        // Compress to PNG to preserve quality, use 100 for max quality
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        albumArtBytes = stream.toByteArray()
                    }

                    val resultMap = mapOf(
                        "title" to title,
                        "artist" to artist,
                        "duration" to duration,
                        "position" to position,
                        "packageName" to packageName,
                        "albumArt" to albumArtBytes
                    )
                    
                    result.success(resultMap)
                }
                "playPause" -> {
                    val controller = getActiveMediaController()
                    if (controller != null) {
                        val state = controller.playbackState?.state
                        if (state == PlaybackState.STATE_PLAYING) {
                            controller.transportControls.pause()
                        } else {
                            controller.transportControls.play()
                        }
                    } else {
                        sendMediaButton(audioManager, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                    }
                    result.success(null)
                }
                "next" -> {
                    getActiveMediaController()?.transportControls?.skipToNext() 
                        ?: sendMediaButton(audioManager, KeyEvent.KEYCODE_MEDIA_NEXT)
                    result.success(null)
                }
                "previous" -> {
                    getActiveMediaController()?.transportControls?.skipToPrevious()
                        ?: sendMediaButton(audioManager, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                    result.success(null)
                }
                "isPlaying" -> {
                    val controller = getActiveMediaController()
                    if (controller != null) {
                        result.success(controller.playbackState?.state == PlaybackState.STATE_PLAYING)
                    } else {
                        result.success(audioManager.isMusicActive)
                    }
                }
                "openNotificationSettings" -> {
                    // Helper to jump to settings if permission is missing
                    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Gets the active media controller. Requires Notification Access permission.
     */
    private fun getActiveMediaController(): MediaController? {
        val componentName = ComponentName(this, CasiNotificationListenerService::class.java)
        val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        
        return try {
            val controllers = mediaSessionManager.getActiveSessions(componentName)
            // Prefer the controller that is currently playing, otherwise fallback to the most recent one
            controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
                ?: controllers.firstOrNull()
        } catch (e: SecurityException) {
            // Thrown if the user hasn't granted Notification Access yet
            null
        }
    }

    private fun sendMediaButton(audioManager: AudioManager, keyCode: Int) {
        val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        audioManager.dispatchMediaKeyEvent(eventDown)
        
        val eventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(eventUp)
    }
}