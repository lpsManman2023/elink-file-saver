//
//  ELKFileExporter.m
//  ELKFileSaver - v8 纯文件系统监控
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

static NSMutableSet *g_knownFiles = nil;
static NSString *g_bestCandidate = nil;
static dispatch_source_t g_timer = NULL;

// ── 文件过滤 ──
static BOOL isGoodFile(NSString *path, unsigned long long size) {
    if (size < 5000) return NO;
    NSString *ext = [[path pathExtension] lowercaseString];
    // 跳过配置文件/数据库/日志
    if ([ext isEqualToString:@"plist"]) return NO;
    if ([ext isEqualToString:@"db"] || [ext isEqualToString:@"sqlite"] || [ext isEqualToString:@"sqlite3"]) return NO;
    if ([ext isEqualToString:@"dat"] || [ext isEqualToString:@"idx"] || [ext isEqualToString:@"log"]) return NO;
    if ([ext isEqualToString:@"json"]) return NO;
    // 无后缀且小于50KB跳过
    if (ext.length == 0 && size < 50000) return NO;
    return YES;
}

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
            if (!isGoodFile(fp, sz)) continue;
            NSDate *mod = attr[NSFileModificationDate];
            if (!best || [mod compare:bestDate] == NSOrderedDescending) {
                best = fp; bestDate = mod; bestSize = sz;
            }
        }
    }
    if (best) NSLog(@"[喵喵] 📁 扫描: %@ (%llu KB)", [best lastPathComponent], bestSize/1024);
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
    dispatch_source_set_timer(g_timer,
                              dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),
                              2*NSEC_PER_SEC, 0.5*NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_timer, ^{ [self checkForNewFiles]; });
    dispatch_resume(g_timer);
    NSLog(@"[喵喵] 🔍 文件监控已启动");
}

+ (void)takeSnapshot {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            NSString *fp = [dir stringByAppendingPathComponent:name];
            NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
            if (attr && ![attr[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                [g_knownFiles addObject:[NSString stringWithFormat:@"%@|%@", fp, attr[NSFileSize]]];
            }
        }
    }
}

+ (void)checkForNewFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            @autoreleasepool {
                NSString *fp = [dir stringByAppendingPathComponent:name];
                NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
                if (!attr || [attr[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
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
    if (g_knownFiles.count > 500) {
        NSArray *all = [g_knownFiles allObjects];
        g_knownFiles = [NSMutableSet setWithArray:[all subarrayWithRange:NSMakeRange(0, all.count/2)]];
    }
}

+ (NSString *)findDecryptedFile {
    if (g_bestCandidate && [[NSFileManager defaultManager] fileExistsAtPath:g_bestCandidate]) {
        return g_bestCandidate;
    }
    g_bestCandidate = nil;
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    for (NSString *dir in @[tmp, caches ?: @""]) {
        if (dir.length == 0) continue;
        NSString *f = scanDir(dir);
        if (f) { g_bestCandidate = f; return f; }
    }
    return nil;
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
