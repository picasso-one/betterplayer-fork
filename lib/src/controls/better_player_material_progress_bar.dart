import 'dart:async';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:better_player/src/video_player/video_player.dart';
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

class BetterPlayerMaterialVideoProgressBar extends StatefulWidget {
  final bool isContentLive;

  BetterPlayerMaterialVideoProgressBar(
    this.controller,
    this.betterPlayerController, {
    BetterPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    Key? key,
  })  : colors = colors ?? BetterPlayerProgressColors(),
        isContentLive = betterPlayerController?.isLiveStream() ?? false,
        super(key: key);

  final VideoPlayerController? controller;
  final BetterPlayerController? betterPlayerController;
  final BetterPlayerProgressColors colors;
  final Function()? onDragStart;
  final Function()? onDragEnd;
  final Function()? onDragUpdate;
  final Function()? onTapDown;

  @override
  _VideoProgressBarState createState() {
    return _VideoProgressBarState();
  }
}

class _VideoProgressBarState extends State<BetterPlayerMaterialVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      if (mounted) setState(() {});
    };
  }

  late VoidCallback listener;
  bool _controllerWasPlaying = false;

  VideoPlayerController? get controller => widget.controller;

  BetterPlayerController? get betterPlayerController => widget.betterPlayerController;

  bool shouldPlayAfterDragEnd = false;
  Duration? lastSeek;
  Timer? _updateBlockTimer;

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag =
        betterPlayerController!.betterPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    return GestureDetector(
      onHorizontalDragStart: (DragStartDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        _controllerWasPlaying = controller!.value.isPlaying;
        if (_controllerWasPlaying) {
          controller!.pause();
        }

        if (widget.onDragStart != null) {
          widget.onDragStart!();
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        seekToRelativePosition(details.globalPosition);

        if (widget.onDragUpdate != null) {
          widget.onDragUpdate!();
        }
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!enableProgressBarDrag) {
          return;
        }

        if (_controllerWasPlaying) {
          betterPlayerController?.play();
          shouldPlayAfterDragEnd = true;
        }
        _setupUpdateBlockTimer();

        if (widget.onDragEnd != null) {
          widget.onDragEnd!();
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }
        seekToRelativePosition(details.globalPosition);
        _setupUpdateBlockTimer();
        if (widget.onTapDown != null) {
          widget.onTapDown!();
        }
      },
      child: Center(
        child: SizedBox(
          height: MediaQuery.of(context).size.height / 2,
          width: MediaQuery.of(context).size.width,
          child: CustomPaint(
            painter: widget.isContentLive
                ? _LiveProgressbarPainter(_getValue(), widget.colors, betterPlayerController)
                : _ProgressBarPainter(_getValue(), widget.colors, betterPlayerController),
          ),
        ),
      ),
    );
  }

  void _setupUpdateBlockTimer() {
    final isLive = betterPlayerController?.isLiveStream() ?? false;
    if (Platform.isIOS && isLive) {
      _updateBlockTimer?.cancel();
      _updateBlockTimer = Timer(const Duration(milliseconds: 500), () {
        lastSeek = null;
        _cancelUpdateBlockTimer();
      });
    } else {
      _updateBlockTimer = Timer(const Duration(milliseconds: 1000), () {
        lastSeek = null;
        _cancelUpdateBlockTimer();
      });
    }
  }

  void _cancelUpdateBlockTimer() {
    _updateBlockTimer?.cancel();
    _updateBlockTimer = null;
  }

  DateTime? _blockProgressUpdatesUntil;

  int clampPosition(int targetMs) {
    final int dvrStartMs = controller!.value.dvrStart.inMilliseconds ?? 0;
    final int dvrEndMs = controller?.value.dvrEnd.inMilliseconds ?? controller?.value.duration?.inMilliseconds ?? 0;

    if (dvrEndMs <= dvrStartMs) {
      return targetMs;
    }

    return targetMs.clamp(dvrStartMs, dvrEndMs);
  }

  VideoPlayerValue _getValue() {
    final isLive = betterPlayerController?.isLiveStream() ?? false;
    if (Platform.isIOS && isLive) {
      if (_blockProgressUpdatesUntil != null && DateTime.now().isBefore(_blockProgressUpdatesUntil!)) {
        return controller!.value.copyWith(position: lastSeek);
      }
      return controller!.value;
    } else {
      if (lastSeek != null) {
        return controller!.value.copyWith(position: lastSeek);
      } else {
        return controller!.value;
      }
    }
  }

  void seekToRelativePosition(Offset globalPosition) async {
    final isLive = betterPlayerController?.isLiveStream() ?? false;
    if (Platform.isIOS && isLive) {
      final box = context.findRenderObject() as RenderBox;
      final double relative = (box.globalToLocal(globalPosition).dx / box.size.width).clamp(0.0, 1.0);

      final int dvrStart = controller!.value.dvrStart.inMilliseconds ?? 0;
      final int dvrEnd = controller!.value.dvrEnd.inMilliseconds ?? controller!.value.duration!.inMilliseconds;

      final int targetMs = (dvrStart + relative * (dvrEnd - dvrStart)).toInt();
      lastSeek = Duration(milliseconds: clampPosition(targetMs));

      _blockProgressUpdatesUntil = DateTime.now().add(const Duration(milliseconds: 700));

      await betterPlayerController!.seekTo(lastSeek!);
      onFinishedLastSeek();
    } else {
      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject != null) {
        final box = renderObject as RenderBox;
        final Offset tapPos = box.globalToLocal(globalPosition);
        final double relative = tapPos.dx / box.size.width;
        if (relative > 0) {
          final Duration position = controller!.value.duration! * relative;
          lastSeek = position;
          await betterPlayerController!.seekTo(position);
          onFinishedLastSeek();
          if (relative >= 1) {
            lastSeek = controller!.value.duration;
            await betterPlayerController!.seekTo(controller!.value.duration!);
            onFinishedLastSeek();
          }
        }
      }
    }
  }

  void onFinishedLastSeek() {
    if (shouldPlayAfterDragEnd) {
      shouldPlayAfterDragEnd = false;
      betterPlayerController?.play();
    }
    if (Platform.isIOS) {
      // Resetuj lastSeek dopiero po małym delay, aby AVPlayer zakończył buffering
      Future.delayed(const Duration(milliseconds: 500), () {
        lastSeek = null;
        if (mounted) setState(() {}); // odśwież progress bar
      });
    }
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double _indicatorScaleFactor;
  final double _progressBarHeightPx;
  final double _progressBarCurrentTimeIndicatorPx;
  final double _roundRadius;

  final VideoPlayerValue _value;
  final BetterPlayerProgressColors _colors;
  final BetterPlayerController? controller;

  _ProgressBarPainter(
    this._value,
    this._colors,
    this.controller, {
    double progressBarHeightPx = 2,
    double indicatorScaleFactor = 3,
    double roundRadius = 4,
  })  : _indicatorScaleFactor = indicatorScaleFactor,
        _progressBarHeightPx = progressBarHeightPx,
        _progressBarCurrentTimeIndicatorPx = progressBarHeightPx * indicatorScaleFactor,
        _roundRadius = roundRadius;

  @override
  bool shouldRepaint(CustomPainter painter) => _value.initialized;

  double _safePlayedPart(Size size) {
    final durationMs = _value.duration?.inMilliseconds ?? 0;

    if (!_value.initialized || durationMs <= 0) {
      return 0.0;
    }

    final positionMs = _value.position.inMilliseconds;
    final percent = (positionMs / durationMs).clamp(0.0, 1.0);

    return percent * size.width;
  }

  void _drawBufferedSafe(Canvas canvas, Size size) {
    final duration = _value.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;

    for (final range in _value.buffered) {
      double start = range.startFraction(duration) * size.width;
      double end = range.endFraction(duration) * size.width;

      if (!start.isNaN && !end.isNaN) {
        drawBufferedProgressBar(canvas, size, start, end);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawProgressBarBackground(canvas, size);

    if (this is _LiveProgressbarPainter) {
      _drawActualProgressBar(canvas, size);
      return;
    }
    final playedPart = _safePlayedPart(size);
    _drawPlayedProgressBar(canvas, size, playedPart);
    _drawCurrentTimeIndicator(canvas, size, playedPart);
    _drawBufferedSafe(canvas, size);
  }

  void _drawProgressBarBackground(Canvas canvas, Size size) {
    _drawLinearProgressBar(
      canvas,
      _colors.backgroundPaint,
      0.0,
      size.height / 2,
      size.width,
      size.height / 2,
    );
  }

  void _drawActualProgressBar(Canvas canvas, Size size) {
    if (_value.duration == null) return;
    if (_value.duration!.inMilliseconds <= 0) return;

    final isLive = controller?.isLiveStream() ?? false;
    if (Platform.isIOS && isLive) {
      // Use DVR if available
      final int dvrStartMs = (_value.dvrStart as Duration?)?.inMilliseconds ?? 0;
      final int dvrEndMs = (_value.dvrEnd as Duration?)?.inMilliseconds ?? _value.duration!.inMilliseconds;
      final int positionMs = _value.position.inMilliseconds;

      // Calculate played part percent based on DVR
      final durationMs = _value.duration?.inMilliseconds ?? 0;
      if (durationMs <= 0) return;

      double playedPartPercent = _value.position.inMilliseconds / durationMs;

      playedPartPercent = playedPartPercent.clamp(0.0, 1.0);
      final double playedPart = playedPartPercent * size.width;

      // Draw buffered ranges based on DVR
      for (final DurationRange range in _value.buffered) {
        double rangeStart =
            ((range.start.inMilliseconds - dvrStartMs) / (dvrEndMs - dvrStartMs) * size.width).clamp(0.0, size.width);
        double rangeEnd =
            ((range.end.inMilliseconds - dvrStartMs) / (dvrEndMs - dvrStartMs) * size.width).clamp(0.0, size.width);
        drawBufferedProgressBar(canvas, size, rangeStart, rangeEnd);
      }

      _drawPlayedProgressBar(canvas, size, playedPart);
      _drawCurrentTimeIndicator(canvas, size, playedPart);
    } else {
      double playedPartPercent = _value.position.inMilliseconds / _value.duration!.inMilliseconds;
      if (playedPartPercent.isNaN) {
        playedPartPercent = 0;
      }
      final double playedPart = playedPartPercent > 1 ? size.width : playedPartPercent * size.width;

      for (final DurationRange range in _value.buffered) {
        double start = range.startFraction(_value.duration!) * size.width;
        if (start.isNaN) {
          start = 0;
        }
        double end = range.endFraction(_value.duration!) * size.width;
        if (end.isNaN) {
          end = 0;
        }
        drawBufferedProgressBar(canvas, size, start, end);
      }

      _drawPlayedProgressBar(canvas, size, playedPart);
      _drawCurrentTimeIndicator(canvas, size, playedPart);
    }
  }

  void _drawLinearProgressBar(Canvas canvas, Paint paint, double startX, double startY, double endX, double endY) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(startX, startY),
          Offset(endX, endY),
        ),
        Radius.circular(_roundRadius),
      ),
      paint,
    );
  }

  void _drawProgressIndicator(Canvas canvas, Paint paint, Offset center, double radius) {
    canvas.drawCircle(center, radius, paint);
  }

  void drawBufferedProgressBar(Canvas canvas, Size size, double start, double end) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(start, size.height / 2),
          Offset(end, size.height / 2 + _progressBarHeightPx),
        ),
        Radius.circular(_roundRadius),
      ),
      _colors.bufferedPaint,
    );
  }

  void _drawCurrentTimeIndicator(Canvas canvas, Size size, double playedPart) {
    canvas.drawCircle(
      Offset(playedPart, size.height / 2 + _progressBarHeightPx / 2),
      _progressBarCurrentTimeIndicatorPx,
      _colors.handlePaint,
    );
  }

  void _drawPlayedProgressBar(Canvas canvas, Size size, double playedPart) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, size.height / 2),
          Offset(playedPart, size.height / 2 + _progressBarHeightPx),
        ),
        Radius.circular(_roundRadius),
      ),
      _colors.playedPaint,
    );
  }
}

class _LiveProgressbarPainter extends _ProgressBarPainter {
  _LiveProgressbarPainter(
    VideoPlayerValue value,
    BetterPlayerProgressColors colors,
    BetterPlayerController? controller,
  ) : super(value, colors, controller);

  @override
  void _drawActualProgressBar(Canvas canvas, Size size) {
    _drawLiveContent(canvas, size);
  }

  void _drawLiveContent(Canvas canvas, Size size) {
    final double liveProgress = _getLiveContentProgress();

    final double indicatorPosition = size.width * liveProgress;

    // below draws right side of the progress bar
    _drawLinearProgressBar(
      canvas,
      _colors.playedPaint,
      indicatorPosition,
      size.height / 2,
      size.width,
      size.height / 2 + _progressBarHeightPx / 2,
    );

    // below draws right side of progress the bar
    _drawLinearProgressBar(
      canvas,
      _colors.playedPaint,
      0.0,
      size.height / 2,
      indicatorPosition,
      size.height / 2 + _progressBarHeightPx,
    );

    _drawProgressIndicator(
      canvas,
      _colors.handlePaint,
      Offset(indicatorPosition, size.height / 2 + _progressBarHeightPx / 2),
      _progressBarHeightPx * _indicatorScaleFactor,
    );
  }

  //make sure that progress is not minus or more than 100%. This can only apply for live content.
  double _getLiveContentProgress() {
    // final isLive = controller?.isLiveStream() ?? false;
    // if (Platform.isIOS && isLive) {
    //   final double startMs = (_value.dvrStart as Duration?)?.inMilliseconds.toDouble() ?? 0.0;
    //   final double endMs =
    //       (_value.dvrEnd as Duration?)?.inMilliseconds.toDouble() ?? _value.duration!.inMilliseconds.toDouble();
    //   final int positionMs = _value.position.inMilliseconds.toInt();

    //   return ((positionMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
    // } else {
    //   return (_value.position.inMilliseconds / _value.duration!.inMilliseconds).clamp(0, 1);
    // }

    final isLive = controller?.isLiveStream() ?? false;

    if (!isLive) return 0.0;

    // iOS LIVE – DVR window
    if (Platform.isIOS) {
      final dvrStartMs = _value.dvrStart.inMilliseconds;
      final dvrEndMs = _value.dvrEnd.inMilliseconds;
      final positionMs = _value.position.inMilliseconds;

      if (dvrEndMs <= dvrStartMs) {
        return 1.0;
      }

      return ((positionMs - dvrStartMs) / (dvrEndMs - dvrStartMs)).clamp(0.0, 1.0);
    }

    // Android / inne
    final durationMs = _value.duration?.inMilliseconds;
    if (durationMs == null || durationMs <= 0) {
      return 1.0; // LIVE EDGE
    }

    return (_value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
  }
}
