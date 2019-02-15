//
//  MetalScaleRenderContext.m
//
//  Copyright 2019 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This module will render into an existing MTKView
//  in the case where a 2D rescale operation is needed
//  to fit the contents of a Metal texture into a view.

#include "MetalScaleRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"

// Private API

@interface MetalScaleRenderContext ()

@end

// Main class performing the rendering
@implementation MetalScaleRenderContext

// Setup render pixpelines

- (void) setupRenderPipelines:(MetalRenderContext*)mrc
                             mtkView:(MTKView*)mtkView
{
  NSString *shader = self.fragmentFunction;
    
  if (shader == nil) {
    shader = @"samplingShader";
  }

  // Render from BGRA where 4 grayscale values are packed into
  // each pixel into BGRA pixels that are expanded to grayscale
  // and cropped to the original image dimensions.
  
  self.pipelineState = [mrc makePipeline:mtkView.colorPixelFormat
                               pipelineLabel:@"Rescale Pipeline"
                              numAttachments:1
                          vertexFunctionName:@"identityVertexShader"
                        fragmentFunctionName:shader];

  NSAssert(self.pipelineState, @"pipelineState");
}

// Render into MTKView with 2D scale operation

- (void) renderScaled:(MetalRenderContext*)mrc
              mtkView:(nonnull MTKView *)mtkView
          renderWidth:(int)renderWidth
         renderHeight:(int)renderHeight
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
 renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
          bgraTexture:(id<MTLTexture>)bgraTexture
{
#if defined(DEBUG)
  assert(mtkView);
  assert(renderWidth > 0);
  assert(renderHeight > 0);
  assert(mrc);
  assert(commandBuffer);
  assert(bgraTexture);
#endif // DEBUG
  
  if (renderPassDescriptor != nil)
  {
    // Create a render command encoder so we can render into something
    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"RescaleRender";
    
    // Set the region of the drawable to which we'll draw.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, renderWidth, renderHeight, -1.0, 1.0 }];
    
    id<MTLRenderPipelineState> pipeline = self.pipelineState;
    [renderEncoder setRenderPipelineState:pipeline];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:0];
    
    // Set the texture object.  The AAPLTextureIndexBaseColor enum value corresponds
    ///  to the 'colorMap' argument in our 'samplingShader' function because its
    //   texture attribute qualifier also uses AAPLTextureIndexBaseColor for its index
    [renderEncoder setFragmentTexture:bgraTexture
                              atIndex:AAPLTextureIndexBaseColor];
    
    // Draw the vertices of our triangles
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:mrc.identityNumVertices];
    
    [renderEncoder endEncoding];
    
    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:mtkView.currentDrawable];
  }
}

@end
