//
//  ELKMenuHook.m
//  ELKFileSaver - v12 快照差分方案
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addExportButton:(UIViewController *)vc;
@end

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

        // 🔥 拍快照 → 等解密 → 找新增文件
        [ELKFileExporter takeBeforeSnapshot];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKFileExporter findNewFilesAfterSnapshot];
            [ELKMenuHook addExportButton:vc];
        });
    } @catch (...) {}
}

@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v12");
        Method m = class_getInstanceMethod([UINavigationController class],
                                           @selector(pushViewController:animated:));
        if (m) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ 已安装");
        }
    } @catch (NSException *e) {}
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
    NSString *path = [ELKFileExporter cachedFile];
    if (path) {
        NSLog(@"[喵喵] 📤 导出: %@", [path lastPathComponent]);
        [ELKFileExporter shareFileAtPath:path];
    } else {
        [ELKFileExporter showAlertWithTitle:@"未找到解密文件"
                                     message:@"请先点开文件预览，\n等待文件加载完成后，\n再点「📤导出」。"];
    }
}

@end
