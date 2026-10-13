package com.mystyle.purelive

import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Streams this process's own logcat lines from the playback engines to Dart,
 * which adds them to the app log. ijkplayer (IJKMEDIA, ffmpeg's output
 * included), ExoPlayer and the platform decoders log only to logcat, out of
 * Dart's reach. An app reads its own process's log without any permission.
 */
internal class NativeLogPlugin : FlutterPlugin, EventChannel.StreamHandler {
    companion object {
        private const val CHANNEL_NAME = "pure_live/native_log"
        private const val BATCH_INTERVAL_MS = 500L

        // The engines' tags from info up, everything else in this process
        // from warning up.
        private val FILTER_SPECS = listOf(
            "IJKMEDIA:I",
            "FIJKPLAYER:I",
            "ExoPlayerImpl:I",
            "BetterPlayer:I",
            "flutter:I",
            "*:W",
        )

        // `-v tag` prints `P/TAG     : message`.
        private val LINE = Regex("""^([VDIWEFA])/([^:]*?)\s*: ?(.*)$""")

        // Dart's print and debugPrint (tag `flutter`) are in the app log
        // already; only fijkplayer's FijkLog lines, `[inf] <time> [tag] msg`,
        // are taken from there.
        private val FIJK_LOG = Regex("""^\[(det|veb|dbg|inf|war|err|fal)] """)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pending = ArrayList<String>()
    private var channel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var process: java.lang.Process? = null
    private var reader: Thread? = null
    private var flushScheduled = false

    private val flush = Runnable {
        val batch: List<String>
        synchronized(pending) {
            batch = ArrayList(pending)
            pending.clear()
            flushScheduled = false
        }
        if (batch.isNotEmpty()) sink?.success(batch)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = EventChannel(binding.binaryMessenger, CHANNEL_NAME).also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        channel?.setStreamHandler(null)
        channel = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        sink = events
        val started = try {
            Runtime.getRuntime().exec(
                (listOf("logcat", "-v", "tag", "--pid=${Process.myPid()}") + FILTER_SPECS).toTypedArray(),
            )
        } catch (error: Exception) {
            events.error("native_log_unavailable", error.message, null)
            return
        }
        process = started
        reader = Thread({ readLines(started) }, "pure-live-native-log").apply {
            isDaemon = true
            start()
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    private fun stop() {
        process?.destroy()
        process = null
        reader?.interrupt()
        reader = null
        mainHandler.removeCallbacks(flush)
        synchronized(pending) {
            pending.clear()
            flushScheduled = false
        }
        sink = null
    }

    private fun readLines(source: java.lang.Process) {
        try {
            BufferedReader(InputStreamReader(source.inputStream)).use { lines ->
                while (!Thread.currentThread().isInterrupted) {
                    val line = lines.readLine() ?: break
                    if (keep(line)) enqueue(line)
                }
            }
        } catch (_: Exception) {
            // The process was destroyed by stop(), or logcat went away.
        }
    }

    private fun keep(line: String): Boolean {
        val match = LINE.find(line) ?: return false
        val tag = match.groupValues[2].trim()
        return tag != "flutter" || FIJK_LOG.containsMatchIn(match.groupValues[3])
    }

    private fun enqueue(line: String) {
        synchronized(pending) {
            pending.add(line)
            if (flushScheduled) return
            flushScheduled = true
        }
        mainHandler.postDelayed(flush, BATCH_INTERVAL_MS)
    }
}
