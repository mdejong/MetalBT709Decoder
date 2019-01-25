//
//  ViewController.m
//  AVPlayerDecodeiOS
//
//  Created by Mo DeJong on 1/24/19.
//  Copyright © 2019 Apple. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface ViewController ()

@property (nonatomic, retain) AVPlayerViewController *avPlayerViewcontroller;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  UIView *view = self.view;
  
  NSString *resourceName = @"QuickTime_Test_Pattern_HD.mov";
  
  NSString* movieFilePath = [[NSBundle mainBundle] pathForResource:resourceName ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  
  NSURL *fileURL = [NSURL fileURLWithPath:movieFilePath];
  
  AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
  
  playerViewController.player = [AVPlayer playerWithURL:fileURL];
  
  self.avPlayerViewcontroller = playerViewController;
  
  [self resizePlayerToViewSize];
  
  [view addSubview:playerViewController.view];
  
  view.autoresizesSubviews = TRUE;
}

- (void) resizePlayerToViewSize
{
  CGRect frame = self.view.frame;
  
  NSLog(@"frame size %d, %d", (int)frame.size.width, (int)frame.size.height);
  
  self.avPlayerViewcontroller.view.frame = frame;
}

@end
