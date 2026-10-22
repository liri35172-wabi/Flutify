package com.flutify.music.flutify_app

import android.os.Build
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.ryanheise.audioservice.AudioService
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service 要求：Activity 与后台媒体服务共用同一个 Flutter 引擎（通知栏 / 锁屏控件）
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android 原生 DRM 播放引擎（该机型 WebView EME 不可用，走 ExoPlayer + MediaDrm）
        NativeDrmPlugin.register(flutterEngine, this)
        UpdatePlugin.register(flutterEngine, this)
        if (!flutterEngine.plugins.has(AppleMusicBackgroundPlugin::class.java)) {
            flutterEngine.plugins.add(AppleMusicBackgroundPlugin())
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flutify/taskbar_lyrics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isFlymeSupported" -> result.success(isMeizuOrFlyme())
                    "hasOverlayPermission" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
                    )
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
                            result.success(true)
                        } else {
                            try {
                                startActivity(Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                ))
                                result.success(false)
                            } catch (error: Exception) {
                                result.error("overlay_permission", error.message, null)
                            }
                        }
                    }
                    "setOverlayOptions" -> {
                        val values = call.arguments as? Map<*, *>
                        AudioService.setFloatingLyricsOptions(
                            values?.get("clickThrough") as? Boolean == true,
                            values?.get("transparentBackground") as? Boolean == true
                        )
                        result.success(null)
                    }
                    "setOverlayEnabled" -> {
                        val enabled = call.arguments as? Boolean == true
                        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
                        if (enabled && !granted) {
                            result.success(false)
                        } else {
                            AudioService.setFloatingLyricsEnabled(enabled)
                            result.success(true)
                        }
                    }
                    "setEnabled" -> {
                        AudioService.setFlymeLyricsEnabled(call.arguments as? Boolean == true)
                        result.success(null)
                    }
                    "setLyrics" -> {
                        val values = call.arguments as? Map<*, *>
                        val times = toLongArray(values?.get("times"))
                        val texts = toStringArray(values?.get("texts"))
                        val translations = toStringArray(values?.get("texts2"))
                        AudioService.setLyricsData(times, texts, translations)
                        result.success(null)
                    }
                    "setPlayback" -> {
                        val values = call.arguments as? Map<*, *>
                        val playing = values?.get("playing") as? Boolean ?: false
                        val position = (values?.get("positionMs") as? Number)?.toLong() ?: 0L
                        AudioService.setFlymePlayback(playing, position)
                        result.success(null)
                    }
                    // These methods are used by the shared Windows lyrics controller but do not
                    // affect a status-bar ticker.
                    "setStyle", "setTrack", "setArt" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun isMeizuOrFlyme(): Boolean =
        Build.MANUFACTURER.contains("meizu", ignoreCase = true) ||
            Build.BRAND.contains("meizu", ignoreCase = true) ||
            Build.DISPLAY.contains("flyme", ignoreCase = true) ||
            Build.FINGERPRINT.contains("flyme", ignoreCase = true)

    private fun toLongArray(value: Any?): LongArray = when (value) {
        is IntArray -> LongArray(value.size) { value[it].toLong() }
        is LongArray -> value
        is List<*> -> value.mapNotNull { (it as? Number)?.toLong() }.toLongArray()
        else -> longArrayOf()
    }

    private fun toStringArray(value: Any?): Array<String> =
        (value as? List<*>)?.map { it as? String ?: "" }?.toTypedArray() ?: emptyArray()
}
