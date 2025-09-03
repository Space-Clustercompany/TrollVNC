#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary*)opts {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor systemBackgroundColor];
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
  label.text = @"MoonlightServer (stub) installed via TrollStore.\nBuild succeeded.";
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    [label.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:20.0],
    [label.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-20.0]
  ]];
  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
