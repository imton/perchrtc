//
//  PHViewController.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHViewController.h"

#import "PHEAGLRenderer.h"
#import "PHMediaConfiguration.h"
#import "PHQuartzVideoView.h"
#import "PHSampleBufferRenderer.h"
#import "PHSampleBufferView.h"

#import "RTCMediaStream+PHStreamConfiguration.h"
#import "RTCMediaStream.h"
#import "RTCVideoTrack.h"
#import "RTCEAGLVideoView.h"

@import AVFoundation;

@interface PHViewController () <PHRendererDelegate>

@property (nonatomic, strong) PHConnectionBroker *connectionBroker;
@property (nonatomic, strong) PHMediaConfiguration *configuration;

@property (nonatomic, strong) id<PHRenderer> localRenderer;
@property (nonatomic, strong) NSMutableArray *remoteRenderers;



@end

@implementation PHViewController

- (id)init
{
    self = [super init];
    
    if (self) {
        _remoteRenderers = [NSMutableArray array];
        _configuration   = [PHMediaConfiguration defaultConfiguration];
    }
    
    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor greenColor];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

#pragma mark - Private

- (void)startDisconnect
{
    
    [self hideAndRemoveRemoteRenderers];
    [self hideLocalRenderer];
    
    [self.connectionBroker disconnect];

}


//- (void)handleZoomTap:(UITapGestureRecognizer *)recognizer
//{
    //    UIView *rendererView = recognizer.view;
    //
    //    if ([rendererView isKindOfClass:[PHSampleBufferView class]]) {
    //        PHSampleBufferView *sampleView = (PHSampleBufferView *)rendererView;
    //        NSString *videoGravity = sampleView.videoGravity;
    //        NSString *updatedGravity = [videoGravity isEqualToString:AVLayerVideoGravityResizeAspect] ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
    //        sampleView.videoGravity = updatedGravity;
    //        sampleView.bounds = CGRectInset(sampleView.bounds, 1, 1);
    //        sampleView.bounds = CGRectInset(sampleView.bounds, -1, -1);
    //    }
//}

//- (void)handleAudioTap:(UITapGestureRecognizer *)recognizer
//{
    //    RTCMediaStream *stream = self.connectionBroker.localStream;
    //    BOOL isAudioEnabled = stream.isAudioEnabled;
    //    BOOL setAudioEnabled = !isAudioEnabled;
    //
    //    stream.audioEnabled = setAudioEnabled;
    //
    //    self.muteOverlayView.mode = setAudioEnabled ? PHAudioModeOn : PHAudioModeMuted;
    //
    //    UIView *renderView = self.localRenderer.rendererView;
    //    CGAffineTransform transform = renderView.transform;
    //    CGAffineTransform popTransform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(1.05, 1.05));
    //
    //    [UIView animateWithDuration:0.14 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
    //        renderView.transform = popTransform;
    //    } completion:^(BOOL finished) {
    //        [UIView animateWithDuration:0.16 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
    //            renderView.transform = transform;
    //        } completion:nil];
    //    }];
//}

- (void)connectWithPermission
{
    __weak typeof(self) weakSelf = self;
    
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL audioGranted) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL videoGranted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (audioGranted && videoGranted) {
                    [weakSelf connectNow];
                }else{
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                                    message:@"Please grant PerchRTC access to both your camera and microphone before connecting."
                                                                   delegate:nil
                                                          cancelButtonTitle:@"Okay"
                                                          otherButtonTitles:nil];
                    [alert show];
                }
            });
        }];
    }];
}

- (void)connectNow
{
    
    PHConnectionBroker *connectionBroker = [[PHConnectionBroker alloc] initWithDelegate:self busDelegate:self.busDelegate];
    
    self.connectionBroker = connectionBroker;
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
}

- (void)removeRendererForStream:(RTCMediaStream *)stream
{
    // When checking for an RTCVideoTrack use indexOfObjectIdenticalTo: instead of containsObject:
    // RTCVideoTrack doesn't implement hash or isEqual: which caused false positives.
    
    id <PHRenderer> rendererToRemove = nil;
    
    for (id<PHRenderer> remoteRenderer in self.remoteRenderers) {
        NSUInteger videoTrackIndex = [stream.videoTracks indexOfObjectIdenticalTo:remoteRenderer.videoTrack];
        if (videoTrackIndex != NSNotFound) {
            rendererToRemove = remoteRenderer;
            break;
        }
    }
    
    if (rendererToRemove) {
        [self hideAndRemoveRenderer:rendererToRemove];
    } else {
        DDLogWarn(@"No renderer to remove for stream: %@", stream);
    }
}

- (void)hideAndRemoveRemoteRenderers
{
    NSArray *remoteRenderers = [self.remoteRenderers copy];
    
    for (id<PHRenderer> rendererToRemove in remoteRenderers) {
        [self hideAndRemoveRenderer:rendererToRemove];
    }
}

- (id<PHRenderer>)rendererForStream:(RTCMediaStream *)stream
{
    NSParameterAssert(stream);
    
    id<PHRenderer> renderer = nil;
    RTCVideoTrack *videoTrack = [stream.videoTracks firstObject];
    PHRendererType rendererType = self.configuration.rendererType;
    
    if (rendererType == PHRendererTypeSampleBuffer) {
        renderer = [[PHSampleBufferRenderer alloc] initWithDelegate:self];
    }
    else if (rendererType == PHRendererTypeOpenGLES) {
        renderer = [[PHEAGLRenderer alloc] initWithDelegate:self];
    }
    else if (rendererType == PHRendererTypeQuartz) {
        PHQuartzVideoView *localVideoView = [[PHQuartzVideoView alloc] initWithFrame:CGRectZero];
        localVideoView.delegate = self;
        renderer = localVideoView;
    }
    else {
        DDLogWarn(@"Unsupported renderer type: %lu", (unsigned long)rendererType);
    }
    
    renderer.videoTrack = videoTrack;
    
    return renderer;
}

- (void)refreshRemoteRendererAspectRatios
{
    BOOL shouldAspectFill = [self.remoteRenderers count] > 1;
    
    for (id<PHRenderer> renderer in self.remoteRenderers) {
        UIView *rendererView = renderer.rendererView;
        if ([rendererView isKindOfClass:[PHSampleBufferView class]]) {
            PHSampleBufferView *sampleView = (PHSampleBufferView *)rendererView;
            sampleView.videoGravity = shouldAspectFill ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
            if (!CGRectEqualToRect(sampleView.bounds, CGRectZero)) {
                sampleView.bounds = CGRectInset(sampleView.bounds, 1, 1);
                sampleView.bounds = CGRectInset(sampleView.bounds, -1, -1);
            }
        }
    }
}

- (void)showLocalRenderer
{
    CGAffineTransform finalTransform = CGAffineTransformMakeScale(-1, 1);
    
    [self showRenderer:self.localRenderer withTransform:finalTransform];
}

- (void)showRemoteRenderer:(id<PHRenderer>)renderer
{
    [self showRenderer:renderer withTransform:CGAffineTransformIdentity];
}

- (void)showRenderer:(id<PHRenderer>)renderer withTransform:(CGAffineTransform)finalTransform
{
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    
    UIView *theView = renderer.rendererView;
    
    [self.view addSubview:theView];

//    if (renderer == self.localRenderer) {
//        [self.view addSubview:theView];
//    } else {
//        [self.view addSubview:theView];
//    }
    
}

- (void)hideLocalRenderer
{
    [self hideAndRemoveRenderer:self.localRenderer];
}

- (void)hideAndRemoveRenderer:(id<PHRenderer>)renderer
{
    UIView *theView = renderer.rendererView;
    renderer.videoTrack = nil;
    
    [theView removeFromSuperview];
    
    if ([self.remoteRenderers count] > 0) {
        
        [self refreshRemoteRendererAspectRatios];
    }
    
    
    if (renderer == self.localRenderer) {
        self.localRenderer = nil;
    }
    else {
        [self.remoteRenderers removeObject:renderer];
    }
}





#pragma mark - PHConnectionBrokerDelegate

- (void)connectionBroker:(PHConnectionBroker *)broker didAddLocalStream:(RTCMediaStream *)localStream
{
    DDLogVerbose(@"Connection manager did receive local video track: %@", [localStream.videoTracks firstObject]);
    
    #if TARGET_IPHONE_SIMULATOR
        localStream.audioEnabled = NO;
    #endif
    
    // Prepare a renderer for the local stream.
    
    self.localRenderer = [self rendererForStream:localStream];
    UIView *theView = self.localRenderer.rendererView;
    
//    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAudioTap:)];
//    [theView addGestureRecognizer:tapRecognizer];
}

- (void)connectionBroker:(PHConnectionBroker *)broker didAddStream:(RTCMediaStream *)remoteStream
{
    DDLogVerbose(@"Connection broker did add stream: %@", remoteStream);
    
    // Prepare a renderer for the remote stream.
    
    id<PHRenderer> remoteRenderer = [self rendererForStream:remoteStream];
    UIView *theView = remoteRenderer.rendererView;
    
    [self.remoteRenderers addObject:remoteRenderer];
    
    UITapGestureRecognizer *tapToZoomRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleZoomTap:)];
    tapToZoomRecognizer.numberOfTapsRequired = 2;
    [theView addGestureRecognizer:tapToZoomRecognizer];
}

- (void)connectionBroker:(PHConnectionBroker *)broker didRemoveStream:(RTCMediaStream *)remoteStream
{
    [self removeRendererForStream:remoteStream];
    
}

- (void)connectionBrokerDidFinish:(PHConnectionBroker *)broker
{
    self.connectionBroker = nil;
    }

- (void)connectionBroker:(PHConnectionBroker *)broker didFailWithError:(NSError *)error
{
    DDLogError(@"Connection broker, did encounter error: %@", error);
    
    [self startDisconnect];
}

#pragma mark - PHRendererDelegate

- (void)renderer:(id<PHRenderer>)renderer streamDimensionsDidChange:(CGSize)dimensions
{
    DDLogVerbose(@"Stream dimensions did change for %@ -> %@", NSStringFromCGSize(dimensions), renderer);
    
    [self.view setNeedsLayout];
}

- (void)rendererDidReceiveVideoData:(id<PHRenderer>)renderer
{
    DDLogVerbose(@"Did receive video data for renderer: %@", renderer);
    
    if (renderer == self.localRenderer) {
        [self showLocalRenderer];
    } else {
        [self refreshRemoteRendererAspectRatios];
        [self showRemoteRenderer:renderer];
    }
}

@end
