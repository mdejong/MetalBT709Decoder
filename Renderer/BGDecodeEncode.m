//
//  BGDecodeEncode.m
//
//  Created by Mo DeJong on 4/5/16.
//
//  See license.txt for BSD license terms.
//

#import "BGDecodeEncode.h"

@import AVFoundation;
@import UIKit;

@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import CoreGraphics;
@import VideoToolbox;

//#import "H264FrameEncoder.h"

#import "CGFrameBuffer.h"

//#if defined(DEBUG)
//static const int dumpFramesImages = 1;
//#else
static const int dumpFramesImages = 0;
//#endif // DEBUG

#define LOGGING 1
//#define LOGGING_EVERY_FRAME 1

// Private API

@interface BGDecodeEncode ()
@end

@implementation BGDecodeEncode

// Return the movie decode OS type, typically kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
// but could be kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange. In any case, this value
// needs to match in both the encoder and decoder.

+ (OSType) getPixelType
{
  // Explicitly use video range color matrix
  const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  //const OSType movieEncodePixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
  return movieEncodePixelFormatType;
}

+ (CVPixelBufferRef) pixelBufferFromCGImage:(CGImageRef)cgImage
                                 renderSize:(CGSize)renderSize
                                       dump:(BOOL)dump
                                      asYUV:(BOOL)asYUV
{
  NSDictionary *options = @{
                            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                            };
  
  int renderWidth = (int) renderSize.width;
  int renderHeight = (int) renderSize.height;
  
  int imageWidth = (int) CGImageGetWidth(cgImage);
  int imageHeight = (int) CGImageGetHeight(cgImage);
  
  assert(imageWidth <= renderWidth);
  assert(imageHeight <= renderHeight);
  
  // FIXME: instead of creating CoreVideo buffers over and over, just create 1 and
  // then keep using it to do the render operations. Could also use a pool, but
  // not really needed either.
  
  CVPixelBufferRef buffer = NULL;
  CVPixelBufferCreate(kCFAllocatorDefault,
                      renderWidth,
                      renderHeight,
                      kCVPixelFormatType_32BGRA,
                      (__bridge CFDictionaryRef)options,
                      &buffer);
  
  size_t bytesPerRow, extraBytes;
  bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
  extraBytes = bytesPerRow - renderWidth*sizeof(uint32_t);
  //NSLog(@"bytesPerRow %d extraBytes %d", (int)bytesPerRow, (int)extraBytes);
  
  CVPixelBufferLockBaseAddress(buffer, 0);
  
  void *baseAddress                  = CVPixelBufferGetBaseAddress(buffer);
  
  //CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
  CGColorSpaceRef colorSpace  = CGColorSpaceCreateDeviceRGB();
  
  CGContextRef context;
  
  context = CGBitmapContextCreate(baseAddress,
                                  renderWidth,
                                  renderHeight,
                                  8,
                                  CVPixelBufferGetBytesPerRow(buffer),
                                  colorSpace,
                                  kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst);
  
  // Render frame into top left corner at exact size
  
  CGContextClearRect(context, CGRectMake(0.0f, 0.0f, renderWidth, renderHeight));
  
  CGContextDrawImage(context, CGRectMake(0.0f, renderHeight - imageHeight, imageWidth, imageHeight), cgImage);
  
  CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
  
  // Convert from BGRA to YUV representation
  
  if (asYUV) {
    NSDictionary *pixelAttributes = @{
                                      (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{},
                                      (__bridge NSString*)kCVPixelFormatOpenGLESCompatibility : @(YES),
                                      (__bridge NSString*)kCVPixelBufferCGImageCompatibilityKey : @(YES),
                                      (__bridge NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @(YES),
                                      };
    
    CVPixelBufferRef yuv420Buffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          renderWidth,
                                          renderHeight,
                                          [self getPixelType],
                                          (__bridge CFDictionaryRef) pixelAttributes,
                                          &yuv420Buffer);
    
    CIContext *context = [CIContext contextWithOptions:nil];
    NSAssert(context, @"CIContext");
    
    CIImage *inImage = [CIImage imageWithCVPixelBuffer:buffer];
    
    if (status == kCVReturnSuccess) {
      [context render:inImage toCVPixelBuffer:yuv420Buffer];
    }
    
    CVPixelBufferRelease(buffer);
    
    return yuv420Buffer;
  }
  
  return buffer;
}

// This method accepts a pixel buffer to be encoded, along with
// an encoder object and an output array that the encoded
// frame will be appened to.

+ (BOOL) encodeAndAppendToArray:(CVPixelBufferRef)pixBuffer
                    frameOffset:(int)frameOffset
                     renderSize:(CGSize)renderSize
             encodedH264Buffers:(NSMutableArray*)encodedH264Buffers
                    resNoSuffix:(NSString*)resNoSuffix
{
  int width = (int) CVPixelBufferGetWidth(pixBuffer);
  int height = (int) CVPixelBufferGetHeight(pixBuffer);
  
  CGSize imgSize = CGSizeMake(width, height);
  
  // 1920 x 1080 is Full HD and the upper limit of H264 render size for iPad devices.
  // When the size of the input and the output exactly match, use input buffer (much faster)
  
  // 2048 x 1536 seems to work just fine on iPad Retina
  
  //CGSize renderSize = CGSizeMake(1920, 1080);
  //CGSize renderSize = CGSizeMake(2048, 1536);
  
  //int renderWidth = (int) renderSize.width;
  //int renderHeight = (int) renderSize.height;
  
  // Render CoreVideo to a NxN square so that square pixels do not distort
  
#if defined(LOGGING_EVERY_FRAME)
  NSLog(@"encode input dimensions %4d x %4d", width, height);
#endif // LOGGING_EVERY_FRAME
  
  CVPixelBufferRef largerBuffer;
  
  if (CGSizeEqualToSize(imgSize, renderSize)) {
    // No resize needed
    largerBuffer = pixBuffer;
    
    CVPixelBufferRetain(largerBuffer);
  } else {
    int srcWidth = (int) CVPixelBufferGetWidth(pixBuffer);
    int srcHeight = (int) CVPixelBufferGetHeight(pixBuffer);
    int pixBufferNumBytes = (int) CVPixelBufferGetBytesPerRow(pixBuffer) * srcHeight;
    
    {
      int status = CVPixelBufferLockBaseAddress(pixBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
    void *pixelsPtr = CVPixelBufferGetBaseAddress(pixBuffer);
    assert(pixelsPtr);
    
    size_t bitsPerComponent = 8;
    size_t numComponents = 4;
    size_t bitsPerPixel = bitsPerComponent * numComponents;
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixBuffer);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst;
    
    CGDataProviderReleaseDataCallback releaseData = NULL;
    
    CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(
                                                                     NULL,
                                                                     pixelsPtr,
                                                                     pixBufferNumBytes,
                                                                     releaseData);
    
    BOOL shouldInterpolate = TRUE;
    
    CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB(); // iOS sRGB
    
    CGImageRef inImageRef = CGImageCreate(srcWidth, srcHeight, bitsPerComponent, bitsPerPixel, bytesPerRow,
                                          colorSpace, bitmapInfo, dataProviderRef, NULL,
                                          shouldInterpolate, renderIntent);
    
    CGDataProviderRelease(dataProviderRef);
    
    CGColorSpaceRelease(colorSpace);
    
    assert(inImageRef);
    
    // Dump original before resize action
    
    if (dumpFramesImages)
    {
      NSString *dumpFilename = [NSString stringWithFormat:@"%@_orig_F%d.png", resNoSuffix, frameOffset];
      NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
      
      UIImage *rerenderedInputImg = [UIImage imageWithCGImage:inImageRef];
      NSData *pngData = UIImagePNGRepresentation(rerenderedInputImg);
      [pngData writeToFile:tmpPath atomically:TRUE];
      
      NSLog(@"wrote \"%@\" at size %d x %d", tmpPath, (int)rerenderedInputImg.size.width, (int)rerenderedInputImg.size.height);
    }
    
    // Output image as CoreGraphics buffer
    
    CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:renderSize.width height:renderSize.height];
    
    // Render the src image into a large framebuffer
    
    BOOL worked = [cgFramebuffer renderCGImage:inImageRef];
    assert(worked);
    
    CGImageRelease(inImageRef);
    
    {
      int status = CVPixelBufferUnlockBaseAddress(pixBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
    
    CGImageRef resizedCgImgRef = [cgFramebuffer createCGImageRef];
    
    if (dumpFramesImages)
    {
      NSString *dumpFilename = [NSString stringWithFormat:@"%@_resized_F%d.png", resNoSuffix, frameOffset];
      NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
      
      UIImage *rerenderedInputImg = [UIImage imageWithCGImage:resizedCgImgRef];
      NSData *pngData = UIImagePNGRepresentation(rerenderedInputImg);
      [pngData writeToFile:tmpPath atomically:TRUE];
      
      NSLog(@"wrote \"%@\" at size %d x %d", tmpPath, (int)rerenderedInputImg.size.width, (int)rerenderedInputImg.size.height);
    }
    
    largerBuffer = [self.class pixelBufferFromCGImage:resizedCgImgRef
                                           renderSize:renderSize
                                                 dump:FALSE
                                                asYUV:FALSE];
    
    CGImageRelease(resizedCgImgRef);
  }
  
  if (dumpFramesImages)
  {
    CIImage *largerCiImage = [CIImage imageWithCVPixelBuffer:largerBuffer];
    
    UIGraphicsBeginImageContext(renderSize);
    CGRect rect;
    rect.origin = CGPointZero;
    rect.size   = renderSize;
    UIImage *remLargerImage = [UIImage imageWithCIImage:largerCiImage];
    [remLargerImage drawInRect:rect];
    UIImage *largerRenderedImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    NSString *dumpFilename = [NSString stringWithFormat:@"%@_F%d.png", resNoSuffix, frameOffset];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dumpFilename];
    
    NSData *pngData = UIImagePNGRepresentation(largerRenderedImg);
    [pngData writeToFile:tmpPath atomically:TRUE];
    
    NSLog(@"wrote \"%@\" at size %d x %d", tmpPath, (int)largerRenderedImg.size.width, (int)largerRenderedImg.size.height);
  }
  
  // Render CoreVideo to a NxN square so that square pixels do not distort
  
#if defined(LOGGING_EVERY_FRAME)
  int largerWidth = (int) CVPixelBufferGetWidth(largerBuffer);
  int largerHeight = (int) CVPixelBufferGetHeight(largerBuffer);
  NSLog(@"encode output dimensions %4d x %4d", largerWidth, largerHeight);
#endif // LOGGING_EVERY_FRAME
  
  //NSLog(@"CVPixelBufferRef: %@", pixBuffer);
  
  __block BOOL encodeFrameErrorCondition = FALSE;
  
//  frameEncoder.sampleBufferBlock = ^(CMSampleBufferRef sampleBuffer) {
//    // If sampleBuffer is NULL, then the frame could not be encoded.
//
//    if (sampleBuffer == NULL) {
//      //NSAssert(sampleBuffer, @"sampleBuffer argument to H264FrameEncoder.sampleBufferBlock is NULL");
//      encodeFrameErrorCondition = TRUE;
//      return;
//    }
//
//    [encodedH264Buffers addObject:(__bridge id)sampleBuffer];
//
//#if defined(LOGGING_EVERY_FRAME)
//    int numBytes = (int) CMSampleBufferGetSampleSize(sampleBuffer, 0);
//    NSLog(@"encoded buffer as %6d H264 bytes", numBytes);
//#endif // LOGGING_EVERY_FRAME
//  };
  
#if TARGET_IPHONE_SIMULATOR
  // No-op
#else
  OSType bufferPixelType = CVPixelBufferGetPixelFormatType(largerBuffer);
  if (bufferPixelType == kCVPixelFormatType_32BGRA) {
    // Already converted from YUV to BGRA
  } else {
    assert([self getPixelType] == bufferPixelType);
  }
#endif // TARGET_IPHONE_SIMULATOR
  
  BOOL worked = TRUE;
  
  //BOOL worked = [frameEncoder encodeH264CoreMediaFrame:largerBuffer];
  
  //if (worked) {
  //  [frameEncoder waitForFrame];
  //}
  
  [encodedH264Buffers addObject:(__bridge id)largerBuffer];
  
  CVPixelBufferRelease(largerBuffer);
  
  // Null out block ref just to make sure
  //frameEncoder.sampleBufferBlock = nil;
  
  if (encodeFrameErrorCondition == TRUE) {
    return FALSE;
  }
  
  if (worked == FALSE) {
    return FALSE;
  } else {
    return TRUE;
  }
};

// Given a .mov generate an array of the frames as CoreVideo buffers.
// This method returns the frames as BGRA pixels or YUV frames.

+ (BOOL) decodeCoreVideoFramesFromMOV:(NSString*)movPath
                                asYUV:(BOOL)asYUV
                           renderSize:(CGSize)renderSize
                   encodedH264Buffers:(NSMutableArray*)encodedH264Buffers
{
  if ([[NSFileManager defaultManager] fileExistsAtPath:movPath] == FALSE) {
    return FALSE;
  }
  
  NSString *resNoSuffix = [[movPath lastPathComponent] stringByDeletingPathExtension];
  
  // Read H.264 frames and extract YUV
  
  NSURL *assetURL = [NSURL fileURLWithPath:movPath];
  if (assetURL == nil) {
    NSLog(@"asset as url failed for \"%@\"", movPath);
    return FALSE;
  }
  
  NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                      forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
  
  AVURLAsset *avUrlAsset = [[AVURLAsset alloc] initWithURL:assetURL options:options];
  
  if (avUrlAsset.hasProtectedContent) {
    NSLog(@"hasProtectedContent is set for \"%@\"", movPath);
    return FALSE;
  }
  
  if ([avUrlAsset tracks] == 0) {
    NSLog(@"zero tracks is set for \"%@\"", movPath);
    return FALSE;
  }
  
  NSError *assetError = nil;
  AVAssetReader *aVAssetReader = [AVAssetReader assetReaderWithAsset:avUrlAsset error:&assetError];
  
  if (aVAssetReader == nil) {
    NSLog(@"aVAssetReader is nil for \"%@\"", movPath);
    return FALSE;
  }
  
  if (assetError) {
    NSLog(@"assetError is \"%@\" for \"%@\"", [assetError description], movPath);
    return FALSE;
  }
  
  NSDictionary *videoSettings;
  
  if (asYUV) {
    videoSettings = [NSDictionary dictionaryWithObject:
                     [NSNumber numberWithUnsignedInt:[self getPixelType]] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  } else {
    videoSettings = [NSDictionary dictionaryWithObject:
                     [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
  }
  
  NSArray *videoTracks = [avUrlAsset tracksWithMediaType:AVMediaTypeVideo];
  
  if ([videoTracks count] != 1) {
    NSLog(@"must contain 1 video track but got %d tracks for \"%@\"", (int)[videoTracks count], movPath);
    return FALSE;
  }
  
  AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
  
#if defined(LOGGING_EVERY_FRAME)
  NSArray *availableMetadataFormats = videoTrack.availableMetadataFormats;
  NSLog(@"availableMetadataFormats %@", availableMetadataFormats);
#endif // LOGGING_EVERY_FRAME
  
  if (videoTrack.isSelfContained != TRUE) {
    NSLog(@"videoTrack.isSelfContained must be TRUE for \"%@\"", movPath);
    return FALSE;
  }
  
#if defined(LOGGING_EVERY_FRAME)
  CGSize uncroppedSize = videoTrack.naturalSize;
  NSLog(@"video track naturalSize w x h : %d x %d", (int)uncroppedSize.width, (int)uncroppedSize.height);
#endif // LOGGING_EVERY_FRAME
  
  // Track length in second, should map directly to number of frames
  
#if defined(LOGGING_EVERY_FRAME)
  CMTimeRange timeRange = videoTrack.timeRange;
  float duration = (float)CMTimeGetSeconds(timeRange.duration);
  NSLog(@"video track time duration %0.3f", duration);
#endif // LOGGING_EVERY_FRAME
  
  // Don't know how many frames at this point
  
  //int numFrames = round(duration);
  //NSLog(@"estimated number of frames %d", numFrames);
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[AVAssetReaderTrackOutput alloc]
                                                   initWithTrack:videoTrack outputSettings:videoSettings];
  
  if (aVAssetReaderOutput == nil) {
    NSLog(@"aVAssetReaderOutput is nil for \"%@\"", movPath);
    return FALSE;
  }
  
  aVAssetReaderOutput.alwaysCopiesSampleData = FALSE;
  
  [aVAssetReader addOutput:aVAssetReaderOutput];
  
  // start reading
  
  BOOL worked = [aVAssetReader startReading];
  
  if (worked == FALSE) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"status = %d", (int)status);
    NSLog(@"error = %@", [error description]);
    
    return FALSE;
  }
  
  // Read N frames as CoreVideo buffers and invoke callback
  
  BOOL allFramesEncodedSuccessfully = TRUE;
  
  // Read N frames, convert to BGRA pixels
  
  for ( int i = 0; 1; i++ ) @autoreleasepool {
    
    CMSampleBufferRef sampleBuffer = NULL;
    sampleBuffer = [aVAssetReaderOutput copyNextSampleBuffer];
    
    if (sampleBuffer == NULL) {
      // Another frame could not be loaded, this is the normal
      // termination condition at the end of the file.
      break;
    }
    
    // Process BGRA data in buffer, crop and then read and combine
    
    CVImageBufferRef imageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBufferRef == NULL) {
      NSLog(@"CMSampleBufferGetImageBuffer() returned NULL at frame %d", i);
      allFramesEncodedSuccessfully = FALSE;
      break;
    }
    
    CVPixelBufferRef pixBuffer = imageBufferRef;
    
    BOOL worked = [self encodeAndAppendToArray:pixBuffer
                                   frameOffset:i
                                    renderSize:renderSize
                            encodedH264Buffers:encodedH264Buffers
                                   resNoSuffix:resNoSuffix];
    
    CFRelease(sampleBuffer);
    
    if (!worked) {
      allFramesEncodedSuccessfully = FALSE;
      break;
    }
  }
  
  [aVAssetReader cancelReading];
  
  if (allFramesEncodedSuccessfully == FALSE) {
    return FALSE;
  } else {
    return TRUE;
  }
}

// Previous API compat

+ (NSArray*) recompressKeyframesOnBackgroundThread:(NSString*)resourceName
                                     frameDuration:(float)frameDuration
                                        renderSize:(CGSize)renderSize
                                        aveBitrate:(int)aveBitrate
{
  NSMutableArray *encodedH264Buffers = [NSMutableArray array];
  
  @autoreleasepool {
    [self recompressKeyframesOnBackgroundThreadImpl:resourceName
                                      frameDuration:frameDuration
                                         renderSize:renderSize
                                         aveBitrate:aveBitrate
                                 encodedH264Buffers:encodedH264Buffers];
  }
  
  NSArray *retArr;
  
  if (encodedH264Buffers.count == 0) {
    retArr = nil;
  } else {
    retArr = [NSArray arrayWithArray:encodedH264Buffers];
  }
  
  encodedH264Buffers = nil;
  
  return retArr;
}

// Decompress and then recompress each frame of H264 video as keyframes that
// can be rendered directly without holding a stream decode resource open.
// If an error is encountered during the encode/decode process then nil
// is returned (this can happen when app is put into the background)

+ (BOOL) recompressKeyframes:(NSString*)resourceName
               frameDuration:(float)frameDuration
                  renderSize:(CGSize)renderSize
                  aveBitrate:(int)aveBitrate
                      frames:(NSMutableArray*)frames
{
  //dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
  
  @autoreleasepool {
    [self recompressKeyframesOnBackgroundThreadImpl:resourceName
                                      frameDuration:frameDuration
                                         renderSize:renderSize
                                         aveBitrate:aveBitrate
                                 encodedH264Buffers:frames];
  }

  //});
  
  //[NSThread sleepForTimeInterval:0.1];
  
  BOOL worked;
  
  if (frames.count == 0) {
    worked = FALSE;
  } else {
    worked = TRUE;
  }
  
  return worked;
}

// This implementation is meant to be called from inside an autorelease block
// so that tmp objects created in the scope of this method execution will
// be cleaned up even if recompressKeyframesOnBackgroundThread is invoked
// over and over in a loop or without leaving a calling scope.
//
// Decompress and then recompress each frame of H264 video as keyframes that
// can be rendered directly without holding a stream decode resource open.
// If an error is encountered during the encode/decode process then nil
// is returned (this can happen when app is put into the background)

+ (void) recompressKeyframesOnBackgroundThreadImpl:(NSString*)resourceName
                                     frameDuration:(float)frameDuration
                                        renderSize:(CGSize)renderSize
                                        aveBitrate:(int)aveBitrate
                                    encodedH264Buffers:(NSMutableArray*)encodedH264Buffers
{
#if defined(LOGGING)
  NSLog(@"recompressKeyframesOnBackgroundThread");
#endif // LOGGING
  
  // This operation cannot be executed on the main thread!
  //NSAssert([NSThread isMainThread] == FALSE, @"isMainThread");

  [encodedH264Buffers removeAllObjects];
  
  NSString *resTail = [resourceName lastPathComponent];
  
  NSString* movieFilePath = [[NSBundle mainBundle]
                             pathForResource:resTail ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  
  // Previously, asYUV was set to TRUE on device in an attempt to get the best
  // performance by avoiding YUV->RGB->YUV conversion, but it seems to produce
  // some slightly off colors in the reencoded video. Convert the initial movie
  // data to RGB and then encode from RGB so that the defaults match whatever iOS
  // is doing with 601 and 709 automatic detection.

  BOOL asYUV = TRUE;
  
//  BOOL asYUV = TRUE;
//#if TARGET_IPHONE_SIMULATOR
//  asYUV = FALSE; // Force BGRA buffer when running in simulator
//#endif // TARGET_IPHONE_SIMULATOR
  
  // Setup frame encoder that will encode each frame
  
  //H264FrameEncoder *frameEncoder = [[H264FrameEncoder alloc] init];
  
  // Hard coded to 24 FPS
  //frameEncoder.frameDuration = 1.0f/24;
  //frameEncoder.frameDuration = frameDuration;
  
  // Larger than original but not too big
  
//  frameEncoder.aveBitrate = 5000000;
  //frameEncoder.aveBitrate = aveBitrate;
  
  // Encode each frame, one at a time, so that totaly memory used is minimized
  
  BOOL worked = [self decodeCoreVideoFramesFromMOV:movieFilePath
                                             asYUV:asYUV
                                        renderSize:renderSize
                                encodedH264Buffers:encodedH264Buffers];

  if (worked == FALSE) {
    NSLog(@"decodeCoreVideoFramesFromMOV failed for %@", movieFilePath);
    
    [encodedH264Buffers removeAllObjects];
  } else {
#if defined(LOGGING)
    int totalEncodeNumBytes = 0;
    for ( id obj in encodedH264Buffers ) {
      CMSampleBufferRef sampleBuffer = (__bridge CMSampleBufferRef) obj;
      if (1 || asYUV) {
        totalEncodeNumBytes += (int) CVPixelBufferGetDataSize((CVPixelBufferRef)sampleBuffer);
      } else {
        totalEncodeNumBytes += (int) CMSampleBufferGetSampleSize(sampleBuffer, 0);
      }
    }
    int totalkb = totalEncodeNumBytes / 1000;
    int totalmb = totalkb / 1000;
    NSLog(@"encoded \"%@\" as %d frames", resTail, (int)encodedH264Buffers.count);
    NSLog(@"total encoded num bytes %d, %d kB, %d mB", totalEncodeNumBytes, totalkb, totalmb);
#endif // LOGGING
  }
  
  //[frameEncoder endSession];
}

@end
