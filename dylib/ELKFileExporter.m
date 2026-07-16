//
//  ELKFileExporter.m
//  ELKFileSaver - 拦截文件预览获取解密文件
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuickLook/QuickLook.h>
#import <objc/runtime.h>

// ── 缓存：最近一次预览的解密文件 ──
static NSString *g_lastDecryptedFilePath = nil;
static NSDate   *g_lastDecryptedTime   = nil;

// ============================================================
//  Hook QLPreviewController —— 拦截文件预览
// ============================================================
static id (*orig_QL_initWithPreviewItems)(id, SEL, NSArray *);
static id hook_QL_initWithPreviewItems(id self, SEL _cmd, NSArray *items) {
    @try {
        if (items.count > 0) {
            id item = items.firstObject;
            NSURL *url = nil;
            if ([item respondsToSelector:@selector(previewItemURL)]) {
                url = [item performSelector:@selector(previewItemURL)];
            }
            if (url && [url isFileURL]) {
                NSString *path = [url path];
                if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    // 复制到我们的临时目录，防止 eLink 清理
                    NSString *fileName = [path lastPathComponent];
                    NSString *ourCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [NSString stringWithFormat:@"meow_%@", fileName]];
                    [[NSFileManager defaultManager] removeItemAtPath:ourCopy error:nil];
                    NSError *err = nil;
                    [[NSFileManager defaultManager] copyItemAtPath:path toPath:ourCopy error:&err];
                    if (!err) {
                        g_lastDecryptedFilePath = ourCopy;
                        g_lastDecryptedTime = [NSDate date];
                        NSLog(@"[喵喵插件] 🔥 拦截到解密文件: %@ → %@ (%llu bytes)",
                              fileName, ourCopy,
                              [[[NSFileManager defaultManager] attributesOfItemAtPath:ourCopy error:nil] fileSize]);
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ⚠️ QLPreviewController hook 异常: %@", e);
    }
    return orig_QL_initWithPreviewItems(self, _cmd, items);
}

// Hook QLPreviewController.initWithNibName (另一个入口)
static id (*orig_QL_initWithNib)(id, SEL, NSString *, NSBundle *);
static id hook_QL_initWithNib(id self, SEL _cmd, NSString *nib, NSBundle *bundle) {
    return orig_QL_initWithNib(self, _cmd, nib, bundle);
}

// ============================================================
//  Hook UIDocumentInteractionController —— 另一个预览入口
// ============================================================
static id (*orig_DIC_initWithURL)(id, SEL, NSURL *);
static id hook_DIC_initWithURL(id self, SEL _cmd, NSURL *url) {
    @try {
        if (url && [url isFileURL]) {
            NSString *path = [url path];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSString *fileName = [path lastPathComponent];
                NSString *ourCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                     [NSString stringWithFormat:@"meow_dic_%@", fileName]];
                [[NSFileManager defaultManager] removeItemAtPath:ourCopy error:nil];
                NSError *err = nil;
                [[NSFileManager defaultManager] copyItemAtPath:path toPath:ourCopy error:&err];
                if (!err) {
                    g_lastDecryptedFilePath = ourCopy;
                    g_lastDecryptedTime = [NSDate date];
                    NSLog(@"[喵喵插件] 🔥 拦截到解密文件(DIC): %@ → %@ (%llu bytes)",
                          fileName, ourCopy,
                          [[[NSFileManager defaultManager] attributesOfItemAtPath:ourCopy error:nil] fileSize]);
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ⚠️ UIDocumentInteractionController hook 异常: %@", e);
    }
    return orig_DIC_initWithURL(self, _cmd, url);
}

// ============================================================
@implementation ELKFileExporter

+ (void)installPreviewHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[喵喵插件] 🔧 安装文件预览拦截 Hook...");

        // Hook QLPreviewController
        Class ql = NSClassFromString(@"QLPreviewController");
        if (ql) {
            // 方法1: initWithPreviewItems:
            SEL sel1 = NSSelectorFromString(@"initWithPreviewItems:");
            Method m1 = class_getInstanceMethod(ql, sel1);
            if (m1) {
                orig_QL_initWithPreviewItems = (id(*)(id, SEL, NSArray *))method_getImplementation(m1);
                method_setImplementation(m1, (IMP)hook_QL_initWithPreviewItems);
                NSLog(@"[喵喵插件] ✅ QLPreviewController initWithPreviewItems: 已 Hook");
            }

            // 方法2: initWithNibName:bundle: (QLPreviewController 会调这个链)
            SEL sel2 = @selector(initWithNibName:bundle:);
            Method m2 = class_getInstanceMethod(ql, sel2);
            if (m2) {
                orig_QL_initWithNib = (id(*)(id, SEL, NSString *, NSBundle *))method_getImplementation(m2);
                method_setImplementation(m2, (IMP)hook_QL_initWithNib);
                NSLog(@"[喵喵插件] ✅ QLPreviewController initWithNibName:bundle: 已 Hook");
            }
        } else {
            NSLog(@"[喵喵插件] ⚠️ QLPreviewController 类不存在");
        }

        // Hook UIDocumentInteractionController
        Class dic = NSClassFromString(@"UIDocumentInteractionController");
        if (dic) {
            SEL sel3 = NSSelectorFromString(@"initWithURL:");
            Method m3 = class_getInstanceMethod(dic, sel3);
            if (m3) {
                orig_DIC_initWithURL = (id(*)(id, SEL, NSURL *))method_getImplementation(m3);
                method_setImplementation(m3, (IMP)hook_DIC_initWithURL);
                NSLog(@"[喵喵插件] ✅ UIDocumentInteractionController initWithURL: 已 Hook");
            }
        }
    });
}

+ (void)exportFileFromMessage:(id)message {
    if (!message) {
        NSLog(@"[喵喵插件] ❌ message 为 nil");
        return;
    }

    NSLog(@"[喵喵插件] 🔍 查找文件...");

    // ── 优先：用预览拦截到的解密文件（5分钟内有效） ──
    if (g_lastDecryptedFilePath &&
        g_lastDecryptedTime &&
        [[NSFileManager defaultManager] fileExistsAtPath:g_lastDecryptedFilePath] &&
        [[NSDate date] timeIntervalSinceDate:g_lastDecryptedTime] < 300) {

        unsigned long long size = [[[NSFileManager defaultManager]
            attributesOfItemAtPath:g_lastDecryptedFilePath error:nil] fileSize];

        if (size > 100) { // 文件大于 100 字节才算有效
            NSLog(@"[喵喵插件] ✅ 使用缓存的解密文件 (%llu bytes)", size);
            [self exportFileAtPath:g_lastDecryptedFilePath withOriginalName:nil];
            return;
        }
    }

    // ── 兜底：KVC 搜索 ──
    NSString *localPath = [self findPathInObject:message depth:0];

    if (localPath) {
        [self exportFileAtPath:localPath withOriginalName:nil];
        return;
    }

    NSLog(@"[喵喵插件] ❌ 未找到文件");
    [self showAlertWithTitle:@"请先查看文件"
                     message:@"① 点一下文件消息，打开预览\n② 返回聊天\n③ 长按文件 → 保存到文件"];
}

// ── 递归搜索（保留作为兜底） ──
+ (NSString *)findPathInObject:(id)obj depth:(int)depth {
    if (!obj || depth > 3) return nil;

    NSArray *pathKeys = @[
        @"localPath", @"fileLocalPath", @"filePath", @"path",
        @"localFilePath", @"recordLocalPath",
        @"previewLocalPath", @"previewPath",
        @"url", @"fileUrl", @"localUrl"
    ];

    NSString *best = nil;

    for (NSString *key in pathKeys) {
        @try {
            id val = [obj valueForKey:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 5) {
                NSString *str = (NSString *)val;
                if ([str hasPrefix:@"file://"]) str = [[NSURL URLWithString:str] path];
                if ([str hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:str]) {
                    if ([str containsString:@"/tmp/"] || [str containsString:@"/Caches/"] || [str containsString:@"/Temp/"]) {
                        return str;
                    }
                    if (!best) best = str;
                }
            }
        } @catch (...) {}
    }

    NSArray *childKeys = @[@"media", @"mediaItem", @"messageMedia",
                           @"fileMessage", @"imageMessage", @"videoMessage", @"content", @"data", @"attachment"];

    for (NSString *key in childKeys) {
        @try {
            id child = [obj valueForKey:key];
            if (child && ![child isKindOfClass:[NSString class]] && ![child isKindOfClass:[NSNumber class]] && ![child isEqual:obj]) {
                NSString *found = [self findPathInObject:child depth:depth + 1];
                if (found) return found;
            }
        } @catch (...) {}
    }

    return best;
}

+ (void)exportFileAtPath:(NSString *)filePath withOriginalName:(NSString *)origName {
    NSString *fileName = origName ?: [filePath lastPathComponent];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

    NSError *copyErr = nil;
    [[NSFileManager defaultManager] copyItemAtPath:filePath toPath:tmpPath error:&copyErr];
    NSURL *exportURL = copyErr ? [NSURL fileURLWithPath:filePath] : [NSURL fileURLWithPath:tmpPath];

    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[exportURL]];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[exportURL]
                                                               inMode:UIDocumentPickerModeExportToService];
    }

    UIViewController *topVC = [ELKRuntimeHelper topViewController];
    if (!topVC) return;

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
