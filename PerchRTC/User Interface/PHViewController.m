//
//  PHViewController.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHViewController.h"

#import "PHConnectionBroker.h"
#import "PHCredentials.h"
#import "PHEAGLRenderer.h"
#import "PHErrors.h"
#import "PHMediaConfiguration.h"
#import "PHMuteOverlayView.h"
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

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    
    if (self) {
        _remoteRenderers = [NSMutableArray array];
        _configuration = [PHMediaConfiguration defaultConfiguration];
    }
    
    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self connectWithPermission];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

#pragma mark - Private

//- (void)layoutLocalFeed
//{
//
//    UIView *localRenderView = self.localRenderer.rendererView;
//
//}

- (NSUInteger)numActiveRemoteRenderers
{
    __block NSUInteger activeRenderers = 0;
    
    [self.remoteRenderers enumerateObjectsUsingBlock:^(id<PHRenderer> renderer, NSUInteger idx, BOOL *stop) {
        if (renderer.hasVideoData) {
            activeRenderers++;
        }
    }];
    
    return activeRenderers;
}

//- (BOOL)rendererOrientationsMatch
//{
//    __block NSUInteger portraitRenderers = 0;
//
//    [self.remoteRenderers enumerateObjectsUsingBlock:^(id<PHRenderer> renderer, NSUInteger idx, BOOL *stop) {
//        if (renderer.hasVideoData && renderer.videoSize.height > renderer.videoSize.width) {
//            portraitRenderers++;
//        }
//    }];
//
//    return (portraitRenderers == [self.remoteRenderers count] || portraitRenderers == 0);
//}

- (void)layoutRemoteFeeds
{
    CGRect bounds = self.view.bounds;
    BOOL isPortrait = UIInterfaceOrientationIsPortrait(self.interfaceOrientation);
    
    NSUInteger numRemoteRenderers = [self numActiveRemoteRenderers];
    
    if (numRemoteRenderers == 1) {
        id<PHRenderer> renderer = [self.remoteRenderers firstObject];
        renderer.rendererView.frame = bounds;
    }
    else if (numRemoteRenderers == 2) {
        for (id<PHRenderer> renderer in self.remoteRenderers) {
            
            // CGRect frame = {origin.x, origin.y, width, height};
            // renderer.rendererView.frame = frame;
            
        }
    }else if (numRemoteRenderers > 2) {
        
        for (id<PHRenderer> renderer in self.remoteRenderers) {
            //            UIView *rendererView = renderer.rendererView;
        }
    }
}

- (void)startDisconnect
{
    
    [self hideAndRemoveRemoteRenderers];
    [self hideLocalRenderer];
    
    [self.connectionBroker disconnect];
    //    [self.connectionBroker removeObserver:self forKeyPath:@"peerConnectionState"];
}

// TODO: Support tap to zoom for all renderers.
- (void)handleZoomTap:(UITapGestureRecognizer *)recognizer
{
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
}

- (void)handleAudioTap:(UITapGestureRecognizer *)recognizer
{
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
}

- (void)connectWithPermission
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL audioGranted) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL videoGranted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (audioGranted && videoGranted) {
                    [self connectToRoom:kPHConnectionManagerDefaultRoomName];
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

- (void)connectToRoom:(NSString *)roomName
{
    //    NSString *name = [UIDevice currentDevice].name;
    //    XSRoom *room = [[XSRoom alloc] initWithAuthToken:nil username:name andRoomName:roomName];
    PHConnectionBroker *connectionBroker = [[PHConnectionBroker alloc] initWithDelegate:self busDelegate:self];
    
    //    [room addRoomObserver:self];
    
    //    [connectionBroker addObserver:self forKeyPath:@"peerConnectionState" options:NSKeyValueObservingOptionOld context:NULL];
    //    [connectionBroker connectToRoom:room withConfiguration:self.configuration];
    
    self.connectionBroker = connectionBroker;
    
    //    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    //    [self.navigationItem setRightBarButtonItem:nil animated:YES];
    
    //    [UIView animateWithDuration:0.2 animations:^{
    //        self.roomInfoLabel.alpha = 0.0;
    //    }];
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
    }
    else {
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
    
    if (renderer == self.localRenderer) {
        [self.view addSubview:theView];
    } else {
        [self.view addSubview:theView];
    }
    
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
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAudioTap:)];
    [theView addGestureRecognizer:tapRecognizer];
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
    
    NSString *message = [NSString stringWithFormat:@"Ready to join %@.", [kPHConnectionManagerDefaultRoomName capitalizedString]];
    
}

- (void)connectionBroker:(PHConnectionBroker *)broker didFailWithError:(NSError *)error
{
    DDLogError(@"Connection broker, did encounter error: %@", error);
    
    [self startDisconnect];
}

#pragma mark - PHRendererDelegate

- (void)renderer:(id<PHRenderer>)renderer streamDimensionsDidChange:(CGSize)dimensions
{
    NSString *rendererTitle = renderer == self.localRenderer ? @"local renderer" : @"remote renderer";
    DDLogVerbose(@"Stream dimensions did change for %@: %@, %@", rendererTitle, NSStringFromCGSize(dimensions), renderer);
    
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
