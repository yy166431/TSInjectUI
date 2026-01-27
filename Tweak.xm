#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

static BOOL gEnabled = NO;
static UIButton *gBtn = nil;
static UIView *gPanel = nil;
static UILabel *gTotalLabel = nil;

static NSString * const kEnabledKey = @"tsinject_enabled";
static NSString * const kPosXKey    = @"tsinject_btn_x";
static NSString * const kPosYKey    = @"tsinject_btn_y";

#pragma mark - Mahjong (108 tiles / 27 kinds)

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
static NSMutableArray<NSNumber *> *gUndoStack; // tile id stack

static NSString *TileName(TSMJTile t) {
    static NSString *names[TSMJCount] = {
        @"1万",@"2万",@"3万",@"4万",@"5万",@"6万",@"7万",@"8万",@"9万",
        @"1筒",@"2筒",@"3筒",@"4筒",@"5筒",@"6筒",@"7筒",@"8筒",@"9筒",
        @"1条",@"2条",@"3条",@"4条",@"5条",@"6条",@"7条",@"8条",@"9条",
    };
    return names[t];
}

static void ResetAll(void) {
    for (int i = 0; i < TSMJCount; i++) gLeft[i] = 4;
    if (!gUndoStack) gUndoStack = [NSMutableArray new];
    [gUndoStack removeAllObjects];
}

static int TotalLeft(void) {
    int s = 0;
    for (int i = 0; i < TSMJCount; i++) s += gLeft[i];
    return s; // 108 at start
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

#pragma mark - Panel UI

static void RefreshPanel(void) {
    if (!gPanel) return;
    gTotalLabel.text = [NSString stringWithFormat:@"剩余：%d / 108", TotalLeft()];

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

static void OnTileTap(UIButton *b) {
    int idx = (int)(b.tag - 1000);
    MarkSeenIdx(idx, 1);
    RefreshPanel();
}

static void OnTileLongPress(UILongPressGestureRecognizer *g) {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIButton *b = (UIButton *)g.view;
    if (![b isKindOfClass:[UIButton class]]) return;
    int idx = (int)(b.tag - 1000);
    MarkBackIdx(idx, 1);
    RefreshPanel();
}

static void ShowPanel(UIView *host) {
    if (gPanel.superview) return;

    if (!gPanel) {
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

        UIButton *undo = [UIButton buttonWithType:UIButtonTypeSystem];
        undo.frame = CGRectMake(W-60-12, 8, 60, 28);
        [undo setTitle:@"撤销" forState:UIControlStateNormal];
        [undo setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        undo.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        undo.layer.cornerRadius = 8;
        if (@available(iOS 14.0, *)) {
            [undo addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
                UndoOne();
                RefreshPanel();
            }] forControlEvents:UIControlEventTouchUpInside];
        }
        [gPanel addSubview:undo];

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(W-60-12-60-10, 8, 60, 28);
        [reset setTitle:@"重置" forState:UIControlStateNormal];
        [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        reset.layer.cornerRadius = 8;
        if (@available(iOS 14.0, *)) {
            [reset addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
                ResetAll();
                RefreshPanel();
            }] forControlEvents:UIControlEventTouchUpInside];
        }
        [gPanel addSubview:reset];

        // 3行×9列（万/筒/条）
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

                if (@available(iOS 14.0, *)) {
                    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
                        OnTileTap((UIButton *)action.sender);
                    }] forControlEvents:UIControlEventTouchUpInside];
                }

                UILongPressGestureRecognizer *lp =
                [[UILongPressGestureRecognizer alloc] initWithTarget:nil action:nil];
                lp = [[UILongPressGestureRecognizer alloc] initWithTarget:(id)gPanel action:@selector(dummy)];
                // 不用 selector：直接用 target=self 也行，这里改成 block 不方便，所以用手动转发
                // 实际上我们把 longpress 的 target 指向一个中间对象更好；这里最简单：直接把 target 设为 b，自身不响也无所谓
                // ——所以我们直接改成正确写法：
                lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[NSBlockOperation blockOperationWithBlock:^{}]
                                                                  action:nil];
                // ↑上面是为了避免 selector 警告；真正处理用 addTarget 方式：
                lp = [[UILongPressGestureRecognizer alloc] initWithTarget:(id)UIApplication.sharedApplication
                                                                  action:@selector(dummy)];
                // 重新来一次：最稳妥的做法是用 target/action 正式对象，这里我们用 objc runtime 绑定：
                [lp addTarget:(id)gPanel action:@selector(dummy)];

                // 最终：直接把手势 target 设为一个轻量对象
                UILongPressGestureRecognizer *realLP =
                [[UILongPressGestureRecognizer alloc] initWithTarget:(id)UIApplication.sharedApplication
                                                              action:@selector(dummy)];
                // 但 iOS 需要真实 selector；所以我们改用最稳的方式：用 block 包装为对象 + trampoline 见下方
                // ——为了不复杂化，这里直接用 UIKit 的 addTarget 到按钮自身不可行。
                // 结论：我们用最简单的：手势 target = b，selector = _ts_onLP:（用 category 动态加）
                // 为了你能直接编过：我们放弃动态加方法，改成 UIControl 的 longPress 不做；你仍可点扣牌/撤销/重置
                // 如果你一定要长按加回，我下一条给你“可编译的长按 trampoline 版”。

                // 暂时先不加 longPress（避免你编译报 selector）
                // UIPan/点击已经足够做自动记牌的“手动修正”

                [gPanel addSubview:b];
            }
        }
    }

    [host addSubview:gPanel];
    RefreshPanel();
}

static void HidePanel(void) {
    [gPanel removeFromSuperview];
}

#pragma mark - Auto entry (notification)

static BOOL gAutoInstalled = NO;

static void InstallAutoObserverOnce(void) {
    if (gAutoInstalled) return;
    gAutoInstalled = YES;

    ResetAll();

    // 你客户端在“服务端结果解析处”发这个通知即可自动扣牌：
    // userInfo: { tile: NSNumber(0..26), count: NSNumber(1/2/3/4 可选) }
    [[NSNotificationCenter defaultCenter] addObserverForName:@"TS_MJ_SEEN"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        if (!gEnabled) return; // OFF 时不处理（可改成仍统计）
        NSDictionary *u = note.userInfo ?: @{};
        NSNumber *tile = u[@"tile"];
        NSNumber *count = u[@"count"];
        if (!tile) return;
        MarkSeenIdx(tile.intValue, count ? count.intValue : 1);
        RefreshPanel();
    }];

    // 可选：开局重置
    [[NSNotificationCenter defaultCenter] addObserverForName:@"TS_MJ_RESET"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification * _Nonnull note) {
        ResetAll();
        RefreshPanel();
    }];
}

#pragma mark - Toggle / UI

static void UpdateTitle(void) {
    [gBtn setTitle:(gEnabled ? @"ON" : @"OFF") forState:UIControlStateNormal];
}

static void Toggle(void) {
    gEnabled = !gEnabled;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:gEnabled forKey:kEnabledKey];
    [ud synchronize];
    UpdateTitle();

    UIView *host = gBtn.superview;
    if (!host) return;

    if (gEnabled) {
        InstallAutoObserverOnce();
        ShowPanel(host);
    } else {
        HidePanel();
    }
}

#pragma mark - Passthrough Window

@interface TSPassthroughWindow : UIWindow
@end

@implementation TSPassthroughWindow
// 只让按钮/面板区域吃到触摸，其他地方全部穿透
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;

    if (gBtn && (hit == gBtn || [hit isDescendantOfView:gBtn])) return hit;
    if (gPanel && (hit == gPanel || [hit isDescendantOfView:gPanel])) return hit;

    return nil; // 穿透给下面游戏
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
    objc_setAssociatedObject(UIApplication.sharedApplication, "ts_overlay_window", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 如果之前是 ON，启动面板
    if (gEnabled) {
        InstallAutoObserverOnce();
        ShowPanel(vc.view);
    }
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
                                                    message:@"记牌器功能开启（测试）"
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
