//
//  ELKFileExporter.h
//  ELKFileSaver - v22
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

+ (void)presentFileBrowser;
+ (void)presentSettings;
+ (void)presentWatermarkMarker:(UIViewController *)top candidates:(NSArray *)candidates;
+ (void)shareFileAtPath:(NSString *)filePath;
+ (void)shareFilesAtPaths:(NSArray *)paths;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;
+ (void)preloadFileList;
+ (NSUInteger)cachedFileCount;

@end
