# MetalBT709Decoder

Proper rendering of BT.709 encoded H.264 image using Metal

## Overview

This project is adapted from the Apple BasicTexturing example code.

## Status

This Metal logic will render BT.709 YCbCr data to a sRGB texture. This implementation takes care to get gamma decoding right according to the BT.709 specification.

## Decoding Speed

The decoder targets the highest quality render possible given a H.264 source with 4:2:0 YCbCr encoding.

## Implementation

See AAPLRenderer.m and AAPLShaders.metal for the core GPU rendering logic.

