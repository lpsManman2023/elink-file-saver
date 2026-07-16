//
//  ELKFileExporter.m
//  ELKFileSaver - v11 异步扫描版
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

static BOOL isGoodFile(NSString *path, unsigned long long size) {
    if (size < 5000) return NO;
    NSString *name = [path lastPathComponent];
    if ([name hasPrefix:@"CFNetwork"]) return NO;
    if ([name hasPrefix:@"NSIRD"]) return NO;
    if ([name hasPrefix:@"com.apple"]) return NO;
    if ([name hasPrefix:@"."]) return NO;
    if ([name hasSuffix:@".tmp"] && size < 200000) return NO;
    if ([name isEqualToString:@".DS_Store"]) return NO;

    NSString *ext = [[name pathExtension] lowercaseString];
    if (ext.length > 0) {
        NSArray *bad = @[@"plist",@"db",@"sqlite",@"sqlite3",@"dat",@"idx",@"log",@"json",@"tmp"];
        for (NSString *b in bad) { if ([ext isEqualToString:b]) return NO; }
        NSArray *good = @[@"pdf",@"doc",@"docx",@"xls",@"xlsx",@"ppt",@"pptx",
                          @"txt",@"csv",@"rtf",@"pages",@"numbers",@"key",
                          @"png",@"jpg",@"jpeg",@"gif",@"bmp",@"heic",@"webp",
                          @"mp4",@"mov",@"m4v",@"mp3",@"m4a",@"wav",@"aac",
                          @"zip",@"rar",@"7z",@"dwg",@"dxf",@"dgn"];
        for (NSString *g in good) { if ([ext isEqualToString:g]) return YES; }
    }
    if (ext.length == 0 && size > 200000) return YES;
    return NO;
}

// ⚠️ 只在后台线程调用！
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
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
            if (!e) continue;
            NSString *rp;
            while ((rp = [e nextObject])) {
                @autoreleasepool {
                    NSString *fp = [root stringByAppendingPathComponent:rp];
                    NSDictionary *a = [fm attributesOfItemAtPath:fp error:nil];
                    if (!a || [a[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
                    unsigned long long sz = [a[NSFileSize] unsignedLongLongValue];
                    if (!isGoodFile(fp, sz)) continue;
                    NSDate *mod = a[NSFileModificationDate];
                    if (!bestPath || [mod compare:bestDate] == NSOrderedDescending) {
                        bestPath = fp; bestDate = mod; bestSize = sz;
                    }
                }
            }
        } @catch (...) {}
    }
    if (bestPath) NSLog(@"[喵喵] 📁 %@ (%llu KB)", [bestPath lastPathComponent], bestSize/1024);
    return bestPath;
}

// ============================================================
@implementation ELKFileExporter

/// 异步扫描，完成回调（主线程）
+ (void)findDecryptedFileAsync:(void(^)(NSString *path))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *path = safeScan();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(path);
        });
    });
}

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (!vc) return;

    // iPhone 不需要 popover
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
