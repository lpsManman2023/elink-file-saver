//
//  ELKFileExporter.h
//  ELKFileSaver - v19 水印精准击杀
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

+ (void)presentFileBrowser;
+ (void)presentSettings;
+ (void)shareFileAtPath:(NSString *)filePath;
+ (void)shareFilesAtPaths:(NSArray *)paths;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;
+ (void)preloadFileList;
+ (NSUInteger)cachedFileCount;

@end
