//
//  PHCredentials.h
//  PerchRTC
//
//  Created by Sam Symons on 2015-05-08.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#ifndef PerchRTC_PHCredentials_h
#define PerchRTC_PHCredentials_h

//#error Please enter your XirSys credentials (http://xirsys.com/pricing/)

static NSString *kPHConnectionManagerDomain = @"api.strngr.co";
static NSString *kPHConnectionManagerApplication = @"default";
static NSString *kPHConnectionManagerXSUsername = @"imton";
static NSString *kPHConnectionManagerXSSecretKey = @"1d430e54-5d80-11e5-bf57-f8ac74ba3b7c";

#ifdef DEBUG
static NSString *kPHConnectionManagerDefaultRoomName = @"default";
#else
static NSString *kPHConnectionManagerDefaultRoomName = @"default";
#endif

#endif
