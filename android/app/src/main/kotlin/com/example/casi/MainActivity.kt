package com.example.casi

import android.Manifest
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.provider.CalendarContract
import android.provider.Settings
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.view.KeyEvent
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.Instant

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "casi.launcher/media"
    private val APP_CHANNEL = "casi.launcher/apps"
    private val NOTIF_CHANNEL = "casi.launcher/notifications"
    private val CALENDAR_CHANNEL = "casi.launcher/calendar"
    private val HEALTH_CHANNEL = "casi.launcher/health"
    private val WALLPAPER_CHANNEL = "casi.launcher/wallpaper"
    private val DEVICE_CHANNEL = "casi.launcher/device"
    private val CLOCK_CHANNEL = "casi.launcher/clock"
    private val CALENDAR_PERMISSION_REQUEST = 100
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val healthPermissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    private var pendingHealthPermissionResult: MethodChannel.Result? = null

    private val requestHealthPermissionsLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        pendingHealthPermissionResult?.success(granted.isNotEmpty())
        pendingHealthPermissionResult = null
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- Notifications Channel ---
        // Only kept for `isNotificationAccessGranted` — needed by the
        // media-controller and system-timer flows so the launcher can ask
        // the user to grant Notification Access from settings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    val componentName = ComponentName(this, CasiNotificationListenerService::class.java)
                    val flat = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val enabled = flat != null && flat.contains(componentName.flattenToString())
                    result.success(enabled)
                }
                else -> result.notImplemented()
            }
        }

        // --- Clock Channel: system alarms & timers ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNextAlarmClock" -> {
                    try {
                        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                        val info = am.nextAlarmClock
                        if (info == null) {
                            result.success(null)
                        } else {
                            val showIntent = info.showIntent
                            val ownerPkg = showIntent?.creatorPackage
                                ?: showIntent?.intentSender?.creatorPackage
                            result.success(mapOf(
                                "triggerTime" to info.triggerTime,
                                "ownerPackage" to ownerPkg
                            ))
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("CASI/Clock", "getNextAlarmClock failed", e)
                        result.success(null)
                    }
                }
                "getSystemTimers" -> {
                    val service = CasiNotificationListenerService.instance
                    result.success(service?.getActiveTimers() ?: "[]")
                }
                "openSystemClock" -> {
                    try {
                        val pm = packageManager
                        // Prefer the app that registered the next alarm — that's
                        // the user's *de facto* default clock app, even if no
                        // intent filter advertises it as such.
                        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                        val ownerPkg = am.nextAlarmClock?.let { info ->
                            info.showIntent?.creatorPackage
                                ?: info.showIntent?.intentSender?.creatorPackage
                        }

                        var launched = false
                        if (ownerPkg != null) {
                            val launch = pm.getLaunchIntentForPackage(ownerPkg)
                            if (launch != null) {
                                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launch)
                                launched = true
                            }
                        }
                        if (!launched) {
                            // Fall back to the standard SHOW_ALARMS intent;
                            // every modern Android clock app handles it.
                            val intent = Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            try {
                                startActivity(intent)
                                launched = true
                            } catch (_: Exception) {}
                        }
                        result.success(launched)
                    } catch (e: Exception) {
                        android.util.Log.w("CASI/Clock", "openSystemClock failed", e)
                        result.success(false)
                    }
                }
                "openSystemTimers" -> {
                    try {
                        val intent = Intent(android.provider.AlarmClock.ACTION_SHOW_TIMERS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Older devices may not support ACTION_SHOW_TIMERS — fall
                        // back to the alarms screen of the user's clock app.
                        try {
                            val intent = Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Calendar Channel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCalendarPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestCalendarPermission" -> {
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALENDAR), CALENDAR_PERMISSION_REQUEST)
                    result.success(null)
                }
                "getTodayEvents" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                        result.success("[]")
                        return@setMethodCallHandler
                    }
                    try {
                        val events = readTodayCalendarEvents()
                        result.success(events)
                    } catch (e: Exception) {
                        result.success("[]")
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Health Channel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEALTH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isHealthConnectAvailable" -> {
                    val status = HealthConnectClient.getSdkStatus(this)
                    result.success(status == HealthConnectClient.SDK_AVAILABLE)
                }
                "requestHealthPermissions" -> {
                    try {
                        pendingHealthPermissionResult = result
                        requestHealthPermissionsLauncher.launch(healthPermissions)
                    } catch (e: Exception) {
                        pendingHealthPermissionResult = null
                        result.success(false)
                    }
                }
                "getTodayHealthData" -> {
                    scope.launch {
                        try {
                            val data = readTodayHealthData()
                            result.success(data)
                        } catch (e: Exception) {
                            result.success(mapOf(
                                "steps" to 0,
                                "sleepMinutes" to 0,
                                "activeMinutes" to 0,
                                "calories" to 0,
                                "distanceMeters" to 0.0,
                                "available" to false
                            ))
                        }
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
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
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
                "lockScreen" -> {
                    val devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                    val adminComponent = ComponentName(this, CasiDeviceAdminReceiver::class.java)

                    if (devicePolicyManager.isAdminActive(adminComponent)) {
                        devicePolicyManager.lockNow()
                        result.success(true)
                    } else {
                        val intent = Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Casi needs device admin to turn off the screen on double-tap")
                        }
                        startActivity(intent)
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Wallpaper Channel ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WALLPAPER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemWallpaper" -> {
                    try {
                        val wallpaperManager = WallpaperManager.getInstance(this)
                        val drawable = wallpaperManager.drawable
                        if (drawable != null) {
                            val bitmap = if (drawable is android.graphics.drawable.BitmapDrawable) {
                                drawable.bitmap
                            } else {
                                val bmp = Bitmap.createBitmap(
                                    drawable.intrinsicWidth.coerceAtMost(1080),
                                    drawable.intrinsicHeight.coerceAtMost(1920),
                                    Bitmap.Config.ARGB_8888
                                )
                                val canvas = android.graphics.Canvas(bmp)
                                drawable.setBounds(0, 0, canvas.width, canvas.height)
                                drawable.draw(canvas)
                                bmp
                            }
                            // Scale down for transfer efficiency
                            val scaled = Bitmap.createScaledBitmap(
                                bitmap,
                                bitmap.width.coerceAtMost(1080),
                                bitmap.height.coerceAtMost(1920),
                                true
                            )
                            val stream = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                            result.success(stream.toByteArray())
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "isLiveWallpaper" -> {
                    try {
                        val wallpaperManager = WallpaperManager.getInstance(this)
                        val info = wallpaperManager.wallpaperInfo
                        result.success(info != null)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Device Context Channel (battery, network, charging) ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceContext" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    val isCharging = batteryManager.isCharging

                    val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val network = connectivityManager.activeNetwork
                    var networkState = "offline"
                    if (network != null) {
                        val capabilities = connectivityManager.getNetworkCapabilities(network)
                        if (capabilities != null) {
                            networkState = when {
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                                else -> "other"
                            }
                        }
                    }

                    // Audio route: lets Foresight react when the user connects
                    // headphones / car bluetooth and immediately surface music
                    // & podcast apps.
                    //
                    // Detection runs through three independent paths so a
                    // single API quirk doesn't blind us:
                    //   1) AudioManager.getDevices(GET_DEVICES_OUTPUTS) — the
                    //      modern path, but on Android 12+ without
                    //      BLUETOOTH_CONNECT it can omit names and on some
                    //      OEMs the list lags real connection state.
                    //   2) Legacy AudioManager flags (isBluetoothA2dpOn /
                    //      isWiredHeadsetOn) — deprecated but still report
                    //      classic A2DP routing without any new permission.
                    //   3) BluetoothAdapter profile state for A2DP / Headset
                    //      / Hearing-Aid / LE Audio (TYPE_BLE_*). Reflects
                    //      actual pairing regardless of audio routing.
                    val audioCtxManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    var audioRoute = "speaker"
                    var bluetoothAudioConnected = false
                    var bluetoothDeviceName: String? = null
                    val typesSeen = StringBuilder()

                    try {
                        val outputs = audioCtxManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        for (d in outputs) {
                            if (typesSeen.isNotEmpty()) typesSeen.append(',')
                            typesSeen.append(d.type)
                            when (d.type) {
                                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                                AudioDeviceInfo.TYPE_HEARING_AID,
                                26 /* TYPE_BLE_HEADSET, API 31 */,
                                27 /* TYPE_BLE_SPEAKER, API 31 */,
                                30 /* TYPE_BLE_BROADCAST, API 33 */ -> {
                                    bluetoothAudioConnected = true
                                    audioRoute = "bluetooth"
                                    if (bluetoothDeviceName.isNullOrEmpty()) {
                                        val candidate = d.productName?.toString()
                                        if (!candidate.isNullOrBlank()) {
                                            bluetoothDeviceName = candidate
                                        }
                                    }
                                }
                                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                                AudioDeviceInfo.TYPE_USB_HEADSET,
                                AudioDeviceInfo.TYPE_USB_DEVICE,
                                AudioDeviceInfo.TYPE_USB_ACCESSORY -> {
                                    if (audioRoute == "speaker") audioRoute = "wired_headphones"
                                }
                                AudioDeviceInfo.TYPE_DOCK -> {
                                    if (audioRoute == "speaker") audioRoute = "dock"
                                }
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("CASI/Foresight", "audio device enumeration failed", e)
                    }

                    // Fallback 1: legacy AudioManager flags. Catches devices
                    // some OEMs hide from the modern device list while audio
                    // is idle.
                    if (!bluetoothAudioConnected) {
                        try {
                            @Suppress("DEPRECATION")
                            if (audioCtxManager.isBluetoothA2dpOn || audioCtxManager.isBluetoothScoOn) {
                                bluetoothAudioConnected = true
                                audioRoute = "bluetooth"
                            }
                        } catch (_: Exception) {}
                    }

                    // Fallback 2: BluetoothAdapter profile state. Detects a
                    // paired-and-connected headset whether or not the system
                    // is currently routing audio through it. Profile-state
                    // reads do not require BLUETOOTH_CONNECT; reading the
                    // device *name* does on Android 12+.
                    try {
                        val btMgr = getSystemService(Context.BLUETOOTH_SERVICE)
                                as? android.bluetooth.BluetoothManager
                        val adapter = btMgr?.adapter
                        if (adapter != null && adapter.isEnabled) {
                            val profiles = intArrayOf(
                                android.bluetooth.BluetoothProfile.A2DP,
                                android.bluetooth.BluetoothProfile.HEADSET,
                                android.bluetooth.BluetoothProfile.HEARING_AID,
                            )
                            for (p in profiles) {
                                try {
                                    val state = adapter.getProfileConnectionState(p)
                                    if (state == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                                        bluetoothAudioConnected = true
                                        audioRoute = "bluetooth"
                                        break
                                    }
                                } catch (_: SecurityException) {}
                            }
                        }
                    } catch (_: Exception) {}

                    android.util.Log.d(
                        "CASI/Foresight",
                        "audio route=$audioRoute bt=$bluetoothAudioConnected " +
                            "name=$bluetoothDeviceName outputTypes=[$typesSeen]"
                    )

                    // Wi-Fi SSID: best-effort. Requires location permission +
                    // location services on. Returns null otherwise — the rule
                    // engine treats a missing SSID as "no extra signal."
                    var wifiSsid: String? = null
                    if (networkState == "wifi") {
                        try {
                            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                            @Suppress("DEPRECATION")
                            val info = wm.connectionInfo
                            val raw = info?.ssid
                            if (!raw.isNullOrEmpty() && raw != "<unknown ssid>" && raw != "0x") {
                                wifiSsid = if (raw.startsWith("\"") && raw.endsWith("\"") && raw.length >= 2) {
                                    raw.substring(1, raw.length - 1)
                                } else raw
                            }
                        } catch (_: Exception) {}
                    }

                    result.success(mapOf(
                        "batteryLevel" to batteryLevel,
                        "isCharging" to isCharging,
                        "networkState" to networkState,
                        "audioRoute" to audioRoute,
                        "bluetoothAudioConnected" to bluetoothAudioConnected,
                        "bluetoothDeviceName" to bluetoothDeviceName,
                        "wifiSsid" to wifiSsid
                    ))
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

    /**
     * Reads today's calendar events from all device calendars using CalendarContract.
     * Returns a JSON array string of events.
     */
    private fun readTodayCalendarEvents(): String {
        val zone = java.util.TimeZone.getDefault()
        val cal = java.util.Calendar.getInstance(zone)
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        val startMillis = cal.timeInMillis

        cal.set(java.util.Calendar.HOUR_OF_DAY, 23)
        cal.set(java.util.Calendar.MINUTE, 59)
        cal.set(java.util.Calendar.SECOND, 59)
        val endMillis = cal.timeInMillis

        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME
        )

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(startMillis.toString())
            .appendPath(endMillis.toString())
            .build()

        val cursor: Cursor? = contentResolver.query(
            uri,
            projection,
            null,
            null,
            "${CalendarContract.Instances.BEGIN} ASC"
        )

        val events = mutableListOf<String>()
        cursor?.use {
            while (it.moveToNext()) {
                val title = it.getString(0) ?: "Untitled"
                val begin = it.getLong(1)
                val end = it.getLong(2)
                val allDay = it.getInt(3) == 1
                val location = it.getString(4) ?: ""
                val description = it.getString(5) ?: ""
                val calendarName = it.getString(6) ?: ""

                // Escape JSON strings
                val escapedTitle = title.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
                val escapedLocation = location.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
                val escapedDesc = description.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
                val escapedCalName = calendarName.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

                events.add("""{"title":"$escapedTitle","begin":$begin,"end":$end,"allDay":$allDay,"location":"$escapedLocation","description":"$escapedDesc","calendarName":"$escapedCalName"}""")
            }
        }

        return "[${events.joinToString(",")}]"
    }

    /**
     * Reads today's health data from Health Connect.
     * Returns a map with steps, sleep, active time, calories, distance.
     */
    private suspend fun readTodayHealthData(): Map<String, Any> {
        val status = HealthConnectClient.getSdkStatus(this)
        if (status != HealthConnectClient.SDK_AVAILABLE) {
            return mapOf(
                "steps" to 0,
                "sleepMinutes" to 0,
                "activeMinutes" to 0,
                "calories" to 0,
                "distanceMeters" to 0.0,
                "available" to false
            )
        }

        val client = HealthConnectClient.getOrCreate(this@MainActivity)

        // Check if any health permissions are granted
        val grantedPermissions = client.permissionController.getGrantedPermissions()
        if (grantedPermissions.intersect(healthPermissions).isEmpty()) {
            return mapOf(
                "steps" to 0,
                "sleepMinutes" to 0,
                "activeMinutes" to 0,
                "calories" to 0,
                "distanceMeters" to 0.0,
                "available" to false
            )
        }

        val now = Instant.now()
        val startOfDay = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()
        val timeRange = TimeRangeFilter.between(startOfDay, now)

        var totalSteps = 0L
        var totalCalories = 0.0
        var totalDistance = 0.0
        var totalActiveMinutes = 0L
        var totalSleepMinutes = 0L

        try {
            // Steps
            val stepsResponse = client.readRecords(
                ReadRecordsRequest(StepsRecord::class, timeRangeFilter = timeRange)
            )
            for (record in stepsResponse.records) {
                totalSteps += record.count
            }
        } catch (_: Exception) {}

        try {
            // Active calories
            val caloriesResponse = client.readRecords(
                ReadRecordsRequest(ActiveCaloriesBurnedRecord::class, timeRangeFilter = timeRange)
            )
            for (record in caloriesResponse.records) {
                totalCalories += record.energy.inKilocalories
            }
        } catch (_: Exception) {}

        try {
            // Distance
            val distanceResponse = client.readRecords(
                ReadRecordsRequest(DistanceRecord::class, timeRangeFilter = timeRange)
            )
            for (record in distanceResponse.records) {
                totalDistance += record.distance.inMeters
            }
        } catch (_: Exception) {}

        try {
            // Exercise (active time)
            val exerciseResponse = client.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRangeFilter = timeRange)
            )
            for (record in exerciseResponse.records) {
                val duration = java.time.Duration.between(record.startTime, record.endTime)
                totalActiveMinutes += duration.toMinutes()
            }
        } catch (_: Exception) {}

        try {
            // Sleep - check last night (start from yesterday 6 PM)
            val sleepStart = LocalDate.now().minusDays(1).atTime(18, 0).atZone(ZoneId.systemDefault()).toInstant()
            val sleepRange = TimeRangeFilter.between(sleepStart, now)
            val sleepResponse = client.readRecords(
                ReadRecordsRequest(SleepSessionRecord::class, timeRangeFilter = sleepRange)
            )
            for (record in sleepResponse.records) {
                val duration = java.time.Duration.between(record.startTime, record.endTime)
                totalSleepMinutes += duration.toMinutes()
            }
        } catch (_: Exception) {}

        return mapOf(
            "steps" to totalSteps,
            "sleepMinutes" to totalSleepMinutes,
            "activeMinutes" to totalActiveMinutes,
            "calories" to totalCalories.toInt(),
            "distanceMeters" to totalDistance,
            "available" to true
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}