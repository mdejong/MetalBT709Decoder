//
//  CVPixelBufferUtils.h
//
//  Created by Moses DeJong on 12/14/18.
//
//  Utility functions for CoreVideo pixel buffers.
//
//  Licensed under BSD terms.

#if !defined(_CVPixelBufferUtils_H)
#define _CVPixelBufferUtils_H

// Copy the contents of a specific plane from src to dst, this
// method is optimized so that memcpy() operations will copy
// either the whole buffer if possible otherwise or a row at a time.

static inline
void cvpbu_copy_plane(CVPixelBufferRef src, CVPixelBufferRef dst, int plane) {
  int width = (int) CVPixelBufferGetWidth(dst);
  int height = (int) CVPixelBufferGetHeight(dst);
  
  // Copy Y values from cvPixelBufferAlphaIn to cvPixelBufferAlphaOut
  
  {
    int status = CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    assert(status == kCVReturnSuccess);
  }
  
  {
    int status = CVPixelBufferLockBaseAddress(dst, 0);
    assert(status == kCVReturnSuccess);
  }
  
  uint8_t *yInPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(src, plane);
  assert(yInPlane);
  const size_t yInBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(src, plane);
  
  uint8_t *yOutPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(dst, plane);
  assert(yOutPlane);
  const size_t yOutBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dst, plane);
  
  if (yInBytesPerRow == yOutBytesPerRow) {
    memcpy(yOutPlane, yInPlane, yInBytesPerRow * height);
  } else {
    for (int row = 0; row < height; row++) {
      uint8_t *rowInPtr = yInPlane + (row * yInBytesPerRow);
      uint8_t *rowOutPtr = yOutPlane + (row * yOutBytesPerRow);
#if defined(DEBUG)
      assert(width <= yOutBytesPerRow);
#endif // DEBUG
      memcpy(rowOutPtr, rowInPtr, width);
    }
  }
  
  if ((0)) {
    for (int row = 0; row < height; row++) {
      uint8_t *rowOutPtr = yOutPlane + (row * yOutBytesPerRow);
      for (int col = 0; col < width; col++) {
        uint8_t bVal = rowOutPtr[col];
        printf("%d ", bVal);
      }
    }
  }
  
  {
    int status = CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    assert(status == kCVReturnSuccess);
  }
  
  {
    int status = CVPixelBufferUnlockBaseAddress(dst, 0);
    assert(status == kCVReturnSuccess);
  }
}

// Wrap a CV pixel buffer plane up as a Metal texture, the plane number
// indicates which plane will be wrapped. The format of the pixels
// is assumed to be a single byte value that will be referenced as a float.

static inline
id<MTLTexture> cvpbu_wrap_y_plane_as_metal_texture(CVPixelBufferRef cvPixelBuffer,
                                                   int width,
                                                   int height,
                                                   CVMetalTextureCacheRef textureCache,
                                                   int plane)
{
  id<MTLTexture> inputTexture = nil;
  
  CVMetalTextureRef textureWrapperRef = NULL;
  
  CVReturn ret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           textureCache,
                                                           cvPixelBuffer,
                                                           nil, // textureAttributes
                                                           MTLPixelFormatR8Unorm,
                                                           width,
                                                           height,
                                                           plane,
                                                           &textureWrapperRef);
  
#if defined(DEBUG)
  assert(ret == kCVReturnSuccess && textureWrapperRef != NULL);
#endif // DEBUG
  
  if (ret != kCVReturnSuccess || textureWrapperRef == NULL) {
    return FALSE;
  }
  
  inputTexture = CVMetalTextureGetTexture(textureWrapperRef);
  
  CFRelease(textureWrapperRef);

  return inputTexture;
}

static inline
id<MTLTexture> cvpbu_wrap_uv_plane_as_metal_texture(CVPixelBufferRef cvPixelBuffer,
                                                   unsigned int width,
                                                   unsigned int height,
                                                   CVMetalTextureCacheRef textureCache,
                                                   int plane)
{
  unsigned int hw = width >> 1;
  unsigned int hh = height >> 1;
  
  id<MTLTexture> inputTexture = nil;
  
  CVMetalTextureRef textureWrapperRef = NULL;
  
  CVReturn ret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           textureCache,
                                                           cvPixelBuffer,
                                                           nil, // textureAttributes
                                                           MTLPixelFormatRG8Unorm,
                                                           hw,
                                                           hh,
                                                           plane,
                                                           &textureWrapperRef);
  
#if defined(DEBUG)
  assert(ret == kCVReturnSuccess && textureWrapperRef != NULL);
#endif // DEBUG
  
  if (ret != kCVReturnSuccess || textureWrapperRef == NULL) {
    return FALSE;
  }
  
  inputTexture = CVMetalTextureGetTexture(textureWrapperRef);
  
  CFRelease(textureWrapperRef);
  
  return inputTexture;
}

// Grab the contents of a Y (byte) plane inside a CoreVideo pixel buffer
// and copy the byte values into a NSData object. This method is
// intended to be used for debug purposes and so it does not need
// to be efficient. This method will lock and then unlock the buffer.

static inline
NSMutableData* cvpbu_get_y_plane_as_data(CVPixelBufferRef cvPixelBuffer, int plane)
{
  int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  NSMutableData *mData = [NSMutableData dataWithLength:width*height*sizeof(uint8_t)];
  
  {
    int status = CVPixelBufferLockBaseAddress(cvPixelBuffer, 0);
    assert(status == kCVReturnSuccess);
  }
  
  uint8_t *yPlane = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, plane);
  size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, plane);
  
  uint8_t *yPlanePacked = (uint8_t *) mData.bytes;
  
  for (int row = 0; row < height; row++) {
    uint8_t *inRowPtr = yPlane + (row * yBytesPerRow);
    uint8_t *outRowPtr = yPlanePacked + (row * (width * sizeof(uint8_t)));
    
    for (int col = 0; col < width; col++) {
      int Y = inRowPtr[col];
      outRowPtr[col] = Y;
    }
  }

  {
    int status = CVPixelBufferUnlockBaseAddress(cvPixelBuffer, 0);
    assert(status == kCVReturnSuccess);
  }
  
  return mData;
}

static inline
NSMutableData* cvpbu_get_uv_plane_as_data(CVPixelBufferRef cvPixelBuffer, int plane)
{
  unsigned int width = (int) CVPixelBufferGetWidth(cvPixelBuffer);
  unsigned int height = (int) CVPixelBufferGetHeight(cvPixelBuffer);
  
  unsigned int hw = width >> 1;
  unsigned int hh = height >> 1;
  
  NSMutableData *mData = [NSMutableData dataWithLength:hw*hh*sizeof(uint16_t)];
  
  {
    int status = CVPixelBufferLockBaseAddress(cvPixelBuffer, 0);
    assert(status == kCVReturnSuccess);
  }
  
  uint16_t *cbcrPlane = (uint16_t *) CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, plane);
  size_t cbcrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(cvPixelBuffer, plane);
  const size_t cbcrPixelsPerRow = cbcrBytesPerRow / sizeof(uint16_t);
  
  uint16_t *cbcrPlanePacked = (uint16_t *) mData.bytes;
  
  for (int row = 0; row < hh; row++) {
    uint16_t *inRowPtr = cbcrPlane + (row * cbcrPixelsPerRow);
    uint16_t *outRowPtr = cbcrPlanePacked + (row * hw);
    
    for (int col = 0; col < hw; col++) {
      uint16_t uv = inRowPtr[col];
      outRowPtr[col] = uv;
    }
  }

  {
    int status = CVPixelBufferUnlockBaseAddress(cvPixelBuffer, 0);
    assert(status == kCVReturnSuccess);
  }
  
  return mData;
}

#endif // _CVPixelBufferUtils_H
