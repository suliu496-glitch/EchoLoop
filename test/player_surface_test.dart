import 'package:echoloop/ui/widgets/fullscreen_playback_surface.dart';
import 'package:echoloop/ui/widgets/media_playback_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [240.0, 320.0, 600.0]) {
    testWidgets('添加断句在 $width 像素宽的控制区可见且可点击', (tester) async {
      var added = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: MediaPlaybackControls(
                  modeLabel: '单曲循环',
                  modeIcon: Icons.repeat_one,
                  onChangeMode: () {},
                  onAddSentence: () => added++,
                  onPrevious: () {},
                  onNext: () {},
                  compact: width < 320,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('add-sentence')), findsOneWidget);
      if (width >= 320) {
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('add-sentence'))).dx,
          greaterThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('media-playback-mode')))
                .dx,
          ),
        );
      }
      await tester.tap(find.byKey(const ValueKey('add-sentence')));
      await tester.pump();
      expect(added, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('全屏单击只切换控制栏，双击播放暂停，退出按钮才退出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var toggles = 0;
    var exits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullscreenPlaybackSurface(
            video: const ColoredBox(color: Colors.black),
            controls: const Text('播放控制'),
            positionMs: 1000,
            durationMs: 10000,
            onSeek: (_) {},
            onTogglePlay: () => toggles++,
            onExit: () => exits++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('fullscreen-controls')), findsOneWidget);
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('fullscreen-controls')), findsNothing);
    expect(exits, 0);
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('fullscreen-controls')), findsOneWidget);
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(toggles, 1);
    expect(exits, 0);
    await tester.tap(find.byKey(const ValueKey('exit-fullscreen')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(exits, 1);
  });

  testWidgets('全屏控制栏自动隐藏后可单击重新显示并拖动进度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var seek = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullscreenPlaybackSurface(
            video: const ColoredBox(color: Colors.black),
            controls: const SizedBox(height: 40),
            positionMs: 1000,
            durationMs: 10000,
            onSeek: (ms) => seek = ms,
            onTogglePlay: () {},
            onExit: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('fullscreen-controls')), findsNothing);
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('fullscreen-controls')), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 350));
    expect(seek, greaterThan(1000));
  });
}
