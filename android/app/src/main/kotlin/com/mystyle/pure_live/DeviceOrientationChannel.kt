package com.mystyle.pure_live

import android.content.Context
import android.provider.Settings
import android.view.OrientationEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 横屏自动全屏: how the phone is physically held, while the room asks for it.
 *
 * A room in its normal layout is locked to portrait, so turning the phone
 * changes nothing on screen and Flutter never hears of it. This listens to
 * the orientation sensor instead and tells Dart "portrait" or "landscape"
 * whenever the phone settles into the other one - only while the system's
 * auto-rotate is on, so a rotation lock keeps meaning "don't turn for me".
 */
internal class DeviceOrientationChannel(
    context: Context,
    binaryMessenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "pure_live/device_orientation"
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(binaryMessenger, CHANNEL)
    private var watching = false
    private var paused = false
    private var reported: String? = null

    private val listener =
        object : OrientationEventListener(appContext) {
            override fun onOrientationChanged(degrees: Int) {
                if (degrees == ORIENTATION_UNKNOWN) return
                if (!autoRotateOn()) {
                    // Turning auto-rotate on later reports the next change.
                    reported = null
                    return
                }
                val held = classify(degrees) ?: return
                if (held == reported) return
                reported = held
                channel.invokeMethod("orientation", held)
            }
        }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                watching = true
                reported = null
                apply()
                result.success(null)
            }

            "stop" -> {
                watching = false
                apply()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** The activity left the foreground: no sensor while nothing is shown. */
    fun pause() {
        paused = true
        apply()
    }

    fun resume() {
        paused = false
        reported = null
        apply()
    }

    fun dispose() {
        watching = false
        apply()
        channel.setMethodCallHandler(null)
    }

    private fun apply() {
        if (watching && !paused && listener.canDetectOrientation()) {
            listener.enable()
        } else {
            listener.disable()
        }
    }

    private fun autoRotateOn(): Boolean =
        Settings.System.getInt(appContext.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) == 1

    /**
     * Portrait within 30 degrees of upright (or upside down), landscape
     * within 30 degrees of either side; the angles between keep the last
     * answer, so a phone held near 45 degrees does not flip back and forth.
     */
    private fun classify(degrees: Int): String? =
        when (degrees) {
            in 0..30, in 330..359, in 150..210 -> "portrait"
            in 60..120, in 240..300 -> "landscape"
            else -> null
        }
}
