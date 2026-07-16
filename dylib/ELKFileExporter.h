//
//  ELKFileExporter.h
//  ELKFileSaver - v8 文件系统监控
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 启动文件系统监控（每2秒扫描 tmp/Caches）
+ (void)startFileMonitor;

/// 查找预览解密文件（监控缓存 + 实时扫描）
+ (NSString *)findDecryptedFile;

/// 弹出系统分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
