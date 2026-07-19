//
//  ELKMenuHook.m
//  ELKFileSaver - v18 水印开关版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addButtonsToVC:(UIViewController *)vc;
@end

static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);

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

        // 如果水印开关已开启，延迟应用
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [ELKMenuHook hideWatermarks];
            });
        }
    } @catch (...) {}
}

// ── 水印视图特征判断 ──
static BOOL looksLikeWatermark(UIView *v, UIWindow *win) {
    // 全屏覆盖
    if (v.frame.size.width < win.bounds.size.width * 0.8) return NO;
    if (v.frame.size.height < win.bounds.size.height * 0.6) return NO;
    // 半透明
    if (v.alpha > 0.6 || v.alpha < 0.1) return NO;
    // 不拦截触摸
    if (v.userInteractionEnabled) return NO;

    // 类名包含关键词
    NSString *cn = NSStringFromClass([v class]).lowercaseString;
    if ([cn containsString:@"water"] || [cn containsString:@"mark"] ||
        [cn containsString:@"overlay"] || [cn containsString:@"mask"] ||
        [cn containsString:@"background"]) return YES;

    // 或者包含 UILabel 里面有10位以上文字（名字+手机号）
    for (UIView *child in v.subviews) {
        if ([child isKindOfClass:[UILabel class]]) {
            NSString *text = ((UILabel *)child).text;
            if (text.length > 10) return YES;
        }
    }

    return NO;
}

// ── 递归扫描隐藏水印 ──
static void scanAndHide(UIView *root, UIWindow *win, NSMutableSet *marked) {
    for (UIView *sub in root.subviews) {
        if (looksLikeWatermark(sub, win)) {
            sub.hidden = YES;
            [marked addObject:[NSValue valueWithNonretainedObject:sub]];
        }
        scanAndHide(sub, win, marked);
    }
}

// ── 全局已标记的水印视图集合 ──
static NSMutableSet *g_markedViews = nil;

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v18");
        g_markedViews = [NSMutableSet set];

        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }

        // 启动时如果开关开着，等 UI 加载完就隐藏
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self hideWatermarks];
            });
        }
    } @catch (NSException *e) {}
}

+ (void)addButtonsToVC:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;

    // ── 水印开关按钮（左侧） ──
    BOOL hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"];
    NSString *wmTitle = hidden ? @"🔓 水印开" : @"🔒 去水印";

    BOOL hasWmBtn = NO;
    for (UIBarButtonItem *item in vc.navigationItem.leftBarButtonItems) {
        if ([item.title hasPrefix:@"🔒"] || [item.title hasPrefix:@"🔓"]) { hasWmBtn = YES; break; }
    }
    if (!hasWmBtn) {
        UIBarButtonItem *wmBtn = [[UIBarButtonItem alloc]
            initWithTitle:wmTitle style:UIBarButtonItemStylePlain
            target:self action:@selector(toggleWatermark:)];
        NSMutableArray *leftItems = vc.navigationItem.leftBarButtonItems
            ? [vc.navigationItem.leftBarButtonItems mutableCopy] : [NSMutableArray array];
        [leftItems insertObject:wmBtn atIndex:0];
        vc.navigationItem.leftBarButtonItems = leftItems;
    }

    // ── 导出按钮（右侧） ──
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

// ── 水印开关 ──
+ (void)toggleWatermark:(UIBarButtonItem *)sender {
    BOOL hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"];

    if (hidden) {
        // 当前隐藏中 → 显示水印
        [self showWatermarks];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"meow_watermark_hidden"];
        sender.title = @"🔒 去水印";
        NSLog(@"[喵喵] 🔓 水印已恢复");
    } else {
        // 当前显示中 → 隐藏水印
        [self hideWatermarks];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"meow_watermark_hidden"];
        sender.title = @"🔓 水印开";
        NSLog(@"[喵喵] 🔒 水印已隐藏");
    }

    // 同步更新所有导航栏上的按钮
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if (!r || ![r isKindOfClass:[UINavigationController class]]) continue;
        UINavigationController *nav = (UINavigationController *)r;
        [self updateWatermarkButton:nav.topViewController title:sender.title];
    }
}

+ (void)updateWatermarkButton:(UIViewController *)vc title:(NSString *)title {
    if (!vc || !vc.navigationItem) return;
    for (UIBarButtonItem *item in vc.navigationItem.leftBarButtonItems) {
        if ([item.title hasPrefix:@"🔒"] || [item.title hasPrefix:@"🔓"]) {
            item.title = title;
        }
    }
}

// ── 扫描并隐藏水印 ──
+ (void)hideWatermarks {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        scanAndHide(w, w, g_markedViews);
    }
    NSLog(@"[喵喵] 🔒 已隐藏 %lu 个水印视图", (unsigned long)g_markedViews.count);
}

// ── 恢复水印 ──
+ (void)showWatermarks {
    for (NSValue *val in g_markedViews) {
        UIView *v = [val nonretainedObjectValue];
        if (v) v.hidden = NO;
    }
    [g_markedViews removeAllObjects];
    NSLog(@"[喵喵] 🔓 水印已恢复");
}

@end
