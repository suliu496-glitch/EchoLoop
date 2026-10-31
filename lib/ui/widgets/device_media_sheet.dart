import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../providers/library_provider.dart';
import '../../services/media_import_service.dart';
import '../../services/native_channel.dart';
import '../adaptive/screen_adaptation.dart';
import 'glass.dart';

/// 从设备媒体库（MediaStore）勾选导入。
///
/// 走这条路的好处是**零拷贝**：MediaStore 里的文件本来就在手机上，
/// 我们只拿它的 `content://` URI，不复制、不移动（需求 §4.3）。
Future<MediaImportResult?> showDeviceMediaSheet(BuildContext context) {
  return showModalBottomSheet<MediaImportResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ScreenAdaptation.sheetConstraints(context),
    builder: (_) => const _DeviceMediaSheet(),
  );
}

class _DeviceMediaSheet extends ConsumerStatefulWidget {
  const _DeviceMediaSheet();

  @override
  ConsumerState<_DeviceMediaSheet> createState() => _DeviceMediaSheetState();
}

class _DeviceMediaSheetState extends ConsumerState<_DeviceMediaSheet> {
  final Set<String> _selected = {};
  String _scope = 'all';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mediaLibraryProvider.notifier).scanDeviceMedia();
    });
  }

  @override
  void dispose() {
    ref.read(mediaLibraryProvider.notifier).closeDevicePanel();
    super.dispose();
  }

  Future<void> _import() async {
    final entries = ref.read(mediaLibraryProvider).deviceEntries ?? const [];
    final chosen = entries.where((e) => _selected.contains(e.uri)).toList();
    if (chosen.isEmpty) return;

    setState(() => _importing = true);
    final result =
        await ref.read(mediaLibraryProvider.notifier).importDeviceEntries(chosen);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = ref.watch(mediaLibraryProvider);
    final entries = state.deviceEntries ?? const <NativeMediaEntry>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => GlassPanel(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.smartphone_rounded, size: 18, color: palette.accent),
                const SizedBox(width: 8),
                const Text(
                  '设备上的媒体',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '已选 ${_selected.length}',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final option in const [
                  ('all', '全部'),
                  ('video', '视频'),
                  ('audio', '音频'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GlassChip(
                      label: option.$2,
                      selected: _scope == option.$1,
                      onTap: () {
                        setState(() => _scope = option.$1);
                        ref
                            .read(mediaLibraryProvider.notifier)
                            .scanDeviceMedia(scope: option.$1);
                      },
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: () => ref
                      .read(mediaLibraryProvider.notifier)
                      .scanDeviceMedia(scope: _scope),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: '重新扫描',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: state.scanningDevice
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '没有扫描到媒体文件。\n'
                              '可能是没有授予读取媒体的权限，\n'
                              '或者手机上确实还没有音频视频。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final checked = _selected.contains(entry.uri);
                            return GlassPanel(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              radius: AppDimens.radiusSm,
                              strong: checked,
                              color: checked
                                  ? palette.accent.withValues(alpha: 0.14)
                                  : null,
                              onTap: () => setState(() {
                                if (checked) {
                                  _selected.remove(entry.uri);
                                } else {
                                  _selected.add(entry.uri);
                                }
                              }),
                              child: Row(
                                children: [
                                  Icon(
                                    checked
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 20,
                                    color: checked
                                        ? palette.accent
                                        : palette.textTertiary,
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(
                                    entry.isVideo
                                        ? Icons.movie_outlined
                                        : Icons.music_note_outlined,
                                    size: 18,
                                    color: palette.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13.5),
                                        ),
                                        Text(
                                          '${DurationUtils.formatShort(entry.durationMs)}'
                                          ' · ${FileUtils.humanSize(entry.sizeBytes)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: palette.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty || _importing ? null : _import,
                child: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_selected.isEmpty ? '选择要导入的文件' : '导入选中的 ${_selected.length} 个'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
