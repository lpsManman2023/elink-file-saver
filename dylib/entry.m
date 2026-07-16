//
//  entry.m
//  ELKFileSaver - Dylib 入口
//
//  __attribute__((constructor)) 会在 dylib 被加载时自动调用
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"\n"
              @"╔══════════════════════════════════════╗\n"
              @"║  ELKFileSaver v1.0 已加载            ║\n"
              @"║  长按聊天文件 → 保存到文件           ║\n"
              @"╚══════════════════════════════════════╝");
        [ELKMenuHook install];

        // ── 调试弹窗：打开 App 后弹出表示 dylib 加载成功 ──
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"ELKFileSaver"
            message:@"✅ dylib 注入成功！\n\n如果长按文件菜单没出现「保存到文件」，说明 Hook 类名需要修正。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];

        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        [root presentViewController:alert animated:YES completion:nil];
    });
}
