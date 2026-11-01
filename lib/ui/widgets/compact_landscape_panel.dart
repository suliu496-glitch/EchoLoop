import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 矮屏横向布局始终保留高频操作，时间轴和句子区可滚动。
class CompactLandscapePanel extends StatelessWidget {
  const CompactLandscapePanel({
    super.key,
    required this.controls,
    required this.timeline,
    required this.sentences,
  });

  final Widget controls;
  final Widget timeline;
  final Widget sentences;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        controls,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    timeline,
                    const SizedBox(height: 4),
                    SizedBox(
                      height: math.max(150.0, constraints.maxHeight - 104),
                      child: sentences,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
