//
//  ELKFileExporter.h
//  ELKFileSaver - v17 全功能版
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 弹出文件浏览器
+ (void)presentFileBrowser;

/// 弹出分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 批量分享多个文件
+ (void)shareFilesAtPaths:(NSArray *)paths;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

/// 后台预加载文件列表（用于按钮角标）
+ (void)preloadFileList;

/// 缓存中的文件数量（用于按钮角标）
+ (NSUInteger)cachedFileCount;

@end
