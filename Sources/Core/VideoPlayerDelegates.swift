//
//  VideoPlayerDelagetes.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import Foundation

protocol PlayerDelagetes: NSObjectProtocol {
    
    associatedtype Element
    
    var delegates: [DelegateBridge<AnyObject>] { get set }
}

extension PlayerDelagetes {
    
    func add(delegate: Element) {
        guard !delegates.contains(where: { $0.object === delegate as AnyObject }) else {
            return
        }
        delegates.append(DelegateBridge(delegate as AnyObject))
    }
    
    func remove(delegate: Element) {
        guard let index = delegates.firstIndex(where: { $0.object === delegate as AnyObject }) else {
            return
        }
        delegates.remove(at: index)
    }
    
    func delegate(_ operat: (Element) -> Void) {
        delegates = delegates.filter({ $0.object != nil })
        for delegate in delegates {
            guard let object = delegate.object as? Element else { continue }
            operat(object)
        }
    }
}

class DelegateBridge<I: AnyObject> {
    weak var object: I?
    init(_ object: I?) {
        self.object = object
    }
}
