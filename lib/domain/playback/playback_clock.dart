import '../../core/constants/app_constants.dart';

/// 高精度播放时钟。
///
/// ## 为什么需要它
///
/// 循环边界靠内核（libmpv）回报的播放位置来判断是不可靠的：
/// 位置回调的间隔由解码器决定，音频文件上往往几十到几百毫秒才跳一次。
/// 拿这种「颗粒很粗」的位置去判断「有没有播到 B 点」，结果就是
/// 有的句子被切掉尾巴，有的句子多播一截，听感上就是「这个循环不精确」。
///
/// 这个类的做法是**自己走一个时钟**：
///
/// - 记下某个时刻的音频位置（锚点）与当时的真实时间；
/// - 之后用「真实经过时长 × 倍速」推算当前位置，粒度由调用方决定（现在是 20ms 轮询）；
/// - 内核回调到达时只做**校正**，而不是拿它当唯一真相。
///
/// 这样位置估算既平滑又精确，而且不依赖内核回调频率。
///
/// ## 两个容易忽略的点
///
/// 1. **倍速要参与换算**。0.5 倍速下真实时间过 2 秒，音频才走了 1 秒。
/// 2. **缓冲时必须冻结**。卡顿时音频没走，时钟却在跑，不冻结就会误判已经越过 B 点。
class PlaybackClock {
  PlaybackClock({int Function()? nowMilliseconds})
      : _now = nowMilliseconds ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// 时间源。抽成可注入是为了单元测试能手动推进时间。
  final int Function() _now;

  int _anchorMediaMs = 0;
  int _anchorWallMs = 0;
  double _speed = 1.0;
  bool _running = false;

  /// 是否正在走时。
  bool get isRunning => _running;

  /// 当前音频位置（毫秒）。
  int get positionMs {
    if (!_running) return _anchorMediaMs;
    final elapsedWallMs = _now() - _anchorWallMs;
    if (elapsedWallMs <= 0) return _anchorMediaMs;
    return _anchorMediaMs + (elapsedWallMs * _speed).round();
  }

  /// 从某个音频位置开始走时（播放、seek 之后、循环回到 A 点之后调用）。
  void startAt(int mediaMs, {double speed = 1.0}) {
    _anchorMediaMs = mediaMs < 0 ? 0 : mediaMs;
    _anchorWallMs = _now();
    _speed = _normalizeSpeed(speed);
    _running = true;
  }

  /// 暂停走时，位置冻结在当前估算值。
  void stop() {
    if (!_running) return;
    final frozen = positionMs;
    _running = false;
    _anchorMediaMs = frozen;
  }

  /// 停止并落到指定位置（seek 之后调用）。
  void seekTo(int mediaMs) {
    _anchorMediaMs = mediaMs < 0 ? 0 : mediaMs;
    _anchorWallMs = _now();
    if (!_running) return;
  }

  /// 变速：先把当前位置落成新锚点，再换倍速，否则历史时间会被新倍速错误换算。
  void setSpeed(double speed) {
    final current = positionMs;
    _anchorMediaMs = current;
    _anchorWallMs = _now();
    _speed = _normalizeSpeed(speed);
  }

  /// 用内核回报的位置校正估算。
  ///
  /// 只有偏差超过阈值才重新对齐，避免内核的抖动把平滑的估算带得一顿一顿。
  /// 返回是否发生了重新对齐。
  bool correctFromKernel(int mediaMs) {
    if (mediaMs < 0) return false;

    if (!_running) {
      // 暂停状态下内核位置才是准的（例如手动拖动后）
      _anchorMediaMs = mediaMs;
      return false;
    }

    final drift = (positionMs - mediaMs).abs();
    if (drift <= AppConstants.clockMaxDriftMs) return false;

    _anchorMediaMs = mediaMs;
    _anchorWallMs = _now();
    return true;
  }

  static double _normalizeSpeed(double speed) => speed <= 0 ? 1.0 : speed;
}
