package dev.altirra.altirra_flutter

import android.content.Intent
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
                        if (path.isNullOrEmpty() || label.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(pinShortcut(path, label))
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

    private fun pinShortcut(path: String, label: String): Boolean {
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
            .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(launchIntent)
            .build()
        return ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
    }
}
