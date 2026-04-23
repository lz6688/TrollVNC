/*
 This file is part of TrollVNC
 Copyright (c) 2025 82Flex <82flex@gmail.com> and contributors

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License version 2
 as published by the Free Software Foundation.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/>.
*/

#import "AppDelegate.h"
#import "TVNCHotspotManager.h"
#import "TVNCServiceCoordinator.h"
#import "TrollVNC-Swift.h"

#if __has_include(<BackgroundTasks/BackgroundTasks.h>)
#import <BackgroundTasks/BackgroundTasks.h>
#endif

#ifdef THEBOOTSTRAP
#import "GitHubReleaseUpdater.h"
#endif

static NSString *const TVNCWidgetBootstrapTaskIdentifier = @"com.82flex.TrollVNCApp.widget-refresh";
static NSTimeInterval const TVNCWidgetBootstrapEarliestDelay = 5.0 * 60.0;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [self registerWidgetBootstrapTaskIfNeeded];
    [[TVNCServiceCoordinator sharedCoordinator] registerServiceMonitor];
    [[TVNCHotspotManager sharedManager] registerWithName:@"TrollVNC"];
    [self scheduleWidgetBootstrapRefreshIfNeeded];

#ifdef THEBOOTSTRAP
    // Initialize Auto Updater
    GHUpdateStrategy *updateStrategy = [[GHUpdateStrategy alloc] init];
    [updateStrategy setRepoFullName:@"OwnGoalStudio/TrollVNC"];

    GitHubReleaseUpdater *updater = [GitHubReleaseUpdater shared];
#if TARGET_IPHONE_SIMULATOR
    [updater configureWithStrategy:updateStrategy];
#else
    [updater configureWithStrategy:updateStrategy currentVersion:@PACKAGE_VERSION];
#endif
    [updater start];
#endif

    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self scheduleWidgetBootstrapRefreshIfNeeded];
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after
    // application:didFinishLaunchingWithOptions. Use this method to release any resources that were specific to the
    // discarded scenes, as they will not return.
}

#pragma mark - Background Tasks

- (void)registerWidgetBootstrapTaskIfNeeded {
#if TARGET_IPHONE_SIMULATOR
    return;
#else
#if __has_include(<BackgroundTasks/BackgroundTasks.h>)
    if (@available(iOS 13.0, *)) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            BOOL registered =
                [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:TVNCWidgetBootstrapTaskIdentifier
                                                                      usingQueue:nil
                                                                   launchHandler:^(__kindof BGTask *_Nonnull task) {
                                                                       if (![task isKindOfClass:[BGAppRefreshTask class]]) {
                                                                           [task setTaskCompletedWithSuccess:NO];
                                                                           return;
                                                                       }
                                                                       [self handleWidgetBootstrapTask:(BGAppRefreshTask *)task];
                                                                   }];
            if (!registered) {
                NSLog(@"[TVNC] Failed to register background refresh task %@", TVNCWidgetBootstrapTaskIdentifier);
            }
        });
    }
#endif
#endif
}

- (void)scheduleWidgetBootstrapRefreshIfNeeded {
#if TARGET_IPHONE_SIMULATOR
    return;
#else
#if __has_include(<BackgroundTasks/BackgroundTasks.h>)
    if (@available(iOS 13.0, *)) {
        BGAppRefreshTaskRequest *request =
            [[BGAppRefreshTaskRequest alloc] initWithIdentifier:TVNCWidgetBootstrapTaskIdentifier];
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:TVNCWidgetBootstrapEarliestDelay];

        [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:TVNCWidgetBootstrapTaskIdentifier];

        NSError *error = nil;
        BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
        if (!submitted) {
            NSLog(@"[TVNC] Failed to submit background refresh task %@: %@", TVNCWidgetBootstrapTaskIdentifier,
                  error.localizedDescription);
        }
    }
#endif
#endif
}

#if __has_include(<BackgroundTasks/BackgroundTasks.h>)
- (void)handleWidgetBootstrapTask:(BGAppRefreshTask *)task API_AVAILABLE(ios(13.0)) {
    [self scheduleWidgetBootstrapRefreshIfNeeded];

    __block BOOL finished = NO;
    void (^finishTask)(BOOL) = ^(BOOL success) {
        @synchronized(self) {
            if (finished) {
                return;
            }
            finished = YES;
        }
        [task setTaskCompletedWithSuccess:success];
    };

    task.expirationHandler = ^{
        finishTask(NO);
    };

    if ([TRWidgetBootstrapState hasPendingWidgetBootstrap]) {
        [[TVNCServiceCoordinator sharedCoordinator] ensureServiceRunning];
        [TRWidgetBootstrapState recordBootstrapAttempt];
        [TRWidgetBootstrapState clearPendingWidgetBootstrap];
        finishTask(YES);
        return;
    }

    [TRWidgetBootstrapState refreshWidgetPresence:^(BOOL hasWidget) {
        if (hasWidget) {
            [[TVNCServiceCoordinator sharedCoordinator] ensureServiceRunning];
        }
        finishTask(YES);
    }];
}
#endif

@end
