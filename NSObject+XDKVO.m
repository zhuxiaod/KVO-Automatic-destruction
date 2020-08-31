









#import "NSObject+XDKVO.h"
#import <objc/message.h>

static NSString *const kXDKVOPrefix = @"XZKVONotifying_";
static NSString *const kXDKVOAssiociateKey = @"kXZKVO_AssiociateKey";

@implementation NSObject (XZKVO)

//添加KVO
- (void)xd_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(nullable void *)context handle:(XDKVOBlock)handle
{
    // 1: 验证setter
    [self judgeSetterMethodFromKeyPath:keyPath];
    // 2: 动态生成子类
    Class newClass = [self createChildClassWithKeyPath:keyPath];
    // 3: isa 指向 isa_swizzling
    object_setClass(self, newClass);
    //4.保存观察者
    XDKVOInfo *info = [[XDKVOInfo alloc]initWitObserver:observer forKeyPath:keyPath options:options andBlock:handle];
    //收集观察者
    NSMutableArray *observerArray = objc_getAssociatedObject(self,(__bridge const void * _Nonnull)(kXDKVOAssiociateKey));
    if (!observerArray) {//如果关联对象里面有东西
        observerArray = [NSMutableArray array];
    }
    [observerArray addObject:info];
    //这里就不保存观察者了，直接将Array进行保存就行了
    objc_setAssociatedObject(self, (__bridge const void * _Nonnull)(kXDKVOAssiociateKey), observerArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);//保存在关联对象中
}

#pragma mark - 验证是否存在setter方法
- (void)judgeSetterMethodFromKeyPath:(NSString *)keyPath{
    //获取当前类
    Class superClass    = object_getClass(self);
    //获取Key 拼接成Set SEL
    SEL setterSeletor   = NSSelectorFromString(setterForGetter(keyPath));
    //从父类获取该实例方法
    Method setterMethod = class_getInstanceMethod(superClass, setterSeletor);
    //如果没有这个方法
    if (!setterMethod) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"哥们没有当前 %@ 的setter",keyPath] userInfo:nil];
    }
}

#pragma mark -
- (Class)createChildClassWithKeyPath:(NSString *)keyPath{
    // 2.1 判断是否有了
    NSString *oldClassName = NSStringFromClass([self class]);
    NSString *newClassName = [NSString stringWithFormat:@"%@%@",kXDKVOPrefix,oldClassName];// XZKVONotifying_XZPerson
    Class newClass = NSClassFromString(newClassName);
    if (newClass) {//给新类添加setter方法
        // 2.3.2 添加setter方法 setNickname
        SEL setterSEL = NSSelectorFromString(setterForGetter(keyPath));
        Method setterMethod = class_getClassMethod([self class], setterSEL);
        const char *setterType = method_getTypeEncoding(setterMethod);
        class_addMethod(newClass, setterSEL, (IMP)xd_setter, setterType);
        return newClass;
    }
    /**
     * 如果内存不存在,创建生成
     * 参数一: 父类
     * 参数二: 新类的名字
     * 参数三: 新类的开辟的额外空间
     */

    // 2.1 申请类
    newClass = objc_allocateClassPair([self class], newClassName.UTF8String, 0);
    // 2.2 注册类
    objc_registerClassPair(newClass);
    // 2.3.1 添加class方法
    SEL classSEL = NSSelectorFromString(@"class");
    Method classMethod = class_getClassMethod([self class], @selector(class));
    const char *classType = method_getTypeEncoding(classMethod);
    class_addMethod(newClass, classSEL, (IMP)xd_class, classType);
    // 2.3.1 添加dealloc方法
    SEL delalocSEL = NSSelectorFromString(@"dealloc");
    Method deallocMethod = class_getClassMethod([self class], delalocSEL);
    const char *deallocType = method_getTypeEncoding(deallocMethod);
    class_addMethod(newClass, delalocSEL, (IMP)xd_dealloc, deallocType);

    // 2.3.2 添加setter方法 setNickname
    SEL setterSEL = NSSelectorFromString(setterForGetter(keyPath));
    Method setterMethod = class_getClassMethod([self class], setterSEL);
    const char *setterType = method_getTypeEncoding(setterMethod);
    class_addMethod(newClass, setterSEL, (IMP)xd_setter, setterType);
    
    return newClass;
}

static void xd_dealloc(id self,SEL _cmd){//销毁所有定时器
    NSLog(@"xd_dealloc来了");
    NSMutableArray *observerArr = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kXDKVOAssiociateKey));
    [observerArr removeAllObjects];
    objc_setAssociatedObject(self, (__bridge const void * _Nonnull)(kXDKVOAssiociateKey), observerArr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    //将指针指回来
    if (observerArr.count <= 0) {
        Class superclass = [self class];
        object_setClass(self, superclass);
    }
}

static void xd_setter(id self,SEL _cmd,id newValue){//添加的setter方法
    NSLog(@"来了:%@",newValue);
    //获取当前监听的key
    NSString *keyPath = getterForSetter(NSStringFromSelector(_cmd));
    //先获取当前的旧值
    NSString *oldValue = [self valueForKey:keyPath];

    //4：消息转发： 转发给父类
    //改变父类的值---可以强制类型转换
    void (*xd_msgSendSuper)(void *,SEL , id) = (void *)objc_msgSendSuper;
    /**
     newvalue 这里修改了子类的的值，父类值是没有改变的
     使用 objc_msgSendSuper给父类的setter方法发送消息修改值
    */
    // 回调给外界
    
    struct objc_super superStruct = {
        .receiver       = self,
        .super_class    = [self class]
    };
    //4.1转发给父类
    xd_msgSendSuper(&superStruct,_cmd,newValue);

    //4.2 获取观察者观察者
    NSMutableArray *observerArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kXDKVOAssiociateKey));
    for (XDKVOInfo *info in observerArray) {
        if ([info.keyPath isEqualToString:keyPath]) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                
                //4.3消息发送观察者
//                NSMutableDictionary *change = [NSMutableDictionary dictionary];
//                //对新旧值进行处理
//                if (info.options & XZKeyValueObservingOptionNew) {
//                    [change setObject:newValue forKey:NSKeyValueChangeNewKey];
//                }
//                if (info.options & XZKeyValueObservingOptionOld) {
//                    [change setObject:@"" forKey:NSKeyValueChangeOldKey];
//                    if (oldValue) {
//                        [change setObject:oldValue forKey:NSKeyValueChangeOldKey];
//                    }
//                }
                //交换值
                info.kvoBlock(info.observer, info.keyPath, oldValue, newValue);
//                SEL observerSel = @selector(observeValueForKeyPath:ofObject:change:context:);
//                SEL xzobserverSel = @selector(xd_observeValueForKeyPath:ofObject:change:context:);
//
//                objc_msgSend(info.observer,xzobserverSel,keyPath,self,change,NULL);
            });
            
        }
    }
}

Class xd_class(id self,SEL _cmd){
    //这里返回父类的isa
    return class_getSuperclass(object_getClass(self));
}

#pragma mark - 从get方法获取set方法的名称 key ===>>> setKey:
static NSString *setterForGetter(NSString *getter){
    
    if (getter.length <= 0) { return nil;}
    
    NSString *firstString = [[getter substringToIndex:1] uppercaseString];//大写
    NSString *leaveString = [getter substringFromIndex:1];
    
    return [NSString stringWithFormat:@"set%@%@:",firstString,leaveString] ;
}

#pragma mark - 从set方法获取getter方法的名称 set<Key>:===> key
static NSString *getterForSetter(NSString *setter){
    
    if (setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) { return nil;}
    
    NSRange range = NSMakeRange(3, setter.length-4);
    NSString *getter = [setter substringWithRange:range];
    NSString *firstString = [[getter substringToIndex:1] lowercaseString];
    return  [getter stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:firstString];
}

@end
