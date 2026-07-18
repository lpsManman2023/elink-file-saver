//
//  ELKFileExporter.m
//  ELKFileSaver - v13 沙箱直读版
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

static NSString *g_cachedFile = nil;
static NSMutableSet *g_beforeSnapshot = nil;

// ── 打分：文件名越像文档，分数越高 ──
static int fileScore(NSString *path, unsigned long long size) {
    if (size < 5000) return 0;
    NSString *name = [path lastPathComponent];

    // 🔥 Decript 目录的文件 → 最优先（原始文件名+解密内容）
    if ([path containsString:@"/Decript/"]) return 200;

    // 系统文件 0 分
    if ([name hasPrefix:@"CFNetwork"]) return 0;
    if ([name hasPrefix:@"NSIRD"]) return 0;
    if ([name hasPrefix:@"com.apple"]) return 0;
    if ([name hasPrefix:@"."]) return 0;
    if ([name isEqualToString:@".DS_Store"]) return 0;

    NSString *ext = [[name pathExtension] lowercaseString];

    // 垃圾扩展名 0 分
    NSArray *bad = @[@"plist",@"db",@"sqlite",@"sqlite3",@"dat",@"idx",@"log",@"json",@"tmp"];
    if (ext.length > 0) {
        for (NSString *b in bad) { if ([ext isEqualToString:b]) return 0; }
    }

    // 文档后缀 → 高分
    NSArray *docs = @[@"pdf",@"doc",@"docx",@"xls",@"xlsx",@"ppt",@"pptx",
                      @"txt",@"csv",@"rtf",@"pages",@"numbers",@"key",
                      @"dwg",@"dxf",@"dgn"];
    for (NSString *d in docs) { if ([ext isEqualToString:d]) return 100; }

    // 媒体/压缩后缀
    NSArray *media = @[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"heic",@"webp",
                       @"mp4",@"mov",@"m4v",@"mp3",@"m4a",@"wav",@"aac",
                       @"zip",@"rar",@"7z"];
    for (NSString *m in media) { if ([ext isEqualToString:m]) return 50; }

    // 大文件无后缀
    if (ext.length == 0 && size > 500000) return 10;
    return 5;
}

// ── 构建沙箱扫描根目录列表 ──
static NSArray *scanRoots(void) {
    NSMutableArray *roots = [NSMutableArray array];

    // tmp / Caches
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    if (tmp.length) [roots addObject:tmp];
    if (caches.length) [roots addObject:caches];

    // 🔥 沙箱 Documents/Profiles/*/ 下的 Decript/ 和 Files/
    NSString *profilesDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Profiles"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *profileIDs = [fm contentsOfDirectoryAtPath:profilesDir error:nil];
    for (NSString *pid in profileIDs) {
        @autoreleasepool {
            NSString *pidPath = [profilesDir stringByAppendingPathComponent:pid];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:pidPath isDirectory:&isDir] || !isDir) continue;

            for (NSString *sub in @[@"Decript", @"Files"]) {
                NSString *subPath = [pidPath stringByAppendingPathComponent:sub];
                if ([fm fileExistsAtPath:subPath]) {
                    [roots addObject:subPath];
                }
            }
        }
    }

    return roots;
}

// ── 递归扫描目录（后台线程使用） ──
static void scanRootsForBest(NSArray *roots, NSString **bestPath, int *bestScore, unsigned long long *bestSize,
                             NSMutableSet *skipSet) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        if (root.length == 0) continue;
        @try {
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
            if (!e) continue;
            NSString *rp;
            while ((rp = [e nextObject])) {
                @autoreleasepool {
                    NSString *fp = [root stringByAppendingPathComponent:rp];
                    NSDictionary *a = [fm attributesOfItemAtPath:fp error:nil];
                    if (!a || [a[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;

                    unsigned long long sz = [a[NSFileSize] unsignedLongLongValue];
                    NSString *key = [NSString stringWithFormat:@"%@|%@", fp, a[NSFileSize]];

                    // 如果给了 skipSet，跳过已存在的
                    if (skipSet && [skipSet containsObject:key]) continue;

                    int score = fileScore(fp, sz);
                    if (score == 0) continue;

                    if (score > *bestScore || (score == *bestScore && sz > *bestSize)) {
                        *bestPath = fp;
                        *bestScore = score;
                        *bestSize = sz;
                    }
                }
            }
        } @catch (...) {}
    }
}

// ============================================================
@implementation ELKFileExporter

+ (void)takeBeforeSnapshot {
    g_beforeSnapshot = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in scanRoots()) {
        @try {
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
            if (!e) continue;
            NSString *rp;
            while ((rp = [e nextObject])) {
                @autoreleasepool {
                    NSString *fp = [root stringByAppendingPathComponent:rp];
                    NSDictionary *a = [fm attributesOfItemAtPath:fp error:nil];
                    if (a && ![a[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                        [g_beforeSnapshot addObject:[NSString stringWithFormat:@"%@|%@", fp, a[NSFileSize]]];
                    }
                }
            }
        } @catch (...) {}
    }
}

+ (void)findNewFilesAfterSnapshot {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *bestPath = nil;
        int bestScore = 0;
        unsigned long long bestSize = 0;
        scanRootsForBest(scanRoots(), &bestPath, &bestScore, &bestSize, g_beforeSnapshot);

        if (bestPath) {
            NSLog(@"[喵喵] 🆕 %@ (%llu KB, score=%d)", [bestPath lastPathComponent], bestSize/1024, bestScore);
            g_cachedFile = bestPath;
        } else {
            // 没找到新增文件 → 全局搜索含 Decript 的文件（不需要新增也能导出）
            NSLog(@"[喵喵] 🔍 新增检测未命中，全局搜索 Decript...");
            NSString *fallback = nil;
            int fallbackScore = 0;
            unsigned long long fallbackSize = 0;
            scanRootsForBest(scanRoots(), &fallback, &fallbackScore, &fallbackSize, nil);
            if (fallback) {
                NSLog(@"[喵喵] 📁 全局: %@ (%llu KB, score=%d)", [fallback lastPathComponent], fallbackSize/1024, fallbackScore);
                g_cachedFile = fallback;
            }
        }
        g_beforeSnapshot = nil;
    });
}

+ (NSString *)cachedFile {
    if (g_cachedFile && [[NSFileManager defaultManager] fileExistsAtPath:g_cachedFile]) {
        return g_cachedFile;
    }
    g_cachedFile = nil;
    return nil;
}

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (!vc) return;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
        shareVC.popoverPresentationController) {
        shareVC.popoverPresentationController.sourceView = vc.view;
        shareVC.popoverPresentationController.sourceRect =
            (CGRect){{vc.view.bounds.size.width/2, vc.view.bounds.size.height/2}, {0, 0}};
        shareVC.popoverPresentationController.permittedArrowDirections = 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc presentViewController:shareVC animated:YES completion:nil];
    });
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
