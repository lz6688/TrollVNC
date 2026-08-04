#import "../include/TVNCJailbreakState.h"
#import "../include/TVNCSharedState.h"

#import <errno.h>
#import <string.h>
#import <sys/sysctl.h>
#import <unistd.h>

static NSError *TVNCJailbreakStateError(int code, NSString *description) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : description}];
}

BOOL TVNCUpdateJailbreakStateFromNetcc(NSError **error) {
    if (error) {
        *error = nil;
    }

    NSURL *containerURL = TVNCAppGroupContainerURL();
    NSString *bootIdentifier = TVNCCurrentBootIdentifier();
    NSURL *stateURL = containerURL ? TVNCJailbreakDetectedStateURL(containerURL) : nil;
    if (stateURL && TVNCStateAtURLMatchesBoot(stateURL, bootIdentifier)) {
        NSLog(@"[TrollVNCJailbreakState] detector=yes source=marker path=%@", stateURL.path);
        return YES;
    }

    int processMIB[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t processInfoLength = 0;
    if (sysctl(processMIB, 4, NULL, &processInfoLength, NULL, 0) != 0 || processInfoLength == 0) {
        int code = errno ?: EIO;
        if (error) {
            *error = TVNCJailbreakStateError(code, @"Unable to read process list size");
        }
        NSLog(@"[TrollVNCJailbreakState] detector=no source=process error=list-size errno=%d", code);
        return NO;
    }

    processInfoLength += sizeof(struct kinfo_proc) * 16;
    struct kinfo_proc *processInfo = (struct kinfo_proc *)calloc(1, processInfoLength);
    if (!processInfo) {
        if (error) {
            *error = TVNCJailbreakStateError(ENOMEM, @"Unable to allocate process list");
        }
        NSLog(@"[TrollVNCJailbreakState] detector=no source=process error=alloc");
        return NO;
    }

    if (sysctl(processMIB, 4, processInfo, &processInfoLength, NULL, 0) != 0) {
        int code = errno;
        free(processInfo);
        if (error) {
            *error = TVNCJailbreakStateError(code, @"Unable to read process list");
        }
        NSLog(@"[TrollVNCJailbreakState] detector=no source=process error=list errno=%d", code);
        return NO;
    }

    static const char targetName[] = "netcc";
    size_t processCount = processInfoLength / sizeof(struct kinfo_proc);
    for (size_t index = 0; index < processCount; ++index) {
        struct extern_proc process = processInfo[index].kp_proc;
        if (process.p_pid <= 0 || strcmp(process.p_comm, targetName) != 0) {
            continue;
        }

        errno = 0;
        int processCheck = kill(process.p_pid, 0);
        int processCheckError = errno;
        if (processCheck != 0 && processCheckError != EPERM) {
            continue;
        }

        pid_t processIdentifier = process.p_pid;
        free(processInfo);

        NSError *writeError = nil;
        BOOL written = TVNCWriteJailbreakDetectedState(&writeError);
        NSLog(@"[TrollVNCJailbreakState] detector=yes source=process process=netcc pid=%d marker=%@ path=%@ error=%@",
              processIdentifier,
              written ? @"yes" : @"no",
              stateURL.path ?: @"-",
              writeError.localizedDescription ?: @"-");
        if (!written && error) {
            *error = writeError;
        }
        return written;
    }

    free(processInfo);
    NSLog(@"[TrollVNCJailbreakState] detector=no source=process process=netcc error=not-found");
    return NO;
}
