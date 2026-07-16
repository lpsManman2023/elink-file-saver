//
//  ELKFileExporter.m
//  ELKFileSaver - v9 递归扫描 + 精确过滤
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

static NSMutableSet *g_knownFiles = nil;
static NSString *g_bestCandidate = nil;
static dispatch_source_t g_timer = NULL;

// ── 文件名/路径过滤 ──
static BOOL isGoodFile(NSString *path, unsigned long long size) {
    if (size < 5000) return NO;
    NSString *name = [path lastPathComponent];

    // ❌ 排除系统临时文件
    if ([name hasPrefix:@"CFNetwork"]) return NO;
    if ([name hasPrefix:@"NSIRD"]) return NO;
    if ([name hasPrefix:@"com.apple"]) return NO;
    if ([name hasSuffix:@".tmp"] && size < 200000) return NO; // 小 .tmp 忽略

    // ❌ 排除数据库/日志/配置
    NSString *ext = [[name pathExtension] lowercaseString];
    if (ext.length > 0) {
        if ([ext isEqualToString:@"plist"]) return NO;
        if ([ext isEqualToString:@"db"] || [ext isEqualToString:@"sqlite"] || [ext isEqualToString:@"sqlite3"]) return NO;
        if ([ext isEqualToString:@"dat"] || [ext isEqualToString:@"idx"] || [ext isEqualToString:@"log"]) return NO;
        if ([ext isEqualToString:@"json"]) return NO;
        if ([ext isEqualToString:@"tmp"]) return NO;
    }

    // ✅ 如果有可识别的文档后缀，一定接受
    if (ext.length > 0) {
        NSArray *goodExts = @[@"pdf", @"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx",
                              @"txt", @"csv", @"rtf", @"pages", @"numbers", @"key",
                              @"png", @"jpg", @"jpeg", @"gif", @"bmp", @"heic", @"webp",
                              @"mp4", @"mov", @"m4v", @"mp3", @"m4a", @"wav", @"aac",
                              @"zip", @"rar", @"7z", @"dwg", @"dxf", @"dgn"];
        for (NSString *good in goodExts) {
            if ([ext isEqualToString:good]) return YES;
        }
    }

    // 无后缀但大于 200KB 的也接受（可能是没有后缀的文档）
    if (ext.length == 0 && size > 200000) return YES;

    return NO;
}

// ── 递归扫描目录，找最佳文件 ──
static void scanDirRecursive(NSString *dir, NSString **bestPath, NSDate **bestDate, unsigned long long *bestSize, int depth) {
    if (depth > 5) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!files.count) return;

    for (NSString *name in files) {
        @autoreleasepool {
            NSString *fp = [dir stringByAppendingPathComponent:name];
            NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
            if (!attr) continue;

            if ([attr[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                // 递归进入子目录
                scanDirRecursive(fp, bestPath, bestDate, bestSize, depth + 1);
                continue;
            }

            unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
            if (!isGoodFile(fp, sz)) continue;

            NSDate *mod = attr[NSFileModificationDate];
            if (!*bestPath || [mod compare:*bestDate] == NSOrderedDescending) {
                *bestPath = fp;
                *bestDate = mod;
                *bestSize = sz;
            }
        }
    }
}

static NSString *scanAllDirs(void) {
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

    NSString *best = nil;
    NSDate *bestDate = nil;
    unsigned long long bestSize = 0;

    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        scanDirRecursive(dir, &best, &bestDate, &bestSize, 0);
    }

    if (best) NSLog(@"[喵喵] 📁 最佳文件: %@ (%llu KB)", [best lastPathComponent], bestSize/1024);
    return best;
}

// ============================================================
@implementation ELKFileExporter

+ (void)startFileMonitor {
    if (g_timer) return;
    g_knownFiles = [NSMutableSet set];
    [self takeSnapshot];
    g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                     dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(g_timer, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),
                              2*NSEC_PER_SEC, 0.5*NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_timer, ^{ [self checkForNewFiles]; });
    dispatch_resume(g_timer);
    NSLog(@"[喵喵] 🔍 文件监控已启动（递归扫描子目录）");
}

+ (void)takeSnapshot {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        [self snapshotDir:dir fm:fm];
    }
}

+ (void)snapshotDir:(NSString *)dir fm:(NSFileManager *)fm {
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        @autoreleasepool {
            NSString *fp = [dir stringByAppendingPathComponent:name];
            NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
            if (!attr) continue;
            if ([attr[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                [self snapshotDir:fp fm:fm];
                continue;
            }
            [g_knownFiles addObject:[NSString stringWithFormat:@"%@|%@", fp, attr[NSFileSize]]];
        }
    }
}

+ (void)checkForNewFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        [self checkDir:dir fm:fm];
    }
    if (g_knownFiles.count > 1000) {
        NSArray *all = [g_knownFiles allObjects];
        g_knownFiles = [NSMutableSet setWithArray:[all subarrayWithRange:NSMakeRange(0, all.count/2)]];
    }
}

+ (void)checkDir:(NSString *)dir fm:(NSFileManager *)fm {
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        @autoreleasepool {
            NSString *fp = [dir stringByAppendingPathComponent:name];
            NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
            if (!attr) continue;
            if ([attr[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                [self checkDir:fp fm:fm];
                continue;
            }
            unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
            NSString *key = [NSString stringWithFormat:@"%@|%@", fp, attr[NSFileSize]];
            if (![g_knownFiles containsObject:key] && isGoodFile(fp, sz)) {
                NSLog(@"[喵喵] 🆕 新文件: %@ (%llu KB)", [fp lastPathComponent], sz/1024);
                g_bestCandidate = fp;
                [g_knownFiles addObject:key];
            }
        }
    }
}

+ (NSString *)findDecryptedFile {
    // 优先用监控缓存
    if (g_bestCandidate && [[NSFileManager defaultManager] fileExistsAtPath:g_bestCandidate]) {
        unsigned long long sz = [[[NSFileManager defaultManager]
            attributesOfItemAtPath:g_bestCandidate error:nil] fileSize];
        if (sz > 5000) {
            NSLog(@"[喵喵] 📤 缓存: %@", [g_bestCandidate lastPathComponent]);
            return g_bestCandidate;
        }
    }
    g_bestCandidate = nil;

    // 兜底：递归全扫描
    NSString *found = scanAllDirs();
    if (found) g_bestCandidate = found;
    return found;
}

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
