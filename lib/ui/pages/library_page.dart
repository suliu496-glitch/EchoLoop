import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/core_providers.dart';
import '../../providers/library_provider.dart';
import '../../services/native_channel.dart';
import '../widgets/device_media_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/media_card.dart';
import 'player_page.dart';
import 'settings_page.dart';

/// 媒体库首页（需求 §6：卡片式媒体库）。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = ref.watch(mediaLibraryProvider);

    // 统一的错误提示出口
    ref.listen(mediaLibraryProvider, (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        ref.read(mediaLibraryProvider.notifier).consumeError();
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'device',
            onPressed: _openDeviceMedia,
            backgroundColor: palette.glassStrong,
            foregroundColor: palette.textPrimary,
            icon: const Icon(Icons.smartphone_rounded, size: 20),
            label: const Text('设备媒体'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'import',
            onPressed: _importFromPicker,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入文件'),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, state),
            if (_searching) _buildSearchField(context),
            Expanded(child: _buildBody(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MediaLibraryState state) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        12,
        AppDimens.pagePadding,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppConstants.appSlogan} · 共 ${state.items.length} 个',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchController.clear();
                ref.read(mediaLibraryProvider.notifier).setKeyword('');
              }
            },
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        0,
        AppDimens.pagePadding,
        8,
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: glassInputDecoration(context, hintText: '搜索文件名'),
        onChanged: (value) =>
            ref.read(mediaLibraryProvider.notifier).setKeyword(value),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MediaLibraryState state) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.isEmpty) {
      return _EmptyLibrary(onImport: _importFromPicker, onScan: _openDeviceMedia);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(mediaLibraryProvider.notifier).refresh(),
      // 用最大单元格宽度而不是固定列数：手机自动一列，平板自动两列甚至三列，
      // 窗口一变大就多排一列，不用写死断点。
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          4,
          AppDimens.pagePadding,
          140,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460,
          mainAxisExtent: 116,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final item = state.items[index];
          return MediaCard(
            item: item,
            onOpen: () => _openPlayer(item.id!),
            onRename: () => _renameDialog(item.id!, item.name),
            onDelete: () => _deleteDialog(item.id!, item.name),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // 打开播放页
  // ------------------------------------------------------------------

  void _openPlayer(int mediaId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerPage(mediaId: mediaId)),
    );
  }

  // ------------------------------------------------------------------
  // 导入
  // ------------------------------------------------------------------

  Future<void> _importFromPicker() async {
    final result = await ref.read(mediaLibraryProvider.notifier).importFromPicker();
    if (!mounted) return;
    if (result == null) return;
    if (result.total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有选择文件')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.summary)),
    );
    if (result.unsupported.isNotEmpty) {
      final supported = ref
          .read(mediaImportServiceProvider)
          .supportedExtensions
          .map((e) => '.$e')
          .join(' ');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('支持的格式：$supported'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _openDeviceMedia() async {
    // 先抓住 messenger：后面要跨 await 用，直接 quote context 会被 lint 拦下
    final messenger = ScaffoldMessenger.of(context);

    // 扫描设备媒体需要按 API 版本申请对应权限，具体申请哪些由原生侧决定
    final granted = await ref.read(nativeChannelProvider).requestPermissions(
      const [NativePermissionGroup.mediaVideo, NativePermissionGroup.mediaAudio],
    );
    final videoOk = granted[NativePermissionGroup.mediaVideo.wire] ?? false;
    final audioOk = granted[NativePermissionGroup.mediaAudio.wire] ?? false;

    if (!mounted) return;

    if (!videoOk && !audioOk) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('没有读取媒体的权限，可以改用「导入文件」手动挑选'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await showDeviceMediaSheet(context);
    if (!mounted || result == null) return;
    messenger.showSnackBar(SnackBar(content: Text(result.summary)));
  }

  // ------------------------------------------------------------------
  // 重命名 / 删除
  // ------------------------------------------------------------------

  Future<void> _renameDialog(int mediaId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: glassInputDecoration(dialogContext, hintText: '新的文件名'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    await ref.read(mediaLibraryProvider.notifier).rename(mediaId, result);
  }

  Future<void> _deleteDialog(int mediaId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从媒体库删除'),
        content: Text(
          '只会删掉「$name」在媒体库里的记录与字幕，'
          '手机上的原文件不会被删除。',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除记录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(mediaLibraryProvider.notifier).remove(mediaId);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport, required this.onScan});

  final VoidCallback onImport;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_rounded, size: 56, color: palette.accent),
            const SizedBox(height: 16),
            Text(
              '先导入一段美剧片段或听力材料',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '导入后可以框选一小段反复循环，配合字幕逐句跟读，'
              '还能留出停顿时间开口练习。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '支持的格式',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '视频 ${AppConstants.videoExtensions.map((e) => '.$e').join(' ')}\n'
                    '音频 ${AppConstants.audioExtensions.map((e) => '.$e').join(' ')}\n'
                    '字幕 ${AppConstants.subtitleExtensions.map((e) => '.$e').join(' ')}',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.7,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('导入文件'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.smartphone_rounded, size: 18),
                  label: const Text('扫描手机媒体'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}