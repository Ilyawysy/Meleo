package com.sparcarclabs.meleo

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class BlockerOverlayView(private val context: Context) {

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayLayout: LinearLayout? = null
    private var isShowing = false

    fun show() {
        if (isShowing) return
        isShowing = true

        val layout = buildLayout()
        overlayLayout = layout

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        try {
            windowManager.addView(layout, params)
        } catch (_: Exception) {
            isShowing = false
            overlayLayout = null
        }
    }

    fun hide() {
        if (!isShowing || overlayLayout == null) return
        try {
            windowManager.removeView(overlayLayout)
        } catch (_: Exception) {}
        overlayLayout = null
        isShowing = false
    }

    private fun buildLayout(): LinearLayout {
        val dp = { value: Float ->
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value,
                context.resources.displayMetrics
            ).toInt()
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F0F4FF"))
            setPadding(dp(32f), dp(48f), dp(32f), dp(48f))

            // Shield icon
            addView(TextView(context).apply {
                text = "\uD83D\uDEE1\uFE0F"
                textSize = 64f
                gravity = Gravity.CENTER
            })

            // Title
            addView(TextView(context).apply {
                text = "Focus Session Active"
                textSize = 24f
                setTextColor(Color.parseColor("#18181B"))
                typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(0, dp(24f), 0, dp(12f))
            })

            // Subtitle
            addView(TextView(context).apply {
                text = "This app is blocked while you're focusing.\nStay on track!"
                textSize = 16f
                setTextColor(Color.parseColor("#71717A"))
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(40f))
            })

            // "Return to Meleo" button
            addView(Button(context).apply {
                text = "Return to Meleo"
                textSize = 16f
                setTextColor(Color.WHITE)
                isAllCaps = false
                typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#2563EB"))
                    cornerRadius = dp(16f).toFloat()
                }
                setPadding(dp(24f), dp(16f), dp(24f), dp(16f))
                val lp = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(56f)
                )
                lp.bottomMargin = dp(12f)
                layoutParams = lp
                setOnClickListener {
                    val intent = context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                        ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (intent != null) context.startActivity(intent)
                }
            })

            // "Close app" button
            addView(Button(context).apply {
                text = "Close this app"
                textSize = 16f
                setTextColor(Color.parseColor("#71717A"))
                isAllCaps = false
                background = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    setStroke(dp(1f), Color.parseColor("#E4E4E7"))
                    cornerRadius = dp(16f).toFloat()
                }
                setPadding(dp(24f), dp(16f), dp(24f), dp(16f))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(56f)
                )
                setOnClickListener {
                    val intent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                }
            })
        }
    }
}
