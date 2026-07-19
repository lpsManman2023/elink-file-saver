//
//  ELKMenuHook.h
//  ELKFileSaver - v19
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKMenuHook : NSObject

+ (void)install;
+ (void)hideWatermarksIfEnabled;
+ (void)showAllWatermarks;

@end
