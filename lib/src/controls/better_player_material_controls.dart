import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:better_player/src/controls/better_player_clickable_widget.dart';
import 'package:better_player/src/controls/better_player_material_progress_bar.dart';
import 'package:better_player/src/controls/progress_bar_utils.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/video_player/video_player.dart';
import 'package:flutter/foundation.dart';
// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_cast_video/flutter_cast_video.dart';
import 'package:flutter_to_airplay/flutter_to_airplay.dart';

class BetterPlayerMaterialControls extends StatefulWidget {
  ///Callback used to send information if player bar is hidden or not
  final Function(bool visbility) onControlsVisibilityChanged;

  ///Controls config
  final BetterPlayerControlsConfiguration controlsConfiguration;
  final Function()? onChannelListPressed;

  const BetterPlayerMaterialControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
    this.onChannelListPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _BetterPlayerMaterialControlsState();
  }
}

class _BetterPlayerMaterialControlsState extends BetterPlayerControlsState<BetterPlayerMaterialControls> {
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  bool _displayTapped = false;
  bool _wasLoading = false;
  VideoPlayerController? _controller;
  BetterPlayerController? _betterPlayerController;
  StreamSubscription? _controlsVisibilityStreamSubscription;
  late ChromeCastController _chromeCastController;
  AppState _state = AppState.idle;
  bool _playing = false;
  Map<dynamic, dynamic> _mediaInfo = {};

  BetterPlayerControlsConfiguration get _controlsConfiguration => widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  BetterPlayerController? get betterPlayerController => _betterPlayerController;

  @override
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration => _controlsConfiguration;

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  ///Builds main widget of the controls.
  Widget _buildMainWidget() {
    _wasLoading = isLoading(_latestValue);
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }
    return GestureDetector(
      onTap: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onTap?.call();
        }
        controlsNotVisible ? cancelAndRestartTimer() : changePlayerControlsNotVisible(true);
      },
      onDoubleTap: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
        }
        cancelAndRestartTimer();
      },
      onLongPress: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < 0) {
            if (betterPlayerController!.isFullScreen)
              betterPlayerController?.betterPlayerSwipeConfiguration?.onSwipeRight.call();
          } else if (details.primaryVelocity! > 0) {
            if (betterPlayerController!.isFullScreen)
              betterPlayerController?.betterPlayerSwipeConfiguration?.onSwipeLeft.call();
          }
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_wasLoading) Center(child: _buildLoadingWidget()) else _buildHitArea(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
            _buildNextVideoWidget(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    _controller?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    final _oldController = _betterPlayerController;
    _betterPlayerController = BetterPlayerController.of(context);
    _controller = _betterPlayerController!.videoPlayerController;
    _latestValue = _controller!.value;

    if (_oldController != _betterPlayerController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildErrorWidget() {
    final errorBuilder = _betterPlayerController!.betterPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(context, _betterPlayerController!.videoPlayerController!.value.errorDescription);
    } else {
      final textStyle = TextStyle(color: _controlsConfiguration.textColor);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning,
              color: _controlsConfiguration.iconsColor,
              size: 42,
            ),
            Text(
              _betterPlayerController!.translations.generalDefaultError,
              style: textStyle,
            ),
            if (_controlsConfiguration.enableRetry)
              TextButton(
                onPressed: () {
                  _betterPlayerController!.retryDataSource();
                },
                child: Text(
                  _betterPlayerController!.translations.generalRetry,
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                ),
              )
          ],
        ),
      );
    }
  }

  Widget _buildTopBar() {
    if (!betterPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return Container(
      child: (_controlsConfiguration.enableOverflowMenu)
          ? AnimatedOpacity(
              opacity: controlsNotVisible ? 0.0 : 1.0,
              duration: _controlsConfiguration.controlsHideTime,
              onEnd: _onPlayerHide,
              child: Container(
                height: _controlsConfiguration.controlBarHeight,
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_betterPlayerController!.isFullScreen && _controlsConfiguration.useModernDesignControls)
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: _buildExitButton(),
                      ),
                    if (_betterPlayerController!.isFullScreen &&
                        _betterPlayerController!.betterPlayerControlsConfiguration.showBackArrow &&
                        !_controlsConfiguration.useModernDesignControls)
                      _buildCloseFullScreenArrow(),
                    const Spacer(),
                    if (defaultTargetPlatform == TargetPlatform.iOS && _controlsConfiguration.useModernDesignControls)
                      _buildAirplayButton(),
                    if (defaultTargetPlatform == TargetPlatform.android &&
                        _controlsConfiguration.useModernDesignControls)
                      _buildChromeCastButton(),
                    if (_controlsConfiguration.enablePip)
                      _buildPipButtonWrapperWidget(controlsNotVisible, _onPlayerHide)
                    else
                      const SizedBox(),
                    _controlsConfiguration.useModernDesignControls ? SizedBox.shrink() : _buildMoreButton(),
                    if (_controlsConfiguration.showExitButton && !_controlsConfiguration.useModernDesignControls)
                      _buildExitButton()
                    else
                      !_controlsConfiguration.useModernDesignControls
                          ? Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: _buildExpandButton(),
                            )
                          : betterPlayerController!.isLiveStream() ||
                                  betterPlayerController!.betterPlayerRestartTvConfiguration != null
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 24),
                                  child: _buildExpandButton(),
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(right: 24),
                                  child: SizedBox.shrink(),
                                ),
                  ],
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  Widget _buildPipButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        betterPlayerController!.enablePictureInPicture(betterPlayerController!.betterPlayerGlobalKey!);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.pipMenuIcon,
          color: betterPlayerControlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  Widget _buildPipButtonWrapperWidget(bool hideStuff, void Function() onPlayerHide) {
    return FutureBuilder<bool>(
      future: betterPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (isPipSupported && _betterPlayerController!.betterPlayerGlobalKey != null) {
          return AnimatedOpacity(
            opacity: hideStuff ? 0.0 : 1.0,
            duration: betterPlayerControlsConfiguration.controlsHideTime,
            onEnd: onPlayerHide,
            child: Container(
              height: betterPlayerControlsConfiguration.controlBarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildPipButton(),
                ],
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget _buildMoreButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Padding(
        padding: EdgeInsets.all(_controlsConfiguration.useModernDesignControls ? 0 : 8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!betterPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        height: _controlsConfiguration.controlBarHeight + (betterPlayerController!.isFullScreen ? 58.0 : 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _betterPlayerController?.betterPlayerConfiguration.videoImageUrl != null &&
                    _controlsConfiguration.useModernDesignControls &&
                    betterPlayerController!.isLiveStream() &&
                    betterPlayerController!.isFullScreen
                ? Expanded(flex: 80, child: _buildVideoImage())
                : SizedBox.shrink(),
            Expanded(
              flex: 75,
              child: Row(
                children: [
                  if (_controlsConfiguration.enablePlayPause && !_controlsConfiguration.useModernDesignControls)
                    _buildPlayPause(_controller!)
                  else
                    const SizedBox(),
                  if (betterPlayerController?.betterPlayerConfiguration.videoTitleText != null &&
                      betterPlayerController!.isFullScreen &&
                      !betterPlayerController!.isLiveStream() &&
                      betterPlayerController!.betterPlayerRestartTvConfiguration == null)
                    Expanded(flex: 4, child: _buildVideoTitle()),
                  if (betterPlayerController?.betterPlayerConfiguration.videoTitleText != null &&
                      betterPlayerController!.isFullScreen &&
                      betterPlayerController!.betterPlayerRestartTvConfiguration != null)
                    _buildVideoTitle(),
                  if (betterPlayerController!.betterPlayerRestartTvConfiguration != null)
                    Expanded(child: _buildIsLiveButton(_controller!)),
                  _controlsConfiguration.enableProgressText
                      ? Expanded(flex: 6, child: _buildPosition())
                      : const SizedBox(),
                  const Spacer(),
                  if (defaultTargetPlatform == TargetPlatform.iOS && !_controlsConfiguration.useModernDesignControls)
                    _buildAirplayButton(),
                  if (defaultTargetPlatform == TargetPlatform.android && _controlsConfiguration.useModernDesignControls)
                    _buildChromeCastButton(),
                  if (_controlsConfiguration.enableMute) _buildMuteButton(_controller) else const SizedBox(),
                  if (_controlsConfiguration.useModernDesignControls)
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: _buildMoreButton(),
                    ),
                  if (_controlsConfiguration.enableFullscreen &&
                      !_controlsConfiguration.onlyFullScreen &&
                      !_controlsConfiguration.useModernDesignControls)
                    _buildExpandButton()
                  else
                    const SizedBox(),
                ],
              ),
            ),
            ProgressbarUtils.canShowProgressbar(
              _controlsConfiguration,
              betterPlayerController!,
              _controller,
            )
                ? _buildProgressBar()
                : const SizedBox.shrink(),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandButton() {
    return Padding(
      padding: EdgeInsets.only(right: 12.0),
      child: BetterPlayerMaterialClickableWidget(
        onTap: _onExpandCollapse,
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Icon(
                _betterPlayerController!.isFullScreen
                    ? _controlsConfiguration.fullscreenDisableIcon
                    : _controlsConfiguration.fullscreenEnableIcon,
                color: _controlsConfiguration.iconsColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    if (!betterPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    return Container(
      child: Center(
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: _buildMiddleRow(),
        ),
      ),
    );
  }

  Widget _buildMiddleRow() {
    return Container(
      color: _controlsConfiguration.controlBarColor,
      width: double.infinity,
      height: double.infinity,
      child: _controlsConfiguration.useModernDesignControls ? _modernControlRow() : _standardControlRow(),
    );
  }

  Widget _standardControlRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_controlsConfiguration.enableSkips) Expanded(child: _buildSkipButton()) else const SizedBox(),
          if (_controlsConfiguration.enableReplayButton) Expanded(child: _buildReplayButton(_controller!)),
          if (_controlsConfiguration.enableSkips) Expanded(child: _buildForwardButton()) else const SizedBox(),
        ],
      );

  Widget _modernControlRow() => Row(
        mainAxisAlignment: betterPlayerController!.isFullScreen
            ? MainAxisAlignment.center
            : betterPlayerController!.betterPlayerRestartTvConfiguration != null &&
                    betterPlayerController!.isLiveStream()
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
        children: [
          if (betterPlayerController?.betterPlayerTvChannelListConfiguration != null &&
              betterPlayerController!.isFullScreen)
            Expanded(child: SizedBox(width: 40)),
          if (betterPlayerController!.betterPlayerRestartTvConfiguration != null &&
              betterPlayerController!.isLiveStream())
            Padding(
              padding: EdgeInsets.only(
                left: betterPlayerController!.isFullScreen
                    ? 0
                    : betterPlayerController!.betterPlayerRestartTvConfiguration != null &&
                            betterPlayerController!.isLiveStream()
                        ? 28
                        : 0,
              ),
              child: _buildRestart(_controller!),
            ),
          if (_controlsConfiguration.enableSkips ||
              betterPlayerController!.isLiveStream() ||
              !betterPlayerController!.isLiveStream())
            _buildModernSkipButton()
          else
            const SizedBox(),
          Center(child: _buildModernReplayButton(_controller!)),
          if (_controlsConfiguration.enableSkips ||
              betterPlayerController!.isLiveStream() ||
              !betterPlayerController!.isLiveStream())
            _buildModernForwardButton()
          else
            const SizedBox(),
          if (betterPlayerController?.betterPlayerTvChannelListConfiguration != null &&
              betterPlayerController!.isFullScreen) ...[
            Expanded(child: SizedBox(width: 40)),
            _buildModernChannelListButton(_controller!),
          ]
        ],
      );

  Widget _buildHitAreaClickableButton({Widget? icon, required void Function() onClicked}) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 80.0, maxWidth: 80.0),
      child: BetterPlayerMaterialClickableWidget(
        onTap: onClicked,
        child: Align(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(48),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [icon!],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipBackIcon,
        size: 24,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipBack,
    );
  }

  Widget _buildModernSkipButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: _BetterPlayerModerBackgroundButton(
        size: 48,
        child: _buildHitAreaClickableButton(
          icon: Text(
            '-10s',
            style: TextStyle(
              color: _controlsConfiguration.iconsColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          onClicked: skipBack,
        ),
      ),
    );
  }

  Widget _buildForwardButton() {
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipForwardIcon,
        size: 24,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipForward,
    );
  }

  Widget _buildModernForwardButton() {
    final end = latestValue!.duration!.inMilliseconds;
    final skip = (latestValue!.position +
            Duration(milliseconds: betterPlayerControlsConfiguration.forwardSkipTimeInMilliseconds))
        .inMilliseconds;

    return _BetterPlayerModerBackgroundButton(
      size: 48,
      color: skip > end ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.8),
      child: _buildHitAreaClickableButton(
        icon: Text(
          '+10s',
          style: TextStyle(
            color: _controlsConfiguration.iconsColor.withOpacity(skip > end ? 0.5 : 1.0),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        onClicked: () {
          if (skip < end) {
            skipForward();
          }
        },
      ),
    );
  }

  Widget _buildReplayButton(VideoPlayerController controller) {
    final bool isFinished = isVideoFinished(_latestValue);
    return _buildHitAreaClickableButton(
      icon: isFinished
          ? Icon(
              Icons.replay,
              size: 42,
              color: _controlsConfiguration.iconsColor,
            )
          : Icon(
              controller.value.isPlaying ? _controlsConfiguration.pauseIcon : _controlsConfiguration.playIcon,
              size: 42,
              color: _controlsConfiguration.iconsColor,
            ),
      onClicked: () {
        if (isFinished) {
          if (_latestValue != null && _latestValue!.isPlaying) {
            if (_displayTapped) {
              changePlayerControlsNotVisible(true);
            } else {
              cancelAndRestartTimer();
            }
          } else {
            _onPlayPause();
            changePlayerControlsNotVisible(true);
          }
        } else {
          _onPlayPause();
        }
      },
    );
  }

  Widget _buildModernReplayButton(VideoPlayerController controller) {
    final bool isFinished = isVideoFinished(_latestValue);
    return _BetterPlayerModerBackgroundButton(
      size: 62,
      horizontalPadding: 16.0,
      child: _buildHitAreaClickableButton(
        icon: isFinished
            ? Icon(
                Icons.replay,
                size: 42,
                color: _controlsConfiguration.iconsColor,
              )
            : Icon(
                controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 42,
                color: _controlsConfiguration.iconsColor,
              ),
        onClicked: () {
          if (isFinished) {
            if (_latestValue != null && _latestValue!.isPlaying) {
              if (_displayTapped) {
                changePlayerControlsNotVisible(true);
              } else {
                cancelAndRestartTimer();
              }
            } else {
              _onPlayPause();
              changePlayerControlsNotVisible(true);
            }
          } else {
            _onPlayPause();
          }
        },
      ),
    );
  }

  Widget _buildModernChannelListButton(VideoPlayerController controller) {
    return _BetterPlayerModerBackgroundButton(
      size: 62,
      horizontalPadding: 24.0,
      child: _buildHitAreaClickableButton(
        icon: Icon(
          Icons.format_list_bulleted,
          size: 42,
          color: _controlsConfiguration.iconsColor,
        ),
        onClicked: () {
          widget.onChannelListPressed?.call();
        },
      ),
    );
  }

  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _betterPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          return BetterPlayerMaterialClickableWidget(
            onTap: () {
              _betterPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: EdgeInsets.only(bottom: _controlsConfiguration.controlBarHeight + 20, right: 24),
                decoration: BoxDecoration(
                  color: _controlsConfiguration.controlBarColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "${_betterPlayerController!.translations.controlsNextVideoIn} $time...",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget _buildVideoTitle() {
    final videoTitle = _betterPlayerController?.betterPlayerConfiguration.videoTitleText ?? '';

    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Padding(
        padding: EdgeInsets.only(
          right: 16,
          left: !_controlsConfiguration.enablePlayPause || _controlsConfiguration.useModernDesignControls ? 16 : 0,
        ),
        child: Text(
          videoTitle,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        ),
      ),
    );
  }

  Widget _buildAirplayButton() {
    final airplayConfig = _betterPlayerController?.betterPLayerAirplayConfiguration;

    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          height: airplayConfig?.airplayButtonSize,
          width: airplayConfig?.airplayButtonSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: Icon(
                    airplayConfig?.airplayIcon,
                    color: airplayConfig?.airplayButtonColor,
                    size: airplayConfig?.airplayButtonSize,
                  ),
                ),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: AirPlayRoutePickerView(
                    tintColor: Colors.transparent,
                    activeTintColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChromeCastButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        onShowChromeCastDevices();
      },
      child: Padding(
        padding: EdgeInsets.all(_controlsConfiguration.useModernDesignControls ? 0 : 8),
        child: Icon(
          Icons.cast,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );

    // return AnimatedOpacity(
    //   opacity: controlsNotVisible ? 0.0 : 1.0,
    //   duration: _controlsConfiguration.controlsHideTime,
    //   child: Padding(
    //     padding: const EdgeInsets.only(right: 12),
    //     child: SizedBox(
    //       height: airplayConfig?.airplayButtonSize,
    //       width: airplayConfig?.airplayButtonSize,
    //       child: IconButton(
    //         onPressed: () => onShowChromeCastDevices(),
    //         icon: Icon(
    //           Icons.cast,
    //           color: Colors.white,
    //           size: 24.0,
    //         ),
    //       ),
    //     ),
    //   ),
    // );
  }

  Widget _buildMuteButton(
    VideoPlayerController? controller,
  ) {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        cancelAndRestartTimer();
        if (VideoVolume.lastVolume == 0) {
          _betterPlayerController!.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = VideoVolume.lastVolume;
          _betterPlayerController!.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        child: ClipRect(
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              (_latestValue != null && VideoVolume.lastVolume > 0)
                  ? _controlsConfiguration.muteIcon
                  : _controlsConfiguration.unMuteIcon,
              color: _controlsConfiguration.iconsColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPause(VideoPlayerController controller) {
    return BetterPlayerMaterialClickableWidget(
      key: const Key("better_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          controller.value.isPlaying ? _controlsConfiguration.pauseIcon : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  Widget _buildRestart(VideoPlayerController controller) {
    return BetterPlayerMaterialClickableWidget(
      key: const Key("better_player_material_controls_restart_button"),
      onTap: () {
        betterPlayerController!.betterPlayerRestartTvConfiguration!.onRestartTvPressed?.call();
      },
      child: _BetterPlayerModerBackgroundButton(
        size: 48,
        child: Icon(
          Icons.history_rounded,
          size: 18,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  Widget _buildIsLiveButton(VideoPlayerController controller) {
    final isLivePosition = controller.value.duration != null
        ? controller.value.duration!.inMilliseconds - controller.value.position.inMilliseconds < 32000
        : true;
    return BetterPlayerMaterialClickableWidget(
      key: const Key("better_player_material_controls_is_live_button"),
      onTap: () => betterPlayerController!.betterPlayerRestartTvConfiguration!.onLiveTvPressed?.call(),
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.fiber_manual_record_rounded,
              color: betterPlayerController!.betterPlayerRestartTvConfiguration?.activeLiveColor,
              size: 6,
            ),
            SizedBox(width: 8),
            Text(
              betterPlayerController!.betterPlayerRestartTvConfiguration?.liveButtonText ?? '',
              style: TextStyle(
                color: betterPlayerController!.isLiveStream() ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosition() {
    final position = _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null ? _latestValue!.duration! : Duration.zero;

    return Padding(
      padding: _controlsConfiguration.enablePlayPause
          ? const EdgeInsets.only(right: 24)
          : const EdgeInsets.symmetric(horizontal: 22),
      child: RichText(
        text: TextSpan(
            text: BetterPlayerUtils.formatDuration(position),
            style: TextStyle(
              fontSize: 10.0,
              color: _controlsConfiguration.textColor,
              decoration: TextDecoration.none,
            ),
            children: <TextSpan>[
              TextSpan(
                text: ' / ${BetterPlayerUtils.formatDuration(duration)}',
                style: TextStyle(
                  fontSize: 10.0,
                  color: _controlsConfiguration.textColor,
                  decoration: TextDecoration.none,
                ),
              )
            ]),
      ),
    );
  }

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    changePlayerControlsNotVisible(false);
    _displayTapped = true;
  }

  Future<void> _initialize() async {
    _controller!.addListener(_updateState);

    _updateState();

    if ((_controller!.value.isPlaying) || _betterPlayerController!.betterPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription = _betterPlayerController!.controlsVisibilityStream.listen((state) {
      changePlayerControlsNotVisible(!state);
      if (!controlsNotVisible) {
        cancelAndRestartTimer();
      }
    });
  }

  void _onExpandCollapse() {
    changePlayerControlsNotVisible(true);
    _betterPlayerController!.toggleFullScreen();
    _showAfterExpandCollapseTimer = Timer(_controlsConfiguration.controlsHideTime, () {
      setState(() {
        cancelAndRestartTimer();
      });
    });
  }

  void _onPlayPause() {
    bool isFinished = false;

    if (_latestValue?.position != null && _latestValue?.duration != null) {
      isFinished = _latestValue!.position >= _latestValue!.duration!;
    }

    if (_controller!.value.isPlaying) {
      changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _betterPlayerController!.pause();
    } else {
      cancelAndRestartTimer();

      if (!_controller!.value.initialized) {
      } else {
        if (isFinished && !_betterPlayerController!.isLiveStream()) {
          _betterPlayerController!.seekTo(const Duration());
        }
        _betterPlayerController!.play();
        _betterPlayerController!.cancelNextVideoTimer();
      }
    }
  }

  void _startHideTimer() {
    if (_betterPlayerController!.controlsAlwaysVisible) {
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      changePlayerControlsNotVisible(true);
    });
  }

  void _updateState() {
    if (mounted) {
      if (!controlsNotVisible || isVideoFinished(_controller!.value) || _wasLoading || isLoading(_controller!.value)) {
        setState(() {
          _latestValue = _controller!.value;
          if (isVideoFinished(_latestValue) && _betterPlayerController?.isLiveStream() == false) {
            changePlayerControlsNotVisible(false);
          }
        });
      }
    }
  }

  Widget _buildProgressBar() {
    return Expanded(
      flex: 40,
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: BetterPlayerMaterialVideoProgressBar(
          _controller,
          _betterPlayerController,
          onDragStart: () {
            _hideTimer?.cancel();
          },
          onDragEnd: () {
            _startHideTimer();
          },
          onTapDown: () {
            cancelAndRestartTimer();
          },
          colors: BetterPlayerProgressColors(
            playedColor: _controlsConfiguration.progressBarPlayedColor,
            handleColor: _controlsConfiguration.progressBarHandleColor,
            bufferedColor: _controlsConfiguration.progressBarBufferedColor,
            backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
          ),
        ),
      ),
    );
  }

  void _onPlayerHide() {
    _betterPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  Widget? _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return Container(
        color: _controlsConfiguration.controlBarColor,
        child: _controlsConfiguration.loadingWidget,
      );
    }

    return CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(_controlsConfiguration.loadingColor),
    );
  }

  Widget _buildExitButton() => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _betterPlayerController!.postEvent(BetterPlayerEvent(BetterPlayerEventType.close)),
        child: Padding(
          padding: EdgeInsets.only(
              left: _controlsConfiguration.useModernDesignControls ? 24.0 : 16.0,
              right: _controlsConfiguration.useModernDesignControls ? 0.0 : 16.0,
              top: 8.0,
              bottom: 8.0),
          child: Center(child: Icon(_controlsConfiguration.exitIcon)),
        ),
      );

  Widget _buildCloseFullScreenArrow() => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _betterPlayerController!.exitFullScreen(),
        child: Padding(
          padding: EdgeInsets.only(left: 24.0, top: 8.0, bottom: 8.0),
          child: Center(child: Icon(Icons.arrow_back)),
        ),
      );

  Widget _buildVideoImage() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: SizedBox(
              width: 58,
              child:
                  Image.network(_betterPlayerController!.betterPlayerConfiguration.videoImageUrl!, fit: BoxFit.cover)),
        ),
      );
}

class _BetterPlayerModerBackgroundButton extends StatelessWidget {
  final double size;
  final Widget child;
  final double horizontalPadding;
  final Color? color;

  const _BetterPlayerModerBackgroundButton({
    required this.child,
    required this.size,
    this.horizontalPadding = 0.0,
    this.color,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Container(
        width: size,
        height: size,
        child: Center(child: child),
        decoration: BoxDecoration(
          color: color ?? Colors.black.withOpacity(0.8),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

enum AppState { idle, connected, mediaLoaded, error }
