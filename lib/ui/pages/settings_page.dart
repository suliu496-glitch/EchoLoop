import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/media_item.dart' show LoopMode;
import '../../providers/playback_provider.dart';
import '../../providers/settings_provider.dart';
import '../adaptive/screen_adaptation.dart';
import '../widgets/glass.dart';

/// 设置页：所有全局开关都收在这里。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ConstrainedContent(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              4,
              AppDimens.pagePadding,
              32,
            ),
            children: [
              // ---------------- 播放 ----------------
              _Section(
                icon: Icons.play_circle_outline_rounded,
                title: '播放',
                children: [
                  _RowLabel(title: '默认倍速', hint: '全局设置，切换文件后保持不变（需求 §4.2）'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in AppConstants.speedPresets)
                        GlassChip(
                          label: preset == preset.roundToDouble()
                              ? '${preset.toInt()}.0x'
                              : '${preset}x',
                          selected: (preset - settings.speed).abs() < 0.001,
                          onTap: () => notifier.setSpeed(preset),
                        ),
                    ],
                  ),
                  const _Gap(height: 14),
                  _RowLabel(title: '默认循环模式', hint: '手动框选片段时默认使用的模式'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GlassChip(
                        label: '无限循环',
                        selected: settings.loopMode == LoopMode.infinite,
                        onTap: () => notifier.setLoopMode(LoopMode.infinite),
                      ),
                      for (final count in AppConstants.loopCountPresets)
                        GlassChip(
                          label: '$count 遍',
                          selected:
                              settings.loopMode == LoopMode.count &&
                              settings.loopCount == count,
                          onTap: () {
                            notifier.setLoopMode(LoopMode.count);
                            notifier.setLoopCount(count);
                          },
                        ),
                    ],
                  ),
                ],
              ),

              // ---------------- 跟读 ----------------
              _Section(
                icon: Icons.mic_none_rounded,
                title: '跟读',
                children: [
                  _RowLabel(title: '跟读停顿', hint: '每遍循环播完插入的静默时间，留出开口说的空隙'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final gap in AppConstants.gapPresets)
                        GlassChip(
                          label: gap == 0 ? '关闭' : '$gap 秒',
                          selected: settings.gapSeconds == gap,
                          onTap: () => notifier.setGapSeconds(gap),
                        ),
                    ],
                  ),
                  const _Gap(height: 12),
                  _SwitchRow(
                    title: '停顿期间自动录音',
                    subtitle: settings.gapEnabled
                        ? '每遍停顿自动开麦，便于原声与录音对比'
                        : '需要先开启跟读停顿',
                    value: settings.recordDuringGap,
                    enabled: settings.gapEnabled,
                    onChanged: notifier.setRecordDuringGap,
                  ),
                  const _Gap(height: 6),
                  _ActionRow(
                    icon: Icons.delete_sweep_outlined,
                    title: '清空录音临时文件',
                    onTap: () async {
                      await ref
                          .read(playbackProvider.notifier)
                          .deleteRecording();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('录音临时文件已清空')),
                      );
                    },
                  ),
                ],
              ),

              // ---------------- AI 自动分句 ----------------
              const _TranscriberSettingsSection(),

              // ---------------- 字幕 ----------------
              _Section(
                icon: Icons.subtitles_outlined,
                title: '字幕',
                children: [
                  _SwitchRow(
                    title: '片段边界自动吸附字幕',
                    subtitle: '拖动 A / B 点时自动贴到最近的字幕句边界（1 秒内）',
                    value: settings.snapToSubtitle,
                    onChanged: notifier.setSnapToSubtitle,
                  ),
                  _SwitchRow(
                    title: '显示字幕列表',
                    subtitle: '关闭字幕显示后，手动断句列表仍可用于精听',
                    value: settings.subtitleVisible,
                    onChanged: notifier.setSubtitleVisible,
                  ),
                  const _Gap(height: 6),
                ],
              ),

              // ---------------- 外观 ----------------
              _Section(
                icon: Icons.palette_outlined,
                title: '外观',
                children: [
                  _RowLabel(title: '主题', hint: '深色模式跟随系统时自动切换毛玻璃变体'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in ThemeModeSetting.values)
                        GlassChip(
                          label: mode.label,
                          selected: settings.themeMode == mode,
                          onTap: () => notifier.setThemeMode(mode),
                        ),
                    ],
                  ),
                ],
              ),

              // ---------------- 关于 ----------------
              _Section(
                icon: Icons.info_outline_rounded,
                title: '关于',
                children: [
                  _InfoRow(
                    icon: Icons.apps_rounded,
                    title: '应用',
                    value: '${AppConstants.appName} 1.0.4',
                  ),
                  _InfoRow(
                    icon: Icons.shield_outlined,
                    title: '权限说明',
                    value: '媒体访问、麦克风、通知、前台播放；AI 转写需联网',
                  ),
                  _InfoRow(
                    icon: Icons.cloud_outlined,
                    title: '网络',
                    value: '仅在使用 AI 自动分句时连接你配置的识别服务',
                  ),
                  _InfoRow(
                    icon: Icons.folder_special_outlined,
                    title: '文件处理',
                    value: '只记录文件引用，不复制、不移动原文件',
                  ),
                  const _Gap(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '导入的美剧片段、听力材料都只保存在媒体库里；'
                      '从媒体库删除条目不会影响手机上的原文件。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: context.palette.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriberSettingsSection extends ConsumerStatefulWidget {
  const _TranscriberSettingsSection();

  @override
  ConsumerState<_TranscriberSettingsSection> createState() =>
      _TranscriberSettingsSectionState();
}

class _TranscriberSettingsSectionState
    extends ConsumerState<_TranscriberSettingsSection> {
  final TextEditingController _apiKeyController = TextEditingController();
  String? _endpointDraft;
  String? _modelDraft;
  String? _languageDraft;
  bool _saving = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final palette = context.palette;

    return _Section(
      icon: Icons.record_voice_over_outlined,
      title: 'AI 自动分句',
      children: [
        const _RowLabel(
          title: 'API 接口地址',
          hint: '使用 Whisper 兼容的语音转写接口；默认 OpenAI 地址，也可填兼容服务地址。',
        ),
        TextFormField(
          key: ValueKey('transcriber-endpoint-${settings.transcriberEndpoint}'),
          initialValue: settings.transcriberEndpoint,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'https://api.openai.com/v1',
            isDense: true,
          ),
          onChanged: (value) => _endpointDraft = value,
        ),
        const _Gap(height: 12),
        const _RowLabel(title: '识别模型'),
        TextFormField(
          key: ValueKey('transcriber-model-${settings.transcriberModel}'),
          initialValue: settings.transcriberModel,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'whisper-1',
            isDense: true,
          ),
          onChanged: (value) => _modelDraft = value,
        ),
        const _Gap(height: 12),
        const _RowLabel(title: '语音语言', hint: '留空时由模型自动识别；也可填写语言代码，例如 zh 或 en。'),
        TextFormField(
          key: ValueKey('transcriber-language-${settings.transcriberLanguage}'),
          initialValue: settings.transcriberLanguage,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '留空自动识别', isDense: true),
          onChanged: (value) => _languageDraft = value,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await notifier.setTranscriberEndpoint(
                        _endpointDraft ?? settings.transcriberEndpoint,
                      );
                      await notifier.setTranscriberModel(
                        _modelDraft ?? settings.transcriberModel,
                      );
                      await notifier.setTranscriberLanguage(
                        _languageDraft ?? settings.transcriberLanguage,
                      );
                      _endpointDraft = null;
                      _modelDraft = null;
                      _languageDraft = null;
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('识别服务设置已保存')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(_saving ? '保存中…' : '保存接口设置'),
          ),
        ),
        const _Gap(height: 4),
        const _RowLabel(
          title: 'API Key',
          hint: '密钥使用 Android 安全存储保存在本机，不会写入字幕或媒体文件。',
        ),
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: settings.transcriberApiKeyConfigured
                ? '已配置；留空会保留当前密钥'
                : '粘贴服务商提供的 API Key',
            isDense: true,
          ),
        ),
        const _Gap(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                settings.transcriberApiKeyConfigured ? '本机已保存识别密钥' : '尚未配置识别密钥',
                style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
              ),
            ),
            if (settings.transcriberApiKeyConfigured)
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          await notifier.clearTranscriberApiKey();
                          _apiKeyController.clear();
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('删除失败：$error')),
                            );
                          }
                        }
                      },
                child: const Text('删除密钥'),
              ),
            FilledButton.tonal(
              onPressed: _saving || _apiKeyController.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await notifier.saveTranscriberApiKey(
                          _apiKeyController.text,
                        );
                        _apiKeyController.clear();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('API Key 已安全保存')),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('保存失败：$error')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: const Text('保存密钥'),
            ),
          ],
        ),
        const _Gap(height: 4),
        Text(
          '点击「AI 自动分句」时，媒体音轨会分段上传到上述服务。请只使用你信任的接口；服务商可能按用量计费。',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassSectionTitle(icon: icon, title: title),
            const _Gap(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: palette.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: palette.accent,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: palette.textSecondary),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
