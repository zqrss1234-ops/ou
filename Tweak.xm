#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#pragma mark - Names

static NSArray<NSString *> *names = @[
    @"Abdulilah", @"Lahhou", @"Charo", @"Said",
    @"AbuMeteab", @"Nasser", @"Alkaed",
    @"Alhbas", @"Alshamara"
];

#pragma mark - State

static UIView *panel = nil;
static UIView *minimizedPanel = nil;
static UIView *namesBar = nil;
static UIView *circleView = nil;
static UIButton *toggleBtn = nil;
static UISlider *speedSlider = nil;
static UILabel *speedValLabel = nil;
static dispatch_source_t tapTimer = NULL;
static BOOL isRunning = NO;
static CGFloat tapDelay = 0.0;
static int udpFD = -1;
static BOOL isFirstInstance = NO;

#pragma mark - Window Helper

static UIWindow *activeWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                UIWindow *w = [(UIWindowScene *)s windows].firstObject;
                if (w && !w.hidden) return w;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (w && !w.hidden) return w;
#pragma clang diagnostic pop
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.hidden && w.rootViewController) return w;
    }
    return nil;
}

#pragma mark - UDP Sync

static void udpInit(void) {
    udpFD = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpFD < 0) return;
    int opt = 1;
    setsockopt(udpFD, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(udpFD, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(51551);
    addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(udpFD, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(udpFD); udpFD = -1; return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buf[256];
        while (1) {
            struct sockaddr_in from;
            socklen_t flen = sizeof(from);
            ssize_t n = recvfrom(udpFD, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&from, &flen);
            if (n > 0) {
                buf[n] = '\0';
                NSString *msg = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([msg hasPrefix:@"POS:"]) {
                        NSString *coords = [msg substringFromIndex:4];
                        NSArray *parts = [coords componentsSeparatedByString:@","];
                        if (parts.count == 2) {
                            CGFloat x = [parts[0] floatValue];
                            CGFloat y = [parts[1] floatValue];
                            if (!isFirstInstance && circleView && circleView.superview) {
                                circleView.center = CGPointMake(x, y);
                            }
                        }
                    } else if ([msg hasPrefix:@"TAP"]) {
                        if (!isFirstInstance && circleView) {
                            [YLTapSync performLocalTap];
                        }
                    }
                });
            }
        }
    });

    // Broadcast our presence
    const char *hello = "YLT:HELLO";
    struct sockaddr_in bc;
    memset(&bc, 0, sizeof(bc));
    bc.sin_family = AF_INET;
    bc.sin_port = htons(51551);
    inet_aton("255.255.255.255", &bc.sin_addr);
    sendto(udpFD, hello, strlen(hello), 0, (struct sockaddr *)&bc, sizeof(bc));
}

static void udpSend(NSString *msg) {
    if (udpFD < 0) return;
    const char *cmsg = [msg UTF8String];
    struct sockaddr_in bc;
    memset(&bc, 0, sizeof(bc));
    bc.sin_family = AF_INET;
    bc.sin_port = htons(51551);
    inet_aton("255.255.255.255", &bc.sin_addr);
    sendto(udpFD, cmsg, strlen(cmsg), 0, (struct sockaddr *)&bc, sizeof(bc));
}

#pragma mark - Tap Actions

@interface YLTapSync : NSObject
+ (void)performLocalTap;
+ (void)startTapping;
+ (void)stopTapping;
@end

@implementation YLTapSync

+ (void)performLocalTap {
    if (!circleView || !isRunning) return;

    [UIView animateWithDuration:0.03 animations:^{
        circleView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        circleView.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.2 alpha:0.95];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.03 animations:^{
            circleView.transform = CGAffineTransformIdentity;
            circleView.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.1 alpha:0.95];
        }];
    }];

    UIWindow *w = activeWindow();
    if (!w) return;

    CGPoint pt = [circleView convertPoint:CGPointMake(30, 30) toView:w];
    UIView *target = [w hitTest:pt withEvent:nil];
    if (!target) return;
    if (target == circleView || [target isDescendantOfView:panel] || [target isDescendantOfView:namesBar]) return;

    if ([target isKindOfClass:[UIControl class]]) {
        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    UIView *flash = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    flash.center = pt;
    flash.backgroundColor = [UIColor whiteColor];
    flash.layer.cornerRadius = 8;
    flash.alpha = 0.8;
    flash.userInteractionEnabled = NO;
    [w addSubview:flash];
    [UIView animateWithDuration:0.25 animations:^{
        flash.alpha = 0; flash.transform = CGAffineTransformMakeScale(2.5, 2.5);
    } completion:^(BOOL f) { [flash removeFromSuperview]; }];

    udpSend(@"TAP");
}

+ (void)startTapping {
    if (tapTimer) return;
    CGFloat interval = tapDelay;
    if (interval < 0.005) interval = 0.005;
    tapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(tapTimer, DISPATCH_TIME_NOW, interval * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(tapTimer, ^{ [self performLocalTap]; });
    dispatch_resume(tapTimer);
}

+ (void)stopTapping {
    if (tapTimer) { dispatch_source_cancel(tapTimer); tapTimer = NULL; }
}

@end

#pragma mark - UI Setup

@interface YLTUI : NSObject
+ (void)setup;
@end

@implementation YLTUI

+ (void)setup {
    UIWindow *kw = activeWindow();
    if (!kw) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setup];
        });
        return;
    }

    NSLog(@"[YLT] Setting up UI on %@", kw);
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;

    // ---- Control Panel (small) ----
    CGFloat pw = 220, ph = 160, px = 20, py = 40;
    panel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    panel.layer.cornerRadius = 16;
    panel.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.6].CGColor;
    panel.layer.borderWidth = 1.5;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.5;
    panel.layer.shadowOffset = CGSizeMake(0, 4);
    panel.layer.shadowRadius = 12;
    panel.clipsToBounds = NO;
    panel.tag = 100;

    CGFloat yy = 10;

    // Toggle
    toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(12, yy, pw - 24, 36);
    toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.7 blue:0.25 alpha:1];
    toggleBtn.layer.cornerRadius = 10;
    toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [toggleBtn setTitle:@"▶ تشغيل" forState:UIControlStateNormal];
    [toggleBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [toggleBtn addTarget:self action:@selector(tapToggle) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:toggleBtn];
    yy += 42;

    // Slider
    speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(12, yy, pw - 24, 24)];
    speedSlider.minimumValue = 0.0;
    speedSlider.maximumValue = 0.05;
    speedSlider.value = 0.0;
    speedSlider.continuous = YES;
    speedSlider.minimumTrackTintColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1];
    speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [speedSlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:speedSlider];
    yy += 26;

    speedValLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, yy, pw - 24, 14)];
    speedValLabel.text = @"0.00 ثانية";
    speedValLabel.textColor = [UIColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1];
    speedValLabel.font = [UIFont systemFontOfSize:10];
    speedValLabel.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:speedValLabel];
    yy += 20;

    // Hide button
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(pw - 34, 6, 24, 24);
    hideBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    hideBtn.layer.cornerRadius = 12;
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [hideBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(tapHide) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideBtn];

    [kw addSubview:panel];

    // ---- Names Strip (movable, horizontal) ----
    CGFloat nbW = sw - 40, nbH = 36, nbX = 20, nbY = py + ph + 12;
    namesBar = [[UIView alloc] initWithFrame:CGRectMake(nbX, nbY, nbW, nbH)];
    namesBar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    namesBar.layer.cornerRadius = 18;
    namesBar.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.5].CGColor;
    namesBar.layer.borderWidth = 1;
    namesBar.clipsToBounds = YES;
    namesBar.tag = 400;

    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, nbW, nbH)];
    sc.showsHorizontalScrollIndicator = NO;
    sc.tag = 500;

    CGFloat sx = 12;
    CGFloat sh = 26;
    CGFloat sy = (nbH - sh) / 2;
    for (NSString *name in names) {
        CGSize ts = [name sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]}];
        CGFloat sw2 = ts.width + 20;
        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(sx, sy, sw2, sh)];
        badge.backgroundColor = [UIColor colorWithRed:0.12 green:0.35 blue:0.65 alpha:0.8];
        badge.layer.cornerRadius = 8;
        badge.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.4].CGColor;
        badge.layer.borderWidth = 1;

        UILabel *lb = [[UILabel alloc] initWithFrame:badge.bounds];
        lb.text = name;
        lb.textColor = UIColor.whiteColor;
        lb.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        lb.textAlignment = NSTextAlignmentCenter;
        [badge addSubview:lb];
        [sc addSubview:badge];
        sx += sw2 + 6;
    }
    sc.contentSize = CGSizeMake(sx, nbH);
    [namesBar addSubview:sc];

    // Drag gesture for names bar
    UIPanGestureRecognizer *np = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragView:)];
    [namesBar addGestureRecognizer:np];

    [kw addSubview:namesBar];

    // ---- Tapping Circle ----
    CGFloat cs = 56, cx2 = (sw - cs) / 2, cy2 = nbY + nbH + 30;
    circleView = [[UIView alloc] initWithFrame:CGRectMake(cx2, cy2, cs, cs)];
    circleView.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.1 alpha:0.95];
    circleView.layer.cornerRadius = cs / 2;
    circleView.layer.borderColor = UIColor.whiteColor.CGColor;
    circleView.layer.borderWidth = 2.5;
    circleView.layer.shadowColor = UIColor.redColor.CGColor;
    circleView.layer.shadowOpacity = 0.6;
    circleView.layer.shadowOffset = CGSizeMake(0, 0);
    circleView.layer.shadowRadius = 10;
    circleView.userInteractionEnabled = YES;
    circleView.tag = 300;

    UILabel *cl = [[UILabel alloc] initWithFrame:circleView.bounds];
    cl.text = @"515";
    cl.textColor = UIColor.whiteColor;
    cl.font = [UIFont boldSystemFontOfSize:16];
    cl.textAlignment = NSTextAlignmentCenter;
    [circleView addSubview:cl];

    UIPanGestureRecognizer *cp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)];
    [circleView addGestureRecognizer:cp];

    // Long press to set as main
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMain:)];
    lp.minimumPressDuration = 1.0;
    [circleView addGestureRecognizer:lp];

    [kw addSubview:circleView];

    // ---- Minimized Panel ----
    CGFloat mw = 70, mh = 70;
    minimizedPanel = [[UIView alloc] initWithFrame:CGRectMake(sw - mw - 10, 60, mw, mh)];
    minimizedPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    minimizedPanel.layer.cornerRadius = 16;
    minimizedPanel.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.6].CGColor;
    minimizedPanel.layer.borderWidth = 1.5;
    minimizedPanel.hidden = YES;
    minimizedPanel.tag = 200;

    UIButton *ab = [UIButton buttonWithType:UIButtonTypeSystem];
    ab.frame = CGRectMake(10, 10, 50, 50);
    ab.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    ab.layer.cornerRadius = 25;
    ab.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [ab setTitle:@"▶" forState:UIControlStateNormal];
    [ab setTitleColor:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1] forState:UIControlStateNormal];
    [ab addTarget:self action:@selector(tapShow) forControlEvents:UIControlEventTouchUpInside];
    [minimizedPanel addSubview:ab];

    [kw addSubview:minimizedPanel];

    // Init UDP
    udpInit();

    NSLog(@"[YLT] UI setup complete");
}

#pragma mark - Actions

+ (void)tapToggle {
    isRunning = !isRunning;
    if (isRunning) {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.15 blue:0.15 alpha:1];
        [toggleBtn setTitle:@"■ إيقاف" forState:UIControlStateNormal];
        [YLTapSync startTapping];
    } else {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.7 blue:0.25 alpha:1];
        [toggleBtn setTitle:@"▶ تشغيل" forState:UIControlStateNormal];
        [YLTapSync stopTapping];
    }
}

+ (void)speedChange {
    CGFloat v = round(speedSlider.value * 100) / 100;
    speedSlider.value = v;
    tapDelay = v;
    speedValLabel.text = [NSString stringWithFormat:@"%.2f ثانية", v];
    if (isRunning) { [YLTapSync stopTapping]; [YLTapSync startTapping]; }
}

+ (void)tapHide {
    panel.hidden = YES;
    minimizedPanel.hidden = NO;
}

+ (void)tapShow {
    minimizedPanel.hidden = YES;
    panel.hidden = NO;
}

+ (void)dragView:(UIPanGestureRecognizer *)g {
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

    if (g.state == UIGestureRecognizerStateEnded) {
        // Broadcast position to all connected instances
        NSString *pos = [NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y];
        udpSend(pos);
    }
}

+ (void)setMain:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isFirstInstance = YES;
        circleView.layer.borderColor = [UIColor yellowColor].CGColor;
        circleView.layer.borderWidth = 3;
        [YLTUI showAlert:@"✓ رئيسي" msg:@"هذه النسخة هي الرئيسية"];
    }
}

#pragma mark - Alert

+ (void)showAlert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rvc = activeWindow().rootViewController;
    if (rvc) [rvc presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - Constructor

__attribute__((constructor)) static void init(void) {
    NSLog(@"[YLT] Constructor called");
    dispatch_async(dispatch_get_main_queue(), ^{
        [YLTUI setup];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIWindow *w = n.object;
        if (w && !w.hidden && w.rootViewController && !panel) {
            NSLog(@"[YLT] Window visible, setting up");
            [YLTUI setup];
        }
    }];
}
