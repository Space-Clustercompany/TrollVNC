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