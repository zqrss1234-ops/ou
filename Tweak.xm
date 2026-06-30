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

static UIColor *rgb(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];
}

static UIColor *rgba(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
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

    [UIView animateWithDuration:0.02 animations:^{
        tapCircle.transform = CGAffineTransformMakeScale(0.82, 0.82);
        tapCircle.backgroundColor = rgba(255, 200, 50, 0.95);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.02 animations:^{
            tapCircle.transform = CGAffineTransformIdentity;
            tapCircle.backgroundColor = isMain ? rgba(80, 80, 80, 0.95) : rgba(80, 80, 80, 0.9);
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

    UIView *fx = [[UIView alloc] initWithFrame:CGRectMake(0,0,14,14)];
    fx.center = pt; fx.backgroundColor = rgba(255, 255, 255, 0.6);
    fx.layer.cornerRadius = 7; fx.userInteractionEnabled = NO;
    [w addSubview:fx];
    [UIView animateWithDuration:0.3 animations:^{
        fx.alpha = 0; fx.transform = CGAffineTransformMakeScale(3.5, 3.5);
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
        if (retries++ < 30)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self buildUI]; });
        return;
    }
    if (ctrlBox) return;

    NSLog(@"[YLT] Building UI");
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;

    UIColor *bg = rgba(22, 22, 38, 0.94);
    UIColor *borderC = rgba(80, 140, 255, 0.35);
    UIColor *accent = rgba(80, 140, 255, 1);
    UIColor *goldAccent = rgba(255, 200, 50, 1);
    UIColor *textLight = rgba(220, 220, 240, 1);
    UIColor *textDim = rgba(150, 160, 190, 1);
    UIColor *btnGreen = rgba(60, 200, 100, 1);
    UIColor *btnRed = rgba(255, 80, 70, 1);

    // ---- Control Box ----
    CGFloat bw = 200, bh = 210, bx = 16, by = 50;
    ctrlBox = [[UIView alloc] initWithFrame:CGRectMake(bx, by, bw, bh)];
    ctrlBox.backgroundColor = bg;
    ctrlBox.layer.cornerRadius = 20;
    ctrlBox.layer.borderColor = borderC.CGColor;
    ctrlBox.layer.borderWidth = 1;
    ctrlBox.layer.shadowColor = UIColor.blackColor.CGColor;
    ctrlBox.layer.shadowOpacity = 0.5;
    ctrlBox.layer.shadowOffset = CGSizeMake(0, 8);
    ctrlBox.layer.shadowRadius = 24;
    ctrlBox.tag = 100;

    CAGradientLayer *bgGrad = [CAGradientLayer layer];
    bgGrad.frame = ctrlBox.bounds;
    bgGrad.colors = @[(id)rgba(35, 35, 60, 0.3).CGColor, (id)rgba(15, 15, 30, 0).CGColor];
    bgGrad.startPoint = CGPointMake(0, 0);
    bgGrad.endPoint = CGPointMake(1, 1);
    [ctrlBox.layer addSublayer:bgGrad];

    CGFloat yy = 8;

    // ---- Top Names Strip ----
    CGFloat nsW = bw-16, nsH = 28, nsX = 8;
    UIView *nameStripView = [[UIView alloc] initWithFrame:CGRectMake(nsX, yy, nsW, nsH)];
    nameStripView.backgroundColor = rgba(30, 30, 55, 0.7);
    nameStripView.layer.cornerRadius = 14;
    nameStripView.clipsToBounds = YES;
    nameStripView.tag = 400;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, nsW, nsH)];
    scroll.showsHorizontalScrollIndicator = NO;
    CGFloat sx = 6, sh2 = 20, sy2 = (nsH-sh2)/2;
    for (NSString *n in accountNames) {
        CGFloat sw2 = [n sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold]}].width + 14;
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(sx, sy2, sw2, sh2)];
        pill.backgroundColor = rgba(50, 80, 160, 0.6);
        pill.layer.cornerRadius = 5;
        UILabel *ll = [[UILabel alloc] initWithFrame:pill.bounds];
        ll.text = n; ll.textColor = textLight;
        ll.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
        ll.textAlignment = NSTextAlignmentCenter;
        [pill addSubview:ll];
        [scroll addSubview:pill];
        sx += sw2 + 4;
    }
    scroll.contentSize = CGSizeMake(sx, nsH);
    [nameStripView addSubview:scroll];
    [ctrlBox addSubview:nameStripView];
    yy += nsH + 6;

    // ---- Name Pills Row ----
    CGFloat pillY = yy, pillH = 22, pillGap = 4;
    CGFloat px2 = 8;
    for (NSString *n in accountNames) {
        CGFloat pw2 = [n sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:8 weight:UIFontWeightMedium]}].width + 12;
        if (px2 + pw2 > bw - 8) break;
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(px2, pillY, pw2, pillH)];
        pill.backgroundColor = rgba(60, 100, 180, 0.5);
        pill.layer.cornerRadius = 4;
        pill.layer.borderColor = rgba(80, 140, 255, 0.3).CGColor;
        pill.layer.borderWidth = 0.5;
        UILabel *ll = [[UILabel alloc] initWithFrame:pill.bounds];
        ll.text = n; ll.textColor = rgba(200, 210, 240, 1);
        ll.font = [UIFont systemFontOfSize:8 weight:UIFontWeightMedium];
        ll.textAlignment = NSTextAlignmentCenter;
        [pill addSubview:ll];
        [ctrlBox addSubview:pill];
        px2 += pw2 + pillGap;
    }
    yy += pillH + 6;

    // ---- Speed Slider (ms) ----
    CGFloat slY = yy + 2;
    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, slY, 50, 14)];
    spLbl.text = @"سرعة";
    spLbl.textColor = textDim;
    spLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    [ctrlBox addSubview:spLbl];

    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(bw-80, slY, 70, 14)];
    delayLabel.text = @"30 ms";
    delayLabel.textColor = goldAccent;
    delayLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    delayLabel.textAlignment = NSTextAlignmentRight;
    [ctrlBox addSubview:delayLabel];

    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(8, slY+16, bw-16, 20)];
    delaySlider.minimumValue = 5;
    delaySlider.maximumValue = 500;
    delaySlider.value = 30;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = accent;
    delaySlider.maximumTrackTintColor = rgba(50, 50, 75, 1);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBox addSubview:delaySlider];
    yy = slY + 16 + 24;

    // ---- Buttons Row ----
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(8, yy, (bw-24)*0.62, 36);
    runBtn.backgroundColor = btnGreen;
    runBtn.layer.cornerRadius = 14;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:runBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(CGRectGetMaxX(runBtn.frame)+8, yy, (bw-24)*0.38, 36);
    hideBtn.backgroundColor = rgba(50, 50, 75, 1);
    hideBtn.layer.cornerRadius = 14;
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [hideBtn setTitle:@"✕" forState:UIControlStateNormal];
    [hideBtn setTitleColor:textLight forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hideAll) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:hideBtn];
    yy += 40;

    // ---- Bottom Status Strip ----
    UIView *botStrip = [[UIView alloc] initWithFrame:CGRectMake(8, yy, bw-16, 14)];
    botStrip.backgroundColor = rgba(30, 30, 55, 0.5);
    botStrip.layer.cornerRadius = 7;
    UILabel *botLbl = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, botStrip.frame.size.width-8, 14)];
    botLbl.text = @"⏻  مستعد  ·  اضغط مطولاً للتحكم";
    botLbl.textColor = textDim;
    botLbl.font = [UIFont systemFontOfSize:7.5];
    botLbl.textAlignment = NSTextAlignmentCenter;
    [botStrip addSubview:botLbl];
    [ctrlBox addSubview:botStrip];

    // ---- Gesture: Drag ----
    UIPanGestureRecognizer *dragG = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [ctrlBox addGestureRecognizer:dragG];

    [w addSubview:ctrlBox];
    [w bringSubviewToFront:ctrlBox];

    // ---- Tap Circle (Black with 515) ----
    CGFloat cs = 52, cx = (sw-cs)/2, cy = sh*0.55;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(40, 40, 40, 0.95);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(255, 255, 255, 0.2).CGColor;
    tapCircle.layer.borderWidth = 1.5;
    tapCircle.layer.shadowColor = UIColor.blackColor.CGColor;
    tapCircle.layer.shadowOpacity = 0.6;
    tapCircle.layer.shadowOffset = CGSizeMake(0, 0);
    tapCircle.layer.shadowRadius = 14;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    UILabel *tl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    tl.text = @"515";
    tl.textColor = rgba(255, 255, 255, 0.7);
    tl.font = [UIFont boldSystemFontOfSize:20];
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
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(ctx, rgba(255, 255, 255, 0.9).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(1, 1, 14, 14));
        CGContextSetFillColorWithColor(ctx, rgba(80, 140, 255, 0.3).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(3, 3, 10, 10));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        img.CGImage;
    })];
}

#pragma mark - Actions

+ (void)toggleRun {
    running = !running;
    if (running) {
        runBtn.backgroundColor = rgba(255, 80, 70, 1);
        [runBtn setTitle:@"■  إيقاف" forState:UIControlStateNormal];
        [Tapper start];
        udpSend(@"RUN");
    } else {
        runBtn.backgroundColor = rgba(60, 200, 100, 1);
        [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
        [Tapper stop];
        udpSend(@"STOP");
    }
}

+ (void)speedChange {
    CGFloat v = round(delaySlider.value);
    delaySlider.value = v;
    currentDelay = v;
    delayLabel.text = [NSString stringWithFormat:@"%.0f ms", v];
    if (running) { [Tapper stop]; [Tapper start]; }
}

+ (void)hideAll {
    ctrlBox.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = activeWindow();
        if (!w) return;
        if (ctrlBox.hidden) {
            ctrlBox.hidden = NO;
            [w bringSubviewToFront:ctrlBox];
        }
    });
}

+ (void)showAll {
    ctrlBox.hidden = NO;
    [activeWindow() bringSubviewToFront:ctrlBox];
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
        tapCircle.layer.borderColor = rgba(255, 200, 50, 0.8).CGColor;
        tapCircle.layer.borderWidth = 2.5;
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
        if (ctrlBox) {
            [activeWindow() bringSubviewToFront:ctrlBox];
            [activeWindow() bringSubviewToFront:tapCircle];
        } else {
            [Controller buildUI];
        }
    }];
}
