package com.maleolabs.kecilin

import com.maleolabs.kecilin.compress.CompressBridge
import com.maleolabs.kecilin.gallery.GalleryBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: CompressBridge? = null
    private var gallery: GalleryBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        bridge = CompressBridge(applicationContext, messenger).also { it.attach() }
        gallery = GalleryBridge(applicationContext, messenger, this).also { it.attach() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.detach()
        bridge = null
        gallery?.detach()
        gallery = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        gallery?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
