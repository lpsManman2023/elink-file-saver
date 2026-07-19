//
//  ELKMenuHook.h
//  ELKFileSaver - v20
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKMenuHook : NSObject

+ (void)install;
+ (void)hideWatermarksIfEnabled;
+ (void)hideWatermarksByClassName:(NSString *)className;
+ (void)showAllWatermarks;

/// 扫描当前页面候选水印视图
+ (NSArray *)scanCandidateWatermarkViews;

/// 已保存的水印类名列表
+ (NSArray *)savedWatermarkClasses;

/// 添加/删除水印类名（JSON 持久化）
+ (void)addWatermarkClass:(NSString *)className;
+ (void)removeWatermarkClass:(NSString *)className;

@end
