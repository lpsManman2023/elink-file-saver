//
//  ELKFileExporter.h
//  ELKFileSaver - v10 极简安全版
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 安全扫描 tmp/Caches 目录找解密文件
+ (NSString *)findDecryptedFile;

/// 弹出系统分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
