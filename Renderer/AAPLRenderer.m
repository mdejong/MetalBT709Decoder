/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"
#import "MetalBT709Decoder.h"
#import "BGRAToBT709Converter.h"
#import "BGDecodeEncode.h"
#import "CGFrameBuffer.h"

@interface AAPLRenderer ()

@property (nonatomic, retain) MetalBT709Decoder *metalBT709Decoder;

@end

// Main class performing the rendering
@implementation AAPLRenderer
{
  // If set to 1, then instead of async sending to the GPU,
  // the render logic will wait for the GPU render to be completed
  // so that results of the render can be captured. This has performance
  // implications so it should only be enabled when debuging.
  int isCaptureRenderedTextureEnabled;
  
  // The device (aka GPU) we're using to render
  id<MTLDevice> _device;
  
  // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
  id<MTLRenderPipelineState> _pipelineState;
  
  // The command Queue from which we'll obtain command buffers
  id<MTLCommandQueue> _commandQueue;
  
  // Input to sRGB texture render comes from H.264 source
  CVPixelBufferRef _yCbCrPixelBuffer;
  
  // BT.709 render operation must write to an intermediate texture
  // (because mixing non-linear BT.709 input is not legit)
  // that can then be sampled to resize render into the view.
  id<MTLTexture> _resizeTexture;
  
  // The Metal buffer in which we store our vertex data
  id<MTLBuffer> _vertices;
  
  // The number of vertices in our vertex buffer
  NSUInteger _numVertices;
  
  // The current size of our view so we can use this in our render pipeline
  vector_uint2 _viewportSize;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
  self = [super init];
  if(self)
  {
    isCaptureRenderedTextureEnabled = 0;
    
    _device = mtkView.device;
    
    if (isCaptureRenderedTextureEnabled) {
      mtkView.framebufferOnly = false;
    }
    
    // Decode H.264 to CoreVideo pixel buffer
    
    _yCbCrPixelBuffer = [self decodeH264YCbCr];
    //CVPixelBufferRetain(_yCbCrPixelBuffer);
    
    int width = (int) CVPixelBufferGetWidth(_yCbCrPixelBuffer);
    int height = (int) CVPixelBufferGetHeight(_yCbCrPixelBuffer);
    
    // Configure Metal view so that it treats pixels as sRGB values.
    
//#if TARGET_OS_IOS
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
//#endif // TARGET_OS_IOS
    
    {
      // Init render texture that will hold resize render intermediate
      // results. This is typically sRGB, but Mac OSX may not support it.
      
      MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
      
      textureDescriptor.textureType = MTLTextureType2D;
      
      // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
      // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
      
      // FIXME: write to sRGB texture seems to require MacOSX 10.14
#if TARGET_OS_IOS
      textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
#else
      //textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
      // FIXME: Render to 16 bit float intermediate texture to avoid precision loss
      textureDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
#endif // TARGET_OS_IOS
      
      // Set the pixel dimensions of the texture
      textureDescriptor.width = width;
      textureDescriptor.height = height;
      
      textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      
      // Create the texture from the device by using the descriptor
      _resizeTexture = [_device newTextureWithDescriptor:textureDescriptor];
      
      NSAssert(_resizeTexture, @"_resizeTexture");
    }
    
    // Set up a simple MTLBuffer with our vertices which include texture coordinates
    static const AAPLVertex quadVertices[] =
    {
      // Pixel positions, Texture coordinates
      { {  250,  -250 },  { 1.f, 0.f } },
      { { -250,  -250 },  { 0.f, 0.f } },
      { { -250,   250 },  { 0.f, 1.f } },
      
      { {  250,  -250 },  { 1.f, 0.f } },
      { { -250,   250 },  { 0.f, 1.f } },
      { {  250,   250 },  { 1.f, 1.f } },
    };
    
    // Create our vertex buffer, and initialize it with our quadVertices array
    _vertices = [_device newBufferWithBytes:quadVertices
                                     length:sizeof(quadVertices)
                                    options:MTLResourceStorageModeShared];
    
    // Calculate the number of vertices by dividing the byte length by the size of each vertex
    _numVertices = sizeof(quadVertices) / sizeof(AAPLVertex);
    
    /// Create render pipeline
    
    // Create the command queue
    _commandQueue = [_device newCommandQueue];
    
    // Load all the shader files with a .metal file extension in the project
    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
    
    // Init Metal context, this object contains refs to metal objects
    // and util functions.

    MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
    
    mrc.device = _device;
    mrc.defaultLibrary = defaultLibrary;
    mrc.commandQueue = _commandQueue;
    
    // Init metalBT709Decoder with MetalRenderContext set as a property
    
    self.metalBT709Decoder = [[MetalBT709Decoder alloc] init];
    
    self.metalBT709Decoder.metalRenderContext = mrc;

#if TARGET_OS_IOS
    // sRGB texture
    self.metalBT709Decoder.colorPixelFormat = mtkView.colorPixelFormat;
#else
    self.metalBT709Decoder.colorPixelFormat = MTLPixelFormatRGBA16Float;
#endif // TARGET_OS_IOS
    
    //self.metalBT709Decoder.useComputeRenderer = TRUE;
    
    BOOL worked = [self.metalBT709Decoder setupMetal];
    NSAssert(worked, @"worked");
    
    {
      // Load the vertex function from the library
      id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
      
      // Load the fragment function from the library
      id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];
      
      // Set up a descriptor for creating a pipeline state object
      MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
      pipelineStateDescriptor.label = @"Rescale Pipeline";
      pipelineStateDescriptor.vertexFunction = vertexFunction;
      pipelineStateDescriptor.fragmentFunction = fragmentFunction;
      pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
      
      NSError *error = NULL;
      _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                               error:&error];
      if (!_pipelineState)
      {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        //  If the Metal API validation is enabled, we can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode)
        NSLog(@"Failed to created pipeline state, error %@", error);
      }
    }
  }
  
  return self;
}

// Decode a single frame of H.264 video as BT.709 formatted CoreVideo frame.
// Note that the ref count of the returned pixel buffer is 1.

- (CVPixelBufferRef) decodeH264YCbCr
{
  const BOOL debugDumpYCbCr = TRUE;
  
  CVPixelBufferRef cvPixelBufer;
  
  //cvPixelBufer = [self decodeQuicktimeTestPattern];
  //cvPixelBufer = [self decodeSMPTEGray75Perent];
  cvPixelBufer = [self decodeH264YCbCr_bars256];
  //cvPixelBufer = [self decodeH264YCbCr_barsFullscreen];

  if (debugDumpYCbCr) {
    [BGRAToBT709Converter dumpYCBCr:cvPixelBufer];
  }
  
  return cvPixelBufer;
}

// Quicktime test pattern

- (CVPixelBufferRef) decodeQuicktimeTestPattern
{
  NSString *resFilename = @"QuickTime_Test_Pattern_HD.mov";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(1920, 1080)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

// Most simple input, 0.75 SMPTE colorbars, input is linear RGB value (192 192 192)
// which gets decoded to sRGB (225 225 255) from the BT.709 YCbCr (206 128 128)

- (CVPixelBufferRef) decodeSMPTEGray75Perent
{
  NSString *resFilename = @"Gamma_test_HD_75Per_24BPP_sRGB_HD.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(1920, 1080)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

- (CVPixelBufferRef) decodeH264YCbCr_bars256
{
  NSString *resFilename = @"osxcolor_test_image_24bit_BT709.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(256, 256)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

- (CVPixelBufferRef) decodeH264YCbCr_barsFullscreen
{
  NSString *resFilename = @"bars_709_Frame01.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(1920, 1080)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
  BOOL worked;

  // Create a new command buffer for each render pass to the current drawable
  id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  commandBuffer.label = @"BT709 Render";
  
  // Obtain a reference to a sRGB intermediate texture
  
  worked = [self.metalBT709Decoder decodeBT709:_yCbCrPixelBuffer
                      bgraSRGBTexture:_resizeTexture
                        commandBuffer:commandBuffer
                   waitUntilCompleted:FALSE];
#if defined(DEBUG)
  NSAssert(worked, @"decodeBT709 worked");
#endif // DEBUG
  if (!worked) {
    return;
  }

  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
  
  if(renderPassDescriptor != nil)
  {
    // Create a render command encoder so we can render into something
    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"RescaleRender";
    
    // Set the region of the drawable to which we'll draw.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setVertexBytes:&_viewportSize
                           length:sizeof(_viewportSize)
                          atIndex:AAPLVertexInputIndexViewportSize];
    
    // Set the texture object.  The AAPLTextureIndexBaseColor enum value corresponds
    ///  to the 'colorMap' argument in our 'samplingShader' function because its
    //   texture attribute qualifier also uses AAPLTextureIndexBaseColor for its index
    [renderEncoder setFragmentTexture:_resizeTexture
                              atIndex:AAPLTextureIndexBaseColor];
    
    // Draw the vertices of our triangles
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:_numVertices];
    
    [renderEncoder endEncoding];
    
    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:view.currentDrawable];
  }
  
  if (isCaptureRenderedTextureEnabled) {
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    // Wait for the GPU to finish rendering
    [commandBuffer waitUntilCompleted];
  } else {
    [commandBuffer commit];
  }

  // Internal resize texture can only be captured when it is sRGB texture. In the case
  // of MacOSX that makes use a linear 16 bit intermeiate texture, no means to
  // capture the intermediate form aside from another render pass that reads from
  // the intermediate and writes into a lower precision texture.
  
  if (isCaptureRenderedTextureEnabled && (_resizeTexture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB)) {
    // Capture results of intermediate render to same size texture
    
    int width = (int) _resizeTexture.width;
    int height = (int) _resizeTexture.height;
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    // Copy 16 bit floating point values into a tmp buffer
    
    // Copy from texture into framebuffer as BGRA pixels
    
    [_resizeTexture getBytes:(void*)renderedFB.pixels
          bytesPerRow:width*sizeof(uint32_t)
        bytesPerImage:width*height*sizeof(uint32_t)
           fromRegion:MTLRegionMake2D(0, 0, width, height)
          mipmapLevel:0
                slice:0];

    if (_resizeTexture.pixelFormat == MTLPixelFormatBGRA8Unorm) {
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
      renderedFB.colorspace = cs;
      CGColorSpaceRelease(cs);
    }
    
    NSData *pngData = [renderedFB formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:@"DUMP_internal_sRGB_texture.png"];
    BOOL worked = [pngData writeToFile:path atomically:TRUE];
    assert(worked);
    NSLog(@"wrote %@ as %d bytes", path, (int)pngData.length);
  }
  
  if (isCaptureRenderedTextureEnabled) {
    // Capture output of the resize operation, this is a
    // sRGB encoded value.
    
    id<MTLTexture> texture = renderPassDescriptor.colorAttachments[0].texture;
    
    int width = (int) texture.width;
    int height = (int) texture.height;
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
    
    [texture getBytes:(void*)renderedFB.pixels
                 bytesPerRow:width*sizeof(uint32_t)
               bytesPerImage:width*height*sizeof(uint32_t)
                  fromRegion:MTLRegionMake2D(0, 0, width, height)
                 mipmapLevel:0
                       slice:0];
    
    if (1) {
      // Backing texture for the view is sRGB
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      renderedFB.colorspace = cs;
      CGColorSpaceRelease(cs);
    }
    
    NSData *pngData = [renderedFB formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *path = [tmpDir stringByAppendingPathComponent:@"DUMP_resized_texture.png"];
    BOOL worked = [pngData writeToFile:path atomically:TRUE];
    assert(worked);
    NSLog(@"wrote %@ as %d bytes", path, (int)pngData.length);
  }
}

@end
