//
//  ELKMenuHook.m
//  ELKFileSaver - v17 全功能版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addButtonToVC:(UIViewController *)vc;
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
            [ELKMenuHook addButtonToVC:vc];
        });

        // 🔍 水印侦查（v17临时版）— 进页面后 1.5 秒扫描可疑覆盖层
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook detectWatermark];
        });
    } @catch (...) {}
}

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v17");
        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }
    } @catch (NSException *e) {}
}

+ (void)addButtonToVC:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;

    // 去重
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title hasPrefix:@"📤"]) return;
    }

    // 🔥 角标显示文件数量
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

// ── 🔍 水印侦查 ──
static BOOL g_watermarkReported = NO;

+ (void)detectWatermark {
    if (g_watermarkReported) return;

    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [self scanView:w forWatermark:0 rootWindow:w];
    }
}

+ (void)scanView:(UIView *)view forWatermark:(int)depth rootWindow:(UIWindow *)win {
    if (depth > 10 || g_watermarkReported) return;

    for (UIView *sub in view.subviews) {
        NSString *cn = NSStringFromClass([sub class]);

        // 水印特征：覆盖全屏的半透明标签/视图
        if ([cn containsString:@"Watermark"] || [cn containsString:@"water"] ||
            [cn containsString:@"Mark"] || [cn containsString:@"mark"] ||
            [cn containsString:@"Overlay"] || [cn containsString:@"overlay"]) {

            // 检查是否有文字
            NSMutableString *info = [NSMutableString stringWithFormat:@"🔍 类名: %@\n", cn];
            [info appendFormat:@"frame: %.0fx%.0f\n", sub.frame.size.width, sub.frame.size.height];
            [info appendFormat:@"alpha: %.2f\n", sub.alpha];

            // 收集子视图的 UILabel 文本
            for (UIView *child in sub.subviews) {
                if ([child isKindOfClass:[UILabel class]]) {
                    [info appendFormat:@"  文字: \"%@\"\n", ((UILabel *)child).text ?: @""];
                }
            }
            if ([sub isKindOfClass:[UILabel class]]) {
                [info appendFormat:@"  文字: \"%@\"\n", ((UILabel *)sub).text ?: @""];
            }

            NSLog(@"[喵喵] 🔍 水印发现! %@", info);
            [self showWatermarkPopup:info];

            // 🔥 临时隐藏水印 — 测试是否能去掉
            sub.hidden = YES;
            g_watermarkReported = YES;
            return;
        }

        [self scanView:sub forWatermark:depth + 1 rootWindow:win];
    }
}

+ (void)showWatermarkPopup:(NSString *)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"🔍 水印侦查报告"
            message:[info stringByAppendingString:@"\n该水印已临时隐藏！\n截图发给我确认"]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"收到" style:UIAlertActionStyleDefault handler:nil]];
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            UIViewController *r = w.rootViewController;
            while (r.presentedViewController) r = r.presentedViewController;
            if (r) { [r presentViewController:a animated:YES completion:nil]; break; }
        }
    });
}

@end
