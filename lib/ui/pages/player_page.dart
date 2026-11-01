import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/media_item.dart';
import '../../data/models/subtitle_models.dart';
import '../../domain/playback/playback_state.dart';
import '../../domain/subtitles/subtitle_cue.dart';
import '../../domain/subtitles/subtitle_snapper.dart';
import '../../providers/core_providers.dart';
import '../../providers/library_provider.dart';
import '../../providers/loop_preset_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/subtitle_provider.dart';
import '../adaptive/screen_adaptation.dart';
import '../widgets/compact_landscape_panel.dart';
import '../widgets/fullscreen_playback_surface.dart';
import '../widgets/glass.dart';
import '../widgets/loop_panel.dart';
import '../widgets/media_playback_controls.dart';
import '../widgets/player_controls.dart';
import '../widgets/subtitle_list_view.dart';
import '../widgets/timeline_bar.dart';
import 'settings_page.dart';
import 'subtitle_editor_page.dart';

/// 播放页。
///
/// ## 布局策略（本次改版的重点）
///
/// 上一版把「设 A / 设 B / 框选 / 清除 / 倍速 / 停顿 / 更多」全铺在主界面上，
/// 太挤也难记。这次的原则是：**主界面只留练习时真正高频的操作，其余收进「更多」面板。**
///
/// 主界面现在只有两行：
/// ```
///   [−5s]  [▶/⏸]  [+5s]             播放控制
///   [🔁 循环]  [1.0x 倍速]  [更多]    练习控制
/// ```
/// 框选改由时间轴上方那条选区轨直接拖动完成，不再需要模式按钮。
///
/// ## 屏幕适配
///
/// 平板（短边 >= 600dp）与横屏手机走两栏：左边画面与控制，右边字幕列表，
/// 字幕能和画面同时看全，不用来回滑。手机竖屏保持单栏。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  MediaItem? _media;
  String? _error;
  bool _loading = true;
  bool _fullscreen = false;
  bool _savingSentence = false;
  bool _precisionExpanded = true;
  bool _changingPrecision = false;

  /// 上一次应用过的方向策略，避免每帧都去调 SystemChrome
  List<DeviceOrientation>? _appliedOrientations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出播放页：落盘进度、撤掉前台服务、释放文件描述符
    ref.read(playbackProvider.notifier).leavePlayer();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(playbackProvider.notifier).flushProgress();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final item = await ref.read(mediaDaoProvider).findById(widget.mediaId);
      if (item == null) {
        setState(() {
          _loading = false;
          _error = '这个媒体已经不在媒体库里了';
        });
        return;
      }

      await ref.read(loopPresetProvider.notifier).loadFor(widget.mediaId);
      await ref.read(subtitleProvider.notifier).loadFor(widget.mediaId);

      if (!mounted) return;
      setState(() {
        _media = item;
        _loading = false;
      });

      final queue = ref.read(mediaLibraryProvider).items;
      await ref.read(playbackProvider.notifier).openMedia(item, queue: queue);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = humanizeError(error);
      });
    }
  }

  // ------------------------------------------------------------------
  // 方向与全屏
  // ------------------------------------------------------------------

  void _applyOrientations(
    List<DeviceOrientation> orientations, {
    bool force = false,
  }) {
    if (!force && _sameOrientations(_appliedOrientations, orientations)) return;
    _appliedOrientations = List<DeviceOrientation>.from(orientations);
    SystemChrome.setPreferredOrientations(orientations);
  }

  bool _sameOrientations(
    List<DeviceOrientation>? a,
    List<DeviceOrientation> b,
  ) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _toggleFullscreen() {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      _applyOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ], force: true);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _applyOrientations(
        ScreenAdaptation.preferredOrientations(context),
        force: true,
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ------------------------------------------------------------------
  // 构建
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('播放')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    // 全屏期间保留横屏策略，退出全屏后再恢复屏幕自适应方向。
    if (!_fullscreen) {
      _applyOrientations(ScreenAdaptation.preferredOrientations(context));
    }

    ref.listen<PlaybackSnapshot>(playbackProvider, (previous, next) {
      if (next.mediaId != null && next.mediaId != _media?.id) {
        _loadDisplayedMedia(next.mediaId!);
      }
    });

    final playback = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final subtitleState = ref.watch(subtitleProvider);
    final currentCue = SubtitleSnapper.cueAt(
      playback.positionMs,
      subtitleState.cues,
    );

    if (_fullscreen) return _buildFullscreen(playback, currentCue);

    // 三种布局各管一段屏幕形态，判断顺序不能调换：
    // 横屏手机在「宽高比」意义上也属于宽屏，但纵向只有三百多 dp，
    // 和平板横屏完全不是一回事，必须先拦下来。
    final Widget body;
    if (!_precisionExpanded) {
      body = _buildStage(
        playback,
        settings,
        currentCue,
        maxVideoHeight: MediaQuery.sizeOf(context).height * .68,
      );
    } else if (ScreenAdaptation.isPhoneLandscape(context)) {
      body = _buildPhoneLandscapeLayout(playback, settings, currentCue);
    } else if (ScreenAdaptation.isWide(context)) {
      body = _buildWideLayout(playback, settings, currentCue);
    } else {
      body = _buildCompactLayout(playback, settings, currentCue);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(playback),
      body: SafeArea(top: false, child: body),
    );
  }

  Future<void> _loadDisplayedMedia(int id) async {
    final item = await ref.read(mediaDaoProvider).findById(id);
    if (!mounted || item == null || ref.read(playbackProvider).mediaId != id) {
      return;
    }
    setState(() => _media = item);
    await ref.read(loopPresetProvider.notifier).loadFor(id);
    if (!mounted || ref.read(playbackProvider).mediaId != id) return;
    await ref.read(subtitleProvider.notifier).loadFor(id);
  }

  /// 手机竖屏：单栏，字幕列表占剩余空间。
  Widget _buildCompactLayout(
    PlaybackSnapshot playback,
    AppSettings settings,
    SubtitleCue? currentCue,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 保留足够空间给句子列表，短屏时压缩画面而不是把操作按钮挤出屏幕。
        final videoCap = math.max(72.0, constraints.maxHeight - 410);
        return Column(
          children: [
            _buildStage(
              playback,
              settings,
              currentCue,
              maxVideoHeight: videoCap,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
              ),
              child: Divider(color: context.palette.divider, height: 1),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pagePadding,
                  8,
                  AppDimens.pagePadding,
                  0,
                ),
                child: _buildSubtitleArea(settings),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 平板 / 横屏：左右两栏，画面与字幕同时可见。
  Widget _buildWideLayout(
    PlaybackSnapshot playback,
    AppSettings settings,
    SubtitleCue? currentCue,
  ) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ConstrainedContent(
            maxWidth: 780,
            child: Padding(
              padding: const EdgeInsets.only(left: AppDimens.pagePadding),
              child: _buildStage(playback, settings, currentCue),
            ),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          color: palette.divider,
        ),
        Expanded(
          flex: 2,
          child: ConstrainedContent(
            maxWidth: 520,
            child: Padding(
              padding: const EdgeInsets.only(right: AppDimens.pagePadding),
              child: _buildSubtitleArea(settings),
            ),
          ),
        ),
      ],
    );
  }

  /// 「舞台」区：视频 + 当前字幕 + 时间轴 + 两行控制。
  /// 竖屏手机与平板都用它，区别只在外面给的宽度。
  Widget _buildStage(
    PlaybackSnapshot playback,
    AppSettings settings,
    SubtitleCue? currentCue, {
    double? maxVideoHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final isVideo = _media?.isVideo ?? playback.isVideo;
        // 视频最多占屏幕高度的 46%，把空间留给控制与字幕
        final videoLimit = math.min(
          screenHeight * (_precisionExpanded ? 0.46 : 0.68),
          maxVideoHeight ?? double.infinity,
        );
        final videoHeight = isVideo
            ? math.min(constraints.maxWidth * 9 / 16, videoLimit)
            : math.min(132.0, videoLimit);

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVideoBlock(
                playback,
                settings,
                currentCue,
                height: videoHeight,
                isVideo: isVideo,
              ),
              _buildTransportBlock(playback, settings),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 视频 + 下方当前字幕。
  ///
  /// 独立成一个方法是为了让横屏布局也能复用：横屏时视频要吃掉整栏高度，
  /// 当前字幕则改成叠在画面上，两者的高度分配完全不同。
  Widget _buildVideoBlock(
    PlaybackSnapshot playback,
    AppSettings settings,
    SubtitleCue? currentCue, {
    required double height,
    required bool isVideo,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: _buildVideoArea(playback, isVideo),
        ),
        if (currentCue != null &&
            currentCue.text.isNotEmpty &&
            settings.subtitleVisible)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              currentCue.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
          ),
      ],
    );
  }

  /// 时间读数 + 时间轴 + 播放控制 + 操作行。
  ///
  /// 竖屏时接在视频下面，横屏时整块搬到右栏，所以要和视频分开。
  Widget _buildTransportBlock(PlaybackSnapshot playback, AppSettings settings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTimeline(playback, settings),
        const SizedBox(height: 6),
        _buildTransportRow(playback),
        _buildMediaPlaybackControls(playback),
        const SizedBox(height: 8),
        _buildActionRow(playback),
        if (playback.status == PlaybackStatus.gapCounting &&
            playback.gapRemaining != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GapCountdownBanner(
              seconds: playback.gapRemaining!,
              total: playback.gapSeconds,
            ),
          ),
      ],
    );
  }

  Widget _buildTimeline(PlaybackSnapshot playback, AppSettings settings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            4,
            AppDimens.pagePadding,
            0,
          ),
          child: TimelineReadout(
            positionMs: playback.positionMs,
            durationMs: playback.durationMs,
            region: playback.loopRegion,
            onClearRegion: playback.loopRegion == null
                ? null
                : () => ref.read(playbackProvider.notifier).clearLoopRegion(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pagePadding,
          ),
          child: TimelineBar(
            positionMs: playback.positionMs,
            durationMs: playback.durationMs,
            region: playback.loopRegion,
            snapEnabled: settings.snapToSubtitle,
            snap: (ms) => ref
                .read(subtitleProvider.notifier)
                .snap(ms, enabled: settings.snapToSubtitle),
            onSeek: (ms) => ref.read(playbackProvider.notifier).seekTo(ms),
            regionChanged: (start, end) =>
                ref.read(playbackProvider.notifier).setLoopRegion(start, end),
          ),
        ),
      ],
    );
  }

  /// 手机横屏：可用高度只有 350dp 上下，竖着堆完视频、时间轴、控制与字幕
  /// 一定溢出，所以换成左右分栏。
  ///
  /// 左栏把高度**全部**给视频（横屏最大的好处就是画面大），当前字幕改为叠在
  /// 画面上；右栏自上而下是时间轴、控制按钮、字幕列表，字幕列表仍然可滚动。
  /// 竖屏时视频下面那行独立字幕因此取消，避免左栏多占一行高度。
  Widget _buildPhoneLandscapeLayout(
    PlaybackSnapshot playback,
    AppSettings settings,
    SubtitleCue? currentCue,
  ) {
    final palette = context.palette;
    final isVideo = _media?.isVideo ?? playback.isVideo;
    final overlay = (currentCue != null && settings.subtitleVisible)
        ? currentCue.text
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            // 左右留白交给 _buildVideoArea 自己处理，这里只管外侧
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _buildVideoArea(
                          playback,
                          isVideo,
                          overlayText: overlay,
                        ),
                      ),
                      if (playback.status == PlaybackStatus.gapCounting &&
                          playback.gapRemaining != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 4,
                          child: GapCountdownBanner(
                            seconds: playback.gapRemaining!,
                            total: playback.gapSeconds,
                          ),
                        ),
                    ],
                  ),
                ),
                _buildTransportRow(playback),
                _buildActionRow(playback),
              ],
            ),
          ),
        ),
        Container(width: 1, color: palette.divider),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, AppDimens.pagePadding, 0),
            child: CompactLandscapePanel(
              controls: _buildMediaPlaybackControls(playback),
              timeline: _buildTimeline(playback, settings),
              sentences: _buildSubtitleArea(settings),
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(PlaybackSnapshot playback) {
    final palette = context.palette;
    return AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _media?.name ?? '播放',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Text(
                playback.status.label,
                style: TextStyle(fontSize: 11, color: palette.textSecondary),
              ),
              if (playback.buffering) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: palette.accent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('toggle-precision'),
          onPressed: _changingPrecision ? null : _togglePrecision,
          icon: Icon(
            _precisionExpanded
                ? Icons.chevron_right_rounded
                : Icons.headphones_rounded,
          ),
          label: Text(_precisionExpanded ? '折叠精听' : '展开精听'),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.subtitles_rounded),
          tooltip: '字幕',
          onSelected: (value) async {
            switch (value) {
              case 'import':
                await _importSubtitle();
                break;
              case 'add':
                await _addSubtitleAtCurrent();
                break;
              case 'edit':
                _openSubtitleEditor();
                break;
              case 'ai':
                await _runAiTranscribe();
                break;
              case 'toggle':
                await ref
                    .read(settingsProvider.notifier)
                    .setSubtitleVisible(
                      !ref.read(settingsProvider).subtitleVisible,
                    );
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'import',
              child: Text('导入字幕（srt / ass / vtt）'),
            ),
            const PopupMenuItem(value: 'add', child: Text('添加字幕（记当前时间点）')),
            const PopupMenuItem(value: 'edit', child: Text('编辑字幕')),
            const PopupMenuItem(value: 'ai', child: Text('AI 自动分句')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                ref.read(settingsProvider).subtitleVisible ? '隐藏字幕' : '显示字幕',
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }

  /// 画面区。竖屏时下方另排一行当前字幕；横屏时高度全部给它，
  /// 当前字幕改用 [overlayText] 叠在画面上。
  Widget _buildVideoArea(
    PlaybackSnapshot playback,
    bool isVideo, {
    String? overlayText,
  }) {
    final palette = context.palette;
    final cue = overlayText == null ? null : _buildOverlayCue(overlayText);

    if (!isVideo) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
        decoration: BoxDecoration(
          color: palette.videoBackdrop,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 34,
                    color: palette.accent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '纯音频模式',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ?cue,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Container(
          color: palette.videoBackdrop,
          child: Stack(
            children: [
              Positioned.fill(
                child: Video(
                  controller: ref.watch(playbackEngineProvider).videoController,
                  // 关掉内置控件，用我们自己的时间轴与按钮
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  // 默认值为 true，会在切后台时暂停，与需求「切后台继续播放」冲突
                  pauseUponEnteringBackgroundMode: false,
                ),
              ),
              ?cue,
              Positioned(
                right: 8,
                bottom: 8,
                child: _VideoCornerButton(
                  icon: Icons.fullscreen_rounded,
                  onTap: _toggleFullscreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 叠在画面上的当前字幕（横屏与全屏播放共用）。
  ///
  /// 需求 §6 要求视频区域不加半透明蒙层，所以可读性靠文字描边与阴影保证。
  /// 底部会抬高一点，避开右下角的全屏按钮。
  Widget _buildOverlayCue(
    String text, {
    double fontSize = 15,
    double bottom = 42,
    double horizontal = 14,
  }) {
    return Positioned(
      left: horizontal,
      right: horizontal,
      bottom: bottom,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          height: 1.3,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(blurRadius: 10, color: Colors.black, offset: Offset(0, 2)),
            Shadow(blurRadius: 4, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportRow(PlaybackSnapshot playback) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: ConstrainedContent(
        maxWidth: 460,
        child: TransportControls(
          isPlaying: playback.isPlaying,
          onTogglePlay: () => ref.read(playbackProvider.notifier).togglePlay(),
          onJump: (seconds) =>
              ref.read(playbackProvider.notifier).seekBySeconds(seconds),
          enabled: playback.hasMedia,
        ),
      ),
    );
  }

  Widget _buildMediaPlaybackControls(
    PlaybackSnapshot playback, {
    bool dark = false,
  }) {
    final mode = ref.watch(mediaPlaybackModeProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final label = switch (mode) {
      MediaPlaybackMode.sequential => '顺序播放',
      MediaPlaybackMode.repeatOne => '单曲循环',
      MediaPlaybackMode.repeatAll => '列表循环',
    };
    final icon = switch (mode) {
      MediaPlaybackMode.sequential => Icons.playlist_play_rounded,
      MediaPlaybackMode.repeatOne => Icons.repeat_one_rounded,
      MediaPlaybackMode.repeatAll => Icons.repeat_rounded,
    };
    return MediaPlaybackControls(
      modeLabel: label,
      modeIcon: icon,
      dark: dark,
      compact: !dark && ScreenAdaptation.isPhoneLandscape(context),
      isPlaying: playback.isPlaying,
      saving: _savingSentence,
      onAddSentence: playback.hasMedia ? _saveSelectedSentence : null,
      onTogglePlay: playback.hasMedia ? notifier.togglePlay : null,
      onPrevious: playback.hasMedia && notifier.queueIndex > 0
          ? notifier.previousMedia
          : null,
      onNext:
          playback.hasMedia &&
              notifier.queueIndex >= 0 &&
              (notifier.queueIndex < notifier.queue.length - 1 ||
                  mode == MediaPlaybackMode.repeatAll)
          ? notifier.nextMedia
          : null,
      onChangeMode: () {
        ref.read(mediaPlaybackModeProvider.notifier).state = switch (mode) {
          MediaPlaybackMode.sequential => MediaPlaybackMode.repeatOne,
          MediaPlaybackMode.repeatOne => MediaPlaybackMode.repeatAll,
          MediaPlaybackMode.repeatAll => MediaPlaybackMode.sequential,
        };
      },
    );
  }

  /// 主操作行：只有循环、倍速、更多三样。
  ///
  /// 「设 A / 设 B / 清除 / 停顿 / 录音 / 收藏」全部收进「更多」面板；
  /// 框选直接拖时间轴上方的选区轨。
  Widget _buildActionRow(PlaybackSnapshot playback) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: ConstrainedContent(
        maxWidth: 520,
        child: Row(
          children: [
            Expanded(
              child: LoopButton(
                snapshot: playback,
                onStart: () async {
                  if (playback.loopRegion == null) {
                    // 没有选区时，一键用当前字幕句建选区；没字幕就教一下框选
                    final cue = SubtitleSnapper.cueAt(
                      playback.positionMs,
                      ref.read(subtitleProvider).cues,
                    );
                    if (cue == null) {
                      _toast('在时间轴上方那条轨道上左右拖动，就能框出一段');
                      return;
                    }
                    await ref.read(playbackProvider.notifier).loopCue(cue);
                  } else {
                    await ref.read(playbackProvider.notifier).startLoop();
                  }
                },
                onStop: () =>
                    ref.read(playbackProvider.notifier).stopLoopKeepRegion(),
                onOpenSettings: _openMoreSheet,
              ),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.speed_rounded,
              label: SpeedSelector.label(playback.speed),
              onTap: () => _openSpeedSheet(playback.speed),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.more_horiz_rounded,
              label: '更多',
              onTap: _openMoreSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitleArea(AppSettings settings) {
    final hasManualSentences = ref
        .watch(subtitleProvider)
        .activeTracks
        .any(
          (track) =>
              track.source == SubtitleSource.manual && track.name == '手动断句',
        );
    if (!settings.subtitleVisible && !hasManualSentences) {
      return Center(
        child: Text(
          '字幕显示已关闭，可在设置里重新打开',
          style: TextStyle(fontSize: 12.5, color: context.palette.textTertiary),
        ),
      );
    }
    return SubtitleListView(
      onImport: _importSubtitle,
      onAdd: _addSubtitleAtCurrent,
      onEdit: _openSubtitleEditor,
    );
  }

  Widget _buildFullscreen(PlaybackSnapshot playback, SubtitleCue? currentCue) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FullscreenPlaybackSurface(
        positionMs: playback.positionMs,
        durationMs: playback.durationMs,
        onSeek: (ms) => ref.read(playbackProvider.notifier).seekTo(ms),
        onTogglePlay: () => ref.read(playbackProvider.notifier).togglePlay(),
        onExit: _toggleFullscreen,
        controls: _buildMediaPlaybackControls(playback, dark: true),
        subtitle:
            currentCue != null &&
                currentCue.text.isNotEmpty &&
                ref.watch(settingsProvider).subtitleVisible
            ? _buildOverlayCue(
                currentCue.text,
                fontSize: 22,
                bottom: 90,
                horizontal: 24,
              )
            : null,
        video: playback.isVideo
            ? Video(
                controller: ref.watch(playbackEngineProvider).videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
                pauseUponEnteringBackgroundMode: false,
              )
            : const Center(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
      ),
    );
  }
  // ------------------------------------------------------------------
  // 底部面板
  // ------------------------------------------------------------------

  /// 「更多」面板：所有不常用的操作集中在这里。
  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ScreenAdaptation.sheetConstraints(context),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: const LoopControlPanel(),
        ),
      ),
    );
  }

  void _openSpeedSheet(double current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: ScreenAdaptation.sheetConstraints(context),
      builder: (sheetContext) => SafeArea(
        child: GlassPanel(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GlassSectionTitle(
                icon: Icons.speed_rounded,
                title: '播放倍速（变速不变调）',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in AppConstants.speedPresets)
                    GlassChip(
                      label: SpeedSelector.label(preset),
                      selected: (preset - current).abs() < 0.001,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(playbackProvider.notifier).setSpeed(preset);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 字幕操作
  // ------------------------------------------------------------------

  Future<void> _saveSelectedSentence() async {
    if (_savingSentence) return;
    final playback = ref.read(playbackProvider);
    final region = playback.loopRegion;
    if (region == null) {
      _toast('请先在时间轴上方拖动框选一段，再点击添加断句');
      return;
    }
    if (playback.mediaId == null ||
        ref.read(subtitleProvider).mediaId != playback.mediaId) {
      _toast('媒体正在切换，请稍后再试');
      return;
    }
    setState(() => _savingSentence = true);
    try {
      final message = await ref
          .read(subtitleProvider.notifier)
          .addSelectedSentence(region.startMs, region.endMs);
      if (!mounted) return;
      final error = ref.read(subtitleProvider).error;
      if (message != null && !_precisionExpanded) {
        setState(() => _precisionExpanded = true);
      }
      _toast(message ?? error ?? '保存断句失败');
      if (error != null) ref.read(subtitleProvider.notifier).consumeError();
    } finally {
      if (mounted) setState(() => _savingSentence = false);
    }
  }

  Future<void> _togglePrecision() async {
    if (_changingPrecision) return;
    if (!_precisionExpanded) {
      setState(() => _precisionExpanded = true);
      return;
    }
    setState(() {
      _precisionExpanded = false;
      _changingPrecision = true;
    });
    try {
      await ref.read(playbackProvider.notifier).exitPrecisionAndRestart();
    } catch (error) {
      if (mounted) _toast(humanizeError(error));
    } finally {
      if (mounted) setState(() => _changingPrecision = false);
    }
  }

  Future<void> _importSubtitle() async {
    final message = await ref
        .read(subtitleProvider.notifier)
        .importFromPicker();
    if (!mounted) return;
    if (message != null) {
      _toast(message);
      return;
    }
    final error = ref.read(subtitleProvider).error;
    if (error != null) {
      _toast(error);
      ref.read(subtitleProvider.notifier).consumeError();
    }
  }

  Future<void> _addSubtitleAtCurrent() async {
    final position = ref.read(playbackProvider).positionMs;
    final message = await ref
        .read(subtitleProvider.notifier)
        .createManualTrackAndLine(position);
    if (!mounted) return;
    if (message != null) {
      _toast(message);
      _openSubtitleEditor();
    } else {
      final error = ref.read(subtitleProvider).error;
      if (error != null) {
        _toast(error);
        ref.read(subtitleProvider.notifier).consumeError();
      }
    }
  }

  Future<void> _runAiTranscribe() async {
    final media = _media;
    if (media == null) return;
    final message = await ref
        .read(subtitleProvider.notifier)
        .runAiTranscribe(mediaUri: media.uri, mediaName: media.name);
    if (!mounted) return;
    _toast(message);
  }

  void _openSubtitleEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SubtitleEditorPage(mediaId: _media?.id ?? widget.mediaId),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _VideoCornerButton extends StatelessWidget {
  const _VideoCornerButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}
