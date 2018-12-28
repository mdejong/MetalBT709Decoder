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

@interface MetalBT709Decoder : NSObject

// If an existing Metal ref is provided by the system, set
// this property before the first call to decode. If not
// defined by the user then a default system Metal device
// is allocated.

@property (nonatomic, retain) id<MTLDevice> device;

@property (nonatomic, retain) id<MTLLibrary> defaultLibrary;

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
