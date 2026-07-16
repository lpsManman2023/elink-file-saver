//
//  ELKFileExporter.m
//  ELKFileSaver - 喵喵插件
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

@implementation ELKFileExporter

+ (NSString *)searchFileIn:(id)obj depth:(int)depth {
    if (!obj || depth > 4) return nil;

    NSArray *pathKeys = @[@"localPath", @"fileLocalPath", @"filePath", @"path",
                          @"localFilePath", @"recordLocalPath", @"previewLocalPath",
                          @"previewPath", @"cachePath", @"downloadPath", @"url", @"localUrl"];

    NSString *best = nil;

    for (NSString *key in pathKeys) {
        @try {
            id val = [obj valueForKey:key];
            if (![val isKindOfClass:[NSString class]] || [(NSString *)val length] < 5) continue;
            NSString *s = val;
            if ([s hasPrefix:@"http"] || [s hasPrefix:@"https"]) continue;
            if ([s hasPrefix:@"file://"]) s = [[NSURL URLWithString:s] path];
            if (![s hasPrefix:@"/"]) continue;
            if (![[NSFileManager defaultManager] fileExistsAtPath:s]) continue;
            unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:s error:nil] fileSize];
            if (sz < 100) continue;
            if ([s containsString:@"/tmp/"] || [s containsString:@"/Caches/"] || [s containsString:@"/Temp/"]) {
                NSLog(@"[喵喵] 🔥 解密文件: %@ (%llu bytes)", key, sz);
                return s;
            }
            if (!best) best = s;
        } @catch (...) {}
    }

    NSArray *childKeys = @[@"media", @"mediaItem", @"messageMedia",
                           @"fileMessage", @"imageMessage", @"videoMessage",
                           @"voiceMessage", @"content", @"data", @"attachment"];

    for (NSString *key in childKeys) {
        @try {
            id child = [obj valueForKey:key];
            if (child && ![child isKindOfClass:[NSString class]] && ![child isKindOfClass:[NSNumber class]] && child != obj) {
                NSString *f = [self searchFileIn:child depth:depth+1];
                if (f) return f;
            }
        } @catch (...) {}
    }

    if (depth <= 1) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList([obj class], &count);
        for (unsigned int i = 0; i < count && i < 60; i++) {
            const char *n = property_getName(props[i]);
            NSString *pn = [NSString stringWithUTF8String:n];
            if ([pathKeys containsObject:pn] || [childKeys containsObject:pn]) continue;
            @try {
                id val = [obj valueForKey:pn];
                if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                    NSString *s = val;
                    if ([s hasPrefix:@"file://"]) s = [[NSURL URLWithString:s] path];
                    if ([s hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:s]) {
                        unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:s error:nil] fileSize];
                        if (sz > 100) {
                            if ([s containsString:@"/tmp/"] || [s containsString:@"/Caches/"]) { free(props); return s; }
                            if (!best) best = s;
                        }
                    }
                } else if (val && ![val isKindOfClass:[NSString class]] && ![val isKindOfClass:[NSNumber class]] && val != obj) {
                    NSString *f = [self searchFileIn:val depth:depth+1];
                    if (f) { free(props); return f; }
                }
            } @catch (...) {}
        }
        free(props);
    }

    return best;
}

+ (void)exportFileFromMessage:(id)message {
    if (!message) return;

    NSLog(@"[喵喵] 🔍 搜索: %@", NSStringFromClass([message class]));

    NSString *path = [self searchFileIn:message depth:0];

    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        NSLog(@"[喵喵] 📤 导出: %@ (%llu bytes)", [path lastPathComponent], sz);

        NSString *name = [path lastPathComponent];
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        NSError *err = nil;
        [[NSFileManager defaultManager] copyItemAtPath:path toPath:tmp error:&err];
        NSURL *url = err ? [NSURL fileURLWithPath:path] : [NSURL fileURLWithPath:tmp];

        UIDocumentPickerViewController *picker;
        if (@available(iOS 14.0, *)) {
            picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url]];
        } else {
            picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[url] inMode:UIDocumentPickerModeExportToService];
        }

        UIViewController *vc = [ELKRuntimeHelper topViewController];
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc presentViewController:picker animated:YES completion:nil];
        });
    } else {
        [self showAlertWithTitle:@"文件需先解密"
                         message:@"① 点一下文件，打开预览\n② 返回聊天\n③ 再次长按 → 💾 保存到文件"];
    }
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [ELKRuntimeHelper topViewController];
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

@end
