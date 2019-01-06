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

#import "H264Encoder.h"

#import "CGFrameBuffer.h"
#import "BGRAToBT709Converter.h"

#import "BGDecodeEncode.h"

#import "BT709.h"

typedef struct {
  int fps;
} ConfigurationStruct;

void usage() {
  printf("encode_h264 ?OPTIONS? IN.png OUT.m4v\n");
  fflush(stdout);
}

// Helper class

@interface EncoderImpl : NSObject <H264EncoderFrameSource, H264EncoderResult>

//- (CGImageRef) imageForFrame:(int)frameNum;
//- (BOOL) hasMoreFrames;

@property (nonatomic, assign) int frameNum;

// Array of CGImageRef

@property (nonatomic, retain) NSMutableArray *frames;

@end

@implementation EncoderImpl

// Provide frames for H264 encoder interface

- (CGImageRef) imageForFrame:(int)frameNum
{
  CGImageRef imageRef = (__bridge CGImageRef) [self.frames objectAtIndex:frameNum];
  
  self.frameNum = self.frameNum + 1;
  
  return imageRef;
}

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been encoded.

- (BOOL) hasMoreFrames
{
  if (self.frameNum < self.frames.count) {
    return TRUE;
  } else {
    return FALSE;
  }
}

- (void)encoderResult:(H264EncoderErrorCode)code {
  NSLog(@"encoderResult : %@", [H264Encoder ErrorCodeToString:code]);
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
  // Allocate a H264Encoder instance and declare a util
  // object that feeds CoreGraphics images to the encoder
  // and take care of reporting an error condition.
  
  H264Encoder *encoder = [H264Encoder h264Encoder];
  
  EncoderImpl *impl = [[EncoderImpl alloc] init];
  
  encoder.frameSource = impl;
  encoder.encoderResult = impl;
  
  impl.frames = [NSMutableArray array];
  [impl.frames addObject:(__bridge id)inCGImage];
  
  float fps = 1.0f; // 1 FPS
  
  int width = (int) CGImageGetWidth(inCGImage);
  int height = (int) CGImageGetHeight(inCGImage);
  
  CGSize renderSize = CGSizeMake(width, height);
  
  [encoder encodeframes:outPath
          frameDuration:fps
             renderSize:renderSize
             aveBitrate:0];
  
  // Wait until the encoding operation is complet
  
  [encoder blockUntilFinished];
  
  NSLog(@"wrote %@", outPath);
}

int process(NSString *inPNGStr, NSString *outM4vStr, ConfigurationStruct *configSPtr) {
  // Read PNG
  
  NSLog(@"loading %@", inPNGStr);

  CGImageRef inImage;
  
  if ((0)) {
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

  if (0 && inputIsBT709Colorspace == FALSE) {
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
    // The block above should have converted the input into BT.709, assuming that
    // is the case print the converted values after a nop conversion to BT.709.

    CGColorSpaceRef convertToColorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage bpp:24 convertToColorspace:convertToColorspace];
    
    CGColorSpaceRelease(convertToColorspace);
    
    uint32_t pixel = ((uint32_t*) convertedFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel  BT709 (R G B) (%3d %3d %3d)\n", R, G, B);
  }
  
  if (1) {
    // Print RGB in the colorspace defined for the input image
    
    CGColorSpaceRef cs = CGImageGetColorSpace(inImage);
    
    CGFrameBuffer *convertedFB = [EncoderImpl convertFromColorspaceToColorspace:inImage bpp:24 convertToColorspace:cs];
    
    //CGColorSpaceRelease(cs);
    
    uint32_t pixel = ((uint32_t*) convertedFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel  INPUT (R G B) (%3d %3d %3d)\n", R, G, B);
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
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    cgFramebuffer.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    [cgFramebuffer renderCGImage:inImage];
    
    uint32_t *pixelPtr = (uint32_t*) cgFramebuffer.pixels;
    
    for (int i = 0; i < 256; i++) {
      uint32_t pixel = pixelPtr[i];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("sRGB (R G B) (%3d %3d %3d)\n", R, G, B);
    }

  }

  if (0) {
    // Render into linear (gamma 1.0) RGB buffer and print
    
    CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    cgFramebuffer.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    [cgFramebuffer renderCGImage:inImage];
    
    uint32_t *pixelPtr = (uint32_t*) cgFramebuffer.pixels;

    for (int i = 0; i < (256 * 2); i++) {
      uint32_t pixel = pixelPtr[i];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("linRGB (R G B) (%3d %3d %3d)\n", R, G, B);
    }
  }
  
  CGImageRelease(inImage);
  
  if ((1)) {
    // Load Y Cb Cr values from movie that was just written by reading
    // values into a pixel buffer.
    
    NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:outPath
                                                                      frameDuration:1.0/30
                                                                         renderSize:CGSizeMake(width, height)
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
    
    NSMutableArray *mYAverages = [NSMutableArray array];
    
    for (int i = 0; i < (2 * 256); i += 2) {
      int yVal1 = yPtr[i];
      int yVal2 = yPtr[i+1];
      
      int ave = (int) round((yVal1 + yVal2) / 2.0);
      
      [mYAverages addObject:@(ave)];
    }
    
    assert([mYAverages count] == 256);
    
    if ((0)) {
      // Write the Y values out to stdout, assumes there are not too many
      
      const int dumpGrayOut = 0;
      
      if (dumpGrayOut) {
        printf("dumpGrayOut:\n");
      }
      
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          int offset = (row * width) + col;
          int Y = yPtr[offset];
          
          if (dumpGrayOut) {
            printf("%3d ", Y);
          }
        }
        
        if (dumpGrayOut) {
          printf("\n");
        }
      }
    }
    
    // Full mapping of output values to CSV file to determine gamma
    
    if ((1)) {
    
    NSArray *labels = @[ @"G", @"R", @"PG", @"PR", @"AG", @"BT" ];
    
    NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < mYAverages.count; i++) {
      NSNumber *yNum = mYAverages[i];
      int yVal = [yNum intValue];
      rangeMap[@(i)] = @(yVal);
      
      // Use (Y 128 128) to decode grayscale value to a RGB value.
      // Since the values for Y are setup with a gamma, need to
      // know the gamma to be able to decode ?
      
      // Float amount of the grayscale range that input grayscale
      // value corresponds to.
      
      float percentOfGrayscale = ((float)i) / 255.0f;
      
      // Weirdly, max seems to be 237 instead of 235 ? Why Apple?
      int minY = 16;
      int maxY = 237;
      
      //float percentOfRange = (yVal - 16) / (237.0f - (16+2));
      float percentOfRange = (yVal - minY) / (float)(maxY - minY);
      
      float appleGamma196 = AppleGamma196_linearNormToNonLinear(percentOfGrayscale);
      
      float bt709Gamma12 = BT709_linearNormToNonLinear(percentOfGrayscale);
      
      [yPairsArr addObject:@[@(i), @(yVal), @(percentOfGrayscale), @(percentOfRange), @(appleGamma196), @(bt709Gamma12)]];
    }

    NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
    
    [EncoderImpl writeTableToCSV:@"EncodeGR.csv" labelsArr:labels valuesArr:yPairsArr];
    NSLog(@"");
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

