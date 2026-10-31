import 'transcriber.dart';
import 'unavailable_transcriber.dart';

/// 识别服务注册表（需求 §3.2-6 / §5「未来接入只需新增实现类并替换 provider」）。
///
/// 全局只有一个实例，UI 通过它拿到「当前生效的识别器」，
/// 从而做到「点击 AI 识别入口时永远不关心具体是谁在实现」。
class TranscriberRegistry {
  TranscriberRegistry._();

  static final TranscriberRegistry instance = TranscriberRegistry._();

  /// 兜底实现：未注册任何服务时使用
  static const Transcriber fallback = UnavailableTranscriber();

  final Map<String, Transcriber> _transcribers = <String, Transcriber>{};

  String? _activeId;

  /// 注册一个识别器。同一个 id 重复注册会覆盖（方便热更新配置）。
  void register(Transcriber transcriber) {
    _transcribers[transcriber.id] = transcriber;
    if (_activeId == null && transcriber.isConfigured) {
      _activeId = transcriber.id;
    }
  }

  void unregister(String id) {
    _transcribers.remove(id);
    if (_activeId == id) _activeId = null;
  }

  List<Transcriber> get all => _transcribers.values.toList(growable: false);

  /// 手动指定当前生效的识别器。
  void setActive(String? id) {
    _activeId = id;
  }

  String? get activeId => _activeId;

  /// 当前生效的识别器；没有可用的就返回 [fallback]。
  ///
  /// 注意：这里**永远不返回 null**，这样 UI 不需要到处判空，
  /// 「没配置」这件事由 [Transcriber.isConfigured] 表达。
  Transcriber get active {
    final id = _activeId;
    if (id != null) {
      final transcriber = _transcribers[id];
      if (transcriber != null) return transcriber;
    }
    return _transcribers.values.firstWhere(
      (transcriber) => transcriber.isConfigured,
      orElse: () => fallback,
    );
  }

  /// 是否有可用的识别服务（用于控制入口按钮的样式与提示）。
  bool get hasConfiguredService =>
      _transcribers.values.any((transcriber) => transcriber.isConfigured);

  /// 启动时调用，把所有已知实现注册进来。
  ///
  /// 未来接入真实服务时，只需要在这里加一行：
  /// ```dart
  /// register(WhisperTranscriber(apiKey: settings.whisperKey));
  /// ```
  void bootstrap() {
    // 目前不接任何真实服务，注册表保持为空，active 会落到 fallback。
  }
}
