#import <Foundation/Foundation.h>
#include <stdint.h>
NS_ASSUME_NONNULL_BEGIN
@protocol RGStatusWire
- (void)inspectFrame:(NSData *)frame reply:(void (^)(NSData *))reply;
@end
// Public SDK wrappers only. No PID lookup, arbitrary executable, or audit token supplied by the peer.
BOOL RGStatusCurrentAuditSession(int32_t *session);
BOOL RGStatusConfigureRequirement(NSXPCConnection *connection, NSString *requirement);
NSXPCInterface *RGStatusInterface(void);
NS_ASSUME_NONNULL_END
