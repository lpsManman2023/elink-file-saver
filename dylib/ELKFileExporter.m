//
//  ELKFileExporter.m
//  ELKFileSaver - v8 纯文件系统监控（零 Hook App 对象）
//
//  原理：
//    eLink 预览文件时必定把解密文件写入 tmp/ 或 Caches/
//    我们用 GCD timer 每 2 秒扫描一次目录
//    发现新文件 → 缓存路径
//    用户点 📤导出 → 直接用缓存路径
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

// ── 监控状态 ──
static NSMutableSet *g_knownFiles = nil;     // 已知文件路径集合
static NSString *g_bestCandidate = nil;       // 最佳候选文件
static dispatch_source_t g_timer = NULL;

// 文件扩展名黑名单（绝对不导出的类型）
static NSSet *blacklist(void) {
    static NSSet *set = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithObjects:
               @"plist", @"json", @"db", @"sqlite", @"sqlite3",
               @"dat", @"idx", @"log", @"txt-small", nil];
    });
    return set;
}

// 检查文件是否值得导出
static BOOL isGoodFile(NSString *path, unsigned long long size) {
    if (size < 5000) return NO;  // < 5KB 忽略

    NSString *ext = [[path pathExtension] lowercaseString];

    // 黑名单
    if ([blacklist containsObject:ext]) return NO;

    // 无后缀但很小的文件忽略
    if (ext.length == 0 && size < 50000) return NO;

    return YES;
}

// 扫描目录，返回最符合条件的文件路径
static NSString *scanDir(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!files.count) return nil;

    NSString *best = nil;
    NSDate *bestDate = nil;
    unsigned long long bestSize = 0;

    for (NSString *name in files) {
        @autoreleasepool {
            NSString *fp = [dir stringByAppendingPathComponent:name];
            NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
            if (!attr || [attr[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;

            unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
            NSDate *mod = attr[NSFileModificationDate];

            if (!isGoodFile(fp, sz)) continue;

            // 策略：找最近修改的、最大的文件
            if (!best || [mod compare:bestDate] == NSOrderedDescending ||
                ([mod isEqualToDate:bestDate] && sz > bestSize)) {
                best = fp;
                bestDate = mod;
                bestSize = sz;
            }
        }
    }

    if (best) {
        NSLog(@"[喵喵] 📁 扫描发现: %@ (%llu KB, %@)",
              [best lastPathComponent], bestSize/1024, bestDate);
    }
    return best;
}

// ============================================================
@implementation ELKFileExporter

+ (void)startFileMonitor {
    if (g_timer) return;

    g_knownFiles = [NSMutableSet set];

    // 初始快照
    [self takeSnapshot];

    // 创建 GCD timer，每 2 秒扫描
    g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                     dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(g_timer,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              2 * NSEC_PER_SEC,
                              0.5 * NSEC_PER_SEC);

    dispatch_source_set_event_handler(g_timer, ^{
        [self checkForNewFiles];
    });

    dispatch_resume(g_timer);
    NSLog(@"[喵喵] 🔍 文件监控已启动");
}

+ (void)takeSnapshot {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tmp = NSTemporaryDirectory();
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

        for (NSString *dir in @[tmp, caches]) {
            NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *name in files) {
                @autoreleasepool {
                    NSString *fp = [dir stringByAppendingPathComponent:name];
                    NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
                    if (attr && ![attr[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                        unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
                        // 用 path+size 作为 key
                        [g_knownFiles addObject:[NSString stringWithFormat:@"%@|%llu", fp, sz]];
                    }
                }
            }
        }
    }
}

+ (void)checkForNewFiles {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tmp = NSTemporaryDirectory();
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

        for (NSString *dir in @[tmp, caches]) {
            NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *name in files) {
                @autoreleasepool {
                    NSString *fp = [dir stringByAppendingPathComponent:name];
                    NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
                    if (!attr || [attr[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;

                    unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
                    NSString *key = [NSString stringWithFormat:@"%@|%llu", fp, sz];

                    // 发现新文件！（之前快照里没有）
                    if (![g_knownFiles containsObject:key] && isGoodFile(fp, sz)) {
                        NSLog(@"[喵喵] 🆕 发现新文件: %@ (%llu KB)", [fp lastPathComponent], sz/1024);
                        g_bestCandidate = fp;
                        [g_knownFiles addObject:key];
                    }
                }
            }
        }

        // 限制 set 大小
        if (g_knownFiles.count > 500) {
            // 只保留最近一半
            NSArray *all = [g_knownFiles allObjects];
            NSArray *keep = [all subarrayWithRange:NSMakeRange(0, all.count/2)];
            g_knownFiles = [NSMutableSet setWithArray:keep];
        }
    }
}

+ (NSString *)findDecryptedFile {
    // 优先：监控发现的新文件
    if (g_bestCandidate && [[NSFileManager defaultManager] fileExistsAtPath:g_bestCandidate]) {
        unsigned long long sz = [[[NSFileManager defaultManager]
            attributesOfItemAtPath:g_bestCandidate error:nil] fileSize];
        if (sz > 5000) {
            NSLog(@"[喵喵] 📤 使用监控缓存: %@", [g_bestCandidate lastPathComponent]);
            return g_bestCandidate;
        }
    }
    g_bestCandidate = nil;

    // 兜底：实时扫描 tmp/ 和 Caches/
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

    for (NSString *dir in @[tmp, caches]) {
        NSString *found = scanDir(dir);
        if (found) {
            g_bestCandidate = found;
            return found;
        }
    }

    return nil;
}

// ============================================================
//  导出 & 提示（不变）
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
