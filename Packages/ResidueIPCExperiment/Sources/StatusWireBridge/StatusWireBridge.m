#import "StatusWireBridge.h"
#import <bsm/audit.h>
#import <Security/Security.h>
BOOL RGStatusCurrentAuditSession(int32_t *session) {
    auditinfo_addr_t info = {0};
    if (getaudit_addr(&info, sizeof(info)) != 0 || info.ai_asid <= AU_DEFAUDITSID) return NO;
    *session = info.ai_asid; return YES;
}
BOOL RGStatusConfigureRequirement(NSXPCConnection *connection, NSString *requirement) {
    SecRequirementRef compiled = NULL;
    if (SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &compiled) != errSecSuccess) return NO;
    CFRelease(compiled);
    @try { [connection setCodeSigningRequirement:requirement]; return YES; }
    @catch (NSException *exception) { return NO; }
}
NSXPCInterface *RGStatusInterface(void) {
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(RGStatusWire)];
    NSSet *allowed = [NSSet setWithObject:NSData.class];
    [interface setClasses:allowed forSelector:@selector(inspectFrame:reply:) argumentIndex:0 ofReply:NO];
    [interface setClasses:allowed forSelector:@selector(inspectFrame:reply:) argumentIndex:0 ofReply:YES];
    return interface;
}
