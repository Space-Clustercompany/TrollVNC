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