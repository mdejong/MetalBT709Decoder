//
//  BGRAToBT709Converter.m
//
//  Created by Mo DeJong on 11/25/18.
//

#import "BGRAToBT709Converter.h"

#import "CGFrameBuffer.h"

#import "BT709.h"

#import "H264Encoder.h"

@import Accelerate;
@import CoreImage;

static inline uint32_t byte_to_grayscale24(uint32_t byteVal)
{
  return ((0xFF << 24) | (byteVal << 16) | (byteVal << 8) | byteVal);
}

@interface BGRAToBT709Converter ()

@end

@implementation BGRAToBT709Converter

// BGRA -> BT709

+ (BOOL) convert:(uint32_t*)inBGRAPixels
  outBT709Pixels:(uint32_t*)outBT709Pixels
           width:(int)width
          height:(int)height
            type:(BGRAToBT709ConverterTypeEnum)type
{
  // width and height must be even for subsampling to work
  
  if ((width % 2) != 0) {
    return FALSE;
  }
  if ((height % 2) != 0) {
    return FALSE;
  }
  
  if (type == BGRAToBT709ConverterSoftware) @autoreleasepool {
    return [self.class convertSoftware:inBGRAPixels outBT709Pixels:outBT709Pixels width:width height:height];
  } else if (type == BGRAToBT709ConverterVImage) @autoreleasepool {
    return [self.class convertVimage:inBGRAPixels outBT709Pixels:outBT709Pixels width:width height:height];
  } else {
    return FALSE;
  }
  
  return TRUE;
}

// BT709 -> BGRA

+ (BOOL) unconvert:(uint32_t*)inBT709Pixels
     outBGRAPixels:(uint32_t*)outBGRAPixels
             width:(int)width
            height:(int)height
              type:(BGRAToBT709ConverterTypeEnum)type
{
  // width and height must be even for subsampling to work
  
  if ((width % 2) != 0) {
    return FALSE;
  }
  if ((height % 2) != 0) {
    return FALSE;
  }
    
  if (type == BGRAToBT709ConverterSoftware) @autoreleasepool {
    [self.class unconvertSoftware:inBT709Pixels outBGRAPixels:outBGRAPixels width:width height:height];
  } else if (type == BGRAToBT709ConverterVImage) @autoreleasepool {
    return [self.class unconvertVimage:inBT709Pixels outBGRAPixels:outBGRAPixels width:width height:height];
  } else {
    return FALSE;
  }
  
  return TRUE;
}

// BT709 module impl

+ (BOOL) convertSoftware:(uint32_t*)inBGRAPixels
  outBT709Pixels:(uint32_t*)outBT709Pixels
           width:(int)width
          height:(int)height
{
  
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      int offset = (row * width) + col;
      uint32_t inPixel = inBGRAPixels[offset];
      
      uint32_t B = (inPixel & 0xFF);
      uint32_t G = ((inPixel >> 8) & 0xFF);
      uint32_t R = ((inPixel >> 16) & 0xFF);
      
      int Y, Cb, Cr;
      
      if (1) {
        // sRGB -> Apple 1.96 gamma curve -> YCbCr
        
        int result = Apple196_from_sRGB_convertRGBToYCbCr(
                                                               R,
                                                               G,
                                                               B,
                                                               &Y,
                                                               &Cb,
                                                               &Cr);
        
        assert(result == 0);
      } else {
        // convertsion from sRGB -> BT.709 gamma curve -> YCbCr
        
        int result = BT709_from_sRGB_convertRGBToYCbCr(
                                                               R,
                                                               G,
                                                               B,
                                                               &Y,
                                                               &Cb,
                                                               &Cr,
                                                               1);
        
        assert(result == 0);
      }
      
      uint32_t Yu = Y;
      uint32_t Cbu = Cb;
      uint32_t Cru = Cr;
      
      uint32_t outPixel = (Cru << 16) | (Cbu << 8) | Yu;
      
      outBT709Pixels[offset] = outPixel;
    }
  }
  
  return TRUE;
}

+ (BOOL) unconvertSoftware:(uint32_t*)inBT709Pixels
             outBGRAPixels:(uint32_t*)outBGRAPixels
                     width:(int)width
                    height:(int)height
{
  
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      int offset = (row * width) + col;
      uint32_t inPixel = inBT709Pixels[offset];
      
      uint32_t Y = (inPixel & 0xFF);
      uint32_t Cb = ((inPixel >> 8) & 0xFF);
      uint32_t Cr = ((inPixel >> 16) & 0xFF);
      
      int Ri, Gi, Bi;
      
      int result;
      
      if ((1)) {
        result = Apple196_to_sRGB_convertYCbCrToRGB(
                                                         Y,
                                                         Cb,
                                                         Cr,
                                                         &Ri,
                                                         &Gi,
                                                         &Bi,
                                                         1);
      } else {
        result = BT709_to_sRGB_convertYCbCrToRGB(
                                                         Y,
                                                         Cb,
                                                         Cr,
                                                         &Ri,
                                                         &Gi,
                                                         &Bi,
                                                         1);
      }
      
      assert(result == 0);
      
      uint32_t Ru = Ri;
      uint32_t Gu = Gi;
      uint32_t Bu = Bi;
      
      uint32_t outPixel = (Ru << 16) | (Gu << 8) | Bu;
      
      outBGRAPixels[offset] = outPixel;
    }
  }
  
  return TRUE;
}

// vImage based implementation, this implementation makes
// use of CoreGraphics to implement reading of sRGB pixels
// and writing of BT.709 formatted CoreVideo pixel buffers.

+ (BOOL) convertVimage:(uint32_t*)inBGRAPixels
          outBT709Pixels:(uint32_t*)outBT709Pixels
                   width:(int)width
                  height:(int)height
{
  CGImageRef inputImageRef;
  
  CGFrameBuffer *inputFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  // Explicitly indicate that incoming pixels are in sRGB colorspace
  
  CGColorSpaceRef sRGBcs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  inputFB.colorspace = sRGBcs;
  CGColorSpaceRelease(sRGBcs);
  
  memcpy(inputFB.pixels, inBGRAPixels, width*height*sizeof(uint32_t));
  
  inputImageRef = [inputFB createCGImageRef];
  
  inputFB = nil;
  
  // Copy data into a CoreVideo buffer which will be wrapped into a CGImageRef
  
  CVPixelBufferRef cvPixelBuffer = [self createYCbCrFromCGImage:inputImageRef];
  
  CGImageRelease(inputImageRef);
  
  // Copy (Y Cb Cr) as (c0 c1 c2) in (c3 c2 c1 c0)
  
  NSMutableData *Y = [NSMutableData data];
  NSMutableData *Cb = [NSMutableData data];
  NSMutableData *Cr = [NSMutableData data];
  
  const BOOL dump = FALSE;

  [self copyYCBCr:cvPixelBuffer Y:Y Cb:Cb Cr:Cr dump:dump];

  // Dump (Y Cb Cr) of first pixel
  
  uint8_t *yPtr = (uint8_t *) Y.bytes;
  uint8_t *cbPtr = (uint8_t *) Cb.bytes;
  uint8_t *crPtr = (uint8_t *) Cr.bytes;
  
  if ((1)) {
    int Y = yPtr[0];
    int Cb = cbPtr[0];
    int Cr = crPtr[0];
    printf("first pixel (Y Cb Cr) (%3d %3d %3d)\n", Y, Cb, Cr);
  }
  
  // Copy (Y Cb Cr) to output BGRA buffer and undo subsampling
  
  if (1) {
    const int yRowBytes = (int) width;
    const int cbRowBytes = (int) width / 2;
    const int crRowBytes = (int) width / 2;
    
    const int debug = 0;
    
    if (debug) {
    printf("destYBuffer %d x %d : YCbCr\n", width, height);
    }
    
    for (int row = 0; row < height; row++) {
      uint8_t *rowYPtr = yPtr + (row * yRowBytes);
      uint8_t *rowCbPtr = cbPtr + (row/2 * cbRowBytes);
      uint8_t *rowCrPtr = crPtr + (row/2 * crRowBytes);
      
      uint32_t *outRowPtr = outBT709Pixels + (row * width);
      
      for (int col = 0; col < width; col++) {
        uint32_t Y = rowYPtr[col];
        uint32_t Cb = rowCbPtr[col / 2];
        uint32_t Cr = rowCrPtr[col / 2];
        
        if (debug) {
          printf("Y Cb Cr (%3d %3d %3d)\n", Y, Cb, Cr);
        }
        
        uint32_t outPixel = (Cr << 16) | (Cb << 8) | Y;
        outRowPtr[col] = outPixel;
      }
    }
  }
  
  CVPixelBufferRelease(cvPixelBuffer);
  
  return TRUE;
}

+ (BOOL) unconvertVimage:(uint32_t*)inBT709Pixels
             outBGRAPixels:(uint32_t*)outBGRAPixels
                     width:(int)width
                    height:(int)height
{
  const int debug = 1;
  
  // Copy (Y Cb Cr) from c0 c1 c2 and then subsample into CoreVideo buffer
  
  CGSize size = CGSizeMake(width, height);
  
  // FIXME: pixel buffer pool here?
  
  CVPixelBufferRef cvPixelBuffer = [self createCoreVideoYCbCrBuffer:size];
  
  BOOL worked = [self setBT709Attributes:cvPixelBuffer];
  NSAssert(worked, @"worked");
  
  // Explicitly set BT.709 as the colorspace of the pixels
  
  worked = [self setBT709Colorspace:cvPixelBuffer];
  NSAssert(worked, @"worked");

  // Write input YCBCr pixels as subsampled planes in the CoreVideo buffer
  
  [self copyBT709ToCoreVideo:inBT709Pixels cvPixelBuffer:cvPixelBuffer];

  // Convert from YCbCr and write as sRGB pixels
  
  vImage_Buffer dstBuffer;
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  
  worked = [self convertFromCoreVideoBuffer:cvPixelBuffer bufferPtr:&dstBuffer colorspace:colorspace];
  NSAssert(worked, @"worked");
  
  CGColorSpaceRelease(colorspace);
  
  CVPixelBufferRelease(cvPixelBuffer);

  // Copy BGRA pixels from dstBuffer to outBGRAPixels
  
  const int dstRowBytes = (int) dstBuffer.rowBytes;
  
  if (debug) {
    printf("destBuffer %d x %d : R G B A\n", width, height);
    
    for (int row = 0; row < height; row++) {
      uint32_t *inRowPtr = (uint32_t*) (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
      
      for (int col = 0; col < width; col++) {
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
  
  for (int row = 0; row < height; row++) {
    uint8_t *outPtr = (((uint8_t*)outBGRAPixels) + (row * width * sizeof(uint32_t)));
    uint8_t *inPtr = (((uint8_t*)dstBuffer.data) + (row * dstRowBytes));
    memcpy(outPtr, inPtr, width * sizeof(uint32_t));
  }

  // Free allocated bufers
  
  free(dstBuffer.data);
  
  return TRUE;
}

// Attach ICC profile data to a pixel buffer, so that pixels rendered
// in the BT.709 colorspace are known to color matching.

+ (BOOL) setBT709Colorspace:(CVPixelBufferRef)cvPixelBuffer
{
  // FIXME: UHDTV : HEVC uses kCGColorSpaceITUR_2020
  
  //CGColorSpaceRef yuvColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
  
  // FIXME: This call is not efficient, need to cache the HDTV colorspace
  // ref across calls to this module for better performance.
  
  CGColorSpaceRef yuvColorSpace = [H264Encoder createHDTVColorSpaceRef];
  
  // Attach BT.709 info to pixel buffer
  
  //CFDataRef colorProfileData = CGColorSpaceCopyICCProfile(yuvColorSpace); // deprecated
  CFDataRef colorProfileData = CGColorSpaceCopyICCData(yuvColorSpace);
  
  NSDictionary *pbAttachments = @{
                                  (__bridge NSString*)kCVImageBufferICCProfileKey: (__bridge NSData *)colorProfileData,
                                  };
  
  CVBufferRef pixelBuffer = cvPixelBuffer;
  
  CVBufferSetAttachments(pixelBuffer, (__bridge CFDictionaryRef)pbAttachments, kCVAttachmentMode_ShouldPropagate);
  
  // Drop ref to NSDictionary to enable explicit checking of ref count of colorProfileData, after the
  // release below the colorProfileData must be 1.
  pbAttachments = nil;
  CFRelease(colorProfileData);
   
  CGColorSpaceRelease(yuvColorSpace);
  
  return TRUE;
}

// Set the proper attributes on a CVPixelBufferRef so that vImage
// is able to render directly into BT.709 formatted YCbCr planes.

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

// Return pixel buffer attributes

+ (NSDictionary*) getPixelBufferAttributes
{
  NSDictionary *pixelAttributes = @{
                                    (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{},
#if TARGET_OS_IOS
                                    (__bridge NSString*)kCVPixelFormatOpenGLESCompatibility : @(YES),
#endif // TARGET_OS_IOS
                                    (__bridge NSString*)kCVPixelBufferCGImageCompatibilityKey : @(YES),
                                    (__bridge NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @(YES),
                                    (__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @(YES),
                                    };
  return pixelAttributes;
}

// Allocate a CoreVideo buffer for use with BT.709 format YCBCr 2 plane data

+ (CVPixelBufferRef) createCoreVideoYCbCrBuffer:(CGSize)size
{
  int width = (int) size.width;
  int height = (int) size.height;
  
  NSDictionary *pixelAttributes = [self getPixelBufferAttributes];
  
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
  
  return cvPixelBuffer;
}

// Allocate a CoreVideo buffer that contains a single 8 bit component for each pixel

+ (CVPixelBufferRef) createCoreVideoYBuffer:(CGSize)size
{
  int width = (int) size.width;
  int height = (int) size.height;
  
  NSDictionary *pixelAttributes = [self getPixelBufferAttributes];
  
  CVPixelBufferRef cvPixelBuffer = NULL;
  
  uint32_t yuvImageFormatType;
  yuvImageFormatType = kCVPixelFormatType_OneComponent8; // luma (0, 255)
  
  // FIXME: Invoke CVPixelBufferCreateWithPlanarBytes() but create just
  // 1 single plane of widthxheight bytes. Use this when holding on to
  // a buffer, in the case where a buffer is rendered and then dropped
  // there is no need to create a new buffer and copy since that wastes
  // CPU time in process.
  
  CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        yuvImageFormatType,
                                        (__bridge CFDictionaryRef)(pixelAttributes),
                                        &cvPixelBuffer);
  
  NSAssert(result == kCVReturnSuccess, @"CVPixelBufferCreate failed");
  
  return cvPixelBuffer;
}

// Copy pixel data from CoreGraphics source into vImage buffer for processing.
// Note that data is copied as original pixel values, for example if the input
// is in linear RGB then linear RGB values are copied over.

+ (BOOL) convertIntoCoreVideoBuffer:(CGImageRef)inputImageRef
                      cvPixelBuffer:(CVPixelBufferRef)cvPixelBuffer
                          bufferPtr:(vImage_Buffer*)bufferPtr
{
  // Default to sRGB on both MacOSX and iOS
  //CGColorSpaceRef inputColorspaceRef = NULL;
  CGColorSpaceRef inputColorspaceRef = CGImageGetColorSpace(inputImageRef);
  
  vImageCVImageFormatRef cvImgFormatRef;

  if ((1)) {
    // Create from CoreVideo pixel buffer properties
    cvImgFormatRef = vImageCVImageFormat_CreateWithCVPixelBuffer(cvPixelBuffer);
  } else {
    // Init vImageCVImageFormatRef explicitly to enable sRGB boost to
    // the input signal described in docs for vImageBuffer_CopyToCVPixelBuffer()
    // This logic depends on a colorspace not being set on the CoreVideo buffer!
    
    int alphaIsOne = 1; // 24 BPP
    
    cvImgFormatRef = vImageCVImageFormat_Create(
                                                CVPixelBufferGetPixelFormatType(cvPixelBuffer),
                                                kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
                                                kCVImageBufferChromaLocation_Center,
                                                inputColorspaceRef,
                                                alphaIsOne);
  }

  vImage_CGImageFormat rgbCGImgFormat = {
    .bitsPerComponent = 8,
    .bitsPerPixel = 32,
    .bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst),
    .colorSpace = inputColorspaceRef,
  };
  
  const CGFloat backgroundColor = 0.0f;
  
  vImage_Flags flags = 0;
  flags = kvImagePrintDiagnosticsToConsole;
  
  vImage_Error err;
  
  // Copy input CoreGraphic image data into vImage buffer and then copy into CoreVideo buffer
  
  err = vImageBuffer_InitWithCGImage(bufferPtr, &rgbCGImgFormat, &backgroundColor, inputImageRef, flags);
  
  NSAssert(err == kvImageNoError, @"vImageBuffer_InitWithCGImage failed");
  
  err = vImageBuffer_CopyToCVPixelBuffer(bufferPtr, &rgbCGImgFormat, cvPixelBuffer, cvImgFormatRef, &backgroundColor, flags);
  
  NSAssert(err == kvImageNoError, @"error in vImageBuffer_CopyToCVPixelBuffer %d", (int)err);
  
  vImageCVImageFormat_Release(cvImgFormatRef);
  
  return TRUE;
}

// Convert the contents of a CoreVideo pixel buffer and write the results
// into the indicated destination vImage buffer.

+ (BOOL) convertFromCoreVideoBuffer:(CVPixelBufferRef)cvPixelBuffer
                          bufferPtr:(vImage_Buffer*)bufferPtr
                         colorspace:(CGColorSpaceRef)colorspace
{
  // Note that NULL passed in as colorspace defines colorspace as sRGB on both MacOSX and iOS
  
  vImage_CGImageFormat rgbCGImgFormat = {
    .bitsPerComponent = 8,
    .bitsPerPixel = 32,
    .bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst),
    .colorSpace = colorspace,
  };

//  const uint32_t bitsPerPixel = 32;
  const CGFloat backgroundColor = 0.0f;
  
  vImage_Flags flags = 0;
  flags = kvImagePrintDiagnosticsToConsole;
  
  vImage_Error err;
  
  vImageCVImageFormatRef cvImgFormatRef;
  
  if ((1)) {
    // Create from CoreVideo pixel buffer properties
    cvImgFormatRef = vImageCVImageFormat_CreateWithCVPixelBuffer(cvPixelBuffer);
  } else {
    // Init vImageCVImageFormatRef explicitly to enable sRGB boost to
    // the input signal described in docs for vImageBuffer_CopyToCVPixelBuffer()
    // This logic depends on a colorspace not being set on the CoreVideo buffer!
    
    int alphaIsOne = 1; // 24 BPP
    
    cvImgFormatRef = vImageCVImageFormat_Create(
                                                CVPixelBufferGetPixelFormatType(cvPixelBuffer),
                                                kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
                                                kCVImageBufferChromaLocation_Center,
                                                colorspace,
                                                alphaIsOne);
  }
  
  NSAssert(cvImgFormatRef, @"vImageCVImageFormat_CreateWithCVPixelBuffer failed");
  
  err = vImageBuffer_InitWithCVPixelBuffer(bufferPtr, &rgbCGImgFormat, cvPixelBuffer, cvImgFormatRef, &backgroundColor, flags);
  
  NSAssert(err == kvImageNoError, @"vImageBuffer_InitWithCVPixelBuffer failed");
  
  vImageCVImageFormat_Release(cvImgFormatRef);
  
  if (err != kvImageNoError) {
    return FALSE;
  }
  
  return TRUE;
}

// Copy Y Cb Cr pixel data from the planes of a CoreVideo pixel buffer.
// Writes Y Cb Cr values to grayscale PNG if dump flag is TRUE.

+ (BOOL) copyYCBCr:(CVPixelBufferRef)cvPixelBuffer
                 Y:(NSMutableData*)Y
                Cb:(NSMutableData*)Cb
                Cr:(NSMutableData*)Cr
              dump:(BOOL)dump
{
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);

  NSAssert((width % 2) == 0, @"width must be even : got %d", width);
  NSAssert((height % 2) == 0, @"height must be even : got %d", height);
  
  int hw = width / 2;
  int hh = height / 2;

  [Y setLength:width*height];
  [Cb setLength:hw*hh];
  [Cr setLength:hw*hh];
  
  {
    int status = CVPixelBufferLockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);
    assert(status == kCVReturnSuccess);
  }
  
  uint8_t *yOutPtr = (uint8_t *) Y.bytes;
  uint8_t *CbOutPtr = (uint8_t *) Cb.bytes;
  uint8_t *CrOutPtr = (uint8_t *) Cr.bytes;
  
  uint8_t *yPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 0);
  const size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 0);
  
  for (int row = 0; row < height; row++) {
    uint8_t *rowPtr = yPlane + (row * yBytesPerRow);
    for (int col = 0; col < width; col++) {
      uint8_t bVal = rowPtr[col];
      
      int offset = (row * width) + col;
      yOutPtr[offset] = bVal;
    }
  }
  
  uint16_t *uvPlane = (uint16_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 1);
  const size_t cbcrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 1);
  const size_t cbcrPixelsPerRow = cbcrBytesPerRow / sizeof(uint16_t);
  
  for (int row = 0; row < hh; row++) {
    uint16_t *rowPtr = uvPlane + (row * cbcrPixelsPerRow);
    
    for (int col = 0; col < hw; col++) {
      uint16_t bPairs = rowPtr[col];
      uint8_t cbByte = bPairs & 0xFF; // uvPair[0]
      uint8_t crByte = (bPairs >> 8) & 0xFF; // uvPair[1]

      int offset = (row * hw) + col;
      CbOutPtr[offset] = cbByte;
      CrOutPtr[offset] = crByte;
    }
  }
  
  {
    int status = CVPixelBufferUnlockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);
    assert(status == kCVReturnSuccess);
  }
  
  if (dump && 0) {
    uint8_t *yPtr = (uint8_t*)Y.bytes;
    uint8_t *cbPtr = (uint8_t*)Cb.bytes;
    uint8_t *crPtr = (uint8_t*)Cr.bytes;
    
    int Y = yPtr[0];
    int Cb = cbPtr[0];
    int Cr = crPtr[0];
    printf("first pixel (Y Cb Cr) (%3d %3d %3d)\n", Y, Cb, Cr);
  }
  
#if defined(DEBUG)
  if (dump) {
    NSString *filename = [NSString stringWithFormat:@"dump_Y.png"];
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:filename];
    [self dumpArrayOfGrayscale:(uint8_t*)Y.bytes width:width height:height filename:path];
    NSLog(@"wrote %@ : %d x %d", path, width, height);
  }
  
  if (dump) {
    NSString *filename = [NSString stringWithFormat:@"dump_Cb.png"];
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:filename];
    [self dumpArrayOfGrayscale:(uint8_t*)Cb.bytes width:hw height:hh filename:path];
    NSLog(@"wrote %@ : %d x %d", path, hw, hh);
  }
  
  if (dump) {
    NSString *filename = [NSString stringWithFormat:@"dump_Cr.png"];
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:filename];
    [self dumpArrayOfGrayscale:(uint8_t*)Cr.bytes width:hw height:hh filename:path];
    NSLog(@"wrote %@ : %d x %d", path, hw, hh);
  }
#endif // DEBUG
  
  return TRUE;
}

// Dump the Y Cb Cr elements of a CoreVideo pixel buffer to PNG images
// in the tmp directory.

+ (BOOL) dumpYCBCr:(CVPixelBufferRef)cvPixelBuffer
{
  NSMutableData *Y = [NSMutableData data];
  NSMutableData *Cb = [NSMutableData data];
  NSMutableData *Cr = [NSMutableData data];
  
  [self copyYCBCr:cvPixelBuffer Y:Y Cb:Cb Cr:Cr dump:TRUE];
  
  return TRUE;
}

// Dump grayscale pixels as 24 BPP PNG image

+ (void) dumpArrayOfGrayscale:(uint8_t*)inGrayscalePtr
                        width:(int)width
                       height:(int)height
                     filename:(NSString*)filename
{
  CGFrameBuffer *fb = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  uint32_t *pixelsPtr = (uint32_t *) fb.pixels;
  
  for ( int i = 0; i < (width*height); i++) {
    uint8_t gray = inGrayscalePtr[i];
    uint32_t pixel = byte_to_grayscale24(gray);
    *pixelsPtr++ = pixel;
  }
  
#if TARGET_OS_IPHONE
  // No-op
#else
  CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  fb.colorspace = colorspace;
  CGColorSpaceRelease(colorspace);
#endif // TARGET_OS_IPHONE
  
  NSData *pngData = [fb formatAsPNG];
  BOOL worked = [pngData writeToFile:filename atomically:TRUE];
  assert(worked);
  return;
}

+ (BOOL) setColorspace:(CVPixelBufferRef)cvPixelBuffer
            colorSpace:(CGColorSpaceRef)colorSpace
{
  //CFDataRef colorProfileData = CGColorSpaceCopyICCProfile(colorSpace); // deprecated
  CFDataRef colorProfileData = CGColorSpaceCopyICCData(colorSpace);
  NSAssert(colorProfileData, @"CGColorSpaceCopyICCData retuned nil");
  
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

+ (CVPixelBufferRef) createYCbCrFromCGImage:(CGImageRef)inputImageRef
{
  return [self createYCbCrFromCGImage:inputImageRef isLinear:FALSE asSRGBGamma:FALSE];
}

// Given a CGImageRef, create a CVPixelBufferRef and render into it,
// format input BGRA data into BT.709 formatted YCbCr at 4:2:0 subsampling.
// This method returns a new CoreVideo buffer on success, otherwise failure.
// The isLinear argument forces the conversion logic to treat input pixels
// as linear SRGB with a gamma = 1.0. If instead, the asSRGBGamma flag
// is set to TRUE then the sRGB gamma function is applied to values
// before converting to BT.709 values.

+ (CVPixelBufferRef) createYCbCrFromCGImage:(CGImageRef)inputImageRef
                                   isLinear:(BOOL)isLinear
                                   asSRGBGamma:(BOOL)asSRGBGamma
{
  if (isLinear) {
    assert(asSRGBGamma == FALSE);
  }

  int width = (int) CGImageGetWidth(inputImageRef);
  int height = (int) CGImageGetHeight(inputImageRef);
  
  CGSize size = CGSizeMake(width, height);

  // FIXME: pixel buffer pool here?
  
  CVPixelBufferRef cvPixelBuffer = [self createCoreVideoYCbCrBuffer:size];
  
  BOOL worked;
  
  worked = [self setBT709Attributes:cvPixelBuffer];
  NSAssert(worked, @"worked");

  // Explicitly set BT.709 as the colorspace of the pixels, this logic
  // will convert from the input colorspace and gamma settings to the
  // BT.709 defined gamma space. Note that sRGB and BT.709 share the
  // same color primaries so typically only the gamma is adjusted
  // in this type of conversion.
  
  if (isLinear) {
    CGColorSpaceRef inputCS = CGImageGetColorSpace(inputImageRef);
    worked = [self setColorspace:cvPixelBuffer colorSpace:inputCS];
  } else if (asSRGBGamma) {
    CGColorSpaceRef sRGBcs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    worked = [self setColorspace:cvPixelBuffer colorSpace:sRGBcs];
    CGColorSpaceRelease(sRGBcs);
  } else {
    worked = [self setBT709Colorspace:cvPixelBuffer];
  }
  
  NSAssert(worked, @"worked");

  vImage_Buffer sourceBuffer;
  
  worked = [self convertIntoCoreVideoBuffer:inputImageRef cvPixelBuffer:cvPixelBuffer bufferPtr:&sourceBuffer];
  NSAssert(worked, @"worked");

  if ((0)) {
    uint32_t *pixelPtr = (uint32_t *) sourceBuffer.data;
    uint32_t pixel = pixelPtr[0];
    
    int B = pixel & 0xFF;
    int G = (pixel >> 8) & 0xFF;
    int R = (pixel >> 16) & 0xFF;
    
    printf("first pixel (R G B) : %3d %3d %3d\n", R, G, B);
  }
  
  if ((0)) {
    printf("sourceBuffer %d x %d : R G B\n", width, height);
    
    const int srcRowBytes = sourceBuffer.rowBytes;
    
    for (int row = 0; row < height; row++) {
      uint32_t *rowPtr = (uint32_t*) (((uint8_t*)sourceBuffer.data) + (row * srcRowBytes));
      
      for (int col = 0; col < width; col++) {
        uint32_t inPixel = rowPtr[col];
        
        uint32_t B = (inPixel & 0xFF);
        uint32_t G = ((inPixel >> 8) & 0xFF);
        uint32_t R = ((inPixel >> 16) & 0xFF);
        
        printf("R G B (%3d %3d %3d)\n", R, G, B);
      }
    }
  }
  
  // Manually free() the allocated buffer for sourceBuffer
  
  free(sourceBuffer.data);
  
  // Copy data from CoreVideo pixel buffer planes into flat buffers
  
  if ((0)) {
    NSMutableData *Y = [NSMutableData data];
    NSMutableData *Cb = [NSMutableData data];
    NSMutableData *Cr = [NSMutableData data];
    
    const BOOL dump = FALSE;
    
    [self copyYCBCr:cvPixelBuffer Y:Y Cb:Cb Cr:Cr dump:dump];
    
    if ((1)) {
      // Dump YUV of first pixel
      
      uint8_t *yPtr = (uint8_t *) Y.bytes;
      uint8_t *cbPtr = (uint8_t *) Cb.bytes;
      uint8_t *crPtr = (uint8_t *) Cr.bytes;
      
      int Y = yPtr[0];
      int Cb = cbPtr[0];
      int Cr = crPtr[0];
      printf("first pixel (Y Cb Cr) (%3d %3d %3d)\n", Y, Cb, Cr);
    }
  }
  
  /*
  
  if (1) {
    // Convert the generated Y pixels back to RGB pixels
    // using CoreVideo and capture the results into a PNG.
    
    CGFrameBuffer *fb = [self processYUVTosRGB:cvPixelBuffer];
    
    {
      NSString *filename = [NSString stringWithFormat:@"dump_RGB_from_YUV.png"];
      NSString *tmpDir = NSTemporaryDirectory();
      NSString *path = [tmpDir stringByAppendingPathComponent:filename];
      NSData *pngData = [fb formatAsPNG];
      
      BOOL worked = [pngData writeToFile:path atomically:TRUE];
      assert(worked);
    }
    
    if ((1)) {
      // Dump RGB of first pixel
      uint32_t *pixelPtr = (uint32_t*) fb.pixels;
      uint32_t pixel = pixelPtr[0];
      int B = pixel & 0xFF;
      int G = (pixel >> 8) & 0xFF;
      int R = (pixel >> 16) & 0xFF;
      printf("YUV -> BGRA : first pixel (R G B) (%3d %3d %3d)\n", R, G, B);
    }
  }
   
  */
  
  return cvPixelBuffer;
}

// Copy YCbCr data stored in BGRA pixels into Y CbCr planes in CoreVideo
// pixel buffer.

+ (BOOL) copyBT709ToCoreVideo:(uint32_t*)inBT709Pixels
                cvPixelBuffer:(CVPixelBufferRef)cvPixelBuffer
{
  const int debug = 1;
  
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  {
    {
      int status = CVPixelBufferLockBaseAddress(cvPixelBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
    
    uint8_t *yPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 0);
    const size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 0);
    
    uint16_t *cbcrPlane = (uint16_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 1);
    const size_t cbcrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 1);
    const size_t cbcrPixelsPerRow = cbcrBytesPerRow / sizeof(uint16_t);
    
    for (int row = 0; row < height; row++) {
      uint8_t *yRowPtr = yPlane + (row * yBytesPerRow);
      uint16_t *cbcrRowPtr = cbcrPlane + (row/2 * cbcrPixelsPerRow);
      
      for (int col = 0; col < width; col++) {
        int offset = (row * width) + col;
        uint32_t inPixel = inBT709Pixels[offset];
        
        uint32_t Y = inPixel & 0xFF;
        uint32_t Cb = (inPixel >> 8) & 0xFF;
        uint32_t Cr = (inPixel >> 16) & 0xFF;
        
        yRowPtr[col] = Y;
        
        if (debug) {
          printf("Y %3d\n", Y);
        }
        
        if ((col % 2) == 0) {
          int hcol = col / 2;
          cbcrRowPtr[hcol] = (Cr << 8) | (Cb);
          
          if (debug) {
            printf("Cb Cr (%3d %3d)\n", Cb, Cr);
          }
        }
      }
    }
    
    {
      int status = CVPixelBufferUnlockBaseAddress(cvPixelBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
  }
  
  return TRUE;
}

// Process a YUV CoreVideo buffer with Metal logic that will convert the BT.709
// colorspace image and resample it into a sRGB output image. Note that this
// implementation is not optimal since it allocates intermediate images
// and a CIContext.

+ (CGFrameBuffer*) processYUVTosRGB:(CVPixelBufferRef)cvPixelBuffer
{
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  CIImage *rgbFromCVImage = [CIImage imageWithCVPixelBuffer:cvPixelBuffer];
  
  CIContext *context = [CIContext contextWithOptions:nil];
  
  CGImageRef outCGImageRef = [context createCGImage:rgbFromCVImage fromRect:rgbFromCVImage.extent];
  
  CGFrameBuffer *cgFramebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];

  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  cgFramebuffer.colorspace = cs;
  CGColorSpaceRelease(cs);
  
  [cgFramebuffer renderCGImage:outCGImageRef];
  
  return cgFramebuffer;
}

// Unpremultiply a 32 BPP image and return the results as
// a 24 BPP image where the alpha is assumed to be 0xFF.
// This method returns NULL if there was an error.

+ (CGImageRef) unpremultiply:(CGImageRef)inputImageRef
{
  // Default to sRGB on both MacOSX and iOS
  //CGColorSpaceRef inputColorspaceRef = NULL;
  CGColorSpaceRef inputColorspaceRef = CGImageGetColorSpace(inputImageRef);
  
  vImage_CGImageFormat rgbCGImgFormat24 = {
    .bitsPerComponent = 8,
    .bitsPerPixel = 32,
    .bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst),
    .colorSpace = inputColorspaceRef,
  };
  
  vImage_CGImageFormat rgbCGImgFormat32 = {
    .bitsPerComponent = 8,
    .bitsPerPixel = 32,
    .bitmapInfo = (CGBitmapInfo)(kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst),
    .colorSpace = inputColorspaceRef,
  };
  
  const CGFloat backgroundColor = 0.0f;
  
  vImage_Flags flags = 0;
  flags = kvImagePrintDiagnosticsToConsole;
  
  vImage_Error err;
  
  vImage_Buffer sourceBuffer;
  vImage_Buffer dstBuffer;
  
  // Copy input CoreGraphic image data into vImage buffer and then copy into CoreVideo buffer
  
  err = vImageBuffer_InitWithCGImage(&sourceBuffer, &rgbCGImgFormat32, &backgroundColor, inputImageRef, flags);
  
  NSAssert(err == kvImageNoError, @"vImageBuffer_InitWithCGImage failed");
  
  // Allocate dst buffer
  
  err = vImageBuffer_Init(&dstBuffer,
                          sourceBuffer.height,
                          sourceBuffer.width,
                          rgbCGImgFormat24.bitsPerPixel,
                          flags);

  NSAssert(err == kvImageNoError, @"vImageBuffer_Init failed : %d", (int)err);
  
  err = vImageUnpremultiplyData_BGRA8888(&sourceBuffer,
                                         &dstBuffer,
                                         flags);

  NSAssert(err == kvImageNoError, @"vImageUnpremultiplyData_ARGB8888 failed : %d", (int)err);
  
  CGImageRef unPreImg = vImageCreateCGImageFromBuffer(&dstBuffer,
                                                      &rgbCGImgFormat24,
                                                      nil,
                                                      nil,
                                                      flags,
                                                      &err);
  
  free(sourceBuffer.data);
  free(dstBuffer.data);
  
  return unPreImg;
}

@end
