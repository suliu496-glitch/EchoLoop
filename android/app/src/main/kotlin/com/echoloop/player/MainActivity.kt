package com.echoloop.player

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 应用唯一的 Activity。
 *
 * 除承载 Flutter 界面外，还负责把两类系统回调转发给 [NativeBridge]：
 * 1. `startActivityForResult` 的结果（SAF 文件选择、SAF 目录授权）
 * 2. 运行时权限申请结果
 *
 * 未被本应用消费的回调会继续交给 `super`，以免影响插件（sqflite 等）的自身逻辑。
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** Flutter 与原生之间的方法通道名。 */
        const val CHANNEL_NAME = "com.echoloop/player"
    }

    private var bridge: NativeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = NativeBridge(this, flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.attach()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val handled = bridge?.onActivityResult(requestCode, resultCode, data) == true
        if (!handled) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val handled = bridge?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true
        if (!handled) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        super.onDestroy()
    }
}
