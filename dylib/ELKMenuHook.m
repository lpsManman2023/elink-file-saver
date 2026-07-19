//
//  ELKMenuHook.m
//  ELKFileSaver - v19 水印精准击杀
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addButtonsToVC:(UIViewController *)vc;
@end

static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);
static NSMutableSet *g_markedViews = nil;

// ── 水印隐藏逻辑 ──
static void scanAndApply(UIView *root) {
    for (UIView *sub in root.subviews) {
        // 策略1: 搜索子视图中的 UILabel 含目标文字
        for (UIView *child in sub.subviews) {
            if ([child isKindOfClass:[UILabel class]]) {
                NSString *t = ((UILabel *)child).text ?: @"";
                if ([t containsString:@"耿娟"] || [t containsString:@"6789"]) {
                    sub.hidden = YES;
                    [g_markedViews addObject:[NSValue valueWithNonretainedObject:sub]];
                    break;
                }
            }
        }
        // 策略2 兜底: 全屏半透明无交互
        if (!sub.hidden && sub.alpha > 0.05 && sub.alpha < 0.65 &&
            !sub.userInteractionEnabled &&
            sub.frame.size.width >= root.bounds.size.width * 0.65) {
            sub.hidden = YES;
            [g_markedViews addObject:[NSValue valueWithNonretainedObject:sub]];
        }
        // 继续递归
        scanAndApply(sub);
    }
}

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

        // 水印开关开着 → 自动隐藏
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
        NSLog(@"[喵喵] 🚀 install v19");
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

    // 导出按钮（右侧）
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

// ── 水印控制（由设置页调用） ──
+ (void)hideWatermarksIfEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"]) return;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        scanAndApply(w);
    }
}

+ (void)showAllWatermarks {
    for (NSValue *val in g_markedViews) {
        UIView *v = [val nonretainedObjectValue];
        if (v) v.hidden = NO;
    }
    [g_markedViews removeAllObjects];
}

@end
