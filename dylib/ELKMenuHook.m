//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（C+F组合方案 v7）
//
//  方案 C: Hook QLPreviewController.initWithPreviewItems: 拦截文件 URL
//  方案 F: KVC 搜索 VC 对象属性链（在 ELKFileExporter 中）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

// ── 前向声明 ──
@interface ELKMenuHook (Private)
+ (void)addExportButton:(UIViewController *)vc;
+ (void)interceptPreviewItems:(NSArray *)items;
@end

// ============================================================
//  方案 C: Hook QLPreviewController 拦截预览文件
// ============================================================
static id (*orig_QL_initWithItems)(id, SEL, NSArray *);

static id hook_QL_initWithItems(id self, SEL _cmd, NSArray *items) {
    // 拦截预览的文件列表
    if (items.count > 0) {
        [ELKMenuHook interceptPreviewItems:items];
    }
    return orig_QL_initWithItems(self, _cmd, items);
}

// ============================================================
//  Hook: UINavigationController.pushViewController:
// ============================================================
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

        // 等页面渲染完：加按钮 + 搜索 VC 属性（方案 F）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ELKMenuHook addExportButton:vc];
            // 方案 F：立即搜索 VC 属性链缓存文件路径
            NSString *path = [ELKFileExporter searchVCForFile:vc];
            if (path) {
                [ELKFileExporter cacheInterceptedPath:path];
            }
        });
    } @catch (...) {}
}

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install v7 (C+F)");

        // Hook 1: pushViewController
        Method m1 = class_getInstanceMethod([UINavigationController class],
                                            @selector(pushViewController:animated:));
        if (m1) {
            orig_pushVC = (void(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_pushVC);
            NSLog(@"[喵喵] ✅ pushVC Hook 完成");
        }

        // Hook 2: QLPreviewController.initWithPreviewItems: (方案 C)
        Class ql = NSClassFromString(@"QLPreviewController");
        if (ql) {
            SEL sel = NSSelectorFromString(@"initWithPreviewItems:");
            Method m2 = class_getInstanceMethod(ql, sel);
            if (m2) {
                orig_QL_initWithItems = (id(*)(id, SEL, NSArray *))method_getImplementation(m2);
                method_setImplementation(m2, (IMP)hook_QL_initWithItems);
                NSLog(@"[喵喵] ✅ QLPreviewItem Hook 完成（方案C）");
            } else {
                NSLog(@"[喵喵] ⚠️ QLPreviewController 存在但无 initWithPreviewItems: 方法");
            }
        } else {
            NSLog(@"[喵喵] ⚠️ QLPreviewController 类不存在（eLink 用自建预览器）");
        }

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ install: %@", e);
    }
}

// ── 方案 C: 拦截预览文件列表 ──
+ (void)interceptPreviewItems:(NSArray *)items {
    for (id item in items) {
        @try {
            // QLPreviewItem 协议：previewItemURL
            if ([item respondsToSelector:@selector(previewItemURL)]) {
                NSURL *url = [item performSelector:@selector(previewItemURL)];
                if (url && [url isFileURL]) {
                    NSString *p = [url path];
                    if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                        unsigned long long sz = [[[NSFileManager defaultManager]
                            attributesOfItemAtPath:p error:nil] fileSize];
                        if (sz > 100) {
                            NSLog(@"[喵喵] 🔥 方案C: QLPreviewItem URL = %@ (%llu bytes)", [p lastPathComponent], sz);
                            [ELKFileExporter cacheInterceptedPath:p];
                        }
                    }
                }
            }

            // 也查 KVC（有些实现把 URL 藏在别的地方）
            for (NSString *key in @[@"previewItemURL", @"url", @"fileURL", @"filePath"]) {
                @try {
                    id val = [item valueForKey:key];
                    NSURL *fileURL = nil;
                    if ([val isKindOfClass:[NSURL class]]) fileURL = val;
                    else if ([val isKindOfClass:[NSString class]]) {
                        NSString *s = val;
                        if ([s hasPrefix:@"file://"]) fileURL = [NSURL URLWithString:s];
                        else if ([s hasPrefix:@"/"]) fileURL = [NSURL fileURLWithPath:s];
                    }
                    if (fileURL && [fileURL isFileURL]) {
                        NSString *p = [fileURL path];
                        if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                            unsigned long long sz = [[[NSFileManager defaultManager]
                                attributesOfItemAtPath:p error:nil] fileSize];
                            if (sz > 100) {
                                NSLog(@"[喵喵] 🔥 方案C: KVC(%@) = %@", key, [p lastPathComponent]);
                                [ELKFileExporter cacheInterceptedPath:p];
                            }
                        }
                    }
                } @catch (...) {}
            }
        } @catch (...) {}
    }
}

// ── 预览页加导出按钮 ──
+ (void)addExportButton:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if ([item.title isEqualToString:@"📤导出"]) return;
    }
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"📤导出" style:UIBarButtonItemStylePlain target:self action:@selector(handleExport:)];
    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy] : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;
    NSLog(@"[喵喵] ✅ 按钮已添加");
}

// ── 导出按钮点击 ──
+ (void)handleExport:(UIBarButtonItem *)sender {
    // 优先：方案 C 拦截缓存
    NSString *path = [ELKFileExporter cachedPath];
    if (path) {
        NSLog(@"[喵喵] 📤 使用方案C路径");
        [ELKFileExporter shareFileAtPath:path];
        return;
    }

    // 兜底：方案 F 搜索当前 VC
    UIViewController *vc = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if (r) {
            if ([r isKindOfClass:[UINavigationController class]]) {
                vc = [(UINavigationController *)r topViewController];
            } else {
                vc = r;
            }
            break;
        }
    }

    if (vc) {
        path = [ELKFileExporter searchVCForFile:vc];
    }

    if (path) {
        NSLog(@"[喵喵] 📤 使用方案F路径");
        [ELKFileExporter shareFileAtPath:path];
    } else {
        [ELKFileExporter showAlertWithTitle:@"未找到文件"
                                     message:@"可能原因：\n\n1. eLink 用了自建预览器\n   (非 QLPreviewController)\n\n2. 文件路径不在 VC 属性中\n\n请尝试：关闭预览，重新点开文件后再试。"];
    }
}

@end
