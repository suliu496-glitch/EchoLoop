package com.echoloop.player

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID

/**
 * Extracts an AAC audio track from a local media file and remuxes it into small,
 * audio-only M4A chunks. The source file is never modified.
 */
internal object AudioChunkExporter {
    private const val CHUNK_DURATION_US = 8L * 60L * 1_000_000L
    private const val TARGET_CHUNK_BYTES = 20L * 1024L * 1024L

    fun export(context: Context, uriString: String): List<Map<String, Any>> {
        val outputRoot = File(context.cacheDir, "echoloop-transcription")
        if (!outputRoot.exists() && !outputRoot.mkdirs()) {
            throw IllegalStateException("无法创建转写临时目录")
        }
        val runDir = File(outputRoot, UUID.randomUUID().toString())
        if (!runDir.mkdirs()) throw IllegalStateException("无法创建转写任务目录")

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, Uri.parse(uriString), null)
            val audioTrack = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index)
                    .getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("这个文件没有可识别的音轨")

            val format = extractor.getTrackFormat(audioTrack)
            val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
            val durationUs = readDurationUs(context, uriString, format)

            extractor.selectTrack(audioTrack)
            if (mime != "audio/mp4a-latm" || durationUs <= 0L) {
                return AudioPcmTranscoder.transcode(extractor, format, mime, runDir)
            }

            val maxInputSize = runCatching {
                format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            }.getOrDefault(256 * 1024).coerceAtLeast(256 * 1024)
            val bitRate = runCatching {
                format.getInteger(MediaFormat.KEY_BIT_RATE)
            }.getOrDefault(128_000).coerceAtLeast(32_000)
            val estimatedChunkDurationUs = TARGET_CHUNK_BYTES * 8L * 1_000_000L / bitRate
            val chunkDurationUs = minOf(CHUNK_DURATION_US, estimatedChunkDurationUs)
            val chunks = mutableListOf<Map<String, Any>>()
            var startUs = 0L
            var index = 0

            while (startUs < durationUs) {
                val endUs = (startUs + chunkDurationUs).coerceAtMost(durationUs)
                val outFile = File(runDir, "audio_${index.toString().padStart(3, '0')}.m4a")
                writeChunk(extractor, format, outFile, startUs, endUs, maxInputSize)
                chunks += mapOf(
                    "path" to outFile.absolutePath,
                    "startMs" to (startUs / 1_000L).toInt(),
                    "durationMs" to ((endUs - startUs) / 1_000L).toInt(),
                )
                startUs = endUs
                index += 1
            }

            if (chunks.isEmpty()) throw IllegalArgumentException("没有提取到音频")
            return chunks
        } catch (error: Throwable) {
            runCatching { runDir.deleteRecursively() }
            throw error
        } finally {
            extractor.release()
        }
    }

    private fun writeChunk(
        extractor: MediaExtractor,
        format: MediaFormat,
        output: File,
        startUs: Long,
        endUs: Long,
        maxInputSize: Int,
    ) {
        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerStarted = false
        var wroteSample = false
        try {
            val outputTrack = muxer.addTrack(format)
            muxer.start()
            muxerStarted = true
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val buffer = ByteBuffer.allocateDirect(maxInputSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs < 0L || sampleTimeUs >= endUs) break
                if (sampleTimeUs >= startUs) {
                    info.set(
                        0,
                        size,
                        sampleTimeUs - startUs,
                        extractor.sampleFlags,
                    )
                    muxer.writeSampleData(outputTrack, buffer, info)
                    wroteSample = true
                }
                if (!extractor.advance()) break
            }
            if (!wroteSample) throw IllegalArgumentException("音轨分段后没有有效音频数据")
        } finally {
            if (muxerStarted) runCatching { muxer.stop() }
            muxer.release()
        }
    }

    private fun readDurationUs(context: Context, uriString: String, format: MediaFormat): Long {
        val fromFormat = runCatching { format.getLong(MediaFormat.KEY_DURATION) }
            .getOrDefault(0L)
        if (fromFormat > 0L) return fromFormat
        val retriever = MediaMetadataRetriever()
        return runCatching {
            retriever.setDataSource(context, Uri.parse(uriString))
            (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L) * 1_000L
        }.getOrDefault(0L).also { retriever.release() }
    }
}
