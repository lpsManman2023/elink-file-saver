//
//  ELKFileExporter.m
//  ELKFileSaver - 喵喵插件（C+F组合方案）
//
//  方案 C: Hook QLPreviewController 拦截（在 ELKMenuHook 中）
//  方案 F: 搜索 VC 对象属性链（本文件）
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 文件级静态变量 ──
static NSString *g_interceptedPath = nil;

// ============================================================
@implementation ELKFileExporter

+ (void)cacheInterceptedPath:(NSString *)path {
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        g_interceptedPath = path;
        NSLog(@"[喵喵] 🔥 方案C拦截: %@", [path lastPathComponent]);
    }
}

+ (NSString *)cachedPath {
    if (g_interceptedPath && [[NSFileManager defaultManager] fileExistsAtPath:g_interceptedPath]) {
        return g_interceptedPath;
    }
    g_interceptedPath = nil;
    return nil;
}

// ============================================================
//  方案 F: KVC 递归搜索 VC 对象属性（不搜索 View！）
//  只走 VC → message → media → file → path 这条链
// ============================================================

+ (NSString *)searchVCForFile:(UIViewController *)vc {
    if (!vc) return nil;

    // 先查缓存（方案 C 的拦截结果）
    NSString *cached = [self cachedPath];
    if (cached) return cached;

    // KVC 搜索 VC 自身属性
    NSString *found = [self searchObject:vc depth:0];
    if (found) return found;

    return nil;
}

+ (NSString *)searchObject:(id)obj depth:(int)depth {
    if (!obj || depth > 4) return nil;

    NSString *bestNonTemp = nil;
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([obj class], &count);

    for (unsigned int i = 0; i < count && i < 100; i++) {
        const char *pName = property_getName(props[i]);
        @try {
            id val = [obj valueForKey:[NSString stringWithUTF8String:pName]];

            // ── 找到了 NSString ──
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                NSString *s = val;
                if ([s hasPrefix:@"file://"]) s = [[NSURL URLWithString:s] path];

                if ([s hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:s]) {
                    unsigned long long sz = [[[NSFileManager defaultManager]
                        attributesOfItemAtPath:s error:nil] fileSize];
                    if (sz > 100) {
                        // 🔥 只要文件真实存在就接受
                        if ([s containsString:@"/tmp/"] || [s containsString:@"/Caches/"] ||
                            [s containsString:@"/Temp/"]) {
                            NSLog(@"[喵喵] 🔥 方案F VC属性: %s = %@ (%llu bytes)", pName, [s lastPathComponent], sz);
                            free(props);
                            return s;
                        }
                        if (!bestNonTemp) bestNonTemp = s;
                    }
                }
                continue;
            }

            // ── 找到了 NSURL ──
            if ([val isKindOfClass:[NSURL class]]) {
                NSURL *url = val;
                if ([url isFileURL]) {
                    NSString *p = [url path];
                    if ([p hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                        unsigned long long sz = [[[NSFileManager defaultManager]
                            attributesOfItemAtPath:p error:nil] fileSize];
                        if (sz > 100) {
                            if ([p containsString:@"/tmp/"] || [p containsString:@"/Caches/"] ||
                                [p containsString:@"/Temp/"]) {
                                NSLog(@"[喵喵] 🔥 方案F VC属性: %s = NSURL:%@ (%llu bytes)", pName, [p lastPathComponent], sz);
                                free(props);
                                return p;
                            }
                            if (!bestNonTemp) bestNonTemp = p;
                        }
                    }
                }
                continue;
            }

            // ── 找到了子对象 → 递归深入 ──
            if (val && depth < 3 &&
                ![val isKindOfClass:[NSNumber class]] &&
                ![val isKindOfClass:[NSString class]] &&
                ![val isKindOfClass:[NSURL class]] &&
                ![val isKindOfClass:[UIView class]] &&
                ![val isKindOfClass:[UIViewController class]] &&
                ![val isKindOfClass:NSClassFromString(@"CALayer")] &&
                ![val isEqual:obj]) {

                NSString *found = [self searchObject:val depth:depth + 1];
                if (found) { free(props); return found; }
            }
        } @catch (...) {}
    }
    free(props);
    return bestNonTemp;
}

// ============================================================
//  导出 & 提示
// ============================================================

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    if (shareVC.popoverPresentationController) {
        UIViewController *top = [ELKRuntimeHelper topViewController];
        shareVC.popoverPresentationController.sourceView = top.view;
        CGFloat hw = top.view.bounds.size.width / 2;
        CGFloat hh = top.view.bounds.size.height / 2;
        shareVC.popoverPresentationController.sourceRect = (CGRect){{hw, hh}, {0, 0}};
        shareVC.popoverPresentationController.permittedArrowDirections = 0;
    }
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (vc) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc presentViewController:shareVC animated:YES completion:nil];
        });
    }
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [ELKRuntimeHelper topViewController];
        if (!vc) return;
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:title message:message
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

@end
