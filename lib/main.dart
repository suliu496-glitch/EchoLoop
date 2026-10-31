import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/models/app_settings.dart';
import 'providers/settings_provider.dart';
import 'ui/adaptive/screen_adaptation.dart';
import 'ui/pages/library_page.dart';
import 'ui/widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit 会在这一步加载 libmpv 原生库，必须在使用任何 Player 之前调用
  MediaKit.ensureInitialized();

  runApp(const ProviderScope(child: EchoLoopApp()));
}

/// 应用根组件。
///
/// 主题在亮色 / 深色两套毛玻璃之间切换（需求 §6：深色模式跟随系统）；
/// 背景通过 [MaterialApp.builder] 注入，这样二级页面也能共享同一层柔光背景。
class EchoLoopApp extends ConsumerStatefulWidget {
  const EchoLoopApp({super.key});

  @override
  ConsumerState<EchoLoopApp> createState() => _EchoLoopAppState();
}

class _EchoLoopAppState extends ConsumerState<EchoLoopApp> {
  /// 方向策略是否已经应用过
  bool _orientationApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orientationApplied) return;
    _orientationApplied = true;

    // 方向策略：全部放开。竖屏是主用姿态，但横过来也要能用
    // （看视频、跟读时把手机平放在桌面上）。
    //
    // 只设一次就够：这份策略与设备形态无关，旋转屏幕时不需要重新设置，
    // 反复调用反而会多走几遍 platform channel。
    // 全屏播放视频时播放页会临时锁成横屏，退出全屏时恢复到这一份。
    SystemChrome.setPreferredOrientations(
      ScreenAdaptation.preferredOrientations(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = switch (settings.themeMode) {
      ThemeModeSetting.light => ThemeMode.light,
      ThemeModeSetting.dark => ThemeMode.dark,
      ThemeModeSetting.system => ThemeMode.system,
    };

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          AppBackground(child: child ?? const SizedBox.shrink()),
      home: const LibraryPage(),
    );
  }
}
