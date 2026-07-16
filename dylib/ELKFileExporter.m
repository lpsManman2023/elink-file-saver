//
//  ELKFileExporter.m
//  ELKFileSaver - 文件导出实现（增强版）
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ELKFileExporter

/// 递归查找 key，深入嵌套对象
+ (NSString *)findPathInObject:(id)obj depth:(int)depth {
    if (!obj || depth > 3) return nil;

    // ── 第1轮：直接查常用的 path 属性 ──
    NSArray *pathKeys = @[
        @"localPath", @"fileLocalPath", @"filePath", @"path",
        @"localFilePath", @"recordLocalPath", @"thumbLocalPath",
        @"originLocalPath", @"downloadPath", @"cachePath",
        @"url", @"fileUrl", @"localUrl"
    ];

    for (NSString *key in pathKeys) {
        @try {
            id val = [obj valueForKey:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                NSString *str = (NSString *)val;
                if (![str hasPrefix:@"http://"] && ![str hasPrefix:@"https://"]) {
                    if ([str hasPrefix:@"/"] || [str hasPrefix:@"file://"]) {
                        if ([str hasPrefix:@"file://"]) {
                            str = [[NSURL URLWithString:str] path];
                        }
                        if ([[NSFileManager defaultManager] fileExistsAtPath:str]) {
                            NSLog(@"[喵喵插件] ✅ 找到文件: %@ = %@", key, str);
                            return str;
                        }
                    }
                }
            }
        } @catch (...) {}
    }

    // ── 第2轮：深入子对象 ──
    NSArray *childKeys = @[
        @"media", @"mediaItem", @"messageMedia", @"mediaObject",
        @"fileMessage", @"imageMessage", @"videoMessage", @"voiceMessage",
        @"content", @"messageContent", @"data", @"item",
        @"file", @"image", @"video", @"voice", @"attachment"
    ];

    for (NSString *key in childKeys) {
        @try {
            id child = [obj valueForKey:key];
            if (child && ![child isKindOfClass:[NSString class]] &&
                ![child isKindOfClass:[NSNumber class]] && ![child isEqual:obj]) {
                NSString *found = [self findPathInObject:child depth:depth + 1];
                if (found) return found;
            }
        } @catch (...) {}
    }

    // ── 第3轮：遍历所有属性 ──
    if (depth == 0) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList([obj class], &count);
        for (unsigned int i = 0; i < count && i < 50; i++) {
            const char *name = property_getName(props[i]);
            NSString *propName = [NSString stringWithUTF8String:name];

            if ([pathKeys containsObject:propName] || [childKeys containsObject:propName]) continue;

            @try {
                id val = [obj valueForKey:propName];
                if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                    NSString *str = (NSString *)val;
                    if (![str hasPrefix:@"http://"] && ![str hasPrefix:@"https://"]) {
                        if ([str hasPrefix:@"/"] || [str hasPrefix:@"file://"]) {
                            if ([str hasPrefix:@"file://"]) {
                                str = [[NSURL URLWithString:str] path];
                            }
                            if ([[NSFileManager defaultManager] fileExistsAtPath:str]) {
                                NSLog(@"[喵喵插件] ✅ 找到文件(属性遍历): %@ = %@", propName, str);
                                free(props);
                                return str;
                            }
                        }
                    }
                } else if (val && ![val isKindOfClass:[NSString class]] &&
                           ![val isKindOfClass:[NSNumber class]] && ![val isEqual:obj]) {
                    NSString *found = [self findPathInObject:val depth:depth + 1];
                    if (found) { free(props); return found; }
                }
            } @catch (...) {}
        }
        free(props);
    }

    return nil;
}

+ (void)exportFileFromMessage:(id)message {
    if (!message) {
        NSLog(@"[喵喵插件] ❌ message 为 nil");
        return;
    }

    NSLog(@"[喵喵插件] 🔍 搜索文件路径，消息类型: %@", NSStringFromClass([message class]));

    NSString *localPath = [self findPathInObject:message depth:0];

    if (!localPath) {
        @try {
            id preview = [message valueForKey:@"previewLocalPath"];
            if (!preview) preview = [message valueForKey:@"previewPath"];
            if (!preview) preview = [message valueForKey:@"thumbnailPath"];
            if (preview && [preview isKindOfClass:[NSString class]]) {
                localPath = preview;
            }
        } @catch (...) {}
    }

    if (!localPath) {
        NSLog(@"[喵喵插件] ❌ 未找到文件路径");
        [self showAlertWithTitle:@"未找到文件"
                         message:@"可能原因：\n1. 文件还未下载，请先点开文件查看\n2. 该消息类型暂不支持\n\n请先点开文件确认可以正常查看后再试。"];
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        [self showAlertWithTitle:@"文件不存在"
                         message:[NSString stringWithFormat:@"路径: %@\n文件可能已被清理或尚未下载完成。", [localPath lastPathComponent]]];
        return;
    }

    [self exportFileAtPath:localPath withOriginalName:nil];
}

+ (void)exportFileAtPath:(NSString *)filePath withOriginalName:(NSString *)origName {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    NSString *fileName = origName ?: [filePath lastPathComponent];

    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

    NSError *copyErr = nil;
    [[NSFileManager defaultManager] copyItemAtPath:filePath toPath:tmpPath error:&copyErr];
    NSURL *exportURL = copyErr ? fileURL : [NSURL fileURLWithPath:tmpPath];

    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[exportURL]];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[exportURL]
                                                               inMode:UIDocumentPickerModeExportToService];
    }

    UIViewController *topVC = [ELKRuntimeHelper topViewController];
    if (!topVC) {
        NSLog(@"[喵喵插件] ❌ 无法获取顶层 ViewController");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [topVC presentViewController:picker animated:YES completion:^{
            NSLog(@"[喵喵插件] ✅ 文件选择器已弹出");
        }];
    });

    if (!copyErr) {
        NSString *cleanPath = tmpPath;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            [[NSFileManager defaultManager] removeItemAtPath:cleanPath error:nil];
        });
    }
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [ELKRuntimeHelper topViewController];
        if (!topVC) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title message:message
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                                  style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

@end
