package com.echoloop.player

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore

/**
 * 把数据库里保存的 URI 转换成 libmpv 能直接打开的文件路径。
 *
 * 背景：media_kit 底层的 mpv 不能直接读 Android 的 `content://` URI，必须给出
 * 一个真实可访问的路径。两条路线，按代价从低到高依次尝试：
 *
 * 1. **真实路径**：MediaStore 里的媒体文件可以通过 `DATA` 列拿到
 *    `/storage/emulated/0/...` 这样的路径，配合 READ_MEDIA_* 权限可直接读取。
 *
 * 2. **文件描述符路径**：SAF 选中的文件（不在 MediaStore 索引里）没有真实路径，
 *    此时打开文件描述符并暴露成 `/proc/self/fd/N`。对 mpv 来说它是一个普通文件，
 *    可 seek、可读取。代价是必须持有 Pdf 直到播放结束，否则路径立即失效，
 *    因此这里用一个进程级 Map 缓存，播放切换时由 Flutter 侧显式释放。
 */
object PlaybackPathResolver {

    private val openedFds = LinkedHashMap<String, ParcelFileDescriptor>()

    /** 解析结果中的 `path` 为 null 时表示失败，`message` 给出可读原因。 */
    fun resolve(context: Context, rawUri: String): Map<String, Any?> {
        val uri = Uri.parse(rawUri)

        // 普通文件路径或 file:// URI，直接用
        if (uri.scheme == null || uri.scheme == "file") {
            return mapOf("path" to (uri.path ?: rawUri), "mode" to "path")
        }

        if (uri.scheme != "content") {
            // 其他协议（http 等）交给 mpv 自己处理，本应用是离线的，正常不会走到这里
            return mapOf("path" to rawUri, "mode" to "uri")
        }

        val realPath = queryRealPath(context, uri)
        if (realPath != null) {
            return mapOf("path" to realPath, "mode" to "path")
        }

        // 回退：暴露文件描述符
        release(rawUri)
        val pfd = try {
            context.contentResolver.openFileDescriptor(uri, "r")
        } catch (_: Exception) {
            null
        } ?: return mapOf(
            "path" to null,
            "mode" to "error",
            "message" to "无法打开该文件，可能已被移动或删除",
        )

        openedFds[rawUri] = pfd
        return mapOf("path" to "/proc/self/fd/${pfd.fd}", "mode" to "fd")
    }

    /** 释放某个 URI 占用的文件描述符（切换媒体时调用，避免 fd 泄漏）。 */
    fun release(rawUri: String) {
        openedFds.remove(rawUri)?.let { runCatching { it.close() } }
    }

    /** 释放全部文件描述符（播放页退出时调用）。 */
    fun releaseAll() {
        openedFds.values.forEach { runCatching { it.close() } }
        openedFds.clear()
    }

    private fun queryRealPath(context: Context, uri: Uri): String? {
        // DATA 列在 API 29 起被标记废弃，但对 MediaStore 索引内的媒体仍然可查
        val path = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (idx >= 0 && !cursor.isNull(idx)) cursor.getString(idx) else null
                } else {
                    null
                }
            }
        }.getOrNull() ?: return null

        if (path.isEmpty()) return null
        val file = java.io.File(path)
        return if (file.exists() && file.canRead()) path else null
    }
}
