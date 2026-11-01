import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

Future<bool> confirmDeleteSentence(BuildContext context, int number) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这句断句？'),
        content: Text('确定删除第 $number 句吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

/// 左滑露出操作，只有确认对话框通过后才调用删除。
class SwipeSentenceTile extends StatefulWidget {
  const SwipeSentenceTile({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    required this.sentenceNumber,
  });
  final Widget child;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;
  final int sentenceNumber;
  @override
  State<SwipeSentenceTile> createState() => _SwipeSentenceTileState();
}

class _SwipeSentenceTileState extends State<SwipeSentenceTile> {
  static const double _actionsWidth = 144;
  double _offset = 0;
  bool _dragging = false;
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await confirmDeleteSentence(
      context,
      widget.sentenceNumber,
    );
    if (!mounted || !confirmed) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
          _offset = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _actionsWidth,
                child: Row(
                  children: [
                    Expanded(
                      child: _action(
                        '编辑',
                        Icons.edit_outlined,
                        Colors.blueGrey,
                        () {
                          setState(() => _offset = 0);
                          widget.onEdit();
                        },
                      ),
                    ),
                    Expanded(
                      child: _action(
                        '删除',
                        Icons.delete_outline,
                        Colors.red.shade700,
                        _deleting ? null : _delete,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (details) => setState(
              () => _offset = (_offset - details.delta.dx).clamp(
                0.0,
                _actionsWidth,
              ),
            ),
            onHorizontalDragEnd: (details) => setState(() {
              _dragging = false;
              final velocity = details.primaryVelocity ?? 0;
              _offset =
                  velocity < -300 ||
                      (velocity <= 300 && _offset > _actionsWidth / 2)
                  ? _actionsWidth
                  : 0;
            }),
            onHorizontalDragCancel: () => setState(() {
              _dragging = false;
              _offset = 0;
            }),
            onTap: _offset > 0 ? () => setState(() => _offset = 0) : null,
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              transform: Matrix4.translationValues(-_offset, 0, 0),
              child: AbsorbPointer(
                absorbing: _offset > 0,
                child: ColoredBox(
                  color: context.palette.background,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) => _SwipeAction(label: label, icon: icon, color: color, onTap: onTap);
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    child: InkWell(
      onTap: onTap,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
