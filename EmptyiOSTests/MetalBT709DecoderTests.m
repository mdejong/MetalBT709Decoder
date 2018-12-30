//
//  MetalBT709DecoderTests.m
//
//  Created by Mo DeJong on 12/13/18.
//

#import <XCTest/XCTest.h>

#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

#import "MetalBT709Decoder.h"

#import "BGRAToBT709Converter.h"

#import "CGFrameBuffer.h"

#import "MetalRenderContext.h"

@interface MetalBT709DecoderTests : XCTestCase

@end

static inline
BOOL
floatIsEqualEpsilion(float f1, float f2, float epsilion)
{
  float delta = f1 - f2;
  return (delta < epsilion);
}

static inline
BOOL
floatIsEqual(float f1, float f2)
{
  float epsilion = 0.001;
  return floatIsEqualEpsilion(f1, f2, epsilion);
}

static inline
uint32_t rgbToPixel(uint32_t R, uint32_t G, uint32_t B)
{
  uint32_t outPixel = (R << 16) | (G << 8) | B;
  return outPixel;
}

static inline
uint32_t rgbaToPixel(uint32_t R, uint32_t G, uint32_t B, uint32_t A)
{
  uint32_t outPixel = (A << 24) | (R << 16) | (G << 8) | B;
  return outPixel;
}

// Unpack a pixel and assign to variables

static inline
void pixelToRGBA(uint32_t inPixel, uint32_t * R, uint32_t * G, uint32_t* B, uint32_t * A)
{
  uint32_t c0 = (inPixel & 0xFF);
  uint32_t c1 = ((inPixel >> 8) & 0xFF);
  uint32_t c2 = ((inPixel >> 16) & 0xFF);
  uint32_t c3 = ((inPixel >> 16) & 0xFF);
 
  *B = c0;
  *G = c1;
  *R = c2;
  *A = c3;
}

static inline
uint32_t grayToPixel(uint32_t gray)
{
  return rgbaToPixel(gray, gray, gray, 0xFF);
}

@implementation MetalBT709DecoderTests

- (void)setUp {
  // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (BOOL) isExactlyTheSame:(int)R
                        G:(int)G
                        B:(int)B
                     decR:(int)decR
                     decG:(int)decG
                     decB:(int)decB
{
  return (B == decB) && (G == decG) && (R == decR);
}

// Is v2 close enough to v1 (+- delta), return TRUE if so

- (BOOL) isCloseEnough:(int)v1
                    v2:(int)v2
                 delta:(int)delta
{
  assert(delta > 0);
  
  int max = (v1 + delta);
  int min = (v1 - delta);
  
  if (v2 >= min && v2 <= max) {
    return TRUE;
  } else {
    return FALSE;
  }
}

- (BOOL) isOffBy:(int)R
               G:(int)G
               B:(int)B
            decR:(int)decR
            decG:(int)decG
            decB:(int)decB
           delta:(int)delta
{
  BOOL BClose = [self isCloseEnough:B v2:decB delta:delta];
  BOOL GClose = [self isCloseEnough:G v2:decG delta:delta];
  BOOL RClose = [self isCloseEnough:R v2:decR delta:delta];
  
  if (BClose == FALSE || GClose == FALSE || RClose == FALSE) {
    // One of these values is larger than +-1 delta
    return FALSE;
  } else {
    // All 3 values are close enough
    return TRUE;
  }
}

// Convert with C or vImage and then decode with Metal shader

- (void)testMetalBT709Decoder_Gray50Percent {
  
  // Gray at 50% intensity
  //
  // sRGB (128 128 128) -> Linear RGB (55 55 55) -> REC.709 (115 128 128)
  
  uint32_t Gin;
  
  uint32_t Y, Cb, Cr, dummy;
  
  Gin = 128;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = grayToPixel(Gin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 115;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA

  MetalRenderContext *metalRenderContext = [[MetalRenderContext alloc] init];
  metalRenderContext.device = MTLCreateSystemDefaultDevice();
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  
  metalDecoder.metalRenderContext = metalRenderContext;
  
  metalDecoder.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
  
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];

  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  id<MTLCommandBuffer> commandBuffer = [metalRenderContext.commandQueue commandBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                       commandBuffer:commandBuffer
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);

  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  {
    int v = outR;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

/*

// Convert with C or vImage and then decode with Metal shader

- (void)testMetalBT709Decoder_Gray10Percent {
  
  // Gray at 10% intensity
  //
  // sRGB (85 85 85) -> Linear RGB (23 23 23) -> REC.709 (76 128 128)
  
  uint32_t Gin;
  
  uint32_t Y, Cb, Cr, dummy;
  
  Gin = 85;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = grayToPixel(Gin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 76;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  {
    int v = outR;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}


- (void)testMetalBT709Decoder_Gray2Percent {
  
  // Gray at 2% intensity is less than the sRGB knee and the BT.709 knee
  //
  // sRGB (5 5 5) -> Linear RGB (0.38  0.38  0.38) -> REC.709 (17 128 128)

  uint32_t Rin, Gin, Bin;
  
  uint32_t Y, Cb, Cr, dummy;
  
  Rin = 5;
  Gin = Rin;
  Bin = Rin;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = grayToPixel(Gin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    // C code : round(17.4956) -> 17
    int expectedVal = 17;
    // vImage :
    //int expectedVal = 18;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  // C decoder output (3 3 3)
  // Metal output (3 3 3)

  // Both decoded with Metal
  // C (5 5 5)           -> (3 3 3)
  // vImage (18 128 128) -> (6 6 6)
  
  {
    int v = outR;
    int expectedVal = Rin - 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin - 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin - 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Gray2Percent_Part2 {
  
  // Gray at 2% intensity is less than the sRGB knee and the BT.709 knee
  //
  // sRGB (6 6 6) -> Linear RGB (0.0018 0.0018 0.0018) -> REC.709 (18 128 128)
  
  uint32_t Rin, Gin, Bin;
  
  uint32_t Y, Cb, Cr, dummy;
  
  Rin = 6;
  Gin = Rin;
  Bin = Rin;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = grayToPixel(Gin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    // C code : round(17.79) -> 18
    int expectedVal = 18;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  // Both C code and vImage emit (18 128 128)
  //
  // Metal (6 6 6)
  
  // The C code decodes (7 7 7) due to rounding
  
  {
    int v = outR;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}


- (void)testMetalBT709Decoder_R75G50B25 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;

  // sRGB (75 50 25) -> Linear RGB (18 8 2) -> REC.709 (49 115 140)
  
  Rin = 75;
  Gin = 50;
  Bin = 25;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = rgbToPixel(Rin, Gin, Bin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 49;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 115;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 140;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  {
    int v = outR;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }

}


- (void)testMetalBT709Decoder_Red255 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  
  // sRGB (255 0 0) -> Linear RGB (255 0 0) -> REC.709 (63 102 240)
  
  Rin = 255;
  Gin = 0;
  Bin = 0;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = rgbToPixel(Rin, Gin, Bin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 63;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 102;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 240;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  // sRGB (255 0 0) -> Metal (255 2 0)
  
  {
    int v = outR;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin + 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Green255 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  
  // sRGB (0 255 0) -> Linear RGB (0 255 0) -> REC.709 (173 42 26)
  
  Rin = 0;
  Gin = 255;
  Bin = 0;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = rgbToPixel(Rin, Gin, Bin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 173;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 42;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 26;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  // sRGB (0 255 0) -> Metal (0 255 3)
  
  {
    int v = outR;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin + 3;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Blue255 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  
  // sRGB (0 0 255) -> Linear RGB (0 0 255) -> REC.709 (32 240 118)
  
  Rin = 0;
  Gin = 0;
  Bin = 255;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value to a grayscale step
  
  inBGRA[0] = rgbToPixel(Rin, Gin, Bin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 32;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 240;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 118;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  // Use Metal impl to convert BT709 data to BGRA
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  MetalRenderContext *metalRenderContext = metalDecoder.metalRenderContext;
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t outR, outG, outB;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  pixelToRGBA(bgraOutPixel, &outR, &outG, &outB, &dummy);
  
  // sRGB (0 0 255) -> Metal (2 0 255)
  
  {
    int v = outR;
    int expectedVal = Rin + 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outG;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = outB;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

*/
 
@end
