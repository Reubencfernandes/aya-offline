package com.inl.aya_flutter

import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aya/storage_info"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getAvailableBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_args", "Missing path argument.", null)
                return@setMethodCallHandler
            }

            try {
                val resolvedPath = resolveExistingPath(File(path))
                val availableBytes = StatFs(resolvedPath.absolutePath).availableBytes
                result.success(availableBytes)
            } catch (error: Exception) {
                result.error("storage_error", error.message, null)
            }
        }
    }

    private fun resolveExistingPath(file: File): File {
        var current: File? = file
        while (current != null && !current.exists()) {
            current = current.parentFile
        }
        return current ?: filesDir
    }
}
