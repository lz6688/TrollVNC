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

#import "TVNCServiceCoordinator.h"
#import "TrollVNC-Swift.h"

#import <Foundation/Foundation.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/wait.h>
#import <unistd.h>

#import "Control.h"

NSNotificationName const TVNCServiceStatusDidChangeNotification = @"TVNCServiceStatusDidChangeNotification";

FOUNDATION_EXPORT NSString *const SBSApplicationLaunchOptionUnlockDeviceKey;
FOUNDATION_EXPORT
int SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(CFStringRef bundleIdentifier, CFURLRef url,
                                                             CFDictionaryRef appOptions, CFDictionaryRef launchOptions,
                                                             BOOL suspended);

extern char **environ;

static BOOL TVNCFileExistsAtAnyPath(NSFileManager *fileManager, NSArray<NSString *> *paths) {
    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            return YES;
        }
    }

    return NO;
}

static BOOL TVNCExecutableProbeSucceeds(NSString *path, NSArray<NSString *> *arguments) {
    NSUInteger argc = arguments.count + 2;
    char **argv = (char **)calloc(argc, sizeof(char *));
    if (!argv) {
        return NO;
    }

    argv[0] = strdup([path fileSystemRepresentation]);
    for (NSUInteger i = 0; i < arguments.count; ++i) {
        argv[i + 1] = strdup([arguments[i] UTF8String]);
    }

    posix_spawn_file_actions_t actions;
    BOOL actionsReady = posix_spawn_file_actions_init(&actions) == 0;
    if (actionsReady) {
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    }

    pid_t pid = -1;
    int spawnResult = posix_spawn(&pid, argv[0], actionsReady ? &actions : NULL, NULL, argv, environ);

    if (actionsReady) {
        posix_spawn_file_actions_destroy(&actions);
    }
    for (NSUInteger i = 0; i < argc; ++i) {
        free(argv[i]);
    }
    free(argv);

    if (spawnResult != 0) {
        return NO;
    }

    int status = 0;
    BOOL exited = NO;
    for (NSUInteger attempt = 0; attempt < 20; ++attempt) {
        pid_t waitResult = waitpid(pid, &status, WNOHANG);
        if (waitResult == pid) {
            exited = YES;
            break;
        }
        if (waitResult < 0) {
            return NO;
        }
        usleep(100000);
    }

    if (!exited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        return NO;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static BOOL TVNCDeviceIsActivelyJailbroken(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *rootlessLaunchctlPath = @"/var/jb/usr/bin/launchctl";
    NSArray<NSString *> *rootlessMarkers = @[
        @"/var/jb/var/lib/dpkg/status",
        @"/var/jb/usr/bin/dpkg",
        @"/var/jb/basebin/jbctl",
        @"/var/jb/usr/lib/TweakInject.dylib",
        @"/var/jb/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/var/jb/Applications/Sileo.app",
        @"/var/jb/Applications/Zebra.app",
    ];

    if ([fileManager fileExistsAtPath:rootlessLaunchctlPath] &&
        TVNCFileExistsAtAnyPath(fileManager, rootlessMarkers) &&
        TVNCExecutableProbeSucceeds(rootlessLaunchctlPath, @[ @"help" ])) {
        return YES;
    }

    NSArray<NSString *> *rootfulMarkers = @[
        @"/var/lib/dpkg/status",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/Applications/Cydia.app",
        @"/Applications/Sileo.app",
        @"/Applications/Zebra.app",
        @"/bin/bash",
        @"/usr/sbin/sshd",
        @"/usr/bin/dpkg",
    ];
    if (!TVNCFileExistsAtAnyPath(fileManager, rootfulMarkers)) {
        return NO;
    }

    if ([fileManager fileExistsAtPath:@"/bin/bash"] &&
        TVNCExecutableProbeSucceeds(@"/bin/bash", @[ @"-c", @":" ])) {
        return YES;
    }

    if ([fileManager fileExistsAtPath:@"/usr/bin/dpkg"] &&
        TVNCExecutableProbeSucceeds(@"/usr/bin/dpkg", @[ @"--version" ])) {
        return YES;
    }

    return NO;
}

@interface TVNCServiceCoordinator ()
@property(nonatomic, strong) NSTimer *checkTimer;
@property(nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation TVNCServiceCoordinator

+ (instancetype)sharedCoordinator {
    static TVNCServiceCoordinator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (NSDictionary *)sharedTaskEnvironment {
    static NSDictionary *sharedEnvironment = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *env =
            [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
        NSString *languageCode = [[NSLocale preferredLanguages] firstObject];
        if (languageCode) {
            env[@"TVNC_LANGUAGE_CODE"] = languageCode;
        }
#if TARGET_IPHONE_SIMULATOR
        [env addEntriesFromDictionary:[[NSProcessInfo processInfo] environment]];
#endif
        sharedEnvironment = [env copy];
    });
    return sharedEnvironment;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _checkTimer = nil;
    _serviceRunning = NO;
    _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.trollvnc"];

    NSBundle *prefsBundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"TrollVNCPrefs"
                                                                                     ofType:@"bundle"]];

    NSString *presetPath = [prefsBundle pathForResource:@"Managed" ofType:@"plist"];
    if (presetPath) {
        NSDictionary *presetDefaults = [NSDictionary dictionaryWithContentsOfFile:presetPath];
        if (presetDefaults) {
            [_userDefaults registerDefaults:presetDefaults];
        }
    }
}

#pragma mark - Public Methods

- (void)registerServiceMonitor {
    [_checkTimer invalidate];
    [self checkTimerFired:nil];
    _checkTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                   target:self
                                                 selector:@selector(checkTimerFired:)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (BOOL)isServiceRunning {
    return _serviceRunning;
}

#pragma mark - Private Methods

- (void)checkTimerFired:(NSTimer *_Nullable)timer {
    [self ensureServiceRunning];
}

- (void)ensureServiceRunning {
    BOOL running = [self _isServiceRunning];
    if (!running) {
        if (TVNCDeviceIsActivelyJailbroken()) {
#if DEBUG
            NSLog(@"[TVNC] Active jailbreak detected; skip launching trollvncmanager");
#endif
            if (_serviceRunning) {
                _serviceRunning = NO;
                [[NSNotificationCenter defaultCenter] postNotificationName:TVNCServiceStatusDidChangeNotification
                                                                    object:self];
            }
            return;
        }
        [self checkPrebootDependencies];
        [self spawnService];
    }
    if (_serviceRunning != running) {
        _serviceRunning = running;
        [[NSNotificationCenter defaultCenter] postNotificationName:TVNCServiceStatusDidChangeNotification object:self];
    }
}

- (BOOL)_isServiceRunning {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        return NO;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kTvAlivePort);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int result = connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));
    close(sockfd);

    return result == 0;
#endif
}

- (void)spawnService {
    static TRTask *serviceTask = nil;
    serviceTask = [[TRTask alloc] init];

    NSString *executablePath = [[NSBundle mainBundle] pathForResource:@"trollvncmanager" ofType:@""];
    if (!executablePath) {
        return;
    }

    [serviceTask setExecutableURL:[NSURL fileURLWithPath:executablePath]];

#if !TARGET_IPHONE_SIMULATOR
    [serviceTask setUserIdentifier:0];
    [serviceTask setGroupIdentifier:0];
#endif

    [serviceTask setArguments:[NSArray array]];
    [serviceTask setEnvironment:[TVNCServiceCoordinator sharedTaskEnvironment]];

    NSError *error = nil;
    BOOL launched = [serviceTask launchAndReturnError:&error];
    if (!launched) {
#if DEBUG
        NSLog(@"[TVNC] Failed to launch service: %@", error);
#endif
        return;
    }

    int unused;
    waitpid(serviceTask.processIdentifier, &unused, WNOHANG);
}

- (void)checkPrebootDependencies {
#if !TARGET_IPHONE_SIMULATOR
    id configVal = [_userDefaults objectForKey:@"LaunchAtLogin"];

    NSString *appId = nil;
    if ([configVal isKindOfClass:[NSNumber class]]) {
        BOOL launchAtLogin = [(NSNumber *)configVal boolValue];
        if (launchAtLogin) {
            appId = [[NSBundle mainBundle] bundleIdentifier];
        }
    } else if ([configVal isKindOfClass:[NSString class]]) {
        appId = (NSString *)configVal;
    } else if ([configVal isKindOfClass:[NSArray class]]) {
        NSArray *appIds = (NSArray *)configVal;
        for (NSString *candidateAppId in appIds) {
            LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:candidateAppId];
            if (![appProxy isInstalled]) {
                continue;
            }
            appId = candidateAppId;
        }
    }

    if (!appId) {
        return;
    }

    NSDate *lastLaunch = [_userDefaults objectForKey:@"LastPrebootLaunch"];
    if (lastLaunch) {
        // Compare with device uptime
        NSTimeInterval uptime = [[NSProcessInfo processInfo] systemUptime];
        NSDate *bootTime = [NSDate dateWithTimeIntervalSinceNow:-uptime];
        if ([lastLaunch compare:bootTime] == NSOrderedDescending) {
            // Already launched since last boot
            return;
        }
    }

    UInt32 result;
    result = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(
        (__bridge CFStringRef)appId, NULL, NULL,
        (__bridge CFDictionaryRef) @{SBSApplicationLaunchOptionUnlockDeviceKey : @YES}, NO);

    if (result == 0) {
        NSDate *now = [NSDate date];
        [_userDefaults setObject:now forKey:@"LastPrebootLaunch"];
        [_userDefaults synchronize];
    }
#endif
}

@end
