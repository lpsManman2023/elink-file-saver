//
//  entry.m
//  ELKFileSaver - 喵喵专用插件 v5.0
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵] 🚀 v5.0 已加载");
        [ELKMenuHook install];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"🐱 喵喵插件 v5.0"
                message:@"✅ 注入成功！\n\n点开任意文件预览\n右上角出现「📤导出」按钮\n点击 → 保存到文件"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"喵～" style:UIAlertActionStyleDefault handler:nil]];
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { [r presentViewController:alert animated:YES completion:nil]; break; }
            }
        });
    });
}
