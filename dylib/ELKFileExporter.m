//
//  ELKFileExporter.m
//  ELKFileSaver - v10 极简安全版
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

// ── 文件过滤 ──
static BOOL isGoodFile(NSString *path, unsigned long long size) {
    if (size < 5000) return NO;
    NSString *name = [path lastPathComponent];

    // 排除系统文件
    if ([name hasPrefix:@"CFNetwork"]) return NO;
    if ([name hasPrefix:@"NSIRD"]) return NO;
    if ([name hasPrefix:@"com.apple"]) return NO;
    if ([name hasPrefix:@"."]) return NO;
    if ([name hasSuffix:@".tmp"] && size < 200000) return NO;
    if ([name isEqualToString:@".DS_Store"]) return NO;
    if ([name containsString:@"GeoLite2"]) return NO;

    // 排除垃圾文件类型
    NSString *ext = [[name pathExtension] lowercaseString];
    if (ext.length > 0) {
        NSArray *bad = @[@"plist", @"db", @"sqlite", @"sqlite3", @"dat", @"idx", @"log", @"json", @"tmp"];
        for (NSString *b in bad) {
            if ([ext isEqualToString:b]) return NO;
        }
    }

    // 文档后缀白名单
    if (ext.length > 0) {
        NSArray *good = @[@"pdf",@"doc",@"docx",@"xls",@"xlsx",@"ppt",@"pptx",
                          @"txt",@"csv",@"rtf",@"pages",@"numbers",@"key",
                          @"png",@"jpg",@"jpeg",@"gif",@"bmp",@"heic",@"webp",
                          @"mp4",@"mov",@"m4v",@"mp3",@"m4a",@"wav",@"aac",
                          @"zip",@"rar",@"7z",@"dwg",@"dxf",@"dgn"];
        for (NSString *g in good) {
            if ([ext isEqualToString:g]) return YES;
        }
    }

    // 大文件无后缀也接受
    if (ext.length == 0 && size > 200000) return YES;
    return NO;
}

// ── 使用 NSDirectoryEnumerator 安全扫描 ──
static NSString *safeScan(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bestPath = nil;
    NSDate *bestDate = nil;
    unsigned long long bestSize = 0;

    NSString *tmp = NSTemporaryDirectory();
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

    for (NSString *root in @[tmp, caches ?: @""]) {
        if (root.length == 0) continue;

        @try {
            NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
            if (!enumerator) continue;

            NSString *relPath;
            while ((relPath = [enumerator nextObject])) {
                @autoreleasepool {
                    NSString *fp = [root stringByAppendingPathComponent:relPath];
                    NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
                    if (!attr || [attr[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;

                    unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
                    if (!isGoodFile(fp, sz)) continue;

                    NSDate *mod = attr[NSFileModificationDate];
                    if (!bestPath || [mod compare:bestDate] == NSOrderedDescending) {
                        bestPath = fp;
                        bestDate = mod;
                        bestSize = sz;
                    }
                }
            }
        } @catch (...) {
            // 跳过无法访问的目录
        }
    }

    if (bestPath) {
        NSLog(@"[喵喵] 📁 最佳: %@ (%llu KB, %@)", [bestPath lastPathComponent], bestSize/1024, bestDate);
    }
    return bestPath;
}

// ============================================================
@implementation ELKFileExporter

+ (NSString *)findDecryptedFile {
    return safeScan();
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
