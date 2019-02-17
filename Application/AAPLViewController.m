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

#if TARGET_OS_IOS
    UIImage *alphaImg = [UIImage imageNamed:@"AlphaBGHalf.png"];
    assert(alphaImg);
    UIColor *patternColor = [UIColor colorWithPatternImage:alphaImg];
    imageView.backgroundColor = patternColor;
#else
    // MacOSX
    NSImage *alphaImg = [NSImage imageNamed:@"AlphaBG.png"];
    assert(alphaImg);
    NSColor *patternColor = [NSColor colorWithPatternImage:alphaImg];
    [imageView setWantsLayer:YES];
    imageView.layer.backgroundColor = patternColor.CGColor;
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
