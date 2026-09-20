#import <Foundation/Foundation.h>
// Experiment's entire IPC surface: no input, paths, commands, or mutations.
@protocol RGExperimentPing
- (void)pingWithReply:(void (^)(NSString *))reply;
@end
