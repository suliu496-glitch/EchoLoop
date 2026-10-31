/// 播放源解析接口。
///
/// 数据库里存的是 `content://` 这类 URI，但底层的 libmpv 只认真实文件路径。
/// 这层抽象把「怎么把 URI 变成能播的路径」隔离出去：
/// - 生产实现走 Android 原生桥（真实路径 / 文件描述符路径）；
/// - 写单元测试时可以塞一个假的实现，不依赖任何平台通道。
abstract class PlayableSourceResolver {
  /// 把媒体 URI 解析成播放内核可用的路径。
  Future<String> resolve(String uri);

  /// 释放该 URI 占用的资源（例如已打开的文件描述符）。
  Future<void> release(String uri);

  /// 释放全部资源。
  Future<void> releaseAll();
}
