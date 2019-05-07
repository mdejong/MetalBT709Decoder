//
//  y4m_writer.h
//
//  Created by Moses DeJong on 12/14/18.
//
//  Header only interface that supports writing
//  a Y4M file that contains tagged YUV bytes
//  in 4:2:0 format.
//
//  Licensed under BSD terms.

#if !defined(_Y4M_WRITER_H)
#define _Y4M_WRITER_H

#include <stdio.h>

typedef enum {
  Y4MHeaderFPS_1,
  Y4MHeaderFPS_15,
  Y4MHeaderFPS_24,
  Y4MHeaderFPS_25,
  Y4MHeaderFPS_29_97,
  Y4MHeaderFPS_30,
  Y4MHeaderFPS_60
} Y4MHeaderFPS;

typedef struct {
  int width;
  int height;
  Y4MHeaderFPS fps;
} Y4MHeaderStruct;

// Emit a single frame to the output Y4M file.

typedef struct {
  uint8_t *yPtr;
  int yLen;
  
  uint8_t *uPtr;
  int uLen;
  
  uint8_t *vPtr;
  int vLen;
} Y4MFrameStruct;

// Open output Y4M file descriptor with binary setting

static inline
FILE* y4m_open_file(const char *outFilePath) {
  FILE *outFile = fopen(outFilePath, "wb");
  
  if (outFile == NULL) {
    fprintf(stderr, "could not open output Y4M file \"%s\"\n", outFilePath);
  }

  return outFile;
}

// Emit header given the options indicated in header

static inline
int y4m_write_header(FILE *outFile, Y4MHeaderStruct *hsPtr) {
  {
    char *segment = "YUV4MPEG2 ";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  {
    int width = hsPtr->width;
    NSString *formatted = [NSString stringWithFormat:@"W%d ", width];
    char *segment = (char*) [formatted UTF8String];
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  {
    int height = hsPtr->height;
    NSString *formatted = [NSString stringWithFormat:@"H%d ", height];
    char *segment = (char*) [formatted UTF8String];
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // Framerate :
  // 'F30:1' = 30 FPS
  // 'F30000:1001' = 29.97 FPS
  // '1:1' = 1 FPS
  
  {
    //char *segment = "F30:1 ";
    char *segment;
    
    switch (hsPtr->fps) {
      case Y4MHeaderFPS_1: {
        segment = "F1:1 ";
        break;
      }
      case Y4MHeaderFPS_15: {
        segment = "F15:1 ";
        break;
      }
      case Y4MHeaderFPS_24: {
        segment = "F24:1 ";
        break;
      }
      case Y4MHeaderFPS_25: {
        segment = "F25:1 ";
        break;
      }
      case Y4MHeaderFPS_29_97: {
        // 29.97 standard video rate
        segment = "F30000:1001 ";
        break;
      }
      case Y4MHeaderFPS_30: {
        segment = "F30:1 ";
        break;
      }
      case Y4MHeaderFPS_60: {
        segment = "F60:1 ";
        break;
      }
      default: {
        assert(0);
        return 3;
        break;
      }
    }
    
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // interlacing progressive
  
  {
    char *segment = "Ip ";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // Pixel aspect ratio
  
  {
    char *segment = "A1:1 ";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // Colour space = 4:2:0 subsampling
  
  {
    char *segment = "C420jpeg\n";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // Comment
  
  {
    char *segment = "XYSCSS=420JPEG\n";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  return 0;
}

static inline
int y4m_write_frame(FILE *outFile, Y4MFrameStruct *fsPtr) {
  // FRAME marker
  
  {
    char *segment = "FRAME\n";
    int segmentLen = (int) strlen(segment);
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // Y
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->yPtr;
    int segmentLen = (int) fsPtr->yLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // U
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->uPtr;
    int segmentLen = (int) fsPtr->uLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  // V
  
  {
    uint8_t *segment = (uint8_t *) fsPtr->vPtr;
    int segmentLen = (int) fsPtr->vLen;
    int numWritten = (int) fwrite(segment, segmentLen, 1, outFile);
    if (numWritten != 1) {
      return 2;
    }
  }
  
  return 0;
}

#endif // _Y4M_WRITER_H
