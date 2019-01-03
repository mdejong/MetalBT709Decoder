//
//  encode_h264.m
//
//  Created by Mo DeJong on 12/31/18.
//
//  Command line utility that reads a single image
//  and write out an encoded h264 video that
//  contains the image data.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import <QuartzCore/QuartzCore.h>

#import <ImageIO/ImageIO.h>

#import "CGFramebuffer.h"
#import "BGRAToBT709Converter.h"

typedef struct {
  int fps;
} ConfigurationStruct;

void usage() {
  printf("encode_h264 ?OPTIONS? IN.png OUT.m4v\n");
  fflush(stdout);
}

// Helper class

@interface EncoderImpl : NSObject

@end

@implementation EncoderImpl

+ (void) blockingEncode:(CGImageRef)inImageRef
          outputPathURL:(NSURL*)outputPathURL
{
#define LOGGING
  
  int width = (int) CGImageGetWidth(inImageRef);
  int height = (int) CGImageGetHeight(inImageRef);
  
  @autoreleasepool {
    
    BOOL worked;
    
    CGSize movieSize = CGSizeMake(width, height);
    
#ifdef LOGGING
    NSLog(@"Writing movie with size %d x %d", width, height);
#endif // LOGGING
    
    // Output file is a file name like "out.mov" or "out.m4v"
    
    NSAssert(outputPathURL, @"outputPathURL");
    NSError *error = nil;
    
    // Output types:
    // AVFileTypeQuickTimeMovie
    // AVFileTypeMPEG4 (no)
    
    AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:outputPathURL
                                                           fileType:AVFileTypeAppleM4V
                                                              error:&error];
#if __has_feature(objc_arc)
#else
    videoWriter = [videoWriter autorelease];
#endif // objc_arc
    
    NSAssert(videoWriter, @"videoWriter");
    NSAssert(error == nil, @"error %@", error);
    
    NSNumber *widthNum = [NSNumber numberWithUnsignedInteger:width];
    NSNumber *heightNum = [NSNumber numberWithUnsignedInteger:height];
    
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecTypeH264, AVVideoCodecKey,
                                   widthNum, AVVideoWidthKey,
                                   heightNum, AVVideoHeightKey,
                                   nil];
    NSAssert(videoSettings, @"videoSettings");
    
    AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
                                            assetWriterInputWithMediaType:AVMediaTypeVideo
                                            outputSettings:videoSettings];
    
    NSAssert(videoWriterInput, @"videoWriterInput");
    
    // adaptor handles allocation of a pool of pixel buffers and makes writing a series
    // of images to the videoWriterInput easier.
    
    NSMutableDictionary *adaptorAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                              [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                              widthNum,  kCVPixelBufferWidthKey,
                                              heightNum, kCVPixelBufferHeightKey,
                                              nil];
    
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                     assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                     sourcePixelBufferAttributes:adaptorAttributes];
    
    NSAssert(adaptor, @"assetWriterInputPixelBufferAdaptorWithAssetWriterInput");
    
    // Media data comes from an input file, not real time
    
    videoWriterInput.expectsMediaDataInRealTime = NO;
    
    NSAssert([videoWriter canAddInput:videoWriterInput], @"canAddInput");
    [videoWriter addInput:videoWriterInput];
    
    // Start writing samples to video file
    
    [videoWriter startWriting];
    [videoWriter startSessionAtSourceTime:kCMTimeZero];
    
    // If the pixelBufferPool is nil after the call to startSessionAtSourceTime then something went wrong
    // when creating the pixel buffers. Typically, an error indicates the the size of the video data is
    // not acceptable to the AVAssetWriterInput (like smaller than 128 in either dimension).
    
    if (adaptor.pixelBufferPool == nil) {
#ifdef LOGGING
      NSLog(@"Failed to start exprt session with movie size %d x %d", width, height);
#endif // LOGGING
      
      [videoWriterInput markAsFinished];
      
      [self.class videoWriterFinishWriting:videoWriter];
      
      // Remove output file when H264 compressor is not working
      
      //worked = [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
      //NSAssert(worked, @"could not remove output file");
      
      //self.state = AVAssetWriterConvertFromMaxvidStateFailed;
      return;
    }
    
    CVPixelBufferRef buffer = NULL;
    
    //const int numFrames = (int) [frameDecoder numFrames];
    const int numFrames = 1;
    int frameNum;
    for (frameNum = 0; frameNum < numFrames; frameNum++) @autoreleasepool {
#ifdef LOGGING
      NSLog(@"Writing frame %d", frameNum);
#endif // LOGGING
      
      // FIXME: might reconsider logic design in terms of using block pull approach
      
      // http://stackoverflow.com/questions/11033421/optimization-of-cvpixelbufferref
      // https://developer.apple.com/library/mac/#documentation/AVFoundation/Reference/AVAssetWriterInput_Class/Reference/Reference.html
      
      while (adaptor.assetWriterInput.readyForMoreMediaData == FALSE) {
        // In the case where the input is not ready to accept input yet, wait until it is.
        // This is a little complex in the case of the main thread, because we would
        // need to visit the event loop in order for other processing tasks to happen.
        
#ifdef LOGGING
        NSLog(@"Waiting until writer is ready");
#endif // LOGGING
        
        NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
        [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
      }
      
      // Pull frame of data from MVID file
      
      //AVFrame *frame = [frameDecoder advanceToFrame:frameNum];
      //UIImage *frameImage = frame.image;
      
      //NSAssert(frame, @"advanceToFrame returned nil frame");
      //NSAssert(frameImage, @"advanceToFrame returned frame with nil image");
      //if (frame.isDuplicate) {
      // FIXME: (can output frame  duration time be explicitly set to deal with this duplication)
      // Input frame data is the same as the previous one : (keep using previous one)
      //}
      
      CVReturn poolResult = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
      NSAssert(poolResult == kCVReturnSuccess, @"CVPixelBufferPoolCreatePixelBuffer");
      
#ifdef LOGGING
      NSLog(@"filling pixel buffer");
#endif // LOGGING
      
      // Buffer pool error conditions should have been handled already:
      // kCVReturnInvalidArgument = -6661 (some configuration value is invalid, like adaptor.pixelBufferPool is nil)
      // kCVReturnAllocationFailed = -6662
      
      [self fillPixelBufferFromImage:inImageRef buffer:buffer size:movieSize];
      
      NSTimeInterval frameDuration = 1.0; // 1 FPS
      NSAssert(frameDuration != 0.0, @"frameDuration not set in frameDecoder");
      int numerator = frameNum;
      int denominator = (int)round(1.0 / frameDuration);
      CMTime presentationTime = CMTimeMake(numerator, denominator);
      worked = [adaptor appendPixelBuffer:buffer withPresentationTime:presentationTime];
      
      if (worked == FALSE) {
        // Fails on 3G, but works on iphone 4, due to lack of hardware encoder on versions < 4
        // com.apple.mediaserverd[18] : VTSelectAndCreateVideoEncoderInstance: no video encoder found for 'avc1'
        
        NSAssert(FALSE, @"appendPixelBuffer failed");
        
        // FIXME: Need to break out of loop and free writer elements in this fail case
      }
      
      CVPixelBufferRelease(buffer);
    }
    
    NSAssert(frameNum == numFrames, @"numFrames");
    
#ifdef LOGGING
    NSLog(@"successfully wrote %d frames", numFrames);
#endif // LOGGING
    
    // Done writing video data
    
    [videoWriterInput markAsFinished];
    
    [self.class videoWriterFinishWriting:videoWriter];
  }
  
  return;
}

// Util to invoke finishWriting method

+ (void) videoWriterFinishWriting:(AVAssetWriter*)videoWriter
{
  // Bug in finishWriting in iOS 6 simulator:
  // http://stackoverflow.com/questions/12517760/avassetwriter-finishwriting-fails-on-ios-6-simulator
  
#if TARGET_IPHONE_SIMULATOR
  [videoWriter performSelectorOnMainThread:@selector(finishWriting) withObject:nil waitUntilDone:TRUE];
#elif TARGET_MACOS
#else
  // Invoke finishWriting on some other thread?
  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [videoWriter finishWriting];
  });
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [videoWriter finishWriting];
#pragma clang diagnostic pop
#endif
}

+ (void) fillPixelBufferFromImage:(CGImageRef)imageRef
                           buffer:(CVPixelBufferRef)buffer
                             size:(CGSize)size
{
  CVPixelBufferLockBaseAddress(buffer, 0);
  void *pxdata = CVPixelBufferGetBaseAddress(buffer);
  NSParameterAssert(pxdata != NULL);
  
  NSAssert(size.width == CVPixelBufferGetWidth(buffer), @"CVPixelBufferGetWidth");
  NSAssert(size.height == CVPixelBufferGetHeight(buffer), @"CVPixelBufferGetHeight");
  
  // zero out all pixel buffer memory before rendering an image (buffers are reused in pool)
  
  if (FALSE) {
    size_t bytesPerPBRow = CVPixelBufferGetBytesPerRow(buffer);
    size_t totalNumPBBytes = bytesPerPBRow * CVPixelBufferGetHeight(buffer);
    memset(pxdata, 0, totalNumPBBytes);
  }
  
  if (TRUE) {
    size_t bufferSize = CVPixelBufferGetDataSize(buffer);
    memset(pxdata, 0, bufferSize);
  }
  
  if (FALSE) {
    size_t bufferSize = CVPixelBufferGetDataSize(buffer);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(buffer, &left, &right, &top, &bottom);
    NSLog(@"extended pixels : left %d right %d top %d bottom %d", (int)left, (int)right, (int)top, (int)bottom);
    
    NSLog(@"buffer size = %d (bpr %d), row bytes (%d) * height (%d) = %d", (int)bufferSize, (int)(bufferSize/size.height), (int)bytesPerRow, (int)size.height, (int)(bytesPerRow * size.height));
    
  }
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  // 24 BPP with no alpha channel
  
  bitsPerComponent = 8;
  numComponents = 4;
  bitsPerPixel = bitsPerComponent * numComponents;
  bytesPerRow = size.width * (bitsPerPixel / 8);
  
  CGBitmapInfo bitmapInfo = 0;
  bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst;
  
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(imageRef);
  
  CGContextRef bitmapContext =
  CGBitmapContextCreate(pxdata, size.width, size.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
  if (bitmapContext == NULL) {
    NSAssert(FALSE, @"CGBitmapContextCreate() failed");
  }
  
  CGContextDrawImage(bitmapContext, CGRectMake(0, 0, size.width, size.height), imageRef);
  
  CGContextRelease(bitmapContext);
  
  CVPixelBufferFillExtendedPixels(buffer);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
  
  return;
}

@end

// Load PNG from the filesystem

CGImageRef makeImageFromFile(NSString *filenameStr)
{
  CGImageSourceRef sourceRef;
  CGImageRef imageRef;
  
  NSData *image_data = [NSData dataWithContentsOfFile:filenameStr];
  if (image_data == nil) {
    fprintf(stderr, "can't read image data from file \"%s\"\n", [filenameStr UTF8String]);
    exit(1);
  }
  
  // Create image object from src image data.
  
  sourceRef = CGImageSourceCreateWithData((__bridge CFDataRef)image_data, NULL);
  
  // Make sure the image source exists before continuing
  
  if (sourceRef == NULL) {
    fprintf(stderr, "can't create image data from file \"%s\"\n", [filenameStr UTF8String]);
    exit(1);
  }
  
  // Create an image from the first item in the image source.
  
  imageRef = CGImageSourceCreateImageAtIndex(sourceRef, 0, NULL);
  
  CFRelease(sourceRef);
  
  return imageRef;
}

// Export a video to H.264

static inline
void exportVideo(CGImageRef inCGImage) {
  //AVAsset* inAsset = [AVAsset assetWithURL:inURL];
  
  //NSString *resFilename = @"Gamma_test_HD_75Per_24BPP_sRGB_HD.png";
  //NSString *path = [[NSBundle mainBundle] pathForResource:resFilename ofType:nil];
  
  //UIImage *inImage = [UIImage imageNamed:@"Gamma_test_HD_75Per_24BPP_sRGB_HD.png"];
  
  NSString *outFilename = @"Encoded.m4v";
  NSString *dirName = NSTemporaryDirectory();
  NSString *outPath = [dirName stringByAppendingPathComponent:outFilename];
  NSURL *outUrl = [NSURL fileURLWithPath:outPath];
  
  [EncoderImpl blockingEncode:inCGImage outputPathURL:outUrl];
  
  NSLog(@"wrote %@", outPath);
}

int process(NSString *inPNGStr, NSString *outY4mStr, ConfigurationStruct *configSPtr) {
  // Read PNG
  
  CGImageRef inImage = makeImageFromFile(inPNGStr);
  //  if (inImage == NULL) {
  //  }
  
  int width = (int) CGImageGetWidth(inImage);
  int height = (int) CGImageGetHeight(inImage);
  
  assert(width > 0);
  assert(height > 0);
  
  assert((width % 2) == 0);
  assert((height % 2) == 0);
  
  CGColorSpaceRef inputColorspace = CGImageGetColorSpace(inImage);
  
  BOOL inputIsRGBColorspace = FALSE;
  BOOL inputIsSRGBColorspace = FALSE;
  BOOL inputIsGrayColorspace = FALSE;
  
  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    
    NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsRGBColorspace = TRUE;
    }
    
    CGColorSpaceRelease(colorspace);
  }
  
  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsSRGBColorspace = TRUE;
    }
    
    CGColorSpaceRelease(colorspace);
  }
  
  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceGray();
    
    // ICC gray (not the default)
    
    // FIXME: is it possible that input could be tagged as generic gray and then
    // this device check would not detect it?
    
    //CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
    
    NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsGrayColorspace = TRUE;
    }
    
    CGColorSpaceRelease(colorspace);
  }
  
  if (inputIsRGBColorspace) {
    printf("untagged RGB colorspace is not supported as input\n");
    exit(2);
  } else if (inputIsSRGBColorspace) {
    printf("input is sRGB colorspace\n");
  } else if (inputIsGrayColorspace) {
    printf("input is grayscale colorspace\n");
  } else {
    printf("will convert from input colorspace to BT709 gamma encoded space:\n");
    NSString *desc = [(__bridge id)inputColorspace description];
    printf("%s\n", [desc UTF8String]);
  }
  
  // Load BGRA pixel data into BGRA CoreVideo pixel buffer
  
  exportVideo(inImage);
  
  if (1) {
    // Render into sRGB buffer in order to dump the first input pixel in terms of sRGB
    
    CGFrameBuffer *inFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    [inFB renderCGImage:inImage];
    
    uint32_t pixel = ((uint32_t*) inFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel sRGB (R G B) (%d %d %d)\n", R, G, B);
  }
  
  // FIXME: Render into linear RGB and print that value
  
  CGImageRelease(inImage);
  
  return 1;
}

int main(int argc, const char * argv[]) {
  int retcode = 0;
  
  @autoreleasepool {
    char *inPNG = NULL;
    char *outY4m = NULL;
    
    //int fps = 30; // Default to 30 frames per second
    //int fps = 1;
    
    ConfigurationStruct configS;
    configS.fps = 1;
    
    if (argc == 3) {
      // No options, input and output files indicated
      inPNG = (char *) argv[1];
      outY4m = (char *) argv[2];
    } else {
      usage();
      exit(1);
    }
    
    NSString *inPNGStr = [NSString stringWithFormat:@"%s", inPNG];
    NSString *outY4mStr = [NSString stringWithFormat:@"%s", outY4m];
    
    retcode = process(inPNGStr, outY4mStr, &configS);
  }
  
  exit(retcode);
  return retcode;
}

