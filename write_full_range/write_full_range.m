//
//  main.m
//  write_full_range
//
//  Created by Mo DeJong on 2/3/19.
//  Copyright © 2019 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CGFrameBuffer.h"
#import "BGRAToBT709Converter.h"

#import "sRGB.h"
#import "BT709.h"

#import "y4m_writer.h"


int main(int argc, const char * argv[]) {
  @autoreleasepool {
    // Generate YCbCr bytes using full range [0, 255]
    // values as opposed to pc range [16, 235 | 240]

    const char *outFilename = "write_y4m_ex.y4m";
    FILE *outFile = y4m_open_file(outFilename);
    
    if (outFile == NULL) {
      return 1;
    }
    
    int width = 256;
    int height = 256;
    
    NSMutableData *yData = [NSMutableData dataWithLength:width*height];
    uint8_t *yPtr = (uint8_t*) yData.bytes;
    
    for (int i = 0; i < (width * height); i++) {
      if ((i % 2) == 0) {
        yPtr[i] = 255;
      } else {
        yPtr[i] = 128;
      }
    }
    
    int hw = 256 / 2;
    int hh = 256 / 2;
    
    NSMutableData *uData = [NSMutableData dataWithLength:hw*hh];
    NSMutableData *vData = [NSMutableData dataWithLength:hw*hh];
    
    uint8_t *uPtr = (uint8_t*) uData.bytes;
    uint8_t *vPtr = (uint8_t*) vData.bytes;
    
    for (int i = 0; i < (hw * hh); i++) {
      if ((i % 2) == 0) {
        uPtr[i] = 128;
        vPtr[i] = 128;
      } else {
        uPtr[i] = 128;
        vPtr[i] = 128;
      }
    }
    
    Y4MHeaderStruct header;
    
    header.width = width;
    header.height = height;
    
    header.fps = Y4MHeaderFPS_1;
    //header.fps = Y4MHeaderFPS_30;
    
    int header_result = y4m_write_header(outFile, &header);
    if (header_result != 0) {
      return header_result;
    }
    
    Y4MFrameStruct fs;
    
    fs.yPtr = (uint8_t*) yData.bytes;
    fs.yLen = (int) yData.length;
    
    fs.uPtr = (uint8_t*) uData.bytes;
    fs.uLen = (int) uData.length;
    
    fs.vPtr = (uint8_t*) vData.bytes;
    fs.vLen = (int) vData.length;
    
    int write_frame_result = y4m_write_frame(outFile, &fs);
    if (write_frame_result != 0) {
      return write_frame_result;
    }
    
    fclose(outFile);
  }
  return 0;
}
