package com.sparcarclabs.meleo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class AppBlockerService : Service() {

    companion object {
        const val CHANNEL_ID = "meleo_blocker"
        const val NOTIFICATION_ID = 9001
        private const val POLL_INTERVAL_MS = 700L

        @Volatile
        var isRunning = false
            private set
    }

    private var pollThread: HandlerThread? = null
    private var pollHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var blockedPackages = setOf<String>()
    private var overlayView: BlockerOverlayView? = null
    private var lastForegroundPackage: String? = null

    private val pollRunnable = object : Runnable {
        override fun run() {
            checkForegroundApp()
            pollHandler?.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        overlayView = BlockerOverlayView(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always call startForeground first to avoid ForegroundServiceDidNotStartInTimeException
        startForeground(NOTIFICATION_ID, buildNotification())

        val prefs = getSharedPreferences("app_blocker", Context.MODE_PRIVATE)
        blockedPackages = prefs.getStringSet("blocked_packages", emptySet()) ?: emptySet()

        if (blockedPackages.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        isRunning = true

        // Remove any existing polling before starting new one
        pollHandler?.removeCallbacks(pollRunnable)
        pollThread?.quitSafely()

        // Start polling on a background thread
        val thread = HandlerThread("AppBlockerPoll").also { it.start() }
        pollThread = thread
        pollHandler = Handler(thread.looper)
        pollHandler?.post(pollRunnable)

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        pollHandler?.removeCallbacks(pollRunnable)
        pollThread?.quitSafely()
        pollThread = null
        pollHandler = null
        mainHandler.post { overlayView?.hide() }
        overlayView = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun checkForegroundApp() {
        val foreground = getForegroundPackage() ?: return

        if (foreground == lastForegroundPackage) return
        lastForegroundPackage = foreground

        if (foreground != packageName && foreground in blockedPackages) {
            mainHandler.post { overlayView?.show() }
        } else {
            mainHandler.post { overlayView?.hide() }
        }
    }

    private fun getForegroundPackage(): String? {
        val usm = getSystemService(USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(now - 5000, now) ?: return null
        val event = UsageEvents.Event()
        var lastForeground: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastForeground = event.packageName
            }
        }
        return lastForeground
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Blocker",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows while app blocking is active during focus sessions"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (openIntent != null) {
            PendingIntent.getActivity(
                this, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Focus session active")
            .setContentText("${blockedPackages.size} app(s) blocked")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }
}
