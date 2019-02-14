//
//  MetalBT709Decoder.h
//
//  Created by Mo DeJong on 12/26/18.
//

#import "MetalBT709Decoder.h"

#import "MetalRenderContext.h"

#import "CVPixelBufferUtils.h"

@interface MetalBT709Decoder ()
{
  CVMetalTextureCacheRef _textureCache;
}

@property (nonatomic, retain) id<MTLRenderPipelineState> renderPipelineState;

@property (nonatomic, retain) id<MTLComputePipelineState> computePipelineState;

// FIXME: Make Y and CbCr textures a set of properties that can be passed
// in so that triple buffering is possible.

@property (nonatomic, retain) id<MTLTexture> inputYTexture;
@property (nonatomic, retain) id<MTLTexture> inputCbCrTexture;
@property (nonatomic, retain) id<MTLTexture> inputAlphaTexture;

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
  
  MetalRenderContext *metalRenderContext = self.metalRenderContext;
  
  // Invoking setupMetal a second time is a nop
  
  BOOL worked = [metalRenderContext setupMetal];
  if (!worked) {
    return FALSE;
  }
  
  // Was setupMetal already invoked and it returned successfully?
  
  if (_textureCache != NULL) {
    return TRUE;
  }
  
  id<MTLLibrary> defaultLibrary = metalRenderContext.defaultLibrary;
  if (defaultLibrary == nil) {
#if defined(DEBUG)
    NSAssert(defaultLibrary, @"metalRenderContext.defaultLibrary is nil");
#endif // DEBUG
    return FALSE;
  }
  
  if (self.useComputeRenderer) {
    worked = [self setupMetalComputePipeline];
  } else {
    worked = [self setupMetalRenderPipeline];
  }

  if (worked == FALSE) {
    return FALSE;
  }
  
  // Setup texture cache so that pixel buffers can be represented by a Metal texture
  
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

- (BOOL) setupMetalComputePipeline
{
  NSAssert(self.hasAlphaChannel == FALSE, @"compute pipeline does not support hasAlphaChannel");
  
  NSError *error = NULL;
  
  MetalRenderContext *metalRenderContext = self.metalRenderContext;
  id<MTLLibrary> defaultLibrary = metalRenderContext.defaultLibrary;

  NSString *functionName = nil;
  MetalBT709Gamma gamma = self.gamma;

  if (gamma == MetalBT709GammaApple) {
    functionName = @"BT709ToLinearSRGBKernel";
  } else if (gamma == MetalBT709GammaSRGB) {
    functionName = @"sRGBToLinearSRGBKernel";
  } else if (gamma == MetalBT709GammaLinear) {
    functionName = @"LinearToLinearSRGBKernel";
  } else {
    assert(0);
  }
  
  // Load the kernel function from the library
  id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:functionName];
  
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

  return TRUE;
}

- (BOOL) setupMetalRenderPipeline
{
  NSError *error = NULL;
  
  MetalRenderContext *metalRenderContext = self.metalRenderContext;
  id<MTLLibrary> defaultLibrary = metalRenderContext.defaultLibrary;
  
  // Load vertex function from metal library that renders full size into viewport with flipped Y axis
  id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"identityVertexShader"];
  
  NSString *functionName = nil;
  MetalBT709Gamma gamma = self.gamma;
  
  if (self.hasAlphaChannel) {
    // RGBA alpha channel render supports only the sRGB gamma function and assumes
    // that the alpha channel is always encoded as linear.    
    self.gamma = MetalBT709GammaSRGB;
    functionName = @"sRGBToLinearSRGBFragmentAlpha";
  } else if (gamma == MetalBT709GammaApple) {
    functionName = @"BT709ToLinearSRGBFragment";
  } else if (gamma == MetalBT709GammaSRGB) {
    functionName = @"sRGBToLinearSRGBFragment";
  } else if (gamma == MetalBT709GammaLinear) {
    functionName = @"LinearToLinearSRGBFragment";
  } else {
    assert(0);
  }
  
  // Load the fragment function from the library
  id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:functionName];
  
  // Set up a descriptor for creating a pipeline state object
  MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label = [NSString stringWithFormat:@"Render Pipeline %@", functionName];
  pipelineStateDescriptor.vertexFunction = vertexFunction;
  pipelineStateDescriptor.fragmentFunction = fragmentFunction;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
  
  //NSError *error = NULL;
  self.renderPipelineState = [metalRenderContext.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                       error:&error];
  if (self.renderPipelineState == nil)
  {
    // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
    //  If the Metal API validation is enabled, we can find out more information about what
    //  went wrong.  (Metal API validation is enabled by default when a debug build is run
    //  from Xcode)
#if defined(DEBUG)
    NSAssert(self.renderPipelineState, @"Failed to create pipeline state, error %@", error);
#else
    NSLog(@"Failed to create pipeline state, error %@", error);
#endif // DEBUG
    return FALSE;
  }
  
  return TRUE;
}

// BT709 -> BGRA conversion that writes directly into a Metal texture.
// This logic assumes that the Metal texture was already allocated at
// exactly the same dimensions as the input YCbCr encoded data.
// Note that in the case where the render should be done in 1 step,
// meaning directly into a view then pass a renderPassDescriptor.
// A 2 stage render would pass nil for renderPassDescriptor.

- (BOOL) decodeBT709:(CVPixelBufferRef)yCbCrPixelBuffer
    alphaPixelBuffer:(CVPixelBufferRef)alphaPixelBuffer
     bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
       commandBuffer:(id<MTLCommandBuffer>)commandBuffer
renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
         renderWidth:(int)renderWidth
        renderHeight:(int)renderHeight
  waitUntilCompleted:(BOOL)waitUntilCompleted
{
  BOOL worked;
  
  worked = [self setupMetal];
  if (worked == FALSE) {
    return FALSE;
  }
  
  worked = [self processBT709ToSRGB:yCbCrPixelBuffer
                   alphaPixelBuffer:alphaPixelBuffer
                    bgraSRGBTexture:bgraSRGBTexture
                      commandBuffer:commandBuffer
               renderPassDescriptor:renderPassDescriptor
                        renderWidth:renderWidth
                       renderHeight:renderHeight
                 waitUntilCompleted:waitUntilCompleted];

  if (worked == FALSE) {
    return FALSE;
  }
  
  return TRUE;
}

// Process a YUV CoreVideo buffer with Metal logic that will convert the BT.709
// colorspace image and resample it into a sRGB output image.

- (BOOL) processBT709ToSRGB:(CVPixelBufferRef)cvPixelBuffer
           alphaPixelBuffer:(CVPixelBufferRef)alphaPixelBuffer
            bgraSRGBTexture:(id<MTLTexture>)bgraSRGBTexture
              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
       renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
                renderWidth:(int)renderWidth
               renderHeight:(int)renderHeight
         waitUntilCompleted:(BOOL)waitUntilCompleted
{
  const int debug = 0;
  
  // Setup Metal textures for Y and UV input
  
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  // Verify that the SRGB output texture buffer is exactly the same pixel
  // dimensions as the YCbCr pixel buffer, resizing and scaling a
  // non-linear BT709 input texture would generate incorrect pixel values.
  
  if (bgraSRGBTexture != nil) {
#if defined(DEBUG)
    NSAssert(width == bgraSRGBTexture.width, @"width mismatch between BT709 and SRGB : %d != %d", width, (int)bgraSRGBTexture.width);
    NSAssert(height == bgraSRGBTexture.height, @"height mismatch between BT709 and SRGB : %d != %d", height, (int)bgraSRGBTexture.height);
#endif // DEBUG
    
    if (width != bgraSRGBTexture.width || height != bgraSRGBTexture.height) {
      return FALSE;
    }
  }

#if defined(DEBUG)
  NSAssert(width == renderWidth, @"width mismatch : %d != %d", width, renderWidth);
  NSAssert(height == renderHeight, @"height mismatch : %d != %d", height, renderHeight);
#endif // DEBUG
  
  if (width != renderWidth || height != renderHeight) {
    return FALSE;
  }
  
  // Check dimensions of alpha pixel buffer
  
  if (alphaPixelBuffer != NULL) {
    int alphaWidth = (int) CVPixelBufferGetWidth(alphaPixelBuffer);
    int alphaHeight = (int) CVPixelBufferGetHeight(alphaPixelBuffer);
    
#if defined(DEBUG)
    NSAssert(width == alphaWidth, @"width mismatch between RGB and Alpha buffers : %d != %d", width, alphaWidth);
    NSAssert(height == alphaHeight, @"height mismatch between RGB and Alpha : %d != %d", height, alphaHeight);
#endif // DEBUG
    
    if (width != alphaWidth || height != alphaHeight) {
      return FALSE;
    }
  }
  
  // Verify that the input CoreVideo buffer is explicitly tagged as BT.709
  // video. This module only supports BT.709, so no need to guess.
  
  CFTypeRef matrixKeyAttachment = CVBufferGetAttachment(cvPixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
  
  BOOL supported = (CFStringCompare(matrixKeyAttachment, kCVImageBufferYCbCrMatrix_ITU_R_709_2, 0) == kCFCompareEqualTo);
  
  if (!supported) {
    NSLog(@"unsupported YCbCrMatrix \"%@\", only BT.709 matrix is supported", matrixKeyAttachment);
    return FALSE;
  }
  
  CFTypeRef transferFunctionKeyAttachment = CVBufferGetAttachment(cvPixelBuffer, kCVImageBufferTransferFunctionKey, NULL);
  
  // Require iOS 12 or newer to access kCVImageBufferTransferFunction_sRGB and kCVImageBufferTransferFunction_Linear
  //const NSString *kCVImageBufferTransferFunction_sRGB_str = @"IEC_sRGB";
  //const NSString *kCVImageBufferTransferFunction_Linear_str = @"Linear";
 
  BOOL isBT709Gamma = (CFStringCompare(transferFunctionKeyAttachment, kCVImageBufferTransferFunction_ITU_R_709_2, 0) == kCFCompareEqualTo);
  //BOOL isSRGBGamma = (CFStringCompare(transferFunctionKeyAttachment, (__bridge CFStringRef)kCVImageBufferTransferFunction_sRGB_str, 0) == kCFCompareEqualTo);
  BOOL isSRGBGamma = (CFStringCompare(transferFunctionKeyAttachment, kCVImageBufferTransferFunction_sRGB, 0) == kCFCompareEqualTo);
  //BOOL isLinearGamma = (CFStringCompare(transferFunctionKeyAttachment, (__bridge CFStringRef)kCVImageBufferTransferFunction_Linear_str, 0) == kCFCompareEqualTo);
  BOOL isLinearGamma = (CFStringCompare(transferFunctionKeyAttachment, kCVImageBufferTransferFunction_Linear, 0) == kCFCompareEqualTo);
  
#if defined(DEBUG)
  //NSLog(@"isBT709Gamma %d : isSRGBGamma %d : isSRGBGamma %d", isBT709Gamma, isSRGBGamma, isLinearGamma);
#endif // DEBUG
  
  MetalBT709Gamma gamma = self.gamma;
  
  if (gamma == MetalBT709GammaApple) {
    if (isBT709Gamma == FALSE) {
      NSLog(@"Decoder configured for gamma = MetalBT709GammaApple but TransferFunction was \"%@\"", transferFunctionKeyAttachment);
      return FALSE;
    }
  } else if (gamma == MetalBT709GammaSRGB) {
    if (isSRGBGamma == FALSE) {
      NSLog(@"Decoder configured for gamma = MetalBT709GammaSRGB but TransferFunction was \"%@\"", transferFunctionKeyAttachment);
      return FALSE;
    }
  } else if (gamma == MetalBT709GammaLinear) {
    if (isLinearGamma == FALSE) {
      NSLog(@"Decoder configured for gamma = MetalBT709GammaLinear but TransferFunction was \"%@\"", transferFunctionKeyAttachment);
      return FALSE;
    }
  }
  
  // Alpha channel pixel buffer must be encoded as linear
  
  if (alphaPixelBuffer != NULL) {
    CFTypeRef transferFunctionKeyAttachment = CVBufferGetAttachment(alphaPixelBuffer, kCVImageBufferTransferFunctionKey, NULL);
#if defined(DEBUG)
    assert(transferFunctionKeyAttachment != NULL);
#endif // DEBUG
    BOOL isLinearGamma = (CFStringCompare(transferFunctionKeyAttachment, kCVImageBufferTransferFunction_Linear, 0) == kCFCompareEqualTo);
    
    if (isLinearGamma == FALSE) {
      NSLog(@"Decoder alpha pixel buffer TransferFunction must be linear, it was \"%@\"", transferFunctionKeyAttachment);
      return FALSE;
    }
  }
  
  // Map Metal texture to the CoreVideo pixel buffer
  
  id<MTLTexture> inputYTexture = cvpbu_wrap_y_plane_as_metal_texture(cvPixelBuffer, width, height, _textureCache, 0);
  id<MTLTexture> inputCbCrTexture = cvpbu_wrap_uv_plane_as_metal_texture(cvPixelBuffer, width, height, _textureCache, 1);
  id<MTLTexture> inputAlphaTexture = nil;
  
  if (alphaPixelBuffer != NULL) {
    inputAlphaTexture = cvpbu_wrap_y_plane_as_metal_texture(alphaPixelBuffer, width, height, _textureCache, 0);
  }

  // Dumping contents only needed when DEBUG is explicitly indicated
  
  if (debug) {
    
    NSMutableData *yData = cvpbu_get_y_plane_as_data(cvPixelBuffer, 0);
    NSMutableData *uvData = cvpbu_get_uv_plane_as_data(cvPixelBuffer, 1);
    NSMutableData *aData = nil;
    
    if (alphaPixelBuffer != NULL) {
      cvpbu_get_y_plane_as_data(alphaPixelBuffer, 0);
    }

    // Debug dump Y
    
    if (debug) {
      printf("Y : %d x %d\n", width, height);
      
      uint8_t *yPlanePacked = (uint8_t *) yData.bytes;
      
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
      unsigned int hw = width / 2;
      unsigned int hh = height / 2;
      
      printf("CbCr : %d x %d\n", hw, hh);
      
      uint16_t *cbcrPlanePacked = (uint16_t *) uvData.bytes;
      
      for (int row = 0; row < hh; row++) {
        for (int col = 0; col < hw; col++) {
          int offset = (row * hw) + col;
          uint16_t CbCr = cbcrPlanePacked[offset];
          uint8_t Cb = CbCr & 0xFF;
          uint8_t Cr = (CbCr >> 8) & 0xFF;
          printf("%3d %3d ", Cb, Cr);
        }
        printf("\n");
      }
    }
    
    // Debug dump Alpha channel Y values
    
    if (debug && (alphaPixelBuffer != NULL)) {
      printf("A : %d x %d\n", width, height);
      
      uint8_t *aPlanePacked = (uint8_t *) aData.bytes;
      
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          int offset = (row * width) + col;
          int Y = aPlanePacked[offset];
          printf("%3d ", Y);
        }
        printf("\n");
      }
    }
  }

  // Hold on to texture ref until next render
  self.inputYTexture = inputYTexture;
  self.inputCbCrTexture = inputCbCrTexture;
  self.inputAlphaTexture = inputAlphaTexture;
  
  id<MTLTexture> outputTexture = bgraSRGBTexture;
  
  BOOL worked;
  
  if (self.useComputeRenderer) {
    worked = [self renderWithComputePipeline:outputTexture
                               commandBuffer:commandBuffer];
  } else {
    if (renderPassDescriptor != nil) {
      worked = [self renderWithRenderPipeline:commandBuffer
                         renderPassDescriptor:renderPassDescriptor
                                  renderWidth:renderWidth
                                 renderHeight:renderHeight];
    } else {
      worked = [self renderWithRenderPipeline:outputTexture
                                commandBuffer:commandBuffer];
    }
    
    if (waitUntilCompleted && renderPassDescriptor != nil) {
      // FIXME: would need to present drawable here before
      // calling commit on the commandBuffer
      assert(0);
    }
  }
  
  if (worked == FALSE) {
    // Return FALSE to indicate that render was not successful
    return FALSE;
  }
  
  // Wait for GPU to complete this task
  
  if (waitUntilCompleted) {
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
  }
  
  return TRUE;
}


// Compute kernel based render

- (BOOL) renderWithComputePipeline:(id<MTLTexture>)outputTexture
                     commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
  NSString *label = @"BT709 Compute Render";
  
  // Setup mapping from pixels to threadgroups
  
  const int blockDim = 8;
  
  int width = (int) outputTexture.width;
  int height = (int) outputTexture.height;
  
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
  
  if (computeEncoder != nil) {
    [computeEncoder setComputePipelineState:self.computePipelineState];
    
    computeEncoder.label = label;
    
    // Render YCbCr -> SRGB
    
    [computeEncoder setTexture:self.inputYTexture atIndex:0];
    [computeEncoder setTexture:self.inputCbCrTexture atIndex:1];
    [computeEncoder setTexture:outputTexture atIndex:2];
    
    [computeEncoder dispatchThreadgroups:threadsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
    
    [computeEncoder endEncoding];
    
    return TRUE;
  } else {
    return FALSE;
  }
}

// Fragment shader based render

- (BOOL) renderWithRenderPipeline:(id<MTLTexture>)outputTexture
                    commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
  NSString *label = @"BT709 Render";
  
  id<MTLRenderPipelineState> pipeline = self.renderPipelineState;
  
  // Configure fragment shader render into output texture of the exact same dimensions
  // so that there is no scaling and single (non-linear) pixels are rendered 1 to 1.
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = label;
    
    [renderEncoder pushDebugGroup:label];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:pipeline];
    
    [renderEncoder setVertexBuffer:self.metalRenderContext.identityVerticesBuffer
                            offset:0
                           atIndex:0];
    
    [renderEncoder setFragmentTexture:self.inputYTexture
                              atIndex:0];
    [renderEncoder setFragmentTexture:self.inputCbCrTexture
                              atIndex:1];
    if (self.hasAlphaChannel) {
#if defined(DEBUG)
      NSAssert(self.inputAlphaTexture, @"inputAlphaTexture Metal texture is nil with hasAlphaChannel set to TRUE");
#endif // DEBUG
      [renderEncoder setFragmentTexture:self.inputAlphaTexture
                                atIndex:2];
    }

    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.metalRenderContext.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
    
    return TRUE;
  } else {
    // Return FALSE to indicate that render was not successful
    return FALSE;
  }
}

// Fragment shader based render that output directly into a view
// via an existing MTLRenderPassDescriptor, this optimized
// execution path is only useful when the view to render into
// is exactly the same size at the input texture.
// When the sizes exactly match then no resampling against
// a non-linear texture is done and thus no intermediate
// texture is needed. This render path should be 2x faster.

- (BOOL) renderWithRenderPipeline:(id<MTLCommandBuffer>)commandBuffer
             renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
                      renderWidth:(int)renderWidth
                     renderHeight:(int)renderHeight
{
  NSString *label = @"BT709 Render";
  
  id<MTLRenderPipelineState> pipeline = self.renderPipelineState;
  
  // Configure fragment shader render into output texture of the exact same dimensions
  // so that there is no scaling and single (non-linear) pixels are rendered 1 to 1.
  
  if (renderPassDescriptor != nil)
  {
    id<MTLRenderCommandEncoder> renderEncoder =
      [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = label;
    
    [renderEncoder pushDebugGroup:label];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, renderWidth, renderHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:pipeline];
    
    [renderEncoder setVertexBuffer:self.metalRenderContext.identityVerticesBuffer
                            offset:0
                           atIndex:0];
    
#if defined(DEBUG)
    // This render operation is only legal when the input dimensions
    // exactly match the output dimensions so that there is no resampling
    // of a non-linear input texture. Note that any 2x scaling on an iOS
    // screen does not matter, the pixel width is all that matters.
    
    NSAssert(renderWidth == self.inputYTexture.width, @"render width must exactly match original texture width : %d != %d", renderWidth, (int)self.inputYTexture.width);
    NSAssert(renderHeight == self.inputYTexture.height, @"render height must exactly match original texture height : %d != %d", renderHeight, (int)self.inputYTexture.height);
#endif // DEBUG
    
    [renderEncoder setFragmentTexture:self.inputYTexture
                              atIndex:0];
    [renderEncoder setFragmentTexture:self.inputCbCrTexture
                              atIndex:1];
    if (self.hasAlphaChannel) {
#if defined(DEBUG)
      NSAssert(self.inputAlphaTexture, @"inputAlphaTexture Metal texture is nil with hasAlphaChannel set to TRUE");
#endif // DEBUG
      [renderEncoder setFragmentTexture:self.inputAlphaTexture
                                atIndex:2];
    }
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.metalRenderContext.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
    
    return TRUE;
  } else {
    // Return FALSE to indicate that render was not successful
    return FALSE;
  }
}

@end
