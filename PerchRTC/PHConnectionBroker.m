//
//  PHConnectionManager.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHConnectionBroker.h"

#if !TARGET_IPHONE_SIMULATOR
#import "PHVideoCaptureKit.h"
#import "PHVideoPublisher.h"
#endif

#import "PHErrors.h"
#import "PHCredentials.h"
#import "PHMediaSession.h"
#import "PHPeerConnection.h"

#import "RTCICECandidate.h"
#import "RTCICEServer.h"
#import "RTCMediaStream.h"
#import "RTCPeerConnection.h"
#import "RTCSessionDescription.h"
#import "RTCMediaStream.h"


@import AVFoundation;

static NSUInteger kPHConnectionManagerMaxIceAttempts = 3;
static NSUInteger kPHConnectionManagerMaxWebSocketAuthAttempts = 3;

// This is the maximum number of remote peers allowed in the room, not including yourself.
// In this case we only allow 3 people in one room.
//static NSUInteger kPHConnectionManagerMaxRoomPeers = 2;


// Types

#define kXSMessageTypeKey "type"

// Content

#define kXSMessageSenderIdKey @"userid"
#define kXSMessageTargetIdKey @"targetUserId"
#define kXSMessageDataKey @"message"
#define kXSMessagePeerDataKey @"data"
#define kXSMessageRoomKey @"room"
#define kXSMessageConnectionIdKey @"connectionId"
#define kXSMessageEventName @"eventName"

// Peer message event types.

#define kXSMessageEventICE @"ice"
#define kXSMessageEventOffer @"offer"
#define kXSMessageEventAnswer @"answer"
#define kXSMessageEventBye @"bye"

// Peer message payloads.

#define kXSMessageOfferDataKey @"offer"
#define kXSMessageAnswerDataKey @"answer"
#define kXSMessageICECandidateDataKey @"iceCandidate"
#define kXSMessageByeDataKey @"bye"


#if !TARGET_IPHONE_SIMULATOR
static BOOL kPHConnectionManagerUseCaptureKit = YES;
#endif

@interface PHConnectionBroker() <PHSignalingDelegate>

@property (nonatomic, strong) NSMutableArray *mutableRemoteStreams;

@property (nonatomic, strong) PHMediaSession *mediaSession;

#if !TARGET_IPHONE_SIMULATOR
@property (nonatomic, strong) PHVideoPublisher *publisher;
#endif

@property (nonatomic, assign) NSUInteger retryCount;

@end

@implementation PHConnectionBroker

#pragma mark - Init & Dealloc

- (instancetype)initWithDelegate:(id<PHConnectionBrokerDelegate>)_aDelegate busDelegate:(id<PHConnectionBrokerBusDelegate>)_aBusDelegate
{
    self = [super init];
    if (self) {
        _delegate = _aDelegate;
        _busDelegate = _aBusDelegate;
        _mutableRemoteStreams = [NSMutableArray array];
        
        NSAssert(_busDelegate, @"A bus delegate is required.");
        
        __weak typeof(self) weakSelf = self;
        [_busDelegate receivedFromPeerEvent:^(NSString *peerID, NSString *eventName, NSDictionary *data, NSString *connectionID) {
            
            if ([eventName isEqualToString:kXSMessageEventICE]){
                
                [weakSelf handleICEMessage:data peerID:peerID connectionID:connectionID];
                
            }else if ([eventName isEqualToString:kXSMessageEventOffer]){
                
                [weakSelf handleOffer:data peerID:peerID connectionID:connectionID];
                
            }else if ([eventName isEqualToString:kXSMessageEventAnswer]){
                
                [weakSelf handleAnswer:data peerID:peerID connectionID:connectionID];
                
            }else if ([eventName isEqualToString:kXSMessageEventBye]){
                
                [weakSelf handleBye:data peerID:peerID connectionID:connectionID];
                
            }
            
        }];
        
    }
    return self;
}

- (void)dealloc
{
    DDLogDebug(@"%s", __PRETTY_FUNCTION__);
}

#pragma mark - NSObject


#pragma mark - Public

// Fetch the ice servers, and socket credentials in order to connect with the room.
- (BOOL)connectWithConfiguration:(PHMediaConfiguration *)configuration
{
    
    if (!self.mediaSession) {
        [self setupMediaSessionWithConfiguration:configuration];
    }

    return YES;
}

- (void)disconnect
{
    [self disconnectPrivate];
}

- (RTCMediaStream *)localStream
{
    return self.mediaSession.localStream;
}

- (NSArray *)remoteStreams
{
    return [self.mutableRemoteStreams copy];
}


#pragma mark - Private


- (void)setupMediaSessionWithConfiguration:(PHMediaConfiguration *)config
{
    PHVideoCaptureKit *captureKit = nil;
    
#if !TARGET_IPHONE_SIMULATOR
    if (kPHConnectionManagerUseCaptureKit) {
        self.publisher = [[PHVideoPublisher alloc] init];
        captureKit = self.publisher.captureKit;
    }
#endif
    
    self.mediaSession = [[PHMediaSession alloc] initWithDelegate:self configuration:config andCapturer:captureKit];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate connectionBroker:self didAddLocalStream:self.localStream];
    });
}


- (void)setupPeerConnectionWithPeerID:(NSString*)_peerID
                           ICEServers:(NSArray*)_iceServersDictionary
                         connectionId:(NSString *)_connectionId
                                offer:(RTCSessionDescription *)_offerSDP
{
    
    NSMutableArray *iceServers = [NSMutableArray array];
    
    for (NSDictionary *server in _iceServersDictionary) {
        
        RTCICEServer *iceServer = [[RTCICEServer alloc] initWithURI:[server objectForKey:@"url"]
                                                           username:([server objectForKey:@"username"] ? : @"")
                                                           password:([server objectForKey:@"credential"] ? : @"")];
        
        if (iceServer) {
            [iceServers addObject:iceServers];
        }
        
    }
    
    
    [self.mediaSession addIceServers:iceServers singleUse:YES];


    if (_offerSDP) { // accepts connection if it receives an offer
        [self.mediaSession acceptConnectionFromPeer:_peerID withId:_connectionId offer:_offerSDP];
    }else{
        [self.mediaSession connectToPeer:_offerSDP];
    }


}

- (void)checkCaptureFormat
{
#if !TARGET_IPHONE_SIMULATOR

    // Reduce capture quality for multi-party.

    PHCapturePreset preset = [PHVideoPublisher recommendedCapturePreset];

    if (self.mediaSession.connectionCount > 1) {
        preset = PHCapturePresetAcademyExtraLowQuality;
    }

    [self.publisher updateCaptureFormat:preset];
#endif
}

- (void)disconnectPrivate
{
    DDLogInfo(@"Connection broker: Disconnect.");

    [self sendByeToConnectedPeer];

    [self teardownMedia];

    [self.delegate connectionBrokerDidFinish:self]; // TOREV
    
}

- (void)teardownMedia
{
    [self.mutableRemoteStreams removeAllObjects];

    [self.mediaSession stopLocalMedia];
}

- (void)sendSessionDescription:(RTCSessionDescription *)sdp toPeer:(NSString *)peerId connectionId:(NSString *)connectionId
{
    DDLogVerbose(@"Send session description to peer: %@", peerId);

    NSDictionary *json = @{@"sdp" : sdp.description, @"type" : sdp.type};
    NSDictionary *message = nil;

    // Generate a connection Id for offers.

    if ([sdp.type isEqualToString:@"offer"]) {
        
        // Offer
        
        NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                      kXSMessageOfferDataKey : json};
        
        [[self busDelegate] sendToPeerID:peerId event:kXSMessageEventOffer data:json];
        
    } else {
        
        // Answer
        
        NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                      kXSMessageAnswerDataKey : json};
        
        [[self busDelegate] sendToPeerID:peerId event:kXSMessageEventAnswer data:messageData];
        
    }

}


- (void)sendByeToConnectedPeer
{
    
    PHPeerConnection *connection = [self.mediaSession connectionForPeerId:[[self busDelegate] peerID]];

    if (connection) {
        [self sendByeToPeerID:connection.peerId connectionId:connection.connectionId];
    }

}

- (void)sendByeToPeerID:(NSString *)peerID connectionId:(NSString *)connectionId
{

    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageByeDataKey : @{}};
    
    [[self busDelegate] sendToPeerID:peerID event:kXSMessageEventBye data:messageData];
    
}


- (NSString *)parseSocketCredentials:(id)socketData
{
    NSString *token = nil;

    // ..Parse the socket credentials

    if ([socketData isKindOfClass:[NSDictionary class]]) {
        token = socketData[@"token"];
    }

    return token;
}

- (void)handleICEMessage:(NSDictionary *)_data peerID:(NSString*)_peerID connectionID:(NSString*)_connectionID
{

    NSDictionary *iceData = _data[kXSMessageICECandidateDataKey];
    NSString *connectionId = _data[kXSMessageConnectionIdKey];
    
    NSAssert([_connectionID isEqualToString:connectionId], @"Connection ID should match, right?");
    
    BOOL shouldAccept = connectionId.length > 0;

    if (!shouldAccept) {
        DDLogWarn(@"Discarding ICE Message :%@", _data);
        return;
    }

    NSString *mid = iceData[@"id"];
    NSNumber *sdpLineIndex = iceData[@"label"];
    NSString *sdp = iceData[@"candidate"];
    RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:mid
                                                                index:sdpLineIndex.intValue
                                                                  sdp:sdp];
    
    [self.mediaSession addIceCandidate:candidate forPeer:_peerID connectionId:connectionId];;
}

- (void)handleOffer:(NSDictionary *)_data peerID:(NSString*)_peerID connectionID:(NSString*)_connectionID
{
    NSString *connectionId = _data[kXSMessageConnectionIdKey];
    
    NSAssert([_connectionID isEqualToString:connectionId], @"Connection ID should match, right?");

    
    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:_peerID];
    BOOL shouldAccept = !peerConnection && [connectionId length] > 0;
    BOOL shouldRenegotiate = peerConnection && [peerConnection.connectionId isEqualToString:connectionId];

    NSString *sdpString = _data[kXSMessageOfferDataKey][@"sdp"];
    NSString *sdpType = _data[kXSMessageOfferDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];
    
    if (shouldAccept) {
        [self setupPeerConnectionWithPeerID:_peerID ICEServers:[[self busDelegate] ICEServers] connectionId:connectionId offer:sdp];
    }else if (shouldRenegotiate) {
        [self.mediaSession addOffer:sdp forPeer:_peerID connectionId:connectionId];
    }else {
        [self sendByeToPeerID:_peerID connectionId:connectionId];
    }
    
}

- (void)handleAnswer:(NSDictionary *)_data peerID:(NSString*)_peerID connectionID:(NSString*)_connectionID
{
    NSString *connectionId = _data[kXSMessageConnectionIdKey];
    
    NSAssert([_connectionID isEqualToString:connectionId], @"Connection ID should match, right?");
 
    NSString *sdpString = _data[kXSMessageAnswerDataKey][@"sdp"];
    NSString *sdpType = _data[kXSMessageAnswerDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];

    [self.mediaSession addAnswer:sdp forPeer:_peerID connectionId:connectionId];
}

- (void)handleBye:(NSDictionary *)_data peerID:(NSString*)_peerID connectionID:(NSString*)_connectionID
{
    // NSDictionary *messageData = _data[kXSMessageByeDataKey];
    NSString *connectionId = _data[kXSMessageConnectionIdKey];

    NSAssert([_connectionID isEqualToString:connectionId], @"Connection ID should match, right?");
    
    [self.mediaSession closeConnectionWithPeer:_peerID];
}

//- (void)evaluatePeerCandidate:(XSPeer *)peer
//{
//    NSLog(@"%s", __PRETTY_FUNCTION__);
//
//    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:peer.identifier];
//
//    if (!peerConnection) {
//        [self fetchICEServersAndSetupPeerConnectionForRoom:self.room peer:peer connectionId:nil offer:nil];
//    }
//    else {
//        DDLogWarn(@"Not opening a peer connection with: %@ because one already exists.", peer.identifier);
//    }
//}

//- (BOOL)isRoomFull:(XSRoom *)room
//{
//    return [room.peers count] > kPHConnectionManagerMaxRoomPeers;
//}

#pragma mark - Class

#pragma mark - PHSignalingDelegate

- (void)signalOffer:(RTCSessionDescription *)sdpOffer forConnection:(PHPeerConnection *)connection
{
    [self sendSessionDescription:sdpOffer toPeer:connection.peerId connectionId:connection.connectionId];
}

- (void)signalAnswer:(RTCSessionDescription *)sdpAnswer forConnection:(PHPeerConnection *)connection
{
    [self sendSessionDescription:sdpAnswer toPeer:connection.peerId connectionId:connection.connectionId];
}

- (void)signalICECandidate:(RTCICECandidate *)iceCandidate forConnection:(PHPeerConnection *)connection
{
    DDLogVerbose(@"Send ICE candidate: %@", iceCandidate.sdpMid);

    NSDictionary *json = @{
                           @"label" : @(iceCandidate.sdpMLineIndex),
                           @"id" : iceCandidate.sdpMid,
                           @"candidate" : iceCandidate.sdp
                           };

    
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connection.connectionId,
                                  kXSMessageICECandidateDataKey : json};
    
    [[self busDelegate] sendToPeerID:connection.peerId event:kXSMessageEventICE data:messageData];

}

- (void)connection:(PHPeerConnection *)connection addedStream:(RTCMediaStream *)stream
{
    [self.mutableRemoteStreams addObject:stream];

    [self.delegate connectionBroker:self didAddStream:stream];
}

- (void)connection:(PHPeerConnection *)connection removedStream:(RTCMediaStream *)stream
{
    [self.mutableRemoteStreams removeObject:stream];

    [self.delegate connectionBroker:self didRemoveStream:stream];
}

- (void)connection:(PHPeerConnection *)connection iceStatusChanged:(RTCICEConnectionState)state
{
    switch (state) {
        case RTCICEConnectionNew:
        case RTCICEConnectionChecking:
        case RTCICEConnectionCompleted:
        case RTCICEConnectionConnected:
            break;
        case RTCICEConnectionClosed:
        {
            [self.mediaSession closeConnectionWithPeer:connection.peerId];
            break;
        }
        case RTCICEConnectionDisconnected:
        {
            [self.mediaSession closeConnectionWithPeer:connection.peerId];
            break;
        }
        case RTCICEConnectionFailed:
        {
            // The connection failed during the ICE candidate phase.
            // While the peer is available on the signaling server we should retry with an ice-restart.

            BOOL peerReachable = YES;
            BOOL isInitiator = connection.role == PHPeerConnectionRoleInitiator;
            BOOL canAttemptRestart = connection.iceAttempts <= kPHConnectionManagerMaxIceAttempts;

            BOOL restartICE = isInitiator && peerReachable && canAttemptRestart;
            BOOL closeConnection = !peerReachable || !canAttemptRestart;

            if (restartICE) {
                [self.mediaSession restartIceWithPeer:connection.peerId];
            }
            else if (closeConnection) {
                [self.mediaSession closeConnectionWithPeer:connection.peerId];
            }

            break;
        }
    }
}

- (BOOL)session:(PHMediaSession *)session shouldRenegotiateConnectionsWithFormat:(PHVideoFormat)receiverFormat
{
    [self checkCaptureFormat];

    return YES;
}

//#pragma mark - XSPeerClientDelegate
//
//- (void)clientDidConnect:(XSPeerClient *)client
//{
//    // Wait for join event to come. Potentially inform our delegate of signaling connection status?
//
//    self.retryCount = 0;
//}

//- (void)clientDidDisconnect:(XSPeerClient *)client
//{
//    // If this was a final disconnection, let our delegate know.
//    // If we can reconnect, start now otherwise wait for reachability to return.
//
//    if (!self.apiClient) {
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            [self.delegate connectionBrokerDidFinish:self];
//        });
//    }
//    else {
//        [self checkAuthorizationStatus];
//    }
//}

//- (void)client:(XSPeerClient *)client didEncounterError:(NSError *)error
//{
//    [self.delegate connectionBroker:self didFailWithError:error];
//}

//#pragma mark - XSRoomObserver
//
//- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer
//{
//    NSString *peerId = peer.identifier;
//    PHPeerConnection *peerConnectionWrapper = [self.mediaSession connectionForPeerId:peerId];
//
//    if (!peerConnectionWrapper) {
//        return;
//    }
//
//    RTCICEConnectionState iceState = peerConnectionWrapper.peerConnection.iceConnectionState;
//
//    switch (iceState) {
//        case RTCICEConnectionDisconnected:
//        case RTCICEConnectionNew:
//        case RTCICEConnectionFailed:
//            [self.mediaSession closeConnectionWithPeer:peerId];
//            break;
//        default:
//            break;
//    }
//}

@end
