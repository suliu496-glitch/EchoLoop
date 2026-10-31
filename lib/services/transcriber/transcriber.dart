/// 一句 AI 识别结果。
///
/// 刻意与数据库的 `SubtitleLine` 解耦：识别服务只需要产出「起止时间 + 文本」，
/// 由字幕服务负责落库并补上 media_id / track_id / 来源标识。
/// 这样将来换服务商（或换成本地 whisper.cpp）时，数据层完全不用改。
class TranscriptSegment {
  const TranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.confidence,
  });

  final int startMs;
  final int endMs;
  final String text;

  /// 置信度，0~1；服务商不提供时为 null
  final double? confidence;

  int get durationMs => endMs - startMs;

  @override
  String toString() => '[$startMs - $endMs] $text';
}

/// 识别进度回调。
/// [ratio] 为 0~1，[message] 是给人看的阶段描述（如「正在切分音频」）。
typedef TranscriberProgress = void Function(double ratio, String message);

/// AI 语音识别服务的抽象接口。
///
/// ============================ 为什么这么设计 ============================
///
/// 识别服务只产出带时间范围的文本；分句、落库和播放由应用统一负责：
///
/// ```
/// 输入：音视频文件 URI + 显示名
/// 输出：TranscriptSegment 列表（起止时间毫秒 + 文本）
/// ```
///
/// UI 与业务层只依赖这个抽象类。当前应用注入 Whisper 兼容服务，
/// 后续增加其他云端或本地识别服务时，不需要改变字幕与播放器的数据结构。
///
/// ====================== 增加服务实现时的步骤 =========================
///
/// 1. 在 `lib/services/transcriber/` 下新建文件，例如 `whisper_transcriber.dart`；
/// 2. 实现本接口的 4 个成员：[id] / [displayName] / [isConfigured] / [transcribe]；
/// 3. 在 provider 中注入新实现，必要时增加对应设置项。
///
/// 落库由 `SubtitleService.importFromTranscriber()` 统一处理，
/// 写库时 `source` 字段固定为 `SubtitleSource.ai`，不需要在实现类里操心。
///
/// 参考实现骨架（以「本地文件 + HTTP 接口」为例）：
///
/// ```dart
/// class ExampleTranscriber implements Transcriber {
///   @override
///   String get id => 'example';
///
///   @override
///   String get displayName => '示例识别服务';
///
///   @override
///   bool get isConfigured => _apiKey.isNotEmpty;
///
///   @override
///   Future<List<TranscriptSegment>> transcribe({
///     required String mediaUri,
///     required String mediaName,
///     TranscriberProgress? onProgress,
///   }) async {
///     onProgress?.call(0.1, '正在解析音频');
///     final localPath = await _bridge.toLocalFile(mediaUri); // 需要时先落地一份临时音频
///     onProgress?.call(0.4, '正在上传');
///     final raw = await _client.post(...);
///     onProgress?.call(1.0, '识别完成');
///     return raw.map((e) => TranscriptSegment(
///       startMs: e.startMs, endMs: e.endMs, text: e.text,
///     )).toList();
///   }
/// }
/// ```
///
/// 注意：真正实现时如果服务商只接受本地文件，需要在 `AppDirectories` 下
/// 生成一份**临时副本**并在识别结束后删除，仍然不允许改动用户的原始文件。
abstract class Transcriber {
  /// 唯一标识，用于持久化「用户选择了哪个识别服务」。
  String get id;

  /// 界面上展示的名字。
  String get displayName;

  /// 是否已经配置好（例如 API Key 已填写）。未配置时 UI 上的入口给出引导提示。
  bool get isConfigured;

  /// 核心方法：识别音视频并返回字幕段落列表。
  ///
  /// 实现要求：
  /// - 返回的段落必须按 `startMs` 升序；
  /// - 失败时抛出 [AppException] 的子类，带可读的 message；
  /// - 支持通过 [onProgress] 汇报进度，UI 会显示进度条；
  /// - 实现方自行处理超时与重试，但不得无限阻塞。
  Future<List<TranscriptSegment>> transcribe({
    required String mediaUri,
    required String mediaName,
    TranscriberProgress? onProgress,
  });
}
