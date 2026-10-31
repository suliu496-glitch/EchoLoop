import '../domain/playback/playable_source_resolver.dart';
import 'native_channel.dart';

/// [PlayableSourceResolver] 的生产实现：交给 Android 原生层解析。
///
/// 加了进程内缓存的原因：拖动进度条、倍速切换都会频繁走这条路径，
/// 每次都过通道会白白付出通道开销；而原生侧对同一个 URI 也只维护一份文件描述符，
/// 缓存与原生状态是一一对应的，release 时会同步清掉。
class NativePlayableSourceResolver implements PlayableSourceResolver {
  NativePlayableSourceResolver(this._channel);

  final NativeChannel _channel;
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<String> resolve(String uri) async {
    final cached = _cache[uri];
    if (cached != null && cached.isNotEmpty) return cached;
    final path = await _channel.resolvePlayablePath(uri);
    _cache[uri] = path;
    return path;
  }

  @override
  Future<void> release(String uri) async {
    _cache.remove(uri);
    await _channel.releasePlayablePath(uri);
  }

  @override
  Future<void> releaseAll() async {
    _cache.clear();
    await _channel.releaseAllPlayablePaths();
  }
}
