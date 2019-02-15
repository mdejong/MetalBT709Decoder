//
//  MetalScaleRenderContext.h
//
//  Copyright 2019 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This module will render into an existing MTKView
//  in the case where a 2D rescale operation is needed
//  to fit the contents of a Metal texture into a view.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@class MetalRenderContext;

@interface MetalScaleRenderContext : NSObject

// Name of fragment shader function

@property (nonatomic, copy) NSString *fragmentFunction;

// fragment pipeline

@property (nonatomic, retain) id<MTLRenderPipelineState> pipelineState;

// Setup render pixpeline to render into the given view.

- (void) setupRenderPipelines:(MetalRenderContext*)mrc
                      mtkView:(MTKView*)mtkView;

// Render into MTKView with 2D scale operation

- (void) renderScaled:(MetalRenderContext*)mrc
              mtkView:(nonnull MTKView *)mtkView
          renderWidth:(int)renderWidth
         renderHeight:(int)renderHeight
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
 renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
          bgraTexture:(id<MTLTexture>)bgraTexture;

@end
