//
//  ELKMenuHook.m
//  ELKFileSaver - v8 文件系统监控方案
//
//  唯一 Hook：UINavigationController.pushViewController:
//  只做两件事：检测预览页 → 加按钮 → 按钮点导出
//
//  文件查找全部走 ELKFileExporter（纯文件系统操作，零崩溃风险）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addExportButton:(UIViewController *)vc;
@end

// ── 唯一 Hook ──
static void (*orig_pushVC)(id, SEL, UIViewController *, BOOL);

static void hook_pushVC(id self, SEL _cmd, UIViewController *vc, BOOL animated) {
    orig_pushVC(self, _cmd, vc, animated);
    @try {
        NSString *cn = NSStringFromClass([vc class]);
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
        NSLog(@"[喵喵] 🚀 install v10");

        // Hook pushVC
        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ pushVC Hook 完成");
        }
        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ %@", e);
    }
}

+ (void)addExportButton:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title isEqualToString:@"📤导出"]) return;
    }
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"📤导出" style:UIBarButtonItemStylePlain
        target:self action:@selector(handleExport:)];
    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy] : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;
    NSLog(@"[喵喵] ✅ 按钮已添加");
}

+ (void)handleExport:(UIBarButtonItem *)sender {
    // 🔥 后台扫描文件，主线程展示结果
    [ELKFileExporter findDecryptedFileAsync:^(NSString *path) {
        if (path) {
            [ELKFileExporter shareFileAtPath:path];
        } else {
            [ELKFileExporter showAlertWithTitle:@"未找到解密文件"
                                         message:@"请确认：\n\n① 文件已在预览中打开\n② 文件已下载完成\n\n提示：点开文件查看后，\n立即点右上角「📤导出」。"];
        }
    }];
}

@end
