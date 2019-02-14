//
//  MetalBT709Decoder.h
//
//  Created by Mo DeJong on 12/26/18.
//
//  Given an input buffer of BT.709 encoded YCbCr data, decode
//  pixels into a sRGB texture.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

@class MetalRenderContext;

typedef enum {
  MetalBT709GammaApple = 0, // default
  MetalBT709GammaSRGB,
  MetalBT709GammaLinear
} MetalBT709Gamma;

@interface MetalBT709Decoder : NSObject

// Setup MetalRenderContext instance before the first decode,
// existing Metal refs will be used if set, otherwise new
// instance will be allocated.

@property (nonatomic, retain) MetalRenderContext *metalRenderContext;

@property (nonatomic, assign) MTLPixelFormat colorPixelFormat;

// Defaults to apple gamma. Caller must set the specific gamma function
// to use white decoded before Metal is initialized. The decoding
// logic must indicate the gamma function to be used at init time
// even though the actualy type of content to be decoded may not
// be known until the first frame of video is read.

@property (nonatomic, assign) MetalBT709Gamma gamma;

// If set to TRUE, a compute kernel will be used to render,
// otherwise use a fragment shader.

@property (nonatomic, assign) BOOL useComputeRenderer;

// If hasAlphaChannel is set to TRUE then a second alpha
// is defined as a linear channel that can be directly
// interpolated.

@property (nonatomic, assign) BOOL hasAlphaChannel;

// Set to TRUE once a render context has been setup

// Setup Metal refs for this instance, this is implicitly
// invoked by decodeBT709 but some test code may want to
// setup metal before invoking the decode method.

- (BOOL) setupMetal;

// BT709 -> BGRA conversion that writes directly into a Metal texture.
// This logic assumes that the Metal texture was already allocated at
// exactly the same dimensions as the input YCbCr encoded data.
// Note that in the case where the render should be done in 1 step,
// meaning directly into a view then pass a renderPassDescriptor.
// A 2 stage render would pass nil for renderPassDescriptor.

- (BOOL) decodeBT709:(CVPixelBufferRef)yCbCrInputTexture
    alphaPixelBuffer:(CVPixelBufferRef)alphaPixelBuffer
     bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
         renderWidth:(int)renderWidth
        renderHeight:(int)renderHeight
  waitUntilCompleted:(BOOL)waitUntilCompleted;

@end
