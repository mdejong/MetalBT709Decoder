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

- (void)testConvertsLinearRGBToBT709_42PercentBlue_srgb {
  
  int Rin = 0;
  int Gin = 0;
  int Bin = 107;
  
  int Y, Cb, Cr;
  int applyGammaMap = 1;
  
  int result;
  
  result = BT709_from_sRGB_convertRGBToYCbCr(Rin, Gin, Bin, &Y, &Cb, &Cr, 1);
  XCTAssert(result == 0);
  
  {
    int v = Y;
    int expectedVal = 22;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 169;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 124;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  int R, G, B;
  result = BT709_to_sRGB_convertYCbCrToRGB(Y, Cb, Cr, &R, &G, &B, applyGammaMap);
  XCTAssert(result == 0);
  
  {
    int v = R;
    int expectedVal = Rin;
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

// Round trip sRGB -> BT.709 with all R,G,B values

- (void)testConvertsRGBTo709_RoundTripAll_WithGamma {
  
  // The sRGB space will contain more pixels than the BT.709
  // space because of the compressed range of YCbCr vlaues.
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionary];
  
  mDict[@"exact"] = @(0);
  mDict[@"off1"] = @(0);
  mDict[@"off2"] = @(0);
  mDict[@"off3"] = @(0);
  mDict[@"off4"] = @(0);
  mDict[@"off5"] = @(0);
  mDict[@"off6"] = @(0);
  mDict[@"off7"] = @(0);
  mDict[@"off8"] = @(0);
  mDict[@"off9"] = @(0);
  mDict[@"offMore9"] = @(0);
  
  const int applyGammaMap = 1;
  
  for (int R = 0; R <= 255; R++) {
    for (int G = 0; G <= 255; G++) {
      for (int B = 0; B <= 255; B++) {
        
        int Y, Cb, Cr;
        
        int result;
        
        result = BT709_from_sRGB_convertRGBToYCbCr(R, G, B, &Y, &Cb, &Cr, applyGammaMap);
        XCTAssert(result == 0);
        
        // Reverse encoding process to get back to original RGB
        
        int decR, decG, decB;
        
        result = BT709_to_sRGB_convertYCbCrToRGB(Y, Cb, Cr, &decR, &decG, &decB, applyGammaMap);
        XCTAssert(result == 0);
        
        // Determine if the round trip is exact, off by 1, off by 2
        // or off by more than 2.
        
        BOOL isTheSame = [self isExactlyTheSame:R G:G B:B decR:decR decG:decG decB:decB];
        
        if (isTheSame) {
          // Increment count of values that are exactly the same
          
          NSString *key = @"exact";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:1]) {
          NSString *key = @"off1";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:2]) {
          NSString *key = @"off2";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:3]) {
          NSString *key = @"off3";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:4]) {
          NSString *key = @"off4";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:5]) {
          NSString *key = @"off5";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:6]) {
          NSString *key = @"off6";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:7]) {
          NSString *key = @"off7";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:8]) {
          NSString *key = @"off8";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:9]) {
          NSString *key = @"off9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else {
          // Off by more than 3, save as a key
          NSString *str = [NSString stringWithFormat:@"(%d %d %d) != (%d %d %d)", R, G, B, decR, decG, decB];
          //          mDict[str] = @"";
          
          NSString *key = @"offMore9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        }
      }
    }
  }
  
  NSLog(@"mDict %@", mDict);
  
  // Lossy range conversion means a whole bunch of colors are not an exact match
  
  XCTAssert([mDict[@"exact"] intValue] == 2753221, @"all exact");
  
  return;
}

/* Round trip with software
 
 exact =  2753221
 off1 =  12653553
 off2 =   1006705
 off3 =    295446
 off4 =     67339
 off5 =       952
 off6 =         0
 off7 =         0
 off8 =         0
 off9 =         0
 offMore9 =     0
 
 */

// Round trip sRGB -> Apple196 with all R,G,B values

- (void)testConvertsRGBToApple196_RoundTripAll_WithGamma {
  
  // The sRGB space will contain more pixels than the BT.709
  // space because of the compressed range of YCbCr vlaues.
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionary];
  
  mDict[@"exact"] = @(0);
  mDict[@"off1"] = @(0);
  mDict[@"off2"] = @(0);
  mDict[@"off3"] = @(0);
  mDict[@"off4"] = @(0);
  mDict[@"off5"] = @(0);
  mDict[@"off6"] = @(0);
  mDict[@"off7"] = @(0);
  mDict[@"off8"] = @(0);
  mDict[@"off9"] = @(0);
  mDict[@"offMore9"] = @(0);
  
  const int applyGammaMap = 1;
  
  for (int R = 0; R <= 255; R++) {
    for (int G = 0; G <= 255; G++) {
      for (int B = 0; B <= 255; B++) {
        
        int Y, Cb, Cr;
        
        int result;
        
        result = Apple196_from_sRGB_convertRGBToYCbCr(R, G, B, &Y, &Cb, &Cr);
        XCTAssert(result == 0);
        
        // Reverse encoding process to get back to original RGB
        
        int decR, decG, decB;
        
        result = Apple196_to_sRGB_convertYCbCrToRGB(Y, Cb, Cr, &decR, &decG, &decB, applyGammaMap);
        XCTAssert(result == 0);
        
        // Determine if the round trip is exact, off by 1, off by 2
        // or off by more than 2.
        
        BOOL isTheSame = [self isExactlyTheSame:R G:G B:B decR:decR decG:decG decB:decB];
        
        if (isTheSame) {
          // Increment count of values that are exactly the same
          
          NSString *key = @"exact";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:1]) {
          NSString *key = @"off1";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:2]) {
          NSString *key = @"off2";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:3]) {
          NSString *key = @"off3";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:4]) {
          NSString *key = @"off4";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:5]) {
          NSString *key = @"off5";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:6]) {
          NSString *key = @"off6";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:7]) {
          NSString *key = @"off7";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:8]) {
          NSString *key = @"off8";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:9]) {
          NSString *key = @"off9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else {
          // Off by more than 3, save as a key
          NSString *str = [NSString stringWithFormat:@"(%d %d %d) != (%d %d %d)", R, G, B, decR, decG, decB];
          //          mDict[str] = @"";
          
          NSString *key = @"offMore9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        }
      }
    }
  }
  
  NSLog(@"mDict %@", mDict);
  
  // Lossy range conversion means a whole bunch of colors are not an exact match
  
  XCTAssert([mDict[@"exact"] intValue] == 2753405, @"all exact");
  
  return;
}

/*
 Software results:
 
 exact =  2753405;
 off1  = 13499212;
 off2  =   524599;
 off3 = 0;
 off4 = 0;
 off5 = 0;
 off6 = 0;
 off7 = 0;
 off8 = 0;
 off9 = 0;
 offMore9 = 0;
 
 */


// SRGB curve to represent gamma encoded value before matrix transform

- (void)testConvertSRGBToSRGB_RoundTripAll_WithGamma {
  
  // The sRGB space will contain more pixels than the BT.709
  // space because of the compressed range of YCbCr vlaues.
  
  NSMutableDictionary *mDict = [NSMutableDictionary dictionary];
  
  mDict[@"exact"] = @(0);
  mDict[@"off1"] = @(0);
  mDict[@"off2"] = @(0);
  mDict[@"off3"] = @(0);
  mDict[@"off4"] = @(0);
  mDict[@"off5"] = @(0);
  mDict[@"off6"] = @(0);
  mDict[@"off7"] = @(0);
  mDict[@"off8"] = @(0);
  mDict[@"off9"] = @(0);
  mDict[@"offMore9"] = @(0);
  
  const int applyGammaMap = 1;
  
  for (int R = 0; R <= 255; R++) {
    for (int G = 0; G <= 255; G++) {
      for (int B = 0; B <= 255; B++) {
        
        int Y, Cb, Cr;
        
        int result;
        
        result = sRGB_from_sRGB_convertRGBToYCbCr(R, G, B, &Y, &Cb, &Cr);
        XCTAssert(result == 0);
        
        // Reverse encoding process to get back to original RGB
        
        int decR, decG, decB;
        
        result = sRGB_to_sRGB_convertYCbCrToRGB(Y, Cb, Cr, &decR, &decG, &decB, applyGammaMap);
        XCTAssert(result == 0);
        
        // Determine if the round trip is exact, off by 1, off by 2
        // or off by more than 2.
        
        BOOL isTheSame = [self isExactlyTheSame:R G:G B:B decR:decR decG:decG decB:decB];
        
        if (isTheSame) {
          // Increment count of values that are exactly the same
          
          NSString *key = @"exact";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:1]) {
          NSString *key = @"off1";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:2]) {
          NSString *key = @"off2";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:3]) {
          NSString *key = @"off3";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:4]) {
          NSString *key = @"off4";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:5]) {
          NSString *key = @"off5";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:6]) {
          NSString *key = @"off6";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:7]) {
          NSString *key = @"off7";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:8]) {
          NSString *key = @"off8";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else if ([self isOffBy:R G:G B:B decR:decR decG:decG decB:decB delta:9]) {
          NSString *key = @"off9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        } else {
          // Off by more than 3, save as a key
          NSString *str = [NSString stringWithFormat:@"(%d %d %d) != (%d %d %d)", R, G, B, decR, decG, decB];
          //          mDict[str] = @"";
          
          NSString *key = @"offMore9";
          NSNumber *countNum = mDict[key];
          int countPlusOne = [countNum intValue] + 1;
          mDict[key] = @(countPlusOne);
        }
      }
    }
  }
  
  NSLog(@"mDict %@", mDict);
  
  // Lossy range conversion means a whole bunch of colors are not an exact match
  
  XCTAssert([mDict[@"exact"] intValue] == 2753405, @"all exact");
  
  return;
}

/*
 
 Apple196 results:
 
 exact =  2753405
 off1  = 13499212
 off2  =   524599
 off3  =        0
 
 sRGB encode/decode results:
 
 exact =  2753772
 off1 =  13893861
 off2 =    129583
 off3 =         0
 
 */


@end
