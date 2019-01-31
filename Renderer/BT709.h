//
//  BT709.h
//
//  Created by Moses DeJong on 12/14/18.
//
//  Header only interface to mapping from from linear RGB to BT.709,
//  from sRGB to BT.709, and vice versa.
//
//  https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.709-6-201506-I!!PDF-E.pdf
//  https://forums.creativecow.net/thread/2/1131717
//  https://www.khronos.org/registry/DataFormat/specs/1.2/dataformat.1.2.html#TRANSFER_ITU
//
//  Licensed under BSD terms.

#include "sRGB.h"

#if !defined(_BT709_H)
#define _BT709_H

// BT.601 constants

// Kr, Kg, Kb (601)

//const float Kr = 0.299f;
//const float Kg = 0.587f;
//const float Kb = 0.114f;
//
//const float Er_minus_Ey_Range = 0.701f * 2.0f; // 1.402 : aka 2*(1.0 - Kr)
//const float Eb_minus_Ey_Range = 0.886f * 2.0f; // 1.772 : aka 2*(1.0 - Kb)

// Kr, Kg, Kb (709)

const static float BT709_Kr = 0.2126f;
const static float BT709_Kg = 0.7152f;
const static float BT709_Kb = 0.0722f;

const static float BT709_Er_minus_Ey_Range = 1.5748f; // 2*(1.0 - Kr)
const static float BT709_Eb_minus_Ey_Range = 1.8556f; // 2*(1.0 - Kb)

//const static float Er_minus_Ey_Range = (2.0f * (1.0f - Kr));
//const static float Eb_minus_Ey_Range = (2.0f * (1.0f - Kb));

// Generic

const static float BT709_Kr_over_Kg = BT709_Kr / BT709_Kg;
const static float BT709_Kb_over_Kg = BT709_Kb / BT709_Kg;

const static int BT709_YMin =  16;
const static int BT709_YMax = 235;

const static int BT709_UVMin =  16;
const static int BT709_UVMax = 240;

// BT.709

// Convert a non-linear log value to a linear value.
// Note that normV must be normalized in the range [0.0 1.0].
// Note that converting from non-linear to linear
// with a form like pow(x, Gamma) will reduce the signal strength.

static inline
float BT709_nonLinearNormToLinear(float normV) {
  
  if (normV < 0.081f) {
    normV *= (1.0f / 4.5f);
  } else {
    const float a = 0.099f;
    const float gamma = 1.0f / 0.45f;
    normV = (normV + a) * (1.0f / (1.0f + a));
    normV = pow(normV, gamma);
  }
  
  return normV;
}

// ((v + 0.099) / 1.099) ^ 1.961

// Convert a linear log value to a non-linear value.
// Note that normV must be normalized in the range [0.0 1.0]
// Note that converting from linear to non-linear
// with a form like pow(x, 1/Gamma) will boost the signal up.

static inline
float BT709_linearNormToNonLinear(float normV) {
  
  if (normV < 0.018f) {
    normV *= 4.5f;
  } else {
    // This 0.45 constant rounds better than (1.0f / 2.2f)
    const float a = 0.099f;
    const float gamma = 0.45f;
    normV = (1.0f + a) * pow(normV, gamma) - a;
  }
  
  return normV;
}

// Apple ColorSync defined gamma 1.961 combined with a straight line
// with a slope of 16 (aka 0.0625) intersects at (0.00349, 0.05584)

// [gamma a b c d e f]
//
// Curve Type 3 : Y = (aX+b)^gamma     [X >= d],     Y = cX [X < d]
//
// "com.apple.cmm.ParamCurve3" = (
//                                       "1.960938", // gamma
//                                       1, // a
//                                       0, // b
//                                       "0.0625", // c
//                                       "0.05583828", // d
//                                       0, // e
//                                       0 // f
//                                       );

//#define APPLE_GAMMA_196 (1.961f)
#define APPLE_GAMMA_196 (1.960938f)

static inline
float Apple196_nonLinearNormToLinear(float normV) {
  const float xIntercept = 0.05583828f;
  
  if (normV < xIntercept) {
    normV *= (1.0f / 16.0f);
  } else {
    const float gamma = APPLE_GAMMA_196;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

static inline
float Apple196_linearNormToNonLinear(float normV) {
  const float yIntercept = 0.00349f;
  
  if (normV < yIntercept) {
    normV *= 16.0f;
  } else {
    const float gamma = 1.0f / APPLE_GAMMA_196;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

// Decode Gamma encoding to a byte value that is already normalized.
// A decode converts from non-linear to linear.

static inline
int BT709_decodeGamma(int v, int minv, int maxv) {
#if defined(DEBUG)
  assert(v >= minv);
  assert(v <= maxv);
#endif // DEBUG
  v = v - minv;
  
  float normV = v / (float) (maxv - minv);
  
  normV = BT709_nonLinearNormToLinear(normV);
  
  int rInt = round(normV * (maxv - minv));
  rInt += minv;
  return rInt;
}

// Add Gamma encoding on a byte value that is already normalized

static inline
int BT709_encodeGamma(int v, int minv, int maxv) {
#if defined(DEBUG)
  assert(v >= minv);
  assert(v <= maxv);
#endif // DEBUG
  v = v - minv;
  
  float normV = v / (float) (maxv - minv);
  
  normV = BT709_linearNormToNonLinear(normV);
  
  int rInt = round(normV * (maxv - minv));
  rInt += minv;
  return rInt;
}

// Given a non-linear gamma encoded and normalized value,
// pass through Y Cb Cr conversion matrix and generate
// integer representations of the components. Note that
// it is also possible that this method can be invoked
// with a linear value that is not gamma encoded, for
// example when an alpha channel is encoded.

static inline
int BT709_convertNonLinearRGBToYCbCr(
                                  float Rn,
                                  float Gn,
                                  float Bn,
                                  int *YPtr,
                                  int *CbPtr,
                                  int *CrPtr)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(YPtr);
  assert(CbPtr);
  assert(CrPtr);
#endif // DEBUG
  
  if (debug) {
    printf("Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    printf("R G B in byte range : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
  }
  
  // https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.709-6-201506-I!!PDF-E.pdf
  
  float Ey = (BT709_Kr * Rn) + (BT709_Kg * Gn) + (BT709_Kb * Bn);
  float Eb = (Bn - Ey) / BT709_Eb_minus_Ey_Range;
  float Er = (Rn - Ey) / BT709_Er_minus_Ey_Range;
  
  if (debug) {
    printf("Ey Eb Er : %.4f %.4f %.4f\n", Ey, Eb, Er);
  }
  
  // Quant Y to range [16, 235] (inclusive 219 values)
  // Quant Eb, Er to range [16, 240] (inclusive 224 values, centered at 128)
  
  float AdjEy = (Ey * (BT709_YMax-BT709_YMin)) + 16;
  float AdjEb = (Eb * (BT709_UVMax-BT709_UVMin)) + 128;
  float AdjEr = (Er * (BT709_UVMax-BT709_UVMin)) + 128;
  
  if (debug) {
    printf("unrounded:\n");
    printf("Ey Eb Er : %.4f %.4f %.4f\n", AdjEy, AdjEb, AdjEr);
  }
  
  // Round to nearest int value
  
  int Y = (int) round(AdjEy);
  int Cb = (int) round(AdjEb);
  int Cr = (int) round(AdjEr);
  
#if defined(DEBUG)
  assert(Y >= BT709_YMin);
  assert(Y <= BT709_YMax);
  
  assert(Cb >= BT709_UVMin);
  assert(Cb <= BT709_UVMax);
  
  assert(Cr >= BT709_UVMin);
  assert(Cr <= BT709_UVMax);
#endif // DEBUG
  
  *YPtr = Y;
  *CbPtr = Cb;
  *CrPtr = Cr;
  
  if (debug) {
    printf("Y Cb Cr : %3d %3d %3d\n", Y, Cb, Cr);
  }
  
  return 0;
}

// Given a normalized linear RGB pixel value, convert to BT.709
// YCbCr log colorspace. This method assumes Alpha = 255, the
// gamma flag makes it possible to return Y without a gamma
// adjustment.

static inline
int BT709_convertLinearRGBToYCbCr(
                            float Rn,
                            float Gn,
                            float Bn,
                            int *YPtr,
                            int *CbPtr,
                            int *CrPtr,
                            int applyGammaMap)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(YPtr);
  assert(CbPtr);
  assert(CrPtr);
#endif // DEBUG
  
  if (debug) {
    printf("Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    printf("R G B in byte range : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
  }

  // Gamma adjustment to non-linear value
  
  if (applyGammaMap) {
    
    if (debug) {
      printf("pre  to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
    
    // Always encode using BT.709 defined curve.
    // Apple may decode with a slightly different curve.
    
    Rn = BT709_linearNormToNonLinear(Rn);
    Gn = BT709_linearNormToNonLinear(Gn);
    Bn = BT709_linearNormToNonLinear(Bn);
    
    if (debug) {
      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
      printf("R G B in byte range : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
  }
  
  int result = BT709_convertNonLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr);
  return result;
}

// Previous API, only used in test cases

static inline
int BT709_convertRGBToYCbCr(
                                    int R,
                                    int G,
                                    int B,
                                    int *YPtr,
                                    int *CbPtr,
                                    int *CrPtr,
                                    int applyGammaMap)
{
  float Rn = byteNorm(R);
  float Gn = byteNorm(G);
  float Bn = byteNorm(B);
  
  return BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr, applyGammaMap);
}

// Given a YCbCr input stored as an integer, apply the
// BT.709 matrix conversion step and return a non-linear
// result (result is still gamma adjusted) as a normalzied value.

static inline
int BT709_convertYCbCrToNonLinearRGB(
                                  int Y,
                                  int Cb,
                                  int Cr,
                                  float *RPtr,
                                  float *GPtr,
                                  float *BPtr)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(RPtr);
  assert(GPtr);
  assert(BPtr);
  
  assert(BT709_YMin <= Y && Y <= BT709_YMax);
#endif // DEBUG
  
  // https://en.wikipedia.org/wiki/YCbCr#ITU-R_BT.709_conversion
  // http://www.niwa.nu/2013/05/understanding-yuv-values/
  
  // Normalize Y to range [0 255]
  //
  // Note that the matrix multiply will adjust
  // this byte normalized range to account for
  // the limited range [16 235]
  
  float Yn = (Y - 16) * (1.0f / 255.0f);
  
  // Normalize Cb and CR with zero at 128 and range [0 255]
  // Note that matrix will adjust to limited range [16 240]
  
  float Cbn = (Cb - 128) * (1.0f / 255.0f);
  float Crn = (Cr - 128) * (1.0f / 255.0f);
  
  if (debug) {
    printf("zerod normalized Yn Cbn Crn : %.8f %.8f %.8f\n", Yn, Cbn, Crn);
    
    int Yint = round(Yn * 255.0f);
    int Cbint = round(Cbn * 255.0f);
    int Crint = round(Crn * 255.0f);
    
    printf("as byte range Y Cb Cr : %3d %3d %3d\n", Yint, Cbint, Crint);
  }
  
  // BT.601
  //
  // 1.164,  0.000, 1.596
  // 1.164, -0.392, -0.813
  // 1.164,  2.017, 0.000
  
  // BT.709 (HDTV)
  // (col0) (col1) (col2)
  // 1.164  0.000  1.793
  // 1.164 -0.213 -0.533
  // 1.164  2.112  0.000
  
  // Col 0 : range of Y and UV values
  //
  // [0] : 1.164 : YScale
  // [1] : 1.164 : YScale
  // [2] : 1.164 : YScale
  
  // Col 1 :
  // [0] : 0.0 (No Cb input)
  // [1] : -1 * UVScale * Eb_minus_Ey_Range * Kb_over_Kg
  // [2] : UVScale * Eb_minus_Ey_Range
  
  // Col 2 : Cr
  //
  // [0] : UVScale * Er_minus_Ey_Range
  // [1] : -1 * UVScale * Er_minus_Ey_Range * Kr_over_Kg
  // [2] : 0.0
  
  const float YScale = 255.0f / (BT709_YMax-BT709_YMin);
  const float UVScale = 255.0f / (BT709_UVMax-BT709_UVMin);
  
  const
  float BT709Mat[] = {
    YScale,   0.000f,  (UVScale * BT709_Er_minus_Ey_Range),
    YScale, (-1.0f * UVScale * BT709_Eb_minus_Ey_Range * BT709_Kb_over_Kg),  (-1.0f * UVScale * BT709_Er_minus_Ey_Range * BT709_Kr_over_Kg),
    YScale, (UVScale * BT709_Eb_minus_Ey_Range),  0.000f,
  };
  
  if (debug) {
    printf("Mat 3x3:\n");
    printf("%.8f %.8f %.8f\n", BT709Mat[0], BT709Mat[1], BT709Mat[2]);
    printf("%.8f %.8f %.8f\n", BT709Mat[3], BT709Mat[4], BT709Mat[5]);
    printf("%.8f %.8f %.8f\n", BT709Mat[6], BT709Mat[7], BT709Mat[8]);
  }
  
  // Matrix multiply operation
  //
  // rgb = BT709Mat * YCbCr
  
  if (debug) {
    // Print the normalized Y value before dealing with colors in the Mat
    
    float Yscaled = (Yn * BT709Mat[0]);
    
    printf("Yscaled %.8f\n", Yscaled);
    
    float YscaledByte = Yscaled * 255.0f;
    
    printf("Yscaled in byte range %.4f\n", YscaledByte);
  }
  
  // Convert input Y, Cb, Cr to normalized float values
  
  float Rn = (Yn * BT709Mat[0]) + (Cbn * BT709Mat[1]) + (Crn * BT709Mat[2]);
  float Gn = (Yn * BT709Mat[3]) + (Cbn * BT709Mat[4]) + (Crn * BT709Mat[5]);
  float Bn = (Yn * BT709Mat[6]) + (Cbn * BT709Mat[7]) + (Crn * BT709Mat[8]);
  
  if (debug) {
    printf("unclamped:\n");
    printf("Rn %.8f\n", Rn);
    printf("Gn %.8f\n", Gn);
    printf("Bn %.8f\n", Bn);
  }
  
  // Saturate normalized linear (R G B) to range [0.0, 1.0]
  
  Rn = saturatef(Rn);
  Gn = saturatef(Gn);
  Bn = saturatef(Bn);
  
  if (debug) {
    printf("clamped:\n");
    printf("Rn %.8f\n", Rn);
    printf("Gn %.8f\n", Gn);
    printf("Bn %.8f\n", Bn);
  }
  
  *RPtr = Rn;
  *GPtr = Gn;
  *BPtr = Bn;
  
  return 0;
}

// Convert from BT.709 YCbCr to linear RGB as a normalized float

static inline
int BT709_convertYCbCrToLinearRGB(
                             int Y,
                             int Cb,
                             int Cr,
                             float *RPtr,
                             float *GPtr,
                             float *BPtr,
                             int applyGammaMap)
{
  const int debug = 1;
  
  BT709_convertYCbCrToNonLinearRGB(Y, Cb, Cr, RPtr, GPtr, BPtr);
  
  float Rn = *RPtr;
  float Gn = *GPtr;
  float Bn = *BPtr;
  
  // Gamma adjustment for RGB components after matrix transform
  
  if (applyGammaMap) {
    if (debug) {
      printf("pre  to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
    
    Rn = BT709_nonLinearNormToLinear(Rn);
    Gn = BT709_nonLinearNormToLinear(Gn);
    Bn = BT709_nonLinearNormToLinear(Bn);
    
    if (debug) {
      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
  }
  
  *RPtr = Rn;
  *GPtr = Gn;
  *BPtr = Bn;
  
  return 0;
}

static inline
int BT709_convertYCbCrToRGB(
                            int Y,
                            int Cb,
                            int Cr,
                            int *RIntPtr,
                            int *GIntPtr,
                            int *BIntPtr,
                            int applyGammaMap)
{
  const int debug = 1;
  
  float Rn;
  float Gn;
  float Bn;
  
  BT709_convertYCbCrToLinearRGB(Y, Cb, Cr, &Rn, &Gn, &Bn, applyGammaMap);
  
  // Round to nearest int value in range [0, 255]
  
  int R = (int) round(Rn * 255.0f);
  int G = (int) round(Gn * 255.0f);
  int B = (int) round(Bn * 255.0f);
  
  if (debug) {
    printf("scaled up to byte range:\n");
    printf("R %.4f\n", Rn * 255.0f);
    printf("G %.4f\n", Gn * 255.0f);
    printf("B %.4f\n", Bn * 255.0f);
    
    printf("rounded to int:\n");
    printf("R %3d\n", R);
    printf("G %3d\n", G);
    printf("B %3d\n", B);
  }
  
#if defined(DEBUG)
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  *RIntPtr = R;
  *GIntPtr = G;
  *BIntPtr = B;
  
  return 0;
}

// Convert sRGB directly to BT.709 by first converting
// to linear RGB and then to YCbCr.

static inline
int BT709_from_sRGB_convertRGBToYCbCr(
                                    int R,
                                    int G,
                                    int B,
                                    int *YPtr,
                                    int *CbPtr,
                                    int *CrPtr,
                                    int applyGammaMap)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(YPtr);
  assert(CbPtr);
  assert(CrPtr);
  
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  if (debug) {
    printf("sRGB in : R G B : %3d %3d %3d\n", R, G, B);
  }
  
  // Intermediate rep must use float to avoid dark precision loss
  // https://blog.demofox.org/2018/03/10/dont-convert-srgb-u8-to-linear-u8/
  
  float Rn = byteNorm(R);
  float Gn = byteNorm(G);
  float Bn = byteNorm(B);
  
  // Convert non-linear sRGB to linear
  
  if (applyGammaMap) {
    if (debug) {
      printf("pre  to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
      
      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
    
    Rn = sRGB_nonLinearNormToLinear(Rn);
    Gn = sRGB_nonLinearNormToLinear(Gn);
    Bn = sRGB_nonLinearNormToLinear(Bn);
    
    if (debug) {
      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
      
      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
  }
  
  return BT709_convertLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr, applyGammaMap);
}

// Convert BT.709 to sRGB in non-linear space

static inline
int BT709_to_sRGB_convertYCbCrToRGB(
                                    int Y,
                                    int Cb,
                                    int Cr,
                                    int *RPtr,
                                    int *GPtr,
                                    int *BPtr,
                                    int applyGammaMap)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(RPtr);
  assert(GPtr);
  assert(BPtr);
#endif // DEBUG
  
  if (debug) {
    printf("Y Cb Cr : %3d %3d %3d\n", Y, Cb, Cr);
  }
  
  float Rn, Gn, Bn;
  BT709_convertYCbCrToLinearRGB(Y, Cb, Cr, &Rn, &Gn, &Bn, applyGammaMap);
  
  // Convert linear RGB to non-linear sRGB

  if (applyGammaMap) {
    if (debug) {
      printf("pre  to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
    
    Rn = sRGB_linearNormToNonLinear(Rn);
    Gn = sRGB_linearNormToNonLinear(Gn);
    Bn = sRGB_linearNormToNonLinear(Bn);
    
    if (debug) {
      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
  }
  
  // Write RGB values as int in byte range [0 255]
  
  int R = (int) round(Rn * 255.0f);
  int G = (int) round(Gn * 255.0f);
  int B = (int) round(Bn * 255.0f);
  
  if (debug) {
    printf("scaled up to byte range:\n");
    printf("R %.4f\n", Rn * 255.0f);
    printf("G %.4f\n", Gn * 255.0f);
    printf("B %.4f\n", Bn * 255.0f);
    
    printf("rounded to int:\n");
    printf("R %3d\n", R);
    printf("G %3d\n", G);
    printf("B %3d\n", B);
  }
  
#if defined(DEBUG)
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  *RPtr = R;
  *GPtr = G;
  *BPtr = B;
  
  return 0;
}

// Apple specific gamma encoding curve from sRGB to 1.96
// like encoding that can be exactly inverted with CoreVideo.

static inline
int Apple196_from_sRGB_convertRGBToYCbCr(
                                      int R,
                                      int G,
                                      int B,
                                      int *YPtr,
                                      int *CbPtr,
                                      int *CrPtr)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(YPtr);
  assert(CbPtr);
  assert(CrPtr);
  
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  if (debug) {
    printf("sRGB in : R G B : %3d %3d %3d\n", R, G, B);
  }
  
  // Intermediate rep must use float to avoid dark precision loss
  // https://blog.demofox.org/2018/03/10/dont-convert-srgb-u8-to-linear-u8/
  
  float Rn = byteNorm(R);
  float Gn = byteNorm(G);
  float Bn = byteNorm(B);
  
  // Boosted encoding of linear RGB values, encode with an inverse
  // of the Apple decoding gamma so that sRGB values will come out
  // exactly the same as the original inputs when generated from
  // RGB values. This differs from camera recorded video since
  // a dark room boost of 1.2 and the BT.709 encoding are automatically
  // applied in that situation.

  if (1) {
    if (debug) {
      printf("pre  to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);

      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }

    Rn = sRGB_nonLinearNormToLinear(Rn);
    Gn = sRGB_nonLinearNormToLinear(Gn);
    Bn = sRGB_nonLinearNormToLinear(Bn);

    if (debug) {
      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);

      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
  }
  
  if (1) {
    if (debug) {
      printf("pre  to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
    
    Rn = Apple196_linearNormToNonLinear(Rn);
    Gn = Apple196_linearNormToNonLinear(Gn);
    Bn = Apple196_linearNormToNonLinear(Bn);
    
    if (debug) {
      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
    }
  }
  
  return BT709_convertNonLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr);
}

// Convert from Apple 1.96 gamma encoded value to sRGB

static inline
int Apple196_to_sRGB_convertYCbCrToRGB(
                                    int Y,
                                    int Cb,
                                    int Cr,
                                    int *RPtr,
                                    int *GPtr,
                                    int *BPtr,
                                    int applyGammaMap)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(RPtr);
  assert(GPtr);
  assert(BPtr);
#endif // DEBUG
  
  if (debug) {
    printf("Y Cb Cr : %3d %3d %3d\n", Y, Cb, Cr);
  }
  
  float Rn, Gn, Bn;
    
  BT709_convertYCbCrToNonLinearRGB(Y, Cb, Cr, &Rn, &Gn, &Bn);
  
  // Convert non-linear RGB to linear RGB
  
  if (applyGammaMap) {
    if (debug) {
      printf("pre  to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }

    Rn = Apple196_nonLinearNormToLinear(Rn);
    Gn = Apple196_nonLinearNormToLinear(Gn);
    Bn = Apple196_nonLinearNormToLinear(Bn);

    if (debug) {
      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
  }

  // Convert linear RGB values to non-linear sRGB
  
  if (applyGammaMap) {
    if (debug) {
      printf("pre  to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
    
    Rn = sRGB_linearNormToNonLinear(Rn);
    Gn = sRGB_linearNormToNonLinear(Gn);
    Bn = sRGB_linearNormToNonLinear(Bn);
    
    if (debug) {
      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
  }
  
  // Write RGB values as int in byte range [0 255]
  
  int R = (int) round(Rn * 255.0f);
  int G = (int) round(Gn * 255.0f);
  int B = (int) round(Bn * 255.0f);
  
  if (debug) {
    printf("scaled up to byte range:\n");
    printf("R %.4f\n", Rn * 255.0f);
    printf("G %.4f\n", Gn * 255.0f);
    printf("B %.4f\n", Bn * 255.0f);
    
    printf("rounded to int:\n");
    printf("R %3d\n", R);
    printf("G %3d\n", G);
    printf("B %3d\n", B);
  }
  
#if defined(DEBUG)
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  *RPtr = R;
  *GPtr = G;
  *BPtr = B;
  
  return 0;
}

// When input RGB data is already encoded in sRGB colorspace
// then the normalized float values can be passed directly
// into YCbCr matrix transform.

static inline
int sRGB_from_sRGB_convertRGBToYCbCr(
                                         int R,
                                         int G,
                                         int B,
                                         int *YPtr,
                                         int *CbPtr,
                                         int *CrPtr)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(YPtr);
  assert(CbPtr);
  assert(CrPtr);
  
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  if (debug) {
    printf("sRGB in : R G B : %3d %3d %3d\n", R, G, B);
  }
  
  float Rn = byteNorm(R);
  float Gn = byteNorm(G);
  float Bn = byteNorm(B);
  
  return BT709_convertNonLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr);
}

// Convert from YCbCr encoded with sRGB gamma curve back to sRGB

static inline
int sRGB_to_sRGB_convertYCbCrToRGB(
                                       int Y,
                                       int Cb,
                                       int Cr,
                                       int *RPtr,
                                       int *GPtr,
                                       int *BPtr,
                                       int applyGammaMap)
{
  const int debug = 1;
  
#if defined(DEBUG)
  assert(RPtr);
  assert(GPtr);
  assert(BPtr);
#endif // DEBUG
  
  if (debug) {
    printf("Y Cb Cr : %3d %3d %3d\n", Y, Cb, Cr);
  }
  
  float Rn, Gn, Bn;
  
  BT709_convertYCbCrToNonLinearRGB(Y, Cb, Cr, &Rn, &Gn, &Bn);
  
  // Write RGB values as int in byte range [0 255]
  
  int R = (int) round(Rn * 255.0f);
  int G = (int) round(Gn * 255.0f);
  int B = (int) round(Bn * 255.0f);
  
  if (debug) {
    printf("scaled up to byte range:\n");
    printf("R %.4f\n", Rn * 255.0f);
    printf("G %.4f\n", Gn * 255.0f);
    printf("B %.4f\n", Bn * 255.0f);
    
    printf("rounded to int:\n");
    printf("R %3d\n", R);
    printf("G %3d\n", G);
    printf("B %3d\n", B);
  }
  
#if defined(DEBUG)
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  *RPtr = R;
  *GPtr = G;
  *BPtr = B;
  
  return 0;
}

#endif // _BT709_H
