import UIKit

class VideoPlayerSlider: UISlider {

    @IBInspectable var height: CGFloat = 2.0
    
    private let thumbBoundX: CGFloat = 10
    private let thumbBoundY: CGFloat = 20
    private var lastBounds: CGRect?
    
    override func minimumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        return bounds
    }
    
    override func maximumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        return bounds
    }
    
    /// 控制slider的宽和高，这个方法才是真正的改变slider滑道的高的
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        super.trackRect(forBounds: bounds)
        return CGRect(x: 0,
                      y: (bounds.size.height - height) / 2,
                      width: bounds.size.width,
                      height: height)
    }
    
    /// 改变滑块的触摸范围
    override func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let result = super.thumbRect(forBounds: bounds,
                                     trackRect: rect,
                                     value: value)
        lastBounds = result
        return result
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        guard let lastBounds = lastBounds else {
            return result
        }
        guard point.x >= 0, point.x <= bounds.width else {
            return result
        }
        
        if ((point.y >= -thumbBoundY) &&
            (point.y < lastBounds.height + thumbBoundY)) {
            var value: CGFloat = 0.0
            value = point.x - bounds.origin.x
            value = value / bounds.width
            
            value = value < 0 ? 0 : value
            value = value > 1 ? 1: value
            
            value = value * CGFloat(maximumValue - minimumValue) + CGFloat(minimumValue)
            setValue(Float(value), animated: true)
        }
        return result
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var result = super.point(inside: point, with: event)
        
        guard let lastBounds = lastBounds else {
            return result
        }
        
        if (!result && point.y > -10) {
            if ((point.x >= lastBounds.origin.x - thumbBoundX) &&
                (point.x <= (lastBounds.origin.x + lastBounds.size.width + thumbBoundX)) &&
                (point.y < (lastBounds.size.height + thumbBoundY))) {
                result = true
            }
            
        }
        return result
    }
}
