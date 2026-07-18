//
//  ELKMenuHook.m
//  ELKFileSaver - v14 文件浏览器
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

        // 📤 在有导航栏的页面上加按钮（聊天页/文件传输页/预览页等）
        // 只要不是系统页都加，让用户随时可以浏览文件
        BOOL shouldAdd = NO;
        if ([cn hasPrefix:@"WWK"]) shouldAdd = YES;  // eLink 的所有页面
        if ([cn hasPrefix:@"QL"]) shouldAdd = YES;   // QuickLook 预览
        if (!shouldAdd) return;

        NSLog(@"[喵喵] 🎯 页面: %@", cn);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook addButtonToVC:vc];
        });
    } @catch (...) {}
}

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v14 文件浏览器");
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
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title isEqualToString:@"📤"]) return;
    }
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"📤" style:UIBarButtonItemStylePlain
        target:self action:@selector(onExportTap)];
    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy] : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;
    NSLog(@"[喵喵] ✅ 📤 按钮已添加");
}

+ (void)onExportTap {
    [ELKFileExporter presentFileBrowser];
}

@end
