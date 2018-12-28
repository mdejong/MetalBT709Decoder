/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of a very simple container for image data
*/

#import "AAPLImage.h"
#include <simd/simd.h>

@implementation AAPLImage

-(nullable instancetype) initWithTGAFileAtLocation:(nonnull NSURL *)tgaLocation
{
    self = [super init];
    if(self)
    {
        NSString * fileExtension = tgaLocation.pathExtension;

        if(!([fileExtension caseInsensitiveCompare:@"TGA"] == NSOrderedSame))
        {
            NSLog(@"This image loader only loads TGA files");
            return nil;
        }

        // Structure fitting the layout of a TGA header containing image metadata.
        typedef struct __attribute__ ((packed)) TGAHeader
        {
            uint8_t  IDSize;         // Size of ID info following header
            uint8_t  colorMapType;   // Whether this is a paletted image
            uint8_t  imageType;      // type of image 0=none, 1=indexed, 2=rgb, 3=grey, +8=rle packed

            int16_t  colorMapStart;  // Offset to color map in palette
            int16_t  colorMapLength; // Number of colors in palette
            uint8_t  colorMapBpp;    // number of bits per palette entry

            uint16_t xOffset;        // Number of pixels to the right to start of image
            uint16_t yOffset;        // Number of pixels down to start of image
            uint16_t width;          // Width in pixels
            uint16_t height;         // Height in pixels
            uint8_t  bitsPerPixel;   // Bits per pixel 8,16,24,32
            uint8_t  descriptor;     // Descriptor bits (flipping, etc)
        } TGAHeader;

        NSError * error;

        // Copy the entire file to this fileData variable
        NSData *fileData = [[NSData alloc] initWithContentsOfURL:tgaLocation
                                                         options:0x0
                                                           error:&error];

        if (!fileData)
        {
            NSLog(@"Could not open TGA File:%@", error.localizedDescription);
            return nil;
        }

        TGAHeader *tgaInfo = (TGAHeader *) fileData.bytes;

        if(tgaInfo->imageType != 2) {
            NSLog(@"This image loader only supports non-compressed BGR(A) TGA files");
            return nil;
        }

        if(tgaInfo->colorMapType)
        {
            NSLog(@"This image loader doesn't support TGA files with a colormap");
            return nil;
        }

        if(tgaInfo->xOffset || tgaInfo->yOffset)
        {
            NSLog(@"This image loader doesn't support TGA files with offsets");
            return nil;
        }

        if(!(tgaInfo->bitsPerPixel == 32 || tgaInfo->bitsPerPixel == 24))
        {
            NSLog(@"This image loader only supports 24-bit and 32-bit TGA files");
            return nil;
        }

        if(tgaInfo->bitsPerPixel == 32)
        {
            if((tgaInfo->descriptor & 0xF) != 8)
            {
                NSLog(@"Image loader only supports 32-bit TGA files with 8 bits of alpha");
            }
        }
        else if(tgaInfo->descriptor)
        {
            NSLog(@"Image loader only supports 24-bit TGA files with the default descriptor");
            return nil;
        }

        _width = tgaInfo->width;
        _height = tgaInfo->height;

        // Calculate the byte size of our image data.  Since we store our image data as
        //   32-bits per pixel BGRA data
        NSUInteger dataSize = _width * _height * 4;

        if(tgaInfo->bitsPerPixel == 24)
        {
            // Metal will not understand an image with 24-bpp format so we must convert our
            //   TGA data from the 24-bit BGR format to a 32-bit BGRA format that Metal does
            //   understand (as MTLPixelFormatBGRA8Unorm)

            NSMutableData *mutableData = [[NSMutableData alloc] initWithLength:dataSize];

            // TGA spec says the image data is immediately after the header and the ID so set
            //   the pointer to file's start + size of the header + size of the ID
            // Initialize a source pointer with the source image data that's in BGR form
            uint8_t *srcImageData = ((uint8_t*)fileData.bytes +
                                     sizeof(TGAHeader) +
                                     tgaInfo->IDSize);

            // Initialize a destination pointer to which you'll store the converted BGRA
            // image data
            uint8_t *dstImageData = mutableData.mutableBytes;

            // For every row of the image
            for(NSUInteger y = 0; y < _height; y++)
            {
                // For every column of the current row
                for(NSUInteger x = 0; x < _width; x++)
                {
                    // Calculate the index for the first byte of the pixel you're
                    // converting in both the source and destination images
                    NSUInteger srcPixelIndex = 3 * (y * _width + x);
                    NSUInteger dstPixelIndex = 4 * (y * _width + x);

                    // Copy BGR channels from the source to the destination
                    // Set the alpha channel of the destination pixel to 255
                    dstImageData[dstPixelIndex + 0] = srcImageData[srcPixelIndex + 0];
                    dstImageData[dstPixelIndex + 1] = srcImageData[srcPixelIndex + 1];
                    dstImageData[dstPixelIndex + 2] = srcImageData[srcPixelIndex + 2];
                    dstImageData[dstPixelIndex + 3] = 255;
                }
            }
            _data = mutableData;
        }
        else
        {
            // Metal will understand an image with 32-bpp format so we must only create
            //   an NSData object with the file's image data

            // TGA spec says the image data is immediately after the header and the ID so set
            //   the pointer to file's start + size of the header + size of the ID
            uint8_t *srcImageData = ((uint8_t*)fileData.bytes +
                                     sizeof(TGAHeader) +
                                     tgaInfo->IDSize);

            _data = [[NSData alloc] initWithBytes:srcImageData
                                           length:dataSize];
        }
    }

    return self;
}

@end
