//
//  MetalBT709Decoder.h
//
//  Created by Mo DeJong on 12/26/18.
//

#import "MetalBT709Decoder.h"

#import "MetalRenderContext.h"

@interface MetalBT709Decoder ()
{
  CVMetalTextureCacheRef _textureCache;
}

@property (nonatomic, retain) id<MTLComputePipelineState> computePipelineState;

// FIXME: Make Y and CbCr textures a set of properties that can be passed
// in so that triple buffering is possible.

@property (nonatomic, retain) id<MTLTexture> inputYTexture;
@property (nonatomic, retain) id<MTLTexture> inputCbCrTexture;

@end

@implementation MetalBT709Decoder

- (void) deallocate
{
  self.inputYTexture = nil;
  self.inputCbCrTexture = nil;
  
  if (_textureCache != NULL) {
    CVMetalTextureCacheFlush(_textureCache, 0);
    CFRelease(_textureCache);
  }
  
  return;
}

- (BOOL) setupMetal
{
  if (self.metalRenderContext == nil) {
#if defined(DEBUG)
    NSAssert(self.metalRenderContext != nil, @"metalRenderContext must be set before invoking setupMetal");
#endif // DEBUG

    return FALSE;
  }
  
  NSError *error = NULL;
  
  MetalRenderContext *metalRenderContext = self.metalRenderContext;
  
  // Invoking setupMetal a second time is a nop
  
  BOOL worked = [metalRenderContext setupMetal];
  if (!worked) {
    return FALSE;
  }
  
  id<MTLLibrary> defaultLibrary = metalRenderContext.defaultLibrary;
  if (defaultLibrary == nil) {
#if defined(DEBUG)
    NSAssert(defaultLibrary, @"metalRenderContext.defaultLibrary is nil");
#endif // DEBUG
    return FALSE;
  }
  
  // Load the kernel function from the library
  id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"BT709ToLinearSRGBKernel"];
  
  // Create a compute pipeline state
  self.computePipelineState = [metalRenderContext.device newComputePipelineStateWithFunction:kernelFunction
                                                                         error:&error];
  
  if (self.computePipelineState == nil)
  {
    // Compute pipeline State creation could fail if kernelFunction failed to load from the
    //   library.  If the Metal API validation is enabled, we automatically be given more
    //   information about what went wrong.  (Metal API validation is enabled by default
    //   when a debug build is run from Xcode)
#if defined(DEBUG)
    NSAssert(self.computePipelineState, @"Failed to create compute pipeline state, error %@", error);
#else
    NSLog(@"Failed to create compute pipeline state, error %@", error);
#endif // DEBUG
    return FALSE;
  }
  
  // Setup testure cache so that pixel buffers can be represented by a Metal texture
  
  NSDictionary *cacheAttributes = @{
                                    (NSString*)kCVMetalTextureCacheMaximumTextureAgeKey: @(0),
                                    };
  
  CVReturn status = CVMetalTextureCacheCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)cacheAttributes, metalRenderContext.device, nil, &_textureCache);
  if (status != kCVReturnSuccess || _textureCache == NULL) {
#if defined(DEBUG)
  NSParameterAssert(status == kCVReturnSuccess && _textureCache != NULL);
#endif // DEBUG
    return FALSE;
  }
  
  return TRUE;
}

// BT709 -> BGRA conversion that writes directly into a Metal texture.
// This logic assumes that the Metal texture was already allocated at
// exactly the same dimensions as the input YCbCr encoded data.

- (BOOL) decodeBT709:(CVPixelBufferRef)yCbCrInputTexture
     bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
  waitUntilCompleted:(BOOL)waitUntilCompleted
{
  BOOL worked;
  
  worked = [self setupMetal];
  if (worked == FALSE) {
    return FALSE;
  }
  
  worked = [self processBT709ToSRGB:yCbCrInputTexture
                    bgraSRGBTexture:bgraSRGBTexture
                      commandBuffer:commandBuffer
                 waitUntilCompleted:waitUntilCompleted];
  if (worked == FALSE) {
    return FALSE;
  }
  
  return TRUE;
}

// Process a YUV CoreVideo buffer with Metal logic that will convert the BT.709
// colorspace image and resample it into a sRGB output image.

- (BOOL) processBT709ToSRGB:(CVPixelBufferRef)cvPixelBuffer
            bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
         waitUntilCompleted:(BOOL)waitUntilCompleted
{
  const int debug = 0;
  
  // Setup Metal textures for Y and UV input
  
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  // Verify that the SRGB output texture buffer is exactly the same pixel
  // dimensions as the YCbCr pixel buffer, resizing and scaling a
  // non-linear BT709 input texture would generate incorrect pixel values.
  
  NSAssert(width == bgraSRGBTexture.width, @"width mismatch between BT709 and SRGB : %d != %d", width, (int)bgraSRGBTexture.width);
  NSAssert(height == bgraSRGBTexture.height, @"height mismatch between BT709 and SRGB : %d != %d", height, (int)bgraSRGBTexture.height);
  if (width != bgraSRGBTexture.width || height != bgraSRGBTexture.height) {
    return FALSE;
  }
  
  int hw = width / 2;
  int hh = height / 2;
  
  // Map Metal texture to the CoreVideo pixel buffer
  
  id<MTLTexture> inputYTexture = nil;
  id<MTLTexture> inputCbCrTexture = nil;
  
  {
    CVMetalTextureRef yTextureWrapperRef = NULL;
    
    CVReturn ret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                             _textureCache,
                                                             cvPixelBuffer,
                                                             nil,
                                                             MTLPixelFormatR8Unorm,
                                                             width,
                                                             height,
                                                             0,
                                                             &yTextureWrapperRef);
    
    NSParameterAssert(ret == kCVReturnSuccess && yTextureWrapperRef != NULL);
    
    inputYTexture = CVMetalTextureGetTexture(yTextureWrapperRef);
    
    CFRelease(yTextureWrapperRef);
  }

  {
    CVMetalTextureRef cbcrTextureWrapperRef = NULL;
    
    CVReturn ret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                             _textureCache,
                                                             cvPixelBuffer,
                                                             nil,
                                                             MTLPixelFormatRG8Unorm,
                                                             hw,
                                                             hh,
                                                             1,
                                                             &cbcrTextureWrapperRef);
    
    NSParameterAssert(ret == kCVReturnSuccess && cbcrTextureWrapperRef != NULL);
    
    inputCbCrTexture = CVMetalTextureGetTexture(cbcrTextureWrapperRef);
    
    CFRelease(cbcrTextureWrapperRef);
  }
  
  // Dumping contents only needed when DEBUG is explicitly indicated
  
  if (debug) {
    
    // lock and grab pointers to copy from
    
    {
      int status = CVPixelBufferLockBaseAddress(cvPixelBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
    
    // FIXME: It should be possible to wrap these CoreVideo pixel buffer planes
    // as Metal textures directly without cistly memcpy()
    
    uint8_t *yPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 0);
    size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 0);
    //assert(yBytesPerRow == width);
    
    uint8_t *yPlanePacked = (uint8_t *) malloc(width * height * sizeof(uint8_t));
    
    for (int row = 0; row < height; row++) {
      uint8_t *inRowPtr = yPlane + (row * yBytesPerRow);
      uint8_t *outRowPtr = yPlanePacked + (row * (width * sizeof(uint8_t)));
      
      for (int col = 0; col < width; col++) {
        int Y = inRowPtr[col];
        outRowPtr[col] = Y;
      }
    }
    
    uint16_t *uvPlane = (uint16_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, 1);
    size_t uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, 1);
    //assert(uvBytesPerRow == (hw * sizeof(uint16_t)));
    
    uint16_t *uvPlanePacked = (uint16_t *) malloc(hw * hh * sizeof(uint16_t));
    
    for (int row = 0; row < hh; row++) {
      uint16_t *inRowPtr = (uint16_t*) (((uint8_t*)uvPlane) + (row * uvBytesPerRow));
      uint16_t *outRowPtr = (uint16_t*) (((uint8_t*)uvPlanePacked) + (row * (hw * sizeof(uint16_t))));
      
      for (int col = 0; col < hw; col++) {
        uint16_t uv = inRowPtr[col];
        outRowPtr[col] = uv;
      }
    }
    
    // Debug dump Y
    
    if (debug) {
      printf("Y : %d x %d\n", width, height);
      
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          int offset = (row * width) + col;
          int Y = yPlanePacked[offset];
          printf("%3d ", Y);
        }
        printf("\n");
      }
    }
    
    // Debug dump CbCr
    
    if (debug) {
      printf("CbCr : %d x %d\n", hw, hh);
      
      for (int row = 0; row < hh; row++) {
        for (int col = 0; col < hw; col++) {
          int offset = (row * hw) + col;
          uint16_t CbCr = uvPlanePacked[offset];
          uint8_t Cb = CbCr & 0xFF;
          uint8_t Cr = (CbCr >> 8) & 0xFF;
          printf("%3d %3d ", Cb, Cr);
        }
        printf("\n");
      }
    }
    
    free(yPlanePacked);
    free(uvPlanePacked);
    
    {
      int status = CVPixelBufferUnlockBaseAddress(cvPixelBuffer, 0);
      assert(status == kCVReturnSuccess);
    }
  }

  // Hold on to texture ref until next render
  self.inputYTexture = inputYTexture;
  self.inputCbCrTexture = inputCbCrTexture;
  
  id<MTLTexture> outputTexture = bgraSRGBTexture;
  
  // Setup mapping from pixels to threadgroups
  
  const int blockDim = 8;
  
  int numBlocksInWidth = width / blockDim;
  if ((outputTexture.width % blockDim) != 0) {
    numBlocksInWidth += 1;
  }
  
  int numBlocksInHeight = height / blockDim;
  if ((outputTexture.height % blockDim) != 0) {
    numBlocksInHeight += 1;
  }
  
  MTLSize threadsPerThreadgroup = MTLSizeMake(blockDim, blockDim, 1);
  MTLSize threadsPerGrid = MTLSizeMake(numBlocksInWidth, numBlocksInHeight, 1);
  
  id<MTLComputeCommandEncoder> computeEncoder;
  
  computeEncoder = [commandBuffer computeCommandEncoder];
  
  [computeEncoder setComputePipelineState:self.computePipelineState];
  
  // Render YCbCr -> SRGB
  
  [computeEncoder setTexture:inputYTexture atIndex:0];
  [computeEncoder setTexture:inputCbCrTexture atIndex:1];
  [computeEncoder setTexture:outputTexture atIndex:2];
  
  [computeEncoder dispatchThreadgroups:threadsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
  
  [computeEncoder endEncoding];
  
  // Wait for GPU to complete this task
  
  if (waitUntilCompleted) {
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
  }
  
  return TRUE;
}

@end
