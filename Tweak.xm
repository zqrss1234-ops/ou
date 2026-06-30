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
    // This method triggers follow between all accounts.
    // Each account follows every other account in the list.
    // Hook into YallaLite's follow API methods below.
    for (NSInteger i = 0; i < accountNames.count; i++) {
        for (NSInteger j = 0; j < accountNames.count; j++) {
            if (i == j) continue;
            // Perform follow action with delay
            [NSThread sleepForTimeInterval:delay];
            // TODO: Replace with actual YallaLite hook call
            // e.g., [[YLLFollowManager shared] followUser:accountNames[j]];
            NSLog(@"[YLTool] Following %@ -> %@", accountNames[i], accountNames[j]);
        }
    }
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

    // Add to window
    [tweakWindow addSubview:mainContainer];
    [tweakWindow addSubview:minimizedContainer];
    tweakWindow.hidden = NO;
}

#pragma mark - Toggle Run/Stop

+ (void)toggleRunStop {
    isRunning = !isRunning;
    if (isRunning) {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
        [toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
    } else {
        toggleBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1.0];
        [toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
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

    UIViewController *rootVC = tweakWindow.rootViewController;
    if (!rootVC) {
        rootVC = [[UIViewController alloc] init];
        tweakWindow.rootViewController = rootVC;
        [tweakWindow makeKeyAndVisible];
    }
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
