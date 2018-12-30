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

@interface MetalBT709Decoder : NSObject

// Setup MetalRenderContext instance before the first decode,
// existing Metal refs will be used if set, otherwise new
// instance will be allocated.

@property (nonatomic, retain) MetalRenderContext *metalRenderContext;

@property (nonatomic, assign) MTLPixelFormat colorPixelFormat;

// If set to TRUE, a compute kernel will be used to render,
// otherwise use a fragment shader.

@property (nonatomic, assign) BOOL useComputeRenderer;

// Setup Metal refs for this instance, this is implicitly
// invoked by decodeBT709 but some test code may want to
// setup metal before invoking the decode method.

- (BOOL) setupMetal;

// BT709 -> BGRA conversion that writes directly into a Metal texture.
// This logic assumes that the Metal texture was already allocated at
// exactly the same dimensions as the input YCbCr encoded data.

- (BOOL) decodeBT709:(CVPixelBufferRef)yCbCrInputTexture
     bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
  waitUntilCompleted:(BOOL)waitUntilCompleted;

@end
