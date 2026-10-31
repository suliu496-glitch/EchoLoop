import '../../core/errors/app_exception.dart';
import 'transcriber.dart';

/// 占位实现：代表「还没有接入任何 AI 识别服务」。
///
/// 需求 §3.2-6 要求 UI 上保留「AI 识别字幕」入口，点击提示
/// 「功能开发中，请先配置识别服务」，并且**不发任何实际请求**。
/// 这个类就是那个「永远不可用」的实现，保证入口链路是通的、
/// 但不会误触发网络请求。
class UnavailableTranscriber implements Transcriber {
  const UnavailableTranscriber();

  @override
  String get id => 'unavailable';

  @override
  String get displayName => '未配置识别服务';

  @override
  bool get isConfigured => false;

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String mediaUri,
    required String mediaName,
    TranscriberProgress? onProgress,
  }) async {
    throw const SubtitleException(
      '功能开发中，请先配置识别服务',
      detail: '在 services/transcriber/ 下新增一个 Transcriber 实现并注册即可启用',
      code: 'transcriber_unavailable',
    );
  }
}
