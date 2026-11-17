package org.pobos.hfs.hfs_flutter

import android.content.ContentValues
import android.content.Intent
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "hfs_storage"
        const val CREATE_DOCUMENT = 4101
        const val OPEN_DOCUMENT = 4102
    }

    private var pendingSave: Map<String, Any?>? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingOpenResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveBytes" -> beginSave(call.argument("fileName"), call.argument("mimeType"), call.argument("bytes"), result)
                    "openText" -> beginOpen(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun beginSave(fileName: String?, mimeType: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        if (pendingResult != null || pendingOpenResult != null) {
            result.error("BUSY", "已有文件操作正在等待完成", null)
            return
        }
        if (fileName.isNullOrBlank() || mimeType.isNullOrBlank() || bytes == null) {
            result.error("INVALID_ARGUMENT", "文件名、MIME 类型或内容为空", null)
            return
        }
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("CREATE_FAILED", "无法创建 Android Downloads 文档", null)
                    return
                }
                try {
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                        ?: throw IllegalStateException("无法打开 Downloads 输出流")
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    result.success(uri.toString())
                } catch (e: Exception) {
                    contentResolver.delete(uri, null, null)
                    result.error("WRITE_FAILED", e.message, null)
                }
            } catch (e: Exception) {
                result.error("MEDIASTORE_FAILED", e.message, null)
            }
        } else {
            pendingSave = mapOf("fileName" to fileName, "mimeType" to mimeType, "bytes" to bytes)
            pendingResult = result
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            }, CREATE_DOCUMENT)
        }
    }

    private fun beginOpen(result: MethodChannel.Result) {
        if (pendingResult != null || pendingOpenResult != null) {
            result.error("BUSY", "已有文件操作正在等待完成", null)
            return
        }
        pendingOpenResult = result;
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "*/*"))
        }, OPEN_DOCUMENT)
    }

    private fun failPending(code: String, message: String) {
        pendingResult?.error(code, message, null)
        pendingOpenResult?.error(code, message, null)
        pendingResult = null
        pendingOpenResult = null
        pendingSave = null
    }

    override fun onDestroy() {
        failPending("ACTIVITY_DESTROYED", "Android 页面已关闭，文件操作未完成")
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CREATE_DOCUMENT) {
            val result = pendingResult
            pendingResult = null
            val save = pendingSave
            pendingSave = null
            if (result == null) return
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null || save == null) {
                result.error("CANCELLED", "用户取消保存", null)
                return
            }
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(save["bytes"] as ByteArray) }
                    ?: throw IllegalStateException("无法打开目标文件")
                result.success(uri.toString())
            } catch (e: Exception) {
                result.error("WRITE_FAILED", e.message, null)
            }
        } else if (requestCode == OPEN_DOCUMENT) {
            val result = pendingOpenResult
            pendingOpenResult = null
            val uri = data?.data
            if (result == null) return
            if (resultCode != RESULT_OK || uri == null) {
                result.error("CANCELLED", "用户取消选择", null)
                return
            }
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("无法读取文件")
                result.success(mapOf("uri" to uri.toString(), "bytes" to bytes))
            } catch (e: Exception) {
                result.error("READ_FAILED", e.message, null)
            }
        }
    }
}
