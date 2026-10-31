package com.echoloop.player

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * Flutter ⇄ Android 原生 的唯一桥接层。
 *
 * 把「必须走系统能力」的事情收在一处，Flutter 侧只面对语义化方法名，
 * 不需要关心 API Level 差异（例如 Android 13 的 READ_MEDIA_* 细分权限）。
 *
 * 通道名见 [MainActivity.CHANNEL_NAME]，方法清单见 [onMethodCall] 的分支。
 */
class NativeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    channelName: String,
) : MethodChannel.MethodCallHandler {

    private companion object {
        const val REQ_PICK_MEDIA = 9001
        const val REQ_PICK_SUBTITLE = 9002
        const val REQ_PERMISSION = 9101

        const val PICK_MEDIA = 0
        const val PICK_SUBTITLE = 1
    }

    private val channel = MethodChannel(messenger, channelName)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val recorder = RecorderHelper(activity)
    private val transcriptionExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingPickKind = PICK_MEDIA
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** 通知栏动作回调的持有者，见 [PlaybackService.actionListener]。 */
    private val notificationActionListener: (String) -> Unit = { action ->
        mainHandler.post {
            runCatching { channel.invokeMethod("onNotificationAction", mapOf("action" to action)) }
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun attach() {
        PlaybackService.actionListener = notificationActionListener
    }

    fun detach() {
        PlaybackService.actionListener = null
        pendingPickResult = null
        pendingPermissionResult = null
        recorder.cancel()
        transcriptionExecutor.shutdownNow()
        PlaybackPathResolver.releaseAll()
        channel.setMethodCallHandler(null)
    }

    // ------------------------------------------------------------------
    // 方法分发
    // ------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickMediaFiles" -> launchPicker(result, PICK_MEDIA, call.argument<Boolean>("allowMultiple") ?: true)
            "pickSubtitleFile" -> launchPicker(result, PICK_SUBTITLE, false)
            "scanMediaStore" -> handleScan(call, result)
            "resolvePlayablePath" -> handleResolve(call, result)
            "releasePlayablePath" -> {
                call.argument<String>("uri")?.let { PlaybackPathResolver.release(it) }
                result.success(true)
            }
            "releaseAllPlayablePaths" -> {
                PlaybackPathResolver.releaseAll()
                result.success(true)
            }
            "exportTranscriptionAudio" -> handleExportTranscriptionAudio(call, result)
            "deleteTranscriptionAudio" -> handleDeleteTranscriptionAudio(call, result)
            "hasTranscriberApiKey" -> result.success(SecureStore.hasTranscriberApiKey(activity))
            "readTranscriberApiKey" -> result.success(SecureStore.readTranscriberApiKey(activity))
            "saveTranscriberApiKey" -> handleSaveTranscriberApiKey(call, result)
            "clearTranscriberApiKey" -> {
                SecureStore.clearTranscriberApiKey(activity)
                result.success(true)
            }
            "createThumbnail" -> handleThumbnail(call, result)
            "readTextFile" -> handleReadText(call, result)
            "checkPermissions" -> result.success(checkPermissionGroups(call.argument<List<String>>("groups").orEmpty()))
            "requestPermissions" -> handleRequestPermissions(call, result)
            "startRecording" -> result.success(recorder.start(call.argument<String>("outPath").orEmpty()))
            "stopRecording" -> result.success(recorder.stop())
            "cancelRecording" -> {
                recorder.cancel()
                result.success(true)
            }
            "startForegroundPlayback" -> result.success(pushNotification(call))
            "updatePlaybackNotification" -> result.success(pushNotification(call))
            "stopForegroundPlayback" -> {
                stopService()
                result.success(true)
            }
            "openAppNotificationSettings" -> {
                result.success(openNotificationSettings())
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------
    // 文件导入（SAF）
    // ------------------------------------------------------------------

    private fun launchPicker(result: MethodChannel.Result, kind: Int, allowMultiple: Boolean) {
        if (pendingPickResult != null) {
            result.error("busy", "已有文件选择正在进行中", null)
            return
        }
        pendingPickResult = result
        pendingPickKind = kind

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // 具体类型由 EXTRA_MIME_TYPES 收窄，这里必须给通配，否则部分机型会过滤掉合法文件
            type = "*/*"
            if (kind == PICK_MEDIA) {
                // 只展示音视频，字幕文件单独走 pickSubtitleFile
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("video/*", "audio/*"),
                )
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            } else {
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "text/*",
                        "application/x-subrip",
                        "application/octet-stream",
                    ),
                )
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }

        val requestCode = if (kind == PICK_MEDIA) REQ_PICK_MEDIA else REQ_PICK_SUBTITLE
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("no_picker", "未找到可用的文件选择器：${e.message}", null)
        }
    }

    /** @return true 表示本层已消费该回调。 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_MEDIA && requestCode != REQ_PICK_SUBTITLE) return false
        val result = pendingPickResult ?: return true
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(if (pendingPickKind == PICK_MEDIA) emptyList<Map<String, Any?>>() else null)
            return true
        }

        val uris = collectUris(data)
        if (uris.isEmpty()) {
            result.success(if (pendingPickKind == PICK_MEDIA) emptyList<Map<String, Any?>>() else null)
            return true
        }

        if (pendingPickKind == PICK_SUBTITLE) {
            val uri = uris.first()
            val name = MediaImporter.describe(activity, uri).name
            val content = readText(uri)
            if (content == null) {
                result.error("read_failed", "字幕文件读取失败，请确认文件可访问", null)
            } else {
                result.success(mapOf("uri" to uri.toString(), "name" to name, "content" to content))
            }
            return true
        }

        val entries = uris.map { uri ->
            // 申请持久化读取权限，避免重启后 URI 失效（不复制文件，只保留引用）
            runCatching {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            MediaImporter.describe(activity, uri).toMap()
        }
        result.success(entries)
        return true
    }

    private fun collectUris(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        }
        data.data?.let { uris.add(it) }
        return uris.distinct()
    }

    // ------------------------------------------------------------------
    // MediaStore 扫描（设备已有媒体，零拷贝）
    // ------------------------------------------------------------------

    private fun handleScan(call: MethodCall, result: MethodChannel.Result) {
        val scope = call.argument<String>("scope") ?: "all"
        val keyword = call.argument<String>("keyword")?.trim().orEmpty()
        val out = mutableListOf<Map<String, Any?>>()

        if (scope == "video" || scope == "all") {
            out.addAll(queryCollection(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true, keyword))
        }
        if (scope == "audio" || scope == "all") {
            out.addAll(queryCollection(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, false, keyword))
        }
        result.success(out)
    }

    private fun queryCollection(
        collection: Uri,
        isVideo: Boolean,
        keyword: String,
    ): List<Map<String, Any?>> {
        val columns = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        // Video 的 DURATION 列 API 29 才加入，低版本查了会抛异常
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            columns.add(MediaStore.MediaColumns.DURATION)
        }

        val selection = if (keyword.isEmpty()) null else "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        val args = if (keyword.isEmpty()) null else arrayOf("%$keyword%")

        val rows = mutableListOf<Map<String, Any?>>()
        runCatching {
            activity.contentResolver.query(
                collection,
                columns.toTypedArray(),
                selection,
                args,
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                val mimeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                val durIdx = columns.indexOf(MediaStore.MediaColumns.DURATION)

                while (cursor.moveToNext() && rows.size < 500) {
                    val id = cursor.getLong(idIdx)
                    val uri = android.content.ContentUris.withAppendedId(collection, id)
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "未知文件" else "未知文件"
                    val mime = if (mimeIdx >= 0) cursor.getString(mimeIdx).orEmpty() else ""
                    if (!MediaImporter.isSupportedMedia(name, mime)) continue
                    rows.add(
                        MediaEntry(
                            uri = uri.toString(),
                            name = name,
                            sizeBytes = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L,
                            mimeType = mime,
                            durationMs = if (durIdx >= 0 && !cursor.isNull(durIdx)) cursor.getLong(durIdx) else 0L,
                            isVideo = MediaImporter.isVideoFile(name, mime),
                        ).toMap(),
                    )
                }
            }
        }
        return rows
    }

    // ------------------------------------------------------------------
    // 播放路径 / 缩略图 / 文本读取
    // ------------------------------------------------------------------

    private fun handleResolve(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        if (uri.isNullOrBlank()) {
            result.success(mapOf("path" to null, "mode" to "error", "message" to "缺少文件 URI"))
            return
        }
        result.success(runCatching { PlaybackPathResolver.resolve(activity, uri) }.getOrElse {
            mapOf("path" to null, "mode" to "error", "message" to "文件解析失败：${it.message}")
        })
    }

    private fun handleExportTranscriptionAudio(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        if (uri.isNullOrBlank()) {
            result.error("missing_uri", "缺少媒体文件 URI", null)
            return
        }
        transcriptionExecutor.execute {
            runCatching {
                AudioChunkExporter.export(activity.applicationContext, uri)
            }.onSuccess { chunks ->
                mainHandler.post { result.success(chunks) }
            }.onFailure { error ->
                mainHandler.post {
                    result.error(
                        "audio_export_failed",
                        error.message ?: "无法准备识别音频",
                        null,
                    )
                }
            }
        }
    }

    private fun handleDeleteTranscriptionAudio(call: MethodCall, result: MethodChannel.Result) {
        val root = File(activity.cacheDir, "echoloop-transcription").canonicalFile
        val paths = call.argument<List<String>>("paths").orEmpty()
        paths.forEach { path ->
            runCatching {
                val candidate = File(path).canonicalFile
                if (candidate.path.startsWith(root.path + File.separator)) candidate.delete()
            }
        }
        root.listFiles()?.forEach { if (it.isDirectory && it.list().isNullOrEmpty()) it.delete() }
        result.success(true)
    }

    private fun handleSaveTranscriberApiKey(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("value")
        if (value.isNullOrBlank()) {
            result.error("empty_api_key", "API Key 不能为空", null)
            return
        }
        runCatching { SecureStore.saveTranscriberApiKey(activity, value.trim()) }
            .onSuccess { result.success(true) }
            .onFailure { result.error("secure_store_failed", "API Key 保存失败", null) }
    }

    private fun handleThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        if (uri.isNullOrBlank()) {
            result.success(null)
            return
        }
        val outPath = call.argument<String>("outPath")
        if (outPath.isNullOrBlank()) {
            result.success(null)
            return
        }
        val timeMs = (call.argument<Number>("timeMs")?.toLong()) ?: -1L
        val maxWidth = call.argument<Number>("maxWidth")?.toInt() ?: 480
        result.success(ThumbnailHelper.create(activity, uri, timeMs, outPath, maxWidth))
    }

    private fun handleReadText(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val text = uri?.let { readText(Uri.parse(it)) }
        if (text == null) {
            result.error("read_failed", "文件读取失败或为空", null)
        } else {
            result.success(text)
        }
    }

    /**
     * 读取字幕文本。
     *
     * 编码处理是这里的关键：中文字幕常见 UTF-8 / GBK 混用，直接按 UTF-8 解码会变乱码。
     * 策略是先去掉 BOM，再严格 UTF-8 解码，失败则回退 GB18030（GBK 超集）。
     */
    private fun readText(uri: Uri): String? {
        val bytes = runCatching {
            activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrNull() ?: return null
        if (bytes.isEmpty()) return null

        var offset = 0
        if (bytes.size >= 3 &&
            bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()
        ) {
            offset = 3
        }
        val buffer = ByteBuffer.wrap(bytes, offset, bytes.size - offset)
        return try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(buffer)
                .toString()
        } catch (_: CharacterCodingException) {
            runCatching { String(bytes, offset, bytes.size - offset, charset("GB18030")) }.getOrNull()
        }
    }

    // ------------------------------------------------------------------
    // 权限
    // ------------------------------------------------------------------

    /** 逻辑权限组 → 实际权限清单，屏蔽 API Level 差异。 */
    private fun permissionsFor(group: String): List<String> = when (group) {
        "mediaVideo" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            )
        } else {
            listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        "mediaAudio" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        "microphone" -> listOf(Manifest.permission.RECORD_AUDIO)
        "notification" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            emptyList()
        }

        else -> emptyList()
    }

    private fun isGroupGranted(group: String): Boolean {
        val permissions = permissionsFor(group)
        if (permissions.isEmpty()) return true
        val states = permissions.map {
            ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
        }
        // 视频组在 Android 14 支持「部分访问」，只要拿到任一即视为可用
        return if (group == "mediaVideo") states.any { it } else states.all { it }
    }

    private fun checkPermissionGroups(groups: List<String>): Map<String, Boolean> =
        groups.associateWith { isGroupGranted(it) }

    private fun handleRequestPermissions(call: MethodCall, result: MethodChannel.Result) {
        val groups = call.argument<List<String>>("groups").orEmpty()
        if (groups.isEmpty()) {
            result.success(emptyMap<String, Boolean>())
            return
        }
        val missing = groups
            .flatMap { permissionsFor(it) }
            .distinct()
            .filter { ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED }

        if (missing.isEmpty()) {
            result.success(checkPermissionGroups(groups))
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQ_PERMISSION)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQ_PERMISSION) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        // 权限组结果由系统状态反查，避免依赖回调顺序
        result.success(checkPermissionGroups(listOf("mediaVideo", "mediaAudio", "microphone", "notification")))
        return true
    }

    private fun openNotificationSettings(): Boolean = runCatching {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", activity.packageName, null))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
        true
    }.getOrDefault(false)

    // ------------------------------------------------------------------
    // 前台服务
    // ------------------------------------------------------------------

    private fun pushNotification(call: MethodCall): Boolean = runCatching {
        val intent = Intent(activity, PlaybackService::class.java).apply {
            action = PlaybackService.ACTION_UPDATE
            putExtra(PlaybackService.EXTRA_TITLE, call.argument<String>("title").orEmpty())
            putExtra(PlaybackService.EXTRA_TEXT, call.argument<String>("text").orEmpty())
            putExtra(PlaybackService.EXTRA_PLAYING, call.argument<Boolean>("playing") ?: false)
            putExtra(PlaybackService.EXTRA_POSITION, (call.argument<Number>("positionMs") ?: 0).toLong())
            putExtra(PlaybackService.EXTRA_DURATION, (call.argument<Number>("durationMs") ?: 0).toLong())
            putExtra(PlaybackService.EXTRA_KEEP_AWAKE, call.argument<Boolean>("keepAwake") ?: false)
            putExtra(
                PlaybackService.EXTRA_SPEED,
                (call.argument<Number>("speed") ?: 1.0).toFloat(),
            )
        }
        ContextCompat.startForegroundService(activity, intent)
        true
    }.getOrDefault(false)

    private fun stopService(): Boolean = runCatching {
        activity.startService(
            Intent(activity, PlaybackService::class.java).setAction(PlaybackService.ACTION_STOP),
        )
        true
    }.getOrDefault(false)
}

/** 把原生条目统一成 Flutter 侧的 Map 结构。 */
private fun MediaEntry.toMap(): Map<String, Any?> = mapOf(
    "uri" to uri,
    "name" to name,
    "sizeBytes" to sizeBytes,
    "mimeType" to mimeType,
    "durationMs" to durationMs,
    "isVideo" to isVideo,
)

/** 供 Flutter 侧清理临时文件时使用。 */
internal fun deleteQuietly(path: String?) {
    if (path.isNullOrBlank()) return
    runCatching { File(path).delete() }
}
