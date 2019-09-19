import UIKit

protocol VideoPlayerControlViewable: NSObjectProtocol {
    
    /// 设置代理对象
    ///
    /// - Parameter delegate: 代理
    func set(delegate: VideoPlayerControlViewDelegate?)
    
    /// 设置状态
    ///
    /// - Parameter state: true 播放, false 暂停
    func set(state: Bool)
    
    /// 设置缓冲进度
    ///
    /// - Parameters:
    ///   - progress: 进度
    ///   - animated: 是否动画
    func set(buffer progress: Double, animated: Bool)
    
    /// 设置当前播放时长
    ///
    /// - Parameter time: 时间(秒)
    func set(current time: TimeInterval)
    
    /// 设置总播放时长
    ///
    /// - Parameter time: 时间(秒)
    func set(total time: TimeInterval)
    
    /// 加载状态
    func loadingBegin()
    func loadingEnd()
    
    /// 设置启用 (当准备完成时可以启用子控件, 未准备完成时禁用子控件)
    ///
    /// - Parameter enabled: true or false
    func set(enabled: Bool)
}

protocol VideoPlayerControlViewDelegate: NSObjectProtocol {
    
    /// 控制播放
    func controlPlay()
    /// 控制暂停
    func controlPause()
    /// 控制跳转指定时间
    func controlSeek(time: Double, completion: @escaping (()->Void))
}

class VideoPlayerControlView: UIView {
    
    private weak var delegate: VideoPlayerControlViewDelegate?
    
    lazy var loadingView: UIActivityIndicatorView = {
        $0.style = .white
        $0.hidesWhenStopped = true
        return $0
    }( UIActivityIndicatorView() )
    
    lazy var stateButton: UIButton = {
        $0.isUserInteractionEnabled = false
        $0.bounds = CGRect(x: 0, y: 0, width: 66, height: 66)
        $0.setImage(#imageLiteral(resourceName: "video_play"), for: .normal)
        $0.setImage(#imageLiteral(resourceName: "video_pause"), for: .selected)
        $0.addTarget(self, action: #selector(stateAction), for: .touchUpInside)
        return $0
    }( UIButton(type: .custom) )
    
    lazy var bottomView: UIView = {
        $0.backgroundColor = .clear
        return $0
    }( UIView() )
    
    lazy var progressView: UIProgressView = {
        $0.progressViewStyle = .default
        $0.progressTintColor = .lightGray
        $0.trackTintColor = UIColor.lightGray.withAlphaComponent(0.3)
        return $0
    }( UIProgressView() )
    
    lazy var sliderView: VideoPlayerSlider = {
        $0.isEnabled = false
        $0.setThumbImage(#imageLiteral(resourceName: "video_slider"), for: .normal)
        $0.minimumTrackTintColor = .cyan
        $0.maximumTrackTintColor = .clear
        $0.addTarget(self, action: #selector(sliderTouchBegin), for: .touchDown)
        $0.addTarget(self, action: #selector(sliderTouchEnd), for: [.touchUpInside, .touchUpOutside])
        $0.addTarget(self, action: #selector(sliderTouchCancel), for: .touchCancel)
        $0.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        return $0
    }( VideoPlayerSlider() )
    
    lazy var currentLabel: UILabel = {
        $0.font = .systemFont(ofSize: 10.0)
        $0.textAlignment = .center
        $0.textColor = .white
        $0.text = "00:00"
        return $0
    }( UILabel() )
    
    lazy var totalLabel: UILabel = {
        $0.font = .systemFont(ofSize: 10.0)
        $0.textAlignment = .center
        $0.textColor = .white
        $0.text = "00:00"
        return $0
    }( UILabel() )
    
    private var isShow: Bool = true { didSet { if isShow { show() } else { hide() } } }
    private var isDraging: Bool = false
    private var autoHideTask: DispatchWorkItem?
    private let format = DateFormatter()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setup()
        setupLayout()
        
        autoHide()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        setup()
        setupLayout()
        
        autoHide()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        setupLayout()
    }
    
    private func setup() {
        
        backgroundColor = .clear
        
        addSubview(loadingView)
        addSubview(stateButton)
        addSubview(bottomView)
        bottomView.addSubview(progressView)
        bottomView.addSubview(sliderView)
        bottomView.addSubview(currentLabel)
        bottomView.addSubview(totalLabel)
        
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapAction(_:)))
        single.numberOfTapsRequired = 1
        addGestureRecognizer(single)
        
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapAction(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        
        single.require(toFail: double)
    }
    
    private func setupLayout() {
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        loadingView.center = center
        stateButton.center = center
        
        bottomView.frame = CGRect(x: 0,
                                  y: bounds.height - 30,
                                  width: bounds.width,
                                  height: 30)
        
        progressView.frame = CGRect(x: 50,
                                    y: bottomView.bounds.height - 15,
                                    width: bottomView.bounds.width - 100,
                                    height: 15)
        sliderView.frame = progressView.frame
        currentLabel.frame = CGRect(x: 0,
                                    y: 0,
                                    width: 50,
                                    height: 30)
        totalLabel.frame = CGRect(x: bottomView.bounds.width - 50,
                                  y: 0,
                                  width: 50,
                                  height: 30)
    }
}

/// 事件处理
extension VideoPlayerControlView {
    
    @objc private func stateAction(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            delegate?.controlPlay()
        } else {
            delegate?.controlPause()
        }
    }
    
    @objc private func sliderTouchBegin(_ sender: UISlider) {
        isDraging = true
        autoHide(true)
    }
    
    @objc private func sliderTouchEnd(_ sender: UISlider) {
        isDraging = false
        delegate?.controlSeek(time: Double(sender.value)) { }
        autoHide()
    }
    
    @objc private func sliderTouchCancel(_ sender: UISlider) {
        isDraging = false
        autoHide()
    }
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        
        currentLabel.text = timeToHMS(time: Float64(sender.value))
    }
    
    @objc private func singleTapAction(_ gesture: UITapGestureRecognizer) {
        isShow = !isShow
        autoHide()
    }
    
    @objc private func doubleTapAction(_ gesture: UITapGestureRecognizer) {
        stateAction(stateButton)
    }
}

/// 显示与隐藏控制视图
extension VideoPlayerControlView {
    
    private func show() {
        UIView.beginAnimations("", context: nil)
        UIView.setAnimationDuration(0.2)
        stateButton.alpha = 1.0
        bottomView.alpha = 1.0
        UIView.commitAnimations()
    }
    
    private func hide() {
        UIView.beginAnimations("", context: nil)
        UIView.setAnimationDuration(0.2)
        stateButton.alpha = 0.0
        bottomView.alpha = 0.0
        UIView.commitAnimations()
    }
    
    private func autoHide(_ cancel: Bool = false) {
        autoHideTask?.cancel()
        autoHideTask = nil
        
        if cancel { return }
        
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.isShow = false
        }
        autoHideTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: item)
    }
}

extension VideoPlayerControlView: VideoPlayerControlViewable {
    
    func set(delegate: VideoPlayerControlViewDelegate?) {
        self.delegate = delegate
    }
    
    func set(state: Bool) {
        stateButton.isSelected = state
    }
    
    func set(buffer progress: Double, animated: Bool = true) {
        progressView.setProgress(Float(progress), animated: animated)
    }
    
    func set(current time: TimeInterval) {
        guard !isDraging else { return }
        
        sliderView.value = Float(time)
        currentLabel.text = timeToHMS(time: time)
    }
    
    func set(total time: TimeInterval) {
        sliderView.maximumValue = Float(time)
        totalLabel.text = timeToHMS(time: time)
    }
    
    func loadingBegin() {
        loadingView.startAnimating()
    }
    
    func loadingEnd() {
        loadingView.stopAnimating()
    }
    
    func set(enabled: Bool) {
        sliderView.isEnabled = enabled
        stateButton.isUserInteractionEnabled = enabled
    }
}

extension VideoPlayerControlView {
    
    private func timeToHMS(time: TimeInterval) -> String {
        
        format.timeZone = TimeZone(secondsFromGMT: 0)
        if time / 3600 >= 1 {
            format.dateFormat = "HH:mm:ss"
        } else {
            format.dateFormat = "mm:ss"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let string = format.string(from: date)
        return string
    }
}
