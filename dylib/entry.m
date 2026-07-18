//
//  entry.m
//  ELKFileSaver - 喵喵插件 v17 全功能版
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import <UIKit/UIKit.h>

// ── 随机温馨提示（20条） ──
static NSString *randomTip(void) {
    NSArray *tips = @[
        @"🐱 今天也要开心搬砖哦～",
        @"☕ 咖啡续命中... 文件导出就靠我了！",
        @"📎 回形针不是文具，是生活态度",
        @"💼 打工人，打工魂，导出文件不求人",
        @"📂 文件虽多，我帮你理清",
        @"🔍 找文件？搜一下，秒定位",
        @"🎯 精准打击，一个文件都不放过",
        @"🦸 今天也是拯救文件的一天",
        @"☁️ 云盘要钱，我免费",
        @"💾 你的文件小管家已上线",
        @"📋 合同、图纸、扫描件，统统拿下",
        @"🏗️ 基建人专属文件助手",
        @"📐 CAD图纸导出无压力",
        @"📊 报表、清单、合同一键导出",
        @"🔐 加密文件？eLink解完我帮你拿",
        @"🎒 上班摸鱼？不如来导个文件",
        @"🛠️ 工具人已就位，请指示",
        @"📤 点右上角，文件就到你手里",
        @"🏃 跑得快，导得快，文件到手不等待",
        @"🐾 喵～需要什么文件？自己搜！",
    ];
    return tips[arc4random_uniform((uint32_t)tips.count)];
}

// ── 时间段问候 ──
static NSString *timeGreeting(void) {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
    NSInteger h = c.hour;
    if (h >= 6  && h < 12) return @"早上好喵～ ☀️";
    if (h >= 12 && h < 18) return @"下午好喵～ 🌤️";
    if (h >= 18 && h < 22) return @"晚上好喵～ 🌙";
    return @"夜深了喵～ 🌙";
}

__attribute__((constructor))
static void ELKFileSaverInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[喵喵] 🚀 v17 全功能版");
        [ELKMenuHook install];

        // 后台预加载文件列表（更新按钮角标）
        [ELKFileExporter preloadFileList];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // ── 一天内静音检测 ──
            NSTimeInterval last = [[NSUserDefaults standardUserDefaults] doubleForKey:@"meow_last_dismiss"];
            if ([[NSDate date] timeIntervalSince1970] - last < 86400) return;

            UIAlertController *a = [UIAlertController
                alertControllerWithTitle:@"🐱 喵喵插件 v17"
                message:[NSString stringWithFormat:@"%@\n\n━━━━━━━━━━━━━━━━\n%@\n━━━━━━━━━━━━━━━━\n✅ 注入成功！\n右上角「📤 导出」→ 浏览文件", timeGreeting(), randomTip()]
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"喵～" style:UIAlertActionStyleDefault handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:@"一天内别说了 🐱" style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
                [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"meow_last_dismiss"];
            }]];

            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { [r presentViewController:a animated:YES completion:nil]; break; }
            }
        });
    });
}
