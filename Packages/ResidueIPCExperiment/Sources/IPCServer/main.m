#import <Foundation/Foundation.h>
#import <IPCWire.h>
#import <unistd.h>

@interface PingServer : NSObject <NSXPCListenerDelegate, RGExperimentPing>
@end
@implementation PingServer
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    // Fixed lab-level harness manifest, never IPC-supplied and not a production trust root.
    NSURL *lab = NSBundle.mainBundle.bundleURL;
    for (int i = 0; i < 4; ++i) lab = [lab URLByDeletingLastPathComponent];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:[lab URLByAppendingPathComponent:@"peer-requirements.plist"]];
    NSString *caseName = NSBundle.mainBundle.infoDictionary[@"RGCase"];
    NSString *requirement = manifest[caseName][@"client"];
    if (!requirement || connection.effectiveUserIdentifier != getuid()) return NO;
    // Public transport-enforced code identity, not a PID/path/self-reported identity check.
    [connection setCodeSigningRequirement:requirement];
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RGExperimentPing)];
    connection.exportedObject = self;
    connection.invalidationHandler = ^{ exit(0); };
    [connection resume];
    return YES;
}
- (void)pingWithReply:(void (^)(NSString *))reply { reply(@"pong-v1"); }
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (getuid() == 0) return 64;
        // Hard bound even if a connection fails before delegate invocation.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ exit(0); });
        PingServer *server = [PingServer new];
        NSXPCListener *listener = NSXPCListener.serviceListener;
        listener.delegate = server;
        [listener resume];
    }
    return 0;
}
