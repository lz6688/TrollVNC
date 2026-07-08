#import "TrollVNCWidgetHelper.h"

#import <errno.h>
#import <stdint.h>
#import <signal.h>
#import <string.h>

FOUNDATION_EXPORT NSString *const SBSApplicationLaunchOptionUnlockDeviceKey;
FOUNDATION_EXPORT int SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(CFStringRef bundleIdentifier,
                                                                               CFURLRef url,
                                                                               CFDictionaryRef appOptions,
                                                                               CFDictionaryRef launchOptions,
                                                                               BOOL suspended);

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
    BOOL running = [fileManager fileExistsAtPath:launchedPath];
    if (!running) {
        running = TVNCPidFileIndicatesRunning(TVNCManagerPidPath()) || TVNCPidFileIndicatesRunning(TVNCServerPidPath());
    }

    if (running) {
        return kRunningColor;
    }

    NSString *markerContent = TVNCMarkerContent();
    [markerContent writeToFile:launchedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [markerContent writeToFile:TVNCMarkerPath(TVNCWidgetStartupNeedLockPrefix(), bundleIdentifier)
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:nil];

    NSDictionary *launchOptions = @{SBSApplicationLaunchOptionUnlockDeviceKey : @YES};
    int result = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions((__bridge CFStringRef)bundleIdentifier,
                                                                          NULL,
                                                                          NULL,
                                                                          (__bridge CFDictionaryRef)launchOptions,
                                                                          NO);
    return result == 0 ? kLaunchedColor : kRunningColor;
}

@end
