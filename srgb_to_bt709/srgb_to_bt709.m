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

typedef struct {
  int fps;
} ConfigurationStruct;

void usage() {
  printf("srgb_to_bt709 ?OPTIONS? IN.png OUT.y4m\n");
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

// Emit a single frame to the output Y4M file.

typedef struct {
  uint8_t *yPtr;
  int yLen;

  uint8_t *uPtr;
  int uLen;

  uint8_t *vPtr;
  int vLen;
} FrameStruct;

static inline
int write_frame(FILE *outFile, FrameStruct *fsPtr) {
  // FRAME marker
  
  {
    char *segment = "FRAME\n";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 1;
    }
  }
  
  // Y
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->yPtr;
    int segmentLen = (int) fsPtr->yLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // U
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->uPtr;
    int segmentLen = (int) fsPtr->uLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 3;
    }
  }

  // V
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->vPtr;
    int segmentLen = (int) fsPtr->vLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 4;
    }
  }

  return 0;
}

int process(NSString *inPNGStr, NSString *outY4mStr, ConfigurationStruct *configSPtr) {
  // Read PNG
  
  printf("loading %s\n", [inPNGStr UTF8String]);
  
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
  
  // FIXME: should the format of the input image be constrained? If it is sRGB then
  // the boost is used, but what about linear input and BT.709 input?
  
  CVPixelBufferRef cvPixelBuffer = [BGRAToBT709Converter createYCbCrFromCGImage:inImage];
  
  // Copy (Y Cb Cr) as (c0 c1 c2) in (c3 c2 c1 c0)
  
  NSMutableData *Y = [NSMutableData data];
  NSMutableData *Cb = [NSMutableData data];
  NSMutableData *Cr = [NSMutableData data];
  
  const BOOL dump = TRUE;
  
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
  
  if ((1)) {
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
  
  // Process YCbCr by writing to output y4m file
  
  const char *outFilename = [outY4mStr UTF8String];
  FILE *outFile = fopen(outFilename, "w");
  
  if (outFile == NULL) {
    fprintf(stderr, "could not open output Y4M file \"%s\"\n", outFilename);
    return 1;
  }
  
  {
    char *segment = "YUV4MPEG2 ";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  {
    NSString *formatted = [NSString stringWithFormat:@"W%d ", width];
    char *segment = (char*) [formatted UTF8String];
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }

  {
    NSString *formatted = [NSString stringWithFormat:@"H%d ", height];
    char *segment = (char*) [formatted UTF8String];
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }

  // Framerate :
  // 'F30:1' = 30 FPS
  // 'F30000:1001' = 29.97 FPS
  // '1:1' = 1 FPS
  
  {
    //char *segment = "F30:1 ";
    char *segment = "F1:1 ";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // interlacing progressive
  
  {
    char *segment = "Ip ";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Pixel aspect ratio

  {
    char *segment = "A1:1 ";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Colour space
  
  {
    char *segment = "C420jpeg\n";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Comment

  {
    char *segment = "XYSCSS=420JPEG\n";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  FrameStruct fs;
  
  fs.yPtr = (uint8_t*) Y.bytes;
  fs.yLen = (int) Y.length;
  
  fs.uPtr = (uint8_t*) Cb.bytes;
  fs.uLen = (int) Cb.length;
  
  fs.vPtr = (uint8_t*) Cr.bytes;
  fs.vLen = (int) Cr.length;
  
  int write_frame_result = write_frame(outFile, &fs);
  if (write_frame_result != 0) {
    return write_frame_result;
  }
  
  fclose(outFile);
  
  CGImageRelease(inImage);
  
  return 0;
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
