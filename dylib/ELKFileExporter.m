//
//  ELKFileExporter.m
//  ELKFileSaver - 喵喵插件
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

@implementation ELKFileExporter

+ (NSString *)findDecryptedFileInView:(UIView *)view {
    if (!view) return nil;

    NSMutableArray *allViews = [NSMutableArray arrayWithObject:view];
    NSUInteger idx = 0;
    while (idx < allViews.count) {
        UIView *v = allViews[idx];
        idx++;

        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList([v class], &count);
        for (unsigned int i = 0; i < count && i < 100; i++) {
            @try {
                id val = [v valueForKey:[NSString stringWithUTF8String:property_getName(props[i])]];
                if ([val isKindOfClass:[NSString class]]) {
                    NSString *s = val;
                    if ([s hasPrefix:@"file://"]) s = [[NSURL URLWithString:s] path];
                    if ([s hasPrefix:@"/"] && s.length > 5) {
                        if (([s containsString:@"/tmp/"] || [s containsString:@"/Caches/"] ||
                             [s containsString:@"/Temp/"]) &&
                            [[NSFileManager defaultManager] fileExistsAtPath:s]) {
                            unsigned long long sz = [[[NSFileManager defaultManager]
                                attributesOfItemAtPath:s error:nil] fileSize];
                            if (sz > 100) {
                                NSLog(@"[喵喵] 🔥 找到解密文件: %@ (%llu bytes)", [s lastPathComponent], sz);
                                free(props);
                                return s;
                            }
                        }
                    }
                }
            } @catch (...) {}
        }
        free(props);

        for (UIView *sub in v.subviews) {
            [allViews addObject:sub];
        }
    }
    return nil;
}

+ (void)exportFileFromMessage:(id)message {
    if (!message) return;

    NSString *path = nil;
    @try {
        for (NSString *key in @[@"localPath", @"fileLocalPath", @"filePath",
                                @"previewLocalPath", @"previewPath", @"cachePath",
                                @"downloadPath", @"url"]) {
            @try {
                id val = [message valueForKey:key];
                if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                    NSString *s = val;
                    if ([s hasPrefix:@"file://"]) s = [[NSURL URLWithString:s] path];
                    if ([s hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:s]) {
                        unsigned long long sz = [[[NSFileManager defaultManager]
                            attributesOfItemAtPath:s error:nil] fileSize];
                        if (sz > 100) { path = s; break; }
                    }
                }
            } @catch (...) {}
        }
    } @catch (...) {}

    if (path) {
        [self shareFileAtPath:path];
    } else {
        [self showAlertWithTitle:@"未找到文件"
                         message:@"请先点开文件预览，再试。"];
    }
}

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];

    if (shareVC.popoverPresentationController) {
        UIViewController *top = [ELKRuntimeHelper topViewController];
        CGFloat hw = top.view.bounds.size.width / 2.0;
        CGFloat hh = top.view.bounds.size.height / 2.0;
        shareVC.popoverPresentationController.sourceView = top.view;
        shareVC.popoverPresentationController.sourceRect =
            (CGRect){{hw, hh}, {0, 0}};
        shareVC.popoverPresentationController.permittedArrowDirections = 0;
    }

    UIViewController *vc = [ELKRuntimeHelper topViewController];
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
