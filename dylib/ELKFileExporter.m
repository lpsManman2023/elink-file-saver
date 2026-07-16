//
//  ELKFileExporter.m
//  ELKFileSaver - 喵喵插件（极简稳定版）
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

@implementation ELKFileExporter

+ (NSString *)findDecryptedFileInView:(UIView *)view {
    if (!view) return nil;

    // 收集视图层级中所有视图
    NSMutableArray *all = [NSMutableArray arrayWithObject:view];
    NSUInteger i = 0;
    while (i < all.count && all.count < 500) {
        UIView *v = all[i]; i++;
        [all addObjectsFromArray:v.subviews];
    }

    // 在每个视图上查已知 key
    NSArray *keys = @[@"url", @"fileURL", @"filePath", @"localPath",
                      @"previewItemURL", @"previewLocalPath"];

    for (UIView *v in all) {
        for (NSString *key in keys) {
            @try {
                id val = [v valueForKey:key];
                NSURL *fileURL = nil;

                if ([val isKindOfClass:[NSURL class]]) {
                    fileURL = val;
                } else if ([val isKindOfClass:[NSString class]]) {
                    NSString *s = val;
                    if ([s hasPrefix:@"file://"]) fileURL = [NSURL URLWithString:s];
                    else if ([s hasPrefix:@"/"]) fileURL = [NSURL fileURLWithPath:s];
                }

                if (fileURL && [fileURL isFileURL]) {
                    NSString *p = [fileURL path];
                    if ([p hasPrefix:@"/"] && ( [p containsString:@"/tmp/"] ||
                                                [p containsString:@"/Caches/"] ||
                                                [p containsString:@"/Temp/"])) {
                        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                            unsigned long long sz = [[[NSFileManager defaultManager]
                                attributesOfItemAtPath:p error:nil] fileSize];
                            if (sz > 100) {
                                NSLog(@"[喵喵] 🔥 解密文件: %@ (%llu bytes)", [p lastPathComponent], sz);
                                return p;
                            }
                        }
                    }
                }
            } @catch (...) {}
        }
    }

    return nil;
}

+ (void)exportFileFromMessage:(id)message {
    // 不再使用，保留空实现
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
