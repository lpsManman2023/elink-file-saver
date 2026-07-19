//
//  ELKMenuHook.m
//  ELKFileSaver - v20 水印标记训练版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addButtonsToVC:(UIViewController *)vc;
@end

static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);
static NSMutableSet *g_markedViews = nil;

// ── 读取水印规则文件 ──
static NSString *rulesPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/meow_watermark_rules.json"];
}

static NSArray *loadWatermarkClasses(void) {
    NSData *d = [NSData dataWithContentsOfFile:rulesPath()];
    if (!d) return @[];
    @try {
        NSDictionary *rules = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        return rules[@"watermark_classes"] ?: @[];
    } @catch (...) { return @[]; }
}

// ── 按类名精准隐藏 ──
static void hideByClassName(UIView *root, NSArray *classNames, NSMutableSet *marked) {
    NSString *cn = NSStringFromClass([root class]);
    if ([classNames containsObject:cn]) {
        root.hidden = YES;
        [marked addObject:[NSValue valueWithNonretainedObject:root]];
    }
    for (UIView *sub in root.subviews) {
        hideByClassName(sub, classNames, marked);
    }
}

// ── Hook pushVC ──
static void hook_pushVC(id self, SEL _cmd, UIViewController *vc, BOOL animated) {
    orig_pushVC(self, _cmd, vc, animated);
    @try {
        NSString *cn = NSStringFromClass([vc class]);
        BOOL shouldAdd = NO;
        if ([cn hasPrefix:@"WWK"]) shouldAdd = YES;
        if ([cn hasPrefix:@"QL"]) shouldAdd = YES;
        if (!shouldAdd) return;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook addButtonsToVC:vc];
        });

        // 水印开关开着 → 按类名自动隐藏
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [ELKMenuHook hideWatermarksIfEnabled];
            });
        }
    } @catch (...) {}
}

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v20");
        g_markedViews = [NSMutableSet set];

        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }

        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self hideWatermarksIfEnabled];
            });
        }
    } @catch (NSException *e) {}
}

+ (void)addButtonsToVC:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;

    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title hasPrefix:@"📤"]) return;
    }
    NSUInteger count = [ELKFileExporter cachedFileCount];
    NSString *title = count > 0
        ? [NSString stringWithFormat:@"📤 导出 (%lu)", (unsigned long)count]
        : @"📤 导出";
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:title style:UIBarButtonItemStylePlain
        target:self action:@selector(onExportTap)];
    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy] : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;
}

+ (void)onExportTap {
    [ELKFileExporter presentFileBrowser];
}

// ── 水印控制（类名精准匹配） ──
+ (void)hideWatermarksIfEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) return;
    NSArray *names = loadWatermarkClasses();
    if (names.count == 0) return;

    [g_markedViews removeAllObjects];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        hideByClassName(w, names, g_markedViews);
    }
    NSLog(@"[喵喵] 🔒 已隐藏 %lu 个水印 (类名:%@)", (unsigned long)g_markedViews.count, [names componentsJoinedByString:@","]);
}

+ (void)hideWatermarksByClassName:(NSString *)className {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        hideByClassName(w, @[className], g_markedViews);
    }
    NSLog(@"[喵喵] 🔒 按类名隐藏: %@", className);
}

+ (void)showAllWatermarks {
    for (NSValue *val in g_markedViews) {
        UIView *v = [val nonretainedObjectValue];
        if (v) v.hidden = NO;
    }
    [g_markedViews removeAllObjects];
    NSLog(@"[喵喵] 🔓 水印已恢复");
}

// ── 扫描候选水印视图（供标记页使用） ──
+ (NSArray *)scanCandidateWatermarkViews {
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableSet *seenClasses = [NSMutableSet set];

    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [self collectCandidatesFrom:w window:w candidates:candidates seenClasses:seenClasses];
    }

    // 按覆盖率降序
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"coverRatio"] compare:a[@"coverRatio"]];
    }];
    return candidates;
}

+ (void)collectCandidatesFrom:(UIView *)view window:(UIWindow *)win
                   candidates:(NSMutableArray *)out seenClasses:(NSMutableSet *)seenClasses {
    for (UIView *sub in view.subviews) {
        NSString *cn = NSStringFromClass([sub class]);
        if ([seenClasses containsObject:cn]) continue;

        CGFloat coverW = sub.frame.size.width / (win.bounds.size.width ?: 1);
        CGFloat coverH = sub.frame.size.height / (win.bounds.size.height ?: 1);

        // 水印特征：覆盖 ≥60% 屏幕 + 有透明度 + 不拦截触摸
        if (coverW >= 0.6 && coverH >= 0.5 && sub.alpha < 0.999 && !sub.userInteractionEnabled) {
            [seenClasses addObject:cn];
            [out addObject:@{
                @"className": cn,
                @"frameW": @(sub.frame.size.width),
                @"frameH": @(sub.frame.size.height),
                @"alpha": @(sub.alpha),
                @"coverRatio": @(coverW),
            }];
        }

        [self collectCandidatesFrom:sub window:win candidates:out seenClasses:seenClasses];
    }
}

// ── 规则文件操作 ──
+ (NSArray *)savedWatermarkClasses {
    return loadWatermarkClasses();
}

+ (void)addWatermarkClass:(NSString *)className {
    NSMutableArray *names = [loadWatermarkClasses() mutableCopy];
    if ([names containsObject:className]) return;
    [names addObject:className];

    NSDictionary *rules = @{@"watermark_classes": names, @"version": @1};
    NSData *d = [NSJSONSerialization dataWithJSONObject:rules options:NSJSONWritingPrettyPrinted error:nil];
    [d writeToFile:rulesPath() atomically:YES];
    NSLog(@"[喵喵] ✅ 已保存规则: %@", className);
}

+ (void)removeWatermarkClass:(NSString *)className {
    NSMutableArray *names = [loadWatermarkClasses() mutableCopy];
    [names removeObject:className];
    NSDictionary *rules = @{@"watermark_classes": names, @"version": @1};
    NSData *d = [NSJSONSerialization dataWithJSONObject:rules options:NSJSONWritingPrettyPrinted error:nil];
    [d writeToFile:rulesPath() atomically:YES];
}

@end
