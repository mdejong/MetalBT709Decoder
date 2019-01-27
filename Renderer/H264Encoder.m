//
//  H264Encoder.m
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//

#import "H264Encoder.h"

#import <QuartzCore/QuartzCore.h>
#import "CGFrameBuffer.h"

//#import "BGRAToBT709Converter.h"

@import AVFoundation;

@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import CoreGraphics;
@import VideoToolbox;

//#if defined(DEBUG)
//static const int dumpFramesImages = 1;
//#else
static const int dumpFramesImages = 0;
//#endif // DEBUG

#define LOGGING 1
//#define LOGGING_EVERY_FRAME 1

// Private API

@interface H264Encoder ()

@property (nonatomic, assign) CGColorSpaceRef encodedColorspace;

@end

@implementation H264Encoder

// constructor

+ (H264Encoder*) h264Encoder
{
#if __has_feature(objc_arc)
  return [[H264Encoder alloc] init];
#else
  return [[[H264Encoder alloc] init] autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  CGColorSpaceRef encodedColorspace = self.encodedColorspace;
  
  if (encodedColorspace != nil) {
    CGColorSpaceRelease(encodedColorspace);
    self.encodedColorspace = nil;
  }
}

// convert error code to string

+ (NSString*) ErrorCodeToString:(H264EncoderErrorCode)code
{
  if (code == H264EncoderErrorCodeSuccess) {
    return @"H264EncoderErrorCodeSuccess";
  } else if (code == H264EncoderErrorCodeNoFrameSource) {
    return @"H264EncoderErrorCodeNoFrameSource";
  } else if (code == H264EncoderErrorCodeSessionNotStarted) {
    return @"H264EncoderErrorCodeSessionNotStarted";
  } else {
    return @"unknown";
  }
}

+ (OSType) getPixelType
{
  // Explicitly use video range color matrix
  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  //const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
  return movieEncodePixelFormatType;
}

// Main entry point, this method will kick off an encoding operaiton
// on a background thread.

- (void) encodeframes:(NSString*)outH264Path
        frameDuration:(float)frameDuration
           renderSize:(CGSize)renderSize
           aveBitrate:(int)aveBitrate
{
  // The result reporting protocol must be defined as non-nil.
  
  NSAssert(self.encoderResult != nil, @"encoderResult");
  if (self.encoderResult == nil) {
    // Return as nop in the case where NSAssert() is compiled away
    NSLog(@"encoderResult must be defined");
    return;
  }
  
  self.finished = FALSE;
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    @autoreleasepool {
      // Block holds strong ref to self here
      H264EncoderErrorCode code = [self blockingEncode:outH264Path
                                         frameDuration:frameDuration
                                            renderSize:renderSize
                                            aveBitrate:aveBitrate];
      if (code != H264EncoderErrorCodeSuccess) {
        [self reportErrorCode:code];
      }

      self.finished = TRUE;
    }
  });
  
  return;
}

// Block the calling thread until encoding is finished

- (void) blockUntilFinished
{
//  const float waitTime = 0.1f;
  const float waitTime = 1.0f;
  
  while (self.finished == FALSE) {
#ifdef LOGGING
    NSLog(@"Waiting until H264Encoder is finished encoding");
#endif // LOGGING
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:waitTime];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }

#ifdef LOGGING
  NSLog(@"H264Encoder is now finished encoding");
#endif // LOGGING
  
  return;
}

// This util method reports an error code to the associated H264EncoderResult

- (void) reportErrorCode:(H264EncoderErrorCode)code
{
  id<H264EncoderResult> encoderResult = self.encoderResult;
  
  dispatch_async(dispatch_get_main_queue(), ^{
    [encoderResult encoderResult:code];
  });
}

// Invoke this method on the background thread to encode N
// frames from an input source.

- (H264EncoderErrorCode) blockingEncode:(NSString*)outH264Path
          frameDuration:(float)frameDuration
             renderSize:(CGSize)renderSize
             aveBitrate:(int)aveBitrate
{
  if (self.frameSource == nil) {
    return H264EncoderErrorCodeNoFrameSource;
  }
  
  // If the output file already exists, remove it before starting
  // the encode process. This is basically "rm -f FILE". This
  // logic is run on the current thread (main thread)
  
  [[NSFileManager defaultManager] removeItemAtPath:outH264Path error:nil];
  
  NSURL *outH264URL = [NSURL fileURLWithPath:outH264Path];
  // FIXME: report error via callback
  NSAssert(outH264URL, @"outH264URL");
  
  BOOL worked;
  
  int width = (int) renderSize.width;
  int height = (int) renderSize.height;
  
#ifdef LOGGING
  NSLog(@"Writing movie with size %d x %d", width, height);
#endif // LOGGING
  
  // Output file is a file name like "out.mov" or "out.m4v"
  
  NSAssert(outH264URL, @"outH264URL");
  NSError *error = nil;
  
  // Output types:
  // AVFileTypeQuickTimeMovie
  // AVFileTypeMPEG4 (no)
  // AVFileTypeAppleM4V
  
  AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:outH264URL
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
  
  // Supports only HD video output settings, it is critical that iOS
  // does not guess the YCbCr transform incorrectly.
  
  NSDictionary *hdVideoProperties = @{
                                      AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                      AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                      AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                                      };

  NSDictionary *videoSettings = @{
                                  AVVideoCodecKey: AVVideoCodecTypeH264,
                                  AVVideoWidthKey: widthNum,
                                  AVVideoHeightKey: heightNum,
                                  AVVideoColorPropertiesKey: hdVideoProperties,
                                  };
  
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
  
  // Media data comes from an input file, not real time source
  
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
    NSLog(@"Failed to start export session with movie size %d x %d", width, height);
#endif // LOGGING
    
    [videoWriterInput markAsFinished];
    
    [self.class videoWriterFinishWriting:videoWriter];
    
    // Remove output file when writing to the video file is not successful

    NSString *outPath = [outH264URL path];
    NSError *error = nil;
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:&error];
    NSAssert(worked, @"could not remove output file : %@", error);
    
    // Return code indicating that the session could not be started, this is
    // seen as a nil pixelBufferPool, but it means something went wrong
    // when starting the encoding process.
    
    return H264EncoderErrorCodeSessionNotStarted;
  }
  
  CVPixelBufferRef cvPixelBuffer = NULL;
  
  // This frame encoding loop runs until the source reports that no
  // more frames are avaialble.
  
  //NSTimeInterval frameDuration = 1.0; // 1 FPS
  NSAssert(frameDuration != 0.0, @"frameDuration cannot be zero");
  int denominator = (int)round(1.0 / frameDuration);
  CMTime endTime = CMTimeMake(0, denominator);
  
  int frameNum;
  for (frameNum = 0; TRUE; frameNum++) @autoreleasepool {
    
    // Return TRUE if more frames can be returned by this frame source,
    // returning FALSE means that all frames have been encoded.
    
    BOOL hasMoreFrames = [self.frameSource hasMoreFrames];
    
    if (hasMoreFrames == FALSE) {
#ifdef LOGGING
      NSLog(@"Finished writing frames at %d", frameNum);
#endif // LOGGING
      
      break;
    }
    
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
    
    // Grab next input image frame
    
    NSAssert(self.frameSource, @"frameSource");
    CGImageRef inImageRef = [self.frameSource imageForFrame:frameNum];
    NSAssert(inImageRef != NULL, @"frameSource returned NULL for frame %d", frameNum);
    
    CVReturn poolResult = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &cvPixelBuffer);
    NSAssert(poolResult == kCVReturnSuccess, @"CVPixelBufferPoolCreatePixelBuffer");
    
#ifdef LOGGING
    NSLog(@"filling pixel buffer");
#endif // LOGGING
    
    // Buffer pool error conditions should have been handled already:
    // kCVReturnInvalidArgument = -6661 (some configuration value is invalid, like adaptor.pixelBufferPool is nil)
    // kCVReturnAllocationFailed = -6662
    
    [self fillPixelBufferFromImage:inImageRef cvPixelBuffer:cvPixelBuffer size:renderSize];
    
    // Verify that the pixel buffer uses the BT.709 colorspace at this
    // points. This should have been defined inside the fill method.
    
    int numerator = frameNum;
    CMTime presentationTime = CMTimeMake(numerator, denominator);
    endTime = CMTimeMake(numerator+1, denominator);
    worked = [adaptor appendPixelBuffer:cvPixelBuffer withPresentationTime:presentationTime];
    
    if (worked == FALSE) {
      // Fails on 3G, but works on iphone 4, due to lack of hardware encoder on versions < 4
      // com.apple.mediaserverd[18] : VTSelectAndCreateVideoEncoderInstance: no video encoder found for 'avc1'
      
      NSAssert(FALSE, @"appendPixelBuffer failed");
      
      // FIXME: Need to break out of loop and free writer elements in this fail case
    }
    
    CVPixelBufferRelease(cvPixelBuffer);
  }
  
#ifdef LOGGING
  NSLog(@"successfully wrote %d frames", frameNum);
#endif // LOGGING
  
  // Done writing video data
  
  [videoWriterInput markAsFinished];
  
  [videoWriter endSessionAtSourceTime:endTime];
  
  [self videoWriterFinishWriting:videoWriter];
  
  return H264EncoderErrorCodeSuccess;
}

// Util to invoke finishWriting method

- (void) videoWriterFinishWriting:(AVAssetWriter*)videoWriter
{
  // Bug in finishWriting in iOS 6 simulator:
  // http://stackoverflow.com/questions/12517760/avassetwriter-finishwriting-fails-on-ios-6-simulator
  
#if TARGET_IPHONE_SIMULATOR
  [videoWriter performSelectorOnMainThread:@selector(finishWriting) withObject:nil waitUntilDone:TRUE];
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [videoWriter finishWriting];
#pragma clang diagnostic pop
#endif
}

// Copy the contents of a CGImageRef into the indicated CVPixelBufferRef.

- (void) fillPixelBufferFromImage:(CGImageRef)imageRef
                    cvPixelBuffer:(CVPixelBufferRef)cvPixelBuffer
                             size:(CGSize)size
{
  CVPixelBufferLockBaseAddress(cvPixelBuffer, 0);
  void *pxdata = CVPixelBufferGetBaseAddress(cvPixelBuffer);
  NSParameterAssert(pxdata != NULL);
  
  NSAssert(size.width == CVPixelBufferGetWidth(cvPixelBuffer), @"CVPixelBufferGetWidth");
  NSAssert(size.height == CVPixelBufferGetHeight(cvPixelBuffer), @"CVPixelBufferGetHeight");
  
  // zero out all pixel buffer memory before rendering an image (buffers are reused in pool)
  
  if (FALSE) {
    size_t bytesPerPBRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer);
    size_t totalNumPBBytes = bytesPerPBRow * CVPixelBufferGetHeight(cvPixelBuffer);
    memset(pxdata, 0, totalNumPBBytes);
  }
  
  if (TRUE) {
    size_t bufferSize = CVPixelBufferGetDataSize(cvPixelBuffer);
    memset(pxdata, 0, bufferSize);
  }
  
  if (FALSE) {
    size_t bufferSize = CVPixelBufferGetDataSize(cvPixelBuffer);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer);
    
    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(cvPixelBuffer, &left, &right, &top, &bottom);
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
  
  // Make sure the rendered pixels are in the BT.709 colorspace,
  // if not then do a colorspace and gamma space conversion to
  // BT.709 so that the proper gamma adjustment is done *before*
  // the BT.709 matrix is applied.
  
#if defined(DEBUG)
  // Verify input colorspace is sRGB
  
  if ((0)) {
    CGColorSpaceRef inputColorspace = CGImageGetColorSpace(imageRef);
    
    BOOL inputIsSRGBColorspace = FALSE;
    
    {
      CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      
      NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
      NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
      
      if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
        inputIsSRGBColorspace = TRUE;
      }
      
      CGColorSpaceRelease(colorspace);
    }
    
    assert(inputIsSRGBColorspace == TRUE);
  }
#endif // DEBUG

  //CGColorSpaceRef encodedColorspace = CGImageGetColorSpace(imageRef);
  //CGColorSpaceRef encodedColorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  //CGColorSpaceRef encodedColorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
  //CGColorSpaceRef encodedColorspace = [H264Encoder createHDTVColorSpaceRef];

  CGColorSpaceRef encodedColorspace = self.encodedColorspace;

  if (encodedColorspace == nil) {
    encodedColorspace = [H264Encoder createHDTVColorSpaceRef];
    self.encodedColorspace = encodedColorspace;
  }
  
  CGContextRef bitmapContext =
  CGBitmapContextCreate(pxdata, size.width, size.height, bitsPerComponent, bytesPerRow, encodedColorspace, bitmapInfo);
  
  if (bitmapContext == NULL) {
    NSAssert(FALSE, @"CGBitmapContextCreate() failed");
  }
  
  // This invocation of CGContextDrawImage() should basically be a memcpy()
  // since the colorspace of the source and the bitmapContext are the same.
  
  CGContextDrawImage(bitmapContext, CGRectMake(0, 0, size.width, size.height), imageRef);
  
  CGContextRelease(bitmapContext);
  
  CVPixelBufferFillExtendedPixels(cvPixelBuffer);
  
  if ((1)) {
    // Should have rendered BT.709 pixels into the BGRA pixel buffer at this
    // point, grab the RGB values and print to make sure.

    uint32_t *pixelPtr = (uint32_t*) pxdata;
    uint32_t pixel = pixelPtr[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first CoreVideo pixel  BT709 (R G B) (%3d %3d %3d)\n", R, G, B);
  }
  
  CVPixelBufferUnlockBaseAddress(cvPixelBuffer, 0);

  // Attach BT.709 colorspace to CoreVideo buffer, this is required so that
  // AVFoundation knows that this CoreVideo pixel buffer is defined in
  // terms of the BT.709 colorspace and gamma curve and that values
  // can be fed into the BT.709 matrix conversion directly.
  
  [self setColorspace:cvPixelBuffer colorSpace:encodedColorspace];
  
  //CGColorSpaceRelease(bt709ColorSpace);
  
  return;
}

// Define colorspace associated with a CoreVideo pixel buffer
// by attching a generated ICC profile generated from the
// indicated colorspace. This logic is required to define how
// RGB values in the CoreVideo buffer are interpreted.
//
// https://developer.apple.com/library/archive/qa/qa1839/_index.html
// https://developer.apple.com/library/archive/technotes/tn2257/_index.html
// https://developer.apple.com/library/archive/technotes/tn2227/_index.html

// FIXME: set kCVImageBufferCGColorSpaceKey directly

- (BOOL) setColorspace:(CVPixelBufferRef)cvPixelBuffer
            colorSpace:(CGColorSpaceRef)colorSpace
{
  //CFDataRef colorProfileData = CGColorSpaceCopyICCProfile(colorSpace); // deprecated
  CFDataRef colorProfileData = CGColorSpaceCopyICCData(colorSpace);
  NSAssert(colorProfileData, @"CGColorSpaceCopyICCData retuned nil, must not pass default device colorspace");
  
  NSDictionary *pbAttachments = @{
                                  (__bridge NSString*)kCVImageBufferICCProfileKey: (__bridge NSData *)colorProfileData,
                                  };
  
  CVBufferRef pixelBuffer = cvPixelBuffer;
  
  CVBufferSetAttachments(pixelBuffer, (__bridge CFDictionaryRef)pbAttachments, kCVAttachmentMode_ShouldPropagate);
  
  // Drop ref to NSDictionary to enable explicit checking of ref count of colorProfileData, after the
  // release below the colorProfileData must be 1.
  pbAttachments = nil;
  CFRelease(colorProfileData);
  
  // Note that the passed in colorSpace is not created/retained here so do not relese.
  //CGColorSpaceRelease(colorSpace);
  
  return TRUE;
}

// Generate a reference to the hidden "HDTV" colorspace that decodes already brightness
// adjusted video data to light linear with a 1.961 gamma.

+ (CGColorSpaceRef) createHDTVColorSpaceRef {
  int width = 1920;
  int height = 1080;
  
  NSDictionary *pixelAttributes = @{
                                    (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{},
                                    (__bridge NSString*)kCVPixelBufferCGImageCompatibilityKey : @(YES),
                                    (__bridge NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @(YES),
                                    };
  
  CVPixelBufferRef cvPixelBuffer = NULL;
  
  uint32_t yuvImageFormatType;
  //yuvImageFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange; // luma (0, 255)
  yuvImageFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; // luma (16, 235)
  
  CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        yuvImageFormatType,
                                        (__bridge CFDictionaryRef)(pixelAttributes),
                                        &cvPixelBuffer);
  
  NSAssert(result == kCVReturnSuccess, @"CVPixelBufferCreate failed");
  
  // Define HDTV properties on pixel buffer, note that colorspace is not defined
  // since the system defined "HDTV" is what we are after.
  
  BOOL worked = [self setBT709Attributes:cvPixelBuffer];
  NSAssert(worked, @"worked");
  
  CIImage *rgbFromCVImage = [CIImage imageWithCVPixelBuffer:cvPixelBuffer];

  CGColorSpaceRef hdcs = rgbFromCVImage.colorSpace;
  
  CGColorSpaceRetain(hdcs);
  
  CVPixelBufferRelease(cvPixelBuffer);
  
  return hdcs;
}

+ (BOOL) setBT709Attributes:(CVPixelBufferRef)cvPixelBuffer
{
  // FIXME: UHDTV : HEVC uses kCGColorSpaceITUR_2020
  
  //CGColorSpaceRef yuvColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
  
  // Attach BT.709 info to pixel buffer
  
  //CFDataRef colorProfileData = CGColorSpaceCopyICCProfile(yuvColorSpace); // deprecated
  //CFDataRef colorProfileData = CGColorSpaceCopyICCData(yuvColorSpace);
  
  // FIXME: "CVImageBufferChromaSubsampling" read from attached H.264 (.m4v) is "TopLeft"
  // kCVImageBufferChromaLocationTopFieldKey = kCVImageBufferChromaLocation_TopLeft
  
  NSDictionary *pbAttachments = @{
                                  (__bridge NSString*)kCVImageBufferChromaLocationTopFieldKey: (__bridge NSString*)kCVImageBufferChromaLocation_Center,
                                  (__bridge NSString*)kCVImageBufferAlphaChannelIsOpaque: (id)kCFBooleanTrue,
                                  
                                  (__bridge NSString*)kCVImageBufferYCbCrMatrixKey: (__bridge NSString*)kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                                  (__bridge NSString*)kCVImageBufferColorPrimariesKey: (__bridge NSString*)kCVImageBufferColorPrimaries_ITU_R_709_2,
                                  (__bridge NSString*)kCVImageBufferTransferFunctionKey: (__bridge NSString*)kCVImageBufferTransferFunction_ITU_R_709_2,
                                  // Note that icc profile is required to enable gamma mapping
                                  //(__bridge NSString*)kCVImageBufferICCProfileKey: (__bridge NSData *)colorProfileData,
                                  };
  
  CVBufferRef pixelBuffer = cvPixelBuffer;
  
  CVBufferSetAttachments(pixelBuffer, (__bridge CFDictionaryRef)pbAttachments, kCVAttachmentMode_ShouldPropagate);
  
  // Drop ref to NSDictionary to enable explicit checking of ref count of colorProfileData, after the
  // release below the colorProfileData must be 1.
  pbAttachments = nil;
  //CFRelease(colorProfileData);
  
  //CGColorSpaceRelease(yuvColorSpace);
  
  return TRUE;
}

@end
