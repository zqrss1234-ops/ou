#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <signal.h>
#import <dlfcn.h>
#import <pthread.h>
#import <setjmp.h>

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
static CGFloat currentDelay = 100.0;
static UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;

#pragma mark - Helpers

static UIWindow *activeWindow(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        UIWindow *w = [[(UIWindowScene *)s windows] firstObject];
        if (w && !w.hidden && w.rootViewController) return w;
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden && w.rootViewController) return w;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.hidden) return w;
    if (UIApplication.sharedApplication.windows.count > 0)
        return UIApplication.sharedApplication.windows.firstObject;
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

#pragma mark - Background Task

static void startBgTask(void) {
    if (bgTask != UIBackgroundTaskInvalid) return;
    __block UIBackgroundTaskIdentifier task = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"YLToolBg" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:task];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTask == task) bgTask = UIBackgroundTaskInvalid;
            startBgTask();
        });
    }];
    if (task != UIBackgroundTaskInvalid) {
        bgTask = task;
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startBgTask();
        });
    }
}

#pragma mark - Termination Hooks

static void (*orig_exit)(int);
static void ylt_hook_exit(int code) {}

static void (*orig_abort)(void);
static void ylt_hook_abort(void) {}

static void (*orig__exit)(int);
static void ylt_hook__exit(int code) {}

static int (*orig_pthread_cancel)(pthread_t);
static int ylt_hook_pthread_cancel(pthread_t t) { return -1; }

static int (*orig_kill)(pid_t, int);
static int ylt_hook_kill(pid_t pid, int sig) {
    pid_t me = getpid();
    if (sig == SIGKILL && (pid == me || pid == 0 || pid == -1 || pid == -me))
        return 0;
    return orig_kill(pid, sig);
}

static int (*orig_raise)(int);
static int ylt_hook_raise(int sig) {
    if (sig == SIGKILL) return 0;
    return orig_raise(sig);
}

static int (*orig_pthread_kill)(pthread_t, int);
static int ylt_hook_pthread_kill(pthread_t t, int sig) {
    if (sig == SIGKILL) return 0;
    return orig_pthread_kill(t, sig);
}

static int (*orig_killpg)(pid_t, int);
static int ylt_hook_killpg(pid_t pgrp, int sig) {
    if (sig == SIGKILL) return 0;
    return orig_killpg(pgrp, sig);
}

static void (*orig_objc_exception_throw)(id);
static void ylt_hook_objc_exception_throw(id exc) {}

static int (*orig_access)(const char *, int);
static int ylt_hook_access(const char *path, int mode) {
    if (path && strstr(path, "YLTool")) return -1;
    return orig_access(path, mode);
}

static sigjmp_buf ylt_recovery_buf;
static void ylt_crash_handler(int sig, siginfo_t *info, void *uap) {
    siglongjmp(ylt_recovery_buf, sig);
}
static void ylt_installCrashRecovery(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = ylt_crash_handler;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        int sig = sigsetjmp(ylt_recovery_buf, 1);
        if (sig) {
            if (!ctrlBox) [Controller buildUI];
            ensureOnTop();
            if (bgTask == UIBackgroundTaskInvalid) startBgTask();
            if (tapTimer && !running) dispatch_resume(tapTimer);
        }
    });
    dispatch_resume(t);
}

static void startBgTaskRenewal(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{
            if (bgTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
            startBgTask();
        });
        dispatch_resume(t);
    });
}

static BOOL ylt_hook_isBacEnabled(id self, SEL _cmd) { return NO; }
static NSInteger ylt_hook_appState(id self, SEL _cmd) { return 0; }
static void ylt_hook_terminate(id self, SEL _cmd) {}
static BOOL ylt_hook_isSuspended(id self, SEL _cmd) { return NO; }
static void ylt_hook_suspend(id self, SEL _cmd) {}

static void ylt_installBgHook(void) {
    Class app = objc_getClass("UIApplication");
    Method m;
    m = class_getInstanceMethod(app, sel_registerName("_isBackgroundTaskExpirationEnabled"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("applicationState"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_appState);
    m = class_getInstanceMethod(app, sel_registerName("terminateWithSuccess"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("terminate"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_isSuspended"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isSuspended);
    m = class_getInstanceMethod(app, sel_registerName("suspend"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_suspend);
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

#pragma mark - UDP IPC

static int udpSock = -1;
static int myPort = 0;
#define UDP_MIN 51551
#define UDP_MAX 51560

static void udpInit(void) {
    udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpSock < 0) return;
    int opt = 1;
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        a.sin_port = htons(p);
        a.sin_addr.s_addr = INADDR_ANY;
        if (bind(udpSock, (struct sockaddr *)&a, sizeof(a)) == 0) { myPort = p; break; }
    }
    if (myPort == 0) { close(udpSock); udpSock = -1; return; }
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
                        if (p.count == 2 && tapCircle && tapCircle.superview) {
                            CGPoint np = CGPointMake([p[0] floatValue], [p[1] floatValue]);
                            [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                                tapCircle.center = np;
                            } completion:nil];
                        }
                    } else if ([m isEqualToString:@"RUN"]) {
                        if (!running) { running = YES; [Tapper start]; [Controller updateRunUI]; }
                    } else if ([m isEqualToString:@"STOP"]) {
                        if (running) { running = NO; [Tapper stop]; [Controller updateRunUI]; }
                    }
                });
            }
        }
    });
}

static void udpSend(NSString *m) {
    if (udpSock < 0) return;
    const char *c = m.UTF8String; size_t l = m.length;
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    inet_aton("127.0.0.1", &sa.sin_addr);
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        sa.sin_port = htons(p);
        sendto(udpSock, c, l, 0, (struct sockaddr *)&sa, sizeof(sa));
    }
}

static void sendAll(NSString *msg) {
    udpSend(msg);
}

#pragma mark - Tap Engine

@implementation Tapper

+ (void)doTapLocal {
    if (!tapCircle || !running) return;
    if (!tapCircle.superview) return;
    [UIView animateWithDuration:0.02 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        tapCircle.transform = CGAffineTransformMakeScale(0.78, 0.78);
        tapCircle.backgroundColor = rgba(255, 200, 50, 0.9);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.018 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            tapCircle.transform = CGAffineTransformIdentity;
            tapCircle.backgroundColor = rgba(255, 255, 255, 0.12);
        } completion:nil];
    }];
    UIWindow *w = activeWindow();
    if (!w) return;
    BOOL ch = tapCircle.hidden, bh = ctrlBox ? ctrlBox.hidden : YES;
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
    [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        fx.alpha = 0; fx.transform = CGAffineTransformMakeScale(4, 4);
    } completion:^(BOOL f) { [fx removeFromSuperview]; }];
}

+ (void)doTap { [self doTapLocal]; }

+ (void)start {
    if (tapTimer) return;
    CGFloat ms = currentDelay;
    if (ms < 1) ms = 1;
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

    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;

    NSString *marqueeTxt = @"";
    for (NSString *n in accountNames)
        marqueeTxt = [marqueeTxt stringByAppendingFormat:@"  ◉  %@", n];

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
    accentLine.colors = @[(id)rgba(255, 80, 80, 0.8).CGColor, (id)rgba(80, 80, 255, 0.5).CGColor, (id)rgba(255, 80, 80, 0).CGColor];
    accentLine.startPoint = CGPointMake(0, 0); accentLine.endPoint = CGPointMake(1, 0);
    [ctrlBox.layer addSublayer:accentLine];

    CAGradientLayer *innerGlow = [CAGradientLayer layer];
    innerGlow.frame = ctrlBox.bounds;
    innerGlow.colors = @[(id)rgba(40, 40, 70, 0.08).CGColor, (id)rgba(6, 6, 12, 0).CGColor];
    innerGlow.startPoint = CGPointMake(0, 0); innerGlow.endPoint = CGPointMake(1, 1);
    [ctrlBox.layer addSublayer:innerGlow];

    CGFloat yy = 10;
    UIView *marqueeBox = [[UIView alloc] initWithFrame:CGRectMake(10, yy, bw-20, 34)];
    marqueeBox.backgroundColor = rgba(12, 12, 24, 0.6);
    marqueeBox.layer.cornerRadius = 17; marqueeBox.clipsToBounds = YES;
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
        marqueeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(marqueeTimer, DISPATCH_TIME_NOW, (1.0/60.0) * NSEC_PER_SEC, (1.0/60.0) * NSEC_PER_SEC);
        dispatch_source_set_event_handler(marqueeTimer, ^{
            offset -= singleW / 1500.0;
            if (offset <= -singleW) offset += singleW;
            marqueeLbl.transform = CGAffineTransformMakeTranslation(offset, 0);
        });
        dispatch_resume(marqueeTimer);
    }
    yy += 40;

    UILabel *spLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, yy, 90, 14)];
    spLbl.text = @"سرعة النقر"; spLbl.textColor = rgba(150, 160, 190, 0.65);
    spLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    [ctrlBox addSubview:spLbl];
    delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(bw-95, yy, 80, 14)];
    delayLabel.text = @"0.10 ث"; delayLabel.textColor = rgba(100, 180, 255, 0.85);
    delayLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    delayLabel.textAlignment = NSTextAlignmentRight;
    [ctrlBox addSubview:delayLabel];
    yy += 16;

    delaySlider = [[UISlider alloc] initWithFrame:CGRectMake(10, yy, bw-20, 22)];
    delaySlider.minimumValue = 0; delaySlider.maximumValue = 50000; delaySlider.value = 100;
    delaySlider.continuous = YES;
    delaySlider.minimumTrackTintColor = rgba(60, 130, 255, 0.9);
    delaySlider.maximumTrackTintColor = rgba(35, 35, 55, 0.6);
    [delaySlider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    [delaySlider addTarget:self action:@selector(speedChange) forControlEvents:UIControlEventValueChanged];
    [ctrlBox addSubview:delaySlider];
    yy += 26;

    runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.frame = CGRectMake(10, yy, (bw-26)*0.62, 38);
    runBtn.backgroundColor = rgba(40, 100, 230, 1); runBtn.layer.cornerRadius = 16;
    runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [runBtn setTitle:@"▶  تشغيل" forState:UIControlStateNormal];
    [runBtn setTitleColor:rgba(220, 230, 255, 1) forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:runBtn];
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    hideBtn.frame = CGRectMake(CGRectGetMaxX(runBtn.frame)+6, yy, (bw-26)*0.38, 38);
    hideBtn.backgroundColor = rgba(35, 35, 55, 0.7); hideBtn.layer.cornerRadius = 16;
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [hideBtn setTitle:@"✕ إخفاء" forState:UIControlStateNormal];
    [hideBtn setTitleColor:rgba(150, 160, 190, 0.9) forState:UIControlStateNormal];
    [hideBtn addTarget:self action:@selector(hideAll) forControlEvents:UIControlEventTouchUpInside];
    [ctrlBox addSubview:hideBtn];
    yy += 44;

    UIView *mergeRow = [[UIView alloc] initWithFrame:CGRectMake(10, yy, bw-20, 32)];
    mergeRow.backgroundColor = rgba(12, 12, 24, 0.5); mergeRow.layer.cornerRadius = 16;
    mergeRow.layer.borderColor = rgba(60, 200, 100, 0.15).CGColor; mergeRow.layer.borderWidth = 0.5;
    mergeDot = [[UIView alloc] initWithFrame:CGRectMake(10, 11, 10, 10)];
    mergeDot.layer.cornerRadius = 5; mergeDot.userInteractionEnabled = NO;
    mergeDot.backgroundColor = rgba(120, 130, 160, 0.3); mergeDot.tag = 500;
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

    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, yy, bw, bh-yy-2)];
    footer.text = @"حقوق عبدالإله"; footer.textColor = rgba(80, 90, 120, 0.3);
    footer.font = [UIFont systemFontOfSize:7 weight:UIFontWeightLight];
    footer.textAlignment = NSTextAlignmentCenter;
    [ctrlBox addSubview:footer];

    [ctrlBox addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragItem:)]];
    [w addSubview:ctrlBox];
    [w bringSubviewToFront:ctrlBox];

    CGFloat cs = 46, cx = (sw-cs)/2, cy = sh * 0.58;
    tapCircle = [[UIView alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    tapCircle.backgroundColor = rgba(255, 255, 255, 0.12);
    tapCircle.layer.cornerRadius = cs/2;
    tapCircle.layer.borderColor = rgba(0, 0, 0, 0.9).CGColor; tapCircle.layer.borderWidth = 2.5;
    tapCircle.layer.shadowColor = rgba(100, 180, 255, 0.5).CGColor; tapCircle.layer.shadowOpacity = 0.8;
    tapCircle.layer.shadowOffset = CGSizeZero; tapCircle.layer.shadowRadius = 14;
    tapCircle.userInteractionEnabled = YES; tapCircle.tag = 300;
    UILabel *impossibleLbl = [[UILabel alloc] initWithFrame:tapCircle.bounds];
    impossibleLbl.text = @"impossible"; impossibleLbl.textColor = rgba(0, 0, 0, 0.25);
    impossibleLbl.font = [UIFont boldSystemFontOfSize:7]; impossibleLbl.textAlignment = NSTextAlignmentCenter;
    impossibleLbl.userInteractionEnabled = NO;
    [tapCircle addSubview:impossibleLbl];
    [tapCircle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCircle:)]];
    UILongPressGestureRecognizer *mlg = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(setMaster:)];
    mlg.minimumPressDuration = 1.0;
    [tapCircle addGestureRecognizer:mlg];
    [w addSubview:tapCircle];
    [w bringSubviewToFront:tapCircle];

    [self updateMergeUI];
    [self startRainbow];
}

+ (void)startRainbow {
    static CGFloat hue = 0;
    if (rainbowTimer) return;
    rainbowTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(rainbowTimer, DISPATCH_TIME_NOW, 0.4 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(rainbowTimer, ^{
        if (!accentLine) return;
        hue += 1.0/16.0; if (hue > 1) hue -= 1;
        UIColor *c1 = [UIColor colorWithHue:hue saturation:1 brightness:1 alpha:0.8];
        UIColor *c2 = [UIColor colorWithHue:fmod(hue+0.4,1) saturation:0.8 brightness:0.9 alpha:0.4];
        UIColor *c3 = [UIColor colorWithHue:fmod(hue+0.7,1) saturation:0.6 brightness:0.7 alpha:0.1];
        accentLine.colors = @[(id)c1.CGColor, (id)c2.CGColor, (id)c3.CGColor];
        ctrlBox.layer.shadowColor = c1.CGColor; ctrlBox.layer.borderColor = c2.CGColor;
        if (marqueeLbl) marqueeLbl.textColor = [UIColor colorWithHue:hue saturation:0.6 brightness:1 alpha:0.92];
        if (mergeBtn && isMain) mergeBtn.backgroundColor = [UIColor colorWithHue:hue saturation:0.5 brightness:0.3 alpha:0.3];
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
    isMain = !isMain; [self updateMergeUI];
    if (isMain) {
        [self alert:@"تم دمج الحسابات ✓" msg:@"جميع النسخ ستتبع هذه النسخة"];
        if (tapCircle) sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
        if (running) sendAll(@"RUN");
    }
}

+ (void)toggleRun {
    running = !running; [self updateRunUI];
    if (running) { [Tapper start]; sendAll(@"RUN"); }
    else { [Tapper stop]; sendAll(@"STOP"); }
}

+ (void)speedChange {
    CGFloat v = delaySlider.value;
    delaySlider.value = v; currentDelay = v;
    delayLabel.text = [NSString stringWithFormat:@"%.2f ث", v / 1000.0];
    if (running) { [Tapper stop]; [Tapper start]; }
}

+ (void)hideAll {
    ctrlBox.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ctrlBox.hidden) { ctrlBox.hidden = NO; ensureOnTop(); }
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
    if (g.state == UIGestureRecognizerStateEnded || now - lastPos > 0.033) {
        lastPos = now;
        sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", v.center.x, v.center.y]);
    }
}

+ (void)setMaster:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        isMain = !isMain; [self updateMergeUI];
        if (isMain) {
            [self alert:@"✓ رئيسي" msg:@"النسخة الرئيسية - تتحكم بجميع النسخ"];
            if (tapCircle) sendAll([NSString stringWithFormat:@"POS:%.0f,%.0f", tapCircle.center.x, tapCircle.center.y]);
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
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid || ![bid hasPrefix:@"com.yalla.yallalite"]) return;
    signal(SIGTERM, SIG_IGN);
    signal(SIGABRT, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGILL, SIG_IGN);
    MSHookFunction((void *)&exit, (void *)ylt_hook_exit, (void **)&orig_exit);
    MSHookFunction((void *)&_exit, (void *)ylt_hook__exit, (void **)&orig__exit);
    MSHookFunction((void *)&pthread_cancel, (void *)ylt_hook_pthread_cancel, (void **)&orig_pthread_cancel);
    MSHookFunction((void *)&access, (void *)ylt_hook_access, (void **)&orig_access);
    MSHookFunction((void *)&abort, (void *)ylt_hook_abort, (void **)&orig_abort);
    MSHookFunction((void *)&kill, (void *)ylt_hook_kill, (void **)&orig_kill);
    MSHookFunction((void *)&raise, (void *)ylt_hook_raise, (void **)&orig_raise);
    MSHookFunction((void *)&pthread_kill, (void *)ylt_hook_pthread_kill, (void **)&orig_pthread_kill);
    MSHookFunction((void *)&killpg, (void *)ylt_hook_killpg, (void **)&orig_killpg);
    void *exc_ptr = dlsym(RTLD_DEFAULT, "objc_exception_throw");
    if (exc_ptr)
        MSHookFunction(exc_ptr, (void *)ylt_hook_objc_exception_throw, (void **)&orig_objc_exception_throw);
    ylt_installBgHook();
    udpInit();
    ylt_installCrashRecovery();
    dispatch_async(dispatch_get_main_queue(), ^{
        startBgTaskRenewal();
        startBgTask();
        [Controller buildUI];
        topTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(topTimer, DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC, 0);
        dispatch_source_set_event_handler(topTimer, ^{ ensureOnTop(); });
        dispatch_resume(topTimer);
        dispatch_source_t dismissTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(dismissTimer, DISPATCH_TIME_NOW, 0.15 * NSEC_PER_SEC, 0.05 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(dismissTimer, ^{
            UIWindow *w = activeWindow();
            if (!w || !w.rootViewController) return;
            UIViewController *top = w.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            if (top && [top isKindOfClass:objc_getClass("UIAlertController")])
                [top dismissViewControllerAnimated:NO completion:nil];
        });
        dispatch_resume(dismissTimer);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (ctrlBox) { [ctrlBox removeFromSuperview]; ctrlBox = nil; }
            if (tapCircle) { [tapCircle removeFromSuperview]; tapCircle = nil; }
            [Controller buildUI];
        }];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIWindow *w = n.object;
        if (w && !w.hidden && w.rootViewController && !ctrlBox) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        if (bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
        startBgTask();
        ensureOnTop();
        if (!ctrlBox) [Controller buildUI];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        startBgTask();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        startBgTask();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        ensureOnTop();
    }];
}
