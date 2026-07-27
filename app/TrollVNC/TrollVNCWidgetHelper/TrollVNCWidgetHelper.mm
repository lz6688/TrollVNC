#import "TrollVNCWidgetHelper.h"

#import <errno.h>
#import <dlfcn.h>
#import <stdint.h>
#import <signal.h>
#import <string.h>

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
    TVNC_OBF(value, "/tmp/.trollvnc.widget-launched", 0x7d01e3db4520a811ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCWidgetStartupNeedLockPrefix(void) {
    TVNC_OBF(value, "/tmp/.trollvnc.widget-startup-need-lock", 0xe4b475b39023d65aULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCManagerPidPath(void) {
    TVNC_OBF(value, "/var/mobile/Library/Caches/com.82flex.trollvnc.manager.pid", 0x61c2a0b48fe73d09ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCServerPidPath(void) {
    TVNC_OBF(value, "/var/mobile/Library/Caches/com.82flex.trollvnc.server.pid", 0x462ea4a79afec383ULL);
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

static NSString *TVNCMarkerContent(void) {
    TVNC_OBF(value, "ok", 0x172b69f5d9b40c33ULL);
    return tvnc_obf::makeNSString(value);
}

static NSString *TVNCMarkerPath(NSString *prefix, NSString *bundleIdentifier) {
    return [NSString stringWithFormat:@"%@.%@", prefix, bundleIdentifier];
}

static BOOL TVNCPidFileIndicatesRunning(NSString *path) {
    NSString *pidText = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    pid_t pid = (pid_t)[pidText integerValue];
    if (pid <= 0) {
        return NO;
    }

    if (kill(pid, 0) == 0) {
        return YES;
    }

    return errno == EPERM;
}

static BOOL TVNCServicePidIndicatesRunning(void) {
    return TVNCPidFileIndicatesRunning(TVNCManagerPidPath()) || TVNCPidFileIndicatesRunning(TVNCServerPidPath());
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

static int TVNCLaunchApplication(NSString *bundleIdentifier, NSDictionary *launchOptions) {
    CFDictionaryRef optionsRef = (__bridge CFDictionaryRef)launchOptions;
    CFStringRef bundleIdentifierRef = (__bridge CFStringRef)bundleIdentifier;
    int result = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(bundleIdentifierRef,
                                                                          NULL,
                                                                          optionsRef,
                                                                          optionsRef,
                                                                          NO);
    if (result == 0) {
        return result;
    }

    return SBSLaunchApplicationWithIdentifierAndLaunchOptions(bundleIdentifierRef, optionsRef, optionsRef, NO);
}

typedef NSString *(*TVNCPathProvider)(void);

static BOOL TVNCFileExistsAtAnyPath(NSFileManager *fileManager, const TVNCPathProvider *providers, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if ([fileManager fileExistsAtPath:providers[i]()]) {
            return YES;
        }
    }

    return NO;
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
    };

    if ([fileManager fileExistsAtPath:TVNCRootlessLaunchctlPath()] &&
        TVNCFileExistsAtAnyPath(fileManager, rootlessMarkers, sizeof(rootlessMarkers) / sizeof(rootlessMarkers[0]))) {
        return YES;
    }

    return TVNCFileExistsAtAnyPath(fileManager, rootfulMarkers, sizeof(rootfulMarkers) / sizeof(rootfulMarkers[0]));
}

@implementation TrollVNCWidgetHelper

+ (uint32_t)launchTrollVNCIfNecessary {
    static const uint32_t kRunningColor = 3502775;  // 0x003566E7
    static const uint32_t kLaunchedColor = 7632505; // 0x00746E69

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleIdentifier = [bundle objectForInfoDictionaryKey:TVNCWidgetBundleIdentifierKey()];
    if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) {
        bundleIdentifier = TVNCDefaultBundleIdentifier();
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *launchedPath = TVNCMarkerPath(TVNCWidgetLaunchedPrefix(), bundleIdentifier);
    BOOL launched = [fileManager fileExistsAtPath:launchedPath];
    BOOL serviceRunning = TVNCServicePidIndicatesRunning();
    BOOL deviceIsJailbroken = TVNCDeviceIsJailbroken(fileManager);

    if (deviceIsJailbroken && serviceRunning) {
        if (launched) {
            return kRunningColor;
        }

        NSString *markerContent = TVNCMarkerContent();
        [markerContent writeToFile:launchedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [markerContent writeToFile:TVNCMarkerPath(TVNCWidgetStartupNeedLockPrefix(), bundleIdentifier)
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil];

        SBSLockDevice();
        return kLaunchedColor;
    }

    if (serviceRunning) {
        return kRunningColor;
    }

    NSString *markerContent = TVNCMarkerContent();
    NSString *startupNeedLockPath = TVNCMarkerPath(TVNCWidgetStartupNeedLockPrefix(), bundleIdentifier);
    [markerContent writeToFile:startupNeedLockPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    int result = TVNCLaunchApplication(bundleIdentifier, TVNCLaunchOptions());
    if (result == 0) {
        [markerContent writeToFile:launchedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return kLaunchedColor;
    }

    [fileManager removeItemAtPath:launchedPath error:nil];
    [fileManager removeItemAtPath:startupNeedLockPath error:nil];
    return kRunningColor;
}

@end
