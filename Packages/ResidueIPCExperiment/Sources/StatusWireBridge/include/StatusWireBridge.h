#import <Foundation/Foundation.h>
#include <stdint.h>
NS_ASSUME_NONNULL_BEGIN
@protocol RGStatusWire
- (void)inspectFrame:(NSData *)frame reply:(void (^)(NSData *))reply;
@end
// Public SDK wrappers only. No PID lookup, arbitrary executable, or audit token supplied by the peer.
// 0=available, 1=query unavailable, 2=default/unknown; no identity values in diagnostics.
int32_t RGStatusAuditSessionResult(int32_t *session);
BOOL RGStatusCurrentAuditSession(int32_t *session);
BOOL RGStatusConfigureRequirement(NSXPCConnection *connection, NSString *requirement);
NSXPCInterface *RGStatusInterface(void);
NS_ASSUME_NONNULL_END
