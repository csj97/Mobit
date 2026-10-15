import UIKit

final class MobitToastPresenter {
  enum Position {
    case top
    case bottom
  }

  // 진입 애니메이션이 끝난 뒤 메시지를 유지하는 시간이다.
  static let displayDuration: TimeInterval = 3
  // 한 화면에서는 마지막으로 요청한 토스트만 표시한다.
  private var toastView: MobitToastView?
  // 교체·화면 이탈 시 이전 자동 닫기 작업을 취소한다.
  private var dismissWorkItem: DispatchWorkItem?

  deinit {
    dismiss()
  }

  func show(
    _ message: String,
    in view: UIView,
    position: Position = .bottom,
    above bottomAnchor: NSLayoutYAxisAnchor? = nil
  ) {
    dismiss()
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    // 화면 전체를 덮지 않아 토스트 바깥의 입력과 스크롤을 유지한다.
    let toast = MobitToastView(message: message, position: position)
    toast.dismissCallBack = { [weak self, weak toast] in
      guard let self, let toast, self.toastView === toast else { return }
      self.hide(toast)
    }
    toastView = toast
    view.addSubview(toast)
    toast.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      toast.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      toast.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
    ])
    switch position {
    case .top:
      toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
    case .bottom:
      // 키보드·배너·Safe Area 중 가장 높은 경계 위로 자동 배치한다.
      let preferredBottom = toast.bottomAnchor.constraint(
        equalTo: bottomAnchor ?? view.safeAreaLayoutGuide.bottomAnchor,
        constant: -20
      )
      preferredBottom.priority = .defaultHigh
      preferredBottom.isActive = true
      NSLayoutConstraint.activate([
        toast.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        toast.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -20)
      ])
      if let bottomAnchor {
        toast.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20).isActive = true
      }
    }
    view.layoutIfNeeded()
    toast.alpha = 0
    toast.transform = UIAccessibility.isReduceMotionEnabled ? .identity
      : CGAffineTransform(translationX: 0, y: position == .top ? -8 : 8)
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
      animations: {
        toast.alpha = 1
        toast.transform = .identity
      },
      completion: { [weak self, weak toast] _ in
        guard let self, let toast, self.toastView === toast else { return }
        self.announce(message)
        // 이전 토스트의 타이머가 새 토스트를 닫지 않도록 동일 뷰인지 다시 확인한다.
        let workItem = DispatchWorkItem { [weak self, weak toast] in
          guard let self, let toast, self.toastView === toast else { return }
          self.hide(toast)
        }
        self.dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: workItem)
      }
    )
  }

  func dismiss() {
    dismissWorkItem?.cancel()
    dismissWorkItem = nil
    // 먼저 소유권을 해제해 진행 중인 애니메이션의 완료 콜백을 무효화한다.
    let toast = toastView
    toastView = nil
    toast?.layer.removeAllAnimations()
    toast?.removeFromSuperview()
  }

  private func hide(_ toast: MobitToastView) {
    guard toastView === toast, toast.isUserInteractionEnabled else { return }
    dismissWorkItem?.cancel()
    dismissWorkItem = nil
    toast.isUserInteractionEnabled = false
    UIView.animate(
      withDuration: 0.18,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseIn, .allowUserInteraction],
      animations: {
        toast.alpha = 0
        toast.transform = UIAccessibility.isReduceMotionEnabled ? .identity
          : CGAffineTransform(translationX: 0, y: toast.position == .top ? -8 : 8)
      },
      completion: { [weak self, weak toast] _ in
        guard let self, let toast, self.toastView === toast else { return }
        self.dismiss()
      }
    )
  }

  private func announce(_ message: String) {
    // 진행 중인 VoiceOver 안내를 끊지 않고 다음 순서로 읽는다.
    let attributes: [NSAttributedString.Key: Any]
    if #available(iOS 17.0, *) {
      attributes = [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.low]
    } else {
      attributes = [.accessibilitySpeechQueueAnnouncement: true]
    }
    UIAccessibility.post(
      notification: .announcement,
      argument: NSAttributedString(string: message, attributes: attributes)
    )
  }
}

private final class MobitToastView: UIView {
  // 위치에 따라 여백·색상·닫기 방향을 결정한다.
  let position: MobitToastPresenter.Position
  // 스와이프·접근성 닫기 요청을 표시 소유자에게 전달한다.
  var dismissCallBack: (() -> Void)?
  // 긴 번역과 글자 크기 확대에 맞춰 여러 줄로 표시한다.
  private let messageLabel = UILabel()

  init(message: String, position: MobitToastPresenter.Position) {
    self.position = position
    super.init(frame: .zero)
    accessibilityIdentifier = "mobitToast"
    isAccessibilityElement = true
    accessibilityLabel = message
    accessibilityTraits = .staticText
    messageLabel.text = message
    messageLabel.accessibilityIdentifier = "mobitToastMessage"
    messageLabel.isAccessibilityElement = false
    messageLabel.numberOfLines = 0
    messageLabel.lineBreakMode = .byWordWrapping
    messageLabel.textAlignment = .center
    messageLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 15, weight: .semibold)
    )
    messageLabel.adjustsFontForContentSizeCategory = true
    messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    addSubview(messageLabel)
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    // 상단은 가볍게, 하단은 넉넉한 캡슐 여백으로 구분한다.
    let padding = position == .top ? UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
      : UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
    NSLayoutConstraint.activate([
      messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: padding.top),
      messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
      messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
      messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.bottom)
    ])
    // 토스트의 위치 방향으로 밀어 즉시 닫을 수 있다.
    let swipe = UISwipeGestureRecognizer(target: self, action: #selector(requestDismiss))
    swipe.direction = position == .top ? .up : .down
    addGestureRecognizer(swipe)
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = CGSize(width: 0, height: 4)
    layer.shadowRadius = 12
    applyTheme()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
    applyTheme()
  }

  override func accessibilityPerformEscape() -> Bool {
    requestDismiss()
    return true
  }

  @objc private func requestDismiss() {
    dismissCallBack?()
  }

  private func applyTheme() {
    if position == .top {
      backgroundColor = .mobitColors(.surfaceElevated)
      messageLabel.textColor = .mobitColors(.textPrimary)
      layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.3 : 0.12
    } else {
      // 밝은 회색 대신 대비가 충분한 회색을 사용해 흰 글자를 유지한다.
      backgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(red: 0.24, green: 0.28, blue: 0.34, alpha: 1)
          : UIColor(red: 0.31, green: 0.35, blue: 0.41, alpha: 1)
      }
      messageLabel.textColor = .white
      layer.shadowOpacity = 0
    }
  }
}
