//
//  entry.m
//  ELKFileSaver - Dylib 入口（喵喵专用插件版）
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

static UIViewController *getTopVC(void) {
    @try {
        UIWindow *keyWin = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { keyWin = w; break; }
                }
            }
        }
        if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = keyWin.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        return root;
    } @catch (...) { return nil; }
}

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵插件] 🚀 dylib 已加载");
        [ELKMenuHook install];

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"🐱 喵喵专用插件"
            message:@"✅ 插件注入成功！\n\n长按聊天中的文件/图片/视频\n菜单会出现「保存到文件」\n点击即可导出到手机本地文件夹"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"喵～知道了" style:UIAlertActionStyleDefault handler:nil]];

        UIViewController *vc = getTopVC();
        if (vc) {
            [vc presentViewController:alert animated:YES completion:nil];
        } else {
            // 兜底：延迟再试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *vc2 = getTopVC();
                if (vc2) [vc2 presentViewController:alert animated:YES completion:nil];
            });
        }
    });
}
