#import <UIKit/UIKit.h>
extern "C" int gs_run_server(const char* name, struct GsPorts ports, struct GsVideoProfile prof);
struct GsPorts { int http, https, rtsp, video, control, audio; };
struct GsVideoProfile { int width, height, fps, bitrateKbps; bool hevc; };

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary*)opts {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor systemBackgroundColor];
  UILabel *label = [UILabel new];
  label.text = @"MoonlightServer (video-only) is running.\nFind this device in Moonlight.";
  label.numberOfLines = 0; label.textAlignment = NSTextAlignmentCenter; label.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    [label.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:20.0],
    [label.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-20.0]
  ]];
  self.window.rootViewController = vc; [self.window makeKeyAndVisible];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    struct GsPorts p = {47989, 47984, 48010, 47998, 47999, 48000};
    struct GsVideoProfile prof = {1920, 1080, 60, 12000, false};
    gs_run_server("Moonlight iPhone", p, prof);
  });
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}