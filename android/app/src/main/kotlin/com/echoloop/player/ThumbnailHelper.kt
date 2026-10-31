package com.echoloop.player

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

/**
 * 视频封面抽帧。纯音频文件没有画面帧，返回 null，由 Flutter 侧回退成音符图标。
 */
object ThumbnailHelper {

    /**
     * @param timeMs  抽帧时间点（毫秒），传 -1 表示取首帧
     * @param maxWidth 输出图最大宽度，等比例缩放，控制缓存体积
     * @return 成功返回写出的文件路径，失败返回 null
     */
    fun create(
        context: Context,
        rawUri: String,
        timeMs: Long,
        outPath: String,
        maxWidth: Int,
    ): String? {
        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        return try {
            retriever.setDataSource(context, Uri.parse(rawUri))
            val frameTimeUs = if (timeMs >= 0) timeMs * 1000 else -1L
            bitmap = if (frameTimeUs >= 0) {
                retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } else {
                retriever.getFrameAtTime()
            }
            bitmap ?: return null

            val scaled = scaleDown(bitmap, maxWidth)
            val out = File(outPath)
            out.parentFile?.mkdirs()
            FileOutputStream(out).use { stream ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
            }
            if (scaled !== bitmap) scaled.recycle()
            outPath
        } catch (_: Exception) {
            null
        } finally {
            bitmap?.let { if (!it.isRecycled) it.recycle() }
            runCatching { retriever.release() }
        }
    }

    private fun scaleDown(source: Bitmap, maxWidth: Int): Bitmap {
        if (source.width <= maxWidth) return source
        val ratio = maxWidth.toFloat() / source.width
        val height = (source.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, maxWidth, height, true)
    }
}
