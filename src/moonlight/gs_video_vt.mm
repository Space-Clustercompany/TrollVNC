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
    if (self.onNALU){ if(self->_vps){ self.onNALU(b,4,NO); self.onNALU((const uint8_t*)(const uint8_t*)self->_vps.bytes,self->_vps.length,NO); }
      self.onNALU(b,4,NO); self.onNALU((const uint8_t*)(const uint8_t*)self->_sps.bytes,self->_sps.length,NO);
      self.onNALU(b,4,NO); self.onNALU((const uint8_t*)(const uint8_t*)self->_pps.bytes,self->_pps.length,NO); }
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