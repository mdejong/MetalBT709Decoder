//
//  sRGB.h
//
//  Created by Moses DeJong on 12/14/18.
//
//  Header only interface to mapping for sRGB to linear
//  and sRGB to XYZ.
//
//  http://www.color.org/srgb.pdf
//
//  Licensed under BSD terms.

#if !defined(_SRGB_H)
#define _SRGB_H

// saturate limits the range to [0.0, 1.0]

static inline
float saturatef(float v) {
  if (v < 0.0f) {
    return 0.0f;
  }
  if (v > 1.0f) {
    return 1.0f;
  }
  return v;
}

// Convert a byte range integer [0 255] into a normalized float
// using a multiply operation.

static inline
float byteNorm(int val)
{
  return val * (1.0f/255.0f);
}

// sRGB

// Convert a non-linear log value to a linear value.
// Note that normV must be normalized in the range [0.0 1.0].

static inline
float sRGB_nonLinearNormToLinear(float normV)
{
  if (normV <= 0.04045f) {
    normV *= (1.0f / 12.92f);
  } else {
    const float a = 0.055f;
    const float gamma = 2.4f;
    //const float gamma = 1.0f / (1.0f / 2.4f);
    normV = (normV + a) * (1.0f / (1.0f + a));
    normV = pow(normV, gamma);
  }
  
  return normV;
}

// Convert a linear log value to a non-linear value.
// Note that normV must be normalized in the range [0.0 1.0]

static inline
float sRGB_linearNormToNonLinear(float normV) {
  
  if (normV <= 0.0031308f) {
    normV *= 12.92f;
  } else {
    const float a = 0.055f;
    const float gamma = 1.0f / 2.4f; // 0.4166...
    normV = (1.0f + a) * pow(normV, gamma) - a;
  }

  return normV;
}

// sRGB to XYZ colorspace conversion (CIE 1931)

static inline
int sRGB_convertRGBToXYZ(
                         int R,
                         int G,
                         int B,
                         float *XPtr,
                         float *YPtr,
                         float *ZPtr,
                         int applyGammaMap)
{
  const int debug = 0;
  
#if defined(DEBUG)
  assert(XPtr);
  assert(YPtr);
  assert(ZPtr);
  
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
#endif // DEBUG
  
  if (debug) {
    printf("R G B : %3d %3d %3d\n", R, G, B);
  }
  
  // Normalize
  
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
  
  if (debug) {
    printf("Rn %.4f\n", Rn);
    printf("Gn %.4f\n", Gn);
    printf("Bn %.4f\n", Bn);
  }
  
  // sRGB -> XYZ
  
  const
  float Matrix[] = {
    0.4124f, 0.3576f, 0.1805f,
    0.2126f, 0.7152f, 0.0722f,
    0.0193f, 0.1192f, 0.9505f
  };
  
  if (debug) {
    printf("Mat 3x3:\n");
    printf("%.4f %.4f %.4f\n", Matrix[0], Matrix[1], Matrix[2]);
    printf("%.4f %.4f %.4f\n", Matrix[3], Matrix[4], Matrix[5]);
    printf("%.4f %.4f %.4f\n", Matrix[6], Matrix[7], Matrix[8]);
  }
  
  // Matrix multiply operation
  //
  // rgb = Matrix * (Rn,Gn,Bn)
  
  // Convert input X, Y, Z float values
  
  float X = (Rn * Matrix[0]) + (Gn * Matrix[1]) + (Bn * Matrix[2]);
  float Y = (Rn * Matrix[3]) + (Gn * Matrix[4]) + (Bn * Matrix[5]);
  float Z = (Rn * Matrix[6]) + (Gn * Matrix[7]) + (Bn * Matrix[8]);
  
  if (debug) {
    printf("X %.4f\n", X);
    printf("Y %.4f\n", Y);
    printf("Z %.4f\n", Z);
  }
  
  // Scale in terms of (0.9505, 1.0000, 1.08899)
  
  X *= (1.0f / 0.9505f);
  //Y *= 1.0f;
  Z *= (1.0f / 1.08899f);

  if (debug) {
    printf("scaled to whitepoint\n");
    
    printf("X %.4f\n", X);
    printf("Y %.4f\n", Y);
    printf("Z %.4f\n", Z);
  }
  
  X = saturatef(X);
  Y = saturatef(Y);
  Z = saturatef(Z);
  
  // Return float value in XYZ linear colorspace
  
  *XPtr = X;
  *YPtr = Y;
  *ZPtr = Z;
  
  return 0;
}

// Convert from XYZ (linear gamma) to sRGB (pow gamma)

static inline
int sRGB_convertXYZToRGB(
                         float X,
                         float Y,
                         float Z,
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
    printf("X Y Z : %.3f %.3f %.3f\n", X, Y, Z);
  }
  
  // Since XYZ colorspace is always linear, no gamma correction
  // step is needed before processing values.
  
  // Undo Scale in terms of (0.9505, 1.0000, 1.08899)
  
  X *= 0.9505f;
  //Y *= 1.0f;
  Z *= 1.08899f;
  
  // XYZ -> sRGB
  // http://www.ryanjuckett.com/programming/rgb-color-space-conversion/
  
  const
  float Matrix[3*3] = {
    3.2410f, -1.5374f, -0.4986f,
   -0.9692f,  1.8760f,  0.0416f,
    0.0556f, -0.2040f,  1.0570f
  };

  if (debug) {
    printf("Mat 3x3:\n");
    printf("%.7f %.7f %.7f\n", Matrix[0], Matrix[1], Matrix[2]);
    printf("%.7f %.7f %.7f\n", Matrix[3], Matrix[4], Matrix[5]);
    printf("%.7f %.7f %.7f\n", Matrix[6], Matrix[7], Matrix[8]);
  }
  
  // Matrix multiply operation
  //
  // rgb = Matrix * (Xn,Yn,Zn)
  
  // Convert input Y, Cb, Cr to normalized float values
  
  float Rn = (X * Matrix[0]) + (Y * Matrix[1]) + (Z * Matrix[2]);
  float Gn = (X * Matrix[3]) + (Y * Matrix[4]) + (Z * Matrix[5]);
  float Bn = (X * Matrix[6]) + (Y * Matrix[7]) + (Z * Matrix[8]);
  
  if (debug) {
    printf("unclamped:\n");
    printf("Rn %.4f\n", Rn);
    printf("Gn %.4f\n", Gn);
    printf("Bn %.4f\n", Bn);
  }
  
  // Saturate limits range to [0.0, 1.0]
  
  Rn = saturatef(Rn);
  Gn = saturatef(Gn);
  Bn = saturatef(Bn);
  
  // Convert linear RGB to sRGB log space
  
  if (applyGammaMap) {
    // Adjust int values in the input range to gamma mapping over same range
    
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
  
  // Round to nearest int value in range [0, 255]
  
  int R = (int) round(Rn * 255.0f);
  int G = (int) round(Gn * 255.0f);
  int B = (int) round(Bn * 255.0f);
  
  if (debug) {
    printf("scaled up to byte range:\n");
    printf("Rn %.4f\n", Rn * 255.0f);
    printf("Gn %.4f\n", Gn * 255.0f);
    printf("Bn %.4f\n", Bn * 255.0f);
    
    printf("rounded to int:\n");
    printf("X %3d\n", R);
    printf("Y %3d\n", G);
    printf("Z %3d\n", B);
  }
  
  assert(R >= 0 && R <= 255);
  assert(G >= 0 && G <= 255);
  assert(B >= 0 && B <= 255);
  
  *RPtr = R;
  *GPtr = G;
  *BPtr = B;
  
  return 0;
}

#endif // _SRGB_H
