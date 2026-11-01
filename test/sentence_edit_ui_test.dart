import 'package:echoloop/data/models/subtitle_models.dart';
import 'package:echoloop/ui/widgets/sentence_edit_dialog.dart';
import 'package:echoloop/ui/widgets/swipe_sentence_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('左滑出现编辑删除，取消确认不删除，确认后才删除', (tester) async {
    var edited = 0;
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 72,
              child: SwipeSentenceTile(
                sentenceNumber: 2,
                onEdit: () => edited++,
                onDelete: () async {
                  deleted++;
                },
                child: const Material(
                  color: Colors.white,
                  child: Center(child: Text('第 2 句')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('第 2 句'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    await tester.drag(find.text('第 2 句'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除第 2 句吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
  });

  testWidgets('编辑断句校验时间后返回新时间和文字', (tester) async {
    const line = SubtitleLine(
      id: 1,
      mediaId: 1,
      trackId: 1,
      lineIndex: 0,
      startMs: 1000,
      endMs: 2000,
      text: '原句',
    );
    SubtitleLine? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<SubtitleLine>(
                  context: context,
                  builder: (_) =>
                      const SentenceEditDialog(line: line, durationMs: 5000),
                );
              },
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), '00:00:00.500');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入有效时间'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '新句');
    await tester.enterText(find.byType(TextField).at(2), '00:00:03.000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result?.text, '新句');
    expect(result?.startMs, 1000);
    expect(result?.endMs, 3000);
  });
}
