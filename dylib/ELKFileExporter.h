//
//  ELKFileExporter.h
//  ELKFileSaver - v14 文件浏览器
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 弹出文件浏览器（搜索+列表）
+ (void)presentFileBrowser;

/// 弹出分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
