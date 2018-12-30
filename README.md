# MetalBT709Decoder

Proper rendering of BT.709 encoded H.264 image using Metal

## Overview

This project is adapted from the Apple BasicTexturing example code. This render logic attempts to solve the gamma adjustment problem found in Apple provided render logic from example code like AVBasicVideoOutput (and other projects). While the rendering logic works just fine for video source encoded with linear gamma, real world BT.601 and BT.709 video uses a gamma function defined in the specifications that is non-linear. The result is that real world video authored properly WRT the BT.601 or BT.709 specifications will not render properly. This project addresses the problem by adding gamma adjustment to the shader logic and making use of a two pass render process to first decode non-linear values and then rescale sRGB encoded pixel values to render into an MTKView.

## Status

This Metal logic will render BT.709 YCbCr data to a sRGB texture. This implementation takes care to get gamma decoding right according to the BT.709 specification.

## Decoding Speed

The decoder targets the highest quality render possible given a H.264 source with 4:2:0 YCbCr encoding.

## Implementation

See AAPLRenderer.m and AAPLShaders.metal for the core GPU rendering logic.

