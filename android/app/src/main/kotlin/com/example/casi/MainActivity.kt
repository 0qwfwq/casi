package com.example.casi

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
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

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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