//
//  PHConnectionManager.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RTCVideoTrack;
@class RTCMediaStream;
@class PHConnectionBroker;
@class PHMediaConfiguration;

//@class AFNetworkReachabilityManager;

// Provides information about connected streams, errors and final disconnections.
@protocol PHConnectionBrokerDelegate<NSObject>

- (void)connectionBrokerDidFinish:(PHConnectionBroker *)broker;

- (void)connectionBroker:(PHConnectionBroker *)broker didAddLocalStream:(RTCMediaStream *)localStream;

- (void)connectionBroker:(PHConnectionBroker *)broker didAddStream:(RTCMediaStream *)remoteStream;

- (void)connectionBroker:(PHConnectionBroker *)broker didRemoveStream:(RTCMediaStream *)remoteStream;

- (void)connectionBroker:(PHConnectionBroker *)broker didFailWithError:(NSError *)error;

@end

@protocol PHConnectionBrokerBusDelegate<NSObject>

-(NSDictionary*) ICEServers;
-(NSString*) connectionID;
-(NSString*) selfID;
-(NSString*) peerID;
-(void) sendToPeerID:(NSString*)_peerID event:(NSString*)_eventName data:(NSDictionary*)_data;
-(void) receivedFromPeerEvent:(void (^)(NSString* peerID, NSString* eventName, NSDictionary* data, NSString* connectionID))_received;

@end



/**
 *  The connection broker facilitates media streaming.
 *  The broker handles authorization, and signaling to establish and maintain connections.
 */
@interface PHConnectionBroker : NSObject

@property (nonatomic, weak) id<PHConnectionBrokerDelegate> delegate;
@property (nonatomic, weak) id<PHConnectionBrokerBusDelegate> busDelegate;

@property (nonatomic, strong, readonly) RTCMediaStream *localStream;

@property (nonatomic, strong, readonly) NSArray *remoteStreams;

- (instancetype)initWithDelegate:(id<PHConnectionBrokerDelegate>)_aDelegate busDelegate:(id<PHConnectionBrokerBusDelegate>)_aBusDelegate;

- (BOOL)connectWithConfiguration:(PHMediaConfiguration *)_configuration;

- (void)disconnect;

@end
