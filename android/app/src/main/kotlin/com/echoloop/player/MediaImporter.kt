package com.echoloop.player

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns

/** 一次导入/扫描出来的媒体条目，字段与 Flutter 侧 `ImportedMedia` 一一对应。 */
data class MediaEntry(
    val uri: String,
    val name: String,
    val sizeBytes: Long,
    val mimeType: String,
    val durationMs: Long,
    val isVideo: Boolean,
)

/**
 * 媒体导入助手。
 *
 * 设计原则（对应需求 §4.3「数据流转规则」）：
 * 本应用**只记录 URI 引用**，绝不复制、移动用户的原始文件。
 * 因此这里所有操作都是「读取元数据」，没有任何写文件动作。
 */
object MediaImporter {

    private val VIDEO_EXT = setOf("mp4", "mkv", "avi", "mov", "flv", "webm")
    private val AUDIO_EXT = setOf("mp3", "wav", "m4a", "aac", "flac", "ogg")

    /** 通过 SAF 选中的文件：读取显示名 / 体积 / MIME / 时长。 */
    fun describe(context: Context, uri: Uri): MediaEntry {
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "未知文件"
        var size = 0L
        var mime = context.contentResolver.getType(uri) ?: ""

        // OpenableColumns 是 SAF 文档提供者最通用的元数据入口
        runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0 && !cursor.isNull(nameIdx)) name = cursor.getString(nameIdx)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
                }
            }
        }

        val durationMs = readDuration(context, uri)
        if (mime.isEmpty()) mime = guessMimeFromName(name)

        return MediaEntry(
            uri = uri.toString(),
            name = name,
            sizeBytes = size,
            mimeType = mime,
            durationMs = durationMs,
            isVideo = isVideoFile(name, mime),
        )
    }

    /** 用系统元数据解析器读取时长，失败（文件损坏/编码不支持）返回 0。 */
    fun readDuration(context: Context, uri: Uri): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
        } catch (_: Exception) {
            0L
        } finally {
            runCatching { retriever.release() }
        }
    }

    fun isVideoFile(name: String, mime: String): Boolean {
        if (mime.startsWith("video/")) return true
        if (mime.startsWith("audio/")) return false
        val ext = name.substringAfterLast('.', "").lowercase()
        return VIDEO_EXT.contains(ext)
    }

    /** 按扩展名判断是否属于本应用支持的媒体格式。 */
    fun isSupportedMedia(name: String, mime: String): Boolean {
        if (mime.startsWith("video/") || mime.startsWith("audio/")) return true
        val ext = name.substringAfterLast('.', "").lowercase()
        return VIDEO_EXT.contains(ext) || AUDIO_EXT.contains(ext)
    }

    private fun guessMimeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "flv" -> "video/x-flv"
            "webm" -> "video/webm"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "m4a" -> "audio/mp4"
            "aac" -> "audio/aac"
            "flac" -> "audio/flac"
            "ogg" -> "audio/ogg"
            else -> ""
        }
    }
}
