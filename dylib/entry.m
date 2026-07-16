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
    // 等待 App 完成启动后再安装 Hook
    // 确保所有 ObjC 类都已加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"\n"
              @"╔══════════════════════════════════════╗\n"
              @"║  ELKFileSaver v1.0 已加载            ║\n"
              @"║  长按聊天文件 → 保存到文件           ║\n"
              @"╚══════════════════════════════════════╝");
        [ELKMenuHook install];
    });
}
