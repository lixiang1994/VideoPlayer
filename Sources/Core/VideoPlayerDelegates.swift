//
//  VideoPlayerDelegates.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import Foundation

public protocol VideoPlayerDelegates: NSObjectProtocol {
    
    associatedtype Element
    
    var delegates: [VideoPlayerDelegateBridge<AnyObject>] { get set }
}

extension VideoPlayerDelegates {
    
    public func add(delegate: Element) {
        guard !delegates.contains(where: { $0.object === delegate as AnyObject }) else {
            return
        }
        delegates.append(.init(delegate as AnyObject))
    }
    
    public func remove(delegate: Element) {
        guard let index = delegates.firstIndex(where: { $0.object === delegate as AnyObject }) else {
            return
        }
        delegates.remove(at: index)
    }
    
    public func delegate(_ operat: (Element) -> Void) {
        delegates = delegates.filter({ $0.object != nil })
        for delegate in delegates {
            guard let object = delegate.object as? Element else { continue }
            operat(object)
        }
    }
}

public class VideoPlayerDelegateBridge<I: AnyObject> {
    weak var object: I?
    init(_ object: I?) {
        self.object = object
    }
}
