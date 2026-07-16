//
//  ELKFileExporter.m
//  ELKFileSaver - 文件导出实现
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ELKFileExporter

+ (void)exportFileFromMessage:(id)message {
    if (!message) {
        NSLog(@"[ELKFileSaver] ❌ message 为 nil");
        return;
    }

    // 尝试多种方式获取 localPath
    NSString *localPath = nil;

    // 方式1: KVC - 直接的 localPath 属性
    @try {
        localPath = [message valueForKey:@"localPath"];
    } @catch (NSException *e) {
        NSLog(@"[ELKFileSaver] KVC localPath 失败: %@", e);
    }

    // 方式2: getFileLocalPath:type: 方法
    if (!localPath || localPath.length == 0) {
        @try {
            SEL sel = NSSelectorFromString(@"getFileLocalPath:type:");
            if ([message respondsToSelector:sel]) {
                // type 参数尝试 0 (原始文件)
                NSMethodSignature *sig = [message methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:message];
                [inv setSelector:sel];
                NSInteger type = 0;
                [inv setArgument:&type atIndex:2];
                NSInteger fileType = 0;
                [inv setArgument:&fileType atIndex:3];
                [inv invoke];
                // getFileLocalPath:type: 返回的是 NSString *
                NSString *__unsafe_unretained path = nil;
                [inv getReturnValue:&path];
                localPath = path;
            }
        } @catch (NSException *e) {
            NSLog(@"[ELKFileSaver] getFileLocalPath:type: 失败: %@", e);
        }
    }

    // 方式3: 如果是 WWKMessageMedia 尝试取 url 字段中的本地路径
    if (!localPath || localPath.length == 0) {
        @try {
            localPath = [message valueForKey:@"url"];
            // url 可能是远程 URL，检查是否是本地文件
            if ([localPath hasPrefix:@"http"]) {
                localPath = nil;
            }
        } @catch (NSException *e) {
            // 忽略
        }
    }

    // 方式4: 尝试 recordLocalPath (语音消息)
    if (!localPath || localPath.length == 0) {
        @try {
            localPath = [message valueForKey:@"recordLocalPath"];
        } @catch (NSException *e) {
            // 忽略
        }
    }

    if (!localPath || localPath.length == 0) {
        // 文件还没下载
        [self showAlertWithTitle:@"文件未下载"
                         message:@"请先点开文件预览，下载完成后再试。"];
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        [self showAlertWithTitle:@"文件不存在"
                         message:[NSString stringWithFormat:@"文件可能已被清理:\n%@", localPath]];
        return;
    }

    [self exportFileAtPath:localPath];
}

+ (void)exportFileAtPath:(NSString *)filePath {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    // iOS 14+ 使用 initForExportingURLs
    UIDocumentPickerViewController *picker = nil;

    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL]];
    } else {
        // iOS 13 fallback
        picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[fileURL]
                                                               inMode:UIDocumentPickerModeExportToService];
    }

    // 可选：在导出前将文件复制到临时目录并重命名为原始文件名
    // 因为 localPath 的文件名通常是 hash，不够友好
    NSString *fileName = [self guessFileNameFromMessage];
    if (fileName) {
        // 创建临时副本
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *tmpPath = [tmpDir stringByAppendingPathComponent:fileName];
        // 如果已存在则删除
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        NSError *copyErr = nil;
        [[NSFileManager defaultManager] copyItemAtPath:filePath toPath:tmpPath error:&copyErr];
        if (!copyErr) {
            fileURL = [NSURL fileURLWithPath:tmpPath];
        }
    }

    // 重新初始化 picker（因为 fileURL 可能变了）
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL]];
    }

    UIViewController *topVC = [ELKRuntimeHelper topViewController];
    if (!topVC) {
        NSLog(@"[ELKFileSaver] ❌ 无法获取顶层 ViewController");
        return;
    }

    // 确保在主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        [topVC presentViewController:picker animated:YES completion:^{
            NSLog(@"[ELKFileSaver] ✅ 文件选择器已弹出");
        }];
    });

    // 清理临时文件（延迟 60 秒，确保导出完成）
    if (fileName) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory()
                stringByAppendingPathComponent:fileName] error:nil];
        });
    }
}

#pragma mark - Private

+ (NSString *)guessFileNameFromMessage {
    // 尝试从当前消息上下文获取文件名
    // 这是一个尽力而为的方法
    // 真正的文件名在 WWKMessageFile.name 中
    // 但由于我们在静态上下文中，这里返回 nil 使用原始文件名
    return nil;
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [ELKRuntimeHelper topViewController];
        if (!topVC) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

@end
