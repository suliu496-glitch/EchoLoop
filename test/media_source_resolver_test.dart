import 'package:echoloop/services/media_source_resolver.dart';
import 'package:echoloop/services/native_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('echoloop/test_media_source');
  late NativeChannel native;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'resolvePlayablePath') {
            return {'path': '/storage/example.mp4'};
          }
          return true;
        });
    native = NativeChannel(channel: channel);
  });

  tearDown(() {
    native.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android content URI 直接传给播放器，释放时不关闭其他调用者的句柄', () async {
    final resolver = NativePlayableSourceResolver(native);
    const uri =
        'content://com.android.providers.media.documents/document/video%3A42';
    expect(await resolver.resolve(uri), uri);
    await resolver.release(uri);
    expect(calls, isEmpty);
  });

  test('普通路径仍使用原生解析、缓存与释放', () async {
    final resolver = NativePlayableSourceResolver(native);
    const uri = 'file:///storage/example.mp4';
    expect(await resolver.resolve(uri), '/storage/example.mp4');
    expect(await resolver.resolve(uri), '/storage/example.mp4');
    await resolver.release(uri);
    expect(calls.map((call) => call.method), [
      'resolvePlayablePath',
      'releasePlayablePath',
    ]);
    expect(await resolver.resolve(uri), '/storage/example.mp4');
    expect(calls.last.method, 'resolvePlayablePath');
  });
}
