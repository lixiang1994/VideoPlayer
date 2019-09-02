import UIKit

protocol VideoPlayerErrorViewable: NSObjectProtocol {
    
    /// 设置代理对象
    ///
    /// - Parameter delegate: 代理
    func set(delegate: VideoPlayerErrorViewDelegate?)
}

protocol VideoPlayerErrorViewDelegate: NSObjectProtocol {
    
    /// 错误重试
    func errorRetry()
}

class VideoPlayerErrorView: UIView {
    
    private weak var delegate: VideoPlayerErrorViewDelegate?
    
    lazy var retryButton: UIButton = {
        $0.bounds = CGRect(x: 0, y: 0, width: 180, height: 60)
        $0.setTitle("播放异常, 点击重试", for: .normal)
        $0.setTitleColor(.white, for: .normal)
        $0.titleLabel?.font = .systemFont(ofSize: 18)
        $0.addTarget(self, action: #selector(retryAction), for: .touchUpInside)
        $0.layer.shadowColor = UIColor.black.cgColor
        $0.layer.shadowOffset = .zero
        $0.layer.shadowRadius = 4
        $0.layer.shadowOpacity = 0.2
        return $0
    } ( UIButton(type: .custom) )
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        setupLayout()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
        setupLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setupLayout()
    }
    
    private func setup() {
        backgroundColor = .black
        addSubview(retryButton)
    }
    
    private func setupLayout() {
        retryButton.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }
    
    @objc private func retryAction() {
        delegate?.errorRetry()
    }
}

extension VideoPlayerErrorView: VideoPlayerErrorViewable {
    
    func set(delegate: VideoPlayerErrorViewDelegate?) {
        self.delegate = delegate
    }
}
