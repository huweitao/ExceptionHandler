//
//  ExceptionCatcher.m
//  AlipayMoDebugBox
//
//  Created by huweitao on 2019/8/5.
//  Copyright © 2019 Alipay. All rights reserved.
//

#import "ExceptionCatcher.h"

#import <UIKit/UIKit.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>

// Local notification
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
#pragma mark - UNUserNotificationCenterDelegate
#import <UserNotifications/UserNotifications.h>
#endif

typedef void(^ExceptionCatchHandler)(void);

NSString * const UncaughtExceptionHandlerSignalName = @"com.exceptionSignalExceptionName";
NSString * const UncaughtExceptionHandlerSignalKey = @"com.exceptionHandlerSignalKey";
NSString * const UncaughtExceptionHandlerAddressesKey = @"com.exceptionHandlerAddressesKey";

volatile int32_t ExceptionCount = 0;
const int32_t ExceptionMaximum = 10;
static ExceptionCatchHandler bExceptionHandler;
static CFAbsoluteTime AlertStartTime;

void venderHandleException(NSException *exception);
void venderSignalHandler(int signal);

@interface ExceptionCatcher()

+ (NSArray *)backtrace;

- (void)handleException:(NSException *)exception;

@end

@implementation ExceptionCatcher

+ (instancetype)sharedCatch {
    static id _sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

+ (void)setupUncaughtSignalExceptionOn:(void(^)(void))handler
{
    bExceptionHandler = handler;
    NSSetUncaughtExceptionHandler(venderHandleException);
    signal(SIGABRT, venderSignalHandler);
    signal(SIGILL, venderSignalHandler);
    signal(SIGSEGV, venderSignalHandler);
    signal(SIGFPE, venderSignalHandler);
    signal(SIGBUS, venderSignalHandler);
    signal(SIGPIPE, venderSignalHandler);
}

+ (NSArray *)backtrace
{
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);
    int i;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (i = ExceptionCount;i < ExceptionMaximum; i++) {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return backtrace;
}

+ (UIViewController *)currentTopViewController
{
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (  [vc isKindOfClass:[UINavigationController class]] || [vc isKindOfClass:[UITabBarController class]] ) {
        if ( [vc isKindOfClass:[UINavigationController class]] ) vc = [(UINavigationController *)vc topViewController];
        if ( [vc isKindOfClass:[UITabBarController class]] ) vc = [(UITabBarController *)vc selectedViewController];
        if ( vc.presentedViewController ) vc = vc.presentedViewController;
    }
    return vc;
}

+ (void)alertExit
{
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Crash"
                                                                   message:@"App will be killed in 2 seconds!" preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              exit(0);
                                                          }];
    [alert addAction:defaultAction];
    [[ExceptionCatcher currentTopViewController] presentViewController:alert animated:NO completion:nil];
}

+ (BOOL)checkPushAuthority
{
    __block BOOL flag = NO;
    if (@available(iOS 10.0, *)) {
        //
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        UNAuthorizationOptions options = UNAuthorizationOptionAlert + UNAuthorizationOptionSound;
        //
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        // register/query for authority
        [center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (!granted || error) {
                NSLog(@"No Local Push Authority! %@",error);
            }
            else {
                flag = YES;
            }
            dispatch_semaphore_signal(sem);
        }];
        //
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }
    else {
        UIUserNotificationSettings *setting = [[UIApplication sharedApplication] currentUserNotificationSettings];
        flag = (UIUserNotificationTypeNone != setting.types);
    }
    
    return flag;
}

+ (void)sendLocalNotification:(NSString *)title body:(NSString *)body
{
    if (![ExceptionCatcher checkPushAuthority]) {
        return;
    }
    
    NSInteger timeInteval = 4.0;
    NSDictionary *userInfo = @{@"id":@"LOCAL_NOTIFY_RESTART_APP"};
    
    if (@available(iOS 10.0, *)) {
        
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.sound = [UNNotificationSound defaultSound];
        content.title = title;
        content.body = body;
        content.userInfo = userInfo;
        
        NSError *error = nil;
        NSString *path = [[NSBundle mainBundle] pathForResource:@"recovery" ofType:@"png"];
        UNNotificationAttachment *att = [UNNotificationAttachment attachmentWithIdentifier:@"recovery" URL:[NSURL fileURLWithPath:path] options:nil error:&error];
        if (error) {
            NSLog(@"attachment error %@", error);
        }
        content.attachments = @[att];
        
        UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:timeInteval repeats:NO];
        
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"com.from.kill.app" content:content trigger:trigger];
        
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            //
        }];
        
    }
    else {
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        
        // 触发时间
        localNotification.timeZone = [NSTimeZone defaultTimeZone];
        localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:timeInteval];
        
        // 标题
        localNotification.alertBody = title;
        // userinfo
        localNotification.userInfo = userInfo;
        
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
    }
    
}

- (void)handleException:(NSException *)exception {
    NSLog(@"Handle exception: %@", exception);
    NSLog(@"Current Thread: %@", [NSThread currentThread]);
    CFAbsoluteTime endtime = AlertStartTime = CFAbsoluteTimeGetCurrent();
    
    if (bExceptionHandler) {
        bExceptionHandler();
    }
    
    [ExceptionCatcher alertExit];
    
    [ExceptionCatcher sendLocalNotification:@"Tap Here!" body:@"Please tap here to recover last view page!"];
    
    // fake LiveRunloop
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    NSArray *allModes = CFBridgingRelease(CFRunLoopCopyAllModes(runLoop));
    
    while (fabs(endtime - AlertStartTime) < 2.0) {
        for (NSString *mode in allModes) {
            // 快速的切换Mode就能处理滚动、点击等事件
            CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
        }
        endtime = CFAbsoluteTimeGetCurrent();
    }
    
    bExceptionHandler = nil;
    
    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    
    if ([[exception name] isEqual:UncaughtExceptionHandlerSignalName]) {
        kill(getpid(), [[[exception userInfo] objectForKey:UncaughtExceptionHandlerSignalKey] intValue]);
        
    } else {
        [exception raise];
    }
    
}

@end

// inline methods
void venderHandleException(NSException *exception)
{
    int32_t exceptionCount = OSAtomicIncrement32(&ExceptionCount);
    //
    if (exceptionCount > ExceptionMaximum) {
        return;
    }
    
    //
    NSArray *callStack = [exception callStackSymbols];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];
    
    // main thread
    NSException *except = [NSException exceptionWithName:[exception name] reason:[exception reason] userInfo:userInfo];
    
    [[ExceptionCatcher sharedCatch] performSelectorOnMainThread:@selector(handleException:) withObject:except waitUntilDone:YES];
}

void venderSignalHandler(int signal)
{
    int32_t exceptionCount = OSAtomicIncrement32(&ExceptionCount);
    //
    if (exceptionCount > ExceptionMaximum) {
        return;
    }
    
    NSString* description = nil;
    switch (signal) {
        case SIGABRT:
            description = [NSString stringWithFormat:@"Signal SIGABRT was raised!\n"];
            break;
        case SIGILL:
            description = [NSString stringWithFormat:@"Signal SIGILL was raised!\n"];
            break;
        case SIGSEGV:
            description = [NSString stringWithFormat:@"Signal SIGSEGV was raised!\n"];
            break;
        case SIGFPE:
            description = [NSString stringWithFormat:@"Signal SIGFPE was raised!\n"];
            break;
        case SIGBUS:
            description = [NSString stringWithFormat:@"Signal SIGBUS was raised!\n"];
            break;
        case SIGPIPE:
            description = [NSString stringWithFormat:@"Signal SIGPIPE was raised!\n"];
            break;
        default:
            description = [NSString stringWithFormat:@"Signal %d was raised!",signal];
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    NSArray *callStack = [ExceptionCatcher backtrace];
    [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:[NSNumber numberWithInt:signal] forKey:UncaughtExceptionHandlerSignalKey];
    
    // main thread
    NSException *except = [NSException exceptionWithName: UncaughtExceptionHandlerSignalName reason: description userInfo: userInfo];
    
    [[ExceptionCatcher sharedCatch] performSelectorOnMainThread:@selector(handleException:) withObject:except waitUntilDone:YES];
}
