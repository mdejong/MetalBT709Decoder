//
//  MetalRenderContext.h
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This module references Metal objects that are associated with
//  a rendering context, like a view but are not defined on a
//  render frame. There is 1 render context for N render frames.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@interface MetalRenderContext : NSObject

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, retain) id<MTLLibrary> defaultLibrary;
@property (nonatomic, retain) id<MTLCommandQueue> commandQueue;

@property (nonatomic, retain) id<MTLBuffer> identityVerticesBuffer;
@property (nonatomic, assign) int identityNumVertices;

// Query GPU feature set flags

//@property (readonly) NSUInteger highestSupportedFeatureSet;

// Return 1 for A7, otherwise returns 2

//@property (readonly) NSUInteger featureSetGPUFamily;

//@property (readonly) BOOL supportsASTCPixelFormats;

// Invoke this method once a MetalRenderFrame object has been created
// to allocate and create metal resources with the given device instance.
// Note that the device property must be set before this invocation but
// the defaultLibrary and commandQueue properties will be allocated if
// they are not already set as properties. Returns TRUE on success, FALSE
// if any of the Metal setup steps fails. One example FALSE return condition
// could be failing to locate Metal compiled library in the application bundle
// or test bundle.

- (BOOL) setupMetal;

// Create a MTLRenderPipelineDescriptor given a vertex and fragment shader

- (id<MTLRenderPipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                              pipelineLabel:(NSString*)pipelineLabel
                             numAttachments:(int)numAttachments
                         vertexFunctionName:(NSString*)vertexFunctionName
                       fragmentFunctionName:(NSString*)fragmentFunctionName;

// Create a pipeline that executes a compute kernel

- (id<MTLComputePipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                               pipelineLabel:(NSString*)pipelineLabel
                          kernelFunctionName:(NSString*)kernelFunctionName;

// Util to allocate a BGRA 32 bits per pixel texture
// with the given dimensions.

- (id<MTLTexture>) makeBGRATexture:(CGSize)size
                            pixels:(uint32_t*)pixels
                             usage:(MTLTextureUsage)usage
                            isSRGB:(BOOL)isSRGB;

- (void) fillBGRATexture:(id<MTLTexture>)texture pixels:(uint32_t*)pixels;

// Query bytes out of an 32 bit texture, return as NSData that contains uint32_t elements

- (NSData*) getBGRATexturePixels:(id<MTLTexture>)texture;

// Query pixels from a 32 bit texture and then return those
// pixels by reading the B,G,R,A components as byte values
// in a flat NSData. This method does not depend on endian ordering.

- (NSData*) getBGRATextureAsBytes:(id<MTLTexture>)texture;

// Allocate texture that contains an 8 bit int value in the range (0, 255)
// represented by a half float value.

- (id<MTLTexture>) make8bitTexture:(CGSize)size bytes:(uint8_t*)bytes usage:(MTLTextureUsage)usage;

// Fill values in an 8 bit texture

- (void) fill8bitTexture:(id<MTLTexture>)texture bytes:(uint8_t*)bytes;

// Query bytes out of an 8 bit texture, return as NSData that contains uint8_t elements

- (NSData*) get8bitTextureBytes:(id<MTLTexture>)texture;

// Allocate 16 bit unsigned int texture

- (id<MTLTexture>) make16bitTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage;

- (void) fill16bitTexture:(id<MTLTexture>)texture halfwords:(uint16_t*)halfwords;

// Query bytes out of an 16 bit texture, return as NSData that contains uint16_t elements

- (NSData*) get16bitTexturePixels:(id<MTLTexture>)texture;

// RG texture is 2 byte values stored together, typically UV
// 8 bit int value in the range (0, 255) represented by a half float value.

- (id<MTLTexture>) make16bitRGTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage;

@end
