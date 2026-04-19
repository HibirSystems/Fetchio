package com.hibir.fetchio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_STORE_CHANNEL = "com.hibir.fetchio/media_store"
        private const val RUNTIME_CHANNEL = "com.hibir.fetchio/runtime"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = MediaStoreBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_STORE_CHANNEL,
        ).setMethodCallHandler(bridge)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RUNTIME_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
    }
}
