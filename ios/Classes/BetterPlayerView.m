// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "BetterPlayerView.h"
#import <AVFoundation/AVFoundation.h>

@interface BetterPlayerView ()
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) id timeObserver;
@end

// BetterPlayerView.m
@implementation BetterPlayerView

(Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayer *)player {
    return self.playerLayer.player;
}

- (void)setPlayer:(AVPlayer *)player {
    self.playerLayer.player = player;
}

// Override UIView method
+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayerLayer *)playerLayer {
    return (AVPlayerLayer *)self.layer;
}

#pragma mark - Setup UI

- (void)setupControls {
    [self setupSlider];
    [self setupPlayPauseButton];
}

- (void)setupSlider {
    self.progressSlider = [[UISlider alloc] init];
    self.progressSlider.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    // Kolory
    self.progressSlider.minimumTrackTintColor = [UIColor whiteColor];
    self.progressSlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    self.progressSlider.thumbTintColor = [UIColor whiteColor];

    [self.progressSlider addTarget:self
                            action:@selector(sliderValueChanged:)
                  forControlEvents:UIControlEventValueChanged];

    [self addSubview:self.progressSlider];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat padding = 20.0;       // odstęp po bokach
    CGFloat buttonWidth = 70.0;   // miejsce na play/pause
    CGFloat sliderHeight = 30.0;
    CGFloat sliderY = self.bounds.size.height - 40;

    self.progressSlider.frame = CGRectMake(
        padding + buttonWidth,
        sliderY,
        self.bounds.size.width - 2 * padding - buttonWidth,
        sliderHeight
    );

    self.playPauseButton.frame = CGRectMake(
        padding,
        sliderY - 10,
        buttonWidth,
        buttonWidth
    );
}

- (void)setupPlayPauseButton {
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playPauseButton setTitle:@"⏯" forState:UIControlStateNormal];

    // Kolor tekstu
    [self.playPauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    [self.playPauseButton addTarget:self
                             action:@selector(togglePlayPause)
                   forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.playPauseButton];
}

#pragma mark - Play/Pause

- (void)playPauseTapped {
    if (self.player.rate == 0) {
        [self.player play];
        [self.playPauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
    } else {
        [self.player pause];
        [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    }
}

#pragma mark - Slider / DVR Handling

- (void)updateDVRSlider {
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;

    NSArray *seekableRanges = item.seekableTimeRanges;
    if (seekableRanges.count == 0) return;

    CMTimeRange range = [[seekableRanges lastObject] CMTimeRangeValue];
    Float64 startSeconds = CMTimeGetSeconds(range.start);
    Float64 endSeconds   = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
    Float64 currentSeconds = CMTimeGetSeconds(item.currentTime);

    // Start w połowie DVR window
    if (!self.progressSlider.isTracking && self.progressSlider.maximumValue == 0) {
        currentSeconds = startSeconds + (endSeconds - startSeconds) / 2.0;
        [self.player seekToTime:CMTimeMakeWithSeconds(currentSeconds, NSEC_PER_SEC)
                toleranceBefore:kCMTimeZero
                 toleranceAfter:kCMTimeZero];
    }

    Float64 duration = endSeconds - startSeconds;
    Float64 relativePosition = currentSeconds - startSeconds;

    self.progressSlider.minimumValue = 0;
    self.progressSlider.maximumValue = (float)duration;
    self.progressSlider.value = (float)relativePosition;
}

- (void)sliderValueChanged:(UISlider *)sender {
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;

    NSArray *seekableRanges = item.seekableTimeRanges;
    if (seekableRanges.count == 0) return;

    CMTimeRange range = [[seekableRanges lastObject] CMTimeRangeValue];
    Float64 start = CMTimeGetSeconds(range.start);

    Float64 newSeconds = start + sender.value;
    CMTime newTime = CMTimeMakeWithSeconds(newSeconds, NSEC_PER_SEC);

    [self.player seekToTime:newTime
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero];
}

@end
