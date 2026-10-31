import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/media_item.dart';
import 'glass.dart';

/// 媒体库卡片：封面缩略图 + 文件名 + 时长 + 最近播放进度条（需求 §6）。
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.onRename,
    this.onDelete,
  });

  final MediaItem item;
  final VoidCallback onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final extension = FileUtils.extensionOf(item.name).toUpperCase();

    return GlassPanel(
      padding: const EdgeInsets.all(10),
      radius: AppDimens.radiusMd,
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(item: item),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    _MenuButton(
                      onRename: onRename,
                      onDelete: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (extension.isNotEmpty)
                      GlassChip(
                        label: extension,
                        selected: false,
                        color: item.isVideo ? palette.accent : palette.success,
                      ),
                    Text(
                      DurationUtils.formatShort(item.durationMs),
                      style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                    ),
                    Text(
                      FileUtils.humanSize(item.sizeBytes),
                      style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
                    ),
                    if (item.hasLoopRegion)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.repeat_rounded, size: 12, color: palette.accent),
                          const SizedBox(width: 2),
                          Text(
                            '已存片段',
                            style: TextStyle(fontSize: 11, color: palette.accent),
                          ),
                        ],
                      ),
                  ],
                ),
                if (item.positionMs > 0 && item.durationMs > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: item.progressRatio,
                      minHeight: 4,
                      backgroundColor: palette.trackInactive,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '上次播到 ${DurationUtils.formatShort(item.positionMs)}',
                    style: TextStyle(fontSize: 10.5, color: palette.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final path = item.thumbnailPath;

    Widget fallback = Container(
      color: palette.accent.withValues(alpha: 0.12),
      child: Icon(
        item.isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
        color: palette.accent,
        size: 26,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: SizedBox(
        width: 76,
        height: 52,
        child: path != null && File(path).existsSync()
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({this.onRename, this.onDelete});

  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
      onSelected: (value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'delete', child: Text('从媒体库删除')),
      ],
    );
  }
}

/// 封面装饰：给「重命名」输入框用的统一样式。
InputDecoration glassInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
}) {
  final palette = context.palette;
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    isDense: true,
    hintStyle: TextStyle(color: palette.textTertiary, fontSize: 13),
    labelStyle: TextStyle(color: palette.textSecondary, fontSize: 13),
    filled: true,
    fillColor: palette.glass,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      borderSide: BorderSide(color: palette.glassBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      borderSide: BorderSide(color: palette.glassBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      borderSide: BorderSide(color: palette.accent, width: 1.4),
    ),
  );
}
