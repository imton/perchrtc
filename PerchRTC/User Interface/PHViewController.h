//
//  PHViewController.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2014-08-09.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "PHConnectionBroker.h"


@interface PHViewController : UIViewController <PHConnectionBrokerDelegate>

@property (nonatomic, weak) id<PHConnectionBrokerBusDelegate>busDelegate;

- (void)connectWithPermission;

@end
