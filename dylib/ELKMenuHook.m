//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（预览页加导出按钮 v5）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 前向声明 ──
@interface ELKMenuHook (Private)
+ (void)onNewVC:(UIViewController *)vc;
+ (void)addExportButton:(UIViewController *)vc;
+ (void)onExportButtonTap;
+ (BOOL)isPreviewVC:(UIViewController *)vc;
@end

// ── 缓存 ──
static NSString *g_cachedPath = nil;
static BOOL g_inExportFlow = NO;

// ============================================================
//  Hook 1: UINavigationController.pushViewController:
// ============================================================
static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);

static void hook_pushVC(id self, SEL _cmd, UIViewController *vc, BOOL animated) {
    orig_pushVC(self, _cmd, vc, animated);
    if (g_inExportFlow) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ELKMenuHook onNewVC:vc];
    });
}

// ============================================================
//  Hook 2: UIViewController.presentViewController:animated:completion:
// ============================================================
static void (*orig_presentVC)(id, SEL, UIViewController *, BOOL, void(^)(void));

static void hook_presentVC(id self, SEL _cmd, UIViewController *vc,
                           BOOL animated, void(^completion)(void)) {
    orig_presentVC(self, _cmd, vc, animated, completion);

    if (g_inExportFlow) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ELKMenuHook onNewVC:vc];
    });
}

// ============================================================
//  导出按钮点击
// ============================================================
static void onExportTap(void) {
    if (g_cachedPath && [[NSFileManager defaultManager] fileExistsAtPath:g_cachedPath]) {
        NSLog(@"[喵喵] 📤 导出缓存: %@", g_cachedPath);
        g_inExportFlow = YES;
        [ELKFileExporter shareFileAtPath:g_cachedPath];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            g_inExportFlow = NO;
        });
    } else {
        UIViewController *top = [ELKRuntimeHelper topViewController];
        if (top && top.view) {
            NSString *found = [ELKFileExporter findDecryptedFileInView:top.view];
            if (found) {
                g_inExportFlow = YES;
                [ELKFileExporter shareFileAtPath:found];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    g_inExportFlow = NO;
                });
                return;
            }
        }
        [ELKFileExporter showAlertWithTitle:@"未找到文件"
                                     message:@"无法定位解密文件。" ];
    }
}

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v5");

        Method m1 = class_getInstanceMethod([UINavigationController class],
                                            @selector(pushViewController:animated:));
        if (m1) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ pushVC Hook 完成");
        }

        Method m2 = class_getInstanceMethod([UIViewController class],
                                            @selector(presentViewController:animated:completion:));
        if (m2) {
            orig_presentVC = (void(*)(id, SEL, UIViewController *, BOOL, void(^)(void)))
                method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_presentVC);
            NSLog(@"[喵喵] ✅ presentVC Hook 完成");
        }

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ %@", e);
    }
}

+ (BOOL)isPreviewVC:(UIViewController *)vc {
    NSString *cn = NSStringFromClass([vc class]);

    if ([cn hasPrefix:@"QLPreview"]) return YES;

    if ([cn hasPrefix:@"WWK"]) {
        if ([cn containsString:@"File"] || [cn containsString:@"Image"] ||
            [cn containsString:@"Video"] || [cn containsString:@"Doc"] ||
            [cn containsString:@"Preview"] || [cn containsString:@"Detail"] ||
            [cn containsString:@"Photo"] || [cn containsString:@"Media"]) {
            return YES;
        }
    }

    if ([cn containsString:@"DocumentInteraction"]) return YES;

    return NO;
}

+ (void)onNewVC:(UIViewController *)vc {
    if (!vc || g_inExportFlow) return;
    if (![self isPreviewVC:vc]) return;

    NSLog(@"[喵喵] 🎯 预览页: %@", NSStringFromClass([vc class]));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (vc.view) {
            NSString *path = [ELKFileExporter findDecryptedFileInView:vc.view];
            if (path) {
                g_cachedPath = path;
            }
            [self addExportButton:vc];
        }
    });
}

+ (void)addExportButton:(UIViewController *)vc {
    if (vc.navigationItem.rightBarButtonItems) {
        for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
            if ([item.title isEqualToString:@"📤导出"]) return;
        }
    }

    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"📤导出"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(onExportButtonTap)];

    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy]
        : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;

    NSLog(@"[喵喵] ✅ 按钮已添加");
}

+ (void)onExportButtonTap {
    onExportTap();
}

@end
