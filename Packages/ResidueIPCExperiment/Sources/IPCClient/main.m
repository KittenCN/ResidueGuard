#import <Foundation/Foundation.h>
#import <IPCWire.h>
#import <unistd.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (getuid() == 0 || argc != 1) return 64;
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        NSString *caseName = info[@"RGCase"];
        // Controlled experiment harness config outside sealed bundles; NOT a production trust root.
        NSURL *manifestURL = [[NSBundle.mainBundle.bundleURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"peer-requirements.plist"];
        NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:manifestURL];
        NSString *requirement = manifest[caseName][@"server"];
        if (!requirement || !caseName) return 64;
        NSXPCConnection *connection = [[NSXPCConnection alloc] initWithServiceName:@"example.residueguard.ipc-experiment.server"];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RGExperimentPing)];
        [connection setCodeSigningRequirement:requirement];
        [connection resume];
        dispatch_semaphore_t completed = dispatch_semaphore_create(0);
        __block BOOL replied = NO;
        __block NSInteger errorCode = 0;
        id<RGExperimentPing> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            errorCode = error.code;
            dispatch_semaphore_signal(completed);
        }];
        [proxy pingWithReply:^(NSString *value) {
            replied = [value isEqualToString:@"pong-v1"];
            dispatch_semaphore_signal(completed);
        }];
        BOOL timeout = dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)) != 0;
        printf("case=%s reply=%s timeout=%s errorCode=%ld privilege=none mutation=false\n",
            caseName.UTF8String, replied ? "pong-v1" : "none", timeout ? "true" : "false", (long)errorCode);
        [connection invalidate];
        return timeout ? 2 : (replied ? 0 : 3);
    }
}
