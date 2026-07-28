package com.sparcarclabs.meleo

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class AppBlockerMethodChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.meleo.mobile/app_blocker"

        fun register(context: Context, flutterEngine: FlutterEngine) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(AppBlockerMethodChannel(context))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> getInstalledApps(result)
            "startBlocking" -> {
                val packages = call.argument<List<String>>("packageNames") ?: emptyList()
                startBlocking(packages, result)
            }
            "stopBlocking" -> stopBlocking(result)
            "isBlockingActive" -> result.success(AppBlockerService.isRunning)
            "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(context))
            "requestOverlayPermission" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }
            "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
            "requestUsageStatsPermission" -> {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun getInstalledApps(result: MethodChannel.Result) {
        Thread {
            try {
                val pm = context.packageManager
                val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
                val myPackage = context.packageName

                val apps = resolveInfos
                    .mapNotNull { ri ->
                        val pkg = ri.activityInfo.packageName
                        if (pkg == myPackage) return@mapNotNull null
                        try {
                            val appInfo = pm.getApplicationInfo(pkg, 0)
                            val appName = pm.getApplicationLabel(appInfo).toString()
                            val icon = drawableToBytes(pm.getApplicationIcon(appInfo))
                            mapOf(
                                "packageName" to pkg,
                                "appName" to appName,
                                "icon" to icon,
                            )
                        } catch (_: PackageManager.NameNotFoundException) {
                            null
                        }
                    }
                    .distinctBy { it["packageName"] }
                    .sortedBy { (it["appName"] as String).lowercase() }

                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.success(apps)
                }
            } catch (e: Exception) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("GET_APPS_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun startBlocking(packages: List<String>, result: MethodChannel.Result) {
        if (packages.isEmpty()) {
            result.success(null)
            return
        }

        val prefs = context.getSharedPreferences("app_blocker", Context.MODE_PRIVATE)
        prefs.edit().putStringSet("blocked_packages", packages.toSet()).apply()

        val intent = Intent(context, AppBlockerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(null)
    }

    private fun stopBlocking(result: MethodChannel.Result) {
        val intent = Intent(context, AppBlockerService::class.java)
        context.stopService(intent)
        result.success(null)
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun drawableToBytes(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, 48, 48, true)
        } else {
            val bmp = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, 48, 48)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }
}
