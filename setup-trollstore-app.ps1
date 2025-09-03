# save as add-moonlight-video.ps1 and run:  powershell -ExecutionPolicy Bypass -File .\add-moonlight-video.ps1
$ErrorActionPreference='Stop'
function Ensure-Dir($p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function W($p,$t){ $d=Split-Path -Parent $p; if($d){Ensure-Dir $d}; Set-Content -Path $p -Value $t -NoNewline -Encoding UTF8; Write-Host "Wrote $p" }

# App (UI + server bootstrap in one file)
$appMain = @'
#import <UIKit/UIKit.h>
extern "C" int gs_run_server(const char* name, struct GsPorts ports, struct GsVideoProfile prof);
struct GsPorts { int http, https, rtsp, video, control, audio; };
struct GsVideoProfile { int width, height, fps, bitrateKbps; bool hevc; };

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary*)opts {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor systemBackgroundColor];
  UILabel *label = [UILabel new];
  label.text = @"MoonlightServer (video-only) is running.\nFind this device in Moonlight.";
  label.numberOfLines = 0; label.textAlignment = NSTextAlignmentCenter; label.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    [label.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:20.0],
    [label.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-20.0]
  ]];
  self.window.rootViewController = vc; [self.window makeKeyAndVisible];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    struct GsPorts p = {47989, 47984, 48010, 47998, 47999, 48000};
    struct GsVideoProfile prof = {1920, 1080, 60, 12000, false};
    gs_run_server("Moonlight iPhone", p, prof);
  });
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
'@

# Info.plist (Local Network + Bonjour)
$infoPlist = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>MoonlightServer</string>
  <key>CFBundleExecutable</key><string>MoonlightServer</string>
  <key>CFBundleIdentifier</key><string>com.example.trollmoonlight</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MoonlightServer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>14.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UIRequiresFullScreen</key><true/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>This app streams video to Moonlight clients on your local network and needs LAN access for discovery and streaming.</string>
  <key>NSBonjourServices</key>
  <array><string>_nvstream._tcp</string></array>
</dict></plist>
'@

# Entitlements (optional multicast helps Bonjour; TrollStore preserves entitlements you embed)
$entitlements = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.developer.networking.multicast</key><true/>
</dict></plist>
'@

# Moonlight transport: mDNS
$gs_mdns = @'
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
'@

# VideoToolbox H.264 (Annex-B)
$gs_video_vt = @'
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
typedef void (^NALUCallback)(const uint8_t* data, size_t len, BOOL isKey);
@interface GsVTEncoder : NSObject
- (instancetype)initWithWidth:(int)w height:(int)h fps:(int)fps bitrateKbps:(int)kbps hevc:(BOOL)hevc;
- (void)encode:(CVPixelBufferRef)pb pts:(CMTime)pts;
@property(nonatomic,copy) NALUCallback onNALU;
@end
@implementation GsVTEncoder { VTCompressionSessionRef _sess; NSData *_sps,*_pps,*_vps; int _fps; }
static void vt_cb(void *ref, void *srcRefCon, OSStatus st, VTEncodeInfoFlags info, CMSampleBufferRef sbuf) {
  if (st || !CMSampleBufferDataIsReady(sbuf)) return;
  GsVTEncoder *self = (__bridge GsVTEncoder*)ref;
  if (!self->_sps) {
    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sbuf);
    FourCharCode ct = CMFormatDescriptionGetMediaSubType(fmt);
    if (ct == kCMVideoCodecType_H264) {
      const uint8_t *ps; size_t len;
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt,0,&ps,&len,NULL,NULL); self->_sps=[NSData dataWithBytes:ps length:len];
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt,1,&ps,&len,NULL,NULL); self->_pps=[NSData dataWithBytes:ps length:len];
    } else {
      const uint8_t *vps,*sps,*pps; size_t lv,ls,lp;
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt,0,&vps,&lv,NULL,NULL);
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt,1,&sps,&ls,NULL,NULL);
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt,2,&pps,&lp,NULL,NULL);
      self->_vps=[NSData dataWithBytes:vps length:lv]; self->_sps=[NSData dataWithBytes:sps length:ls]; self->_pps=[NSData dataWithBytes:pps length:lp];
    }
    uint8_t b[4]={0,0,0,1};
    if (self.onNALU){ if(self->_vps){ self.onNALU(b,4,NO); self.onNALU(self->_vps.bytes,self->_vps.length,NO); }
      self.onNALU(b,4,NO); self.onNALU(self->_sps.bytes,self->_sps.length,NO);
      self.onNALU(b,4,NO); self.onNALU(self->_pps.bytes,self->_pps.length,NO); }
  }
  CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sbuf);
  size_t off=0,total=CMBlockBufferGetDataLength(bb);
  while (off+4<=total) {
    uint32_t nalsz=0; CMBlockBufferCopyDataBytes(bb,off,4,&nalsz); nalsz=CFSwapInt32BigToHost(nalsz); off+=4;
    uint8_t *nal=(uint8_t*)malloc(nalsz+4); nal[0]=nal[1]=nal[2]=0; nal[3]=1;
    CMBlockBufferCopyDataBytes(bb,off,nalsz,nal+4);
    BOOL isKey=(nalsz>0 && ((nal[4]&0x1F)==5));
    if(self.onNALU) self.onNALU(nal,nalsz+4,isKey);
    free(nal); off+=nalsz;
  }
}
- (instancetype)initWithWidth:(int)w height:(int)h fps:(int)fps bitrateKbps:(int)kbps hevc:(BOOL)hevc {
  if ((self=[super init])) {
    _fps=fps;
    VTCompressionSessionCreate(NULL,w,h,hevc?kCMVideoCodecType_HEVC:kCMVideoCodecType_H264,NULL,NULL,NULL,vt_cb,(__bridge void*)self,&_sess);
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_RealTime,kCFBooleanTrue);
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse);
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_ExpectedFrameRate,(__bridge CFNumberRef)@(_fps));
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_AverageBitRate,(__bridge CFNumberRef)@(kbps*1000));
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_DataRateLimits,(__bridge CFArrayRef)@[@(kbps*1000),@1]);
    VTSessionSetProperty(_sess,kVTCompressionPropertyKey_MaxKeyFrameInterval,(__bridge CFNumberRef)@(_fps*2));
    VTCompressionSessionPrepareToEncodeFrames(_sess);
  } return self;
}
- (void)encode:(CVPixelBufferRef)pb pts:(CMTime)pts { VTEncodeInfoFlags f=0; VTCompressionSessionEncodeFrame(_sess,pb,pts,kCMTimeInvalid,NULL,NULL,&f); }
@end
'@

# RTP/H.264
$gs_rtp = @'
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <string.h>
#include <vector>
#include <algorithm>
class Rtp264Sender {
  int sock=-1; struct sockaddr_in dst{}; uint16_t seq=1; uint32_t ssrc=0x13579BDF; uint32_t ts=0;
public:
  bool open(const char* host,int port){ sock=socket(AF_INET,SOCK_DGRAM,0); if(sock<0)return false;
    memset(&dst,0,sizeof(dst)); dst.sin_family=AF_INET; dst.sin_port=htons(port);
    if(inet_pton(AF_INET,host,&dst.sin_addr)!=1) return false; return true; }
  void setTimestamp(uint32_t t){ ts=t; } void tick(uint32_t inc){ ts+=inc; }
  void sendAnnexB(const uint8_t* a,size_t len,bool mark){
    const uint8_t *n=a+4; size_t nlen=len-4; const size_t MTU=1200;
    if(nlen<=MTU) sendPacket(n,nlen,mark);
    else { uint8_t nalHdr=n[0], fuInd=(nalHdr&0xE0)|28; size_t off=1; bool start=true;
      while(off<nlen){ size_t chunk=std::min(MTU-2,nlen-off);
        std::vector<uint8_t> fu(2+chunk); fu[0]=fuInd; fu[1]=((start?0x80:0x00)|((off+chunk>=nlen)?0x40:0x00)|(nalHdr&0x1F));
        memcpy(&fu[2],n+off,chunk); sendPacket(fu.data(),fu.size(),(off+chunk>=nlen)&&mark);
        off+=chunk; start=false; } }
  }
private:
  void sendPacket(const uint8_t* p,size_t plen,bool mark){
    uint8_t hdr[12]={0x80,(uint8_t)(96|(mark?0x80:0x00)),(uint8_t)(seq>>8),(uint8_t)(seq&0xff),
                    (uint8_t)(ts>>24),(uint8_t)(ts>>16),(uint8_t)(ts>>8),(uint8_t)ts,0x13,0x57,0x9B,0xDF};
    struct iovec iov[2]={{hdr,12},{(void*)p,(size_t)plen}};
    struct msghdr msg={(void*)&dst,sizeof(dst),iov,2,0,0,0};
    sendmsg(sock,&msg,0); seq++;
  }
};
extern "C" void* rtp264_open(const char* host,int port){ Rtp264Sender* s=new Rtp264Sender(); if(!s->open(host,port)){ delete s; return nullptr;} return s; }
extern "C" void  rtp264_set_ts(void* h,uint32_t t){ ((Rtp264Sender*)h)->setTimestamp(t); }
extern "C" void  rtp264_tick(void* h,uint32_t inc){ ((Rtp264Sender*)h)->tick(inc); }
extern "C" void  rtp264_send_nalu(void* h,const uint8_t* d,size_t l,int mark){ ((Rtp264Sender*)h)->sendAnnexB(d,l,mark); }
extern "C" void  rtp264_close(void* h){ delete ((Rtp264Sender*)h); }
'@

# Test pattern frame source
$testpat = @'
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>
extern "C" CVPixelBufferRef gs_testpattern_frame(int w,int h,int t){
  CVPixelBufferRef pb; NSDictionary *attrs=@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
  CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)attrs,&pb);
  CVPixelBufferLockBaseAddress(pb,0); uint8_t* base=(uint8_t*)CVPixelBufferGetBaseAddress(pb); size_t stride=CVPixelBufferGetBytesPerRow(pb);
  for(int y=0;y<h;++y){ uint8_t* row=base+y*stride; for(int x=0;x<w;++x){ int bar=(x*6)/w; uint8_t r=0,g=0,b=0;
      switch(bar){case 0:r=255;break;case 1:r=255;g=255;break;case 2:g=255;break;case 3:g=255;b=255;break;case 4:b=255;break;default:r=255;b=255;break;}
      r=(r+(t%255))%256; row[x*4+0]=b; row[x*4+1]=g; row[x*4+2]=r; row[x*4+3]=0xFF; } }
  int bx=(t*5)%(w-100), by=(t*3)%(h-80);
  for(int y=by;y<by+80 && y<h;++y){ uint8_t* row=base+y*stride; for(int x=bx;x<bx+100 && x<w;++x){ row[x*4+0]=0; row[x*4+1]=0; row[x*4+2]=0; row[x*4+3]=0xFF; } }
  CVPixelBufferUnlockBaseAddress(pb,0); return pb;
}
'@

# RTSP + NVHTTP stub + glue
$gs_rtsp = @'
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <pthread.h>
#import <string.h>

struct GsPorts { int http, https, rtsp, video, control, audio; };
struct GsVideoProfile { int width, height, fps, bitrateKbps; bool hevc; };

extern "C" void* gs_mdns_start(const char* name, int port);
extern "C" void  gs_mdns_stop(void* handle);
extern "C" CVPixelBufferRef gs_testpattern_frame(int w, int h, int t);

@interface GsVTEncoder : NSObject
- (instancetype)initWithWidth:(int)w height:(int)h fps:(int)fps bitrateKbps:(int)kbps hevc:(BOOL)hevc;
- (void)encode:(CVPixelBufferRef)pb pts:(CMTime)pts;
@property(nonatomic,copy) void (^onNALU)(const uint8_t* data, size_t len, BOOL isKey);
@end
extern "C" void* rtp264_open(const char* host, int port);
extern "C" void  rtp264_set_ts(void* h, uint32_t t);
extern "C" void  rtp264_tick(void* h, uint32_t inc);
extern "C" void  rtp264_send_nalu(void* h, const uint8_t* data, size_t len, int mark);
extern "C" void  rtp264_close(void* h);

static NSString* b64(NSData* d){ return [d base64EncodedStringWithOptions:0]; }
static NSString* make_sdp(NSData* sps, NSData* pps, int clock) {
  NSString *spsb=b64(sps), *ppsb=b64(pps);
  return [NSString stringWithFormat:
    @"v=0\r\n"
     "o=- 0 0 IN IP4 0.0.0.0\r\n"
     "s=Moonlight iOS\r\n"
     "t=0 0\r\n"
     "m=video 0 RTP/AVP 96\r\n"
     "a=rtpmap:96 H264/%d\r\n"
     "a=fmtp:96 packetization-mode=1; profile-level-id=42e01f; sprop-parameter-sets=%@,%@\r\n"
     "a=control:trackID=1\r\n", clock, spsb, ppsb];
}
static int tcp_listen(int port){ int fd=socket(AF_INET,SOCK_STREAM,0), yes=1; setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
  struct sockaddr_in a{}; a.sin_family=AF_INET; a.sin_addr.s_addr=INADDR_ANY; a.sin_port=htons(port);
  bind(fd,(struct sockaddr*)&a,sizeof(a)); listen(fd,4); return fd; }
static NSString* http_readline(int fd){ NSMutableData *buf=[NSMutableData data]; char c; while(read(fd,&c,1)==1){ [buf appendBytes:&c length:1];
  if(buf.length>=2){ const char* p=(const char*)buf.bytes; if(p[buf.length-2]=='\r' && p[buf.length-1]=='\n') break; } }
  return [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding]; }
static void http_write(int fd, NSString* s){ NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding]; write(fd,d.bytes,d.length); }

static void* pairing_http(void* arg){ int port = *(int*)arg; int lfd=tcp_listen(port);
  while(1){ int cfd=accept(lfd,NULL,NULL); if(cfd<0) continue;
    // read req (ignore body)
    while(true){ NSString* line=http_readline(cfd); if(!line || [line isEqualToString:@"\r\n"]) break; }
    // very small dev stub (paired=true)
    NSString* body=@"{\"status\":\"ok\",\"paired\":true}\n";
    NSString* resp=[NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@",
                    (unsigned long)body.length, body];
    http_write(cfd,resp); close(cfd);
  } return NULL;
}

static NSString* read_request(int fd, NSMutableDictionary** headers, NSString** startLine) {
  NSMutableDictionary *h=[NSMutableDictionary dictionary]; NSString *line=http_readline(fd); if(startLine)*startLine=line;
  while(true){ NSString *l=http_readline(fd); if(!l || [l isEqualToString:@"\r\n"]) break;
    NSRange r=[l rangeOfString:@": "]; if(r.location!=NSNotFound){ NSString *k=[l substringToIndex:r.location];
      NSString *v=[[l substringFromIndex:r.location+2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; h[k]=v; } }
  if(headers)*headers=h; return line;
}
static void rtsp_write(int fd, NSString* s){ http_write(fd,s); }

static void* rtsp_thread(void* arg){
  struct { GsPorts ports; GsVideoProfile prof; char name[128]; } *cfg = (decltype(cfg))arg;
  void* mdns = gs_mdns_start(cfg->name, cfg->ports.http); // advertise _nvstream._tcp via NVHTTP port
  pthread_t th_pair; pthread_create(&th_pair,NULL,pairing_http,&cfg->ports.http);

  __block GsVTEncoder *enc=[[GsVTEncoder alloc] initWithWidth:cfg->prof.width height:cfg->prof.height fps:cfg->prof.fps bitrateKbps:cfg->prof.bitrateKbps hevc:NO];
  __block void* rtp=NULL; __block NSData *lastSPS=nil,*lastPPS=nil;
  enc.onNALU=^(const uint8_t* data,size_t len,BOOL isKey){
    if(!lastSPS && len>4){ uint8_t t=data[4]&0x1F; if(t==7) lastSPS=[NSData dataWithBytes:data+4 length:len-4];
                            if(t==8) lastPPS=[NSData dataWithBytes:data+4 length:len-4]; }
    if(rtp) rtp264_send_nalu(rtp,data,len,isKey?1:0);
  };

  int lfd=tcp_listen(cfg->ports.rtsp);
  while(1){
    int cfd=accept(lfd,NULL,NULL); if(cfd<0) continue;
    NSString *start; NSMutableDictionary *h; read_request(cfd,&h,&start);
    NSString* cseq=h[@"CSeq"]?:@"1";
    if([start hasPrefix:@"OPTIONS"]){
      NSString* resp=[NSString stringWithFormat:@"RTSP/1.0 200 OK\r\nCSeq: %@\r\nPublic: OPTIONS,DESCRIBE,SETUP,TEARDOWN,PLAY,PAUSE\r\n\r\n",cseq];
      rtsp_write(cfd,resp);
    } else if([start hasPrefix:@"DESCRIBE"]){
      CVPixelBufferRef pb=gs_testpattern_frame(cfg->prof.width,cfg->prof.height,0); [enc encode:pb pts:CMTimeMake(0,90000)]; CFRelease(pb);
      NSString* sdp=make_sdp(lastSPS,lastPPS,90000);
      NSString* resp=[NSString stringWithFormat:@"RTSP/1.0 200 OK\r\nCSeq: %@\r\nContent-Type: application/sdp\r\nContent-Length: %lu\r\n\r\n%@",
                      cseq,(unsigned long)[sdp lengthOfBytesUsingEncoding:NSUTF8StringEncoding],sdp];
      rtsp_write(cfd,resp);
    } else if([start hasPrefix:@"SETUP"]){
      NSString* transport=h[@"Transport"]; int cport=cfg->ports.video;
      if(transport){ NSScanner *sc=[NSScanner scannerWithString:transport]; [sc scanUpToString:@"client_port=" intoString:NULL];
        if(![sc isAtEnd]){ [sc scanString:@"client_port=" intoString:NULL]; [sc scanInt:&cport]; } }
      if(rtp){ rtp264_close(rtp); rtp=NULL; }
      struct sockaddr_in peer; socklen_t plen=sizeof(peer); getpeername(cfd,(struct sockaddr*)&peer,&plen);
      char ipbuf[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&peer.sin_addr,ipbuf,sizeof(ipbuf));
      rtp=rtp264_open(ipbuf,cport);
      NSString* resp=[NSString stringWithFormat:
        @"RTSP/1.0 200 OK\r\nCSeq: %@\r\nTransport: RTP/AVP;unicast;client_port=%d-%d;server_port=%d-%d\r\nSession: 1\r\n\r\n",
        cseq,cport,cport+1,cfg->ports.video,cfg->ports.video+1];
      rtsp_write(cfd,resp);
    } else if([start hasPrefix:@"PLAY"]){
      NSString* resp=[NSString stringWithFormat:@"RTSP/1.0 200 OK\r\nCSeq: %@\r\nSession: 1\r\nRTP-Info: url=rtsp://0.0.0.0/trackID=1;seq=1\r\n\r\n",cseq];
      rtsp_write(cfd,resp);
      uint32_t tick=90000/(cfg->prof.fps>0?cfg->prof.fps:1); rtp264_set_ts(rtp,0);
      for(int i=1;;++i){ CVPixelBufferRef pb=gs_testpattern_frame(cfg->prof.width,cfg->prof.height,i);
        [enc encode:pb pts:CMTimeMake(i*tick,90000)]; rtp264_tick(rtp,tick); usleep(1000000/(cfg->prof.fps>0?cfg->prof.fps:1)); CFRelease(pb); }
    } else {
      NSString* resp=[NSString stringWithFormat:@"RTSP/1.0 501 Not Implemented\r\nCSeq: %@\r\n\r\n",cseq];
      rtsp_write(cfd,resp);
    }
    close(cfd);
  }
  gs_mdns_stop(mdns); return NULL;
}

extern "C" int gs_run_server(const char* name, struct GsPorts ports, struct GsVideoProfile prof){
  pthread_t th; struct { GsPorts ports; GsVideoProfile prof; char name[128]; } cfg;
  cfg.ports=ports; cfg.prof=prof; strncpy(cfg.name,name?name:"MoonlightServer",sizeof(cfg.name)-1);
  pthread_create(&th,NULL,rtsp_thread,&cfg); pthread_join(th,NULL); return 0;
}
'@

# Write all files
W 'src\moonlight\app\AppMain.mm' $appMain
W 'src\moonlight\app\Info.plist' $infoPlist
W 'entitlements.trollstore.plist' $entitlements
W 'src\moonlight\gs_mdns.mm' $gs_mdns
W 'src\moonlight\gs_video_vt.mm' $gs_video_vt
W 'src\moonlight\gs_rtp_video.cpp' $gs_rtp
W 'src\moonlight\test_pattern.mm' $testpat
W 'src\moonlight\gs_rtsp.mm' $gs_rtsp

Write-Host "`nDone. Now commit & push:"
Write-Host "  git add ."
Write-Host "  git commit -m 'Add Moonlight video transport (mDNS + RTSP + RTP/H.264)'"
Write-Host "  git push"
