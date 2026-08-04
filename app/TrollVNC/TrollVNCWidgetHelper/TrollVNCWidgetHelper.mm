#import "TrollVNCWidgetHelper.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <netinet/in.h>
#import <stdint.h>
#import <string.h>
#import <sys/mount.h>
#import <sys/socket.h>
#import <sys/stat.h>
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

static BOOL TVNCPathExists(NSString *path) {
    struct stat info = {};
    return path.length > 0 && lstat(path.fileSystemRepresentation, &info) == 0;
}

static NSString *TVNCResolvedSymlinkAtPath(NSString *path) {
    struct stat info = {};
    if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISLNK(info.st_mode)) {
        return nil;
    }

    char destination[PATH_MAX + 1] = {};
    ssize_t length = readlink(path.fileSystemRepresentation, destination, PATH_MAX);
    if (length <= 0) {
        return nil;
    }
    destination[length] = '\0';

    NSString *resolved = [NSString stringWithUTF8String:destination];
    if (![resolved hasPrefix:@"/"]) {
        resolved = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:resolved];
    }
    return [resolved stringByStandardizingPath];
}

static BOOL TVNCRootlessBootstrapIsVisible(NSMutableArray<NSString *> *signals) {
    NSString *rootPath = @"/var/jb";
    if (!TVNCPathExists(rootPath)) {
        return NO;
    }

    NSString *resolvedRoot = TVNCResolvedSymlinkAtPath(rootPath) ?: rootPath;
    NSArray<NSString *> *relativeMarkers = @[
        @"basebin/jailbreakd",
        @"basebin/jbctl",
        @"procursus",
        @"usr/bin/dpkg",
        @"usr/lib/ellekit",
        @"Library/MobileSubstrate",
    ];

    for (NSString *marker in relativeMarkers) {
        if (TVNCPathExists([resolvedRoot stringByAppendingPathComponent:marker])) {
            [signals addObject:[NSString stringWithFormat:@"rootless-bootstrap:%@", marker]];
            return YES;
        }
    }

    if (![resolvedRoot isEqualToString:rootPath] &&
        [resolvedRoot hasPrefix:@"/private/preboot/"] && TVNCPathExists(resolvedRoot)) {
        [signals addObject:@"rootless-bootstrap:/var/jb-symlink"];
        return YES;
    }
    return NO;
}

typedef kern_return_t (*TVNCBootstrapLookupFunction)(mach_port_t, const char *, mach_port_t *);

static BOOL TVNCKnownJailbreakMachServiceIsReachable(NSMutableArray<NSString *> *signals) {
    TVNCBootstrapLookupFunction lookup =
        (TVNCBootstrapLookupFunction)dlsym(RTLD_DEFAULT, "bootstrap_look_up");
    if (!lookup) {
        return NO;
    }

    static const char *serviceNames[] = {
        "cy:com.saurik.substrated",
        "org.coolstar.jailbreakd",
        "jailbreakd",
        "cy:com.opa334.jailbreakd",
        "lh:com.opa334.jailbreakd",
        "com.opa334.jailbreakd",
    };

    BOOL detected = NO;
    for (const char *serviceName : serviceNames) {
        mach_port_t port = MACH_PORT_NULL;
        kern_return_t result = lookup(bootstrap_port, serviceName, &port);
        if (result == KERN_SUCCESS && MACH_PORT_VALID(port)) {
            [signals addObject:[NSString stringWithFormat:@"mach-service:%s", serviceName]];
            mach_port_deallocate(mach_task_self(), port);
            detected = YES;
        }
    }
    return detected;
}

static BOOL TVNCInjectedJailbreakLibraryIsLoaded(NSMutableArray<NSString *> *signals) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        needles = @[
            @"ellekit",
            @"libhooker",
            @"mobilesubstrate",
            @"substrateloader",
            @"substitute",
            @"tweakinject",
            @"roothideinit",
            @"systemhook.dylib",
        ];
    });

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; ++index) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) {
            continue;
        }
        NSString *lowercaseName = [[NSString stringWithUTF8String:imageName] lowercaseString];
        for (NSString *needle in needles) {
            if ([lowercaseName containsString:needle]) {
                [signals addObject:[NSString stringWithFormat:@"loaded-image:%@", needle]];
                return YES;
            }
        }
    }
    return NO;
}

static BOOL TVNCUnexpectedBindMountIsPresent(NSMutableArray<NSString *> *signals) {
    struct statfs *mounts = NULL;
    int count = getmntinfo(&mounts, MNT_NOWAIT);
    if (count <= 0 || !mounts) {
        return NO;
    }

    static const char *allowedMountPoints[] = {
        "/usr/standalone/firmware",
        "/System/Library/Pearl/ReferenceFrames",
        "/System/Library/Caches/com.apple.factorydata",
    };

    for (int index = 0; index < count; ++index) {
        if (strcmp(mounts[index].f_fstypename, "bindfs") != 0) {
            continue;
        }

        BOOL allowed = NO;
        for (const char *mountPoint : allowedMountPoints) {
            if (strcmp(mounts[index].f_mntonname, mountPoint) == 0) {
                allowed = YES;
                break;
            }
        }
        if (!allowed) {
            [signals addObject:[NSString stringWithFormat:@"bind-mount:%s", mounts[index].f_mntonname]];
            return YES;
        }
    }
    return NO;
}

static BOOL TVNCActiveRootfulJailbreakIsVisible(NSMutableArray<NSString *> *signals) {
    struct statfs rootFileSystem = {};
    if (statfs("/", &rootFileSystem) != 0 || strstr(rootFileSystem.f_mntfromname, "@") != NULL) {
        return NO;
    }

    NSArray<NSString *> *markers = @[
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/Library/MobileSubstrate/CydiaSubstrate.dylib",
        @"/usr/lib/libhooker.dylib",
        @"/usr/lib/libsubstitute.dylib",
        @"/Applications/Cydia.app",
        @"/usr/bin/dpkg",
        @"/etc/apt",
    ];

    NSUInteger matches = 0;
    for (NSString *marker in markers) {
        if (TVNCPathExists(marker) && ++matches >= 2) {
            [signals addObject:@"rootful-bootstrap:non-snapshot-root"];
            return YES;
        }
    }
    return NO;
}

static BOOL TVNCDeviceIsJailbroken(void) {
#if TARGET_OS_SIMULATOR
    TVNCLog(@"jailbreak detector=no signals=simulator");
    return NO;
#else
    NSMutableArray<NSString *> *signals = [NSMutableArray array];
    BOOL detected = NO;
    detected |= TVNCKnownJailbreakMachServiceIsReachable(signals);
    detected |= TVNCInjectedJailbreakLibraryIsLoaded(signals);
    detected |= TVNCRootlessBootstrapIsVisible(signals);
    detected |= TVNCUnexpectedBindMountIsPresent(signals);
    detected |= TVNCActiveRootfulJailbreakIsVisible(signals);

    TVNCLog(@"jailbreak detector=%@ signals=%@",
            TVNCBoolString(detected),
            signals.count > 0 ? [signals componentsJoinedByString:@","] : @"none");
    return detected;
#endif
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
    BOOL deviceIsJailbroken = TVNCDeviceIsJailbroken();
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
