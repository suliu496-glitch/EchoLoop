/// 播放源解析接口。
///
/// 数据库保存的 `content://` URI 由 media_kit 转为播放器可用的文件描述符。
/// 这层抽象把「如何取得播放器可用的来源」隔离出去：
/// - 生产实现将 content URI 直接交给 media_kit，其他来源走原生桥；
/// - 写单元测试时可以塞一个假的实现，不依赖任何平台通道。
abstract class PlayableSourceResolver {
  /// 把媒体 URI 解析成播放内核可用的路径。
  Future<String> resolve(String uri);

  /// 释放该 URI 占用的资源（例如已打开的文件描述符）。
  Future<void> release(String uri);

  /// 释放全部资源。
  Future<void> releaseAll();
}
