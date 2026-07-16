//
//  ELKFileExporter.h
//  ELKFileSaver - v12 快照+新增检测
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 在预览页打开前拍文件快照
+ (void)takeBeforeSnapshot;

/// 在预览页打开后找新增文件（后台线程）
+ (void)findNewFilesAfterSnapshot;

/// 获取缓存的最佳文件路径
+ (NSString *)cachedFile;

/// 弹出分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
