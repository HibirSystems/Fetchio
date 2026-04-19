package com.hibir.fetchio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = MediaStoreBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MediaStoreBridge.CHANNEL,
        ).setMethodCallHandler(bridge)
    }
}
