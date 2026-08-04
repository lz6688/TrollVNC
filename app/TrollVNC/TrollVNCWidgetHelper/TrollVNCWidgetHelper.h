#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrollVNCWidgetHelper : NSObject
+ (uint32_t)launchTrollVNCIfNecessary;
+ (NSTimeInterval)widgetRefreshInterval;
@end

NS_ASSUME_NONNULL_END
