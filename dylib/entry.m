//
//  entry.m
//  ELKFileSaver - 喵喵专用插件
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵] 🚀 已加载");
        [ELKMenuHook install];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"🐱 喵喵专用插件"
                message:@"✅ 注入成功！\n\n使用：\n① 点文件打开预览\n② 返回 → 长按文件\n③ 菜单里选「💾 保存到文件」"
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
