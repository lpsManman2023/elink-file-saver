//
//  ELKMenuHook.m
//  ELKFileSaver - v22 隐藏菜单版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);
static NSMutableSet *g_markedViews = nil;

// ── 预置水印类名（首次自动创建规则文件） ──
static NSArray *presetWatermarkClasses(void) {
    return @[@"WWKWatermarkView", @"WWKWatermarkImageView",
             @"WWKWatermarkHelper", @"WWKWaterMark"];
}

static NSString *rulesPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/meow_watermark_rules.json"];
}

static NSArray *loadWatermarkClasses(void) {
    NSData *d = [NSData dataWithContentsOfFile:rulesPath()];
    if (d) {
        @try {
            NSDictionary *r = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            NSArray *names = r[@"watermark_classes"];
            if (names.count > 0) return names;
        } @catch (...) {}
    }
    // 首次 → 自动写入预置规则
    NSData *jd = [NSJSONSerialization dataWithJSONObject:@{@"watermark_classes":presetWatermarkClasses(), @"version":@1}
                                                 options:NSJSONWritingPrettyPrinted error:nil];
    [jd writeToFile:rulesPath() atomically:YES];
    return presetWatermarkClasses();
}

// ── 按类名精准隐藏 ──
static void hideByClassName(UIView *root, NSArray *names, NSMutableSet *marked) {
    if ([names containsObject:NSStringFromClass([root class])]) {
        root.hidden = YES;
        [marked addObject:[NSValue valueWithNonretainedObject:root]];
    }
    for (UIView *sub in root.subviews) hideByClassName(sub, names, marked);
}

// ── Hook pushVC ──
static void hook_pushVC(id self, SEL _cmd, UIViewController *vc, BOOL animated) {
    orig_pushVC(self, _cmd, vc, animated);
    @try {
        NSString *cn = NSStringFromClass([vc class]);
        if (![cn hasPrefix:@"WWK"]) return;

        // 加水印隐藏
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [ELKMenuHook hideWatermarksIfEnabled];
            });
        }

        // 加隐藏菜单手势（长按导航栏标题区域 1.5 秒）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook installNavGesture:vc];
        });
    } @catch (...) {}
}

// ── 手势 handler ──
@interface ELKNavGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end
@implementation ELKNavGestureHandler
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIView *navBar = gr.view;
    CGPoint p = [gr locationInView:navBar];

    // 只在标题区域（中间 1/3）响应
    CGFloat left = navBar.bounds.size.width * 0.33;
    CGFloat right = navBar.bounds.size.width * 0.67;
    if (p.x < left || p.x > right) return;

    NSLog(@"[喵喵] 🔔 隐藏菜单触发");

    BOOL wmOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"🐱 喵喵工具箱"
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📁 文件浏览器"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [ELKFileExporter preloadFileList];
            [ELKFileExporter presentFileBrowser];
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:wmOn ? @"🔓 显示水印" : @"🔒 隐藏水印"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            BOOL newVal = !wmOn;
            [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"meow_watermark_hidden"];
            if (newVal) [ELKMenuHook hideWatermarksIfEnabled];
            else [ELKMenuHook showAllWatermarks];
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🕵️ 标记水印视图"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIViewController *top = nil;
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    UIViewController *r = w.rootViewController;
                    while (r.presentedViewController) r = r.presentedViewController;
                    if (r) { top = r; break; }
                }
                NSArray *candidates = [ELKMenuHook scanCandidateWatermarkViews];
                // WatermarkCandidateVC is in ELKFileExporter.m - use presentSettings+special flow
                [ELKFileExporter presentWatermarkMarker:top candidates:candidates];
            });
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = navBar;
        sheet.popoverPresentationController.sourceRect = (CGRect){{navBar.bounds.size.width/2, navBar.bounds.size.height}, {0,0}};
    }
    UIViewController *top = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if (r) { top = r; break; }
    }
    if (top) [top presentViewController:sheet animated:YES completion:nil];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

static ELKNavGestureHandler *g_gestureHandler = nil;

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v22");
        g_markedViews = [NSMutableSet set];
        g_gestureHandler = [[ELKNavGestureHandler alloc] init];

        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
                [self hideWatermarksIfEnabled];
            }
        });
    } @catch (NSException *e) {}
}

// ── 给导航栏加长按手势 ──
+ (void)installNavGesture:(UIViewController *)vc {
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (!bar) return;

    // 去重
    for (UIGestureRecognizer *gr in bar.gestureRecognizers) {
        if ([gr.delegate isKindOfClass:[ELKNavGestureHandler class]]) return;
    }

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:g_gestureHandler action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 1.5;
    lp.cancelsTouchesInView = NO;
    lp.delegate = g_gestureHandler;
    [bar addGestureRecognizer:lp];
    NSLog(@"[喵喵] ✅ 隐藏菜单已就绪 (长按标题1.5秒)");
}

// ── 水印控制 ──
+ (void)hideWatermarksIfEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) return;
    NSArray *names = loadWatermarkClasses();
    [g_markedViews removeAllObjects];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        hideByClassName(w, names, g_markedViews);
    }
    NSLog(@"[喵喵] 🔒 %lu 个水印", (unsigned long)g_markedViews.count);
}

+ (void)hideWatermarksByClassName:(NSString *)className {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        hideByClassName(w, @[className], g_markedViews);
    }
}

+ (void)showAllWatermarks {
    for (NSValue *val in g_markedViews) {
        UIView *v = [val nonretainedObjectValue];
        if (v) v.hidden = NO;
    }
    [g_markedViews removeAllObjects];
}

// ── 扫描候选 ──
+ (NSArray *)scanCandidateWatermarkViews {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [self collectFrom:w win:w out:out seen:seen];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"coverRatio"] compare:a[@"coverRatio"]];
    }];
    return out;
}

+ (void)collectFrom:(UIView *)v win:(UIWindow *)win out:(NSMutableArray *)out seen:(NSMutableSet *)seen {
    for (UIView *sub in v.subviews) {
        NSString *cn = NSStringFromClass([sub class]);
        if ([seen containsObject:cn]) continue;
        CGFloat cw = sub.frame.size.width  / (win.bounds.size.width  ?: 1);
        CGFloat ch = sub.frame.size.height / (win.bounds.size.height ?: 1);
        if (cw >= 0.6 && ch >= 0.5 && sub.alpha < 0.999 && !sub.userInteractionEnabled) {
            [seen addObject:cn];
            [out addObject:@{@"className":cn, @"frameW":@(sub.frame.size.width),
                             @"frameH":@(sub.frame.size.height), @"alpha":@(sub.alpha),
                             @"coverRatio":@(cw)}];
        }
        [self collectFrom:sub win:win out:out seen:seen];
    }
}

// ── 规则文件操作 ──
+ (NSArray *)savedWatermarkClasses { return loadWatermarkClasses(); }

+ (void)addWatermarkClass:(NSString *)className {
    NSMutableArray *a = [loadWatermarkClasses() mutableCopy];
    if ([a containsObject:className]) return;
    [a addObject:className];
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"watermark_classes":a, @"version":@1}
                                                options:NSJSONWritingPrettyPrinted error:nil];
    [d writeToFile:rulesPath() atomically:YES];
}

+ (void)removeWatermarkClass:(NSString *)className {
    NSMutableArray *a = [loadWatermarkClasses() mutableCopy];
    [a removeObject:className];
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"watermark_classes":a, @"version":@1}
                                                options:NSJSONWritingPrettyPrinted error:nil];
    [d writeToFile:rulesPath() atomically:YES];
}

@end
