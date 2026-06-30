#import <UIKit/UIKit.h>

#pragma mark - Names Array

static NSArray<NSString *> *accountNames = @[
    @"Abdulilah", @"Lahhou", @"Charo", @"Said",
    @"AbuMeteab", @"Nasser", @"Alkaed",
    @"Alhbas", @"Alshamara"
];

#pragma mark - Global State

static UIWindow *tweakWindow = nil;
static UIView *mainContainer = nil;
static UIView *minimizedContainer = nil;
static UIButton *toggleBtn = nil;
static UIButton *mergeBtn = nil;
static UISlider *speedSlider = nil;
static UILabel *speedValueLabel = nil;
static BOOL isRunning = NO;
static BOOL isExpanded = YES;
static BOOL accountsMerged = NO;
static CGFloat currentDelay = 0.0;
static UIView *circleView = nil;
static UILabel *circleLabel = nil;
static dispatch_source_t tapTimer = NULL;

#pragma mark - Forward Declarations

@interface YLTFollowManager : NSObject
+ (instancetype)sharedManager;
- (void)mergeAllAccounts;
- (void)performFollowWithDelay:(CGFloat)delay;
@end

#pragma mark - Follow Manager (Core Logic)

@implementation YLTFollowManager

+ (instancetype)sharedManager {
    static YLTFollowManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YLTFollowManager alloc] init];
    });
    return instance;
}

- (void)mergeAllAccounts {
    accountsMerged = YES;
    [self performFollowWithDelay:currentDelay];
}

- (void)performFollowWithDelay:(CGFloat)delay {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSInteger i = 0; i < accountNames.count; i++) {
            for (NSInteger j = 0; j < accountNames.count; j++) {
                if (i == j) continue;
                [NSThread sleepForTimeInterval:delay];
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"[YLTool] Following %@ -> %@", accountNames[i], accountNames[j]);
                });
            }
        }
    });
}

@end

#pragma mark - UI Setup

@interface YLTUIHelper : NSObject
+ (void)setupTweakUI;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation YLTUIHelper

+ (void)setupTweakUI {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;

    // ---- Main Window ----
    tweakWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    tweakWindow.windowLevel = UIWindowLevelAlert + 100;
    tweakWindow.backgroundColor = [UIColor clearColor];
    tweakWindow.userInteractionEnabled = YES;

    // ---- Layout Constants ----
    CGFloat cw = 280;
    CGFloat cx = (screenWidth - cw) / 2;
    CGFloat cy = 80;
    CGFloat pad = 12;
    CGFloat gap = 8;

    // ---- Calculate Badge Layout First ----
    CGFloat bX = pad;
    CGFloat bY = pad + 2;
    CGFloat bH = 28;
    CGFloat bGapX = 6;
    CGFloat bGapY = 6;
    CGFloat bMaxX = cw - pad;

    // Store badge frames (name, x, y, w)
    NSMutableArray *badgeLayout = [NSMutableArray array];
    for (NSString *name in accountNames) {
        CGSize ts = [name sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]}];
        CGFloat bw = ts.width + 16;
        if (bw < 50) bw = 50;
        if (bX + bw > bMaxX) { bX = pad; bY += bH + bGapY; }
        [badgeLayout addObject:@{@"name": name, @"x": @(bX), @"y": @(bY), @"w": @(bw)}];
        bX += bw + bGapX;
    }
    CGFloat namesBottom = bY + bH + 8;

    // ---- Container Height ----
    CGFloat toggleH = 42;
    CGFloat sliderTitleH = 18;
    CGFloat sliderH = 30;
    CGFloat speedLabelH = 16;
    CGFloat sepH = 1;
    CGFloat mergeH = 42;
    CGFloat ch = namesBottom + gap + sepH + gap + toggleH + gap +
                 sliderTitleH + sliderH + speedLabelH + gap +
                 sepH + gap + mergeH + pad;

    // ---- Expanded Container ----
    mainContainer = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cw, ch)];
    mainContainer.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    mainContainer.layer.cornerRadius = 14;
    mainContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:0.8].CGColor;
    mainContainer.layer.borderWidth = 2;
    mainContainer.clipsToBounds = YES;
    mainContainer.tag = 100;

    // ---- Add Badges ----
    for (NSDictionary *item in badgeLayout) {
        CGFloat x = [item[@"x"] floatValue];
        CGFloat y = [item[@"y"] floatValue];
        CGFloat w = [item[@"w"] floatValue];
        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, bH)];
        badge.backgroundColor = [UIColor colorWithRed:0.15 green:0.4 blue:0.7 alpha:0.7];
        badge.layer.cornerRadius = 6;
        badge.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.6].CGColor;
        badge.layer.borderWidth = 1;
        UILabel *bl = [[UILabel alloc] initWithFrame:badge.bounds];
        bl.text = item[@"name"];
        bl.textColor = [UIColor whiteColor];
        bl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        bl.textAlignment = NSTextAlignmentCenter;
        [badge addSubview:bl];
        [mainContainer addSubview:badge];
    }

    // ---- Y Offset Tracker ----
    CGFloat yOff = namesBottom + gap;

    // Separator 1
    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(pad, yOff, cw - pad * 2, sepH)];
    sep1.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [mainContainer addSubview:sep1];
    yOff += sepH + gap;

    // ---- Toggle Button (تشغيل / إيقاف) ----
    toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(20, yOff, cw - 40, toggleH);
    toggleBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1.0];
    toggleBtn.layer.cornerRadius = 10;
    [toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [toggleBtn addTarget:self action:@selector(toggleRunStop) forControlEvents:UIControlEventTouchUpInside];
    [mainContainer addSubview:toggleBtn];
    yOff += toggleH + gap;

    // ---- Speed Slider ----
    UILabel *sliderTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, yOff, cw - 40, sliderTitleH)];
    sliderTitle.text = @"سرعة MS";
    sliderTitle.textColor = [UIColor lightGrayColor];
    sliderTitle.font = [UIFont systemFontOfSize:13];
    sliderTitle.textAlignment = NSTextAlignmentCenter;
    [mainContainer addSubview:sliderTitle];
    yOff += sliderTitleH;

    speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, yOff, cw - 40, sliderH)];
    speedSlider.minimumValue = 0.0;
    speedSlider.maximumValue = 0.05;
    speedSlider.value = 0.0;
    speedSlider.continuous = YES;
    speedSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [speedSlider addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    [mainContainer addSubview:speedSlider];
    yOff += sliderH;

    speedValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yOff, cw - 40, speedLabelH)];
    speedValueLabel.text = @"0.00 ثانية";
    speedValueLabel.textColor = [UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0];
    speedValueLabel.font = [UIFont systemFontOfSize:12];
    speedValueLabel.textAlignment = NSTextAlignmentCenter;
    [mainContainer addSubview:speedValueLabel];
    yOff += speedLabelH + gap;

    // Separator 2
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(pad, yOff, cw - pad * 2, sepH)];
    sep2.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [mainContainer addSubview:sep2];
    yOff += sepH + gap;

    // ---- Merge Button (دمج الحسابات) ----
    mergeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    mergeBtn.frame = CGRectMake(20, yOff, cw - 40, mergeH);
    mergeBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.45 blue:0.1 alpha:1.0];
    mergeBtn.layer.cornerRadius = 10;
    [mergeBtn setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
    [mergeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    mergeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [mergeBtn addTarget:self action:@selector(mergeAccounts) forControlEvents:UIControlEventTouchUpInside];
    [mainContainer addSubview:mergeBtn];

    // ---- Hide Button (اخفاء القائمة) ----
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(cw - 38, 6, 28, 28);
    hideBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    hideBtn.layer.cornerRadius = 14;
    [hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [hideBtn addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [mainContainer addSubview:hideBtn];

    // ---- Minimized Container ----
    CGFloat mcw = 80;
    CGFloat mch = 80;
    minimizedContainer = [[UIView alloc] initWithFrame:CGRectMake(cx + cw - mcw, cy, mcw, mch)];
    minimizedContainer.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    minimizedContainer.layer.cornerRadius = 14;
    minimizedContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:0.8].CGColor;
    minimizedContainer.layer.borderWidth = 2;
    minimizedContainer.hidden = YES;
    minimizedContainer.tag = 200;

    // Minimized arrow button
    UIButton *arrowBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    arrowBtn.frame = CGRectMake(10, 10, 60, 60);
    arrowBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    arrowBtn.layer.cornerRadius = 30;
    [arrowBtn setTitle:@"▶" forState:UIControlStateNormal];
    [arrowBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    arrowBtn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [arrowBtn addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
    [minimizedContainer addSubview:arrowBtn];

    // ---- Draggable Circle (515) ----
    CGFloat circleSize = 60;
    CGFloat circleX = (screenWidth - circleSize) / 2;
    CGFloat circleY = cy + ch + 30;
    circleView = [[UIView alloc] initWithFrame:CGRectMake(circleX, circleY, circleSize, circleSize)];
    circleView.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.1 alpha:0.9];
    circleView.layer.cornerRadius = circleSize / 2;
    circleView.layer.borderColor = [UIColor whiteColor].CGColor;
    circleView.layer.borderWidth = 2;
    circleView.userInteractionEnabled = YES;
    circleView.tag = 300;

    circleLabel = [[UILabel alloc] initWithFrame:circleView.bounds];
    circleLabel.text = @"515";
    circleLabel.textColor = [UIColor whiteColor];
    circleLabel.font = [UIFont boldSystemFontOfSize:18];
    circleLabel.textAlignment = NSTextAlignmentCenter;
    [circleView addSubview:circleLabel];

    // Pan gesture for dragging
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[YLTUIHelper class] action:@selector(dragCircle:)];
    [circleView addGestureRecognizer:pan];

    // Add to window
    [tweakWindow addSubview:mainContainer];
    [tweakWindow addSubview:minimizedContainer];
    [tweakWindow addSubview:circleView];
    tweakWindow.hidden = NO;
}

#pragma mark - Circle Drag

+ (void)dragCircle:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    CGPoint center = view.center;
    center.x += translation.x;
    center.y += translation.y;
    view.center = center;
    [gesture setTranslation:CGPointZero inView:view.superview];
}

#pragma mark - Tapping Logic

+ (void)startTapping {
    if (tapTimer) return;
    CGFloat interval = currentDelay;
    if (interval < 0.005) interval = 0.005;
    tapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(tapTimer, DISPATCH_TIME_NOW, interval * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(tapTimer, ^{
        [self performTap];
    });
    dispatch_resume(tapTimer);
}

+ (void)stopTapping {
    if (tapTimer) {
        dispatch_source_cancel(tapTimer);
        tapTimer = NULL;
    }
}

+ (void)performTap {
    if (!circleView || !isRunning) return;

    // Animate tap press
    [UIView animateWithDuration:0.03 animations:^{
        circleView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        circleView.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.2 alpha:0.9];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.03 animations:^{
            circleView.transform = CGAffineTransformIdentity;
            circleView.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.1 alpha:0.9];
        }];
    }];

    // Get key window (iOS 13+ compatible)
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = [(UIWindowScene *)scene windows].firstObject;
                break;
            }
        }
    }
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [[UIApplication sharedApplication] keyWindow];
#pragma clang diagnostic pop
    }
    if (!keyWindow) return;

    // Convert circle center to key window coordinates
    CGPoint tapPoint = [circleView convertPoint:circleView.center toView:keyWindow];

    // Find the view at tap point
    UIView *targetView = [keyWindow hitTest:tapPoint withEvent:nil];
    if (!targetView) return;
    if (targetView == circleView || [targetView isDescendantOfView:mainContainer] || [targetView isDescendantOfView:minimizedContainer]) return;

    // Simulate UIControl tap
    if ([targetView isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)targetView;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    // Flash effect on tap point
    UIView *flash = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    flash.center = tapPoint;
    flash.backgroundColor = [UIColor whiteColor];
    flash.layer.cornerRadius = 10;
    flash.alpha = 0.7;
    flash.userInteractionEnabled = NO;
    [keyWindow addSubview:flash];
    [UIView animateWithDuration:0.2 animations:^{
        flash.alpha = 0;
        flash.transform = CGAffineTransformMakeScale(2, 2);
    } completion:^(BOOL finished) {
        [flash removeFromSuperview];
    }];
}

#pragma mark - Toggle Run/Stop

+ (void)toggleRunStop {
    isRunning = !isRunning;
    if (isRunning) {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
        [toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
        [self startTapping];
    } else {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1.0];
        [toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
        [self stopTapping];
    }
}

#pragma mark - Speed Slider

+ (void)speedChanged {
    CGFloat val = speedSlider.value;
    // Round to 2 decimal places
    val = round(val * 100.0) / 100.0;
    speedSlider.value = val;
    currentDelay = val;
    speedValueLabel.text = [NSString stringWithFormat:@"%.2f ثانية", val];
    if (isRunning) {
        [self stopTapping];
        [self startTapping];
    }
}

#pragma mark - Merge Accounts

+ (void)mergeAccounts {
    [[YLTFollowManager sharedManager] mergeAllAccounts];

    // Show success alert
    [self showAlertWithTitle:@"✓ تم الدمج" message:@"تم ربط جميع الحسابات بنجاح"];

    // Visual feedback
    mergeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:1.0];
    [mergeBtn setTitle:@"✓ تم الربط" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        mergeBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.45 blue:0.1 alpha:1.0];
        [mergeBtn setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
    });
}

#pragma mark - Hide / Show

+ (void)hidePanel {
    isExpanded = NO;
    mainContainer.hidden = YES;
    minimizedContainer.hidden = NO;
}

+ (void)showPanel {
    isExpanded = YES;
    minimizedContainer.hidden = YES;
    mainContainer.hidden = NO;
}

#pragma mark - Alert Helper

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    UIViewController *rootVC = nil;
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = [(UIWindowScene *)scene windows].firstObject;
                break;
            }
        }
    }
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [[UIApplication sharedApplication] keyWindow];
#pragma clang diagnostic pop
    }
    rootVC = keyWindow.rootViewController;
    if (!rootVC) rootVC = tweakWindow.rootViewController;
    if (!rootVC) return;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Constructor

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YLTUIHelper setupTweakUI];
    });
}

#pragma mark - YallaLite Hooks (Placeholder - Customize as needed)

// Replace "YLLFollowManager" and followUser: below with actual YallaLite classes/methods.
// Use `class-dump` or `nm` on the YallaLite binary to find real class/method names.

/*
 %hook YLLFollowManager

 - (void)followUser:(NSString *)userId {
     %orig;
     NSLog(@"[YLTool] followUser hooked: %@", userId);
 }

 - (void)unfollowUser:(NSString *)userId {
     %orig;
     NSLog(@"[YLTool] unfollowUser hooked: %@", userId);
 }

 %end
 */

/*
 %hook YLLNetworkManager

 - (void)sendFollowRequestWithUserId:(NSString *)userId completion:(void(^)(BOOL))completion {
     %orig;
     if (accountsMerged) {
         NSLog(@"[YLTool] Auto-follow active for: %@", userId);
     }
 }

 %end
 */
