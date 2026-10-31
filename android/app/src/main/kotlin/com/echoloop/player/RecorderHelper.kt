package com.echoloop.player

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/**
 * 麦克风录音助手（跟读对比用）。
 *
 * 输出为单声道 AAC / MPEG_4，文件写在应用私有缓存目录，随时可整目录删除，
 * 不进入用户媒体库，对应需求 §3.3「录音文件临时存储，可一键删除，不做长期保存」。
 */
class RecorderHelper(private val context: Context) {

    private var recorder: MediaRecorder? = null
    private var outputPath: String? = null
    private var startedAt: Long = 0L

    val isRecording: Boolean get() = recorder != null

    /** 开始录音；返回 null 表示成功，否则返回可读的错误信息。 */
    fun start(outPath: String): String? {
        if (recorder != null) return "上一次录音尚未结束"
        val target = File(outPath)
        target.parentFile?.mkdirs()

        val instance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        return try {
            instance.setAudioSource(MediaRecorder.AudioSource.MIC)
            instance.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            instance.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            instance.setAudioSamplingRate(44100)
            instance.setAudioEncodingBitRate(96000)
            instance.setAudioChannels(1)
            instance.setOutputFile(target.absolutePath)
            instance.prepare()
            instance.start()
            recorder = instance
            outputPath = target.absolutePath
            startedAt = System.currentTimeMillis()
            null
        } catch (e: Exception) {
            runCatching { instance.release() }
            recorder = null
            outputPath = null
            "录音启动失败：${e.message ?: "设备不支持或麦克风被占用"}"
        }
    }

    /** 停止录音，成功返回 { path, durationMs }，失败返回 { error }。 */
    fun stop(): Map<String, Any?> {
        val instance = recorder ?: return mapOf("error" to "当前没有进行中的录音")
        val path = outputPath
        recorder = null
        outputPath = null
        val elapsed = System.currentTimeMillis() - startedAt

        return try {
            instance.stop()
            instance.release()
            // 极短的录音在部分机型上会产出 0 字节文件，做一次兜底校验
            if (path == null || !File(path).exists() || File(path).length() == 0L) {
                mapOf("error" to "录音文件为空，请靠近麦克风重试")
            } else {
                mapOf("path" to path, "durationMs" to elapsed)
            }
        } catch (e: Exception) {
            runCatching { instance.release() }
            mapOf("error" to "录音结束异常：${e.message ?: "未知错误"}")
        }
    }

    /** 放弃当前录音并删除临时文件。 */
    fun cancel() {
        recorder?.let {
            runCatching { it.stop() }
            runCatching { it.release() }
        }
        recorder = null
        outputPath?.let { runCatching { File(it).delete() } }
        outputPath = null
    }
}
