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

@end
