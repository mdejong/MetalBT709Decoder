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
#import "MetalScaleRenderContext.h"
#import "BGRAToBT709Converter.h"
#import "BGDecodeEncode.h"
#import "CGFrameBuffer.h"
#import "CVPixelBufferUtils.h"

@interface AAPLRenderer ()

@property (nonatomic, retain) MetalBT709Decoder *metalBT709Decoder;

@property (nonatomic, retain) MetalScaleRenderContext *metalScaleRenderContext;

@end

// Define this symbol to enable private texture mode on MacOSX.

//#define STORAGE_MODE_PRIVATE

static inline
void set_storage_mode(MTLTextureDescriptor *textureDescriptor)
{
#if defined(STORAGE_MODE_PRIVATE)
  
#if TARGET_OS_IOS
  // Nop since MTLStorageModeManaged is the default for iOS
#else
  textureDescriptor.storageMode = MTLStorageModePrivate;
#endif // TARGET_OS_IOS
  
#endif // STORAGE_MODE_PRIVATE
}

static inline
void validate_storage_mode(id<MTLTexture> texture)
{
#if defined(STORAGE_MODE_PRIVATE)
  
#if TARGET_OS_IOS
  // Nop
#else
# if defined(DEBUG)
  assert(texture.storageMode == MTLStorageModePrivate);
# endif // DEBUG
#endif // TARGET_OS_IOS
  
#endif // STORAGE_MODE_PRIVATE
}


// Main class performing the rendering
@implementation AAPLRenderer
{
  // If set to 1, then instead of async sending to the GPU,
  // the render logic will wait for the GPU render to be completed
  // so that results of the render can be captured. This has performance
  // implications so it should only be enabled when debuging.
  int isCaptureRenderedTextureEnabled;
  
  // Input to sRGB texture render comes from H.264 source
  CVPixelBufferRef _yCbCrPixelBuffer;
  
  // Secondary Alpha channel texture input
  CVPixelBufferRef _alphaPixelBuffer;
  
  // BT.709 render operation must write to an intermediate texture
  // (because mixing non-linear BT.709 input is not legit)
  // that can then be sampled to resize render into the view.
  id<MTLTexture> _resizeTexture;
  
  // The current size of our view so we can use this in our render pipeline
  vector_uint2 _viewportSize;
  
  // non-zero when writing to a sRGB texture is possible, certain versions
  // of MacOSX do not support sRGB texture write operations.
  int hasWriteSRGBTextureSupport;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
  self = [super init];
  if(self)
  {
    isCaptureRenderedTextureEnabled = 0;
    
    id<MTLDevice> device = mtkView.device;
    
    if (isCaptureRenderedTextureEnabled) {
      mtkView.framebufferOnly = false;
    }
    
    // Init Metal context, this object contains refs to metal objects
    // and util functions.
    
    MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
    
    mrc.device = device;
    mrc.defaultLibrary = [device newDefaultLibrary];
    mrc.commandQueue = [device newCommandQueue];
    
    // Decode H.264 to CoreVideo pixel buffer
    
    _yCbCrPixelBuffer = [self decodeH264YCbCr];
    //CVPixelBufferRetain(_yCbCrPixelBuffer);
    
    int width = (int) CVPixelBufferGetWidth(_yCbCrPixelBuffer);
    int height = (int) CVPixelBufferGetHeight(_yCbCrPixelBuffer);
    
    // Configure Metal view so that it treats pixels as sRGB values.
    
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    
    {
      // Init render texture that will hold resize render intermediate
      // results. This is typically sRGB, but Mac OSX may not support it.
      
      MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
      
      textureDescriptor.textureType = MTLTextureType2D;
      
      // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
      // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0) as sRGB

#if TARGET_OS_IOS
      hasWriteSRGBTextureSupport = 1;
#else
      // MacOSX 10.14 or newer needed to support sRGB texture writes
      
      NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
      
      if (version.majorVersion >= 10 && version.minorVersion >= 14) {
        // Supports sRGB texture write feature.
        hasWriteSRGBTextureSupport = 1;
      } else {
        hasWriteSRGBTextureSupport = 0;
      }
      
      // Force 16 bit float texture to be used (about 2x slower for IO bound shader)
      //hasWriteSRGBTextureSupport = 0;
#endif // TARGET_OS_IOS
      
#if TARGET_OS_IOS
      textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
#else
      // MacOSX
      if (hasWriteSRGBTextureSupport) {
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
      } else {
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
      }
#endif // TARGET_OS_IOS
      
      // Set the pixel dimensions of the texture
      textureDescriptor.width = width;
      textureDescriptor.height = height;
      
      textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      
      // Create the texture from the device by using the descriptor,
      // note that GPU private storage mode is the default for
      // newTextureWithDescriptor, this is just here to make that clear.
      
      set_storage_mode(textureDescriptor);
      
      _resizeTexture = [device newTextureWithDescriptor:textureDescriptor];
      
      NSAssert(_resizeTexture, @"_resizeTexture");
      
      validate_storage_mode(_resizeTexture);
      
      // Debug print size of intermediate render texture
      
# if defined(DEBUG)
      {
        int numBytesPerPixel;
        
        if (hasWriteSRGBTextureSupport) {
          numBytesPerPixel = 4;
        } else {
          numBytesPerPixel = 8;
        }
        
        int numBytes = (int) (width * height * numBytesPerPixel);
        
        printf("intermediate render texture num bytes %d kB : %.2f mB\n", (int)(numBytes / 1000), numBytes / 1000000.0f);
      }
# endif // DEBUG
    }
    
    // Init metalBT709Decoder with MetalRenderContext set as a property
    
    self.metalBT709Decoder = [[MetalBT709Decoder alloc] init];
    
    self.metalBT709Decoder.metalRenderContext = mrc;

#if TARGET_OS_IOS
    // sRGB texture
    self.metalBT709Decoder.colorPixelFormat = mtkView.colorPixelFormat;
#else
    if (hasWriteSRGBTextureSupport) {
      self.metalBT709Decoder.colorPixelFormat = mtkView.colorPixelFormat;
    } else {
      self.metalBT709Decoder.colorPixelFormat = MTLPixelFormatRGBA16Float;
    }
#endif // TARGET_OS_IOS
    
    //self.metalBT709Decoder.useComputeRenderer = TRUE;

    // Process 32BPP input, a CoreVideo pixel buffer is modified so that
    // an additional channel for Y is retained.
    self.metalBT709Decoder.hasAlphaChannel = TRUE;
    
    if (self.metalBT709Decoder.hasAlphaChannel) {
      mtkView.opaque = FALSE;
    } else {
      mtkView.opaque = TRUE;
    }
    
    MetalBT709Gamma decodeGamma = MetalBT709GammaApple;
    
    if ((1)) {
      // Explicitly set gamma to sRGB
      decodeGamma = MetalBT709GammaSRGB;
    } else if ((0)) {
      decodeGamma = MetalBT709GammaLinear;
    }

    self.metalBT709Decoder.gamma = decodeGamma;
    
    BOOL worked = [self.metalBT709Decoder setupMetal];
    worked = worked;
    NSAssert(worked, @"worked");
    
    // Scale render is used to blit and rescale from the 709
    // BGRA pixels into the MTKView. Note that in the special
    // case where no rescale operation is needed then the 709
    // decoder will render directly into the view.
    
    MetalScaleRenderContext *metalScaleRenderContext = [[MetalScaleRenderContext alloc] init];
    
    [metalScaleRenderContext setupRenderPipelines:mrc mtkView:mtkView];
    
    self.metalScaleRenderContext = metalScaleRenderContext;
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
  //cvPixelBufer = [self decodeH264YCbCr_bars256];
  //cvPixelBufer = [self decodeH264YCbCr_bars_iPadFullScreen];
  //cvPixelBufer = [self decodeH264YCbCr_barsFullscreen];
  //cvPixelBufer = [self decodeCloudsiPadImage];
  //cvPixelBufer = [self decodeTest709Frame];
  //cvPixelBufer = [self decodeDropOfWater];
  //cvPixelBufer = [self decodeBigBuckBunny];
  //cvPixelBufer = [self decodeQuicktimeTestPatternLinearGrayscale];

  // RGB + Alpha images
  //cvPixelBufer = [self decodeRedFadeAlpha];
  cvPixelBufer = [self decodeGlobeAlpha];
  
  if (debugDumpYCbCr) {
    [BGRAToBT709Converter dumpYCBCr:cvPixelBufer];
  }
  
  return cvPixelBufer;
}

// Rec 709 encoded frame that shows skin tones

- (CVPixelBufferRef) decodeTest709Frame
{
  NSString *resFilename = @"Rec709Sample.mp4";
  
  // (1920, 1080)
  
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

// iPad full screen size high def image

- (CVPixelBufferRef) decodeCloudsiPadImage
{
  NSString *resFilename = @"clouds_reflecting_off_the_beach-wallpaper-2048x1536.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(2048, 1536)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
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

// Grayscale linear gamma version of Quicktime test pattern

- (CVPixelBufferRef) decodeQuicktimeTestPatternLinearGrayscale
{
  NSString *resFilename = @"QuickTime_Test_Pattern_HD_grayscale.m4v";
  
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

- (CVPixelBufferRef) decodeH264YCbCr_bars_iPadFullScreen
{
  NSString *resFilename = @"osxcolor_test_image_iPad_2048_1536.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(2048, 1536)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

- (CVPixelBufferRef) decodeDropOfWater
{
  //NSString *resFilename = @"drop-of-water-iPad-2048-1536-apple-crf20.m4v";
  NSString *resFilename = @"drop-of-water-iPad-2048-1536-sRGB-crf20.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(2048, 1536)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

- (CVPixelBufferRef) decodeBigBuckBunny
{
  NSString *resFilename = @"big_buck_bunny_HD_apple.m4v";
  //NSString *resFilename = @"big_buck_bunny_HD_srgb.m4v";
  
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

- (CVPixelBufferRef) decodeRedFadeAlpha
{
  NSString *resFilename = @"RedFadeAlpha256.m4v";
  
  int width = 256;
  int height = 256;
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(width, height)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  // FIXME: Read CoreVideo pixel bufer from _alpha input source and then create a single
  // CoreVideo container that is able to represent all 4 channels of input data in
  // a single ref. Another option would be to use 2 CoreVideo buffers but mark
  // the second texture and a single 8 bit input, this would require a copy operation
  // for the Alpha channel but it would mean the extra memory for the CbCr in the
  // second video would not need to be retained.
  
  if ((1)) {
    NSString *resFilename = @"RedFadeAlpha256_alpha.m4v";
    
    NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                      frameDuration:1.0/30
                                                                         renderSize:CGSizeMake(width, height)
                                                                         aveBitrate:0];
    NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
    
    CVPixelBufferRef cvPixelBufferAlphaIn = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
    
    const int makeCopyToReduceMemoryUsage = 0;
    
    if (makeCopyToReduceMemoryUsage) {
      // Create a CoreVideo pixel buffer that features a Y channel but no UV
      // channel. This reduces runtime memory usage at the cost of a copy.
      
      CVPixelBufferRef cvPixelBufferAlphaOut = [BGRAToBT709Converter createCoreVideoYBuffer:CGSizeMake(width, height)];
      
      cvpbu_copy_plane(cvPixelBufferAlphaIn, cvPixelBufferAlphaOut, 0);
      
      // Note that only the kCVImageBufferTransferFunctionKey property is set here, this
      // special purpose Alpha channel buffer cannot be converted from YCbCr to RGB.
      // This linear check is here so that the reduced memory use pixel buffer will
      // pass the same validation as the original encoded with ffmpeg.
      
      NSDictionary *pbAttachments = @{
                                      //(__bridge NSString*)kCVImageBufferYCbCrMatrixKey: (__bridge NSString*)kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                                      //(__bridge NSString*)kCVImageBufferColorPrimariesKey: (__bridge NSString*)kCVImageBufferColorPrimaries_ITU_R_709_2,
                                      (__bridge NSString*)kCVImageBufferTransferFunctionKey: (__bridge NSString*)kCVImageBufferTransferFunction_Linear,
                                      };
      
      CVBufferSetAttachments(cvPixelBufferAlphaOut, (__bridge CFDictionaryRef)pbAttachments, kCVAttachmentMode_ShouldPropagate);
      
      self->_alphaPixelBuffer = cvPixelBufferAlphaOut;
    } else {
      CVPixelBufferRetain(cvPixelBufferAlphaIn);
      self->_alphaPixelBuffer = cvPixelBufferAlphaIn;
    }
  }
  
  // FIXME: Need a way to hold on to these 2 CoreVideo pixel buffers, if the
  // buffers will be used and released right away then no need to copy.
  
  return cvPixelBuffer;
}

- (CVPixelBufferRef) decodeGlobeAlpha
{
  NSString *resFilename = @"GlobeLEDAlpha.m4v";
  
  int width = 1920;
  int height = 1080;
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(width, height)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  // FIXME: Read CoreVideo pixel bufer from _alpha input source and then create a single
  // CoreVideo container that is able to represent all 4 channels of input data in
  // a single ref. Another option would be to use 2 CoreVideo buffers but mark
  // the second texture and a single 8 bit input, this would require a copy operation
  // for the Alpha channel but it would mean the extra memory for the CbCr in the
  // second video would not need to be retained.
  
  if ((1)) {
    NSString *resFilename = @"GlobeLEDAlpha_alpha.m4v";
    
    NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                      frameDuration:1.0/30
                                                                         renderSize:CGSizeMake(width, height)
                                                                         aveBitrate:0];
    NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
    
    CVPixelBufferRef cvPixelBufferAlphaIn = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
    
    const int makeCopyToReduceMemoryUsage = 0;
    
    if (makeCopyToReduceMemoryUsage) {
      // Create a CoreVideo pixel buffer that features a Y channel but no UV
      // channel. This reduces runtime memory usage at the cost of a copy.
      
      CVPixelBufferRef cvPixelBufferAlphaOut = [BGRAToBT709Converter createCoreVideoYBuffer:CGSizeMake(width, height)];
      
      cvpbu_copy_plane(cvPixelBufferAlphaIn, cvPixelBufferAlphaOut, 0);
      
      // Note that only the kCVImageBufferTransferFunctionKey property is set here, this
      // special purpose Alpha channel buffer cannot be converted from YCbCr to RGB.
      // This linear check is here so that the reduced memory use pixel buffer will
      // pass the same validation as the original encoded with ffmpeg.
      
      NSDictionary *pbAttachments = @{
                                      //(__bridge NSString*)kCVImageBufferYCbCrMatrixKey: (__bridge NSString*)kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                                      //(__bridge NSString*)kCVImageBufferColorPrimariesKey: (__bridge NSString*)kCVImageBufferColorPrimaries_ITU_R_709_2,
                                      (__bridge NSString*)kCVImageBufferTransferFunctionKey: (__bridge NSString*)kCVImageBufferTransferFunction_Linear,
                                      };
      
      CVBufferSetAttachments(cvPixelBufferAlphaOut, (__bridge CFDictionaryRef)pbAttachments, kCVAttachmentMode_ShouldPropagate);
      
      self->_alphaPixelBuffer = cvPixelBufferAlphaOut;
    } else {
      CVPixelBufferRetain(cvPixelBufferAlphaIn);
      self->_alphaPixelBuffer = cvPixelBufferAlphaIn;
    }
  }
  
  // FIXME: Need a way to hold on to these 2 CoreVideo pixel buffers, if the
  // buffers will be used and released right away then no need to copy.
  
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

  MetalBT709Decoder *metalBT709Decoder = self.metalBT709Decoder;
  MetalRenderContext *mrc = metalBT709Decoder.metalRenderContext;
  
  // Create a new command buffer for each render pass to the current drawable
  id<MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  commandBuffer.label = @"BT709 Render";
  
  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
  
  int renderWidth = (int) _viewportSize.x;
  int renderHeight = (int) _viewportSize.y;
  
  BOOL isExactlySameSize =
  (renderWidth == ((int)CVPixelBufferGetWidth(_yCbCrPixelBuffer))) &&
  (renderHeight == ((int)CVPixelBufferGetHeight(_yCbCrPixelBuffer))) &&
  (renderPassDescriptor != nil);

  if ((0)) {
    // Phony up exact match results just for testing purposes, this
    // would generate slightly wrong non-linear resample results
    // if the dimensions do not exactly match.
    isExactlySameSize = 1;
    renderWidth = (int)CVPixelBufferGetWidth(_yCbCrPixelBuffer);
    renderHeight = (int)CVPixelBufferGetHeight(_yCbCrPixelBuffer);
  }
  
  if (isExactlySameSize) {
    if (isCaptureRenderedTextureEnabled) {
      // Debug render into the intermediate texture when capture is
      // enabled to determine if there is any difference between
      // rendering into a texture and rendering into the view.
      
      int renderWidth = (int) _resizeTexture.width;
      int renderHeight = (int) _resizeTexture.height;
      
      [metalBT709Decoder decodeBT709:_yCbCrPixelBuffer
                    alphaPixelBuffer:_alphaPixelBuffer
                     bgraSRGBTexture:_resizeTexture
                       commandBuffer:commandBuffer
                renderPassDescriptor:nil
                         renderWidth:renderWidth
                        renderHeight:renderHeight
                  waitUntilCompleted:FALSE];
    }
    
    // Render directly into the view, this optimization reduces IO
    // and results in a significant performance improvement.

    worked = [metalBT709Decoder decodeBT709:_yCbCrPixelBuffer
                           alphaPixelBuffer:_alphaPixelBuffer
                            bgraSRGBTexture:nil
                              commandBuffer:commandBuffer
                       renderPassDescriptor:renderPassDescriptor
                                renderWidth:renderWidth
                               renderHeight:renderHeight
                         waitUntilCompleted:FALSE];

    if (worked) {
      // Schedule a present once the framebuffer is complete using the current drawable
      [commandBuffer presentDrawable:view.currentDrawable];
    }
  } else {
    // Viewport dimensions do not exactly match the input texture
    // dimensions, so a 2 pass render operation with an
    // intermediate texture is required.
    
    if (renderPassDescriptor != nil)
    {
      int renderWidth = (int) _resizeTexture.width;
      int renderHeight = (int) _resizeTexture.height;
      
      worked = [metalBT709Decoder decodeBT709:_yCbCrPixelBuffer
                             alphaPixelBuffer:_alphaPixelBuffer
                              bgraSRGBTexture:_resizeTexture
                                commandBuffer:commandBuffer
                         renderPassDescriptor:nil
                                  renderWidth:renderWidth
                                 renderHeight:renderHeight
                           waitUntilCompleted:FALSE];

#if defined(DEBUG)
      NSAssert(worked, @"decodeBT709 worked");
#endif // DEBUG
      if (!worked) {
        return;
      }
    }
    
    // Invoke scaling operation to fit the intermediate buffer
    // into the current width and height of the viewport.
    
    [self.metalScaleRenderContext renderScaled:mrc
                                       mtkView:view
                                   renderWidth:renderWidth
                                  renderHeight:renderHeight
                                 commandBuffer:commandBuffer
                          renderPassDescriptor:renderPassDescriptor
                                   bgraTexture:_resizeTexture];
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
    
    int bpp = 24;
    if (self.metalBT709Decoder.hasAlphaChannel == TRUE) {
      // 32 BPP
      bpp = 32;
    }
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
    
    // Copy from texture into framebuffer as BGRA pixels
    
    [_resizeTexture getBytes:(void*)renderedFB.pixels
          bytesPerRow:width*sizeof(uint32_t)
        bytesPerImage:width*height*sizeof(uint32_t)
           fromRegion:MTLRegionMake2D(0, 0, width, height)
          mipmapLevel:0
                slice:0];

    if (1) {
      // texture is sRGB
      CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
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
    // Capture output of the resize operation as sRGB pixels
    
    id<MTLTexture> texture = renderPassDescriptor.colorAttachments[0].texture;
    
    int width = (int) texture.width;
    int height = (int) texture.height;
    
    int bpp = 24;
    if (self.metalBT709Decoder.hasAlphaChannel == TRUE) {
      // 32 BPP
      bpp = 32;
    }
    
    CGFrameBuffer *renderedFB = [CGFrameBuffer cGFrameBufferWithBppDimensions:bpp width:width height:height];
    
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
