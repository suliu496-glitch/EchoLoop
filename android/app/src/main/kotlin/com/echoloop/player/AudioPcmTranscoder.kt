package com.echoloop.player

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt

/** Decodes non-AAC source tracks and writes upload-sized 16 kHz mono PCM WAV files. */
internal object AudioPcmTranscoder {
    private const val OUTPUT_SAMPLE_RATE = 16_000
    private const val CHUNK_DURATION_SECONDS = 8 * 60
    private const val MAX_RAW_BYTES = 1_500_000_000L

    fun transcode(
        extractor: MediaExtractor,
        format: MediaFormat,
        mime: String,
        runDir: File,
    ): List<Map<String, Any>> {
        val decoder = MediaCodec.createDecoderByType(mime)
        val rawFile = File(runDir, "decoded_${UUID.randomUUID()}.pcm")
        var decoderStarted = false
        try {
            decoder.configure(format, null, null, 0)
            decoder.start()
            decoderStarted = true
            FileOutputStream(rawFile).use { output ->
                decodeToMonoPcm(decoder, extractor, output)
            }

            if (!rawFile.exists() || rawFile.length() == 0L) {
                throw IllegalArgumentException("音轨解码后没有有效音频")
            }
            if (rawFile.length() > MAX_RAW_BYTES) {
                throw IllegalArgumentException("解码后的音频临时文件过大，建议先截取需要精听的片段")
            }
            return splitPcmIntoWav(rawFile, runDir)
        } finally {
            if (decoderStarted) runCatching { decoder.stop() }
            decoder.release()
            rawFile.delete()
        }
    }

    private fun decodeToMonoPcm(
        decoder: MediaCodec,
        extractor: MediaExtractor,
        output: FileOutputStream,
    ) {
        val info = MediaCodec.BufferInfo()
        var inputFinished = false
        var outputFinished = false
        var sampleRate = 0
        var channelCount = 0
        var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
        val resampler = Resampler()

        fun readOutputFormat(format: MediaFormat) {
            sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            pcmEncoding = runCatching {
                format.getInteger(MediaFormat.KEY_PCM_ENCODING)
            }.getOrDefault(AudioFormat.ENCODING_PCM_16BIT)
            if (sampleRate <= 0 || channelCount <= 0) {
                throw IllegalArgumentException("系统返回了无效的音频格式")
            }
        }

        while (!outputFinished) {
            if (!inputFinished) {
                val inputIndex = decoder.dequeueInputBuffer(10_000)
                if (inputIndex >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputIndex)
                        ?: throw IllegalStateException("解码器输入缓冲区不可用")
                    inputBuffer.clear()
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(
                            inputIndex,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        inputFinished = true
                    } else {
                        val timeUs = extractor.sampleTime.coerceAtLeast(0L)
                        decoder.queueInputBuffer(
                            inputIndex,
                            0,
                            sampleSize,
                            timeUs,
                            extractor.sampleFlags,
                        )
                        extractor.advance()
                    }
                }
            }

            val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)
            when {
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    readOutputFormat(decoder.outputFormat)
                }

                outputIndex >= 0 -> {
                    val buffer = decoder.getOutputBuffer(outputIndex)
                    if (info.size > 0 && buffer != null) {
                        if (sampleRate <= 0 || channelCount <= 0) {
                            readOutputFormat(decoder.outputFormat)
                        }
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        writeResampledMono(
                            buffer.slice().order(ByteOrder.LITTLE_ENDIAN),
                            info.size,
                            sampleRate,
                            channelCount,
                            pcmEncoding,
                            resampler,
                            output,
                        )
                    }
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputFinished = true
                    }
                    decoder.releaseOutputBuffer(outputIndex, false)
                }
            }
        }
    }

    private fun writeResampledMono(
        buffer: ByteBuffer,
        byteCount: Int,
        sampleRate: Int,
        channelCount: Int,
        pcmEncoding: Int,
        resampler: Resampler,
        output: FileOutputStream,
    ) {
        val bytesPerSample = when (pcmEncoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> 4
            AudioFormat.ENCODING_PCM_8BIT -> 1
            else -> 2
        }
        val frameSize = bytesPerSample * channelCount
        val frameCount = byteCount / frameSize
        if (frameCount <= 0) return
        val monoFrames = DoubleArray(frameCount)
        for (frame in 0 until frameCount) {
            var sum = 0.0
            for (channel in 0 until channelCount) {
                val offset = frame * frameSize + channel * bytesPerSample
                sum += if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
                    buffer.getFloat(offset).toDouble().coerceIn(-1.0, 1.0) * Short.MAX_VALUE
                } else if (pcmEncoding == AudioFormat.ENCODING_PCM_8BIT) {
                    ((buffer.get(offset).toInt() and 0xff) - 128) * 256.0
                } else {
                    buffer.getShort(offset).toDouble()
                }
            }
            monoFrames[frame] = sum / channelCount
        }

        val sourceStart = resampler.sourceFramesSeen
        val sourceEnd = sourceStart + frameCount
        val targetEnd = sourceEnd * OUTPUT_SAMPLE_RATE / sampleRate
        val targetFrames = (targetEnd - resampler.outputFramesWritten).toInt()
        if (targetFrames > 0) {
            val outBytes = ByteBuffer.allocate(targetFrames * 2).order(ByteOrder.LITTLE_ENDIAN)

            for (target in 0 until targetFrames) {
                val outputFrame = resampler.outputFramesWritten + target
                val sourcePosition = outputFrame.toDouble() * sampleRate / OUTPUT_SAMPLE_RATE
                val sourceIndex = floor(sourcePosition).toLong()
                val fraction = sourcePosition - sourceIndex
                val left = when {
                    sourceIndex < sourceStart -> resampler.previousMonoFrame ?: monoFrames.first()
                    else -> monoFrames[(sourceIndex - sourceStart).toInt().coerceIn(0, frameCount - 1)]
                }
                val nextIndex = sourceIndex + 1
                val right = when {
                    nextIndex < sourceStart -> resampler.previousMonoFrame ?: left
                    nextIndex >= sourceEnd -> monoFrames.last()
                    else -> monoFrames[(nextIndex - sourceStart).toInt()]
                }
                val interpolated = left * (1.0 - fraction) + right * fraction
                outBytes.putShort(interpolated.roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort())
            }
            output.write(outBytes.array())
            if (output.channel.position() > MAX_RAW_BYTES) {
                throw IllegalArgumentException(
                    "解码后的音频临时文件过大，建议先截取需要精听的片段",
                )
            }
        }
        resampler.sourceFramesSeen = sourceEnd
        resampler.outputFramesWritten = targetEnd
        resampler.previousMonoFrame = monoFrames.last()
    }

    private fun splitPcmIntoWav(
        rawFile: File,
        runDir: File,
    ): List<Map<String, Any>> {
        val bytesPerSecond = OUTPUT_SAMPLE_RATE * 2L
        val chunkBytesLimit = CHUNK_DURATION_SECONDS * bytesPerSecond
        val result = mutableListOf<Map<String, Any>>()
        val buffer = ByteArray(64 * 1024)
        BufferedInputStream(FileInputStream(rawFile)).use { input ->
            var offsetBytes = 0L
            var index = 0
            while (true) {
                val dataBytes = min(chunkBytesLimit, rawFile.length() - offsetBytes).toInt()
                if (dataBytes <= 0) break
                val alignedDataBytes = dataBytes - (dataBytes % 2)
                val chunkFile = File(runDir, "audio_${index.toString().padStart(3, '0')}.wav")
                BufferedOutputStream(FileOutputStream(chunkFile)).use { output ->
                    output.write(wavHeader(alignedDataBytes))
                    var remaining = alignedDataBytes
                    while (remaining > 0) {
                        val read = input.read(buffer, 0, min(buffer.size, remaining))
                        if (read < 0) throw IllegalStateException("临时音频数据不完整")
                        output.write(buffer, 0, read)
                        remaining -= read
                    }
                }
                val startMs = (offsetBytes * 1000L / bytesPerSecond).toInt()
                val durationMs = (alignedDataBytes * 1000L / bytesPerSecond).toInt()
                result += mapOf(
                    "path" to chunkFile.absolutePath,
                    "startMs" to startMs,
                    "durationMs" to durationMs,
                )
                offsetBytes += alignedDataBytes
                index += 1
            }
        }
        if (result.isEmpty()) throw IllegalArgumentException("没有生成可识别的音频分段")
        return result
    }

    private fun wavHeader(dataBytes: Int): ByteArray =
        ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(36 + dataBytes)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(1)
            putShort(1)
            putInt(OUTPUT_SAMPLE_RATE)
            putInt(OUTPUT_SAMPLE_RATE * 2)
            putShort(2)
            putShort(16)
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataBytes)
        }.array()

    private class Resampler(
        var sourceFramesSeen: Long = 0,
        var outputFramesWritten: Long = 0,
        var previousMonoFrame: Double? = null,
    )
}
