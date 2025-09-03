#import <Foundation/Foundation.h>
@interface GsMdns : NSObject <NSNetServiceDelegate>
@property(nonatomic,strong) NSNetService *svc;
@end
@implementation GsMdns
- (void)start:(NSString *)name port:(int)port {
  self.svc = [[NSNetService alloc] initWithDomain:@"local."
                                             type:@"_nvstream._tcp."
                                             name:name.length?name:@"TrollVNC"
                                             port:port];
  NSDictionary *txt = @{@"uuid": [[NSUUID UUID] UUIDString], @"srcvers": @"1.0", @"app": @"MoonlightServer"};
  [self.svc setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
  [self.svc publish];
}
- (void)stop { [self.svc stop]; self.svc = nil; }
@end
extern "C" void* gs_mdns_start(const char* name, int port) {
  @autoreleasepool { GsMdns *m = [GsMdns new]; [m start:[NSString stringWithUTF8String:name?name:"MoonlightServer"] port:port];
                     return (__bridge_retained void*)m; }
}
extern "C" void gs_mdns_stop(void* h) {
  @autoreleasepool { GsMdns *m = (__bridge_transfer GsMdns*)h; [m stop]; }
}