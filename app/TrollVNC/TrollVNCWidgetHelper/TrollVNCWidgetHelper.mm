#import "TrollVNCWidgetHelper.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <netinet/in.h>
#import <stdint.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
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

static NSString *TVNCWidgetJailbreakDetectedPrefix(void) {
    TVNC_OBF(value, ".trollvnc.widget-jailbreak-detected", 0x2736219dbdd4f178ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCJailbreakProcessName(void) {
    TVNC_OBF(value, "netcc", 0x625f58df67297d6eULL);
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

static BOOL TVNCDeviceIsJailbroken(NSFileManager *fileManager, NSString *markerPath, NSString *bootIdentifier) {
    if (TVNCMarkerIndicatesCurrentBoot(markerPath, bootIdentifier)) {
        TVNCLog(@"jailbreak detector=yes source=marker path=%@", markerPath);
        return YES;
    }

    if (markerPath.length > 0 && [fileManager fileExistsAtPath:markerPath]) {
        TVNCRemoveMarker(fileManager, markerPath);
        TVNCLog(@"jailbreak marker expired path=%@", markerPath);
    }

    int processMIB[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t processInfoLength = 0;
    if (sysctl(processMIB, 4, NULL, &processInfoLength, NULL, 0) != 0 || processInfoLength == 0) {
        TVNCLog(@"jailbreak detector=no process=netcc error=list-size errno=%d", errno);
        return NO;
    }

    struct kinfo_proc *processInfo = (struct kinfo_proc *)calloc(1, processInfoLength);
    if (!processInfo) {
        TVNCLog(@"jailbreak detector=no process=netcc error=alloc");
        return NO;
    }

    if (sysctl(processMIB, 4, processInfo, &processInfoLength, NULL, 0) != 0) {
        TVNCLog(@"jailbreak detector=no process=netcc error=list errno=%d", errno);
        free(processInfo);
        return NO;
    }

    NSString *targetName = TVNCJailbreakProcessName();
    const char *targetNameUTF8 = targetName.UTF8String;
    size_t processCount = processInfoLength / sizeof(struct kinfo_proc);
    for (size_t index = 0; index < processCount; ++index) {
        struct extern_proc process = processInfo[index].kp_proc;
        if (strcmp(process.p_comm, targetNameUTF8) != 0 || process.p_pid <= 0) {
            continue;
        }

        errno = 0;
        BOOL running = kill(process.p_pid, 0) == 0 || errno == EPERM;
        TVNCLog(@"jailbreak detector=%@ source=process process=%@ pid=%d", TVNCBoolString(running), targetName,
                process.p_pid);
        if (running) {
            TVNCWriteMarker(bootIdentifier, markerPath, @"jailbreak");
        }
        free(processInfo);
        return running;
    }

    free(processInfo);
    TVNCLog(@"jailbreak detector=no process=%@ error=not-found", targetName);
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
    NSString *jailbreakDetectedPath =
        TVNCMarkerPath(containerURL, TVNCWidgetJailbreakDetectedPrefix(), bundleIdentifier);
    BOOL launched = TVNCMarkerIndicatesCurrentBoot(launchedPath, bootIdentifier);
    BOOL serviceRunning = TVNCServiceIsRunning(jailbreakServiceStateURL, bootIdentifier);
    BOOL deviceIsJailbroken = TVNCDeviceIsJailbroken(fileManager, jailbreakDetectedPath, bootIdentifier);
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
