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

#import <CoreLocation/CoreLocation.h>

#ifdef THEBOOTSTRAP
#import "GitHubReleaseUpdater.h"
#endif

static NSString *const TVNCLocationWakeEnabledKey = @"LocationWakeEnabled";
static NSString *const TVNCLocationWakeRegionLatitudeKey = @"LocationWakeRegionLatitude";
static NSString *const TVNCLocationWakeRegionLongitudeKey = @"LocationWakeRegionLongitude";
static NSString *const TVNCLocationWakeRegionRadiusKey = @"LocationWakeRegionRadius";
static NSString *const TVNCLocationWakeRegionIdentifier = @"com.82flex.trollvnc.location-wake";

@interface AppDelegate ()
@property(nonatomic, strong) CLLocationManager *locationManager;
@property(nonatomic, strong) NSUserDefaults *serviceDefaults;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [self configureLocationWakeTriggerWithLaunchOptions:launchOptions];
    [[TVNCServiceCoordinator sharedCoordinator] registerServiceMonitor];
    [[TVNCHotspotManager sharedManager] registerWithName:@"TrollVNC"];

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

#pragma mark - Location Wake

- (void)configureLocationWakeTriggerWithLaunchOptions:(NSDictionary *)launchOptions {
#if TARGET_IPHONE_SIMULATOR
    (void)launchOptions;
    return;
#else
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;

    if (@available(iOS 11.0, *)) {
        self.locationManager.showsBackgroundLocationIndicator = NO;
    }

    if (![self isLocationWakeEnabled]) {
        [self stopLocationWakeMonitoring];
        return;
    }

    if (![CLLocationManager locationServicesEnabled]) {
#if DEBUG
        NSLog(@"[TVNC] Location wake is enabled but Location Services are disabled.");
#endif
        return;
    }

    [self refreshLocationWakeMonitoring];

    if (launchOptions[UIApplicationLaunchOptionsLocationKey] != nil) {
        [self handleLocationWakeEvent:@"launch"];
    }
#endif
}

- (NSUserDefaults *)serviceDefaults {
    if (!_serviceDefaults) {
        _serviceDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.trollvnc"];

        NSMutableDictionary *defaults = [@{TVNCLocationWakeEnabledKey : @NO} mutableCopy];
        NSBundle *prefsBundle =
            [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"TrollVNCPrefs" ofType:@"bundle"]];
        NSString *presetPath = [prefsBundle pathForResource:@"Managed" ofType:@"plist"];
        NSDictionary *presetDefaults = [NSDictionary dictionaryWithContentsOfFile:presetPath];
        if (presetDefaults) {
            [defaults addEntriesFromDictionary:presetDefaults];
        }

        [_serviceDefaults registerDefaults:defaults];
    }
    return _serviceDefaults;
}

- (BOOL)isLocationWakeEnabled {
    return [[self serviceDefaults] boolForKey:TVNCLocationWakeEnabledKey];
}

- (CLAuthorizationStatus)currentLocationAuthorizationStatus {
    if (@available(iOS 14.0, *)) {
        return self.locationManager.authorizationStatus;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
}

- (void)refreshLocationWakeMonitoring {
    if (!self.locationManager) {
        return;
    }

    CLAuthorizationStatus status = [self currentLocationAuthorizationStatus];
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            [self.locationManager requestAlwaysAuthorization];
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
            [self.locationManager startMonitoringSignificantLocationChanges];
            [self refreshLocationWakeRegionMonitoring];
            break;
        default:
            [self stopLocationWakeMonitoring];
            break;
    }
}

- (void)stopLocationWakeMonitoring {
    [self.locationManager stopMonitoringSignificantLocationChanges];

    for (CLRegion *region in self.locationManager.monitoredRegions) {
        if ([region.identifier isEqualToString:TVNCLocationWakeRegionIdentifier]) {
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

- (void)refreshLocationWakeRegionMonitoring {
    for (CLRegion *region in self.locationManager.monitoredRegions) {
        if ([region.identifier isEqualToString:TVNCLocationWakeRegionIdentifier]) {
            [self.locationManager stopMonitoringForRegion:region];
        }
    }

    if (![CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]]) {
        return;
    }

    id latitudeValue = [[self serviceDefaults] objectForKey:TVNCLocationWakeRegionLatitudeKey];
    id longitudeValue = [[self serviceDefaults] objectForKey:TVNCLocationWakeRegionLongitudeKey];
    id radiusValue = [[self serviceDefaults] objectForKey:TVNCLocationWakeRegionRadiusKey];

    if (![latitudeValue isKindOfClass:[NSNumber class]] || ![longitudeValue isKindOfClass:[NSNumber class]] ||
        ![radiusValue isKindOfClass:[NSNumber class]]) {
        return;
    }

    CLLocationDegrees latitude = [(NSNumber *)latitudeValue doubleValue];
    CLLocationDegrees longitude = [(NSNumber *)longitudeValue doubleValue];
    CLLocationDistance radius = [(NSNumber *)radiusValue doubleValue];
    if (!CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(latitude, longitude)) || radius <= 0.0) {
        return;
    }

    CLLocationDistance maxRadius = self.locationManager.maximumRegionMonitoringDistance;
    if (maxRadius > 0.0) {
        radius = MIN(radius, maxRadius);
    }

    CLCircularRegion *region =
        [[CLCircularRegion alloc] initWithCenter:CLLocationCoordinate2DMake(latitude, longitude)
                                          radius:radius
                                      identifier:TVNCLocationWakeRegionIdentifier];
    region.notifyOnEntry = YES;
    region.notifyOnExit = YES;
    [self.locationManager startMonitoringForRegion:region];
}

- (void)handleLocationWakeEvent:(NSString *)source {
#if TARGET_IPHONE_SIMULATOR
    (void)source;
    return;
#else
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
    backgroundTask = [application beginBackgroundTaskWithName:@"TVNCLocationWake"
                                            expirationHandler:^{
                                                if (backgroundTask != UIBackgroundTaskInvalid) {
                                                    [application endBackgroundTask:backgroundTask];
                                                    backgroundTask = UIBackgroundTaskInvalid;
                                                }
                                            }];

#if DEBUG
    NSLog(@"[TVNC] Location wake event received from %@.", source);
#endif
    [[TVNCServiceCoordinator sharedCoordinator] ensureServiceRunning];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (backgroundTask != UIBackgroundTaskInvalid) {
            [application endBackgroundTask:backgroundTask];
        }
    });
#endif
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    (void)manager;
    [self refreshLocationWakeMonitoring];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    (void)manager;
    (void)status;
    [self refreshLocationWakeMonitoring];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager;
    if (locations.count > 0) {
        [self handleLocationWakeEvent:@"significant-change"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    (void)manager;
    if ([region.identifier isEqualToString:TVNCLocationWakeRegionIdentifier]) {
        [self handleLocationWakeEvent:@"region-enter"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    (void)manager;
    if ([region.identifier isEqualToString:TVNCLocationWakeRegionIdentifier]) {
        [self handleLocationWakeEvent:@"region-exit"];
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(nullable CLRegion *)region withError:(NSError *)error {
    (void)manager;
#if DEBUG
    NSLog(@"[TVNC] Failed to monitor region %@: %@", region.identifier, error);
#else
    (void)region;
    (void)error;
#endif
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

@end
