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