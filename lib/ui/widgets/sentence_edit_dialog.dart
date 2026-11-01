import 'package:flutter/material.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/subtitle_models.dart';
import '../../domain/subtitles/subtitle_text_utils.dart';

class SentenceEditDialog extends StatefulWidget {
  const SentenceEditDialog({
    super.key,
    required this.line,
    required this.durationMs,
  });
  final SubtitleLine line;
  final int durationMs;
  @override
  State<SentenceEditDialog> createState() => _SentenceEditDialogState();
}

class _SentenceEditDialogState extends State<SentenceEditDialog> {
  late final _text = TextEditingController(text: widget.line.text);
  late final _start = TextEditingController(
    text: DurationUtils.formatMilliseconds(widget.line.startMs),
  );
  late final _end = TextEditingController(
    text: DurationUtils.formatMilliseconds(widget.line.endMs),
  );
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _save() {
    final start = SubtitleTextUtils.parseTimeCode(_start.text);
    final end = SubtitleTextUtils.parseTimeCode(_end.text);
    if (start == null ||
        end == null ||
        start < 0 ||
        end <= start ||
        (widget.durationMs > 0 && end > widget.durationMs)) {
      setState(() => _error = '请输入有效时间，结束时间需晚于开始时间且不超过媒体时长');
      return;
    }
    Navigator.of(
      context,
    ).pop(widget.line.copyWith(startMs: start, endMs: end, text: _text.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑断句'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: '句子文字（可留空）'),
          ),
          TextField(
            controller: _start,
            decoration: const InputDecoration(
              labelText: '开始时间',
              hintText: '00:00:01.250',
            ),
          ),
          TextField(
            controller: _end,
            decoration: const InputDecoration(
              labelText: '结束时间',
              hintText: '00:00:03.000',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
