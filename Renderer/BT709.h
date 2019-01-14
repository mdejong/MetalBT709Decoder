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

#define APPLE_GAMMA_ADJUST (1.961f)

/*

// Exact same linear range, then a reduce log (kind off off)

static inline
float AppleGamma196_sloped_nonLinearNormToLinear(float normV) {
  
  if (normV < 0.081f) {
    normV *= (1.0f / 4.5f);
  } else {
    const float a = 0.055f;
    const float gamma = APPLE_GAMMA_ADJUST;
    normV = (normV + a) * (1.0f / (1.0f + a));
    normV = pow(normV, gamma);
  }
  
  return normV;
}

static inline
float AppleGamma196_sloped_linearNormToNonLinear(float normV) {
  
  if (normV < 0.018f) {
    normV *= 4.5f;
  } else {
    const float a = 0.055f;
    const float gamma = 1.0f / APPLE_GAMMA_ADJUST;
    normV = (1.0f + a) * pow(normV, gamma) - a;
  }
  
  return normV;
}
 
*/

/*

// About 1/2 the difference between the log 1.961 amount
// and the 2.2 amount at X = 0.081
// halfway between (0.081,0.018) and (0.081,0.00706)

static inline
float AppleGamma196_sloped_nonLinearNormToLinear(float normV) {
  const float xIntercept = 0.14259f;
  const float yIntercept = 0.02194f;
  
  if (normV < xIntercept) {
    normV *= (1.0f / 6.5f);
  } else {
    const float gamma = APPLE_GAMMA_ADJUST;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

static inline
float AppleGamma196_sloped_linearNormToNonLinear(float normV) {
  const float xIntercept = 0.14259f;
  const float yIntercept = 0.02194f;
  
  if (normV < yIntercept) {
    normV *= 6.5f;
  } else {
    const float gamma = 1.0f / APPLE_GAMMA_ADJUST;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

*/

// Straight line segment passing through the point where log(1.961)
// would cross the x cutoff of the encoding at (0.081,0.00706)

static inline
float AppleGamma196_sloped_nonLinearNormToLinear(float normV) {
  const float xIntercept = 0.018f;
  const float yIntercept = 0.007237f;
  
  if (normV < xIntercept) {
    normV *= (1.0f / 11.193f);
  } else {
    const float gamma = APPLE_GAMMA_ADJUST;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

static inline
float AppleGamma196_sloped_linearNormToNonLinear(float normV) {
  const float xIntercept = 0.018f;
  const float yIntercept = 0.007237f;
  
  if (normV < yIntercept) {
    normV *= 11.193f;
  } else {
    const float gamma = 1.0f / APPLE_GAMMA_ADJUST;
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

// https://forums.creativecow.net/thread/2/1131717

// Apple seems to boost sRGB values after converting
// to linear. This seems to adjust the sRGB
// input so that when decoded the pixel intensities
// will more closely match the original sRGB values.

// CRT gamma / gamma boost ⇒ 2.45 / 1.25 = 1.96

// What is weird is that the boosted values seem to
// very closely fit a linear boost with 1.0/2.2
// as the amount. Would this amount then reduced
// by the 1.961 leave the boosted sRGB above the
// tv levels?

//#define APPLE_GAMMA_SIMPLIFIED_ADJUST 1.96f
//#define APPLE_GAMMA_SIMPLIFIED_ADJUST 1.961f

// Non-Linear to linear adjustment for vImage encoded video

// Better at 75% but off at low values
//#define APPLE_GAMMA_ADJUST_VIDEO 2.25f

//#define APPLE_GAMMA_ADJUST_VIDEO (1.0f/0.4509f) // aka 2.217

// (2.2 / 1.961) = 1.1218765935747068

// When sRGB is converted to linear, this
// boost amount is applied after the value
// in linear but before the value is passed
// through the BT.709 matrix transform.
//
// gamma = (1.0f / 0.8782f) // aka 1.1386
// pow(x, gamma)
//

// Converting from sRGB on every value to liner seems
// to have a best fit at 2.233
//
// With low values [0.0, 0.081]

// a*x
// line fit : a = 0.08365 = 11.95 slope? This is near sRGB 12.96 low slope

// a*x + b
// line 0.08692
// b 0.0001836

/*

//#define APPLE_GAMMA_ADJUST_BOOST_LINEAR 1.14f
#define APPLE_GAMMA_ADJUST_BOOST_LINEAR (1.0f / 0.8782f) // aka 1.1386

//static inline
//float AppleGamma196_boost_linearNorm(float normV) {
//  const float gamma = 1.0f / APPLE_GAMMA_ADJUST_BOOST_LINEAR;
//  normV = pow(normV, gamma);
//  return normV;
//}
//

static inline
float AppleGamma196_unboost_linearNorm(float normV) {
  const float gamma = APPLE_GAMMA_ADJUST_BOOST_LINEAR;
  normV = pow(normV, gamma);
  return normV;
}

*/

// Simple Apple boost with Gamma 2.2 up, then
// when 2.2 is removed the RGB colors are returned to
// identity and video colors are also reduced.



// A previous fit attempted to adjust sRGB
// to the boosted value while it was in sRGB
// gamma adjusted space. That gamma was 2.55
//
// Best Fit: 2.549 from http://www.lelandstanfordjunior.com/quickfit.html

//#define APPLE_GAMMA_ADJUST_BOOST_SRGB 2.549f
//
//// Boosting a sRGB value directly before converting
//// sRGB to linear.
//
//static inline
//float AppleGamma196_boost_srgbNorm(float normV) {
//  const float gamma = 1.0f / APPLE_GAMMA_ADJUST_BOOST_SRGB;
//  normV = pow(normV, gamma);
//  return normV;
//}
//
//static inline
//float AppleGamma196_unboost_srgbNorm(float normV) {
//  const float gamma = APPLE_GAMMA_ADJUST_BOOST_SRGB;
//  normV = pow(normV, gamma);
//  return normV;
//}

/*

// This simplified adjustment uses a pow()
// to convert a 2 stage BT.709 encoded value
// to a linear light value but without a
// linear segment.

#define APPLE_GAMMA_SIMPLIFIED_ADJUST 1.961f

// Apple gamma adjustment that seems to remove "dark room"
// levels from BT.709.

static inline
float AppleGamma196_nonLinearNormToLinear(float normV) {
  const float gamma = APPLE_GAMMA_SIMPLIFIED_ADJUST;
  normV = pow(normV, gamma);
  return normV;
}
 
*/

/*

// Use simple 2.2 gamma when operating on BGRA pixels
// since these should be returned to identity values
// when video data is dropped back down by 2.2

// Is this 2.222... aka (1.0 / 0.45) ?

#define BT709_G22_GAMMA 2.2f
// better fit?
//#define BT709_G22_GAMMA 2.2177f
//#define BT709_G22_GAMMA 2.219f

static inline
float BT709_G22_nonLinearNormToLinear(float normV) {
  const float gamma = BT709_G22_GAMMA;
  normV = pow(normV, gamma);
  return normV;
}

// Convert a linear log value to a non-linear value.
// Note that normV must be normalized in the range [0.0 1.0]

static inline
float BT709_G22_linearNormToNonLinear(float normV) {
  const float gamma = 1.0f / BT709_G22_GAMMA;
  normV = pow(normV, gamma);
  return normV;
}

*/

/*

// Undo a boost to sRGB values by applying a 2.2 like gamma.
// This should return a sRGB boosted value to linear when
// a 2.2 monitor gamma is applied.
//
// Note that converting from non-linear to linear
// with a form like pow(x, Gamma) will reduce the signal strength.

#define BT709_B22_GAMMA 2.233f
//#define BT709_B22_MULT (1.0f / 0.08365f) // about 11.95
//#define BT709_B22_MULT 8.85f
#define BT709_B22_MULT 9.05f

// f1 = x / BT709_B22_MULT
// f2 = pow(x, 2.233)
// intercept = ( 0.16754, 0.01851 )

static inline
float BT709_B22_nonLinearNormToLinear(float normV) {
  const float xCrossing = 0.16754f;
  
  if (normV < xCrossing) {
    //normV *= (1.0f / BT709_B22_MULT); // 27
    //normV *= (1.0f / 12.92f); // 25
    //normV *= (1.0f / 10.0f); // 30
    //normV *= (1.0f / 8.0f); // 34
    // Between 8.5 and 9.5 ?
    //normV *= (1.0f / 9.0f); // 31.6 -> 32
    //normV *= (1.0f / 9.5f); // 30.6 -> 31
    //normV *= (1.0f / 8.5f); // 32.7 -> 33
    //normV *= (1.0f / 8.75f); // 32.2 -> 32
    //normV *= (1.0f / 8.85f); // 32.0039 -> 32
    //normV *= (1.0f / BT709_B22_MULT); // 27
    // Between 8.5 -> 8.9
    //normV *= (1.0f / 8.9f); // 26.7 -> 27
    //normV *= (1.0f / 8.95f); // 26.6 -> 27
    //normV *= (1.0f / 8.99f); // 26.5 -> 27
    //normV *= (1.0f / 9.0f); // 26.5 -> 27
    //normV *= (1.0f / 9.1f); // 26.3 -> 26
    //normV *= (1.0f / 9.05f); // 26.4 -> 26
    
    normV *= (1.0f / BT709_B22_MULT);
  } else {
    const float gamma = BT709_B22_GAMMA;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

// Boost a linear signal with a Gamma 2.2 like piecewise function.
// Note that converting from linear to non-linear
// with a form like pow(x, 1/Gamma) will boost the signal up.

// f1 = x * BT709_B22_MULT
// f2 = pow(x, 1.0 / 2.233)
// intercept = ( 0.01851, 0.16754 )

static inline
float BT709_B22_linearNormToNonLinear(float normV) {
  const float xCrossing = 0.01851f;
  
  if (normV < xCrossing) {
    normV *= BT709_B22_MULT;
  } else {
    const float gamma = 1.0f / BT709_B22_GAMMA;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

*/
 
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

// This "boosted" call just encodes the sRGB values
// as already non-linear gamma adjusted into the SRGB colorspace.
// This is what happens w

// This boosted sRGB conversion is an Apple specific
// method of increasing an input sRGB signal to
// account for the fact that at decode time a
// drop by 2.2 will be applied.

static inline
int BT709_boosted_from_sRGB_convertRGBToYCbCr(
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
  
  // Pass sRGB values directly in as R', G', B' in this "boosted" call
  
//  // Convert non-linear sRGB to linear
//
//  if (applyGammaMap) {
//    if (debug) {
//      printf("pre  to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
//
//      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
//    }
//
//    Rn = sRGB_nonLinearNormToLinear(Rn);
//    Gn = sRGB_nonLinearNormToLinear(Gn);
//    Bn = sRGB_nonLinearNormToLinear(Bn);
//
//    if (debug) {
//      printf("post to linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
//
//      printf("byte range     Rn Gn Bn : %.4f %.4f %.4f\n", Rn*255.0f, Gn*255.0f, Bn*255.0f);
//    }
//  }
  
  return BT709_convertNonLinearRGBToYCbCr(Rn, Gn, Bn, YPtr, CbPtr, CrPtr);
}

// Convert from BT.709 YCbCr to unboosted linear RGB as a normalized float

static inline
int BT709_boosted_convertYCbCrToLinearRGB(
                                  int Y,
                                  int Cb,
                                  int Cr,
                                  float *RPtr,
                                  float *GPtr,
                                  float *BPtr)
{
  BT709_convertYCbCrToNonLinearRGB(Y, Cb, Cr, RPtr, GPtr, BPtr);
  
  return 0;
}

// Convert BT.709 to sRGB in non-linear space

static inline
int BT709_boosted_to_sRGB_convertYCbCrToRGB(
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
  
  // When the original input was known to be sRGB "boosted"
  // values then the non-linear values returned are actually
  // sRGB already.
  
  BT709_convertYCbCrToNonLinearRGB(Y, Cb, Cr, &Rn, &Gn, &Bn);
  
  // Convert linear RGB to non-linear sRGB
  
//  if (applyGammaMap) {
//    if (debug) {
//      printf("pre  to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
//    }
//
//    Rn = sRGB_linearNormToNonLinear(Rn);
//    Gn = sRGB_linearNormToNonLinear(Gn);
//    Bn = sRGB_linearNormToNonLinear(Bn);
//
//    if (debug) {
//      printf("post to non-linear Rn Gn Bn : %.4f %.4f %.4f\n", Rn, Gn, Bn);
//    }
//  }
  
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
