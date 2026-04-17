import 'package:flutter/material.dart';

class BetterPlayerPlayNextVideoConfiguration {
  final int showBeforeEndMillis;
  final int autoSwitchToNextMillis;
  final Widget Function(double progress) playNextBuilder;
  final VoidCallback? onPlayNext;

  BetterPlayerPlayNextVideoConfiguration({
    required this.playNextBuilder,
    required this.autoSwitchToNextMillis,
    required this.showBeforeEndMillis,
    this.onPlayNext,
  });
}
