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
static UILabel *nameLabel = nil;
static UISlider *delaySlider = nil;
static UILabel *delayLabel = nil;
static UIButton *runBtn = nil;
static dispatch_source_t tapTimer = NULL;
static dispatch_source_t scrollTimer = NULL;
static BOOL running = NO;
static BOOL isMain = NO;
static CGFloat currentDelay = 30.0;
static int udpSock = -1;
static int nameIndex = 0;

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
    if (ctrlBox && ctrlBox.superview != w) {
        [ctrlBox removeFromSuperview];
        [w addSubview:ctrlBox];
    }
    if (tapCircle && tapCircle.superview != w) {
        [tapCircle removeFromSuperview];
        [w addSubview:tapCircle];
    }
    if (ctrlBox) [w bringSubviewToFront:ctrlBox];
    if (tapCircle) [w bringSubviewToFront:tapCircle];
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
                        if (!running && !isMain) {
                            running = YES;
                            [NSClassFromString(@"Tapper") performSelector:@selector(start)];
                        }
                    } else if ([m isEqualToString:@"STOP"]) {
                        if (running && !isMain) {
                            running = NO;
                            [NSClassFromString(@"Tapper") performSelector:@selector(stop)];
                        }
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
            tapCircle.backgroundColor = rgba(25, 25, 25, 0.95);
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

    UIControl *ctrl = nil;
    if ([target isKindOfClass:[UIControl class]]) ctrl = (UIControl *)target;
    else {
        UIResponder *r = target.nextResponder;
        while (r) { if ([r isKindOfClass:[UIControl class]]) { ctrl = (UIControl *)r; break; } r = r.nextResponder; }
    }
    if (ctrl) {
        [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
        [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    for (UIGestureRecognizer *gr in [target.gestureRecognizers copy]) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr.enabled) {
            gr.enabled = NO;
            gr.enabled = YES;
        }
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
    if (ctrlBox) {
        ensureOnTop();
        return;
    }

    NSLog(@"[YLT] Building UI");
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;

    // ---- Control Box (Dark Elegant Card) ----
    CGFloat bw = 195, bh = 175, bx = (sw-bw)/2, by = sh*0.18;
    ctrlBox = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bw, bh)];
    ctrlBox.backgroundColor = rgba(18, 18, 28, 0.92);
    ctrlBox.layer.cornerRadius = 24;
    ctrlBox.layer.borderColor = rgba(60, 60, 90, 0.4).CGColor;
    ctrlBox.layer.borderWidth = 0.5;
    ctrlBox.layer.shadowColor = UIColor.blackColor.CGColor;
    ctrlBox.layer.shadowOpacity = 0.6;
    ctrlBox.layer.shadowOffset = CGSizeMake(0, 10);
    ctrlBox.layer.shadowRadius = 30;
    ctrlBox.tag = 100;

    // Gradient accent line at top
    CAGradientLayer *accentLine = [CAGradientLayer layer];
    accentLine.frame = CGRectMake(0, 0, bw, 3);
    accentLine.colors = @[(id)rgba(60, 120, 255, 0.8).CGColor,
                          (id)rgba(120, 80, 255, 0.6).CGColor,
                          (id)rgba(60, 120, 255, 0).CGColor];
    accentLine.startPoint = CGPointMake(0, 0);
    accentLine.endPoint = CGPointMake(1, 0);
    [ctrlBox.layer addSublayer:accentLine];

    // Subtle inner glow
    CAGradientLayer *innerGlow = [CAGradientLayer layer];
    innerGlow.frame = ctrlBox.bounds;
    innerGlow.colors = @[(id)rgba(40, 40, 70, 0.15).CGColor,
                         (id)rgba(15, 15, 25, 0).CGColor];
    innerGlow.startPoint = CGPointMake(0, 0);
    innerGlow.endPoint = CGPointMake(1, 1);
    [ctrlBox.layer addSublayer:innerGlow];

    CGFloat yy = 12;

    // ---- Auto-Scrolling Names ----
    UIView *nameBox = [[UIView alloc] initWithFrame:CGRectMake(12, yy, bw-24, 32)];
    nameBox.backgroundColor = rgba(30, 30, 50, 0.6);
    nameBox.layer.cornerRadius = 16;
    nameBox.clipsToBounds = YES;

    nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, nameBox.frame.size.width-40, 32)];
    nameLabel.text = accountNames[0];
    nameLabel.textColor = rgba(220, 220, 240, 1);
    nameLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [nameBox addSubview:nameLabel];

    // Left/right decorative dots
    UIView *dotL = [[UIView alloc] initWithFrame:CGRectMake(8, 14, 4, 4)];
    dotL.backgroundColor = rgba(80, 140, 255, 0.6);
    dotL.layer.cornerRadius = 2;
    [nameBox addSubview:dotL];
    UIView *dotR = [[UIView alloc] initWithFrame:CGRectMake(nameBox.frame.size.width-12, 14, 4, 4)];
    dotR.backgroundColor = rgba(80, 140, 255, 0.6);
    dotR.layer.cornerRadius = 2;
    [nameBox addSubview:dotR];

    [ctrlBox addSubview:nameBox];
    yy += 38;

    // Start auto-scroll timer
    nameIndex = 0;
    scrollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(scrollTimer, DISPATCH_TIME_NOW, 1.8 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(scrollTimer, ^{
        nameIndex = (nameIndex + 1) % accountNames.count;
        [UIView transitionWithView:nameLabel duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            nameLabel.text = accountNames[nameIndex];
        } completion:nil];
    });
    dispatch_resume(scrollTimer);

    // ---- Speed Label ----
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, yy, 80, 16)];
    spLbl.text = @"سرعة النقر";
    spLbl.textColor = rgba(140, 150, 180, 0.9);
    spLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    [ctrlBox addSubview:spLbl];

    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(bw-90, yy, 74, 16)];
    delayLabel.text = @"030 ms";
    delayLabel.textColor = rgba(100, 180, 255, 1);
    delayLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12];
    delayLabel.textAlignment = NSTextAlignmentRight;
    [ctrlBox addSubview:delayLabel];
    yy += 20;

    // ---- Speed Slider ----
    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(10, yy, bw-20, 24)];
    delaySlider.minimumValue = 5;
    delaySlider.maximumValue = 500;
    delaySlider.value = 30;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = rgba(60, 130, 255, 1);
    delaySlider.maximumTrackTintColor = rgba(40, 40, 65, 0.8);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBox addSubview:delaySlider];
    yy += 28;

    // ---- Buttons Row ----
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(12, yy, (bw-32)*0.62, 38);
    runBtn.backgroundColor = rgba(40, 100, 230, 1);
    runBtn.layer.cornerRadius = 16;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:rgba(220, 230, 255, 1) forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:runBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(CGRectGetMaxX(runBtn.frame)+8, yy, (bw-32)*0.38, 38);
    hideBtn.backgroundColor = rgba(40, 40, 60, 0.8);
    hideBtn.layer.cornerRadius = 16;
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [hideBtn setTitle:@"✕ إخفاء" forState:UIControlStateNormal];
    [hideBtn setTitleColor:rgba(160, 170, 200, 1) forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hideAll) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:hideBtn];
    yy += 44;

    // ---- Footer ----
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, yy, bw, bh-yy-4)];
    footer.text = @"حقوق عبدالإله";
    footer.textColor = rgba(100, 110, 140, 0.5);
    footer.font = [UIFont systemFontOfSize:7.5];
    footer.textAlignment = NSTextAlignmentCenter;
    [ctrlBox addSubview:footer];

    // Drag gesture
    UIPanGestureRecognizer *dragG = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [ctrlBox addGestureRecognizer:dragG];

    [w addSubview:ctrlBox];
    [w bringSubviewToFront:ctrlBox];

    // ---- Tap Circle (Dark minimal) ----
    CGFloat cs = 48, cx = (sw-cs)/2, cy = sh*0.6;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(25, 25, 25, 0.95);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(255, 255, 255, 0.15).CGColor;
    tapCircle.layer.borderWidth = 1.5;
    tapCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    tapCircle.layer.shadowOpacity = 0.5;
    tapCircle.layer.shadowOffset = CGSizeMake(0, 0);
    tapCircle.layer.shadowRadius = 12;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    // Subtle ring
    UIView *ring = [[UIView alloc] initWithFrame:CGRectInset(tapCircle.bounds, 4, 4)];
    ring.backgroundColor = [UIColor clearColor];
    ring.layer.cornerRadius = (cs-8)/2;
    ring.layer.borderColor = rgba(255, 255, 255, 0.08).CGColor;
    ring.layer.borderWidth = 0.5;
    ring.userInteractionEnabled = NO;
    [tapCircle addSubview:ring];

    UILabel *tl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    tl.text = @"515";
    tl.textColor = rgba(255, 255, 255, 0.65);
    tl.font = [UIFont boldSystemFontOfSize:17];
    tl.textAlignment = NSTextAlignmentCenter;
    [tapCircle addSubview:tl];

    UIPanGestureRecognizer *cg = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)];
    [tapCircle addGestureRecognizer:cg];

    UILongPressGestureRecognizer *lg = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMaster:)];
    lg.minimumPressDuration = 1.0;
    [tapCircle addGestureRecognizer:lg];

    [w addSubview:tapCircle];
    [w bringSubviewToFront:tapCircle];

    udpInit();
    NSLog(@"[YLT] UI ready");
}

+ (UIImage *)thumbImage {
    return [UIImage imageWithCGImage:({
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(14, 14), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetShadowWithColor(ctx, CGSizeZero, 3, rgba(60, 130, 255, 0.4).CGColor);
        CGContextSetFillColorWithColor(ctx, rgba(255, 255, 255, 0.9).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(1, 1, 12, 12));
        CGContextSetFillColorWithColor(ctx, rgba(60, 130, 255, 0.25).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(3, 3, 8, 8));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        img.CGImage;
    })];
}

#pragma mark - Actions

+ (void)toggleRun {
    running = !running;
    if (running) {
        runBtn.backgroundColor = rgba(200, 60, 60, 1);
        [runBtn setTitle:@"■  إيقاف" forState:UIControlStateNormal];
        [Tapper start];
        udpSend(@"RUN");
    } else {
        runBtn.backgroundColor = rgba(40, 100, 230, 1);
        [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
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
    if (g.state == UIGestureRecognizerStateEnded && isMain)
        udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y]);
}

+ (void)setMaster:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isMain = YES;
        tapCircle.layer.borderColor = rgba(255, 200, 50, 0.7).CGColor;
        tapCircle.layer.borderWidth = 2;
        [self alert:@"✓ رئيسي" msg:@"النسخة الرئيسية - تتحكم بجميع النسخ"];
        udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
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
}
