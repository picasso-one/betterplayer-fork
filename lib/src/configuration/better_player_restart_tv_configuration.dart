import 'package:flutter/material.dart';

class BetterPlayerRestartTvConfiguration {
  final int? startTimeMillis;
  final int? endTimeMillis;
  final Color? activeLiveColor;
  final Color? inactiveLiveColor;
  final String? liveButtonText;

  BetterPlayerRestartTvConfiguration({
    required this.startTimeMillis,
    required this.endTimeMillis,
    required this.activeLiveColor,
    required this.inactiveLiveColor,
    required this.liveButtonText,
  });
}
