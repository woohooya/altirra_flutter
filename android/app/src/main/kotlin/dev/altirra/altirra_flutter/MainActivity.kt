package dev.altirra.altirra_flutter

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "dev.altirra.altirra_flutter/shortcuts"
        private const val EXTRA_GAME_PATH = "game_path"
    }

    private var channel: MethodChannel? = null
    private var pendingGamePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingGamePath = intent?.getStringExtra(EXTRA_GAME_PATH)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialGamePath" -> {
                        val path = pendingGamePath
                        pendingGamePath = null
                        result.success(path)
                    }
                    "isPinSupported" -> {
                        result.success(ShortcutManagerCompat.isRequestPinShortcutSupported(this@MainActivity))
                    }
                    "pinGameShortcut" -> {
                        val path = call.argument<String>("path")
                        val label = call.argument<String>("label")
                        val iconPath = call.argument<String>("iconPath")
                        if (path.isNullOrEmpty() || label.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(pinShortcut(path, label, iconPath))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = intent.getStringExtra(EXTRA_GAME_PATH) ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onLaunchGame", path)
        } else {
            pendingGamePath = path
        }
    }

    private fun buildShortcutIcon(iconPath: String?): IconCompat {
        if (!iconPath.isNullOrEmpty()) {
            val raw = BitmapFactory.decodeFile(iconPath)
            if (raw != null) {
                val side = minOf(raw.width, raw.height)
                val x = (raw.width - side) / 2
                val y = (raw.height - side) / 2
                val square = Bitmap.createBitmap(raw, x, y, side, side)
                val scaled = Bitmap.createScaledBitmap(square, 256, 256, true)
                if (square !== raw) square.recycle()
                if (scaled !== raw) raw.recycle()
                return IconCompat.createWithBitmap(scaled)
            }
        }
        return IconCompat.createWithResource(this, R.mipmap.ic_launcher)
    }

    private fun pinShortcut(path: String, label: String, iconPath: String?): Boolean {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(this)) {
            return false
        }
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_GAME_PATH, path)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val shortcut = ShortcutInfoCompat.Builder(this, "game_${path.hashCode()}")
            .setShortLabel(label.take(25))
            .setLongLabel(label)
            .setIcon(buildShortcutIcon(iconPath))
            .setIntent(launchIntent)
            .build()
        return ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
    }
}
