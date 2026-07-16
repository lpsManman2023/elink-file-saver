//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（诊断版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (void)addExportButton:(UIViewController *)vc;
@end

// ── Hook：UINavigationController.pushViewController: ──
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
        NSLog(@"[喵喵] 🚀 install");
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
        initWithTitle:@"📤导出" style:UIBarButtonItemStylePlain target:self action:@selector(handleExport:)];
    NSMutableArray *items = vc.navigationItem.rightBarButtonItems
        ? [vc.navigationItem.rightBarButtonItems mutableCopy] : [NSMutableArray array];
    [items addObject:btn];
    vc.navigationItem.rightBarButtonItems = items;
    NSLog(@"[喵喵] ✅ 按钮已添加");
}

+ (void)handleExport:(UIBarButtonItem *)sender {
    // 先尝试导出
    UIViewController *vc = [self topPreviewVC];
    if (vc) {
        NSString *path = [ELKFileExporter findDecryptedFileInView:vc.view];
        if (path) {
            [ELKFileExporter shareFileAtPath:path];
            return;
        }
    }

    // 没找到 → dump 诊断信息到文件 → 让用户分享给我
    NSString *dump = [self dumpAllInfo];
    NSString *dumpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"meow_debug.txt"];
    [dump writeToFile:dumpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSLog(@"[喵喵] 📝 诊断文件: %@", dumpPath);
    NSLog(@"[喵喵] === 诊断信息 ===\n%@\n=== 结束 ===", dump);

    // 弹出分享 → 用户可以发送给我
    [ELKFileExporter showDebugShareAlertWithPath:dumpPath dump:dump];
}

+ (UIViewController *)topPreviewVC {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if (r) {
            if ([r isKindOfClass:[UINavigationController class]]) {
                return [(UINavigationController *)r topViewController];
            }
            return r;
        }
    }
    return nil;
}

+ (NSString *)dumpAllInfo {
    NSMutableString *s = [NSMutableString string];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [s appendFormat:@"=== 喵喵插件诊断报告 %@ ===\n\n", [f stringFromDate:[NSDate date]]];

    // ── 1. 所有 Window → Root VC → 导航栈 ──
    [s appendString:@"【Window / VC 层级】\n"];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [s appendFormat:@"  Window: %@ hidden=%d size=%.0fx%.0f\n",
         NSStringFromClass([w class]), w.hidden, w.bounds.size.width, w.bounds.size.height];

        UIViewController *r = w.rootViewController;
        int depth = 0;
        while (r && depth < 20) {
            [s appendFormat:@"    [%d] %@\n", depth, NSStringFromClass([r class])];
            if ([r isKindOfClass:[UINavigationController class]]) {
                for (UIViewController *child in [(UINavigationController *)r viewControllers]) {
                    [s appendFormat:@"      nav-stack: %@\n", NSStringFromClass([child class])];
                    if (child.isViewLoaded) {
                        [self dumpView:child.view to:s prefix:@"        " maxDepth:3];
                    }
                }
                // presented on top of nav
                if (r.presentedViewController) {
                    r = r.presentedViewController;
                    depth++;
                    continue;
                }
                break;
            }
            if (r.presentedViewController) {
                r = r.presentedViewController;
                depth++;
            } else {
                break;
            }
        }
    }
    [s appendString:@"\n"];

    // ── 2. 预览页 VC 属性 ──
    UIViewController *pvc = [self topPreviewVC];
    if (pvc) {
        [s appendFormat:@"【预览页 VC: %@】\n", NSStringFromClass([pvc class])];

        if (pvc.navigationItem) {
            [s appendFormat:@"  title=%@, prompt=%@\n", pvc.navigationItem.title, pvc.navigationItem.prompt];
            [s appendFormat:@"  rightItems=%lu\n", (unsigned long)pvc.navigationItem.rightBarButtonItems.count];
        }
        if (pvc.isViewLoaded) {
            [s appendFormat:@"  view=%@ size=%.0fx%.0f subviews=%lu\n",
             NSStringFromClass([pvc.view class]),
             pvc.view.bounds.size.width, pvc.view.bounds.size.height,
             (unsigned long)pvc.view.subviews.count];
        }
        [self dumpVCProperties:pvc to:s];
        [s appendString:@"\n"];
    }

    // ── 3. View 层级 + 含 NSString/NSURL 属性的视图 ──
    if (pvc && pvc.isViewLoaded) {
        [s appendString:@"【View 层级（含路径/URL属性）】\n"];
        [self dumpView:pvc.view to:s prefix:@"" maxDepth:10];
        [s appendString:@"\n"];
    }

    // ── 4. 全局搜索 /tmp/ 目录下 eLink 相关文件 ──
    [s appendString:@"【全局 /tmp/ 搜索】\n"];
    [self dumpTmpFilesTo:s];
    [s appendString:@"\n"];

    [s appendString:@"=== 报告结束 ==="];
    return s;
}

// ── 递归 dump view 层级 ──
+ (void)dumpView:(UIView *)v to:(NSMutableString *)s prefix:(NSString *)pfx maxDepth:(int)depth {
    if (!v || depth <= 0 || s.length > 800000) return;
    [s appendFormat:@"%@%@ tag=%ld frame=(%.0f,%.0f,%.0f,%.0f)",
     pfx, NSStringFromClass([v class]), (long)v.tag,
     v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height];

    // 检查 NSString/NSURL 属性
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([v class], &count);
    NSMutableString *found = [NSMutableString string];
    for (unsigned int i = 0; i < count && i < 200; i++) {
        @try {
            NSString *pName = [NSString stringWithUTF8String:property_getName(props[i])];
            id val = [v valueForKey:pName];

            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) {
                NSString *str = val;
                if (str.length > 120) str = [[str substringToIndex:120] stringByAppendingString:@"..."];
                [found appendFormat:@" | \"%@\"=\"%@\"", pName, str];
            } else if ([val isKindOfClass:[NSURL class]]) {
                [found appendFormat:@" | \"%@\"=NSURL:%@", pName, [val absoluteString]];
            } else if (val && ![val isKindOfClass:[NSNumber class]] &&
                       ![val isKindOfClass:[NSString class]] && ![val isKindOfClass:[NSURL class]] &&
                       ![val isKindOfClass:[UIView class]] && ![val isKindOfClass:NSClassFromString(@"CALayer")]) {
                [found appendFormat:@" | \"%@\"=%@", pName, NSStringFromClass([val class])];
            }
        } @catch (...) {}
    }
    free(props);

    if (found.length > 0) [s appendString:found];
    [s appendString:@"\n"];

    for (UIView *sub in v.subviews) {
        [self dumpView:sub to:s prefix:[pfx stringByAppendingString:@"  "] maxDepth:depth - 1];
    }
}

// ── 列出 VC 的所有属性 ──
+ (void)dumpVCProperties:(UIViewController *)vc to:(NSMutableString *)s {
    [s appendString:@"  【属性列表】\n"];
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([vc class], &count);
    for (unsigned int i = 0; i < count && i < 300; i++) {
        @try {
            NSString *pName = [NSString stringWithUTF8String:property_getName(props[i])];
            const char *attr = property_getAttributes(props[i]);
            id val = [vc valueForKey:pName];

            NSString *typeStr = [NSString stringWithUTF8String:attr ?: ""];
            if ([val isKindOfClass:[NSString class]]) {
                NSString *str = val;
                if (str.length > 100) str = [[str substringToIndex:100] stringByAppendingString:@"..."];
                [s appendFormat:@"    %@ (%@) = \"%@\"\n", pName, [self typeFromAttr:typeStr], str];
            } else if ([val isKindOfClass:[NSURL class]]) {
                [s appendFormat:@"    %@ (%@) = NSURL:%@\n", pName, [self typeFromAttr:typeStr], [val absoluteString]];
            } else if (val && ![val isKindOfClass:[NSNumber class]] &&
                       ![val isKindOfClass:[UIView class]] && ![val isKindOfClass:NSClassFromString(@"CALayer")]) {
                [s appendFormat:@"    %@ (%@) = %@\n", pName, [self typeFromAttr:typeStr], NSStringFromClass([val class])];
            }
        } @catch (...) {}
    }
    free(props);
}

+ (NSString *)typeFromAttr:(NSString *)attr {
    if ([attr containsString:@"NSString"]) return @"NSString";
    if ([attr containsString:@"NSURL"]) return @"NSURL";
    if ([attr containsString:@"NSData"]) return @"NSData";
    if ([attr containsString:@"NSArray"]) return @"NSArray";
    if ([attr containsString:@"NSDictionary"]) return @"NSDictionary";
    if ([attr containsString:@"@\""]) {
        NSRange r1 = [attr rangeOfString:@"@\""];
        NSRange r2 = [attr rangeOfString:@"\"" options:0 range:NSMakeRange(r1.location+2, attr.length-r1.location-2)];
        if (r2.location != NSNotFound) {
            return [attr substringWithRange:NSMakeRange(r1.location+2, r2.location-r1.location-2)];
        }
    }
    return @"?";
}

// ── 列出 /tmp/ 下的文件 ──
+ (void)dumpTmpFilesTo:(NSMutableString *)s {
    NSArray *dirs = @[@"/tmp", @"/var/tmp"];
    for (NSString *dir in dirs) {
        @try {
            NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
            [s appendFormat:@"  %@ (%lu files):\n", dir, (unsigned long)files.count];
            for (NSString *f in files) {
                NSString *fp = [dir stringByAppendingPathComponent:f];
                unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:fp error:nil] fileSize];
                if (sz > 1000) {
                    [s appendFormat:@"    %@ (%llu KB)\n", f, sz/1024];
                }
            }
        } @catch (...) {}
    }

    // 也搜 Caches
    @try {
        NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSArray *cacheFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cacheDir error:nil];
        [s appendFormat:@"  Caches (%lu files):\n", (unsigned long)cacheFiles.count];
        NSArray *topCache = cacheFiles.count > 50 ? [cacheFiles subarrayWithRange:NSMakeRange(0, 50)] : cacheFiles;
        for (NSString *f in topCache) {
            NSString *fp = [cacheDir stringByAppendingPathComponent:f];
            unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:fp error:nil] fileSize];
            if (sz > 10000) {
                [s appendFormat:@"    %@ (%llu KB)\n", f, sz/1024];
            }
        }
    } @catch (...) {}
}

@end
