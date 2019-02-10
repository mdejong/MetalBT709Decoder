//
//  srgb_to_bt709.m
//
//  Created by Mo DeJong on 12/31/18.
//
//  Command line utility that reads a single image
//  or a series of images to a Y4M 4:2:0 video
//  file encoded as BT.709 colorspace pixels.
//  A y4m file can contain multiple video frames.

#import <Foundation/Foundation.h>

#import "CGFrameBuffer.h"
#import "BGRAToBT709Converter.h"

#import "sRGB.h"
#import "BT709.h"

#import "y4m_writer.h"

// Emit an array of float data as a CSV file, the
// labels should be NSString, these define
// the emitted labels in column 0.

static inline
BOOL writeTableToCSV(NSString *filename, NSArray* labelsArr, NSArray* valuesArr)
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

void usage() {
  printf("srgb_to_bt709 ?OPTIONS? OUTPUT.y4m\n");
  printf("OPTIONS:\n");
  printf("-frame F.png (input is a single frame)\n");
  printf("-frames F0001.png (first frame of N input frames)\n");
  printf("-gamma apple|srgb|linear (default is apple)\n");
  printf("-fps 1|15|24|2997|30|60 (default to 30 with -frames)\n");
  fflush(stdout);
}

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

// Dump image Y U V components and CSV file representing the output

static inline
int dump_image_meta(CGImageRef inImage,
                    CVPixelBufferRef cvPixelBuffer,
                    NSMutableData *Y,
                    NSMutableData *Cb,
                    NSMutableData *Cr)
{
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);

  // FIXME: should the format of the input image be constrained? If it is sRGB then
  // the boost is used, but what about linear input and BT.709 input?
  
  // FIXME: in the case where input is linear, need to use sRGB Linear colorspace
  // so that the RGB values correspond to known color coordinates.
  
  //  *transfer_fnc = kCVImageBufferTransferFunction_UseGamma;
  //  +            *gamma_level = CFNumberCreate(NULL, kCFNumberFloat32Type, &gamma);
  
  //CVPixelBufferRef cvPixelBuffer = [BGRAToBT709Converter createYCbCrFromCGImage:inImage isLinear:isLinearGamma];
  
  // Copy (Y Cb Cr) as (c0 c1 c2) in (c3 c2 c1 c0)
  
//  NSMutableData *Y = [NSMutableData data];
//  NSMutableData *Cb = [NSMutableData data];
//  NSMutableData *Cr = [NSMutableData data];
  
  const BOOL dump = FALSE;
  
  [BGRAToBT709Converter copyYCBCr:cvPixelBuffer Y:Y Cb:Cb Cr:Cr dump:dump];
  
  // Dump (Y Cb Cr) of first pixel
  
  uint8_t *yPtr = (uint8_t *) Y.bytes;
  uint8_t *cbPtr = (uint8_t *) Cb.bytes;
  uint8_t *crPtr = (uint8_t *) Cr.bytes;
  
  if (dump) {
    // Render into sRGB buffer in order to dump the first input pixel in terms of sRGB
    
    CGFrameBuffer *inFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    [inFB renderCGImage:inImage];
    
    uint32_t pixel = ((uint32_t*) inFB.pixels)[0];
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    printf("first pixel sRGB (R G B) (%d %d %d)", R, G, B);
  }
  
  if (dump) {
    int Y = yPtr[0];
    int Cb = cbPtr[0];
    int Cr = crPtr[0];
    printf(" -> (Y Cb Cr) (%d %d %d)\n", Y, Cb, Cr);
  }
  
  if (dump) {
    // Process YCbCr output with CoreImage to generate an output
    // sRGB image that checks decoding logic.
    
    CGFrameBuffer *decompFB = [BGRAToBT709Converter processYUVTosRGB:cvPixelBuffer];
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_RGB_from_YUV.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [decompFB formatAsPNG];
      
      NSLog(@"wrote %@", path);
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      if ((1)) {
        uint32_t pixel = ((uint32_t*) decompFB.pixels)[0];
        int B = pixel & 0xFF;
        int G = (pixel >> 8) & 0xFF;
        int R = (pixel >> 16) & 0xFF;
        printf("CoreImage first decompressed pixel sRGB (R G B) (%d %d %d)\n", R, G, B);
      }
    }
  }
  
  if ((0)) {
    // Process YCbCr output with vImage to decode
    
    vImage_Buffer dstBuffer;
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    BOOL worked = [BGRAToBT709Converter convertFromCoreVideoBuffer:cvPixelBuffer
                                                         bufferPtr:&dstBuffer
                                                        colorspace:cs];
    assert(worked);
    
    CGColorSpaceRelease(cs);
    
    // Copy BGRA pixels from dstBuffer to outBGRAPixels
    
    const int dstRowBytes = (int) dstBuffer.rowBytes;
    
    if ((1)) {
      printf("destBuffer %d x %d : R G B A\n", width, height);
      
      for (int row = 0; row < height; row++) {
        uint32_t *inRowPtr = (uint32_t*) (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
        
        for (int col = 0; col < width; col++) {
          if (col >= 512 || row > 0) {
            continue;
          }
          
          uint32_t inPixel = inRowPtr[col];
          
          uint32_t B = (inPixel & 0xFF);
          uint32_t G = ((inPixel >> 8) & 0xFF);
          uint32_t R = ((inPixel >> 16) & 0xFF);
          uint32_t A = ((inPixel >> 24) & 0xFF);
          
          printf("R G B A (%3d %3d %3d %3d)\n", R, G, B, A);
        }
      }
    }
    
    // Copy from conversion buffer to output pixels
    
    CGFrameBuffer *decompFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    for (int row = 0; row < height; row++) {
      uint8_t *outPtr = (((uint8_t*)decompFB.pixels) + (row * width * sizeof(uint32_t)));
      uint8_t *inPtr = (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
      memcpy(outPtr, inPtr, width * sizeof(uint32_t));
    }
    
    // Free allocated bufers
    
    free(dstBuffer.data);
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_vImage_RGB_from_YUV.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [decompFB formatAsPNG];
      
      NSLog(@"wrote %@", path);
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      if ((1)) {
        uint32_t pixel = ((uint32_t*) decompFB.pixels)[0];
        int B = pixel & 0xFF;
        int G = (pixel >> 8) & 0xFF;
        int R = (pixel >> 16) & 0xFF;
        printf("vImage first decompressed pixel sRGB (R G B) (%d %d %d)\n", R, G, B);
      }
    }
  }
  
  if ((0)) {
    // Process YCbCr output with vImage to decode
    
    vImage_Buffer dstBuffer;
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    
    BOOL worked = [BGRAToBT709Converter convertFromCoreVideoBuffer:cvPixelBuffer
                                                         bufferPtr:&dstBuffer
                                                        colorspace:cs];
    assert(worked);
    
    // Copy BGRA pixels from dstBuffer to outBGRAPixels
    
    const int dstRowBytes = (int) dstBuffer.rowBytes;
    
    if ((1)) {
      printf("destBuffer %d x %d : R G B A\n", width, height);
      
      for (int row = 0; row < height; row++) {
        uint32_t *inRowPtr = (uint32_t*) (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
        
        for (int col = 0; col < width; col++) {
          if (col >= 512 || row > 0) {
            continue;
          }
          
          uint32_t inPixel = inRowPtr[col];
          
          uint32_t B = (inPixel & 0xFF);
          uint32_t G = ((inPixel >> 8) & 0xFF);
          uint32_t R = ((inPixel >> 16) & 0xFF);
          uint32_t A = ((inPixel >> 24) & 0xFF);
          
          printf("R G B A (%3d %3d %3d %3d)\n", R, G, B, A);
        }
      }
    }
    
    // Copy from conversion buffer to output pixels
    
    CGFrameBuffer *decompFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    decompFB.colorspace = cs;
    
    for (int row = 0; row < height; row++) {
      uint8_t *outPtr = (((uint8_t*)decompFB.pixels) + (row * width * sizeof(uint32_t)));
      uint8_t *inPtr = (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
      memcpy(outPtr, inPtr, width * sizeof(uint32_t));
    }
    
    // Free allocated bufers
    
    free(dstBuffer.data);
    
    CGColorSpaceRelease(cs);
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_vImage_RGB_from_YUV_as_linear.png"];
      //NSString *tmpDir = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [decompFB formatAsPNG];
      
      NSLog(@"wrote %@", path);
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      if ((1)) {
        uint32_t pixel = ((uint32_t*) decompFB.pixels)[0];
        int B = pixel & 0xFF;
        int G = (pixel >> 8) & 0xFF;
        int R = (pixel >> 16) & 0xFF;
        printf("vImage first decompressed pixel sRGB (R G B) (%d %d %d)\n", R, G, B);
      }
    }
  }
  
  // Simulate decoding of the YCbCr matrix calculation but without conversion
  // from the non-linear gamma space. Emit the matrix output as linear
  // chopped values to get a rough idea of the graph slope.
  
  if ((0)) {
    // Process YCbCr output with vImage to decode into non-linear rounded output
    // in the linear RGB colorspace.
    
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    
    // Copy from conversion buffer to output pixels
    
    CGFrameBuffer *decompFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    decompFB.colorspace = cs;
    
    uint32_t *pixelPtr = (uint32_t *) decompFB.pixels;
    
    const int dump = FALSE;
    
    // Save the first 512 entries as 256 float values
    
    NSMutableArray *mDecodedGrays = [NSMutableArray array];
    
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        int offset = (row * width) + col;
        uint32_t inY = yPtr[offset];
        
        if (col >= 512 || row > 0) {
          continue;
        }
        
        //        if (dump) {
        //        printf("%3d ", inY);
        //        }
        
        // FIXME: invoke first stage of decompression to reverse matrix
        
        float Rn, Gn, Bn;
        
        BT709_convertYCbCrToNonLinearRGB(inY, 128, 128, &Rn, &Gn, &Bn);
        
        uint32_t G = (uint32_t) round(Gn * 255.0);
        
        assert(G <= 255);
        
        uint32_t pixel = (G << 16) | (G << 8) | G;
        
        if (dump) {
          printf("%3d ", G);
        }
        
        pixelPtr[offset] = pixel;
        
        if ((row == 0) && (col < (256 * 2)) && ((col % 2) == 0)) {
          [mDecodedGrays addObject:@(Gn)];
        }
      }
      
      if (dump) {
        printf("\n");
      }
    }
    
    assert(mDecodedGrays.count == 256);
    
    CGColorSpaceRelease(cs);
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_vImage_gray_nonlinear_as_linear.png"];
      //NSString *dirName = NSTemporaryDirectory();
      NSString *dirName = [[NSFileManager defaultManager] currentDirectoryPath];
      NSString *path = [dirName stringByAppendingPathComponent:filename];
      NSData *pngData = [decompFB formatAsPNG];
      
      NSLog(@"wrote %@", path);
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
      
      if ((1)) {
        uint32_t pixel = ((uint32_t*) decompFB.pixels)[0];
        int B = pixel & 0xFF;
        int G = (pixel >> 8) & 0xFF;
        int R = (pixel >> 16) & 0xFF;
        printf("vImage first decompressed pixel sRGB (R G B) (%d %d %d)\n", R, G, B);
      }
    }
    
    // Map linear values to the output gamma mapped values
    
    if ((0)) {
      NSMutableArray *yPairsArr = [NSMutableArray array];
      
      for (int i = 0; i < mDecodedGrays.count; i++) {
        NSNumber *gNum = mDecodedGrays[i];
        
        float grayN = [gNum floatValue];
        
        int grayInt = (int) round(grayN * 255.0f);
        
        float percentOfGrayscale = ((float)i) / 255.0f;
        
        // Adjust the boosted values using the BT.709 gamma decoding
        // function with a linear ramp. This should generate values
        // that are 1.14 larger than the linear vlaues.
        
        float un709 = BT709_nonLinearNormToLinear(grayN);
        
        // Custom unboost with linear ramp logic, this logic accepts
        // a boosted value in non-linear space and applies a curve
        // that should remove the boost and render a result very
        // near to the original linear line.
        
        float decUnboost = BT709_B22_nonLinearNormToLinear(grayN);
        
        // Second adjustment based on the output of the un-709, this
        // should have interpreted the linear curve segment more
        // effectively.
        
        //float decUnboost709 = AppleGamma196_unboost_linearNorm(dec709);
        
        float up709 = BT709_linearNormToNonLinear(percentOfGrayscale);
        
        //float down709 = BT709_nonLinearNormToLinear(up709);
        
        // Decode the values pushed up to 709 using a simplified
        // 1.961 gamma setting, this decodes but makes use of
        // the linear ramp in the original encoding.
        
        float upSRGB = sRGB_linearNormToNonLinear(percentOfGrayscale);
        
        //printf("%3d: %3d %.4f %.4f %.4f %.4f\n", i, grayInt, percentOfGrayscale, grayN, dec709, decUnboost709);
        
        [yPairsArr addObject:@[@(i), @(grayInt), @(percentOfGrayscale), @(grayN),
                               @(up709), @(un709), @(decUnboost), @(upSRGB)]];
      }
      
      NSArray *labels = @[ @"G", @"R", @"PG", @"OG",
                           @"Up709", @"Un709", @"UnB", @"sRGB" ];
      
      writeTableToCSV(@"EncodeGrayAsLinear.csv", labels, yPairsArr);
      NSLog(@"");
    }
  }
  
  return 0;
}

// Return TRUE if file exists, FALSE otherwise

BOOL fileExists(NSString *filePath) {
  if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// Given an input filename like "F001.png", return the input files
// that exist on the disk given these frame numbers.

int parse_filenames_from_first_file(NSString *firstFilename,
                                    NSMutableArray *mFilenames)
{
  // Given the first frame image filename, build and array of filenames
  // by checking to see if files exist up until we find one that does not.
  // This makes it possible to pass the 25th frame ofa 50 frame animation
  // and generate an animation 25 frames in duration.
  
  const char *firstFilenameCstr = (const char *) [firstFilename UTF8String];
  
  if (fileExists(firstFilename) == FALSE) {
    fprintf(stderr, "error: first filename \"%s\" does not exist\n", firstFilenameCstr);
    exit(1);
  }
  
  NSString *firstFilenameExt = [firstFilename pathExtension];
  
  // Find first numerical character in the [0-9] range starting at the end of the filename string.
  // A frame filename like "Frame0001.png" would be an example input. Note that the last frame
  // number must be the last character before the extension.
  
  NSArray *upToLastPathComponent = [firstFilename pathComponents];
  NSRange upToLastPathComponentRange;
  upToLastPathComponentRange.location = 0;
  upToLastPathComponentRange.length = [upToLastPathComponent count] - 1;
  upToLastPathComponent = [upToLastPathComponent subarrayWithRange:upToLastPathComponentRange];
  NSString *upToLastPathComponentPath = [NSString pathWithComponents:upToLastPathComponent];
  
  NSString *firstFilenameTail = [firstFilename lastPathComponent];
  NSString *firstFilenameTailNoExtension = [firstFilenameTail stringByDeletingPathExtension];
  
  int numericStartIndex = -1;
  BOOL foundNonAlpha = FALSE;
  
  for (int i = (int)[firstFilenameTailNoExtension length] - 1; i > 0; i--) {
    unichar c = [firstFilenameTailNoExtension characterAtIndex:i];
    if ((c >= '0') && (c <= '9') && (foundNonAlpha == FALSE)) {
      numericStartIndex = i;
    } else {
      foundNonAlpha = TRUE;
    }
  }
  if (numericStartIndex == -1 || numericStartIndex == 0) {
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"\n", firstFilenameCstr);
    exit(1);
  }
  
  // Extract the numeric portion of the first frame filename
  
  NSString *namePortion = [firstFilenameTailNoExtension substringToIndex:numericStartIndex];
  NSString *numberPortion = [firstFilenameTailNoExtension substringFromIndex:numericStartIndex];
  
  if ([namePortion length] < 1 || [numberPortion length] == 0) {
    fprintf(stderr, "error: could not find frame number in first filename \"%s\"\n", firstFilenameCstr);
    exit(1);
  }
  
  // Convert number with leading zeros to a simple integer
  
  int formatWidth = (int) [numberPortion length];
  int startingFrameNumber = [numberPortion intValue];
  int endingFrameNumber = -1;
  
#define CRAZY_MAX_FRAMES 9999999
#define CRAZY_MAX_DIGITS 7
  
  // Note that we include the first frame in this loop just so that it gets added to inFramePaths.
  
  for (int i = startingFrameNumber; i < CRAZY_MAX_FRAMES; i++) @autoreleasepool {
    NSMutableString *frameNumberWithLeadingZeros = [NSMutableString string];
    [frameNumberWithLeadingZeros appendFormat:@"%07d", i];
    if ([frameNumberWithLeadingZeros length] > formatWidth) {
      int numToDelete = (int) ([frameNumberWithLeadingZeros length] - formatWidth);
      NSRange delRange;
      delRange.location = 0;
      delRange.length = numToDelete;
      [frameNumberWithLeadingZeros deleteCharactersInRange:delRange];
      assert([frameNumberWithLeadingZeros length] == formatWidth);
    }
    [frameNumberWithLeadingZeros appendString:@"."];
    [frameNumberWithLeadingZeros appendString:firstFilenameExt];
    [frameNumberWithLeadingZeros insertString:namePortion atIndex:0];
    NSString *framePathWithNumber = [upToLastPathComponentPath stringByAppendingPathComponent:frameNumberWithLeadingZeros];
    
    if (fileExists(framePathWithNumber)) {
      // Found frame at indicated path, add it to array of known frame filenames
      
      [mFilenames addObject:framePathWithNumber];
      endingFrameNumber = i;
    } else {
      // Frame filename with indicated frame number not found, done scanning for frame files
      break;
    }
  }
  
  if ([mFilenames count] <= 1) {
    fprintf(stderr, "error: at least 2 input frames are required\n");
    exit(1);
  }
  
  if ((startingFrameNumber == endingFrameNumber) || (endingFrameNumber == CRAZY_MAX_FRAMES-1)) {
    fprintf(stderr, "error: could not find last frame number\n");
    exit(1);
  }

  return 0;
}

// Read from source frame, convert to YCbCr and populate CoreVideo buffer

static inline
CVPixelBufferRef loadFrameIntoCVPixelBuffer(
          NSString *inputImageStr,
                                            int frameNum,
                                            BOOL isLinearGamma,
                                            BOOL isSRGBGamma,
                                            NSMutableData *Y,
                                            NSMutableData *Cb,
                                            NSMutableData *Cr)
{
  if (1 || frameNum == 1) {
    printf("loading %s\n", [inputImageStr UTF8String]);
  }
  
  CGImageRef inImage = makeImageFromFile(inputImageStr);
  if (inImage == NULL) {
    return NULL;
  }
  
  int width = (int) CGImageGetWidth(inImage);
  int height = (int) CGImageGetHeight(inImage);
  
  assert(width > 0);
  assert(height > 0);
  
  BOOL widthDiv2 = ((width % 2) == 0);
  BOOL heightDiv2 = ((height % 2) == 0);
  
  if (widthDiv2 && heightDiv2) {
  } else {
    printf("width and height must both be even but got dimensions %d x %d\n", width, height);
    return NULL;
  }
  
  CGColorSpaceRef inputColorspace = CGImageGetColorSpace(inImage);
  
  BOOL inputIsRGBColorspace = FALSE;
  BOOL inputIsSRGBColorspace = FALSE;
  BOOL inputIsSRGBLinearColorspace = FALSE;
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
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    
    NSString *colorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(colorspace);
    NSString *inputColorspaceDescription = (__bridge_transfer NSString*) CGColorSpaceCopyName(inputColorspace);
    
    if ([colorspaceDescription isEqualToString:inputColorspaceDescription]) {
      inputIsSRGBLinearColorspace = TRUE;
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
  
  if (frameNum == 1) {
    if (inputIsRGBColorspace) {
      printf("untagged RGB colorspace is not supported as input\n");
      exit(4);
    } else if (inputIsSRGBColorspace) {
      printf("input is sRGB colorspace\n");
    } else if (inputIsSRGBLinearColorspace) {
      printf("input is sRGBLinear colorspace\n");
    } else if (inputIsGrayColorspace) {
      printf("input is grayscale colorspace\n");
    } else if (inputIsBT709Colorspace) {
      printf("input is already in BT.709 colorspace\n");
    } else {
      printf("will convert from input colorspace to Apple gamma encoded space:\n");
      NSString *desc = [(__bridge id)inputColorspace description];
      printf("%s\n", [desc UTF8String]);
    }
  }
  
  if (isLinearGamma) {
    // Treat input image data as linear, grayscale input image data
    // must be tagged as sRGB with gamma = 1.0
    
    // ffmpeg -i in.y4m -c:v libx264 -color_primaries bt709 -colorspace bt709 -color_trc linear out.m4v
    
    CGFrameBuffer *inputFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    inputFB.colorspace = CGImageGetColorSpace(inImage);
    
    [inputFB renderCGImage:inImage];
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    
    CGFrameBuffer *linearFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    linearFB.colorspace = colorspace;
    
    CGColorSpaceRelease(colorspace);
    
    // Copy pixel data
    
    memcpy(linearFB.pixels, inputFB.pixels, inputFB.numBytes);
    
    CGImageRelease(inImage);
    
    inImage = [linearFB createCGImageRef];
  } else if (isSRGBGamma) {
    // ffmpeg -i in.y4m -c:v libx264 -color_primaries bt709 -colorspace bt709 -color_trc iec61966_2_1 out.m4v
  }
  
  CVPixelBufferRef cvPixelBuffer = [BGRAToBT709Converter createYCbCrFromCGImage:inImage
                                                                       isLinear:isLinearGamma
                                                                    asSRGBGamma:isSRGBGamma];
  
  int dumpResult = dump_image_meta(inImage, cvPixelBuffer, Y, Cb, Cr);
  
  CGImageRelease(inImage);
  
  if (dumpResult != 0) {
    return NULL;
  }
  
  return cvPixelBuffer;
}

int process(NSDictionary *inDict) {
  // Read PNG
  
  NSString *inputImageStr = inDict[@"input"];
  NSString *outY4mStr = inDict[@"output"];
  NSString *gamma = inDict[@"-gamma"];

  NSNumber *inputIsFramesPatternNum = inDict[@"inputIsFramesPattern"];
  BOOL inputIsFramesPattern = [inputIsFramesPatternNum boolValue];
  NSMutableArray *inputFramesFilenames = [NSMutableArray array];
  
  if (inputIsFramesPattern) {
    int result = parse_filenames_from_first_file(inputImageStr, inputFramesFilenames);
    if (result != 0) {
      return result;
    }
  } else {
    [inputFramesFilenames addObject:inputImageStr];
  }
  
  NSNumber *fpsNum = inDict[@"-fps"];
  Y4MHeaderFPS fps = [fpsNum intValue];
  int frameNum = 1;

  BOOL isLinearGamma = FALSE;
  BOOL isSRGBGamma = FALSE;
  BOOL hasWrittenHeader = FALSE;
  
  if ([gamma isEqualToString:@"linear"]) {
    isLinearGamma = TRUE;
  } else if ([gamma isEqualToString:@"srgb"]) {
    isSRGBGamma = TRUE;
  }
  
  NSMutableData *Y = [NSMutableData data];
  NSMutableData *Cb = [NSMutableData data];
  NSMutableData *Cr = [NSMutableData data];
  
  // Process YCbCr by writing to output YUV frame(s) to y4m file
  
  const char *outFilename = [outY4mStr UTF8String];
  FILE *outFile = y4m_open_file(outFilename);
  
  if (outFile == NULL) {
    return 1;
  }
  
  for (int i = 0; i < (int)[inputFramesFilenames count]; i++) @autoreleasepool {
    inputImageStr = inputFramesFilenames[i];

    CVPixelBufferRef cvPixelBuffer = loadFrameIntoCVPixelBuffer(inputImageStr, frameNum++, isLinearGamma, isSRGBGamma, Y, Cb, Cr);
    
    if (cvPixelBuffer == NULL) {
      return 1;
    }
  
    if (hasWrittenHeader == FALSE) {
      Y4MHeaderStruct header;
      
      int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
      int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
      
      header.width = width;
      header.height = height;
      
      header.fps = fps;
      
      int header_result = y4m_write_header(outFile, &header);
      if (header_result != 0) {
        return header_result;
      }
      
      hasWrittenHeader = TRUE;
    }
    
    // Write frame data
    
    Y4MFrameStruct fs;
    
    fs.yPtr = (uint8_t*) Y.bytes;
    fs.yLen = (int) Y.length;
    
    fs.uPtr = (uint8_t*) Cb.bytes;
    fs.uLen = (int) Cb.length;
    
    fs.vPtr = (uint8_t*) Cr.bytes;
    fs.vLen = (int) Cr.length;
    
    int write_frame_result = y4m_write_frame(outFile, &fs);
    if (write_frame_result != 0) {
      return write_frame_result;
    }
    
    CVPixelBufferRelease(cvPixelBuffer);
  }
  
  fclose(outFile);
  
  return 0;
}

int main(int argc, const char * argv[]) {
  int retcode = 0;
  
  @autoreleasepool {
    char *inPNG = NULL;
    BOOL inPNGIsFramesPattern = FALSE;
    char *outY4m = NULL;
    
    if (argc < 3) {
      usage();
      exit(1);
    }
    
    // Process command line argument(s)
    //
    // -option ARG
    //
    // Followed by OUTPUT.y4m
    
    NSMutableDictionary *args = [NSMutableDictionary dictionary];
    
    // Defaults
    
    args[@"-gamma"] = @"apple";
    
    args[@"-fps"] = @(Y4MHeaderFPS_30);
    
    for (int i = 1; i < argc; ) {
      char *arg = (char *) argv[i];
      
      //printf("process option \"%s\"\n", arg);
      
      if (arg[0] == '-') {
        if (strcmp(arg, "-gamma") == 0) {
          i++;
          arg = (char *) argv[i];
          i++;
          
          if (strcmp(arg, "apple") == 0) {
            args[@"-gamma"] = @"apple";
          } else if (strcmp(arg, "srgb") == 0) {
            args[@"-gamma"] = @"srgb";
          } else if (strcmp(arg, "linear") == 0) {
            args[@"-gamma"] = @"linear";
          } else {
            printf("option -gamma unknown value \"%s\"", arg);
            exit(3);
          }
        } else if (strcmp(arg, "-fps") == 0) {
          i++;
          arg = (char *) argv[i];
          i++;
          
          if (strcmp(arg, "1") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_1);
          } else if (strcmp(arg, "15") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_15);
          } else if (strcmp(arg, "24") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_24);
          } else if (strcmp(arg, "2997") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_29_97);
          } else if (strcmp(arg, "30") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_30);
          } else if (strcmp(arg, "60") == 0) {
            args[@"-fps"] = @(Y4MHeaderFPS_60);
          } else {
            printf("option -fps unknown value \"%s\"", arg);
            exit(3);
          }
        } else if (strcmp(arg, "-frame") == 0) {
          // Indicates a single frame of image data
          i++;
          arg = (char *) argv[i];
          i++;
          
          if (inPNG != NULL) {
            printf("-frame filename \"%s\" must appear just once\n", arg);
            exit(3);
          }
          
          inPNG = arg;
          
          // Default to 1 frame displayed for 1 second
          args[@"-fps"] = @(Y4MHeaderFPS_1);
        } else if (strcmp(arg, "-frames") == 0) {
          // -frames F0001.png indicates the start
          // of a frame input pattern that can indicate
          // multiple frames to be encoded as video.
          
          i++;
          arg = (char *) argv[i];
          i++;
          
          if (inPNG != NULL) {
            printf("-frames filename \"%s\" must appear just once\n", arg);
            exit(3);
          }
          
          inPNG = arg;
          inPNGIsFramesPattern = TRUE;
        } else {
          // Unmatched option
          printf("unknown option \"%s\"\n", arg);
          exit(3);
        }
      } else {
        // Output filename is final argument
        if (outY4m != NULL) {
          printf("output filename \"%s\" must appear just once\n", arg);
          exit(3);
        }
        outY4m = arg;
        i++;
      }
    }

    if (inPNG == NULL) {
      printf("int filename not found, either -frame or -frames must be used to indicate input image(s)\n");
      exit(3);
    }
    
    if (outY4m == NULL) {
      printf("output filename not found, must be last argument\n");
      exit(3);
    }
    
    args[@"input"] = [NSString stringWithFormat:@"%s", inPNG];
    args[@"output"] = [NSString stringWithFormat:@"%s", outY4m];
    
    // Input must be .png or .jpg
    
    BOOL isPNG = [args[@"input"] hasSuffix:@".png"];
    BOOL isJPG = [args[@"input"] hasSuffix:@".jpg"] || [args[@"input"] hasSuffix:@".jpeg"];
    
    if (isPNG || isJPG) {
      // input is good
    } else {
      printf("input filename \"%s\" must be .png or .jpg or .jpeg\n", inPNG);
      exit(3);
    }
    
    args[@"inputIsFramesPattern"] = @(inPNGIsFramesPattern);
    
    BOOL isY4m = [args[@"output"] hasSuffix:@".y4m"];
    
    if (isY4m) {
      // output is good
    } else {
      printf("output filename \"%s\" must have extension .y4m\n", outY4m);
      exit(3);
    }
    
    retcode = process(args);
  }
  
  exit(retcode);
  return retcode;
}
