import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/errors/app_exception.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/app_settings.dart';
import '../../domain/subtitles/sentence_segmenter.dart';
import '../../services/native_channel.dart';
import 'transcriber.dart';

/// OpenAI Whisper-compatible transcription client.
///
/// The endpoint and API key are supplied by the user. Media is uploaded in
/// bounded pieces; source files are never modified and exported audio is
/// removed after the request completes.
class WhisperTranscriber implements Transcriber {
  WhisperTranscriber({
    required NativeChannel channel,
    required AppSettings Function() readSettings,
    required Future<String?> Function() readApiKey,
  }) : _channel = channel,
       _readSettings = readSettings,
       _readApiKey = readApiKey;

  final NativeChannel _channel;
  final AppSettings Function() _readSettings;
  final Future<String?> Function() _readApiKey;

  static const int _maximumUploadBytes = 25 * 1024 * 1024;

  @override
  String get id => 'whisper-compatible';

  @override
  String get displayName => 'AI 自动分句';

  @override
  bool get isConfigured => _readSettings().transcriberApiKeyConfigured;

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String mediaUri,
    required String mediaName,
    TranscriberProgress? onProgress,
  }) async {
    final settings = _readSettings();
    final apiKey = (await _readApiKey())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const SubtitleException(
        '请先在设置中填写语音识别 API Key',
        code: 'transcriber_api_key_missing',
      );
    }

    final endpoint = _transcriptionEndpoint(settings.transcriberEndpoint);
    final model = settings.transcriberModel.trim().isEmpty
        ? 'whisper-1'
        : settings.transcriberModel.trim();
    final sourcePath = await _channel.resolvePlayablePath(mediaUri);
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const SubtitleException('无法读取这个媒体文件', code: 'media_file_missing');
    }

    List<TranscriptionAudioChunk> chunks = const [];
    var ownsChunks = false;
    final isVideo = FileUtils.isVideoName(mediaName);
    if (!isVideo && await sourceFile.length() <= _maximumUploadBytes) {
      chunks = [
        TranscriptionAudioChunk(path: sourcePath, startMs: 0, durationMs: 0),
      ];
    } else {
      onProgress?.call(0.03, '正在从媒体中准备音轨');
      chunks = await _channel.exportTranscriptionAudio(mediaUri);
      ownsChunks = true;
    }

    if (chunks.isEmpty) {
      throw const SubtitleException('没有找到可识别的音频内容', code: 'empty_audio');
    }

    final generatedPaths = ownsChunks
        ? chunks.map((chunk) => chunk.path).toList()
        : <String>[];
    final words = <TranscriptSegment>[];
    final phrases = <TranscriptSegment>[];
    var reportedDurationMs = 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25);
    try {
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final file = File(chunk.path);
        final fileLength = await file.length();
        if (fileLength > _maximumUploadBytes) {
          throw const SubtitleException(
            '音频分段仍超过 25 MB，请降低原音轨码率后重试',
            code: 'transcriber_file_too_large',
          );
        }

        onProgress?.call(
          0.08 + 0.82 * i / chunks.length,
          chunks.length == 1
              ? 'AI 正在识别整段音视频'
              : 'AI 正在识别第 ${i + 1}/${chunks.length} 段音频',
        );
        final response = await _requestChunk(
          client: client,
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          language: settings.transcriberLanguage,
          file: file,
          fileName: ownsChunks
              ? file.path.split(Platform.pathSeparator).last
              : mediaName,
        );

        final chunkDuration = response['duration'];
        if (chunkDuration is num && chunkDuration > 0) {
          reportedDurationMs = max(
            reportedDurationMs,
            chunk.startMs + (chunkDuration * 1000).round(),
          );
        }

        final chunkWords = _parseTimedEntries(
          response['words'],
          offsetMs: chunk.startMs,
        );
        final chunkPhrases = _parseTimedEntries(
          response['segments'],
          offsetMs: chunk.startMs,
        );
        words.addAll(chunkWords);
        phrases.addAll(chunkPhrases);
      }

      onProgress?.call(0.94, '正在整理句子边界');
      final segmenter = const SentenceSegmenter();
      final chunkDurationMs = chunks.any((chunk) => chunk.durationMs > 0)
          ? chunks.fold<int>(
              0,
              (end, chunk) => max(end, chunk.startMs + chunk.durationMs),
            )
          : null;
      final durationMs =
          chunkDurationMs ??
          (reportedDurationMs > 0 ? reportedDurationMs : null);
      final sentences = words.isNotEmpty
          ? segmenter.segment(words, mediaDurationMs: durationMs)
          : segmenter.splitPhrases(phrases, mediaDurationMs: durationMs);
      onProgress?.call(1, '已生成 ${sentences.length} 句');
      return sentences;
    } on SocketException {
      throw const SubtitleException(
        '连接识别服务失败，请检查网络和 API 地址',
        code: 'transcriber_network_error',
      );
    } on HttpException {
      throw const SubtitleException(
        '识别服务连接中断，请稍后重试',
        code: 'transcriber_network_error',
      );
    } finally {
      client.close(force: true);
      if (generatedPaths.isNotEmpty) {
        await _channel.deleteTranscriptionAudio(generatedPaths);
      }
    }
  }

  Future<Map<String, dynamic>> _requestChunk({
    required HttpClient client,
    required Uri endpoint,
    required String apiKey,
    required String model,
    required String language,
    required File file,
    required String fileName,
  }) async {
    final boundary =
        'echoloop-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final request = await client
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 30));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey')
      ..set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      )
      ..set(HttpHeaders.acceptHeader, 'application/json');

    final prefix = StringBuffer();
    void addField(String name, String value) {
      prefix.write('--$boundary\r\n');
      prefix.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      prefix.write('$value\r\n');
    }

    addField('model', model);
    addField('response_format', 'verbose_json');
    addField('timestamp_granularities[]', 'word');
    addField('timestamp_granularities[]', 'segment');
    if (language.trim().isNotEmpty) addField('language', language.trim());
    prefix.write('--$boundary\r\n');
    prefix.write(
      'Content-Disposition: form-data; name="file"; filename="${_safeFileName(fileName)}"\r\n'
      'Content-Type: ${_contentType(fileName)}\r\n\r\n',
    );
    final prefixBytes = utf8.encode(prefix.toString());
    final suffixBytes = utf8.encode('\r\n--$boundary--\r\n');
    request.contentLength =
        prefixBytes.length + await file.length() + suffixBytes.length;
    request.add(prefixBytes);
    await request.addStream(file.openRead());
    request.add(suffixBytes);

    final response = await request.close().timeout(const Duration(minutes: 3));
    final body = await utf8.decoder.bind(response).join();
    Object? decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map && decoded['error'] is Map
          ? (decoded['error'] as Map)['message']?.toString()
          : null;
      final message = switch (response.statusCode) {
        401 || 403 => 'API Key 无效或没有语音识别权限，请检查设置',
        413 => '媒体分段超过服务商的文件大小限制',
        429 => '识别请求太频繁或账户额度不足，请稍后重试',
        _ => detail ?? '识别服务返回错误（${response.statusCode}）',
      };
      throw SubtitleException(
        message,
        detail: detail,
        code: 'transcriber_http_${response.statusCode}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SubtitleException(
        '识别服务返回了无法读取的结果',
        code: 'transcriber_invalid_response',
      );
    }
    return decoded;
  }

  List<TranscriptSegment> _parseTimedEntries(
    Object? raw, {
    required int offsetMs,
  }) {
    if (raw is! List) return const [];
    final result = <TranscriptSegment>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final start = _secondsToMs(value['start']);
      final end = _secondsToMs(value['end']);
      final text = value['word']?.toString() ?? value['text']?.toString() ?? '';
      if (start == null || end == null || end <= start || text.trim().isEmpty) {
        continue;
      }
      result.add(
        TranscriptSegment(
          startMs: start + offsetMs,
          endMs: end + offsetMs,
          text: text,
        ),
      );
    }
    return result;
  }

  int? _secondsToMs(Object? value) {
    final seconds = value is num ? value.toDouble() : double.tryParse('$value');
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    return (seconds * 1000).round();
  }

  Uri _transcriptionEndpoint(String value) {
    final base = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const SubtitleException('请先填写识别服务 API 地址');
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.scheme != 'https') {
      throw const SubtitleException('API 地址必须是有效的 HTTPS 地址');
    }
    if (base.endsWith('/audio/transcriptions')) return uri;
    return Uri.parse('$base/audio/transcriptions');
  }

  String _safeFileName(String path) => path
      .split(Platform.pathSeparator)
      .last
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  String _contentType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'mp3' || 'mpga' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'mp4' => 'video/mp4',
      'wav' => 'audio/wav',
      'webm' => 'audio/webm',
      'ogg' || 'opus' => 'audio/ogg',
      'flac' => 'audio/flac',
      'aac' => 'audio/aac',
      _ => 'application/octet-stream',
    };
  }
}
