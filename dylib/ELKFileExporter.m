//
//  ELKFileExporter.m
//  ELKFileSaver - 喵喵插件（诊断版）
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

@implementation ELKFileExporter

+ (NSString *)findDecryptedFileInView:(UIView *)view {
    if (!view) return nil;

    NSMutableArray *all = [NSMutableArray arrayWithObject:view];
    NSUInteger i = 0;
    while (i < all.count && all.count < 500) {
        UIView *v = all[i]; i++;
        [all addObjectsFromArray:v.subviews];
    }

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
                    if ([p hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:p]) {
                        unsigned long long sz = [[[NSFileManager defaultManager]
                            attributesOfItemAtPath:p error:nil] fileSize];
                        if (sz > 100) {
                            NSLog(@"[喵喵] 🔥 解密文件: %@ (%llu bytes)", [p lastPathComponent], sz);
                            return p;
                        }
                    }
                }
            } @catch (...) {}
        }
    }
    return nil;
}

+ (void)exportFileFromMessage:(id)message {
    // 保留空实现
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

// ── 诊断分享 ──
+ (void)showDebugShareAlertWithPath:(NSString *)filePath dump:(NSString *)dump {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"🔍 诊断模式"
            message:@"未找到解密文件。\n\n已生成诊断报告，可通过以下方式发送给我：\n\n① 点下方「分享报告」→ 存储到文件\n② 把保存的文件内容发给我"
            preferredStyle:UIAlertControllerStyleAlert];

        [a addAction:[UIAlertAction actionWithTitle:@"分享报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            NSURL *url = [NSURL fileURLWithPath:filePath];
            UIActivityViewController *share = [[UIActivityViewController alloc]
                initWithActivityItems:@[url] applicationActivities:nil];
            if (share.popoverPresentationController) {
                UIViewController *top = [ELKRuntimeHelper topViewController];
                share.popoverPresentationController.sourceView = top.view;
                share.popoverPresentationController.sourceRect = (CGRect){{top.view.bounds.size.width/2, top.view.bounds.size.height/2}, {0,0}};
                share.popoverPresentationController.permittedArrowDirections = 0;
            }
            UIViewController *vc = [ELKRuntimeHelper topViewController];
            if (vc) [vc presentViewController:share animated:YES completion:nil];
        }]];

        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

        UIViewController *vc = [ELKRuntimeHelper topViewController];
        if (vc) [vc presentViewController:a animated:YES completion:nil];
    });
}

@end
