//
//  BT709.h
//
//  Created by Moses DeJong on 12/14/18.
//
//  Header only interface to mapping from from linear RGB to BT.709,
//  from sRGB to BT.709, and vice versa.
//
//  https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.709-6-201506-I!!PDF-E.pdf
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

const static float Kr = 0.2126f;
const static float Kg = 0.7152f;
const static float Kb = 0.0722f;

const static float Er_minus_Ey_Range = 1.5748f; // 2*(1.0 - Kr)
const static float Eb_minus_Ey_Range = 1.8556f; // 2*(1.0 - Kb)

//const static float Er_minus_Ey_Range = (2.0f * (1.0f - Kr));
//const static float Eb_minus_Ey_Range = (2.0f * (1.0f - Kb));

// Generic

const static float Kr_over_Kg = Kr / Kg;
const static float Kb_over_Kg = Kb / Kg;

const static int YMin =  16;
const static int YMax = 235;

const static int UVMin =  16;
const static int UVMax = 240;

// BT.709

// Convert a non-linear log value to a linear value.
// Note that normV must be normalized in the range [0.0 1.0].

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

// Convert a linear log value to a non-linear value.
// Note that normV must be normalized in the range [0.0 1.0]

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
  const int debug = 0;
  
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
    
    Rn = BT709_linearNormToNonLinear(Rn);
    Gn = BT709_linearNormToNonLinear(Gn);
    Bn = BT709_linearNormToNonLinear(Bn);
    
    if (debug) {
      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
    }
  }
  
  // https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.709-6-201506-I!!PDF-E.pdf
  
  float Ey = (Kr * Rn) + (Kg * Gn) + (Kb * Bn);
  float Eb = (Bn - Ey) / Eb_minus_Ey_Range;
  float Er = (Rn - Ey) / Er_minus_Ey_Range;
  
  if (debug) {
    printf("Ey Eb Er : %.4f %.4f %.4f\n", Ey, Eb, Er);
  }
  
  // Quant Y to range [16, 235] (inclusive 219 values)
  // Quant Eb, Er to range [16, 240] (inclusive 224 values, centered at 128)
  
  float AdjEy = (Ey * (YMax-YMin)) + 16;
  float AdjEb = (Eb * (UVMax-UVMin)) + 128;
  float AdjEr = (Er * (UVMax-UVMin)) + 128;
  
  if (debug) {
    printf("unrounded:\n");
    printf("Ey Eb Er : %.4f %.4f %.4f\n", AdjEy, AdjEb, AdjEr);
  }
  
  // Round to nearest int value
  
  int Y = (int) round(AdjEy);
  int Cb = (int) round(AdjEb);
  int Cr = (int) round(AdjEr);
  
#if defined(DEBUG)
  assert(Y >= YMin);
  assert(Y <= YMax);
  
  assert(Cb >= UVMin);
  assert(Cb <= UVMax);
  
  assert(Cr >= UVMin);
  assert(Cr <= UVMax);
#endif // DEBUG
  
  *YPtr = Y;
  *CbPtr = Cb;
  *CrPtr = Cr;
  
  if (debug) {
    printf("Y Cb Cr : %3d %3d %3d\n", Y, Cb, Cr);
  }
  
  return 0;
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
  const int debug = 0;
  
#if defined(DEBUG)
  assert(RPtr);
  assert(GPtr);
  assert(BPtr);
  
  assert(YMin <= Y && Y <= YMax);
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

  const float YScale = 255.0f / (YMax-YMin);
  const float UVScale = 255.0f / (UVMax-UVMin);
  
  const
  float BT709Mat[] = {
    YScale,   0.000f,  (UVScale * Er_minus_Ey_Range),
    YScale, (-1.0f * UVScale * Eb_minus_Ey_Range * Kb_over_Kg),  (-1.0f * UVScale * Er_minus_Ey_Range * Kr_over_Kg),
    YScale, (UVScale * Eb_minus_Ey_Range),  0.000f,
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
  
  // Saturate normalzied linear (R G B) to range [0.0, 1.0]
  
  Rn = saturatef(Rn);
  Gn = saturatef(Gn);
  Bn = saturatef(Bn);
  
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
  const int debug = 0;
  
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
  const int debug = 0;
  
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
    }
    
    Rn = sRGB_nonLinearNormToLinear(Rn);
    Gn = sRGB_nonLinearNormToLinear(Gn);
    Bn = sRGB_nonLinearNormToLinear(Bn);
    
    if (debug) {
      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
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
  const int debug = 0;
  
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

#endif // _BT709_H
