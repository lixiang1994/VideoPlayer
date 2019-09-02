import UIKit

protocol VideoPlayerFinishViewable: NSObjectProtocol {
    
    /// 设置代理对象
    ///
    /// - Parameter delegate: 代理
    func set(delegate: VideoPlayerFinishViewDelegate?)
}

protocol VideoPlayerFinishViewDelegate: NSObjectProtocol {
    
    /// 完成重试
    func finishReplay()
}

class VideoPlayerFinishView: UIView {

    private weak var delegate: VideoPlayerFinishViewDelegate?

    lazy var replayButton: UIButton = {
        $0.bounds = CGRect(x: 0, y: 0, width: 180, height: 60)
        $0.setTitle("播放完成, 点击重播", for: .normal)
        $0.setTitleColor(.white, for: .normal)
        $0.titleLabel?.font = .systemFont(ofSize: 18)
        $0.addTarget(self, action: #selector(replayAction), for: .touchUpInside)
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
        addSubview(replayButton)
    }
    
    private func setupLayout() {
        replayButton.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }
    
    @objc private func replayAction() {
        delegate?.finishReplay()
    }
}

extension VideoPlayerFinishView: VideoPlayerFinishViewable {
    
    func set(delegate: VideoPlayerFinishViewDelegate?) {
        self.delegate = delegate
    }
}
