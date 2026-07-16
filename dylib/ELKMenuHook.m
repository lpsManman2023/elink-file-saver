//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（预览页加导出按钮 v5）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 缓存：预览打开时立即搜到的解密文件路径 ──
static NSString *g_cachedPath = nil;

// ── 防止 present hook 递归（我们自己的弹窗不能触发 hook） ──
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
    // 🔥 我们的导出流程中的 present 不能触发 hook
    BOOL wasExportFlow = g_inExportFlow;
    if (!wasExportFlow) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook onNewVC:vc];
        });
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

// ============================================================
//  导出按钮点击
// ============================================================
static void onExportTap(void) {
    if (g_cachedPath && [[NSFileManager defaultManager] fileExistsAtPath:g_cachedPath]) {
        NSLog(@"[喵喵] 📤 导出缓存文件: %@", g_cachedPath);
        g_inExportFlow = YES;
        [ELKFileExporter shareFileAtPath:g_cachedPath];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            g_inExportFlow = NO;
        });
    } else {
        // 兜底：重新搜索
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

    // Apple QuickLook
    if ([cn hasPrefix:@"QLPreview"]) return YES;

    // WeWork 自定义预览页
    if ([cn hasPrefix:@"WWK"]) {
        if ([cn containsString:@"File"] || [cn containsString:@"Image"] ||
            [cn containsString:@"Video"] || [cn containsString:@"Doc"] ||
            [cn containsString:@"Preview"] || [cn containsString:@"Detail"] ||
            [cn containsString:@"Photo"] || [cn containsString:@"Media"]) {
            return YES;
        }
    }

    // UIDocumentInteractionController
    if ([cn containsString:@"DocumentInteraction"]) return YES;

    return NO;
}

+ (void)onNewVC:(UIViewController *)vc {
    if (!vc || g_inExportFlow) return;
    if (![self isPreviewVC:vc]) return;

    NSLog(@"[喵喵] 🎯 预览页: %@", NSStringFromClass([vc class]));

    // 🔥 立即搜索解密文件
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (vc.view) {
            NSString *path = [ELKFileExporter findDecryptedFileInView:vc.view];
            if (path) {
                g_cachedPath = path;
            }
            // 加按钮
            [self addExportButton:vc];
        }
    });
}

+ (void)addExportButton:(UIViewController *)vc {
    // 去重
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
