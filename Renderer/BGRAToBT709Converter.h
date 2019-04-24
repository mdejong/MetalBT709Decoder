//
//  BGRAToBT709Converter.h
//
//  Created by Mo DeJong on 11/25/18.
//
//  Convert a buffer of sRGB BGRA pixels to BT.709 colorspace pixels.
//  This logic could do YCbCr 4:2:0 subsampling, the value here is
//  that input in the sRGB log space can be internally converted to
//  the linear RGB linear space and then to the BT.709 log colorspace
//  without a loss of precision due to rounding to linear byte step values.
//  The output is (Y Cb CR) pixels stored as (B G R A) -> (Y Cb Cr X)

#import <Foundation/Foundation.h>

#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

@import Accelerate;

@class CGFrameBuffer;

typedef enum {
  BGRAToBT709ConverterSoftware = 0,
  BGRAToBT709ConverterVImage = 1,
  BGRAToBT709ConverterMetal = 2
} BGRAToBT709ConverterTypeEnum;

@interface BGRAToBT709Converter : NSObject

// BGRA -> BT709

+ (BOOL) convert:(uint32_t*)inBGRAPixels
  outBT709Pixels:(uint32_t*)outBT709Pixels
           width:(int)width
          height:(int)height
            type:(BGRAToBT709ConverterTypeEnum)type;

// BT709 -> BGRA

+ (BOOL) unconvert:(uint32_t*)inBT709Pixels
     outBGRAPixels:(uint32_t*)outBGRAPixels
             width:(int)width
            height:(int)height
              type:(BGRAToBT709ConverterTypeEnum)type;

// Util methods, these are used internally but can be useful
// to other modules.

// Set the proper attributes on a CVPixelBufferRef so that vImage
// is able to render directly into BT.709 formatted YCbCr planes.

+ (BOOL) setBT709Attributes:(CVPixelBufferRef)cvPixelBuffer;

// Attach ICC profile data to a pixel buffer, so that pixels rendered
// in the BT.709 colorspace are known to color matching.

+ (BOOL) setBT709Colorspace:(CVPixelBufferRef)cvPixelBuffer;

// Allocate a CoreVideo buffer for use with BT.709 format YCBCr 2 plane data

+ (CVPixelBufferRef) createCoreVideoYCbCrBuffer:(CGSize)size;

// Allocate a CoreVideo buffer that contains a single 8 bit component for each pixel

+ (CVPixelBufferRef) createCoreVideoYBuffer:(CGSize)size;

// Copy pixel data from CoreGraphics source into vImage buffer for processing.
// Note that data is copied as original pixel values, for example if the input
// is in linear RGB then linear RGB values are copied over.

+ (BOOL) convertIntoCoreVideoBuffer:(CGImageRef)inputImageRef
                      cvPixelBuffer:(CVPixelBufferRef)cvPixelBuffer;

// Convert the contents of a CoreVideo pixel buffer and write the results
// into the indicated destination vImage buffer.

+ (BOOL) convertFromCoreVideoBuffer:(CVPixelBufferRef)cvPixelBuffer
                          bufferPtr:(vImage_Buffer*)bufferPtr
                         colorspace:(CGColorSpaceRef)colorspace;

// Copy Y Cb Cr pixel data from the planes of a CoreVideo pixel buffer.
// Writes Y Cb Cr values to grayscale PNG if dump flag is TRUE.

+ (BOOL) copyYCBCr:(CVPixelBufferRef)cvPixelBuffer
                 Y:(NSMutableData*)Y
                Cb:(NSMutableData*)Cb
                Cr:(NSMutableData*)Cr
              dump:(BOOL)dump;

// Dump Y Cb Cr grayscale images to the tmp dir

+ (BOOL) dumpYCBCr:(CVPixelBufferRef)cvPixelBuffer;

// Given a CGImageRef, create a CVPixelBufferRef and render into it,
// format input BGRA data into BT.709 formatted YCbCr at 4:2:0 subsampling.
// This method returns a new CoreVideo buffer on success, otherwise failure.

+ (CVPixelBufferRef) createYCbCrFromCGImage:(CGImageRef)inputImageRef;

// Given a CGImageRef, create a CVPixelBufferRef and render into it,
// format input BGRA data into BT.709 formatted YCbCr at 4:2:0 subsampling.
// This method returns a new CoreVideo buffer on success, otherwise failure.
// The isLinear argument forces the conversion logic to treat input pixels
// as linear SRGB with a gamma = 1.0. If instead, the asSRGBGamma flag
// is set to TRUE then the sRGB gamma function is applied to values
// before converting to BT.709 values.

+ (CVPixelBufferRef) createYCbCrFromCGImage:(CGImageRef)inputImageRef
                                   isLinear:(BOOL)isLinear
                                asSRGBGamma:(BOOL)asSRGBGamma;

// Copy YCbCr data stored in BGRA pixels into Y CbCr planes in CoreVideo
// pixel buffer.

+ (BOOL) copyBT709ToCoreVideo:(uint32_t*)inBT709Pixels
                cvPixelBuffer:(CVPixelBufferRef)cvPixelBuffer;

// Process a YUV CoreVideo buffer with Metal logic that will convert the BT.709
// colorspace image and resample it into a sRGB output image. Note that this
// implementation is not optimal since it allocates intermediate images
// and a CIContext.

+ (CGFrameBuffer*) processYUVTosRGB:(CVPixelBufferRef)cvPixelBuffer;

// Unpremultiply a 32 BPP image and return the results as
// a 24 BPP image where the alpha is assumed to be 0xFF.
// This method returns NULL if there was an error.

+ (CGImageRef) unpremultiply:(CGImageRef)inputImageRef;

@end
