#ifndef TVNC_SHARED_STATE_H
#define TVNC_SHARED_STATE_H

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#import <errno.h>
#import <math.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

static inline NSString *TVNCAppGroupIdentifier(void) {
    return @"group.com.82flex.TrollVNCApp";
}

static inline NSURL *TVNCAppGroupContainerURL(void) {
    return [[NSFileManager defaultManager]
        containerURLForSecurityApplicationGroupIdentifier:TVNCAppGroupIdentifier()];
}

static inline NSString *TVNCJailbreakServiceStateName(void) {
    return @".trollvnc.jailbreak-service";
}

static inline NSString *TVNCJailbreakDetectedStateName(void) {
    return @".trollvnc.widget-jailbreak-detected.com.82flex.TrollVNCApp";
}

static inline NSString *TVNCWidgetRefreshIntervalKey(void) {
    return @"WidgetRefreshIntervalSeconds";
}

static inline NSTimeInterval TVNCDefaultWidgetRefreshInterval(void) {
    return 5.0 * 60.0;
}

static inline NSTimeInterval TVNCSanitizedWidgetRefreshInterval(id value) {
    if (![value respondsToSelector:@selector(doubleValue)]) {
        return TVNCDefaultWidgetRefreshInterval();
    }

    NSTimeInterval interval = [value doubleValue];
    if (!isfinite(interval)) {
        return TVNCDefaultWidgetRefreshInterval();
    }
    return MIN(MAX(interval, 5.0), 60.0 * 60.0);
}

static inline NSUserDefaults *TVNCAppGroupDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:TVNCAppGroupIdentifier()];
}

static inline NSTimeInterval TVNCWidgetRefreshInterval(void) {
    id value = [TVNCAppGroupDefaults() objectForKey:TVNCWidgetRefreshIntervalKey()];
    return value ? TVNCSanitizedWidgetRefreshInterval(value) : TVNCDefaultWidgetRefreshInterval();
}

static inline BOOL TVNCWriteWidgetRefreshInterval(id value) {
    if (!TVNCAppGroupContainerURL()) {
        return NO;
    }

    NSUserDefaults *defaults = TVNCAppGroupDefaults();
    if (!defaults) {
        return NO;
    }

    [defaults setDouble:TVNCSanitizedWidgetRefreshInterval(value) forKey:TVNCWidgetRefreshIntervalKey()];
    [defaults synchronize];
    return YES;
}

static inline NSString *TVNCCurrentBootIdentifier(void) {
    struct timeval bootTime = {};
    size_t size = sizeof(bootTime);
    int mib[] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &bootTime, &size, NULL, 0) != 0 || size != sizeof(bootTime)) {
        return nil;
    }

    return [NSString stringWithFormat:@"%lld.%06d", (long long)bootTime.tv_sec, bootTime.tv_usec];
}

static inline NSURL *TVNCJailbreakServiceStateURL(NSURL *containerURL) {
    return [containerURL URLByAppendingPathComponent:TVNCJailbreakServiceStateName() isDirectory:NO];
}

static inline NSURL *TVNCJailbreakDetectedStateURL(NSURL *containerURL) {
    return [containerURL URLByAppendingPathComponent:TVNCJailbreakDetectedStateName() isDirectory:NO];
}

static inline BOOL TVNCStateAtURLMatchesBoot(NSURL *url, NSString *bootIdentifier) {
    if (!url || bootIdentifier.length == 0) {
        return NO;
    }

    NSString *value = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    NSString *storedBootIdentifier = [[value componentsSeparatedByCharactersInSet:
                                               [NSCharacterSet newlineCharacterSet]] firstObject];
    storedBootIdentifier =
        [storedBootIdentifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [storedBootIdentifier isEqualToString:bootIdentifier];
}

static inline BOOL TVNCProcessInStateAtURLIsRunning(NSURL *url, NSString *bootIdentifier) {
    if (!TVNCStateAtURLMatchesBoot(url, bootIdentifier)) {
        return NO;
    }

    NSString *value = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    NSArray<NSString *> *lines = [value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (lines.count < 2) {
        return NO;
    }

    pid_t pid = (pid_t)[lines[1] integerValue];
    if (pid <= 0) {
        return NO;
    }
    if (kill(pid, 0) == 0) {
        return YES;
    }
    return errno == EPERM;
}

static inline BOOL TVNCExecutableIsInsideAppBundle(NSString *executablePath) {
    for (NSString *component in executablePath.pathComponents) {
        if ([[component pathExtension] caseInsensitiveCompare:@"app"] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

static inline BOOL TVNCWriteJailbreakDetectedState(NSError **error) {
    NSURL *containerURL = TVNCAppGroupContainerURL();
    NSString *bootIdentifier = TVNCCurrentBootIdentifier();
    if (!containerURL || bootIdentifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.82flex.TrollVNC.SharedState"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey : @"App Group container or boot identifier unavailable"}];
        }
        return NO;
    }

    NSURL *stateURL = TVNCJailbreakDetectedStateURL(containerURL);
    NSError *writeError = nil;
    BOOL written = [bootIdentifier writeToURL:stateURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!written && error) {
        *error = writeError;
    }
    NSLog(@"[TrollVNCSharedState] write jailbreak marker=%@ path=%@ boot=%@ error=%@",
          written ? @"yes" : @"no",
          stateURL.path,
          bootIdentifier,
          writeError.localizedDescription ?: @"-");
    if (written) {
        chmod(stateURL.fileSystemRepresentation, 0644);
        chown(stateURL.fileSystemRepresentation, 501, 501);
    }
    return written;
}

static inline BOOL TVNCWriteJailbreakServiceState(NSString *executablePath, NSError **error) {
#if TARGET_OS_SIMULATOR
    return YES;
#else
    if (TVNCExecutableIsInsideAppBundle(executablePath)) {
        return YES;
    }

    NSURL *containerURL = TVNCAppGroupContainerURL();
    NSString *bootIdentifier = TVNCCurrentBootIdentifier();
    if (!containerURL || bootIdentifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.82flex.TrollVNC.SharedState"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : @"App Group container or boot identifier unavailable"}];
        }
        return NO;
    }

    NSURL *stateURL = TVNCJailbreakServiceStateURL(containerURL);
    NSString *state = [NSString stringWithFormat:@"%@\n%d\n", bootIdentifier, getpid()];
    BOOL written = [state writeToURL:stateURL atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (written) {
        chmod(stateURL.fileSystemRepresentation, 0644);
        chown(stateURL.fileSystemRepresentation, 501, 501);
    }
    return written;
#endif
}

#endif
