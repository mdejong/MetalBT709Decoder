//
//  H264Encoder.h
//
//  Created by Mo DeJong on 7/6/16.
//
//  See license.txt for BSD license terms.
//
//  This module wraps AVFoundation APIs so that a H264 video can
//  be created from CoreGraphics refrences to image data. The
//  interface defines a callback that is invoked each time the
//  encoder is redy to write a frame of data to the output thread.
//  All processing is done on a background thread, the main thread
//  is not blocked at any time. Note that any error reporting is
//  handled by invoking H264EncoderResult to report an error
//  on the main thread.

@import Foundation;
@import AVFoundation;
@import CoreVideo;
@import CoreImage;
@import CoreMedia;
@import VideoToolbox;

typedef enum
{
  H264EncoderErrorCodeSuccess = 0,
  H264EncoderErrorCodeNoFrameSource = 1,
  H264EncoderErrorCodeSessionNotStarted = 2,
} H264EncoderErrorCode;

@protocol H264EncoderFrameSource

// Given a frame number in the range (0, N-1), return a CoreGraphics
// image reference to the corresponding image to be written to
// the encoded file.

- (CGImageRef) imageForFrame:(int)frameNum;

// Return TRUE if more frames can be returned by this frame source,
// returning FALSE means that all frames have been encoded.

- (BOOL) hasMoreFrames;

@end

// Implement this protocol to async report the results of an encoding
// operation on a background thread.

@protocol H264EncoderResult

// Given a frame number in the range (0, N-1), return a CoreGraphics
// image reference to the corresponding image to be written to
// the encoded file. The code is zero = H264EncoderErrorCodeSuccess
// on success, otherwise an error code indicates wht went wrong.

- (void) encoderResult:(H264EncoderErrorCode)code;

@end

// H264Encoder class

@interface H264Encoder : NSObject

// Reference to a H264EncoderFrameSource protocol implementation,
// this must be set to a non-nil value before encoding.

@property (nonatomic, assign) id<H264EncoderFrameSource> frameSource;

// Reference to a H264EncoderResult, this must be set to a non-nil
// value before encoding.

@property (nonatomic, assign) id<H264EncoderResult> encoderResult;

// This property is FALSE once encoding has started, when encoding is finished
// with either a success or error status then this property is set to TRUE.
// Note that this property is thread safe as it can be accessed from different threads.

@property (atomic, assign) BOOL finished;

// Block the calling thread until encoding is finished

- (void) blockUntilFinished;

// convert error code to string

+ (NSString*) ErrorCodeToString:(H264EncoderErrorCode)code;

// constructor

+ (H264Encoder*) h264Encoder;

// Invoke this method to start a background thread that will encode
// incoming frames of images and write the result to a H264 file.
// Note that if there are any error conditions, the encoderResult
// protocol callback is invoked to report the error condition.

- (void) encodeframes:(NSString*)outH264Path
        frameDuration:(float)frameDuration
           renderSize:(CGSize)renderSize
           aveBitrate:(int)aveBitrate;

@end
