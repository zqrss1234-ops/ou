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

static UIView *ctrlBar = nil;
static UIView *tapCircle = nil;
static UISlider *delaySlider = nil;
static UILabel *delayLabel = nil;
static UIButton *runBtn = nil;
static dispatch_source_t tapTimer = NULL;
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
    if (ctrlBar && ctrlBar.superview != w) {
        [ctrlBar removeFromSuperview];
        [w addSubview:ctrlBar];
    }
    if (tapCircle && tapCircle.superview != w) {
        [tapCircle removeFromSuperview];
        [w addSubview:tapCircle];
    }
    if (ctrlBar) [w bringSubviewToFront:ctrlBar];
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
            tapCircle.backgroundColor = rgba(20, 20, 20, 0.95);
        }];
    }];

    UIWindow *w = activeWindow();
    if (!w) return;

    BOOL ch = tapCircle.hidden, bh = ctrlBar.hidden;
    tapCircle.hidden = YES; ctrlBar.hidden = YES;

    CGPoint pt = [tapCircle.superview convertPoint:tapCircle.center toView:w];
    UIView *target = [w hitTest:pt withEvent:nil];

    tapCircle.hidden = ch; ctrlBar.hidden = bh;

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
    fx.center = pt; fx.backgroundColor = rgba(100, 180, 255, 0.4);
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
    if (ctrlBar) { ensureOnTop(); return; }

    NSLog(@"[YLT] Building UI");
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;

    // ---- Names marquee string ----
    NSMutableString *marqueeStr = [NSMutableString string];
    for (NSString *n in accountNames) {
        [marqueeStr appendFormat:@"  ◉  %@", n];
    }
    [marqueeStr appendString:@"  ◉  "];

    // ---- Control Bar (Horizontal Rectangle) ----
    CGFloat bw = sw - 20, bh = 56, bx = 10, by = sh * 0.12;
    ctrlBar = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bw, bh)];
    ctrlBar.backgroundColor = rgba(15, 15, 22, 0.92);
    ctrlBar.layer.cornerRadius = 20;
    ctrlBar.layer.borderColor = rgba(70, 70, 100, 0.3).CGColor;
    ctrlBar.layer.borderWidth = 0.5;
    ctrlBar.layer.shadowColor = UIColor.blackColor.CGColor;
    ctrlBar.layer.shadowOpacity = 0.5;
    ctrlBar.layer.shadowOffset = CGSizeMake(0, 6);
    ctrlBar.layer.shadowRadius = 20;
    ctrlBar.tag = 100;
    ctrlBar.clipsToBounds = NO;

    // Subtle top border glow
    CAGradientLayer *topGlow = [CAGradientLayer layer];
    topGlow.frame = CGRectMake(0, 0, bw, 2);
    topGlow.colors = @[(id)rgba(60, 130, 255, 0.6).CGColor,
                       (id)rgba(60, 130, 255, 0).CGColor];
    topGlow.startPoint = CGPointMake(0, 0);
    topGlow.endPoint = CGPointMake(1, 0);
    [ctrlBar.layer addSublayer:topGlow];

    // ---- Marquee Names Strip ----
    UIView *marqueeContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 0, bw-130, bh)];
    marqueeContainer.clipsToBounds = YES;
    marqueeContainer.backgroundColor = [UIColor clearColor];

    UILabel *marqueeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [marqueeStr sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}].width, bh)];
    marqueeLabel.text = marqueeStr;
    marqueeLabel.textColor = rgba(220, 225, 240, 0.85);
    marqueeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [marqueeContainer addSubview:marqueeLabel];

    [ctrlBar addSubview:marqueeContainer];

    // Marquee animation
    CGFloat totalW = marqueeLabel.frame.size.width;
    CGFloat containerW = marqueeContainer.frame.size.width;
    if (totalW > containerW) {
        [UIView animateWithDuration:totalW/25.0 delay:0 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionRepeat animations:^{
            marqueeLabel.transform = CGAffineTransformMakeTranslation(-(totalW - containerW + 20), 0);
        } completion:nil];
    }

    // ---- Right side controls ----
    CGFloat rx = bw - 115;

    // Speed label
    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(rx, 2, 55, 14)];
    delayLabel.text = @"30ms";
    delayLabel.textColor = rgba(100, 180, 255, 0.7);
    delayLabel.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    delayLabel.textAlignment = NSTextAlignmentCenter;
    [ctrlBar addSubview:delayLabel];

    // Slider (thin)
    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(rx, 16, 55, 12)];
    delaySlider.minimumValue = 5;
    delaySlider.maximumValue = 500;
    delaySlider.value = 30;
    delaySlider.continuous = NO;
    delaySlider.minimumTrackTintColor = rgba(60, 130, 255, 0.7);
    delaySlider.maximumTrackTintColor = rgba(40, 40, 60, 0.5);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBar addSubview:delaySlider];

    // Run/Stop button (Blue)
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(bw-52, 6, 44, 44);
    runBtn.backgroundColor = rgba(40, 100, 230, 1);
    runBtn.layer.cornerRadius = 16;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    runBtn.titleLabel.numberOfLines = 2;
    runBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [runBtn setTitle:@"▶\nتشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:rgba(220, 230, 255, 1) forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBar addSubview:runBtn];

    // Drag gesture
    UIPanGestureRecognizer *dragG = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [ctrlBar addGestureRecognizer:dragG];

    // Long press for expanded settings
    UILongPressGestureRecognizer *lpG = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(expandSettings:)];
    lpG.minimumPressDuration = 0.5;
    [ctrlBar addGestureRecognizer:lpG];

    // Double tap to hide
    UITapGestureRecognizer *dtG = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideAll)];
    dtG.numberOfTapsRequired = 2;
    [ctrlBar addGestureRecognizer:dtG];

    [w addSubview:ctrlBar];
    [w bringSubviewToFront:ctrlBar];

    // ---- Tap Circle (Pure Black) ----
    CGFloat cs = 46, cx = (sw-cs)/2, cy = sh*0.6;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(18, 18, 18, 0.95);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(255, 255, 255, 0.12).CGColor;
    tapCircle.layer.borderWidth = 1.5;
    tapCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    tapCircle.layer.shadowOpacity = 0.5;
    tapCircle.layer.shadowOffset = CGSizeMake(0, 0);
    tapCircle.layer.shadowRadius = 10;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    // Outer ring
    UIView *oring = [[UIView alloc] initWithFrame:CGRectInset(tapCircle.bounds, 5, 5)];
    oring.backgroundColor = [UIColor clearColor];
    oring.layer.cornerRadius = (cs-10)/2;
    oring.layer.borderColor = rgba(255, 255, 255, 0.06).CGColor;
    oring.layer.borderWidth = 0.5;
    oring.userInteractionEnabled = NO;
    [tapCircle addSubview:oring];

    UILabel *tl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    tl.text = @"515";
    tl.textColor = rgba(255, 255, 255, 0.55);
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
    NSLog(@"[YLT] UI ready");
}

+ (UIImage *)thumbImage {
    return [UIImage imageWithCGImage:({
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(12, 12), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(ctx, rgba(255, 255, 255, 0.85).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, 12, 12));
        CGContextSetFillColorWithColor(ctx, rgba(60, 130, 255, 0.3).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(2, 2, 8, 8));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        img.CGImage;
    })];
}

#pragma mark - Actions

+ (void)toggleRun {
    running = !running;
    if (running) {
        runBtn.backgroundColor = rgba(200, 55, 55, 1);
        [runBtn setTitle:@"■\nإيقاف" forState:UIControlStateNormal];
        [Tapper start];
        udpSend(@"RUN");
    } else {
        runBtn.backgroundColor = rgba(40, 100, 230, 1);
        [runBtn setTitle:@"▶\nتشغيل" forState:UIControlStateNormal];
        [Tapper stop];
        udpSend(@"STOP");
    }
}

+ (void)speedChange {
    CGFloat v = round(delaySlider.value);
    delaySlider.value = v;
    currentDelay = v;
    delayLabel.text = [NSString stringWithFormat:@"%.0fms", v];
    if (running) { [Tapper stop]; [Tapper start]; }
}

+ (void)hideAll {
    ctrlBar.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ctrlBar.hidden) {
            ctrlBar.hidden = NO;
            [activeWindow() bringSubviewToFront:ctrlBar];
        }
    });
}

+ (void)expandSettings:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        NSString *status = running ? @"تشغيل ✓" : @"إيقاف";
        NSString *speed = [NSString stringWithFormat:@"%.0f ms", currentDelay];
        NSString *master = isMain ? @"رئيسي ✓" : @"اضغط مطولاً على الدائرة";
        NSString *info = [NSString stringWithFormat:@"الحالة: %@\nالسرعة: %@\nالتحكم: %@", status, speed, master];
        [self alert:@"YLTool" msg:info];
    }
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
        runBtn.backgroundColor = rgba(255, 180, 40, 1);
        [runBtn setTitle:@"★\nرئيسي" forState:UIControlStateNormal];
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
        if (w && !w.hidden && w.rootViewController && !ctrlBar) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
        if (!ctrlBar) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
    }];
}
