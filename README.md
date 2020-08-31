# KVO-Automatic-destruction
面试的时候，面试官说了一下KVO如何优化，没有答上来。特地查了一下，自定义KVO，使用关联对象去管理观察者对象，重写Dealloc方法，执行dealloc方法的时候，remove观察者，并且isa指针只回父类就OK了。
