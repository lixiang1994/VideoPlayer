import Foundation

class WeakObject: NSObject {
    
    private weak var target: AnyObject?
    
    init(_ target: AnyObject) {
        self.target = target
        super.init()
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return target?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }
    
    override func method(for aSelector: Selector!) -> IMP! {
        return target?.method(for: aSelector) ?? super.method(for: aSelector)
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        return target?.isEqual(object) ?? super.isEqual(object)
    }
    
    override func isKind(of aClass: AnyClass) -> Bool {
        return target?.isKind(of: aClass) ?? super.isKind(of: aClass)
    }
    
    override var superclass: AnyClass? {
        return target?.superclass
    }
    
    override func isProxy() -> Bool {
        return target?.isProxy() ?? super.isProxy()
    }
    
    override var hash: Int {
        return target?.hash ?? super.hash
    }
    
    override var description: String {
        return target?.description ?? super.description
    }
    
    override var debugDescription: String {
        return target?.debugDescription ?? super.debugDescription
    }
    
    deinit { print("deinit:\t\(classForCoder)") }
}
