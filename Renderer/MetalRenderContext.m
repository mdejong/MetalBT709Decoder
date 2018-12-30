//
//  MetalRenderContext.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object Metal references that are associated with a
//  rendering context like a view but are not defined on a
//  render frame. There is 1 render contet for N render frames.

#include "MetalRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
//#import "AAPLShaderTypes.h"

// Private API

@interface MetalRenderContext ()

@end

// Main class performing the rendering
@implementation MetalRenderContext

- (BOOL) isSetup
{
  if (self.identityVerticesBuffer == nil) {
    return FALSE;
  } else {
    return TRUE;
  }
}

- (BOOL) setupMetal
{
  if ([self isSetup] == TRUE) {
    // Invoking setupMetal again after it has already been run in a nop and returns success
    return TRUE;
  }
  
  if (self.device == nil) {
#if defined(DEBUG)
  NSAssert(self.device != nil, @"Metal device must be set before invoking setupMetal");
#endif // DEBUG
    return FALSE;
  }

  id<MTLLibrary> defaultLibrary = self.defaultLibrary;
  if (defaultLibrary == nil) {
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
#if defined(DEBUG)
    NSAssert(defaultLibrary != nil, @"defaultLibrary is nil, is Metal library compiled into Application or Test target?");
#endif // DEBUG
    self.defaultLibrary = defaultLibrary;
  }

  id<MTLCommandQueue> commandQueue = self.commandQueue;
  if (commandQueue == nil) {
    commandQueue = [self.device newCommandQueue];
    self.commandQueue = commandQueue;
  }
  
#if defined(DEBUG)
  NSAssert(self.identityVerticesBuffer == nil, @"identityVerticesBuffer must be nil");
#endif // DEBUG
  
  int tmp = 0;
  self.identityVerticesBuffer = [self makeIdentityVertexBuffer:&tmp];
  self.identityNumVertices = tmp;
  
  return TRUE;
}

// Util to allocate a BGRA 32 bits per pixel texture
// with the given dimensions.

- (id<MTLTexture>) makeBGRATexture:(CGSize)size
                            pixels:(uint32_t*)pixels
                             usage:(MTLTextureUsage)usage
                            isSRGB:(BOOL)isSRGB
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  if (isSRGB) {
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
  } else {
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
  }
  
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  //textureDescriptor.usage = MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead;
  //textureDescriptor.usage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (pixels != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint32_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:pixels
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

- (void) fillBGRATexture:(id<MTLTexture>)texture pixels:(uint32_t*)pixels
{
  NSUInteger bytesPerRow = texture.width * sizeof(uint32_t);
  
  MTLRegion region = {
    { 0, 0, 0 },                   // MTLOrigin
    {texture.width, texture.height, 1} // MTLSize
  };
  
  // Copy the bytes from our data object into the texture
  [texture replaceRegion:region
             mipmapLevel:0
               withBytes:pixels
             bytesPerRow:bytesPerRow];
}

// Query bytes out of an 32 bit texture, return as NSData that contains uint32_t elements

- (NSData*) getBGRATexturePixels:(id<MTLTexture>)texture
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint32_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
        bytesPerRow:width*sizeof(uint32_t)
      bytesPerImage:width*height*sizeof(uint32_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}

// Query pixels from a 32 bit texture and then return those
// pixels by reading the B,G,R,A components as byte values
// in a flat NSData. This method does not depend on endian ordering.

- (NSData*) getBGRATextureAsBytes:(id<MTLTexture>)texture
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *pixelsData = [NSMutableData dataWithLength:width*height*sizeof(uint32_t)];
  
  [texture getBytes:(void*)pixelsData.mutableBytes
        bytesPerRow:width*sizeof(uint32_t)
      bytesPerImage:width*height*sizeof(uint32_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  uint32_t *inPixelPtr = (uint32_t *) pixelsData.bytes;
  
  NSMutableData *bytesData = [NSMutableData dataWithLength:pixelsData.length];
  uint8_t *outBytesPtr = (uint8_t *) bytesData.mutableBytes;
  
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      int offset = (row * width) + col;
      
      uint32_t pixel = inPixelPtr[offset];
      
      uint8_t b0 = pixel & 0xFF;
      uint8_t b1 = (pixel >> 8) & 0xFF;
      uint8_t b2 = (pixel >> 16) & 0xFF;
      uint8_t b3 = (pixel >> 24) & 0xFF;
      
      *outBytesPtr++ = b0;
      *outBytesPtr++ = b1;
      *outBytesPtr++ = b2;
      *outBytesPtr++ = b3;
    }
  }
  
  return [NSData dataWithData:bytesData];
}

// Allocate texture that contains an 8 bit int value in the range (0, 255)
// represented by a half float value.

- (id<MTLTexture>) make8bitTexture:(CGSize)size bytes:(uint8_t*)bytes usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer value in the range (0,255) inclusive
  // represented by a half float
  
  textureDescriptor.pixelFormat = MTLPixelFormatR8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (bytes != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint8_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:bytes
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

// Fill values in an 8 bit texture

- (void) fill8bitTexture:(id<MTLTexture>)texture
                   bytes:(uint8_t*)bytes
{
    NSUInteger bytesPerRow = texture.width * sizeof(uint8_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {texture.width, texture.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:bytes
               bytesPerRow:bytesPerRow];
}

// Query bytes out of an 8 bit texture, return as NSData that contains uint8_t elements

- (NSData*) get8bitTextureBytes:(id<MTLTexture>)texture
{
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint8_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
        bytesPerRow:width*sizeof(uint8_t)
      bytesPerImage:width*height*sizeof(uint8_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}

// RG texture is 2 byte values stored together, typically UV
// 8 bit int value in the range (0, 255) represented by a half float value.

- (id<MTLTexture>) make16bitRGTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer pair in the range (0,255) inclusive
  // represented by a half float pair of values
  
  textureDescriptor.pixelFormat = MTLPixelFormatRG8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (halfwords != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint16_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:halfwords
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

// Allocate 16 bit unsigned int texture

- (id<MTLTexture>) make16bitTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer value in the range (0,255) inclusive
  
  textureDescriptor.pixelFormat = MTLPixelFormatR16Uint;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [self.device newTextureWithDescriptor:textureDescriptor];
  
  if (halfwords != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint16_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:halfwords
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

- (void) fill16bitTexture:(id<MTLTexture>)texture halfwords:(uint16_t*)halfwords
{

  NSUInteger bytesPerRow = texture.width * sizeof(uint16_t);
  
  MTLRegion region = {
    { 0, 0, 0 },                   // MTLOrigin
    {texture.width, texture.height, 1} // MTLSize
  };
  
  // Copy the bytes from our data object into the texture
  [texture replaceRegion:region
             mipmapLevel:0
               withBytes:halfwords
             bytesPerRow:bytesPerRow];
}

// Query bytes out of an 16 bit texture, return as NSData that contains uint16_t elements

- (NSData*) get16bitTexturePixels:(id<MTLTexture>)texture
{
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint16_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
        bytesPerRow:width*sizeof(uint16_t)
      bytesPerImage:width*height*sizeof(uint16_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}

// Create identity vertex buffer

- (id<MTLBuffer>) makeIdentityVertexBuffer:(int*)numPtr
{
  typedef struct
  {
    //  Positions in pixel space (i.e. a value of 100 indicates 100 pixels from the origin/center)
    vector_float2 position;
    
    // 2D texture coordinate
    vector_float2 textureCoordinate;
  } AAPLVertex;
  
  static const AAPLVertex quadVertices[] =
  {
    // Positions, Texture Coordinates
    { {  1,  -1 }, { 1.f, 0.f } },
    { { -1,  -1 }, { 0.f, 0.f } },
    { { -1,   1 }, { 0.f, 1.f } },
    
    { {  1,  -1 }, { 1.f, 0.f } },
    { { -1,   1 }, { 0.f, 1.f } },
    { {  1,   1 }, { 1.f, 1.f } },
  };
  
  *numPtr = sizeof(quadVertices) / sizeof(AAPLVertex);
  
  // Create our vertex buffer, and intializat it with our quadVertices array
  return [self.device newBufferWithBytes:quadVertices
                                           length:sizeof(quadVertices)
                                          options:MTLResourceStorageModeShared];
}

// Create a MTLRenderPipelineDescriptor given a vertex and fragment shader

- (id<MTLRenderPipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                              pipelineLabel:(NSString*)pipelineLabel
                             numAttachments:(int)numAttachments
                         vertexFunctionName:(NSString*)vertexFunctionName
                       fragmentFunctionName:(NSString*)fragmentFunctionName
{
  // Load the vertex function from the library
  id <MTLFunction> vertexFunction = [self.defaultLibrary newFunctionWithName:vertexFunctionName];
  NSAssert(vertexFunction, @"vertexFunction \"%@\" could not be loaded", vertexFunctionName);
  
  // Load the fragment function from the library
  id <MTLFunction> fragmentFunction = [self.defaultLibrary newFunctionWithName:fragmentFunctionName];
  NSAssert(fragmentFunction, @"fragmentFunction \"%@\" could not be loaded", fragmentFunctionName);
  
  // Set up a descriptor for creating a pipeline state object
  MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label = pipelineLabel;
  pipelineStateDescriptor.vertexFunction = vertexFunction;
  pipelineStateDescriptor.fragmentFunction = fragmentFunction;
  
  for ( int i = 0; i < numAttachments; i++ ) {
    pipelineStateDescriptor.colorAttachments[i].pixelFormat = pixelFormat;
  }
  
  NSError *error = NULL;
  
  id<MTLRenderPipelineState> state = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                 error:&error];
  
  if (!state)
  {
    // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
    //  If the Metal API validation is enabled, we can find out more information about what
    //  went wrong.  (Metal API validation is enabled by default when a debug build is run
    //  from Xcode)
    NSLog(@"Failed to created pipeline state, error %@", error);
  }
  
  return state;
}

// Create a pipeline that executes a compute kernel

- (id<MTLComputePipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                               pipelineLabel:(NSString*)pipelineLabel
                          kernelFunctionName:(NSString*)kernelFunctionName
{
    // Load the vertex function from the library
    id <MTLFunction> kernelFunction = [self.defaultLibrary newFunctionWithName:kernelFunctionName];
    NSAssert(kernelFunction, @"kernel function \"%@\" could not be loaded", kernelFunctionName);
    
    NSError *error = NULL;
    
    id<MTLComputePipelineState> state = [self.device newComputePipelineStateWithFunction:kernelFunction
                                                                                   error:&error];
    
    if (!state)
    {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        //  If the Metal API validation is enabled, we can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode)
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    return state;
}

/*
#if TARGET_OS_IPHONE

- (NSUInteger)highestSupportedFeatureSet
{
  const NSUInteger maxKnownFeatureSet = MTLFeatureSet_iOS_GPUFamily2_v1;
  
  for (int featureSet = maxKnownFeatureSet; featureSet >= 0; --featureSet)
  {
    if ([self.device supportsFeatureSet:featureSet])
    {
      return featureSet;
    }
  }
  
  return MTLFeatureSet_iOS_GPUFamily1_v1;
}

- (NSUInteger)featureSetGPUFamily
{
  switch (self.highestSupportedFeatureSet)
  {
    case MTLFeatureSet_iOS_GPUFamily2_v1:
      return 2;
    case MTLFeatureSet_iOS_GPUFamily1_v1:
    default:
      return 1;
  }
}

- (BOOL)supportsASTCPixelFormats
{
  return (self.featureSetGPUFamily > 1);
}

#endif // TARGET_OS_IPHONE
*/

@end
