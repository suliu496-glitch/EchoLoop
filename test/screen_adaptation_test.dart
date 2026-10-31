import 'package:echoloop/ui/adaptive/screen_adaptation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in <(String, Size, bool, bool)>[
    ('平板横屏', const Size(1440, 900), true, false),
    ('平板竖屏', const Size(900, 1440), true, false),
    ('手机横屏', const Size(844, 390), false, true),
    ('手机竖屏', const Size(390, 844), false, false),
  ]) {
    testWidgets('${scenario.$1}使用正确的布局分类', (tester) async {
      late bool tablet;
      late bool phoneLandscape;
      late bool wide;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: scenario.$2),
          child: Builder(builder: (context) {
            tablet = ScreenAdaptation.isTablet(context);
            phoneLandscape = ScreenAdaptation.isPhoneLandscape(context);
            wide = ScreenAdaptation.isWide(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(tablet, scenario.$3);
      expect(phoneLandscape, scenario.$4);
      expect(wide, scenario.$3 || scenario.$4);
    });
  }
}
