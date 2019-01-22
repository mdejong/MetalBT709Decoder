//
//  gamma_write.m
//
//  Created by Mo DeJong on 12/31/18.
//
//  Command line utility to emit test image
//  that can be passed to H264 encoder to
//  verify that encoding is working properly.
//  This test image is specific to 4:2:0
//  YCbCr format since it emits blocks of
//  2x2 with a known grayscale value. This is
//  so that 2 pixels next to each other do not
//  change the Cb or Cr value of the neighbor
//  pixel which changes the encoded Y value.

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
  printf("gamma_write OUT.m4v\n");
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

int process(NSString *outPNGStr, ConfigurationStruct *configSPtr) {
  // Read PNG
  
  int genWidth = 2 * 256;
  
  if ((1)) {
    // Generate 16x16 image that contains all the grayscale values in linear
    // RGB and then map these values to gamma adjusted values in the BT.709 space
    
    int width = 1920;
    int height = 1080;
    
    // When the Apple supplied BT.709 colorspace is used and every grayscale
    // input value is written into the output, the gamma adjustment in
    // converting from this colorpace to the linear colorspace can be
    // determined by graphing the gamma adjustment.
    
    // Mapping each value in this colorspace to linear seems to make use
    // of a gamma = 1.961
    
    CGFrameBuffer *identityFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    //CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    identityFB.colorspace = cs;
    CGColorSpaceRelease(cs);
    
    uint32_t *pixelsPtr = (uint32_t *) identityFB.pixels;
    
    const int dumpGrayOut = 0;
    
    if (dumpGrayOut) {
      printf("dumpGrayOut:\n");
    }
    
//    for (int row = 0; row < height; row++) {
//      for (int col = 0; col < width; col++) {
//        int offset = (row * width) + col;
//        int rd2 = row / 2;
//        int cd2 = col / 2;
//        int GForPixel = (rd2 * width/2) + cd2;
//        uint32_t G = GForPixel & 0xFF;
//        uint32_t grayPixel = (0xFF << 24) | (G << 16) | (G << 8) | (G);
//        pixelsPtr[offset] = grayPixel;
//
//        if (dumpGrayOut) {
//          printf("%3d ", G);
//        }
//      }
//
//      if (dumpGrayOut) {
//        printf("\n");
//      }
//    }
    
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        int offset = (row * width) + col;
        //int rd2 = row / 2;
        int cd2 = col / 2;
        int GForPixel = cd2;
        uint32_t G = GForPixel & 0xFF;
        uint32_t grayPixel = (0xFF << 24) | (G << 16) | (G << 8) | (G);
        pixelsPtr[offset] = grayPixel;
        
        if (dumpGrayOut) {
          printf("%3d ", G);
        }
      }
      
      if (dumpGrayOut) {
        printf("\n");
      }
    }
    
    if ((0)) {
      // Emit png with linear colorspace
      
      NSString *filename = [NSString stringWithFormat:@"TestHDFirst20PerSRGB.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [identityFB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }
    
    // Convert identity grayscale values to sRGB gamma adjusted values
    // and emit as a PNG. This set of gamma adjusted values can be
    // compared to the known identity values for [0, 255] to see
    // how large the gamma shift was.
    
    CGColorSpaceRef sRGBcs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    CGFrameBuffer *sRGBFB = [EncoderImpl convertFromColorspaceToColorspace:identityFB convertToColorspace:sRGBcs];
    
    CGColorSpaceRelease(sRGBcs);
    
    if ((0)) {
      // Emit png in sRGBcolorspace
      
      NSString *filename = [NSString stringWithFormat:@"TestHDAsSRGB.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [sRGBFB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }
    
    // Convert grayscale range to BT.709 gamma adjusted values
    
    CGColorSpaceRef bt709cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
    
    CGFrameBuffer *bt709FB = [EncoderImpl convertFromColorspaceToColorspace:identityFB convertToColorspace:bt709cs];
    
    CGColorSpaceRelease(bt709cs);
    
    if ((1)) {
      // Emit png in BT.709 colorspace
      
      NSString *filename = [NSString stringWithFormat:@"TestHDAsBT709.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [bt709FB formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      NSLog(@"wrote %@", path);
    }
    
    // Gather value mappings over the entire byte range for lin -> 709
    
    if ((1))
    {
      NSArray *labels = @[ @"G", @"R", @"PG", @"PR", @"AG", @"709" ];
      
      NSMutableArray *yPairsArr = [NSMutableArray array];
      
      // CSV generation logic below depends on getting 256 values that
      // represent the range.
      
      uint32_t *pixelPtr = (uint32_t *) bt709FB.pixels;
      
      NSMutableArray *mSamples = [NSMutableArray array];
      
      for (int i = 0; i < genWidth; i += 2) {
        uint32_t pixel = pixelPtr[i];
        int grayVal = pixel & 0xFF;
        [mSamples addObject:@(grayVal)];
      }
      
      assert([mSamples count] == 256);
      
      NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
      
      for (int i = 0; i < 256; i++) {
        int grayVal = [mSamples[i] intValue];
        rangeMap[@(i)] = @(grayVal);
        
        // Use (Y 128 128) to decode grayscale value to a RGB value.
        // Since the values for Y are setup with a gamma, need to
        // know the gamma to be able to decode ?
        
        // Float amount of the grayscale range that input grayscale
        // value corresponds to.
        
        float percentOfGrayscale = i / 255.0f;
        float percentOfRange = grayVal / 255.0f;
        
        float appleGammaAdjusted = 0.0;
        
        // This actually appears to be a better approximzation of the actualy current
        // output, so why would anything about the Apple 1961 be useful ??
        
        // Perhaps you are only meant to decode with the 1.961 function?
        
        float rec709GammaAdjusted = BT709_linearNormToNonLinear(percentOfGrayscale);
        
        [yPairsArr addObject:@[@(i), @(grayVal), @(percentOfGrayscale), @(percentOfRange), @(appleGammaAdjusted), @(rec709GammaAdjusted)]];
      }
      
      NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
      NSLog(@"");
      
      [EncoderImpl writeTableToCSV:@"Encode_lin_to_709_GR.csv" labelsArr:labels valuesArr:yPairsArr];
    }

    // Gather value mappings over the entire byte range for lin -> sRGB
    
    if ((1))
    {
      NSArray *labels = @[ @"G", @"R", @"PG", @"PR", @"AG", @"sRGB" ];
      
      NSMutableArray *yPairsArr = [NSMutableArray array];
      
      // CSV generation logic below depends on getting 256 values that
      // represent the range.
      
      uint32_t *pixelPtr = (uint32_t *) sRGBFB.pixels;
      
      NSMutableArray *mSamples = [NSMutableArray array];
      
      for (int i = 0; i < genWidth; i += 2) {
        uint32_t pixel = pixelPtr[i];
        int grayVal = pixel & 0xFF;
        [mSamples addObject:@(grayVal)];
      }
      
      assert([mSamples count] == 256);
      
      NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
      
      for (int i = 0; i < 256; i++) {
        int grayVal = [mSamples[i] intValue];
        rangeMap[@(i)] = @(grayVal);
        
        // Use (Y 128 128) to decode grayscale value to a RGB value.
        // Since the values for Y are setup with a gamma, need to
        // know the gamma to be able to decode ?
        
        // Float amount of the grayscale range that input grayscale
        // value corresponds to.
        
        float percentOfGrayscale = i / 255.0f;
        float percentOfRange = grayVal / 255.0f;
        
        float appleGammaAdjusted = 0.0f;
                
        float sRGBGammaAdjusted = sRGB_linearNormToNonLinear(percentOfGrayscale);
        
        [yPairsArr addObject:@[@(i), @(grayVal), @(percentOfGrayscale), @(percentOfRange), @(appleGammaAdjusted), @(sRGBGammaAdjusted)]];
      }
      
      NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
      NSLog(@"");
      
      [EncoderImpl writeTableToCSV:@"Encode_lin_to_sRGB_GR.csv" labelsArr:labels valuesArr:yPairsArr];
    }

    // Emit CSV mapping of the grayscale values to 1.961 power function
    
    if ((1))
    {
      NSArray *labels = @[ @"G", @"R", @"PG", @"PR", @"AG", @"sRGB" ];
      
      NSMutableArray *yPairsArr = [NSMutableArray array];
      
      // CSV generation logic below depends on getting 256 values that
      // represent the range.
      
      uint32_t *pixelPtr = (uint32_t *) sRGBFB.pixels;
      
      NSMutableArray *mSamples = [NSMutableArray array];
      
      for (int i = 0; i < genWidth; i += 2) {
        uint32_t pixel = pixelPtr[i];
        int grayVal = pixel & 0xFF;
        [mSamples addObject:@(grayVal)];
      }
      
      assert([mSamples count] == 256);
      
      NSMutableDictionary *rangeMap = [NSMutableDictionary dictionary];
      
      for (int i = 0; i < 256; i++) {
        int grayVal = [mSamples[i] intValue];
        rangeMap[@(i)] = @(grayVal);
        
        // Use (Y 128 128) to decode grayscale value to a RGB value.
        // Since the values for Y are setup with a gamma, need to
        // know the gamma to be able to decode ?
        
        // Float amount of the grayscale range that input grayscale
        // value corresponds to.
        
        float percentOfGrayscale = i / 255.0f;
        float percentOfRange = grayVal / 255.0f;
        
        float appleGammaAdjusted = 0.0f;
        
        float sRGBGammaAdjusted = sRGB_linearNormToNonLinear(percentOfGrayscale);
        
        [yPairsArr addObject:@[@(i), @(grayVal), @(percentOfGrayscale), @(percentOfRange), @(appleGammaAdjusted), @(sRGBGammaAdjusted)]];
      }
      
      NSLog(@"rangeMap contains %d values", (int)rangeMap.count);
      NSLog(@"");
      
      [EncoderImpl writeTableToCSV:@"Encode_lin_to_sRGB_GR.csv" labelsArr:labels valuesArr:yPairsArr];
    }
  }
  
  return 1;
}

int main(int argc, const char * argv[]) {
  int retcode = 0;
  
  @autoreleasepool {
    char *outPNG = NULL;
    
    //int fps = 30; // Default to 30 frames per second
    //int fps = 1;
    
    ConfigurationStruct configS;
    configS.fps = 1;
    
    if (argc == 2) {
      // No options, input and output files indicated
      outPNG = (char *) argv[1];
    } else {
      usage();
      exit(1);
    }
    
    NSString *outPNGStr = [NSString stringWithFormat:@"%s", outPNG];
    
    retcode = process(outPNGStr, &configS);
  }
  
  exit(retcode);
  return retcode;
}

