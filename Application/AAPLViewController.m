/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

#import <QuartzCore/QuartzCore.h>

@implementation AAPLViewController
{
#if TARGET_OS_IOS
    IBOutlet UIImageView *imageView;
#else
    IBOutlet NSImageView *imageView;
#endif // TARGET_OS_IOS
  
    IBOutlet MTKView *mtkView;

    AAPLRenderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    BOOL alphaImageBackground = FALSE;
    // If alphaImageBackground is FALSE, background can be black or white
    BOOL blackBackground = FALSE;

#if TARGET_OS_IOS
    if (alphaImageBackground) {
        UIImage *alphaImg = [UIImage imageNamed:@"AlphaBGHalf.png"];
        assert(alphaImg);
        UIColor *patternColor = [UIColor colorWithPatternImage:alphaImg];
        imageView.backgroundColor = patternColor;
    } else {
        UIColor *color;
        if (blackBackground == FALSE) {
            color = [UIColor whiteColor];
        } else if (blackBackground) {
            color = [UIColor blackColor];
        }
        imageView.backgroundColor = color;
    }
#else
    // MacOSX
    if (alphaImageBackground) {
        NSImage *alphaImg = [NSImage imageNamed:@"AlphaBG.png"];
        assert(alphaImg);
        NSColor *patternColor = [NSColor colorWithPatternImage:alphaImg];
        [imageView setWantsLayer:YES];
        imageView.layer.backgroundColor = patternColor.CGColor;
    } else {
        NSColor *color;
        if (blackBackground == FALSE) {
            color = [NSColor whiteColor];
        } else if (blackBackground) {
            color = [NSColor blackColor];
        }
        imageView.layer.backgroundColor = color.CGColor;
    }
#endif // TARGET_OS_IOS

    mtkView.device = MTLCreateSystemDefaultDevice();

    if(!mtkView.device)
    {
        NSLog(@"Metal is not supported on this device");
        return;
    }

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:mtkView];

    if(!_renderer)
    {
        NSLog(@"Renderer failed initialization");
        return;
    }

    // Initialize our renderer with the view size
    [_renderer mtkView:mtkView drawableSizeWillChange:mtkView.drawableSize];

    mtkView.delegate = _renderer;
}

@end
