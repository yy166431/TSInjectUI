#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

#pragma mark - ====== Report to Server (no console needed) ======

static NSString * const TS_REPORT_URL   = @"http://159.75.14.193:8099/api/mjlog";
// 如果你服务端启用了 token（LOG_TOKEN），就把下面改成同一个值；如果没启用，留空即可
static NSString * const TS_REPORT_TOKEN = @"";  // e.g. @"your_token_here"

// 简单 ISO8601 时间
static NSString *TSNowISO8601(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [f stringFromDate:[NSDate date]];
}

static void TSReportJSON(NSDictionary *obj) {
    if (!TS_REPORT_URL.length) return;

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
    if (!data || err) return;

    NSURL *url = [NSURL URLWithString:TS_REPORT_URL];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    if (TS_REPORT_TOKEN.length) {
        [req setValue:TS_REPORT_TOKEN forHTTPHeaderField:@"X-Log-Token"];
    }

    req.HTTPBody = data;
    req.timeoutInterval = 5.0;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDataTask *task =
    [session dataTaskWithRequest:req completionHandler:^(__unused NSData *d, __unused NSURLResponse *r, __unused NSError *e) {}];
    [task resume];
}

static void TSReport(NSString *type, NSDictionary *payload) {
    NSMutableDictionary *obj = [NSMutableDictionary dictionary];
    obj[@"t"] = TSNowISO8601();
    obj[@"type"] = type ?: @"unknown";
    obj[@"payload"] = payload ?: @{};
    obj[@"device"] = UIDevice.currentDevice.model ?: @"";
    obj[@"sys"] = UIDevice.currentDevice.systemVersion ?: @"";
    if (TS_REPORT_TOKEN.length) obj[@"token"] = TS_REPORT_TOKEN; // 兼容 body token
    TSReportJSON(obj);
}

#pragma mark - ====== Globals ======

static BOOL gEnabled = NO;

static UIWindow *gOverlayWindow = nil;
static UIButton *gBtn = nil;

static UIView *gPanel = nil;
static UILabel *gTotalLabel = nil;

static NSString * const kEnabledKey = @"tsinject_enabled";
static NSString * const kPosXKey    = @"tsinject_btn_x";
static NSString * const kPosYKey    = @"tsinject_btn_y";

#pragma mark - ====== Mahjong (108 tiles / 27 kinds) ======

typedef NS_ENUM(NSInteger, TSMJTile) {
    // 万 1-9
    TSMJW1,TSMJW2,TSMJW3,TSMJW4,TSMJW5,TSMJW6,TSMJW7,TSMJW8,TSMJW9,
    // 筒 1-9
    TSMJT1,TSMJT2,TSMJT3,TSMJT4,TSMJT5,TSMJT6,TSMJT7,TSMJT8,TSMJT9,
    // 条 1-9
    TSMJS1,TSMJS2,TSMJS3,TSMJS4,TSMJS5,TSMJS6,TSMJS7,TSMJS8,TSMJS9,
    TSMJCount // 27
};

static int gLeft[TSMJCount];
static NSMutableArray<NSNumber *> *gUndoStack = nil;

static NSString *TileName(TSMJTile t) {
    static NSString *names[TSMJCount] = {
        @"1万",@"2万",@"3万",@"4万",@"5万",@"6万",@"7万",@"8万",@"9万",
        @"1筒",@"2筒",@"3筒",@"4筒",@"5筒",@"6筒",@"7筒",@"8筒",@"9筒",
        @"1条",@"2条",@"3条",@"4条",@"5条",@"6条",@"7条",@"8条",@"9条",
    };
    return names[(int)t];
}

static void ResetAll(void) {
    for (int i = 0; i < TSMJCount; i++) gLeft[i] = 4;
    if (!gUndoStack) gUndoStack = [NSMutableArray new];
    [gUndoStack removeAllObjects];
}

static int TotalLeft(void) {
    int s = 0;
    for (int i = 0; i < TSMJCount; i++) s += gLeft[i];
    return s; // 初始 108
}

static void MarkSeenIdx(int idx, int count) {
    if (idx < 0 || idx >= TSMJCount) return;
    if (count < 1) count = 1;
    if (!gUndoStack) gUndoStack = [NSMutableArray new];

    for (int i = 0; i < count; i++) {
        if (gLeft[idx] <= 0) break;
        gLeft[idx] -= 1;
        [gUndoStack addObject:@(idx)];
    }
}

static void MarkBackIdx(int idx, int count) {
    if (idx < 0 || idx >= TSMJCount) return;
    if (count < 1) count = 1;
    for (int i = 0; i < count; i++) {
        if (gLeft[idx] >= 4) break;
        gLeft[idx] += 1;
    }
}

static void UndoOne(void) {
    NSNumber *last = gUndoStack.lastObject;
    if (!last) return;
    [gUndoStack removeLastObject];
    MarkBackIdx((int)last.integerValue, 1);
}

#pragma mark - ====== Helpers ======

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
    if (!gBtn) return;
    [gBtn setTitle:(gEnabled ? @"ON" : @"OFF") forState:UIControlStateNormal];
}

#pragma mark - ====== Panel actions handler ======

@interface TSMJPanelHandler : NSObject
@end

void TSRefreshPanel(void);

@implementation TSMJPanelHandler

- (void)onTileTap:(UIButton *)sender {
    int idx = (int)(sender.tag - 1000);
    MarkSeenIdx(idx, 1);
    TSRefreshPanel();

    // 上报：手动点击扣牌
    TSReport(@"event", @{@"name": @"manual_tap", @"tile": @(idx), @"count": @1, @"left": @(gLeft[idx])});
}

- (void)onUndo:(id)sender {
    (void)sender;
    UndoOne();
    TSRefreshPanel();
    TSReport(@"event", @{@"name": @"manual_undo"});
}

- (void)onReset:(id)sender {
    (void)sender;
    ResetAll();
    TSRefreshPanel();
    TSReport(@"event", @{@"name": @"manual_reset"});
}

@end

static TSMJPanelHandler *GetPanelHandler(void) {
    TSMJPanelHandler *h = objc_getAssociatedObject(UIApplication.sharedApplication, "ts_panel_handler");
    if (!h) {
        h = [TSMJPanelHandler new];
        objc_setAssociatedObject(UIApplication.sharedApplication, "ts_panel_handler", h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return h;
}

#pragma mark - ====== Panel UI ======

void TSRefreshPanel(void) {
    if (!gPanel) return;
    if (gTotalLabel) gTotalLabel.text = [NSString stringWithFormat:@"剩余：%d / 108", TotalLeft()];

    for (UIView *v in gPanel.subviews) {
        if (![v isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)v;
        NSInteger t = b.tag - 1000;
        if (t < 0 || t >= TSMJCount) continue;

        NSString *title = [NSString stringWithFormat:@"%@\n%d", TileName((TSMJTile)t), gLeft[t]];
        [b setTitle:title forState:UIControlStateNormal];
        b.alpha = (gLeft[t] == 0 ? 0.35 : 1.0);
    }
}

static void BuildPanelIfNeeded(UIView *host) {
    if (gPanel) return;

    CGFloat W = 310;
    CGFloat H = 280;

    gPanel = [[UIView alloc] initWithFrame:CGRectMake(12, 130, W, H)];
    gPanel.layer.cornerRadius = 14;
    gPanel.clipsToBounds = YES;
    gPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];

    gTotalLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 200, 24)];
    gTotalLabel.textColor = UIColor.whiteColor;
    gTotalLabel.font = [UIFont boldSystemFontOfSize:16];
    [gPanel addSubview:gTotalLabel];

    TSMJPanelHandler *handler = GetPanelHandler();

    UIButton *undo = [UIButton buttonWithType:UIButtonTypeSystem];
    undo.frame = CGRectMake(W-60-12, 8, 60, 28);
    [undo setTitle:@"撤销" forState:UIControlStateNormal];
    [undo setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    undo.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    undo.layer.cornerRadius = 8;
    [undo addTarget:handler action:@selector(onUndo:) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:undo];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(W-60-12-60-10, 8, 60, 28);
    [reset setTitle:@"重置" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    reset.layer.cornerRadius = 8;
    [reset addTarget:handler action:@selector(onReset:) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:reset];

    // 3行×9列
    CGFloat top = 46;
    CGFloat padding = 10;
    CGFloat gap = 6;
    CGFloat btnW = (W - padding*2 - gap*8) / 9.0;
    CGFloat btnH = 66;

    for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 9; col++) {
            int t = row*9 + col; // 0..26
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.tag = 1000 + t;
            b.frame = CGRectMake(padding + col*(btnW+gap), top + row*(btnH+gap), btnW, btnH);
            b.titleLabel.numberOfLines = 2;
            b.titleLabel.textAlignment = NSTextAlignmentCenter;
            b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            b.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
            b.layer.cornerRadius = 10;
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [b addTarget:handler action:@selector(onTileTap:) forControlEvents:UIControlEventTouchUpInside];
            [gPanel addSubview:b];
        }
    }

    [host addSubview:gPanel];
    TSRefreshPanel();
}

static void ShowPanel(UIView *host) {
    if (!host) return;
    BuildPanelIfNeeded(host);
    if (!gPanel.superview) [host addSubview:gPanel];
    gPanel.hidden = NO;
    TSRefreshPanel();
}

static void HidePanel(void) {
    if (!gPanel) return;
    gPanel.hidden = YES;
}

#pragma mark - ====== Auto counter via notifications ======

static BOOL gAutoInstalled = NO;

static void InstallAutoObserverOnce(void) {
    if (gAutoInstalled) return;
    gAutoInstalled = YES;

    ResetAll();
    TSReport(@"event", @{@"name": @"auto_observer_installed"});

    // 自动扣牌通知：
    // [[NSNotificationCenter defaultCenter] postNotificationName:@"TS_MJ_SEEN"
    //                                                     object:nil
    //                                                   userInfo:@{@"tile": @(tileId), @"count": @(n)}];
    [[NSNotificationCenter defaultCenter] addObserverForName:@"TS_MJ_SEEN"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSDictionary *u = note.userInfo ?: @{};
        NSNumber *tile = u[@"tile"];
        NSNumber *count = u[@"count"];
        if (!tile) return;

        int tid = tile.intValue;
        int cnt = count ? count.intValue : 1;

        // 你也可以改成 OFF 也统计；当前：OFF 不统计
        if (!gEnabled) {
            TSReport(@"event", @{@"name": @"auto_seen_ignored_off", @"tile": @(tid), @"count": @(cnt)});
            return;
        }

        MarkSeenIdx(tid, cnt);
        TSRefreshPanel();
        TSReport(@"event", @{@"name": @"auto_seen", @"tile": @(tid), @"count": @(cnt), @"left": @(gLeft[tid])});
    }];

    // 开局重置
    [[NSNotificationCenter defaultCenter] addObserverForName:@"TS_MJ_RESET"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification * _Nonnull note) {
        ResetAll();
        TSRefreshPanel();
        TSReport(@"event", @{@"name": @"auto_reset"});
    }];
}

#pragma mark - ====== Passthrough Window ======

@interface TSPassthroughWindow : UIWindow
@end

@implementation TSPassthroughWindow
// 只让按钮/面板区域吃到触摸，其余全部穿透
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;

    if (gBtn && (hit == gBtn || [hit isDescendantOfView:gBtn])) return hit;
    if (gPanel && !gPanel.hidden && (hit == gPanel || [hit isDescendantOfView:gPanel])) return hit;

    return nil;
}
@end

#pragma mark - ====== Drag Target (button) ======

@interface DragTarget : NSObject
@end

static void Toggle(void);

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
        TSReport(@"event", @{@"name": @"btn_drag_end", @"x": @(v.center.x), @"y": @(v.center.y)});
    }
}
@end

#pragma mark - ====== Toggle ======

static void Toggle(void) {
    gEnabled = !gEnabled;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:gEnabled forKey:kEnabledKey];
    [ud synchronize];
    UpdateTitle();

    TSReport(@"event", @{@"name": @"toggle", @"enabled": @(gEnabled)});

    if (gEnabled) {
        InstallAutoObserverOnce();
        if (gOverlayWindow && gOverlayWindow.rootViewController) {
            ShowPanel(gOverlayWindow.rootViewController.view);
        }
    } else {
        HidePanel();
    }
}

#pragma mark - ====== UI Setup ======

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

    // 不要高于系统弹窗，否则 Alert 的 OK 点不到
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
    gOverlayWindow = overlay;

    TSReport(@"event", @{@"name": @"setup_ui", @"enabled_restore": @(gEnabled)});

    // 如果之前就是 ON，恢复面板
    if (gEnabled) {
        InstallAutoObserverOnce();
        ShowPanel(vc.view);
    }
}

#pragma mark - ====== Entry ======

__attribute__((constructor))
static void Entry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 震动提示：dylib 已加载
        AudioServicesPlaySystemSound(1519);

        // 上报：注入成功
        TSReport(@"event", @{@"name": @"dylib_loaded"});

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = TopVC();
            if (vc) {
                UIAlertController *a =
                [UIAlertController alertControllerWithTitle:@"本产品严禁用于赌博"
                                                    message:@"记牌器（测试）已加载"
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
