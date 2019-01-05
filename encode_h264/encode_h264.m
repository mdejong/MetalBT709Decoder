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

#import "BGDecodeEncode.h"

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
      NSLog(@"Failed to start export session with movie size %d x %d", width, height);
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
      
      // Verify that the pixel buffer uses the BT.709 colorspace at this
      // points. This should have been defined inside the fill method.
      
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
#else
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
  
  // Drawing into the same colorspace as the input will simply memcpy(),
  // no colorspace mapping and no gamma shift.
  
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(imageRef);
  
#if defined(DEBUG)
  {
    CGColorSpaceRef inputColorspace = colorSpace;
    
    BOOL inputIsBT709Colorspace = FALSE;
    
    {
      CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
      
      NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
      NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
      
      if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
        inputIsBT709Colorspace = TRUE;
      }
      
      CGColorSpaceRelease(colorspace);
    }
    
    assert(inputIsBT709Colorspace == TRUE);
  }
#endif // DEBUG
  
  CGContextRef bitmapContext =
  CGBitmapContextCreate(pxdata, size.width, size.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
  if (bitmapContext == NULL) {
    NSAssert(FALSE, @"CGBitmapContextCreate() failed");
  }
  
  CGContextDrawImage(bitmapContext, CGRectMake(0, 0, size.width, size.height), imageRef);
  
  CGContextRelease(bitmapContext);
  
  CVPixelBufferFillExtendedPixels(buffer);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
  
  // Tell CoreVideo what colorspace the pixels were rendered in
  
  [BGRAToBT709Converter setBT709Colorspace:buffer];
  
  return;
}

// Emit an array of float data as a CSV file, the
// labels should be NSString, these define
// the emitted labels in column 0.

+ (BOOL) writeTableToCSV:(NSString*)filename
               labelsArr:(NSArray*)labelsArr
               valuesArr:(NSArray*)valuesArr
{
  //NSString *tmpDir = NSTemporaryDirectory();
  NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *path = [dirName stringByAppendingPathComponent:filename];
  FILE *csvFile = fopen([path UTF8String], "w");
  if (csvFile == NULL) {
    return FALSE;
  }
  
  int numColumns = (int) [labelsArr count];
  
  for (int i = 0; i < numColumns; i++) {
    NSString *label = labelsArr[i];
    fprintf(csvFile, "%s", [label UTF8String]);
    
    if (i < (numColumns - 1)) {
      fprintf(csvFile, ",");
    }
  }
  fprintf(csvFile, "\n");
  
  for ( NSArray *tuple in valuesArr ) {
    for (int i = 0; i < numColumns; i++) {
      float v = [tuple[i] floatValue];
      
      fprintf(csvFile, "%.4f", v);
      
      if (i < (numColumns - 1)) {
        fprintf(csvFile, ",");
      }
    }
    fprintf(csvFile, "\n");
    //
    //    float y1 = [tuple[0] floatValue];
    //    float y2 = [tuple[1] floatValue];
    //
    //    NSLog(@"[%4d] (y1, y2) = %.4f,%.4f", x, y1, y2);
    //    x++;
    //
    //    fprintf(csvFile, "%.4f,%.4f\n", y1, y2);
  }
  
  fclose(csvFile);
  NSLog(@"wrote %@", path);
  return TRUE;
}

// Util methods to allocate a tmp buffer to hold pixel data
// and render into a new CGFrameBuffer object.

+ (CGFrameBuffer*) convertFromColorspaceToColorspace:(CGImageRef)inImage
                                                 bpp:(int)bpp
                                 convertToColorspace:(CGColorSpaceRef)convertToColorspace
{
  int width = (int) CGImageGetWidth(inImage);
  int height = (int) CGImageGetHeight(inImage);

  CGFrameBuffer *convertedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
  
  //CGColorSpaceRef cs = CGColorSpaceCreateWithName(convertToColorspace);
  convertedFB.colorspace = convertToColorspace;
  //CGColorSpaceRelease(convertToColorspace);
  
  BOOL worked = [convertedFB renderCGImage:inImage];
  NSAssert(worked, @"renderCGImage");
  
  if (!worked) {
    return nil;
  }
  
  return convertedFB;
}

// Convert pixels in one colorspace into a second colorspace, in the
// event that the pixels share the same white point and color bounds
// this invocation will only adjust the gamma.

+ (CGFrameBuffer*) convertFromColorspaceToColorspace:(CGFrameBuffer*)inFB
                                 convertToColorspace:(CGColorSpaceRef)convertToColorspace
{
  int width = (int) inFB.width;
  int height = (int) inFB.height;
  
  CGFrameBuffer *convertedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:inFB.bitsPerPixel width:width height:height];

  //CGColorSpaceRef cs = CGColorSpaceCreateWithName(convertToColorspace);
  convertedFB.colorspace = convertToColorspace;
  //CGColorSpaceRelease(convertToColorspace);
  
  CGImageRef inFBImageRef = [inFB createCGImageRef];
  
  [convertedFB renderCGImage:inFBImageRef];
  
  CGImageRelease(inFBImageRef);
  
  return convertedFB;
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
void exportVideo(CGImageRef inCGImage, NSString *outPath) {
  //AVAsset* inAsset = [AVAsset assetWithURL:inURL];
  
  //NSString *resFilename = @"Gamma_test_HD_75Per_24BPP_sRGB_HD.png";
  //NSString *path = [[NSBundle mainBundle] pathForResource:resFilename ofType:nil];
  
  //UIImage *inImage = [UIImage imageNamed:@"Gamma_test_HD_75Per_24BPP_sRGB_HD.png"];
  
  //NSString *outFilename = @"Encoded.m4v";
  //NSString *outFilename = ;
  
  NSURL *outUrl = [NSURL fileURLWithPath:outPath];
  
  // If the output file already exists, remove it before encoding?
  {
    // rm -f file
    [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  }
  
  [EncoderImpl blockingEncode:inCGImage outputPathURL:outUrl];
  
  NSLog(@"wrote %@", outPath);
}

int process(NSString *inPNGStr, NSString *outM4vStr, ConfigurationStruct *configSPtr) {
  // Read PNG
  
  NSLog(@"loading %@", inPNGStr);

  CGImageRef inImage;
  
  if ((0)) {
    // Generate 16x16 image that contains all the grayscale values in linear
    // RGB and then map these values to gamma adjusted values in the BT.709 space
    
    int width = 16;
    int height = 16;
    
    // When the Apple supplied BT.709 colorspace is used and every grayscale
    // input value is written into the output, the gamma adjustment in
    // converting from this colorpace to the linear colorspace can be
    // determined by graphing the gamma adjustment.
    
    // Mapping each value in this colorspace to linear seems to make use
    // of a gamma = 1.961
    
    CGFrameBuffer *identity709FB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    identity709FB.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    uint32_t *pixelsPtr = (uint32_t *) identity709FB.pixels;
    
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        int offset = (row * width) + col;
        uint32_t G = offset & 0xFF;
        uint32_t grayPixel = (0xFF << 24) | (G << 16) | (G << 8) | (G);
        pixelsPtr[offset] = grayPixel;
      }
    }
    
    if ((1)) {
      // Emit png with linear colorspace
      
      NSString *filename = [NSString stringWithFormat:@"TestBT709InAsLinear.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [identity709FB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }

    // Convert grayscale range to BT.709 gamma adjusted values
    
    CGColorSpaceRef bt709cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    
    CGFrameBuffer *bt709FB = [EncoderImpl convertFromColorspaceToColorspace:identity709FB convertToColorspace:bt709cs];
    
    CGColorSpaceRelease(bt709cs);
    
    if ((1)) {
      // Emit png with linear colorspace
      
      NSString *filename = [NSString stringWithFormat:@"TestBT709InAsBT709.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [bt709FB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }
    
    // Gather value mappings overthe entire byte range
    
    {
      NSArray *labels = @[ @"G", @"R", @"PG", @"PR" ];
      
      NSMutableArray *yPairsArr = [NSMutableArray array];
      
      uint32_t *pixelPtr = (uint32_t *) bt709FB.pixels;
      
      NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
      
      for (int i = 0; i < 256; i++) {
        uint32_t pixel = pixelPtr[i];
        int grayVal = pixel & 0xFF;
        rangeMap[@(i)] = @(grayVal);
        
        // Use (Y 128 128) to decode grayscale value to a RGB value.
        // Since the values for Y are setup with a gamma, need to
        // know the gamma to be able to decode ?
        
        // Float amount of the grayscale range that input grayscale
        // value corresponds to.
        
        float percentOfGrayscale = i / 255.0f;
        float percentOfRange = grayVal / 255.0f;
        
        [yPairsArr addObject:@[@(i), @(grayVal), @(percentOfGrayscale), @(percentOfRange)]];
      }
      
      NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
      NSLog(@"");
      
      [EncoderImpl writeTableToCSV:@"Encode_lin_to_709_GR.csv" labelsArr:labels valuesArr:yPairsArr];
    }
    
  } else if ((0)) {
    // Generate a HD image at 1920x1080
    
    int width = 1920;
    int height = 1080;
    
    // When the Apple supplied BT.709 colorspace is used and every grayscale
    // input value is written into the output, the gamma adjustment in
    // converting from this colorpace to the linear colorspace can be
    // determined by graphing the gamma adjustment.
    
    // Mapping each value in this colorspace to linear seems to make use
    // of a gamma = 1.961
    
    CGFrameBuffer *identity709FB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    identity709FB.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    uint32_t *pixelsPtr = (uint32_t *) identity709FB.pixels;
    
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        int offset = (row * width) + col;
        uint32_t G = col & 0xFF;
        uint32_t grayPixel = (0xFF << 24) | (G << 16) | (G << 8) | (G);
        pixelsPtr[offset] = grayPixel;
      }
    }
    
    if ((0)) {
      // Emit Test.png with colorspace already configured as BT.709
      
      NSString *filename = [NSString stringWithFormat:@"Test.png"];
      NSString *tmpDir = NSTemporaryDirectory();
      NSString *path = [tmpDir stringByAppendingPathComponent:filename];
      NSData *pngData = [identity709FB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }

    // Convert to Linear colorspace
    
    CGColorSpaceRef linRGB = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    
    CGFrameBuffer *linRGBFB = [EncoderImpl convertFromColorspaceToColorspace:identity709FB convertToColorspace:linRGB];
    
    CGColorSpaceRelease(linRGB);
    
    // Represent linear framebuffer as CGIamgeRef
    
    inImage = [linRGBFB createCGImageRef];
  } else {
    inImage = makeImageFromFile(inPNGStr);
    //  if (inImage == NULL) {
    //  }
  }
  
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
  BOOL inputIsBT709Colorspace = FALSE;
  
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

  {
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    
    NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsBT709Colorspace = TRUE;
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
  } else if (inputIsBT709Colorspace) {
    printf("input is already in BT.709 colorspace\n");
  } else {
    printf("will convert from input colorspace to BT709 gamma encoded space:\n");
    NSString *desc = [(__bridge id)inputColorspace description];
    printf("%s\n", [desc UTF8String]);
  }
  
  if (1) {
    // Render into sRGB buffer in order to dump the first input pixel in terms of sRGB
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage bpp:24 convertToColorspace:cs];

    CGColorSpaceRelease(cs);
    
    uint32_t pixel = ((uint32_t*) convertedFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel   sRGB (R G B) (%3d %3d %3d)\n", R, G, B);
  }
  
  if (1) {
    // Render into linear (gamma 1.0) RGB buffer and print
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage bpp:24 convertToColorspace:cs];
    
    CGColorSpaceRelease(cs);
    
    uint32_t pixel = ((uint32_t*) convertedFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel linRGB (R G B) (%3d %3d %3d)\n", R, G, B);
  }

  if (inputIsBT709Colorspace == FALSE) {
    // The input colorspace is converted into the BT.709 colorspace,
    // typically this will only adjust the gamma of sRGB input pixels
    // to match the gamma = 1.961 approach defined by Apple. Use of
    // this specific colorpace indicates that another colorspace
    // change will not be needed before encoding the data to H264.

    CGColorSpaceRef convertToColorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage
                                                                            bpp:24
                                                            convertToColorspace:convertToColorspace];
    
    CGColorSpaceRelease(convertToColorspace);
    
    CGImageRelease(inImage);
    
    inImage = [convertedFB createCGImageRef];
  }
  
  if (1) {
    // Render into sRGB buffer in order to dump the first input pixel in terms of sRGB

    CGColorSpaceRef cs = CGImageGetColorSpace(inImage);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage bpp:24 convertToColorspace:cs];
    
    //CGColorSpaceRelease(cs);
    
    uint32_t pixel = ((uint32_t*) convertedFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel  BT709 (R G B) (%3d %3d %3d)\n", R, G, B);
  }
  
  // Load BGRA pixel data into BGRA CoreVideo pixel buffer, note that
  // all incoming pixels should have been converted to BT.709 at
  // this point.
  
  NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outPath = [dirName stringByAppendingPathComponent:outM4vStr];
  
  exportVideo(inImage, outPath);
  
  if (0) {
    // Render into sRGB buffer in order to dump the first input pixel in terms of sRGB
    
    CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];

    cgFramebuffer.colorspace = CGImageGetColorSpace(inImage);
    
//#if TARGET_OS_OSX
//    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
//    cgFramebuffer.colorspace = cs;
//    CGColorSpaceRelease(cs);
//#endif // TARGET_OS_OSX
    
    [cgFramebuffer renderCGImage:inImage];
    
//    uint32_t pixel = ((uint32_t*) cgFramebuffer.pixels)[0];
//    int B = pixel & 0xFF;
//    int G = (pixel >> 8) & 0xFF;
//    int R = (pixel >> 16) & 0xFF;
//    printf("first pixel   sRGB (R G B) (%3d %3d %3d)\n", R, G, B);
    
    for (int i = 0; i < 256; i++) {
      uint32_t pixel = ((uint32_t*) cgFramebuffer.pixels)[i];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("(R G B) (%3d %3d %3d)\n", R, G, B);
    }

  }

  if (0) {
    // Render into linear (gamma 1.0) RGB buffer and print
    
    CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    cgFramebuffer.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    [cgFramebuffer renderCGImage:inImage];
    
    uint32_t pixel = ((uint32_t*) cgFramebuffer.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("pixel linRGB (R G B) (%3d %3d %3d)\n", R, G, B);

    for (int i = 0; i < 256; i++) {
      uint32_t pixel = ((uint32_t*) cgFramebuffer.pixels)[1];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("pixel linRGB (R G B) (%3d %3d %3d)\n", R, G, B);
    }
  }
  
  CGImageRelease(inImage);
  
  if ((0)) {
    // Load Y Cb Cr values from movie that was just written by reading
    // values into a pixel buffer.
    
    NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:outPath
                                                                      frameDuration:1.0/30
                                                                         renderSize:CGSizeMake(1920, 1080)
                                                                         aveBitrate:0];
    NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
    
    // Grab just the first texture, return retained ref
    
    CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
    
    CVPixelBufferRetain(cvPixelBuffer);
    
    // Load Y values, ignore Cb Cr
    
    NSMutableArray *yPairsArr = [NSMutableArray array];
    
    NSMutableData *yData = [NSMutableData data];
    NSMutableData *cbData = [NSMutableData data];
    NSMutableData *crData = [NSMutableData data];
    
    BOOL worked = [BGRAToBT709Converter copyYCBCr:cvPixelBuffer
                               Y:yData
                              Cb:cbData
                              Cr:crData
                            dump:TRUE];
    assert(worked);
    
    // Iterte over every Y value and make unique
    
    uint8_t *yPtr = (uint8_t *) yData.bytes;
    
    if ((1)) {
      printf("first pixel (Y) (%3d)\n", yPtr[0]);
    }
    
    // 0 5  -> 16
    // 5 10 -> 17
    
    if ((0)) {
    
    NSArray *labels = @[ @"G", @"R", @"PG", @"PR" ];
    
    NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < 256; i++) {
      int yVal = yPtr[i];
      rangeMap[@(i)] = @(yVal);
      
      // Use (Y 128 128) to decode grayscale value to a RGB value.
      // Since the values for Y are setup with a gamma, need to
      // know the gamma to be able to decode ?
      
      // Float amount of the grayscale range that input grayscale
      // value corresponds to.
      
      float percentOfGrayscale = ((float)i) / 255.0f;
      
      float percentOfRange = (yVal - 16) / (237.0f - 16);
      
      [yPairsArr addObject:@[@(i), @(yVal), @(percentOfGrayscale), @(percentOfRange)]];
    }

    NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
    NSLog(@"");
    
    //int yVal = [yNum intValue];
    //[yPairsArr addObject:@[@(yVal)]];
    
    [EncoderImpl writeTableToCSV:@"EncodeGR.csv" labelsArr:labels valuesArr:yPairsArr];
      
    }
  }
  
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

