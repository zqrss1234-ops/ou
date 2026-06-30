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

static UIView *controlPanel = nil;
static UIView *miniPanel = nil;
static UIView *namesStrip = nil;
static UIView *tapCircle = nil;
static UIButton *runBtn = nil;
static UISlider *delaySlider = nil;
static UILabel *delayLabel = nil;
static dispatch_source_t tapTimer = NULL;
static BOOL running = NO;
static BOOL isMain = NO;
static CGFloat currentDelay = 0.0;
static int udpSock = -1;

#pragma mark - Helpers

static UIWindow *appWindow(void) {
    if (@available(iOS 13.0, *))
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive)
                { UIWindow *w = [(UIWindowScene *)s windows].firstObject; if (w && !w.hidden) return w; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (w && !w.hidden) return w;
#pragma clang diagnostic pop
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden && w.rootViewController) return w;
    return nil;
}

static UIColor *color(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

static UIView *makeBlur(CGFloat r) {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [UIColor clearColor];
    UIBlurEffect *be = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:be];
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.layer.cornerRadius = r;
    blur.clipsToBounds = YES;
    [v addSubview:blur];
    return v;
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
                    } else if ([m isEqualToString:@"TAP"]) {
                        if (!isMain) [[NSClassFromString(@"Tapper") performSelector:@selector(fireTap)]];
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
+ (void)fireTap;
+ (void)start;
+ (void)stop;
@end

@implementation Tapper

+ (void)fireTap {
    if (!tapCircle || !running) return;

    [UIView animateWithDuration:0.02 animations:^{
        tapCircle.transform = CGAffineTransformMakeScale(0.82, 0.82);
        tapCircle.backgroundColor = color(255, 200, 50, 0.95);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.02 animations:^{
            tapCircle.transform = CGAffineTransformIdentity;
            tapCircle.backgroundColor = isMain ? color(255, 69, 58, 0.95) : color(255, 159, 10, 0.9);
        }];
    }];

    UIWindow *w = appWindow();
    if (!w) return;

    BOOL ph = controlPanel.hidden, nh = namesStrip.hidden, ch = tapCircle.hidden;
    controlPanel.hidden = YES; namesStrip.hidden = YES; tapCircle.hidden = YES;

    CGPoint pt = [tapCircle.superview convertPoint:tapCircle.center toView:w];
    UIView *target = [w hitTest:pt withEvent:nil];

    controlPanel.hidden = ph; namesStrip.hidden = nh; tapCircle.hidden = ch;

    if (!target || target == tapCircle) return;

    UIControl *ctrl = nil;
    if ([target isKindOfClass:[UIControl class]]) ctrl = (UIControl *)target;
    else {
        UIResponder *r = target.nextResponder;
        while (r) { if ([r isKindOfClass:[UIControl class]]) { ctrl = (UIControl *)r; break; } r = r.nextResponder; }
    }
    [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
    [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];

    if (![target isKindOfClass:[UIControl class]] && [target respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        if (ctrl) { /* already handled */ }
    }

    UIView *fx = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,12)];
    fx.center = pt; fx.backgroundColor = color(100, 200, 255, 0.8);
    fx.layer.cornerRadius = 6; fx.userInteractionEnabled = NO;
    [w addSubview:fx];
    [UIView animateWithDuration:0.25 animations:^{
        fx.alpha = 0; fx.transform = CGAffineTransformMakeScale(3, 3);
    } completion:^(BOOL f) { [fx removeFromSuperview]; }];

    udpSend(@"TAP");
}

+ (void)start {
    if (tapTimer) return;
    CGFloat interval = currentDelay;
    if (interval < 0.005) interval = 0.005;
    tapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(tapTimer, DISPATCH_TIME_NOW, interval * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(tapTimer, ^{ [self fireTap]; });
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
    UIWindow *w = appWindow();
    if (!w) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self buildUI]; }); return; }
    if (controlPanel) return;

    NSLog(@"[YLT] Building UI");
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;

    // Elegant colors
    UIColor *bg = color(18, 18, 30, 0.92);
    UIColor *border = color(60, 120, 255, 0.5);
    UIColor *accent = color(60, 120, 255, 1);
    UIColor *greenOff = color(50, 200, 80, 1);

    // Control Panel
    CGFloat pw = 200, ph = 155, px = 16, py = 50;
    controlPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    controlPanel.backgroundColor = bg;
    controlPanel.layer.cornerRadius = 18;
    controlPanel.layer.borderColor = border.CGColor;
    controlPanel.layer.borderWidth = 1;
    controlPanel.layer.shadowColor = UIColor.blackColor.CGColor;
    controlPanel.layer.shadowOpacity = 0.4;
    controlPanel.layer.shadowOffset = CGSizeMake(0, 6);
    controlPanel.layer.shadowRadius = 20;
    controlPanel.tag = 100;

    // Gradient overlay
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = controlPanel.bounds;
    grad.colors = @[(id)color(30, 30, 60, 0.3).CGColor, (id)color(10, 10, 20, 0).CGColor];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    [controlPanel.layer addSublayer:grad];

    CGFloat y = 10;

    // Run/Stop
    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(10, y, pw-20, 38);
    runBtn.backgroundColor = greenOff;
    runBtn.layer.cornerRadius = 12;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [controlPanel addSubview:runBtn];
    y += 44;

    // Delay Slider
    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(10, y, pw-20, 22)];
    delaySlider.minimumValue = 0;
    delaySlider.maximumValue = 0.05;
    delaySlider.value = 0;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = accent;
    delaySlider.maximumTrackTintColor = color(60, 60, 80, 1);
    [delaySlider addTarget:self action:@selector(delayChange) forControlEvents:UIControlEventValueChanged];
    [controlPanel addSubview:delaySlider];
    y += 26;

    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, y, pw-20, 14)];
    delayLabel.text = @"سرعة 0.00 ث";
    delayLabel.textColor = color(150, 180, 255, 1);
    delayLabel.font = [UIFont systemFontOfSize:10];
    delayLabel.textAlignment = NSTextAlignmentCenter;
    [controlPanel addSubview:delayLabel];
    y += 20;

    // Status
    UILabel *statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, ph-18, pw-44, 12)];
    statusLbl.text = @"⏻  مستعد";
    statusLbl.textColor = color(120, 120, 140, 1);
    statusLbl.font = [UIFont systemFontOfSize:9];
    [controlPanel addSubview:statusLbl];

    // Hide
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(pw-32, 6, 22, 22);
    hideBtn.backgroundColor = color(40, 40, 60, 1);
    hideBtn.layer.cornerRadius = 11;
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [hideBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [controlPanel addSubview:hideBtn];

    [w addSubview:controlPanel];

    // Mini Panel (collapsed)
    miniPanel = [[UIView alloc] initWithFrame:CGRectMake(sw-80-10, 60, 80, 80)];
    miniPanel.backgroundColor = bg;
    miniPanel.layer.cornerRadius = 18;
    miniPanel.layer.borderColor = border.CGColor;
    miniPanel.layer.borderWidth = 1;
    miniPanel.hidden = YES;
    miniPanel.tag = 200;

    UIButton *showBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    showBtn.frame = CGRectMake(10, 10, 60, 60);
    showBtn.backgroundColor = color(30, 30, 50, 1);
    showBtn.layer.cornerRadius = 30;
    showBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [showBtn setTitle:@"▶" forState:UIControlStateNormal];
    [showBtn setTitleColor:accent forState:UIControlStateNormal];
    [showBtn addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
    [miniPanel addSubview:showBtn];

    [w addSubview:miniPanel];

    // Names Strip
    CGFloat nsW = sw-32, nsH = 34, nsX = 16, nsY = py+ph+14;
    namesStrip = [[UIView alloc] initWithFrame:CGRectMake(nsX, nsY, nsW, nsH)];
    namesStrip.backgroundColor = color(18, 18, 30, 0.85);
    namesStrip.layer.cornerRadius = 17;
    namesStrip.layer.borderColor = color(60, 60, 80, 0.6).CGColor;
    namesStrip.layer.borderWidth = 1;
    namesStrip.tag = 400;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, nsW, nsH)];
    scroll.showsHorizontalScrollIndicator = NO;

    CGFloat sx = 10, sh = 24, sy = (nsH-sh)/2;
    for (NSString *n in accountNames) {
        CGFloat sw2 = [n sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]}].width + 18;
        UIView *b = [[UIView alloc] initWithFrame:CGRectMake(sx, sy, sw2, sh)];
        b.backgroundColor = color(30, 60, 120, 0.7);
        b.layer.cornerRadius = 7;
        b.layer.borderColor = color(60, 120, 255, 0.4).CGColor;
        b.layer.borderWidth = 0.5;
        UILabel *l = [[UILabel alloc] initWithFrame:b.bounds];
        l.text = n; l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        l.textAlignment = NSTextAlignmentCenter;
        [b addSubview:l]; [scroll addSubview:b];
        sx += sw2 + 5;
    }
    scroll.contentSize = CGSizeMake(sx, nsH);
    [namesStrip addSubview:scroll];

    UIPanGestureRecognizer *ng = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)];
    [namesStrip addGestureRecognizer:ng];

    [w addSubview:namesStrip];

    // Tap Circle
    CGFloat cs = 50, cx = (sw-cs)/2, cy = nsY+nsH+24;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = color(255, 69, 58, 0.95);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = UIColor.whiteColor.CGColor;
    tapCircle.layer.borderWidth = 2;
    tapCircle.layer.shadowColor = color(255, 69, 58, 0.6).CGColor;
    tapCircle.layer.shadowOpacity = 0.8;
    tapCircle.layer.shadowOffset = CGSizeMake(0, 0);
    tapCircle.layer.shadowRadius = 12;
    tapCircle.userInteractionEnabled = YES;
    tapCircle.tag = 300;

    UILabel *cl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    cl.text = @"515"; cl.textColor = UIColor.whiteColor;
    cl.font = [UIFont boldSystemFontOfSize:18];
    cl.textAlignment = NSTextAlignmentCenter;
    [tapCircle addSubview:cl];

    UIPanGestureRecognizer *cg = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)];
    [tapCircle addGestureRecognizer:cg];

    UILongPressGestureRecognizer *lg = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMaster:)];
    lg.minimumPressDuration = 1.0;
    [tapCircle addGestureRecognizer:lg];

    [w addSubview:tapCircle];

    udpInit();
    NSLog(@"[YLT] UI ready");
}

#pragma mark - Actions

+ (void)toggleRun {
    running = !running;
    if (running) {
        runBtn.backgroundColor = color(255, 69, 58, 1);
        [runBtn setTitle:@"■  إيقاف" forState:UIControlStateNormal];
        [Tapper start];
    } else {
        runBtn.backgroundColor = color(50, 200, 80, 1);
        [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
        [Tapper stop];
    }
}

+ (void)delayChange {
    CGFloat v = round(delaySlider.value * 100) / 100;
    delaySlider.value = v; currentDelay = v;
    delayLabel.text = [NSString stringWithFormat:@"سرعة %.2f ث", v];
    if (running) { [Tapper stop]; [Tapper start]; }
}

+ (void)hidePanel {
    controlPanel.hidden = YES; miniPanel.hidden = NO;
}

+ (void)showPanel {
    miniPanel.hidden = YES; controlPanel.hidden = NO;
}

+ (void)dragItem:(UIPanGestureRecognizer *)g {
    UIView *v = g.view; CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x+t.x, v.center.y+t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

+ (void)dragCircle:(UIPanGestureRecognizer *)g {
    UIView *v = g.view; CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x+t.x, v.center.y+t.y);
    [g setTranslation:CGPointZero inView:v.superview];
    if (g.state == UIGestureRecognizerStateEnded && isMain)
        udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y]);
}

+ (void)setMaster:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isMain = YES;
        tapCircle.layer.borderColor = color(255, 200, 50, 1).CGColor;
        tapCircle.layer.borderWidth = 3;
        [self alert:@"✓ رئيسي" msg:@"النسخة الرئيسية - تتحكم بجميع النسخ"];
        udpSend([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
    }
}

+ (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [appWindow().rootViewController presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Constructor

%ctor {
    NSLog(@"[YLT] Loading...");
    dispatch_async(dispatch_get_main_queue(), ^{ [Controller buildUI]; });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIWindow *w = n.object;
        if (w && !w.hidden && w.rootViewController && !controlPanel) [Controller buildUI];
    }];
}
