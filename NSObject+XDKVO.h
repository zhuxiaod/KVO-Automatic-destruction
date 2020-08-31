









#import <Foundation/Foundation.h>
#import "XDKVOInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (XDKVO)
//添加观察者
- (void)xd_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(nullable void *)context handle:(XDKVOBlock)handle;

//移除观察者
- (void)xd_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;

@end

NS_ASSUME_NONNULL_END
