//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（极简稳定版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

// ── 唯一 Hook：UINavigationController.pushViewController: ──
static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);

static void hook_pushVC(id self, SEL _cmd, UIViewController *vc, BOOL animated) {
    orig_pushVC(self, _cmd, vc, animated);

    @try {
        NSString *cn = NSStringFromClass([vc class]);

        // 检测是否是文件预览页
        BOOL isPreview = NO;
        if ([cn hasPrefix:@"QL"]) isPreview = YES;
        else if ([cn hasPrefix:@"WWK"] && ([cn containsString:@"Preview"] ||
                                            [cn containsString:@"Detail"] ||
                                            [cn containsString:@"File"] ||
                                            [cn containsString:@"Image"] ||
                                            [cn containsString:@"Video"] ||
                                            [cn containsString:@"Doc"] ||
                                            [cn containsString:@"Photo"] ||
                                            [cn containsString:@"Media"])) isPreview = YES;
        else if ([cn containsString:@"DocumentInteraction"]) isPreview = YES;

        if (!isPreview) return;

        NSLog(@"[喵喵] 🎯 预览页: %@", cn);

        // 等页面渲染完再加按钮
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook addExportButton:vc];
        });
    } @catch (...) {}
}

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v6");

        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ %@", e);
    }
}

+ (void)addExportButton:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;

    // 去重
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title isEqualToString:@"📤导出"]) return;
    }

    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"📤导出"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(handleExport:)];

    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy]
        : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;

    NSLog(@"[喵喵] ✅ 按钮已添加");
}

+ (void)handleExport:(UIBarButtonItem *)sender {
    // 找到当前顶层 VC（就是预览页）
    UIViewController *vc = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if (r) {
            // 如果是导航控制器，取 topVC
            if ([r isKindOfClass:[UINavigationController class]]) {
                vc = [(UINavigationController *)r topViewController];
            } else {
                vc = r;
            }
            break;
        }
    }

    if (!vc) return;

    // 在预览 VC 的 view 层级中搜索解密文件
    NSString *path = [ELKFileExporter findDecryptedFileInView:vc.view];
    if (path) {
        [ELKFileExporter shareFileAtPath:path];
    } else {
        [ELKFileExporter showAlertWithTitle:@"未找到文件"
                                     message:@"请确认文件已下载并可以预览。\n\n可尝试：关闭预览，重新点开文件后再试。"];
    }
}

@end
