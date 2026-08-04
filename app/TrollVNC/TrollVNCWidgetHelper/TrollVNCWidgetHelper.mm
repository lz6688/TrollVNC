#import "TrollVNCWidgetHelper.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <signal.h>
#import <spawn.h>
#import <stdint.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/wait.h>
#import <unistd.h>

#import "../TrollVNC/Control.h"
#import "../../../include/TVNCSharedState.h"

FOUNDATION_EXPORT NSString *const SBSApplicationLaunchOptionUnlockDeviceKey;
FOUNDATION_EXPORT int SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(CFStringRef bundleIdentifier,
                                                                               CFURLRef url,
                                                                               CFDictionaryRef appOptions,
                                                                               CFDictionaryRef launchOptions,
                                                                               BOOL suspended);
FOUNDATION_EXPORT int SBSLaunchApplicationWithIdentifierAndLaunchOptions(CFStringRef bundleIdentifier,
                                                                         CFDictionaryRef appOptions,
                                                                         CFDictionaryRef launchOptions,
                                                                         BOOL suspended);
FOUNDATION_EXPORT void SBSLockDevice(void);

extern char **environ;

namespace tvnc_obf {

template <size_t N, uint64_t Key> class String {
  public:
    constexpr String(const char (&plain)[N]) : data_{} {
        for (size_t i = 0; i < N; ++i) {
            data_[i] = static_cast<char>(plain[i] ^ keyByte(i));
        }
    }

    const char *get() {
        if (!decrypted_) {
            for (size_t i = 0; i < N; ++i) {
                data_[i] = static_cast<char>(data_[i] ^ keyByte(i));
            }
            decrypted_ = true;
        }
        return data_;
    }

  private:
    static constexpr uint8_t keyByte(size_t index) {
        return static_cast<uint8_t>((Key >> (8 * (index % 8))) & 0xff);
    }

    char data_[N];
    bool decrypted_ = false;
};

template <size_t N, uint64_t Key> static NSString *makeNSString(String<N, Key> &value) {
    return [NSString stringWithUTF8String:value.get()];
}

} // namespace tvnc_obf

#define TVNC_OBF(name, literal, key)                                                                                    \
    static tvnc_obf::String<sizeof(literal), key> name(literal)

static NSString *TVNCWidgetBundleIdentifierKey(void) {
    TVNC_OBF(value, "XXT_BUNDLE_ID", 0x39e724ac9283fb83ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCDefaultBundleIdentifier(void) {
    TVNC_OBF(value, "com.82flex.TrollVNCApp", 0xc7875f43a19d2b26ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCWidgetLaunchedPrefix(void) {
    TVNC_OBF(value, ".trollvnc.widget-launched", 0x7d01e3db4520a811ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCWidgetStartupNeedLockPrefix(void) {
    TVNC_OBF(value, ".trollvnc.widget-startup-need-lock", 0xe4b475b39023d65aULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessLaunchctlPath(void) {
    TVNC_OBF(value, "/var/jb/usr/bin/launchctl", 0x5e71d9280cb4ac6bULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessDpkgStatusPath(void) {
    TVNC_OBF(value, "/var/jb/var/lib/dpkg/status", 0xa53030e8337e10a4ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessDpkgPath(void) {
    TVNC_OBF(value, "/var/jb/usr/bin/dpkg", 0x2ef6d4158ba7c139ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessJbctlPath(void) {
    TVNC_OBF(value, "/var/jb/basebin/jbctl", 0x97fa4f3db06d816cULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessTweakInjectPath(void) {
    TVNC_OBF(value, "/var/jb/usr/lib/TweakInject.dylib", 0x766e093172ccc9b6ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessMobileSubstratePath(void) {
    TVNC_OBF(value, "/var/jb/Library/MobileSubstrate/MobileSubstrate.dylib", 0x3f0d9685a8e9cd82ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessSileoPath(void) {
    TVNC_OBF(value, "/var/jb/Applications/Sileo.app", 0x37e2d45cedd90b91ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootlessZebraPath(void) {
    TVNC_OBF(value, "/var/jb/Applications/Zebra.app", 0x4d135cd3a4309e17ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulDpkgStatusPath(void) {
    TVNC_OBF(value, "/var/lib/dpkg/status", 0xfdb0c24ff9fbb513ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulDpkgPath(void) {
    TVNC_OBF(value, "/usr/bin/dpkg", 0x34de081aca507f3eULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulMobileSubstratePath(void) {
    TVNC_OBF(value, "/Library/MobileSubstrate/MobileSubstrate.dylib", 0x28d0bbdb667f2cb6ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulCydiaPath(void) {
    TVNC_OBF(value, "/Applications/Cydia.app", 0x1a5d102e9bc541faULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulSileoPath(void) {
    TVNC_OBF(value, "/Applications/Sileo.app", 0x5d4f76cb17b44829ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulZebraPath(void) {
    TVNC_OBF(value, "/Applications/Zebra.app", 0x946da65fdd6bd721ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulBashPath(void) {
    TVNC_OBF(value, "/bin/bash", 0xc0e6d4a59783ae5cULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCRootfulSshdPath(void) {
    TVNC_OBF(value, "/usr/sbin/sshd", 0x6afc8312ad3ae859ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCSBSPromptUnlockKeySymbol(void) {
    TVNC_OBF(value, "SBSApplicationLaunchOptionPromptUnlockKey", 0xf77b0dca2639d2d5ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCSBSURLUnlockKeySymbol(void) {
    TVNC_OBF(value, "SBSApplicationLaunchFromURLOptionUnlockDeviceKey", 0x51612e23a2860b09ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCMarkerPath(NSURL *containerURL, NSString *prefix, NSString *bundleIdentifier) {
    if (!containerURL) {
        return nil;
    }
    NSString *name = [NSString stringWithFormat:@"%@.%@", prefix, bundleIdentifier];
    return [[containerURL URLByAppendingPathComponent:name isDirectory:NO] path];
}

static NSString *TVNCBoolString(BOOL value) {
    return value ? @"yes" : @"no";
}

static void TVNCLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void TVNCLog(NSString *format, ...) {
    @autoreleasepool {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[TrollVNCWidgetHelper] pid=%d %@", getpid(), message);
    }
}

static BOOL TVNCWriteMarker(NSString *content, NSString *path, NSString *name) {
    if (content.length == 0 || path.length == 0) {
        TVNCLog(@"write %@ marker=no path=%@ error=shared state unavailable", name, path ?: @"-");
        return NO;
    }

    NSError *error = nil;
    BOOL ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    TVNCLog(@"write %@ marker=%@ path=%@ error=%@", name, TVNCBoolString(ok), path,
            error.localizedDescription ?: @"-");
    return ok;
}

static void TVNCRemoveMarker(NSFileManager *fileManager, NSString *path) {
    if (path.length > 0) {
        [fileManager removeItemAtPath:path error:nil];
    }
}

static BOOL TVNCMarkerIndicatesCurrentBoot(NSString *path, NSString *bootIdentifier) {
    if (path.length == 0) {
        return NO;
    }
    return TVNCStateAtURLMatchesBoot([NSURL fileURLWithPath:path], bootIdentifier);
}

static BOOL TVNCLoopbackServiceIsRunning(void) {
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD < 0) {
        return NO;
    }

    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(kTvAlivePort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    BOOL running = connect(socketFD, (struct sockaddr *)&address, sizeof(address)) == 0;
    close(socketFD);
    return running;
}

static BOOL TVNCServiceIsRunning(NSURL *jailbreakServiceStateURL, NSString *bootIdentifier) {
    return TVNCProcessInStateAtURLIsRunning(jailbreakServiceStateURL, bootIdentifier) ||
           TVNCLoopbackServiceIsRunning();
}

typedef NSString *(*TVNCPathProvider)(void);

static BOOL TVNCFileExistsAtAnyPath(NSFileManager *fileManager, const TVNCPathProvider *providers, size_t count) {
    for (size_t index = 0; index < count; ++index) {
        if ([fileManager fileExistsAtPath:providers[index]()]) {
            return YES;
        }
    }
    return NO;
}

static BOOL TVNCExecutableProbeSucceeds(NSString *path, NSArray<NSString *> *arguments, NSString *name) {
    NSUInteger argc = arguments.count + 2;
    char **argv = (char **)calloc(argc, sizeof(char *));
    if (!argv) {
        TVNCLog(@"jailbreak probe=%@ alloc failed", name);
        return NO;
    }

    argv[0] = strdup(path.fileSystemRepresentation);
    for (NSUInteger index = 0; index < arguments.count; ++index) {
        argv[index + 1] = strdup(arguments[index].UTF8String);
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
    for (NSUInteger index = 0; index < argc; ++index) {
        free(argv[index]);
    }
    free(argv);

    if (spawnResult != 0) {
        TVNCLog(@"jailbreak probe=%@ spawn failed errno=%d", name, spawnResult);
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
            TVNCLog(@"jailbreak probe=%@ wait failed errno=%d", name, errno);
            return NO;
        }
        usleep(100000);
    }

    if (!exited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        TVNCLog(@"jailbreak probe=%@ timed out", name);
        return NO;
    }

    BOOL succeeded = WIFEXITED(status) && WEXITSTATUS(status) == 0;
    TVNCLog(@"jailbreak probe=%@ exited=%@ status=%d", name, TVNCBoolString(succeeded), status);
    return succeeded;
}

static BOOL TVNCDeviceIsJailbroken(NSFileManager *fileManager) {
    static const TVNCPathProvider rootlessMarkers[] = {
        TVNCRootlessDpkgStatusPath,
        TVNCRootlessDpkgPath,
        TVNCRootlessJbctlPath,
        TVNCRootlessTweakInjectPath,
        TVNCRootlessMobileSubstratePath,
        TVNCRootlessSileoPath,
        TVNCRootlessZebraPath,
    };
    static const TVNCPathProvider rootfulMarkers[] = {
        TVNCRootfulDpkgStatusPath,
        TVNCRootfulMobileSubstratePath,
        TVNCRootfulCydiaPath,
        TVNCRootfulSileoPath,
        TVNCRootfulZebraPath,
        TVNCRootfulBashPath,
        TVNCRootfulSshdPath,
        TVNCRootfulDpkgPath,
    };

    BOOL hasRootlessMarkers =
        [fileManager fileExistsAtPath:TVNCRootlessLaunchctlPath()] &&
        TVNCFileExistsAtAnyPath(fileManager, rootlessMarkers, sizeof(rootlessMarkers) / sizeof(rootlessMarkers[0]));
    if (hasRootlessMarkers &&
        TVNCExecutableProbeSucceeds(TVNCRootlessLaunchctlPath(), @[ @"help" ], @"rootless launchctl")) {
        return YES;
    }

    if (!TVNCFileExistsAtAnyPath(fileManager, rootfulMarkers, sizeof(rootfulMarkers) / sizeof(rootfulMarkers[0]))) {
        return NO;
    }
    if ([fileManager fileExistsAtPath:TVNCRootfulBashPath()] &&
        TVNCExecutableProbeSucceeds(TVNCRootfulBashPath(), @[ @"-c", @":" ], @"rootful bash")) {
        return YES;
    }
    if ([fileManager fileExistsAtPath:TVNCRootfulDpkgPath()] &&
        TVNCExecutableProbeSucceeds(TVNCRootfulDpkgPath(), @[ @"--version" ], @"rootful dpkg")) {
        return YES;
    }
    return NO;
}

static void TVNCSetOptionalSBSBooleanOption(NSMutableDictionary *options, NSString *symbolName) {
    NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, [symbolName UTF8String]);
    if (key != NULL && *key != nil) {
        options[*key] = @YES;
    }
}

static NSDictionary *TVNCLaunchOptions(void) {
    NSMutableDictionary *options = [@{SBSApplicationLaunchOptionUnlockDeviceKey : @YES} mutableCopy];
    TVNCSetOptionalSBSBooleanOption(options, TVNCSBSPromptUnlockKeySymbol());
    TVNCSetOptionalSBSBooleanOption(options, TVNCSBSURLUnlockKeySymbol());
    return options;
}

static int TVNCLaunchApplication(NSString *bundleIdentifier, NSDictionary *launchOptions, NSUInteger maxAttempts) {
    CFDictionaryRef optionsRef = (__bridge CFDictionaryRef)launchOptions;
    CFStringRef bundleIdentifierRef = (__bridge CFStringRef)bundleIdentifier;
    int result = -1;

    for (NSUInteger attempt = 1; attempt <= maxAttempts; ++attempt) {
        result = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(bundleIdentifierRef,
                                                                          NULL,
                                                                          optionsRef,
                                                                          optionsRef,
                                                                          NO);
        TVNCLog(@"launch attempt=%lu primary=%d", (unsigned long)attempt, result);
        if (result == 0) {
            return result;
        }

        result = SBSLaunchApplicationWithIdentifierAndLaunchOptions(bundleIdentifierRef, optionsRef, optionsRef, NO);
        TVNCLog(@"launch attempt=%lu fallback=%d", (unsigned long)attempt, result);
        if (result == 0) {
            return result;
        }

        if (attempt < maxAttempts) {
            usleep(1000000);
        }
    }

    return result;
}

@implementation TrollVNCWidgetHelper

+ (NSTimeInterval)widgetRefreshInterval {
    NSTimeInterval interval = TVNCWidgetRefreshInterval();
    TVNCLog(@"timeline refresh requested after=%.0fs", interval);
    return interval;
}

+ (uint32_t)launchTrollVNCIfNecessary {
    static const uint32_t kRunningColor = 3502775;  // 0x003566E7
    static const uint32_t kLaunchedColor = 7632505; // 0x00746E69

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleIdentifier = [bundle objectForInfoDictionaryKey:TVNCWidgetBundleIdentifierKey()];
    if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) {
        bundleIdentifier = TVNCDefaultBundleIdentifier();
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *containerURL = TVNCAppGroupContainerURL();
    NSString *bootIdentifier = TVNCCurrentBootIdentifier();
    NSURL *jailbreakServiceStateURL = containerURL ? TVNCJailbreakServiceStateURL(containerURL) : nil;
    NSString *launchedPath = TVNCMarkerPath(containerURL, TVNCWidgetLaunchedPrefix(), bundleIdentifier);
    NSString *startupNeedLockPath =
        TVNCMarkerPath(containerURL, TVNCWidgetStartupNeedLockPrefix(), bundleIdentifier);
    BOOL launched = TVNCMarkerIndicatesCurrentBoot(launchedPath, bootIdentifier);
    BOOL serviceRunning = TVNCServiceIsRunning(jailbreakServiceStateURL, bootIdentifier);
    BOOL deviceIsJailbroken = TVNCDeviceIsJailbroken(fileManager);
    TVNCLog(@"begin bundle=%@ group=%@ boot=%@ launchedMarker=%@ service=%@ jailbreak=%@",
            bundleIdentifier,
            containerURL.path ?: @"-",
            bootIdentifier ?: @"-",
            TVNCBoolString(launched),
            TVNCBoolString(serviceRunning),
            TVNCBoolString(deviceIsJailbroken));

    if (deviceIsJailbroken) {
        if (serviceRunning) {
            if (launched) {
                TVNCLog(@"jailbreak service already running; skip app launch");
                return kRunningColor;
            }

            TVNCWriteMarker(bootIdentifier, launchedPath, @"launched");
            TVNCWriteMarker(bootIdentifier, startupNeedLockPath, @"need-lock");

            SBSLockDevice();
            TVNCLog(@"jailbreak service running; called lock device only");
            return kLaunchedColor;
        }

        TVNCRemoveMarker(fileManager, launchedPath);
        TVNCRemoveMarker(fileManager, startupNeedLockPath);
        TVNCLog(@"jailbreak detected and service stopped; skip app launch");
        return kRunningColor;
    }

    if (serviceRunning) {
        TVNCLog(@"service already running; skip launch");
        return kRunningColor;
    }

    TVNCWriteMarker(bootIdentifier, startupNeedLockPath, @"need-lock");

    int result = TVNCLaunchApplication(bundleIdentifier, TVNCLaunchOptions(), 3);
    if (result == 0) {
        TVNCWriteMarker(bootIdentifier, launchedPath, @"launched");
        TVNCLog(@"launch app succeeded");
        return kLaunchedColor;
    }

    TVNCRemoveMarker(fileManager, launchedPath);
    TVNCRemoveMarker(fileManager, startupNeedLockPath);
    TVNCLog(@"launch app failed; markers removed");
    return kRunningColor;
}

@end
