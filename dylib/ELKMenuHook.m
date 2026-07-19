//
//  ELKMenuHook.m
//  ELKFileSaver - v21 浮动按钮版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);
static NSMutableSet *g_markedViews = nil;
static UIButton *g_floatBtn = nil;

// ── 规则文件 ──
static NSString *rulesPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/meow_watermark_rules.json"];
}
static NSArray *loadWatermarkClasses(void) {
    NSData *d = [NSData dataWithContentsOfFile:rulesPath()];
    if (!d) return @[];
    @try {
        NSDictionary *r = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        return r[@"watermark_classes"] ?: @[];
    } @catch (...) { return @[]; }
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
        BOOL isWWK = [cn hasPrefix:@"WWK"];
        BOOL isQL  = [cn hasPrefix:@"QL"];

        if (isWWK) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!g_floatBtn.hidden) return;
                g_floatBtn.hidden = NO;
                [g_floatBtn.superview bringSubviewToFront:g_floatBtn];
            });
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [ELKMenuHook hideWatermarksIfEnabled];
                });
            }
        } else if (isQL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                g_floatBtn.hidden = YES;
            });
        }
    } @catch (...) {}
}

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v21");
        g_markedViews = [NSMutableSet set];

        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }

        // 启动时水印+浮窗
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setupFloatButton];
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
                [self hideWatermarksIfEnabled];
            }
        });
    } @catch (NSException *e) {}
}

// ── 右下浮动 📤 按钮 ──
+ (void)setupFloatButton {
    if (g_floatBtn) return;
    g_floatBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat s = 54;
    g_floatBtn.frame = (CGRect){{0,0},{s,s}};
    g_floatBtn.layer.cornerRadius = s / 2;
    g_floatBtn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
    g_floatBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    [g_floatBtn setTitle:@"📤" forState:UIControlStateNormal];
    g_floatBtn.tintColor = [UIColor whiteColor];
    g_floatBtn.hidden = YES;
    g_floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    g_floatBtn.layer.shadowOffset = (CGSize){2,4};
    g_floatBtn.layer.shadowRadius = 6;
    g_floatBtn.layer.shadowOpacity = 0.3;
    [g_floatBtn addTarget:self action:@selector(onFloatTap) forControlEvents:UIControlEventTouchUpInside];

    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.rootViewController && !w.hidden && w.bounds.size.width > 100) {
            CGFloat x = w.bounds.size.width - s - 16;
            CGFloat y = w.bounds.size.height - w.safeAreaInsets.bottom - s - 88;
            g_floatBtn.frame = (CGRect){{x, y},{s, s}};
            [w addSubview:g_floatBtn];
            NSLog(@"[喵喵] ✅ 浮动按钮已放置 (%.0f,%.0f)", x, y);
            break;
        }
    }
}

+ (void)onFloatTap {
    [ELKFileExporter preloadFileList];
    [ELKFileExporter presentFileBrowser];
}

// ── 水印控制 ──
+ (void)hideWatermarksIfEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) return;
    NSArray *names = loadWatermarkClasses();
    if (names.count == 0) return;
    [g_markedViews removeAllObjects];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        hideByClassName(w, names, g_markedViews);
    }
    NSLog(@"[喵喵] 🔒 %lu 个水印 (类名:%@)", (unsigned long)g_markedViews.count,
          [names componentsJoinedByString:@","]);
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
