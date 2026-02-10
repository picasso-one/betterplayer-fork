// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "BetterPlayer.h"
#import <better_player/better_player-Swift.h>

static void* timeRangeContext;
static void* statusContext;
static void* playbackLikelyToKeepUpContext;
static void* playbackBufferEmptyContext;
static void* playbackBufferFullContext;
static void* presentationSizeContext;

#if TARGET_OS_IOS
void (^__strong _Nonnull _restoreUserInterfaceForPIPStopCompletionHandler)(BOOL);
API_AVAILABLE(ios(9.0))
AVPictureInPictureController *_pipController;
#endif

@interface BetterPlayer ()
- (void)onReadyToPlay;
- (void)onAppDidBecomeActive:(NSNotification *)notification;
@end

static BOOL gWasPlayingBeforePip = NO;
static BOOL gWasFullscreenBeforePip = NO;

@implementation BetterPlayer {
    BOOL _wasPlayingBeforePip;
    BOOL _wasFullscreenBeforePip;
    CGRect screenBounds;
    BOOL wasFullscreen;
    AVPlayerLayer *_playerLayer;
    CGRect _lastPlayerLayerFrame;
}

#pragma mark - Init
- (instancetype)initWithFrame:(CGRect)frame {
     self = [super init];
    NSAssert(self, @"super init cannot be nil");

    // inicjalizacja pól
    screenBounds = [UIScreen mainScreen].bounds;
    wasFullscreen = NO; 

    // przypisanie kontekstów KVO
    timeRangeContext = &timeRangeContext;
    statusContext = &statusContext;
    playbackLikelyToKeepUpContext = &playbackLikelyToKeepUpContext;
    playbackBufferEmptyContext = &playbackBufferEmptyContext;
    playbackBufferFullContext = &playbackBufferFullContext;
    presentationSizeContext = &presentationSizeContext;

    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _player = [[AVPlayer alloc] init];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    if (@available(iOS 10.0, *)) {
        _player.automaticallyWaitsToMinimizeStalling = false;
    }
    self._observersAdded = false;

    __weak typeof(self) weakSelf = self;
    self.timeObserver =
    [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(2, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        if (!weakSelf) {
            return;
        }

        int64_t currentDuration = [weakSelf duration];
        if ((currentDuration > 0) && (currentDuration != weakSelf.lastTimelineDuration)) {
            weakSelf.lastTimelineDuration = currentDuration;
            if (weakSelf.eventSink) {
                weakSelf.eventSink(@{
                    @"event": @"timelineChanged",
                    @"key": weakSelf.key ?: [NSNull null],
                    @"duration": @(currentDuration)
                });
            }
        }
    }];

    return self;
}

- (nonnull UIView *)view {
    BetterPlayerView *playerView = [[BetterPlayerView alloc] initWithFrame:CGRectZero];
    playerView.player = _player;
    return playerView;
}

#pragma mark - Observers
- (void)addObservers:(AVPlayerItem*)item {
    if (!self._observersAdded){
        [_player addObserver:self forKeyPath:@"rate" options:0 context:nil];
        [item addObserver:self forKeyPath:@"loadedTimeRanges" options:0 context:timeRangeContext];
        [item addObserver:self forKeyPath:@"status" options:0 context:statusContext];
        [item addObserver:self forKeyPath:@"presentationSize" options:0 context:presentationSizeContext];
        [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:playbackLikelyToKeepUpContext];
        [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:0 context:playbackBufferEmptyContext];
        [item addObserver:self forKeyPath:@"playbackBufferFull" options:0 context:playbackBufferFullContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemDidPlayToEndTime:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:item];
        self._observersAdded = true;
    }
}

- (void)removeObservers{
    @try {
        if (self._observersAdded){
            [_player removeObserver:self forKeyPath:@"rate" context:nil];
            [[_player currentItem] removeObserver:self forKeyPath:@"status" context:statusContext];
            [[_player currentItem] removeObserver:self forKeyPath:@"presentationSize" context:presentationSizeContext];
            [[_player currentItem] removeObserver:self forKeyPath:@"loadedTimeRanges" context:timeRangeContext];
            [[_player currentItem] removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:playbackLikelyToKeepUpContext];
            [[_player currentItem] removeObserver:self forKeyPath:@"playbackBufferEmpty" context:playbackBufferEmptyContext];
            [[_player currentItem] removeObserver:self forKeyPath:@"playbackBufferFull" context:playbackBufferFullContext];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
            self._observersAdded = false;
        }
    } @catch (NSException *exception) {
        NSLog(@"Exception occurred while removing observers: %@", exception);
    }
}

#pragma mark - Item End
- (void)itemDidPlayToEndTime:(NSNotification*)notification {
    if (_isLooping) {
        AVPlayerItem* p = [notification object];
        [p seekToTime:kCMTimeZero completionHandler:nil];
    } else {
        if (_eventSink) {
            _eventSink(@{@"event" : @"completed", @"key" : _key});
            [ self removeObservers];
        }
    }
}

#pragma mark - Video Composition helpers
static inline CGFloat radiansToDegrees(CGFloat radians) {
    CGFloat degrees = GLKMathRadiansToDegrees((float)radians);
    if (degrees < 0) {
        return degrees + 360;
    }
    return degrees;
};

- (AVMutableVideoComposition*)getVideoCompositionWithTransform:(CGAffineTransform)transform
                                                     withAsset:(AVAsset*)asset
                                                withVideoTrack:(AVAssetTrack*)videoTrack {
    AVMutableVideoCompositionInstruction* instruction =
    [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, [asset duration]);
    AVMutableVideoCompositionLayerInstruction* layerInstruction =
    [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [layerInstruction setTransform:_preferredTransform atTime:kCMTimeZero];

    AVMutableVideoComposition* videoComposition = [AVMutableVideoComposition videoComposition];
    instruction.layerInstructions = @[ layerInstruction ];
    videoComposition.instructions = @[ instruction ];

    CGFloat width = videoTrack.naturalSize.width;
    CGFloat height = videoTrack.naturalSize.height;
    NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)));
    if (rotationDegrees == 90 || rotationDegrees == 270) {
        width = videoTrack.naturalSize.height;
        height = videoTrack.naturalSize.width;
    }
    videoComposition.renderSize = CGSizeMake(width, height);

    float nominalFrameRate = videoTrack.nominalFrameRate;
    int fps = 30;
    if (nominalFrameRate > 0) {
        fps = (int) ceil(nominalFrameRate);
    }
    videoComposition.frameDuration = CMTimeMake(1, fps);
    
    return videoComposition;
}

- (CGAffineTransform)fixTransform:(AVAssetTrack*)videoTrack {
  CGAffineTransform transform = videoTrack.preferredTransform;
  NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(transform.b, transform.a)));
  if (rotationDegrees == 90) {
    transform.tx = videoTrack.naturalSize.height;
    transform.ty = 0;
  } else if (rotationDegrees == 180) {
    transform.tx = videoTrack.naturalSize.width;
    transform.ty = videoTrack.naturalSize.height;
  } else if (rotationDegrees == 270) {
    transform.tx = 0;
    transform.ty = videoTrack.naturalSize.width;
  }
  return transform;
}

#pragma mark - Data source setters
- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int) overriddenDuration{
    NSString* path = [[NSBundle mainBundle] pathForResource:asset ofType:nil];
    return [self setDataSourceURL:[NSURL fileURLWithPath:path] withKey:key withCertificateUrl:certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders: @{} withDrmHeaders: @{} withCache: false cacheKey:cacheKey cacheManager:cacheManager overriddenDuration:overriddenDuration videoExtension: nil];
}

- (void)seekBackward10 {
    AVPlayerItem *item = _player.currentItem;
    if (!item) {
        return;
    }

    NSArray *seekableRanges = item.seekableTimeRanges;
    if (seekableRanges.count == 0) {
        return;
    }

    CMTimeRange range = [seekableRanges.lastObject CMTimeRangeValue];
    CMTime current = item.currentTime;
    CMTime newTime = CMTimeSubtract(current, CMTimeMakeWithSeconds(10, NSEC_PER_SEC));

    if (CMTimeCompare(newTime, range.start) < 0) {
        newTime = range.start;
    }

    bool wasPlaying = _isPlaying;
    if (wasPlaying) {
        [_player pause];
    }

    [_player seekToTime:newTime
        toleranceBefore:kCMTimeZero
         toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {
        if (wasPlaying) {
            self->_player.rate = self->_playerRate;
        }
    }];
}

//MGR: pass both Headers and drmHeaders from flutter
- (void)setDataSourceURL:(NSURL*)url withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders:(NSDictionary*)headers withDrmHeaders:(NSDictionary*)drmHeaders withCache:(BOOL)useCache cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int) overriddenDuration videoExtension: (NSString*) videoExtension{
    _overriddenDuration = 0;
    if (headers == [NSNull null] || headers == NULL){
        headers = @{};
    }
    
    AVPlayerItem* item;
    if (useCache){
        if (cacheKey == [NSNull null]){
            cacheKey = nil;
        }
        if (videoExtension == [NSNull null]){
            videoExtension = nil;
        }
        
        item = [cacheManager getCachingPlayerItemForNormalPlayback:url cacheKey:cacheKey videoExtension: videoExtension headers:headers];
    } else {
        AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url
                                                options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
        if (certificateUrl && certificateUrl != [NSNull null] && [certificateUrl length] > 0) {
            NSURL * certificateNSURL = [[NSURL alloc] initWithString: certificateUrl];
            NSURL * licenseNSURL = [[NSURL alloc] initWithString: licenseUrl];
            //MGR: pass drmHeaders to loader
            _loaderDelegate = [[BetterPlayerEzDrmAssetsLoaderDelegate alloc] init:certificateNSURL withLicenseURL:licenseNSURL withDrmHeaders: drmHeaders];
            dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, -1);
            dispatch_queue_t streamQueue = dispatch_queue_create("streamQueue", qos);
            [asset.resourceLoader setDelegate:_loaderDelegate queue:streamQueue];
        }
        item = [AVPlayerItem playerItemWithAsset:asset];
    }

    if (@available(iOS 10.0, *) && overriddenDuration > 0) {
        _overriddenDuration = overriddenDuration;
    }
    return [self setDataSourcePlayerItem:item withKey:key];
}

- (void)setDataSourcePlayerItem:(AVPlayerItem*)item withKey:(NSString*)key{
    _key = key;
    _stalledCount = 0;
    _isStalledCheckStarted = false;
    _playerRate = 1;
    [_player replaceCurrentItemWithPlayerItem:item];

    AVAsset* asset = [item asset];
    void (^assetCompletionHandler)(void) = ^{
        if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
            NSArray* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            if ([tracks count] > 0) {
                AVAssetTrack* videoTrack = tracks[0];
                void (^trackCompletionHandler)(void) = ^{
                    if (self->_disposed) return;
                    if ([videoTrack statusOfValueForKey:@"preferredTransform"
                                                  error:nil] == AVKeyValueStatusLoaded) {
                        // Rotate the video by using a videoComposition and the preferredTransform
                        self->_preferredTransform = [self fixTransform:videoTrack];
                        // Note:
                        // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
                        // Video composition can only be used with file-based media and is not supported for
                        // use with media served using HTTP Live Streaming.
                        AVMutableVideoComposition* videoComposition =
                        [self getVideoCompositionWithTransform:self->_preferredTransform
                                                     withAsset:asset
                                                withVideoTrack:videoTrack];
                        item.videoComposition = videoComposition;
                    }
                };
                [videoTrack loadValuesAsynchronouslyForKeys:@[ @"preferredTransform" ]
                                          completionHandler:trackCompletionHandler];
            }
        }
    };

    [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ] completionHandler:assetCompletionHandler];
    [self addObservers:item];
}

#pragma mark - Stalled handling

-(void)handleStalled {
    if (_isStalledCheckStarted){
        return;
    }
   _isStalledCheckStarted = true;
    [self startStalledCheck];
}

-(void)startStalledCheck{
    if (_player.currentItem.playbackLikelyToKeepUp ||
        [self availableDuration] - CMTimeGetSeconds(_player.currentItem.currentTime) > 10.0) {
        [self play];
    } else {
        _stalledCount++;
        if (_stalledCount > 60){
            if (_eventSink != nil) {
                _eventSink([FlutterError
                        errorWithCode:@"VideoError"
                        message:@"Failed to load video: playback stalled"
                        details:nil]);
            }
            return;
        }
        [self performSelector:@selector(startStalledCheck) withObject:nil afterDelay:1];
    }
}

- (NSTimeInterval) availableDuration
{
    NSArray *loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
    if (loadedTimeRanges.count > 0){
        CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
        Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
        Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
        NSTimeInterval result = startSeconds + durationSeconds;
        return result;
    } else {
        return 0;
    }
}

#pragma mark - KVO observe

- (void)observeValueForKeyPath:(NSString*)path
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {

    if ([path isEqualToString:@"rate"]) {
        if (@available(iOS 10.0, *)) {
            if (_pipController.pictureInPictureActive == true){
                if (_lastAvPlayerTimeControlStatus != [NSNull null] &&
                    _lastAvPlayerTimeControlStatus == _player.timeControlStatus){
                    return;
                }

                if (_player.timeControlStatus == AVPlayerTimeControlStatusPaused){
                    _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                    if (_eventSink != nil) {
                        _eventSink(@{@"event" : @"pause"});
                    }
                    return;
                }
                if (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying){
                    _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                    if (_eventSink != nil) {
                        _eventSink(@{@"event" : @"play"});
                    }
                }
            }
        }

        if (_player.rate == 0 &&
            CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, >, kCMTimeZero) &&
            CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, <, _player.currentItem.duration) &&
            _isPlaying) {
            [self handleStalled];
        }
    }

    // --- DVR / seekable ranges ---
    if (context == timeRangeContext) {
        AVPlayerItem *item = (AVPlayerItem*)object;
        NSArray *seekableRanges = item.seekableTimeRanges;

        if (seekableRanges.count > 0) {

            // POPRAWKA: najpierw pobieramy dvrRange
            CMTimeRange dvrRange = [seekableRanges.lastObject CMTimeRangeValue];

            Float64 dvrStart = CMTimeGetSeconds(dvrRange.start);
            Float64 dvrEnd   = CMTimeGetSeconds(CMTimeRangeGetEnd(dvrRange));

            if (dvrEnd > dvrStart) {
                NSLog(@"[DVR][loadedTimeRanges] start=%lldms end=%lldms",
                      (int64_t)(dvrStart * 1000),
                      (int64_t)(dvrEnd * 1000));

                if (_eventSink != nil) {
                    _eventSink(@{
                        @"event": @"dvrWindow",
                        @"dvrStart": @((int64_t)(dvrStart * 1000)),
                        @"dvrEnd": @((int64_t)(dvrEnd * 1000)),
                        @"key": _key
                    });
                }
            }

            // BUFFERING UPDATE
            if (_eventSink != nil) {
                NSMutableArray<NSArray<NSNumber*>*>* values = [[NSMutableArray alloc] init];

                for (NSValue* rangeValue in [object loadedTimeRanges]) {
                    CMTimeRange range = [rangeValue CMTimeRangeValue];
                    int64_t start = [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.start)];
                    int64_t end = start + [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.duration)];

                    if (!CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime)) {
                        int64_t endTime = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.forwardPlaybackEndTime)];
                        if (end > endTime){
                            end = endTime;
                        }
                    }

                    [values addObject:@[ @(start), @(end) ]];
                }

                _eventSink(@{
                    @"event" : @"bufferingUpdate",
                    @"values" : values,
                    @"key" : _key,
                    @"dvrStart": @((int64_t)(dvrStart * 1000)),
                    @"dvrEnd": @((int64_t)(dvrEnd * 1000))
                });
            }
        }
    }

    else if (context == presentationSizeContext){
        [self onReadyToPlay];
    }

    else if (context == statusContext) {
        AVPlayerItem* item = (AVPlayerItem*)object;
        switch (item.status) {
            case AVPlayerItemStatusFailed:
                NSLog(@"[BetterPlayer] Failed to load video: %@", item.error.debugDescription);
                if (_eventSink != nil) {
                    _eventSink([FlutterError
                                errorWithCode:@"VideoError"
                                message:[@"Failed to load video: "
                                         stringByAppendingString:[item.error localizedDescription]]
                                details:nil]);
                }
                break;
            case AVPlayerItemStatusUnknown:
                break;
            case AVPlayerItemStatusReadyToPlay:
                [self onReadyToPlay];
                break;
        }
    }

    else if (context == playbackLikelyToKeepUpContext) {
        if ([[_player currentItem] isPlaybackLikelyToKeepUp]) {
            [self updatePlayingState];
            if (_eventSink != nil) {
                _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
            }
        }
    } else if (context == playbackBufferEmptyContext) {
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"bufferingStart", @"key" : _key});
        }
    } else if (context == playbackBufferFullContext) {
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
        }
    }
}



- (void)emitDvrWindow {
   AVPlayerItem *item = self.player.currentItem;
    if (!item) return;

    NSArray *ranges = item.seekableTimeRanges;
    if (ranges.count == 0) return;

    CMTimeRange range = [ranges.lastObject CMTimeRangeValue];
    Float64 start = CMTimeGetSeconds(range.start);
    Float64 end   = CMTimeGetSeconds(CMTimeRangeGetEnd(range));

    if (_eventSink) {
        _eventSink(@{
            @"event": @"dvrWindow",
            @"dvrStart": @((int64_t)(start * 1000)),
            @"dvrEnd":   @((int64_t)(end * 1000)),
        });
    }
}

#pragma mark - Playback state

- (void)updatePlayingState {
    if (!_isInitialized || !_key) {
        return;
    }
    if (!self._observersAdded){
        [self addObservers:[_player currentItem]];
    }

    if (_isPlaying) {
        if (@available(iOS 10.0, *)) {
            [_player playImmediatelyAtRate:1.0];
            _player.rate = _playerRate;
        } else {
            [_player play];
            _player.rate = _playerRate;
        }
    } else {
        [_player pause];
    }
}

#pragma mark - onReadyToPlay (public event send)

- (void)onReadyToPlay {
    if (_eventSink && !_isInitialized && _key) {
        if (!_player.currentItem) {
            return;
        }
        if (_player.status != AVPlayerStatusReadyToPlay) {
            return;
        }

        CGSize size = [_player currentItem].presentationSize;
        CGFloat width = size.width;
        CGFloat height = size.height;

        AVAsset *asset = _player.currentItem.asset;
        bool onlyAudio =  [[asset tracksWithMediaType:AVMediaTypeVideo] count] == 0;

        // The player has not yet initialized.
        if (!onlyAudio && height == CGSizeZero.height && width == CGSizeZero.width) {
            return;
        }
        const BOOL isLive = CMTIME_IS_INDEFINITE([_player currentItem].duration);
        // The player may be initialized but still needs to determine the duration.
        if (isLive == false && [self duration] == 0) {
            return;
        }

        //Fix from https://github.com/flutter/flutter/issues/66413
        AVPlayerItemTrack *track = [self.player currentItem].tracks.firstObject;
        CGSize naturalSize = track.assetTrack.naturalSize;
        CGAffineTransform prefTrans = track.assetTrack.preferredTransform;
        CGSize realSize = CGSizeApplyAffineTransform(naturalSize, prefTrans);

       int64_t duration = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.asset.duration)];
        if (_overriddenDuration > 0 && duration > _overriddenDuration && !CMTIME_IS_INDEFINITE(_player.currentItem.duration)) {
            _player.currentItem.forwardPlaybackEndTime = CMTimeMake(_overriddenDuration/1000, 1);
        }

        _isInitialized = true;
        [self updatePlayingState];
        _eventSink(@{
            @"event" : @"initialized",
            @"duration" : @([self duration]),
            @"width" : @(fabs(realSize.width) ? : width),
            @"height" : @(fabs(realSize.height) ? : height),
            @"key" : _key
        });
    }
}

#pragma mark - Play/pause/position/duration

- (void)play {
    _stalledCount = 0;
    _isStalledCheckStarted = false;
    _isPlaying = true;
    [self updatePlayingState];
}

- (void)pause {
    _isPlaying = false;
    [self updatePlayingState];
}

- (int64_t)position {
    AVPlayerItem *item = _player.currentItem;
    if (!item) return 0;

    NSArray *ranges = item.seekableTimeRanges;
    if (ranges.count == 0) {
        // brak DVR → zwracamy absolutny czas
        Float64 current = CMTimeGetSeconds(_player.currentTime);
        return (int64_t)(current * 1000);
    }

    // DVR window
    CMTimeRange range = [ranges.lastObject CMTimeRangeValue];
    Float64 dvrStart = CMTimeGetSeconds(range.start);
    Float64 dvrEnd   = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
    Float64 current  = CMTimeGetSeconds(_player.currentTime);

    // OFFSET = current - dvrStart
    Float64 offset = current - dvrStart;

    if (offset < 0) offset = 0;
    if (offset > (dvrEnd - dvrStart)) offset = (dvrEnd - dvrStart);

    return (int64_t)(offset * 1000);
}


- (int64_t)absolutePosition {
    return [BetterPlayerTimeUtils FLTNSTimeIntervalToMillis:([[[_player currentItem] currentDate] timeIntervalSince1970])];
}

- (int64_t)duration {
    AVPlayerItem *item = _player.currentItem;
    if (!item) {
        return 0;
    }

    CMTime time;
    if (@available(iOS 13, *)) {
        time = item.duration;
    } else {
        time = item.asset.duration;
    }

    if (!CMTIME_IS_INVALID(item.forwardPlaybackEndTime)) {
        time = item.forwardPlaybackEndTime;
    }

    Float64 seconds = CMTimeGetSeconds(time);
    if (CMTIME_IS_INDEFINITE(time) || isnan(seconds) || seconds <= 0) {
        NSArray *ranges = item.seekableTimeRanges;
        if (ranges.count > 0) {
            CMTimeRange range = [[ranges lastObject] CMTimeRangeValue];
            Float64 dvrSeconds = CMTimeGetSeconds(range.duration);
            return (int64_t)(dvrSeconds * 1000.0);
        }

        return 0;
    }

    return [BetterPlayerTimeUtils FLTCMTimeToMillis:time];
}

#pragma mark - Seek

- (void)seekTo:(int)location {
    BOOL wasPlaying = _isPlaying;
    if (wasPlaying) {
        [_player pause];
    }

    AVPlayerItem *item = _player.currentItem;
    if (!item) {
        return;
    }

    NSArray *seekableRanges = item.seekableTimeRanges;
    if (seekableRanges.count == 0) {
        return;
    }

    // aktualne DVR okno
    CMTimeRange range = [seekableRanges.lastObject CMTimeRangeValue];
    Float64 dvrStart = CMTimeGetSeconds(range.start);
    Float64 dvrEnd   = CMTimeGetSeconds(CMTimeRangeGetEnd(range));

    NSLog(@"DVR Window: start = %f, end = %f", dvrStart, dvrEnd);

    // oblicz docelowy czas (offset → absolutny czas)
    Float64 offsetSeconds = location / 1000.0;
    Float64 targetSeconds = dvrStart + offsetSeconds;

    // clamp
    if (targetSeconds < dvrStart) targetSeconds = dvrStart;
    if (targetSeconds > dvrEnd)   targetSeconds = dvrEnd;

    CMTime seekTime = CMTimeMakeWithSeconds(targetSeconds, NSEC_PER_SEC);

    [_player seekToTime:seekTime
        toleranceBefore:kCMTimeZero
         toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {

        if (wasPlaying) {
            self->_player.rate = self->_playerRate;
        }

        if (self->_eventSink) {

            // OFFSET dla Fluttera
            int64_t offsetMs = (int64_t)((targetSeconds - dvrStart) * 1000);

            int dvrStartMs = (int)(dvrStart * 1000);
            int dvrEndMs   = (int)(dvrEnd * 1000);

            self->_eventSink(@{
                @"event": @"position",
                @"position": @(offsetMs),
                @"dvrStart": @(dvrStartMs),
                @"dvrEnd": @(dvrEndMs),
                @"key": self->_key
            });
        }
    }];
}


#pragma mark - Loop/volume/speed/track parameters

- (void)setIsLooping:(bool)isLooping {
    _isLooping = isLooping;
}

- (void)setVolume:(double)volume {
    _player.volume = (float)((volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume));
}

- (void)setSpeed:(double)speed result:(FlutterResult)result {
    if (speed <= 0.0 || speed > 2.0) {
        result([FlutterError errorWithCode:@"unsupported_speed"
                                   message:@"Speed must be > 0.0 and <= 2.0"
                                   details:nil]);
        return;
    }

    _playerRate = speed;
    if (_isPlaying) {
        _player.rate = _playerRate;
    }

    result(nil);
}

- (void)setTrackParameters:(int) width: (int) height: (int)bitrate {
    _player.currentItem.preferredPeakBitRate = bitrate;
    if (@available(iOS 11.0, *)) {
        if (width == 0 && height == 0){
            _player.currentItem.preferredMaximumResolution = CGSizeZero;
        } else {
            _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height);
        }
    }
}

#pragma mark - Picture in Picture (PiP)

- (void)setPictureInPicture:(BOOL)pictureInPicture {
    self._pictureInPicture = pictureInPicture;
    if (@available(iOS 9.0, *)) {
        if (!_pipController) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self._pictureInPicture && ![_pipController isPictureInPictureActive]) {
                // 📸 Zapamiętaj stan PRZED PiP
                if (self->_playerLayer) {
                    self->_lastPlayerLayerFrame = self->_playerLayer.frame;

                    CGRect screenBounds = [UIScreen mainScreen].bounds;
                    CGRect frame = self->_playerLayer.frame;
                    CGFloat coverage = (frame.size.width * frame.size.height) / (screenBounds.size.width * screenBounds.size.height);
                    self->_wasFullscreenBeforePip = (coverage > 0.95);
self->_wasPlayingBeforePip = self->_isPlaying;

// zapamiętaj też globalnie
gWasFullscreenBeforePip = self->_wasFullscreenBeforePip;
gWasPlayingBeforePip = self->_wasPlayingBeforePip;

NSLog(@"[BetterPlayer] Saving before PiP. wasPlayingBeforePip=%@ wasFullscreenBeforePip=%@",
      gWasPlayingBeforePip ? @"YES" : @"NO",
      gWasFullscreenBeforePip ? @"YES" : @"NO");

                    NSLog(@"[BetterPlayer] Saving before PiP. frame=%@ screen=%@ coverage=%.2f wasFullscreenBeforePip=%@",
                          NSStringFromCGRect(frame),
                          NSStringFromCGRect(screenBounds),
                          coverage,
                          self->_wasFullscreenBeforePip ? @"YES" : @"NO");
                }

                [_pipController startPictureInPicture];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] performSelector:@selector(suspend)];
                });
            } else if (!self._pictureInPicture && [_pipController isPictureInPictureActive]) {
                [_pipController stopPictureInPicture];
            }
        });
    }
}

#if TARGET_OS_IOS
- (void)setRestoreUserInterfaceForPIPStopCompletionHandler:(BOOL)restore
{
    if (_restoreUserInterfaceForPIPStopCompletionHandler != NULL) {
        _restoreUserInterfaceForPIPStopCompletionHandler(restore);
        _restoreUserInterfaceForPIPStopCompletionHandler = NULL;
    }
}

- (void)setupPipController {
    if (@available(iOS 9.0, *)) {
        [[AVAudioSession sharedInstance] setActive: YES error: nil];
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
        if (!_pipController && _playerLayer && [AVPictureInPictureController isPictureInPictureSupported]) {
            _pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:_playerLayer];
            _pipController.delegate = self;
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onAppDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
}

- (void) enablePictureInPicture: (CGRect) frame{
    [self disablePictureInPicture];
    [self usePlayerLayer:frame];
}

- (void)usePlayerLayer: (CGRect) frame
{
    if( _player )
    {
        // Create new controller passing reference to the AVPlayerLayer
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
        UIViewController* vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        _playerLayer.frame = frame;
        _playerLayer.needsDisplayOnBoundsChange = YES;
        //  [_playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
        if (vc && vc.view) {
            [vc.view.layer addSublayer:_playerLayer];
            vc.view.layer.needsDisplayOnBoundsChange = YES;
        }

        if (@available(iOS 9.0, *)) {
            _pipController = NULL;
        }
        [self setupPipController];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setPictureInPicture:true];
        });
    }
}

- (void)disablePictureInPicture
{
    // poprawka: wyłącz PiP zamiast włączać
    [self setPictureInPicture:false];

    // Usuwamy warstwę tylko z hierarchii, ale nie niszczymy obiektu — zachowujemy ją,
    // żeby móc ją ponownie dodać, gdy aplikacja wróci z backgroundu.
    if (_playerLayer && _playerLayer.superlayer) {
        [_playerLayer removeFromSuperlayer];
    }

    if (_eventSink != nil) {
        _eventSink(@{@"event" : @"pipStop"});
    }
}
#endif

#if TARGET_OS_IOS
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(9.0)) {
     if (_playerLayer) {
        UIViewController *rootVC = UIApplication.sharedApplication.keyWindow.rootViewController;
        if (rootVC && rootVC.view) {
            if (_playerLayer.superlayer == nil) {
                [rootVC.view.layer addSublayer:_playerLayer];
            }

            if (_wasFullscreenBeforePip) {
                _playerLayer.frame = [UIScreen mainScreen].bounds;
            } else {
                _playerLayer.frame = _lastPlayerLayerFrame;
            }

            _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        }
    }

    if (_wasFullscreenBeforePip) {
    _playerLayer.frame = [UIScreen mainScreen].bounds;
} else {
    _playerLayer.frame = _lastPlayerLayerFrame;
}

    if (_wasPlayingBeforePip) {
        [self play];
    } else {
        [self pause];
    }

    if (_eventSink != nil) {
        _eventSink(@{@"event" : @"pipStop"});
    }
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController  API_AVAILABLE(ios(9.0)){
    //  NSLog(@"[BetterPlayer] Entered PiP. wasFullscreenBeforePip = %@", _wasFullscreenBeforePip ? @"YES" : @"NO");
    // _wasPlayingBeforePip = _isPlaying;
    // _lastPlayerLayerFrame = _playerLayer.frame; // zapamiętaj aktualny frame
    // _wasFullscreenBeforePip = CGRectEqualToRect(_playerLayer.frame, [UIScreen mainScreen].bounds);

    // if (_eventSink != nil) {
    //     _eventSink(@{@"event" : @"pipStart"});
    // }

    NSLog(@"[BetterPlayer] Entered PiP. wasFullscreenBeforePip = %@", _wasFullscreenBeforePip ? @"YES" : @"NO");
    if (_eventSink != nil) {
        _eventSink(@{@"event" : @"pipStart"});
    }
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController  API_AVAILABLE(ios(9.0)){

}

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {

}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {

}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController 
restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_playerLayer && _playerLayer.superlayer == nil) {
            UIViewController *rootVC = UIApplication.sharedApplication.keyWindow.rootViewController;
            if (rootVC && rootVC.view) {
                [rootVC.view.layer addSublayer:_playerLayer];
                _playerLayer.frame = rootVC.view.bounds;
                _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
            }
        }

        if (_wasPlayingBeforePip) {
            [self play];
        } else {
            [self pause];
        }

        if (completionHandler) {
            completionHandler(YES);
        }
    });
}
#endif

#pragma mark - App lifecycle helper

- (void)onAppDidBecomeActive:(NSNotification *)notification {
    NSLog(@"[BetterPlayer] onAppDidBecomeActive called. gWasFullscreenBeforePip=%@ gWasPlayingBeforePip=%@",
          gWasFullscreenBeforePip ? @"YES" : @"NO",
          gWasPlayingBeforePip ? @"YES" : @"NO");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
        UIViewController *rootVC = keyWindow.rootViewController;
        if (!rootVC || !rootVC.view || !_playerLayer) return;

        if (_playerLayer.superlayer == nil) {
            [rootVC.view.layer addSublayer:_playerLayer];
        }

        if (gWasFullscreenBeforePip) {
            NSLog(@"[BetterPlayer] Restoring fullscreen frame after PiP");
            _playerLayer.frame = [UIScreen mainScreen].bounds;
        } else {
            NSLog(@"[BetterPlayer] Restoring last frame after PiP: %@", NSStringFromCGRect(_lastPlayerLayerFrame));
            _playerLayer.frame = _lastPlayerLayerFrame;
        }

        _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [rootVC.view setNeedsLayout];
        [rootVC.view layoutIfNeeded];

        if (gWasPlayingBeforePip) {
            NSLog(@"[BetterPlayer] Resuming playback after PiP and foreground");
            [self play];
        }
    });
}

- (void) setAudioTrack:(NSString*) name index:(int) index{
    AVMediaSelectionGroup *audioSelectionGroup = [[[_player currentItem] asset] mediaSelectionGroupForMediaCharacteristic: AVMediaCharacteristicAudible];
    NSArray* options = audioSelectionGroup.options;

    for (int audioTrackIndex = 0; audioTrackIndex < [options count]; audioTrackIndex++) {
        AVMediaSelectionOption* option = [options objectAtIndex:audioTrackIndex];
        NSArray *metaDatas = [AVMetadataItem metadataItemsFromArray:option.commonMetadata withKey:@"title" keySpace:@"comn"];
        if (metaDatas.count > 0) {
            NSString *title = ((AVMetadataItem*)[metaDatas objectAtIndex:0]).stringValue;
            if ([name compare:title] == NSOrderedSame && audioTrackIndex == index ){
                [[_player currentItem] selectMediaOption:option inMediaSelectionGroup: audioSelectionGroup];
            }
        }
    }
}

- (void)setMixWithOthers:(bool)mixWithOthers {
  if (mixWithOthers) {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:nil];
  } else {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
  }
}

#pragma mark - Event channel housekeeping

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    // TODO: remove the line below when race condition is resolved:
    // ensures the 'initialized' event is sent when AVPlayerItemStatusReadyToPlay fires before _eventSink is set
    [self onReadyToPlay];
    [self emitDvrWindow];
    return nil;
}

- (void)disposeSansEventChannel {
    @try{
        [self clear];
    }
    @catch(NSException *exception) {
        NSLog(exception.debugDescription);
    }
}

- (void)dispose {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    
    [self pause];
    [self disposeSansEventChannel];
    if (_eventChannel) {
        [_eventChannel setStreamHandler:nil];
    }

    // Usuń obserwator powrotu aplikacji
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];

    [self disablePictureInPicture];
    [self setPictureInPicture:false];
    _disposed = true;
}

#pragma mark - Clear

- (void)clear {
    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _failedCount = 0;
    _key = nil;
    if (_player.currentItem == nil) {
        return;
    }
    [self removeObservers];
    AVAsset* asset = [_player.currentItem asset];
    [asset cancelLoading];
}

@end