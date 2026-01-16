#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

static BOOL gEnabled = NO;
static UIWindow *gOverlayWindow = nil;
static UIButton *gBtn = nil;

static NSString * const kEnabledKey = @"tsinject_enabled";
static NSString * const kPosXKey    = @"tsinject_btn_x";
static NSString * const kPosYKey    = @"tsinject_btn_y";

static UIWindow *TSKeyWindow(void) {
    // iOS 13+ 多 Scene：优先找前台激活 scene 的 keyWindow
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        // 有些情况下没有 isKeyWindow，但 windows 里第一个也能用
        if (ws.windows.count > 0) return ws.windows.firstObject;
    }

    // 兜底：直接用 UIApplication.windows（不使用 keyWindow API）
    if (UIApplication.sharedApplication.windows.count > 0) {
        return UIApplication.sharedApplication.windows.firstObject;
    }
    return nil;
}

static UIViewController *TopVC(void) {
    UIWindow *w = TSKeyWindow();
    if (!w) return nil;

    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void UpdateTitle(void) {
    [gBtn setTitle:(gEnabled ? @"ON" : @"OFF") forState:UIControlStateNormal];
}

static void Toggle(void) {
    gEnabled = !gEnabled;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:gEnabled forKey:kEnabledKey];
    [ud synchronize];
    UpdateTitle();

    // TODO: put your feature toggle logic here
}

@interface DragTarget : NSObject
@end

@implementation DragTarget
- (void)tap { Toggle(); }

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (!v) return;

    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        [ud setDouble:v.center.x forKey:kPosXKey];
        [ud setDouble:v.center.y forKey:kPosYKey];
        [ud synchronize];
    }
}
@end

static void SetupUI(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    gEnabled = [ud boolForKey:kEnabledKey];

    CGRect screen = UIScreen.mainScreen.bounds;

    // Bind to active scene (better on iOS 15+)
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive &&
            [s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    gOverlayWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:screen];
    gOverlayWindow.frame = screen;
    gOverlayWindow.windowLevel = UIWindowLevelAlert + 999;
    gOverlayWindow.backgroundColor = UIColor.clearColor;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gOverlayWindow.rootViewController = vc;

    gBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gBtn.bounds = CGRectMake(0, 0, 60, 36);
    gBtn.layer.cornerRadius = 10;
    gBtn.clipsToBounds = YES;
    gBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    [gBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];

    double x = [ud doubleForKey:kPosXKey];
    double y = [ud doubleForKey:kPosYKey];
    CGPoint center = (x > 10 && y > 10) ? CGPointMake(x, y) : CGPointMake(screen.size.width - 50, 140);
    gBtn.center = center;

    UpdateTitle();

    DragTarget *t = [DragTarget new];
    [gBtn addTarget:t action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:t action:@selector(pan:)];
    [gBtn addGestureRecognizer:pan];

    // 强引用 target，避免被释放
    objc_setAssociatedObject(gBtn, "ts_target", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [vc.view addSubview:gBtn];
    gOverlayWindow.hidden = NO;
}

__attribute__((constructor))
static void Entry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // haptic: proves dylib loaded
        AudioServicesPlaySystemSound(1519);

        // delay to ensure UI is ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = TopVC();
            if (vc) {
                UIAlertController *a =
                [UIAlertController alertControllerWithTitle:@"提示"
                                                    message:@"注入成功"
                                             preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
                [vc presentViewController:a animated:YES completion:nil];
            }
            SetupUI();
        });
    });
}
