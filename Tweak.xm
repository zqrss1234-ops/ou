#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <notify.h>
#import <signal.h>
#import <sys/ucontext.h>

#pragma mark - Crash Prevention (BacRunner – no crashes at all)

static void crashHandler(int sig, siginfo_t *info, void *context) {
    ucontext_t *uc = (ucontext_t *)context;
#if __arm64__
    uint32_t *pc = (uint32_t *)uc->uc_mcontext->__ss.__pc;
    if (*pc != 0 && *pc != 0xDEADBEEF)
        uc->uc_mcontext->__ss.__pc += 4;
#endif
}

static void exceptionHandler(NSException *e) {
    NSLog(@"[YLT] Uncaught exception: %@ %@", e.name, e.reason);
}

static void setupCrashPrevention(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crashHandler;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    sigaction(SIGPIPE, &sa, NULL);
    NSSetUncaughtExceptionHandler(&exceptionHandler);
}

#pragma mark - Names

static NSArray<NSString *> *accountNames = @[
    @"عبدالإله", @"شارو", @"لحلوح", @"سعيد",
    @"ابومتعب", @"كنق الشرق", @"حاتم",
    @"الكايد", @"الشمامره", @"الهباس"
];

#pragma mark - State

static UIView *ctrlBox = nil;
static UIView *tapCircle = nil;
static UILabel *marqueeLbl = nil;
static UISlider *delaySlider = nil;
static UILabel *delayLabel = nil;
static UIButton *runBtn = nil;
static UIButton *mergeBtn = nil;
static UIView *mergeDot = nil;
static dispatch_source_t tapTimer = NULL;
static dispatch_source_t topTimer = NULL;
static dispatch_source_t rainbowTimer = NULL;
static dispatch_source_t marqueeTimer = NULL;
static CAGradientLayer *accentLine = nil;
static BOOL running = NO;
static BOOL isMain = YES;
static CGFloat currentDelay = 200.0;
static UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;

#pragma mark - Helpers

static UIWindow *activeWindow(void) {
    if (@available(iOS 13.0, *))
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive)
                { UIWindow *w = [(UIWindowScene *)s windows].firstObject; if (w && !w.hidden) return w; }
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden && w.rootViewController) return w;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden) return w;
    return nil;
}

static UIColor *rgba(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

static void ensureOnTop(void) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    UIWindow *w = activeWindow();
    if (!w) return;
    if (ctrlBox) {
        if (ctrlBox.superview != w) { [ctrlBox removeFromSuperview]; [w addSubview:ctrlBox]; }
        [w bringSubviewToFront:ctrlBox];
    }
    if (tapCircle) {
        if (tapCircle.superview != w) { [tapCircle removeFromSuperview]; [w addSubview:tapCircle]; }
        [w bringSubviewToFront:tapCircle];
    }
}

#pragma mark - Background Task (BacRunner – keep alive)

static void startBgTask(void) {
    if (bgTask != UIBackgroundTaskInvalid) return;
    __block UIBackgroundTaskIdentifier task = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"YLToolBg" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:task];
        dispatch_async(dispatch_get_main_queue(), ^{
            startBgTask();
        });
    }];
    if (task != UIBackgroundTaskInvalid) bgTask = task;
}

#pragma mark - Forward Declarations

@interface Tapper : NSObject
+ (void)doTap;
+ (void)doTapLocal;
+ (void)start;
+ (void)stop;
@end

@interface Controller : NSObject
+ (void)buildUI;
+ (void)updateRunUI;
+ (void)updateMergeUI;
@end

#pragma mark - Darwin IPC

static int darwinPosToken = 0;
static int darwinRunToken = 0;
static int darwinStopToken = 0;
static int darwinTapToken = 0;

static void darwinInit(void) {
    notify_register_dispatch("com.yltool.pos", &darwinPosToken, dispatch_get_main_queue(), ^(int t) {
        @try {
            uint64_t state;
            notify_get_state(t, &state);
            CGFloat x = (CGFloat)(state >> 32) / 10.0;
            CGFloat y = (CGFloat)(state & 0xFFFFFFFF) / 10.0;
            if (tapCircle && tapCircle.superview)
                tapCircle.center = CGPointMake(x, y);
        } @catch (NSException *e) {
            NSLog(@"[YLT] Darwin pos error: %@ %@", e.name, e.reason);
        }
    });
    notify_register_dispatch("com.yltool.run", &darwinRunToken, dispatch_get_main_queue(), ^(int t) {
        @try {
            if (!running) { running = YES; [Tapper start]; [Controller updateRunUI]; }
        } @catch (NSException *e) {
            NSLog(@"[YLT] Darwin run error: %@ %@", e.name, e.reason);
        }
    });
    notify_register_dispatch("com.yltool.stop", &darwinStopToken, dispatch_get_main_queue(), ^(int t) {
        @try {
            if (running) { running = NO; [Tapper stop]; [Controller updateRunUI]; }
        } @catch (NSException *e) {
            NSLog(@"[YLT] Darwin stop error: %@ %@", e.name, e.reason);
        }
    });
    notify_register_dispatch("com.yltool.tap", &darwinTapToken, dispatch_get_main_queue(), ^(int t) {
        @try {
            [Tapper doTapLocal];
        } @catch (NSException *e) {
            NSLog(@"[YLT] Darwin tap error: %@ %@", e.name, e.reason);
        }
    });
}

static void darwinPostPos(CGFloat x, CGFloat y) {
    if (!darwinPosToken) return;
    uint64_t state = ((uint64_t)(uint32_t)(x * 10) << 32) | (uint64_t)(uint32_t)(y * 10);
    notify_set_state(darwinPosToken, state);
    notify_post("com.yltool.pos");
}

static void darwinPost(const char *name) {
    notify_post(name);
}

#pragma mark - UDP IPC (dispatch recvfrom – proven stable)

static int udpSock = -1;

static void udpInit(void) {
    udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpSock < 0) return;
    int opt = 1;
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
    setsockopt(udpSock, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(51551);
    addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(udpSock, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(udpSock); udpSock = -1; return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        char buf[256];
        fd_set fds;
        struct timeval tv;
        while (1) {
            @autoreleasepool {
                FD_ZERO(&fds);
                FD_SET(udpSock, &fds);
                tv.tv_sec = 0; tv.tv_usec = 10000;
                if (select(udpSock+1, &fds, NULL, NULL, &tv) <= 0) continue;
                struct sockaddr_in from;
                socklen_t flen = sizeof(from);
                ssize_t n = recvfrom(udpSock, buf, sizeof(buf)-1, 0, (struct sockaddr *)&from, &flen);
                if (n <= 0) continue;
                buf[n] = 0;
                NSString *m = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([m hasPrefix:@"POS:"]) {
                        NSArray *p = [[m substringFromIndex:4] componentsSeparatedByString:@","];
                        if (p.count == 2 && tapCircle && tapCircle.superview)
                            tapCircle.center = CGPointMake([p[0] floatValue], [p[1] floatValue]);
                    } else if ([m isEqualToString:@"RUN"]) {
                        if (!running) { running = YES; [Tapper start]; [Controller updateRunUI]; }
                    } else if ([m isEqualToString:@"STOP"]) {
                        if (running) { running = NO; [Tapper stop]; [Controller updateRunUI]; }
                    } else if ([m isEqualToString:@"TAP"]) {
                        [Tapper doTapLocal];
                    }
                });
            }
        }
    });
}

static void udpSend(NSString *m) {
    if (udpSock < 0) return;
    struct sockaddr_in bc;
    memset(&bc, 0, sizeof(bc));
    bc.sin_family = AF_INET;
    bc.sin_port = htons(51551);
    inet_aton("255.255.255.255", &bc.sin_addr);
    sendto(udpSock, m.UTF8String, m.length, 0, (struct sockaddr *)&bc, sizeof(bc));
}

#pragma mark - Universal Send

static void sendAll(NSString *msg) {
    if ([msg hasPrefix:@"POS:"]) {
        NSArray *p = [[msg substringFromIndex:4] componentsSeparatedByString:@","];
        if (p.count == 2) darwinPostPos([p[0] floatValue], [p[1] floatValue]);
    } else {
        const char *n = NULL;
        if ([msg isEqualToString:@"RUN"]) n = "com.yltool.run";
        else if ([msg isEqualToString:@"STOP"]) n = "com.yltool.stop";
        else if ([msg isEqualToString:@"TAP"]) n = "com.yltool.tap";
        if (n) darwinPost(n);
    }
    udpSend(msg);
}

#pragma mark - Tap Engine

@implementation Tapper

+ (void)doTapLocal {
    if (!tapCircle || !running) return;
    if (!tapCircle.superview) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;

    [UIView animateWithDuration:0.015 animations:^{
        tapCircle.transform = CGAffineTransformMakeScale(0.78, 0.78);
        tapCircle.backgroundColor = rgba(255, 200, 50, 0.9);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.015 animations:^{
            tapCircle.transform = CGAffineTransformIdentity;
            tapCircle.backgroundColor = rgba(255, 255, 255, 0.12);
        }];
    }];

    UIWindow *w = activeWindow();
    if (!w) return;

    BOOL ch = tapCircle.hidden, bh = ctrlBox.hidden;
    tapCircle.hidden = YES; ctrlBox.hidden = YES;

    CGPoint pt = [tapCircle.superview convertPoint:tapCircle.center toView:w];
    UIView *target = [w hitTest:pt withEvent:nil];

    tapCircle.hidden = ch; ctrlBox.hidden = bh;

    if (!target || target == tapCircle) return;

    UIView *hit = target;
    while (hit && ![hit isKindOfClass:[UIControl class]]) hit = hit.superview;
    UIControl *ctrl = (UIControl *)hit;
    if (ctrl && [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        @try {
            [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
            [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
        } @catch (NSException *e) {
            NSLog(@"[YLT] sendActions error: %@", e.reason);
        }
    }

    UIView *fx = [[UIView alloc] initWithFrame:CGRectMake(0,0,16,16)];
    fx.center = pt; fx.backgroundColor = rgba(100, 180, 255, 0.5);
    fx.layer.cornerRadius = 8; fx.userInteractionEnabled = NO;
    [w addSubview:fx];
    [UIView animateWithDuration:0.3 animations:^{
        fx.alpha = 0; fx.transform = CGAffineTransformMakeScale(4, 4);
    } completion:^(BOOL f) { [fx removeFromSuperview]; }];
}

+ (void)doTap {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    [self doTapLocal];
    sendAll(@"TAP");
}

+ (void)start {
    if (tapTimer) return;
    CGFloat ms = currentDelay;
    if (ms < 50) ms = 50;
    tapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(tapTimer, DISPATCH_TIME_NOW, (ms / 1000.0) * NSEC_PER_SEC, (ms / 1000.0) * NSEC_PER_SEC);
    dispatch_source_set_event_handler(tapTimer, ^{ [self doTap]; });
    dispatch_resume(tapTimer);
}

+ (void)stop {
    if (tapTimer) { dispatch_source_cancel(tapTimer); tapTimer = NULL; }
}

@end

#pragma mark - UI Setup

@implementation Controller

+ (void)buildUI {
    UIWindow *w = activeWindow();
    if (!w) {
        static int retries = 0;
        if (retries++ < 40)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self buildUI]; });
        return;
    }
    if (ctrlBox) { ensureOnTop(); return; }

    NSLog(@"[YLT] Building UI");
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;

    NSString *marqueeTxt = @"";
    for (NSString *n in accountNames) {
        marqueeTxt = [marqueeTxt stringByAppendingFormat:@"  ◉  %@", n];
    }

    // ---- Premium Control Box ----
    CGFloat bw = 230, bh = 210, bx = (sw-bw)/2, by = sh * 0.12;
    ctrlBox = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bw, bh)];
    ctrlBox.backgroundColor = rgba(6, 6, 12, 0.94);
    ctrlBox.layer.cornerRadius = 26;
    ctrlBox.layer.borderColor = rgba(80, 80, 120, 0.2).CGColor;
    ctrlBox.layer.borderWidth = 0.5;
    ctrlBox.layer.shadowColor = rgba(60, 130, 255, 0.2).CGColor;
    ctrlBox.layer.shadowOpacity = 0.6;
    ctrlBox.layer.shadowOffset = CGSizeMake(0, 12);
    ctrlBox.layer.shadowRadius = 35;
    ctrlBox.tag = 100;

    accentLine = [CAGradientLayer layer];
    accentLine.frame = CGRectMake(0, 0, bw, 3);
    accentLine.colors = @[(id)rgba(255, 80, 80, 0.8).CGColor,
                          (id)rgba(80, 80, 255, 0.5).CGColor,
                          (id)rgba(255, 80, 80, 0).CGColor];
    accentLine.startPoint = CGPointMake(0, 0);
    accentLine.endPoint = CGPointMake(1, 0);
    [ctrlBox.layer addSublayer:accentLine];

    CAGradientLayer *innerGlow = [CAGradientLayer layer];
    innerGlow.frame = ctrlBox.bounds;
    innerGlow.colors = @[(id)rgba(40, 40, 70, 0.08).CGColor, (id)rgba(6, 6, 12, 0).CGColor];
    innerGlow.startPoint = CGPointMake(0, 0);
    innerGlow.endPoint = CGPointMake(1, 1);
    [ctrlBox.layer addSublayer:innerGlow];

    CGFloat yy = 10;

    // ---- Marquee Names (GCD timer, smooth) ----
    UIView *marqueeBox = [[UIView alloc] initWithFrame:CGRectMake(10, yy, bw-20, 34)];
    marqueeBox.backgroundColor = rgba(12, 12, 24, 0.6);
    marqueeBox.layer.cornerRadius = 17;
    marqueeBox.clipsToBounds = YES;
    marqueeBox.layer.borderColor = rgba(60, 60, 100, 0.15).CGColor;
    marqueeBox.layer.borderWidth = 0.5;

    marqueeLbl = [[UILabel alloc] init];
    CGSize singleSz = [marqueeTxt sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]}];
    CGFloat singleW = singleSz.width + 24;
    marqueeLbl.frame = CGRectMake(0, 0, singleW * 2, 34);
    marqueeLbl.text = [marqueeTxt stringByAppendingString:marqueeTxt];
    marqueeLbl.textColor = rgba(240, 245, 255, 0.92);
    marqueeLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [marqueeBox addSubview:marqueeLbl];
    [ctrlBox addSubview:marqueeBox];

    CGFloat cw = marqueeBox.frame.size.width;
    if (singleW > cw) {
        __block CGFloat offset = 0;
        CGFloat speed = singleW / 25.0;
        marqueeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(marqueeTimer, DISPATCH_TIME_NOW, (1.0/60.0) * NSEC_PER_SEC, (1.0/60.0) * NSEC_PER_SEC);
        dispatch_source_set_event_handler(marqueeTimer, ^{
            offset -= speed / 60.0;
            if (offset <= -singleW) offset += singleW;
            marqueeLbl.transform = CGAffineTransformMakeTranslation(offset, 0);
        });
        dispatch_resume(marqueeTimer);
    }
    yy += 40;

    // ---- Speed ----
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, yy, 90, 14)];
    spLbl.text = @"سرعة النقر";
    spLbl.textColor = rgba(150, 160, 190, 0.65);
    spLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    [ctrlBox addSubview:spLbl];

    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(bw-95, yy, 80, 14)];
    delayLabel.text = @"200 ms";
    delayLabel.textColor = rgba(100, 180, 255, 0.85);
    delayLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    delayLabel.textAlignment = NSTextAlignmentRight;
    [ctrlBox addSubview:delayLabel];
    yy += 16;

    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(10, yy, bw-20, 22)];
    delaySlider.minimumValue = 50;
    delaySlider.maximumValue = 500;
    delaySlider.value = 200;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = rgba(60, 130, 255, 0.9);
    delaySlider.maximumTrackTintColor = rgba(35, 35, 55, 0.6);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBox addSubview:delaySlider];
    yy += 26;

    // ---- Run/Hide Row ----
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(10, yy, (bw-26)*0.62, 38);
    runBtn.backgroundColor = rgba(40, 100, 230, 1);
    runBtn.layer.cornerRadius = 16;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:rgba(220, 230, 255, 1) forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:runBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(CGRectGetMaxX(runBtn.frame)+6, yy, (bw-26)*0.38, 38);
    hideBtn.backgroundColor = rgba(35, 35, 55, 0.7);
    hideBtn.layer.cornerRadius = 16;
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [hideBtn setTitle:@"✕ إخفاء" forState:UIControlStateNormal];
    [hideBtn setTitleColor:rgba(150, 160, 190, 0.9) forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hideAll) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:hideBtn];
    yy += 44;

    // ---- Merge Row ----
    UIView *mergeRow = [[UIView alloc] initWithFrame:CGRectMake(10, yy, bw-20, 32)];
    mergeRow.backgroundColor = rgba(12, 12, 24, 0.5);
    mergeRow.layer.cornerRadius = 16;
    mergeRow.layer.borderColor = rgba(60, 200, 100, 0.15).CGColor;
    mergeRow.layer.borderWidth = 0.5;

    mergeDot = [[UIView alloc] initWithFrame:CGRectMake(10, 11, 10, 10)];
    mergeDot.layer.cornerRadius = 5;
    mergeDot.userInteractionEnabled = NO;
    mergeDot.backgroundColor = rgba(120, 130, 160, 0.3);
    mergeDot.tag = 500;
    [mergeRow addSubview:mergeDot];

    mergeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    mergeBtn.frame = CGRectMake(26, 0, mergeRow.frame.size.width-32, 32);
    mergeBtn.backgroundColor = [UIColor clearColor];
    mergeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    mergeBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [mergeBtn setTitle:@"  دمج الحسابات" forState:UIControlStateNormal];
    [mergeBtn setTitleColor:rgba(120, 130, 160, 0.7) forState:UIControlStateNormal];
    [mergeBtn addTarget:self action:@selector(toggleMerge) forControlEvents:UIControlEventTouchUpInside];
    [mergeRow addSubview:mergeBtn];
    [ctrlBox addSubview:mergeRow];
    yy += 38;

    // ---- Footer ----
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, yy, bw, bh-yy-2)];
    footer.text = @"حقوق عبدالإله";
    footer.textColor = rgba(80, 90, 120, 0.3);
    footer.font = [UIFont systemFontOfSize:7 weight:UIFontWeightLight];
    footer.textAlignment = NSTextAlignmentCenter;
    [ctrlBox addSubview:footer];

    UIPanGestureRecognizer *dragG = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [ctrlBox addGestureRecognizer:dragG];

    [w addSubview:ctrlBox];
    [w bringSubviewToFront:ctrlBox];

    // ---- Tap Circle (white inside, black border, "impossible") ----
    CGFloat cs = 46, cx = (sw-cs)/2, cy = sh * 0.58;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(255, 255, 255, 0.12);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(0, 0, 0, 0.9).CGColor;
    tapCircle.layer.borderWidth = 2.5;
    tapCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    tapCircle.layer.shadowOpacity = 0.5;
    tapCircle.layer.shadowOffset = CGSizeZero;
    tapCircle.layer.shadowRadius = 10;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    UILabel *impossibleLbl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    impossibleLbl.text = @"impossible";
    impossibleLbl.textColor = rgba(0, 0, 0, 0.25);
    impossibleLbl.font = [UIFont boldSystemFontOfSize:7];
    impossibleLbl.textAlignment = NSTextAlignmentCenter;
    impossibleLbl.userInteractionEnabled = NO;
    [tapCircle addSubview:impossibleLbl];

    UIPanGestureRecognizer *cg = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)];
    [tapCircle addGestureRecognizer:cg];

    UILongPressGestureRecognizer *mlg = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMaster:)];
    mlg.minimumPressDuration = 1.0;
    [tapCircle addGestureRecognizer:mlg];

    [w addSubview:tapCircle];
    [w bringSubviewToFront:tapCircle];

    [self updateMergeUI];
    darwinInit();
    udpInit();
    [self startRainbow];
    NSLog(@"[YLT] UI ready");
}

+ (void)startRainbow {
    static CGFloat hue = 0;
    if (rainbowTimer) return;
    rainbowTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(rainbowTimer, DISPATCH_TIME_NOW, 0.4 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(rainbowTimer, ^{
        if (!accentLine) return;
        hue += 1.0/16.0;
        if (hue > 1) hue -= 1;
        UIColor *c1 = [UIColor colorWithHue:hue saturation:1 brightness:1 alpha:0.8];
        UIColor *c2 = [UIColor colorWithHue:fmod(hue+0.4,1) saturation:0.8 brightness:0.9 alpha:0.4];
        UIColor *c3 = [UIColor colorWithHue:fmod(hue+0.7,1) saturation:0.6 brightness:0.7 alpha:0.1];
        accentLine.colors = @[(id)c1.CGColor, (id)c2.CGColor, (id)c3.CGColor];
        ctrlBox.layer.shadowColor = c1.CGColor;
        ctrlBox.layer.borderColor = c2.CGColor;
        if (marqueeLbl) marqueeLbl.textColor = [UIColor colorWithHue:hue saturation:0.6 brightness:1 alpha:0.92];
        if (mergeBtn && isMain)
            mergeBtn.backgroundColor = [UIColor colorWithHue:hue saturation:0.5 brightness:0.3 alpha:0.3];
        UIView *dot = [ctrlBox viewWithTag:500];
        if (dot) dot.backgroundColor = isMain ? rgba(60, 200, 100, 0.8) : rgba(120, 130, 160, 0.3);
    });
    dispatch_resume(rainbowTimer);
}

+ (UIImage *)thumbImage {
    return [UIImage imageWithCGImage:({
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(13, 13), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(ctx, rgba(255, 255, 255, 0.9).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(0.5, 0.5, 12, 12));
        CGContextSetFillColorWithColor(ctx, rgba(60, 130, 255, 0.3).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(2.5, 2.5, 8, 8));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        img.CGImage;
    })];
}

#pragma mark - Actions

+ (void)updateRunUI {
    if (!runBtn) return;
    [UIView animateWithDuration:0.2 animations:^{
        if (running) {
            runBtn.backgroundColor = rgba(200, 60, 60, 1);
            [runBtn setTitle:@"■  إيقاف" forState:UIControlStateNormal];
        } else {
            runBtn.backgroundColor = rgba(40, 100, 230, 1);
            [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
        }
    }];
}

+ (void)updateMergeUI {
    if (!mergeBtn) return;
    [UIView animateWithDuration:0.2 animations:^{
        if (isMain) {
            [mergeBtn setTitle:@"  تم دمج الحسابات ✓" forState:UIControlStateNormal];
            [mergeBtn setTitleColor:rgba(100, 255, 150, 1) forState:UIControlStateNormal];
        } else {
            [mergeBtn setTitle:@"  دمج الحسابات" forState:UIControlStateNormal];
            [mergeBtn setTitleColor:rgba(120, 130, 160, 0.7) forState:UIControlStateNormal];
        }
    }];
    UIView *dot = [ctrlBox viewWithTag:500];
    if (dot) dot.backgroundColor = isMain ? rgba(60, 200, 100, 0.8) : rgba(120, 130, 160, 0.3);
}

+ (void)toggleMerge {
    isMain = !isMain;
    [self updateMergeUI];
    if (isMain) {
        [self alert:@"تم دمج الحسابات ✓" msg:@"جميع النسخ ستتبع هذه النسخة"];
        if (tapCircle)
            sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
        if (running) sendAll(@"RUN");
    }
}

+ (void)toggleRun {
    running = !running;
    [self updateRunUI];
    if (running) {
        [Tapper start];
        sendAll(@"RUN");
    } else {
        [Tapper stop];
        sendAll(@"STOP");
    }
}

+ (void)speedChange {
    CGFloat v = round(delaySlider.value);
    delaySlider.value = v;
    currentDelay = v;
    delayLabel.text = [NSString stringWithFormat:@"%03.0f ms", v];
    if (running) { [Tapper stop]; [Tapper start]; }
}

+ (void)hideAll {
    ctrlBox.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ctrlBox.hidden) {
            ctrlBox.hidden = NO;
            ensureOnTop();
        }
    });
}

+ (void)dragItem:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

+ (void)dragCircle:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
    static CFTimeInterval lastPos = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (g.state == UIGestureRecognizerStateEnded || now - lastPos > 0.03) {
        lastPos = now;
        sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y]);
    }
}

+ (void)setMaster:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isMain = !isMain;
        [self updateMergeUI];
        if (isMain) {
            [self alert:@"✓ رئيسي" msg:@"النسخة الرئيسية - تتحكم بجميع النسخ"];
            if (tapCircle)
                sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
        }
    }
}

+ (void)alert:(NSString *)t msg:(NSString *)m {
    UIViewController *root = activeWindow().rootViewController;
    if (!root) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [root presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Constructor

__attribute__((constructor)) static void init() {
    setupCrashPrevention();
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid || ![bid hasPrefix:@"com.yalla.yallalite"]) return;
    NSLog(@"[YLT] Loading...");
    dispatch_async(dispatch_get_main_queue(), ^{ [Controller buildUI]; });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIWindow *w = n.object;
        if (w && !w.hidden && w.rootViewController && !ctrlBox) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
        if (!ctrlBox) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        startBgTask();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        topTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(topTimer, DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(topTimer, ^{ ensureOnTop(); });
        dispatch_resume(topTimer);
    });
}
