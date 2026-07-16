//
//  ELKFileExporter.m
//  ELKFileSaver - v12 快照+新增检测版
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

static NSString *g_cachedFile = nil;
static NSMutableSet *g_beforeSnapshot = nil;

// ── 文件过滤：优先文档类型，按优先级打分 ──
static int fileScore(NSString *path, unsigned long long size) {
    if (size < 5000) return 0;
    NSString *name = [path lastPathComponent];

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

    // 文档后缀 → 高分 (100)
    NSArray *docs = @[@"pdf",@"doc",@"docx",@"xls",@"xlsx",@"ppt",@"pptx",
                      @"txt",@"csv",@"rtf",@"pages",@"numbers",@"key",
                      @"dwg",@"dxf",@"dgn"];
    for (NSString *d in docs) { if ([ext isEqualToString:d]) return 100; }

    // 媒体后缀 → 中分 (50)
    NSArray *media = @[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"heic",@"webp",
                       @"mp4",@"mov",@"m4v",@"mp3",@"m4a",@"wav",@"aac",
                       @"zip",@"rar",@"7z"];
    for (NSString *m in media) { if ([ext isEqualToString:m]) return 50; }

    // 无后缀大文件 → 低分（但至少不会选 CFNetwork 之类）
    if (ext.length == 0 && size > 500000) return 10;

    return 5;
}

// ── 拍摄快照（在预览打开前调用） ──
+ (void)takeBeforeSnapshot {
    g_beforeSnapshot = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

    for (NSString *root in @[tmp, caches ?: @""]) {
        if (root.length == 0) continue;
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

// ── 对比快照找新增文件（在预览打开后调用） ──
+ (void)findNewFilesAfterSnapshot {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tmp = NSTemporaryDirectory();
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

        NSString *bestPath = nil;
        int bestScore = 0;
        unsigned long long bestSize = 0;

        for (NSString *root in @[tmp, caches ?: @""]) {
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

                        // 🔥 只关注快照之后新增的文件
                        if ([g_beforeSnapshot containsObject:key]) continue;

                        int score = fileScore(fp, sz);
                        if (score == 0) continue;

                        if (score > bestScore || (score == bestScore && sz > bestSize)) {
                            bestPath = fp;
                            bestScore = score;
                            bestSize = sz;
                        }
                    }
                }
            } @catch (...) {}
        }

        if (bestPath) {
            NSLog(@"[喵喵] 🆕 新增文件: %@ (%llu KB, score=%d)", [bestPath lastPathComponent], bestSize/1024, bestScore);
            g_cachedFile = bestPath;
        } else {
            NSLog(@"[喵喵] ⚠️ 未找到新增文件");
        }

        g_beforeSnapshot = nil; // 释放内存
    });
}

+ (NSString *)cachedFile {
    if (g_cachedFile && [[NSFileManager defaultManager] fileExistsAtPath:g_cachedFile]) {
        return g_cachedFile;
    }
    g_cachedFile = nil;
    return nil;
}

// ============================================================
@implementation ELKFileExporter

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
