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

#import "CGFramebuffer.h"
#import "BGRAToBT709Converter.h"

typedef struct {
  int fps;
} ConfigurationStruct;

void usage() {
  printf("srgb_to_bt709 ?OPTIONS? IN.png OUT.y4m\n");
  fflush(stdout);
}

// Laod PNG from the filesystem

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
  
  // Process YCBCr by writing to output y4m file
  
  FILE *outFile = fopen([outY4mStr UTF8String], "w");
  
  assert(outFile);
  
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
  
  // N FRAMES
  
  {
    char *segment = "FRAME\n";
    int segmentLen = (int) strlen(segment);
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Y bytes

  {
    uint8_t *segment = (uint8_t *) Y.bytes;
    int segmentLen = (int) Y.length;
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Cb

  {
    uint8_t *segment = (uint8_t *) Cb.bytes;
    int segmentLen = (int) Cb.length;
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  // Cr

  {
    uint8_t *segment = (uint8_t *) Cr.bytes;
    int segmentLen = (int) Cr.length;
    fwrite(segment, segmentLen, 1, outFile);
  }
  
  fclose(outFile);
  
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
