#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#pragma mark - Names

static NSArray<NSString *> *accountNames = @[
    @"Abdulilah", @"Lahhou", @"Charo", @"Said",
    @"AbuMeteab", @"Nasser", @"Alkaed",
    @"Alhbas", @"Alshamara"
];

#pragma mark - State

static UIView *ctrlBox = nil;
static UIView *tapCircle = nil;
static UISlider *delaySlider = nil;
static UILabel *delayLabel = nil;
static UIButton *runBtn = nil;
static UIButton *linkBtn = nil;
static dispatch_source_t tapTimer = NULL;
static dispatch_source_t topTimer = NULL;
static dispatch_source_t rainbowTimer = NULL;
static CAGradientLayer *accentLine = nil;
static BOOL running = NO;
static BOOL isMain = NO;
static CGFloat currentDelay = 30.0;
static int udpSock = -1;

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

#pragma mark - UDP

static void udpInit(void) {
    udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpSock < 0) return;
    int opt = 1;
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(udpSock, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));
    struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };
    setsockopt(udpSock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(51551);
    addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(udpSock, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(udpSock); udpSock = -1; return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buf[256];
        while (1) {
            struct sockaddr_in from;
            socklen_t flen = sizeof(from);
            ssize_t n = recvfrom(udpSock, buf, sizeof(buf)-1, 0, (struct sockaddr *)&from, &flen);
            if (n > 0) {
                buf[n] = 0;
                NSString *m = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([m hasPrefix:@"POS:"]) {
                        NSArray *p = [[m substringFromIndex:4] componentsSeparatedByString:@","];
                        if (p.count == 2 && !isMain && tapCircle && tapCircle.superview)
                            tapCircle.center = CGPointMake([p[0] floatValue], [p[1] floatValue]);
                    } else if ([m isEqualToString:@"RUN"]) {
                        if (!isMain) { running = YES; [NSClassFromString(@"Tapper") performSelector:@selector(start)];
                            [NSClassFromString(@"Controller") performSelector:@selector(updateRunUI)]; }
                    } else if ([m isEqualToString:@"STOP"]) {
                        if (!isMain) { running = NO; [NSClassFromString(@"Tapper") performSelector:@selector(stop)];
                            [NSClassFromString(@"Controller") performSelector:@selector(updateRunUI)]; }
                    } else if ([m isEqualToString:@"TAP"]) {
                        if (!isMain) [NSClassFromString(@"Tapper") performSelector:@selector(doTap)];
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

#pragma mark - Tap Engine

@interface Tapper : NSObject
+ (void)doTap;
+ (void)start;
+ (void)stop;
@end

@implementation Tapper

+ (void)doTap {
    if (!tapCircle || !running) return;

    [UIView animateWithDuration:0.015 animations:^{
        tapCircle.transform = CGAffineTransformMakeScale(0.78, 0.78);
        tapCircle.backgroundColor = rgba(255, 200, 50, 0.9);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.015 animations:^{
            tapCircle.transform = CGAffineTransformIdentity;
            tapCircle.backgroundColor = rgba(20, 20, 20, 0.95);
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
    if (ctrl) {
        [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
        [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    UIView *fx = [[UIView alloc] initWithFrame:CGRectMake(0,0,16,16)];
    fx.center = pt; fx.backgroundColor = rgba(100, 180, 255, 0.5);
    fx.layer.cornerRadius = 8; fx.userInteractionEnabled = NO;
    [w addSubview:fx];
    [UIView animateWithDuration:0.3 animations:^{
        fx.alpha = 0; fx.transform = CGAffineTransformMakeScale(4, 4);
    } completion:^(BOOL f) { [fx removeFromSuperview]; }];

    udpSend(@"TAP");
}

+ (void)start {
    if (tapTimer) return;
    CGFloat ms = currentDelay;
    if (ms < 5) ms = 5;
    tapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(tapTimer, DISPATCH_TIME_NOW, (ms / 1000.0) * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(tapTimer, ^{ [self doTap]; });
    dispatch_resume(tapTimer);
}

+ (void)stop {
    if (tapTimer) { dispatch_source_cancel(tapTimer); tapTimer = NULL; }
}

@end

#pragma mark - UI Setup

@interface Controller : NSObject
+ (void)buildUI;
@end

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

    // ---- Auto-scroll names text ----
    NSMutableString *marqueeStr = [NSMutableString string];
    for (NSString *n in accountNames) {
        [marqueeStr appendFormat:@"  ◉  %@", n];
    }

    // ---- Control Box (Square Rectangle) ----
    CGFloat bw = 220, bh = 185, bx = (sw-bw)/2, by = sh * 0.15;
    ctrlBox = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bw, bh)];
    ctrlBox.backgroundColor = rgba(8, 8, 12, 0.95);
    ctrlBox.layer.cornerRadius = 24;
    ctrlBox.layer.borderColor = rgba(60, 60, 90, 0.35).CGColor;
    ctrlBox.layer.borderWidth = 0.5;
    ctrlBox.layer.shadowColor = UIColor.blackColor.CGColor;
    ctrlBox.layer.shadowOpacity = 0.55;
    ctrlBox.layer.shadowOffset = CGSizeMake(0, 10);
    ctrlBox.layer.shadowRadius = 28;
    ctrlBox.tag = 100;

    // Top accent glow
    accentLine = [CAGradientLayer layer];
    accentLine.frame = CGRectMake(0, 0, bw, 2.5);
    accentLine.colors = @[(id)rgba(60, 130, 255, 0.8).CGColor,
                          (id)rgba(120, 80, 255, 0.5).CGColor,
                          (id)rgba(60, 130, 255, 0).CGColor];
    accentLine.startPoint = CGPointMake(0, 0);
    accentLine.endPoint = CGPointMake(1, 0);
    [ctrlBox.layer addSublayer:accentLine];

    // Inner glow
    CAGradientLayer *innerGlow = [CAGradientLayer layer];
    innerGlow.frame = ctrlBox.bounds;
    innerGlow.colors = @[(id)rgba(35, 35, 60, 0.1).CGColor, (id)rgba(10, 10, 20, 0).CGColor];
    innerGlow.startPoint = CGPointMake(0, 0);
    innerGlow.endPoint = CGPointMake(1, 1);
    [ctrlBox.layer addSublayer:innerGlow];

    CGFloat yy = 12;

    // ---- Marquee Names ----
    UIView *marqueeBox = [[UIView alloc] initWithFrame:CGRectMake(12, yy, bw-24, 34)];
    marqueeBox.backgroundColor = rgba(18, 18, 30, 0.6);
    marqueeBox.layer.cornerRadius = 17;
    marqueeBox.clipsToBounds = YES;

    UILabel *marqueeLbl = [[UILabel alloc] init];
    NSString *singleTxt = marqueeStr;
    CGSize singleSz = [singleTxt sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}];
    CGFloat singleW = singleSz.width + 24;
    marqueeLbl.frame = CGRectMake(0, 0, singleW * 2, 34);
    marqueeLbl.text = [singleTxt stringByAppendingString:singleTxt];
    marqueeLbl.textColor = rgba(235, 240, 255, 0.95);
    marqueeLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [marqueeBox addSubview:marqueeLbl];

    CGFloat cw = marqueeBox.frame.size.width;
    if (singleW > cw) {
        [UIView animateWithDuration:singleW/22.0 delay:0 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionRepeat animations:^{
            marqueeLbl.transform = CGAffineTransformMakeTranslation(-singleW, 0);
        } completion:nil];
    }

    linkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    linkBtn.frame = CGRectMake(bw-24-10, yy+5, 26, 26);
    linkBtn.backgroundColor = rgba(40, 40, 65, 0.7);
    linkBtn.layer.cornerRadius = 13;
    linkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:9];
    [linkBtn setTitle:@"دمج" forState:UIControlStateNormal];
    [linkBtn setTitleColor:rgba(120, 130, 160, 0.7) forState:UIControlStateNormal];
    [linkBtn addTarget:self action:@selector(toggleMerge) forControlEvents:UIControlEventTouchUpInside];
    linkBtn.tag = 500;

    [ctrlBox addSubview:marqueeBox];
    [ctrlBox addSubview:linkBtn];
    [self updateMergeUI];
    yy += 38;

    // ---- Speed Row ----
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, yy, 90, 16)];
    spLbl.text = @"سرعة النقر";
    spLbl.textColor = rgba(150, 160, 190, 0.7);
    spLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    [ctrlBox addSubview:spLbl];

    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(bw-90, yy, 76, 16)];
    delayLabel.text = @"030 ms";
    delayLabel.textColor = rgba(100, 180, 255, 0.9);
    delayLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    delayLabel.textAlignment = NSTextAlignmentRight;
    [ctrlBox addSubview:delayLabel];
    yy += 18;

    // ---- Slider ----
    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(10, yy, bw-20, 22)];
    delaySlider.minimumValue = 5;
    delaySlider.maximumValue = 500;
    delaySlider.value = 30;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = rgba(60, 130, 255, 0.9);
    delaySlider.maximumTrackTintColor = rgba(40, 40, 65, 0.6);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBox addSubview:delaySlider];
    yy += 28;

    // ---- Buttons Row ----
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(12, yy, (bw-30)*0.65, 38);
    runBtn.backgroundColor = rgba(40, 100, 230, 1);
    runBtn.layer.cornerRadius = 15;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:rgba(220, 230, 255, 1) forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:runBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(CGRectGetMaxX(runBtn.frame)+6, yy, (bw-30)*0.35, 38);
    hideBtn.backgroundColor = rgba(40, 40, 60, 0.7);
    hideBtn.layer.cornerRadius = 15;
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [hideBtn setTitle:@"✕" forState:UIControlStateNormal];
    [hideBtn setTitleColor:rgba(160, 170, 200, 0.8) forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hideAll) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:hideBtn];
    yy += 44;

    // ---- Footer ----
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, yy + 2, bw, bh - yy - 4)];
    footer.text = @"حقوق عبدالإله";
    footer.textColor = rgba(90, 100, 130, 0.35);
    footer.font = [UIFont systemFontOfSize:7.5 weight:UIFontWeightLight];
    footer.textAlignment = NSTextAlignmentCenter;
    [ctrlBox addSubview:footer];

    // Drag
    UIPanGestureRecognizer *dragG = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [ctrlBox addGestureRecognizer:dragG];

    [w addSubview:ctrlBox];
    [w bringSubviewToFront:ctrlBox];

    // ---- Tap Circle (Pure Black) ----
    CGFloat cs = 46, cx = (sw-cs)/2, cy = sh * 0.58;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(16, 16, 16, 0.95);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(255, 255, 255, 0.1).CGColor;
    tapCircle.layer.borderWidth = 1.5;
    tapCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    tapCircle.layer.shadowOpacity = 0.5;
    tapCircle.layer.shadowOffset = CGSizeMake(0, 0);
    tapCircle.layer.shadowRadius = 12;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    UIView *oring = [[UIView alloc] initWithFrame:CGRectInset(tapCircle.bounds, 5, 5)];
    oring.backgroundColor = [UIColor clearColor];
    oring.layer.cornerRadius = (cs-10)/2;
    oring.layer.borderColor = rgba(255, 255, 255, 0.05).CGColor;
    oring.layer.borderWidth = 0.5;
    oring.userInteractionEnabled = NO;
    [tapCircle addSubview:oring];

    UILabel *tl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    tl.text = @"515";
    tl.textColor = rgba(255, 255, 255, 0.5);
    tl.font = [UIFont boldSystemFontOfSize:16];
    tl.textAlignment = NSTextAlignmentCenter;
    [tapCircle addSubview:tl];

    UIPanGestureRecognizer *cg = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)];
    [tapCircle addGestureRecognizer:cg];

    UILongPressGestureRecognizer *mlg = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMaster:)];
    mlg.minimumPressDuration = 1.0;
    [tapCircle addGestureRecognizer:mlg];

    [w addSubview:tapCircle];
    [w bringSubviewToFront:tapCircle];

    udpInit();

    // Rainbow color cycling
    static CGFloat hue = 0;
    rainbowTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(rainbowTimer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(rainbowTimer, ^{
        if (!accentLine || !ctrlBox) return;
        hue += 1.0/14.0;
        if (hue > 1) hue -= 1;
        UIColor *c1 = [UIColor colorWithHue:hue saturation:0.9 brightness:0.9 alpha:0.8];
        UIColor *c2 = [UIColor colorWithHue:fmod(hue+0.3,1) saturation:0.7 brightness:0.8 alpha:0.4];
        accentLine.colors = @[(id)c1.CGColor, (id)c2.CGColor, (id)rgba(60,130,255,0).CGColor];
        ctrlBox.layer.borderColor = [UIColor colorWithHue:hue saturation:0.6 brightness:0.5 alpha:0.3].CGColor;
    });
    dispatch_resume(rainbowTimer);

    NSLog(@"[YLT] UI ready");
}

+ (UIImage *)thumbImage {
    return [UIImage imageWithCGImage:({
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(13, 13), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(ctx, rgba(255, 255, 255, 0.85).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(0.5, 0.5, 12, 12));
        CGContextSetFillColorWithColor(ctx, rgba(60, 130, 255, 0.25).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(2.5, 2.5, 8, 8));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        img.CGImage;
    })];
}

#pragma mark - Actions

+ (void)updateRunUI {
    if (!runBtn) return;
    if (running) {
        runBtn.backgroundColor = rgba(200, 60, 60, 1);
        [runBtn setTitle:@"■  إيقاف" forState:UIControlStateNormal];
    } else {
        runBtn.backgroundColor = rgba(40, 100, 230, 1);
        [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    }
}

+ (void)updateMergeUI {
    if (!linkBtn) return;
    if (isMain) {
        linkBtn.backgroundColor = rgba(60, 200, 100, 0.5);
        [linkBtn setTitle:@"دمج" forState:UIControlStateNormal];
        [linkBtn setTitleColor:rgba(100, 255, 150, 1) forState:UIControlStateNormal];
    } else {
        linkBtn.backgroundColor = rgba(40, 40, 65, 0.7);
        [linkBtn setTitle:@"دمج" forState:UIControlStateNormal];
        [linkBtn setTitleColor:rgba(120, 130, 160, 0.7) forState:UIControlStateNormal];
    }
}

+ (void)toggleMerge {
    isMain = !isMain;
    [self updateMergeUI];
    if (isMain) {
        tapCircle.layer.borderColor = rgba(60, 200, 100, 0.7).CGColor;
        tapCircle.layer.borderWidth = 2.5;
        [self alert:@"تم دمج الحسابات ✓" msg:@"جميع النسخ مرتبطة بهذه النسخة"];
        udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
        if (running) udpSend(@"RUN");
    } else {
        tapCircle.layer.borderColor = rgba(255, 255, 255, 0.1).CGColor;
        tapCircle.layer.borderWidth = 1.5;
    }
}

+ (void)toggleRun {
    running = !running;
    [self updateRunUI];
    if (running) {
        [Tapper start];
        udpSend(@"RUN");
    } else {
        [Tapper stop];
        udpSend(@"STOP");
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
    if (isMain) {
        static CFTimeInterval lastPos = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (g.state == UIGestureRecognizerStateEnded || now - lastPos > 0.05) {
            lastPos = now;
            udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y]);
        }
    }
}

+ (void)setMaster:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isMain = !isMain;
        [self updateMergeUI];
        if (isMain) {
            tapCircle.layer.borderColor = rgba(255, 200, 50, 0.7).CGColor;
            tapCircle.layer.borderWidth = 2;
            [self alert:@"✓ رئيسي" msg:@"النسخة الرئيسية - تتحكم بجميع النسخ"];
            udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
        } else {
            tapCircle.layer.borderColor = rgba(255, 255, 255, 0.1).CGColor;
            tapCircle.layer.borderWidth = 1.5;
            [self alert:@"✕ تابع" msg:@"تم إلغاء التحكم الرئيسي"];
        }
    }
}

+ (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [activeWindow().rootViewController presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Constructor

__attribute__((constructor)) static void init() {
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

    // Periodic room check (every 3s keeps UI on top inside rooms)
    dispatch_async(dispatch_get_main_queue(), ^{
        topTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(topTimer, DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(topTimer, ^{ ensureOnTop(); });
        dispatch_resume(topTimer);
    });
}
