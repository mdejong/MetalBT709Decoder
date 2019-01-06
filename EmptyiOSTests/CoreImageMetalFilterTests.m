//
//  CoreImageMetalFilterTests.m
//  CoreImageMetalFilterTests
//
//  Created by Mo DeJong on 12/13/18.
//  Copyright © 2018 HelpURock. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "sRGB.h"
#import "BT709.h"

@interface CoreImageMetalFilterTests : XCTestCase

@end

static inline
BOOL
floatIsEqualEpsilion(float f1, float f2, float epsilion)
{
  float delta = f1 - f2;
  return (delta < epsilion);
}

static inline
BOOL
floatIsEqual(float f1, float f2)
{
  float epsilion = 0.001;
  return floatIsEqualEpsilion(f1, f2, epsilion);
}

@implementation CoreImageMetalFilterTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (BOOL) isExactlyTheSame:(int)R
                        G:(int)G
                        B:(int)B
                     decR:(int)decR
                     decG:(int)decG
                     decB:(int)decB
{
  return (B == decB) && (G == decG) && (R == decR);
}

// Is v2 close enough to v1 (+- delta), return TRUE if so

- (BOOL) isCloseEnough:(int)v1
                    v2:(int)v2
                 delta:(int)delta
{
  assert(delta > 0);
  
  int max = (v1 + delta);
  int min = (v1 - delta);
  
  if (v2 >= min && v2 <= max) {
    return TRUE;
  } else {
    return FALSE;
  }
}

- (BOOL) isOffBy:(int)R
               G:(int)G
               B:(int)B
            decR:(int)decR
            decG:(int)decG
            decB:(int)decB
           delta:(int)delta
{
  BOOL BClose = [self isCloseEnough:B v2:decB delta:delta];
  BOOL GClose = [self isCloseEnough:G v2:decG delta:delta];
  BOOL RClose = [self isCloseEnough:R v2:decR delta:delta];
  
  if (BClose == FALSE || GClose == FALSE || RClose == FALSE) {
    // One of these values is larger than +-1 delta
    return FALSE;
  } else {
    // All 3 values are close enough
    return TRUE;
  }
}


- (void)testConvertsLinearRGBToBT709_NoGamma_75Percent {
  
  // Gray at 75% intensity
  //
  // Linear RGB (191 191 191) -> REC.709 (180 128 128)
  
  int Rin = 191;
  int Gin = Rin;
  int Bin = Rin;
  
  float Rn, Gn, Bn;
  
  Rn = byteNorm(Rin);
  Gn = Rn;
  Bn = Rn;
  
  int Y, Cb, Cr;
  int applyGammaMap = 0;
  
  int result;
  
  result = BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, &Y, &Cb, &Cr, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = Y;
    int expectedVal = 180;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  int R, G, B;
  result = BT709_convertYCbCrToRGB(Y, Cb, Cr, &R, &G, &B, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = R;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = G;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = B;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
}

- (void)testConvertsLinearRGBToBT709_WithGamma_75Percent {
  
  // Gray at 75% intensity
  //
  // Linear RGB (191 191 191) -> REC.709 (206 128 128)
  
  int Rin = 191;
  int Gin = Rin;
  int Bin = Rin;
  
  float Rn, Gn, Bn;
  
  Rn = byteNorm(Rin);
  Gn = Rn;
  Bn = Rn;
  
  int Y, Cb, Cr;
  int applyGammaMap = 1;
  
  int result;
  
  result = BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, &Y, &Cb, &Cr, applyGammaMap);
  XCTAssert(result == 0);
  
  // iOS emits 210 for this Y value, what is the gamma?
  
  {
    int v = Y;
    int expectedVal = 206;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  int R, G, B;
  result = BT709_convertYCbCrToRGB(Y, Cb, Cr, &R, &G, &B, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = R;
    int expectedVal = Rin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = G;
    int expectedVal = Gin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = B;
    int expectedVal = Bin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
}

- (void)testConvertsLinearRGBToBT709_NoGamma_25Percent {
  
  // Gray at 25% intensity
  //
  // Linear RGB (64 64 64) -> REC.709 (71 128 128)
  
  int Rin = 64;
  int Gin = Rin;
  int Bin = Rin;
  
  float Rn, Gn, Bn;
  
  Rn = byteNorm(Rin);
  Gn = Rn;
  Bn = Rn;
  
  int Y, Cb, Cr;
  int applyGammaMap = 0;
  
  int result;
  
  result = BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, &Y, &Cb, &Cr, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = Y;
    int expectedVal = 71;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  int R, G, B;
  result = BT709_convertYCbCrToRGB(Y, Cb, Cr, &R, &G, &B, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = R;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = G;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = B;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
}

- (void)testConvertsLinearRGBToBT709_WithGamma_25Percent {
  
  // Gray at 25% intensity
  //
  // Linear RGB (64 64 64) -> REC.709 (124 128 128)
  
  // Note that using the rounded linear value 64
  // means that the output is rounded up and then
  // the decoded value is +1. When an intermediate
  // float is used the Y rounds down to 123 which
  // decodes exactly when returning to sRGB.
  
  int Rin = 64;
  int Gin = Rin;
  int Bin = Rin;
  
  float Rn, Gn, Bn;
  
  Rn = byteNorm(Rin);
  Gn = Rn;
  Bn = Rn;
  
  int Y, Cb, Cr;
  int applyGammaMap = 1;
  
  int result;
  
  result = BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, &Y, &Cb, &Cr, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = Y;
    int expectedVal = 124;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  int R, G, B;
  result = BT709_convertYCbCrToRGB(Y, Cb, Cr, &R, &G, &B, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = R;
    int expectedVal = Rin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = G;
    int expectedVal = Gin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = B;
    int expectedVal = Bin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
}

@end
