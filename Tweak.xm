#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

static BOOL gEnabled = NO;
static UIButton *gBtn = nil;

static NSString * const kEnabledKey = @"tsinject_enabled";
static NSString * const kPosXKey    = @"tsinject_btn_x";
static NSString * const kPosYKey    = @"tsinject_btn_y";

#pragma mark - Helpers

static UIWindow *TSKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count > 0) return ws.windows.firstObject;
    }
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

#pragma mark - Passthrough Window

@interface TSPassthroughWindow : UIWindow
@end

@implementation TSPassthroughWindow
// 只让按钮区域吃到触摸，其他地方全部穿透
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;

    // 如果点到按钮或按钮子视图 -> 接收
    if (gBtn && (hit == gBtn || [hit isDescendantOfView:gBtn])) {
        return hit;
    }
    // 其余区域 -> 穿透到下面（包括 Alert 的 OK）
    return nil;
}
@end

#pragma mark - Drag Target

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

#pragma mark - UI Setup

static void SetupUI(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    gEnabled = [ud boolForKey:kEnabledKey];

    CGRect screen = UIScreen.mainScreen.bounds;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive &&
            [s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    TSPassthroughWindow *overlay =
        scene ? [[TSPassthroughWindow alloc] initWithWindowScene:scene]
              : [[TSPassthroughWindow alloc] initWithFrame:screen];

    overlay.frame = screen;

    // 关键：不要高于系统弹窗（否则 OK 点不到）
    // 用 StatusBar + 1 足够让按钮浮在最上，但不盖住 Alert
    overlay.windowLevel = UIWindowLevelStatusBar + 1;
    overlay.backgroundColor = UIColor.clearColor;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    overlay.rootViewController = vc;

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
    objc_setAssociatedObject(gBtn, "ts_target", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [vc.view addSubview:gBtn];

    overlay.hidden = NO;

    // 强引用 window（否则可能被释放导致失效）
    objc_setAssociatedObject(UIApplication.sharedApplication, "ts_overlay_window", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

__attribute__((constructor))
static void Entry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(1519);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = TopVC();
            if (vc) {
                UIAlertController *a =
                [UIAlertController alertControllerWithTitle:@"本产品严禁用于赌博"
                                                    message:@"透视注入成功 请使用悬浮窗开关功能"
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
