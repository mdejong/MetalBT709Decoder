//
//  ViewController.m
//  CoreVideoDecodeiOS
//
//  Created by Mo DeJong on 1/23/19.
//  Copyright © 2019 Apple. All rights reserved.
//

#import "ViewController.h"

#import "BGDecodeEncode.h"

#import "CGFrameBuffer.h"

@interface ViewController ()

@property (nonatomic, retain) IBOutlet UIImageView *imageView;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSAssert(self.imageView, @"imageView");
  
  // Decode a single frame of H264 video to YCbCr data contained in a CoreVideo buffer
  
  //NSString *resFilename = @"QuickTime_Test_Pattern_HD.mov";
  //NSString *resFilename = @"Rec709Sample.mp4";
  NSString *resFilename = @"Gamma_test_HD_75Per_24BPP_sRGB_HD.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(1920, 1080)
                                                                       aveBitrate:0];
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  NSLog(@"returned %d YCbCr texture : %d x %d", (int)cvPixelBuffers.count, width, height);
  
  // Access the default HDTV -> sRGB conversion used by CoreVideo via CoreImage API
  // that accepts a YCbCr tagged buffer.
  
  CIImage *rgbFromCVImage = [CIImage imageWithCVPixelBuffer:cvPixelBuffer];
  
  CIContext *context = [CIContext contextWithOptions:nil];
  
  CGImageRef outCGImageRef = [context createCGImage:rgbFromCVImage fromRect:rgbFromCVImage.extent];
  
  UIImage *uiImgFromCIImage = [UIImage imageWithCGImage:outCGImageRef];
  
  self.imageView.image = uiImgFromCIImage;
  
  // Dump PNG that contains the decoded sRGB output pixels
  
  if ((1)) {
    CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    // Explicitly indicate that framebuffer is in terms of sRGB pixels
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    cgFramebuffer.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    [cgFramebuffer renderCGImage:outCGImageRef];
    
    if ((1)) {
      // Dump RGB of first pixel
      uint32_t *pixelPtr = (uint32_t*) cgFramebuffer.pixels;
      uint32_t pixel = pixelPtr[0];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("first pixel (R G B) (%3d %3d %3d)\n", R, G, B);
    }
    
    // Dump generated BGRA in sRGB colorspace as PNG
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_RGB_from_YCbCr_CoreVideo.png"];
      NSString *tmpDir = NSTemporaryDirectory();
      NSString *path = [tmpDir stringByAppendingPathComponent:filename];
      NSData *pngData = [cgFramebuffer formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }
  }
}


@end
