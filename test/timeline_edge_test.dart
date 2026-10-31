import 'package:echoloop/core/theme/app_theme.dart';
import 'package:echoloop/domain/playback/playback_state.dart';
import 'package:echoloop/ui/widgets/timeline_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('拖到媒体两端时不被字幕吸附移走', (tester) async {
    final changes = <LoopRegion>[];
    Future<void> show(LoopRegion region) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: TimelineBar(
                  positionMs: 0,
                  durationMs: 10000,
                  region: region,
                  snapEnabled: true,
                  snap: (ms) => ms < 5000 ? 400 : 9600,
                  onSeek: (_) {},
                  regionChanged: (a, b) =>
                      changes.add(LoopRegion(startMs: a, endMs: b)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await show(const LoopRegion(startMs: 2000, endMs: 8000));
    var origin = tester.getTopLeft(find.byType(TimelineBar));
    await tester.dragFrom(origin + const Offset(80, 17), const Offset(-100, 0));
    await tester.pump();
    expect(changes.last, const LoopRegion(startMs: 0, endMs: 8000));

    await show(const LoopRegion(startMs: 0, endMs: 8000));
    origin = tester.getTopLeft(find.byType(TimelineBar));
    await tester.dragFrom(origin + const Offset(320, 17), const Offset(100, 0));
    await tester.pump();
    expect(changes.last, const LoopRegion(startMs: 0, endMs: 10000));
  });

  testWidgets('整段选区两端的把手可以向内拖动', (tester) async {
    final changes = <LoopRegion>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: TimelineBar(
                positionMs: 0,
                durationMs: 10000,
                region: const LoopRegion(startMs: 0, endMs: 10000),
                snapEnabled: false,
                snap: (ms) => ms,
                onSeek: (_) {},
                regionChanged: (a, b) =>
                    changes.add(LoopRegion(startMs: a, endMs: b)),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(TimelineBar));
    await tester.dragFrom(origin + const Offset(2, 17), const Offset(120, 0));
    await tester.pump();
    expect(changes.last.endMs, 10000);
    expect(changes.last.startMs, greaterThan(0));

    await tester.dragFrom(
      origin + const Offset(398, 17),
      const Offset(-120, 0),
    );
    await tester.pump();
    expect(changes.last.startMs, 0);
    expect(changes.last.endMs, lessThan(10000));
  });
}
