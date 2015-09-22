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

NSString * const kXSMessageTypeKey = @"type";

// Content

NSString * const kXSMessageSenderIdKey = @"userid";
NSString * const kXSMessageTargetIdKey = @"targetUserId";
NSString * const kXSMessageDataKey = @"message";
NSString * const kXSMessagePeerDataKey = @"data";
NSString * const kXSMessageRoomKey = @"room";
NSString * const kXSMessageConnectionIdKey = @"connectionId";
NSString * const kXSMessageEventName = @"eventName";

// Server message event types

NSString * const kXSMessageRoomJoin = @"peer_connected";
NSString * const kXSMessageRoomLeave = @"peer_removed";
NSString * const kXSMessageRoomUsersUpdate = @"peers";

// Server message payloads.

NSString * const kXSMessageRoomUsersUpdateDataKey = @"users";

// Peer message event types.

NSString * const kXSMessageEventICE = @"ice";
NSString * const kXSMessageEventOffer = @"offer";
NSString * const kXSMessageEventAnswer = @"answer";
NSString * const kXSMessageEventBye = @"bye";

// Peer message payloads.

NSString * const kXSMessageOfferDataKey = @"offer";
NSString * const kXSMessageAnswerDataKey = @"answer";
NSString * const kXSMessageICECandidateDataKey = @"iceCandidate";
NSString * const kXSMessageByeDataKey = @"bye";


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


- (void)setupPeerConnectionWithPeer:(NSString*)_peerID
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

    // We are assuming that its possible to send messages to the room immediately before closing the socket in teardownConnection.
    // This has worked so far in my testing.

//    if (self.peerClient.connectionState == XSPeerConnectionStateConnected) {
        [self sendByeToConnectedPeer];
//    }

//    [self.peerClient disconnect];

//    [self teardownAPIClient];

    [self teardownMedia];

    if (self.peerConnectionState == XSPeerConnectionStateDisconnected) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate connectionBrokerDidFinish:self];
        });
    }
}
//
//- (void)teardownAPIClient
//{
//
//    self.apiClient = nil;
//
//    self.retryCount = 0;
//}

//- (void)teardownReachability
//{
//    [self.reachability stopMonitoring];
//    self.reachability = nil;
//}

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
        
        [[self busDelegate] sendToPeerID:peerID event:kXSMessageEventOffer data:messageData];
        
    } else {
        
        // Answer
        
        NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                      kXSMessageAnswerDataKey : answerData};
        
        [[self busDelegate] sendToPeerID:peerID event:kXSMessageEventAnswer data:messageData];
        
    }

}


+ (NSDictionary *)offerWithUserId:(NSString *)targetUserId connectionId:(NSString *)connectionId andData:(NSDictionary *)offerData
{
    NSDictionary *messageData = @{kXSMessageConnectionIdKey : connectionId,
                                  kXSMessageOfferDataKey : offerData};
    
    return [XSMessage messageWithEventType:kXSMessageEventOffer userId:targetUserId messageData:messageData];
}

- (void)sendByeToConnectedPeer
{
    
    PHPeerConnection *connection = [self.mediaSession connectionForPeerId:[[self busDelegate] peerID]];

    if (connection) {
        [self sendByeToPeer:connection.peerId connectionId:connection.connectionId];
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

- (void)handleICEMessage:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSDictionary *iceData = messageData[kXSMessageICECandidateDataKey];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    BOOL shouldAccept = [connectionId length] > 0;

    if (!shouldAccept) {
        DDLogWarn(@"Discarding ICE Message :%@", message);
        return;
    }

    NSString *mid = iceData[@"id"];
    NSNumber *sdpLineIndex = iceData[@"label"];
    NSString *sdp = iceData[@"candidate"];
    RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:mid
                                                                index:sdpLineIndex.intValue
                                                                  sdp:sdp];

    [self.mediaSession addIceCandidate:candidate forPeer:message.senderId connectionId:connectionId];;
}

- (void)handleOffer:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    NSString *peerId = message.senderId;
    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:peerId];
    BOOL shouldAccept = !peerConnection && [connectionId length] > 0;
    BOOL shouldRenegotiate = peerConnection && [peerConnection.connectionId isEqualToString:connectionId];

    NSString *sdpString = messageData[kXSMessageOfferDataKey][@"sdp"];
    NSString *sdpType = messageData[kXSMessageOfferDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];
    XSPeer *peer = self.peerClient.room.peers[peerId];

    if (shouldAccept) {
        [self fetchICEServersAndSetupPeerConnectionForRoom:self.peerClient.room peer:peer connectionId:connectionId offer:sdp];
    }
    else if (shouldRenegotiate) {
        [self.mediaSession addOffer:sdp forPeer:message.senderId connectionId:connectionId];
    }
    else {
        [self sendByeToPeer:self.room.peers[message.senderId] connectionId:connectionId];
    }
}

- (void)handleAnswer:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];
    NSString *sdpString = messageData[kXSMessageAnswerDataKey][@"sdp"];
    NSString *sdpType = messageData[kXSMessageAnswerDataKey][@"type"];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdpString];

    [self.mediaSession addAnswer:sdp forPeer:message.senderId connectionId:connectionId];
}

- (void)handleBye:(XSMessage *)message
{
    NSDictionary *messageData = message.data[@"data"];
    NSString *connectionId = messageData[kXSMessageConnectionIdKey];

    [self.mediaSession closeConnectionWithPeer:message.senderId];
}

- (void)evaluatePeerCandidate:(XSPeer *)peer
{
    NSLog(@"%s", __PRETTY_FUNCTION__);

    PHPeerConnection *peerConnection = [self.mediaSession connectionForPeerId:peer.identifier];

    if (!peerConnection) {
        [self fetchICEServersAndSetupPeerConnectionForRoom:self.room peer:peer connectionId:nil offer:nil];
    }
    else {
        DDLogWarn(@"Not opening a peer connection with: %@ because one already exists.", peer.identifier);
    }
}

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

    XSMessage *message = [XSMessage iceCredentialsWithUserId:connection.peerId connectionId:connection.connectionId andData:json];

    [self.peerClient sendMessage:message];
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
            // We had an active connection, but we lost it.
            // Recover with an ice-restart?

            BOOL peerReachable = self.room.peers[connection.peerId] != nil;
            BOOL closeConnection = self.peerConnectionState != XSPeerConnectionStateConnected || !peerReachable;

            if (closeConnection) {
                [self.mediaSession closeConnectionWithPeer:connection.peerId];
            }

            break;
        }
        case RTCICEConnectionFailed:
        {
            // The connection failed during the ICE candidate phase.
            // While the peer is available on the signaling server we should retry with an ice-restart.

            BOOL peerReachable = self.room.peers[connection.peerId] != nil;
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

#pragma mark - XSPeerClientDelegate

- (void)clientDidConnect:(XSPeerClient *)client
{
    // Wait for join event to come. Potentially inform our delegate of signaling connection status?

    self.retryCount = 0;
}

- (void)clientDidDisconnect:(XSPeerClient *)client
{
    // If this was a final disconnection, let our delegate know.
    // If we can reconnect, start now otherwise wait for reachability to return.

    if (!self.apiClient) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate connectionBrokerDidFinish:self];
        });
    }
    else {
        [self checkAuthorizationStatus];
    }
}

- (void)client:(XSPeerClient *)client didEncounterError:(NSError *)error
{
    [self.delegate connectionBroker:self didFailWithError:error];
}

#pragma mark - XSRoomObserver

- (void)didJoinRoom:(XSRoom *)room
{
    // Prevent multi-party connections when there are too many participants.

    if ([self isRoomFull:room]) {
        [self.peerClient disconnect];
        NSError *error = [[NSError alloc] initWithDomain:PHErrorDomain code:PHErrorCodeFullRoom userInfo:nil];
        [self.delegate connectionBroker:self didFailWithError:error];
        
        return;
    }

    // If we are the first peer, wait for another.
    // If other peers already exist then wait for an offer.

    DDLogVerbose(@"Joined room with peers: %@", room.peers);
}

// TODO: Leave observer event is not fired.
- (void)didLeaveRoom:(XSRoom *)room
{
}

- (void)room:(XSRoom *)room didAddPeer:(XSPeer *)peer
{
    if (![self isRoomFull:room]) {
        [self evaluatePeerCandidate:peer];
    }
}

- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer
{
    NSString *peerId = peer.identifier;
    PHPeerConnection *peerConnectionWrapper = [self.mediaSession connectionForPeerId:peerId];

    if (!peerConnectionWrapper) {
        return;
    }

    RTCICEConnectionState iceState = peerConnectionWrapper.peerConnection.iceConnectionState;

    switch (iceState) {
        case RTCICEConnectionDisconnected:
        case RTCICEConnectionNew:
        case RTCICEConnectionFailed:
            [self.mediaSession closeConnectionWithPeer:peerId];
            break;
        default:
            break;
    }
}

- (void)room:(XSRoom *)room didReceiveMessage:(XSMessage *)message
{
    NSString *type = message.type;

    // Handle incoming SDP offers, and answers.
    // Handle ICE credentials from peers.

    if ([type isEqualToString:kXSMessageEventICE]) {
        [self handleICEMessage:message];
    }
    else if ([type isEqualToString:kXSMessageEventOffer]) {
        [self handleOffer:message];
    }
    else if ([type isEqualToString:kXSMessageEventAnswer]) {
        [self handleAnswer:message];
    }
    else if ([type isEqualToString:kXSMessageEventBye]) {
        [self handleBye:message];
    }
}

@end
