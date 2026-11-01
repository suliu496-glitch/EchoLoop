import '../domain/playback/playable_source_resolver.dart';
import 'native_channel.dart';

/// [PlayableSourceResolver] 的生产实现：交给 Android 原生层解析。
///
/// content URI 交给 media_kit 直接处理：它使用 mpv 的 fd:// 协议，
/// 避免在某些 Android 设备上无法重新打开 /proc/self/fd 路径。
/// 非 content URI 仍通过原生桥解析并缓存。
class NativePlayableSourceResolver implements PlayableSourceResolver {
  NativePlayableSourceResolver(this._channel);

  final NativeChannel _channel;
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<String> resolve(String uri) async {
    if (_isContentUri(uri)) return uri;
    final cached = _cache[uri];
    if (cached != null && cached.isNotEmpty) return cached;
    final path = await _channel.resolvePlayablePath(uri);
    _cache[uri] = path;
    return path;
  }

  @override
  Future<void> release(String uri) async {
    if (_isContentUri(uri)) return;
    _cache.remove(uri);
    await _channel.releasePlayablePath(uri);
  }

  @override
  Future<void> releaseAll() async {
    _cache.clear();
    await _channel.releaseAllPlayablePaths();
  }

  bool _isContentUri(String uri) => Uri.tryParse(uri)?.scheme == 'content';
}
