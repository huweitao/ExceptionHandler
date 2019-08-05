//
//  ExceptionCatcher.h
//  AlipayMoDebugBox
//
//  Created by huweitao on 2019/8/5.
//  Copyright © 2019 Alipay. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExceptionCatcher : NSObject

+ (instancetype)sharedCatch;


/**
 This method should be written at
 
 - (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions

 or may not work as expected way!
 
 @param handler exception handler for user doing something
 */
+ (void)setupUncaughtSignalExceptionOn:(void(^)(void))handler;

@end

NS_ASSUME_NONNULL_END
