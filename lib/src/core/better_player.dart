import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/configuration/better_player_controller_event.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/core/better_player_with_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'better_player_controller.dart';

///Widget which uses provided controller to render video player.
class BetterPlayer extends StatefulWidget {
  const BetterPlayer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  factory BetterPlayer.network(
    String url, {
    BetterPlayerConfiguration? betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource: BetterPlayerDataSource(BetterPlayerDataSourceType.network, url),
        ),
      );

  factory BetterPlayer.file(
    String url, {
    BetterPlayerConfiguration? betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource: BetterPlayerDataSource(BetterPlayerDataSourceType.file, url),
        ),
      );

  final BetterPlayerController controller;

  @override
  _BetterPlayerState createState() {
    return _BetterPlayerState();
  }
}

class _BetterPlayerState extends State<BetterPlayer> with WidgetsBindingObserver {
  BetterPlayerConfiguration get _betterPlayerConfiguration => widget.controller.betterPlayerConfiguration;

  BetterPlayerController get _controller => widget.controller;

  bool _isFullScreen = false;

  ///State of navigator on widget created
  late NavigatorState _navigatorState;

  ///Flag which determines if widget has initialized
  bool _initialized = false;

  ///Subscription for controller events
  StreamSubscription? _controllerEventSubscription;

  Timer? _durationCheckTimer;

  bool isVideoContent = true;

  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_initialized) {
      _startDurationCheckTimer();
    }
  }

  @override
  void didChangeDependencies() {
    if (!_initialized) {
      final navigator = Navigator.of(context);
      setState(() {
        _navigatorState = navigator;
      });
      _setup();
      _initialized = true;
    } else {}

    super.didChangeDependencies();
  }

  Future<void> _setup() async {
    _controllerEventSubscription = widget.controller.controllerEventStream.listen(onControllerEvent);

    //Default locale
    var locale = const Locale("en", "US");
    try {
      if (mounted) {
        final contextLocale = Localizations.localeOf(context);
        locale = contextLocale;
      }
    } catch (exception) {
      BetterPlayerUtils.log(exception.toString());
    }
    widget.controller.setupTranslations(locale);
  }

  @override
  void dispose() {
    _durationCheckTimer?.cancel();

    ///If somehow BetterPlayer widget has been disposed from widget tree and
    ///full screen is on, then full screen route must be pop and return to normal
    ///state.
    if (_isFullScreen) {
      _navigatorState.maybePop();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
      SystemChrome.setPreferredOrientations(_betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
    }

    WidgetsBinding.instance.removeObserver(this);
    _controllerEventSubscription?.cancel();
    widget.controller.dispose();
    VisibilityDetectorController.instance.forget(Key("${widget.controller.hashCode}_key"));
    isVideoContent = true;

    super.dispose();
  }

  @override
  void didUpdateWidget(BetterPlayer oldWidget) {
    if (oldWidget.controller != widget.controller) {
      _controllerEventSubscription?.cancel();
      _controllerEventSubscription = widget.controller.controllerEventStream.listen(onControllerEvent);
    }
    if (_lastUrl != null && _lastUrl != _controller.betterPlayerDataSource?.url) {
      _startDurationCheckTimer();
    }
    super.didUpdateWidget(oldWidget);
  }

  void onControllerEvent(BetterPlayerControllerEvent event) {
    switch (event) {
      case BetterPlayerControllerEvent.openFullscreen:
        widget.controller.postEvent(BetterPlayerEvent(BetterPlayerEventType.openFullscreen));
        onFullScreenChanged();

        break;
      case BetterPlayerControllerEvent.hideFullscreen:
        widget.controller.postEvent(BetterPlayerEvent(BetterPlayerEventType.hideFullscreen));
        onFullScreenChanged();
        break;
      default:
        setState(() {});
        break;
    }
  }

  Future<void> _startDurationCheckTimer() async {
    if (_lastUrl == _controller.betterPlayerDataSource?.url) {
      return Future.value();
    }
    _durationCheckTimer?.cancel();
    isVideoContent = true;
    _lastUrl = _controller.betterPlayerDataSource?.url;
    _durationCheckTimer = Timer(const Duration(seconds: 5), () async {
      final duration = widget.controller.videoPlayerController?.value.duration;
      final isBuffered = widget.controller.videoPlayerController?.value.buffered.isEmpty ?? false;
      if ((duration == null || isBuffered) && mounted) {
        _isFullScreen = false;
        isVideoContent = false;
        widget.controller.exitFullScreen();
        await SystemChrome.setPreferredOrientations(_betterPlayerConfiguration.deviceOrientationsOnFullScreen);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
        await SystemChrome.setPreferredOrientations(_betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
      }
    });
  }

  // ignore: avoid_void_async
  Future<void> onFullScreenChanged() async {
    final controller = widget.controller;
    if (controller.isFullScreen && !_isFullScreen) {
      _isFullScreen = true;
      controller.postEvent(BetterPlayerEvent(BetterPlayerEventType.openFullscreen));
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen) {
      Navigator.of(context, rootNavigator: true).pop();
      _isFullScreen = false;
      controller.postEvent(BetterPlayerEvent(BetterPlayerEventType.hideFullscreen));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BetterPlayerControllerProvider(
      controller: widget.controller,
      child: Stack(children: [
        _buildPlayer(),
        if (!isVideoContent)
          widget.controller.betterPlayerTvChannelListConfiguration?.onErrorWidget ?? SizedBox.shrink(),
      ]),
    );
  }

  Widget _buildFullScreenVideo(
      BuildContext context, Animation<double> animation, BetterPlayerControllerProvider controllerProvider) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onVerticalDragEnd: (details) => widget.controller.fullscreenOnGesture != null ? widget.controller.fullscreenOnGesture!(widget.controller, details.velocity.pixelsPerSecond.dy > 0) : null,
        child: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: controllerProvider,
        ),
      ),
    );
  }

  AnimatedWidget _defaultRoutePageBuilder(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, BetterPlayerControllerProvider controllerProvider) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = BetterPlayerControllerProvider(controller: widget.controller, child: _buildPlayer());

    final routePageBuilder = _betterPlayerConfiguration.routePageBuilder;
    if (routePageBuilder == null) {
      return _defaultRoutePageBuilder(context, animation, secondaryAnimation, controllerProvider);
    }

    return routePageBuilder(context, animation, secondaryAnimation, controllerProvider);
  }

  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final TransitionRoute<void> route = PageRouteBuilder<void>(
      settings: const RouteSettings(),
      pageBuilder: _fullScreenRoutePageBuilder,
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_betterPlayerConfiguration.autoDetectFullscreenDeviceOrientation == true) {
      final aspectRatio = widget.controller.videoPlayerController?.value.aspectRatio ?? 1.0;
      List<DeviceOrientation> deviceOrientations;
      if (aspectRatio < 1.0) {
        deviceOrientations = [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
      } else {
        deviceOrientations = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
      }
      await SystemChrome.setPreferredOrientations(deviceOrientations);
    } else {
      if (widget.controller.wasInPipMode) {
        if (widget.controller.isFullScreen) {
          await SystemChrome.setPreferredOrientations(
            widget.controller.betterPlayerConfiguration.deviceOrientationsAfterFullScreen,
          );
        } else {
          await SystemChrome.setPreferredOrientations(
            widget.controller.betterPlayerConfiguration.deviceOrientationsOnFullScreen,
          );
        }
      } else {
        await SystemChrome.setPreferredOrientations(
          widget.controller.betterPlayerConfiguration.deviceOrientationsOnFullScreen,
        );
      }
    }

    await Navigator.of(context, rootNavigator: true).push(route);
    _isFullScreen = false;
    widget.controller.exitFullScreen();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
    await SystemChrome.setPreferredOrientations(_betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
  }

  Widget _buildPlayer() {
    return VisibilityDetector(
      key: Key("${widget.controller.hashCode}_key"),
      onVisibilityChanged: (VisibilityInfo info) => widget.controller.onPlayerVisibilityChanged(info.visibleFraction),
      child: BetterPlayerWithControls(
        controller: widget.controller,
      ),
    );
  }

  bool isInInactiveState = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    widget.controller.setAppLifecycleState(state);
  }
}

///Page route builder used in fullscreen mode.
typedef BetterPlayerRoutePageBuilder = Widget Function(BuildContext context, Animation<double> animation,
    Animation<double> secondaryAnimation, BetterPlayerControllerProvider controllerProvider);
