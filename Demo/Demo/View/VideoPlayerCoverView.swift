import UIKit

protocol VideoPlayerCoverViewable: NSObjectProtocol {
    
    /// 设置代理对象
    ///
    /// - Parameter delegate: 代理
    func set(delegate: VideoPlayerCoverViewDelegate?)
}

protocol VideoPlayerCoverViewDelegate: NSObjectProtocol {
    
    /// 开始播放
    func play()
}

class VideoPlayerCoverView: UIView {
    
    private weak var delegate: VideoPlayerCoverViewDelegate?
    
    lazy var imageView: UIImageView = {
        $0.contentMode = .scaleAspectFill
        return $0
    } ( UIImageView() )
    
    lazy var playButton: UIButton = {
        $0.bounds = CGRect(x: 0, y: 0, width: 66, height: 66)
        $0.setImage(#imageLiteral(resourceName: "video_play"), for: .normal)
        $0.addTarget(self, action: #selector(playAction), for: .touchUpInside)
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
        addSubview(imageView)
        addSubview(playButton)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapAction))
        imageView.addGestureRecognizer(tap)
    }
    
    private func setupLayout() {
        imageView.frame = bounds
        playButton.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }
    
    @objc private func tapAction() {
        delegate?.play()
    }
    
    @objc private func playAction() {
        delegate?.play()
    }
}

extension VideoPlayerCoverView: VideoPlayerCoverViewable {
    
    func set(delegate: VideoPlayerCoverViewDelegate?) {
        self.delegate = delegate
    }
}
