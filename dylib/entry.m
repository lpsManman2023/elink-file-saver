//
//  entry.m
//  ELKFileSaver - 喵喵插件 v6.0
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵] 🚀 v6.0");
        [ELKMenuHook install];

        // 弹窗确认
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIAlertController *a = [UIAlertController
                alertControllerWithTitle:@"🐱 喵喵插件 v6.0"
                message:@"✅ 注入成功！\n\n点开文件预览\n→ 右上角「📤导出」\n→ 保存到文件"
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"喵～" style:UIAlertActionStyleDefault handler:nil]];

            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { [r presentViewController:a animated:YES completion:nil]; break; }
            }
        });
    });
}
