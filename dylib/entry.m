//
//  entry.m
//  ELKFileSaver - 喵喵专用插件
//
#import "ELKMenuHook.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵] 🚀 已加载");
        [ELKMenuHook install];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"🐱 喵喵专用插件 v2.0"
                message:@"✅ 注入成功！\n\n使用：\n① 先点一下文件打开预览\n② 返回后长按该文件\n③ 自动弹出保存界面"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"喵～知道了" style:UIAlertActionStyleDefault handler:nil]];
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { [r presentViewController:alert animated:YES completion:nil]; break; }
            }
        });
    });
}
