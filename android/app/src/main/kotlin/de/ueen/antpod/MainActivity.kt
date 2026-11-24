package de.ueen.antpod

import android.app.NotificationManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.ueen.antpod/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method == "dismissDownloadNotifications") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        nm.activeNotifications
                            .filter { it.notification.channelId == "ch_flutter_downloader" }
                            .forEach { nm.cancel(it.id) }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
