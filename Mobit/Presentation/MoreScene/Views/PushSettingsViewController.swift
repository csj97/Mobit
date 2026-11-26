import SnapKit
import UIKit
import UserNotifications

// 확인 버튼과 켜진 스위치가 같은 테마 색상을 사용한다.
private let pushSettingsActionColor = UIColor { traits in
  traits.userInterfaceStyle == .dark ? .systemGray5 : UIColor(hex: "#0B1C30")
}

final class PushSettingsViewController: UIViewController {
  // 권한 확인 전에는 스위치 입력을 받지 않는다.
  private var permission: UNAuthorizationStatus?
  // 화면 아래에서 실패한 설정 하나를 안내한다.
  private let errorLabel = UILabel()
  // 시스템 권한이 꺼졌을 때만 설정으로 바로 이동한다.
  private let systemButton = UIButton(type: .system)
  // 토픽별 저장값과 표시 상태를 연결한다.
  private var topicSwitches: [PushCategory: PushSettingsToggle] = [:]
  // 개인 수익률 알림은 토픽과 별도로 기기에 등록한다.
  private let holdingSwitch = PushSettingsToggle()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(hex: "#213145").withAlphaComponent(0.62)
    view.accessibilityViewIsModal = true
    buildCard()
    NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .pushSettingsChanged, object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshPermission),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    refresh()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshPermission()
  }

  @objc private func refreshPermission() {
    Task { @MainActor in
      permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      refresh()
    }
  }

  private func buildCard() {
    // 작은 기기나 큰 글씨에서는 카드 안에서 끝까지 스크롤한다.
    let card = UIScrollView()
    card.accessibilityIdentifier = "pushSettings.card"
    card.backgroundColor = color("#FFFFFF", dark: .secondarySystemBackground)
    card.layer.cornerRadius = 28
    card.contentInsetAdjustmentBehavior = .never
    view.addSubview(card)
    card.snp.makeConstraints { make in
      make.center.equalTo(view.safeAreaLayoutGuide)
      make.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(16)
      make.top.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(12)
      make.width.lessThanOrEqualTo(360)
      make.width.equalTo(360).priority(999)
    }

    // 제목부터 확인 버튼까지 콘텐츠의 고유 높이로 카드를 구성한다.
    let content = UIStackView()
    content.axis = .vertical
    content.spacing = 6
    content.isLayoutMarginsRelativeArrangement = true
    content.directionalLayoutMargins = .init(top: 24, leading: 16, bottom: 24, trailing: 16)
    card.addSubview(content)
    content.snp.makeConstraints { make in
      make.edges.equalTo(card.contentLayoutGuide)
      make.width.equalTo(card.frameLayoutGuide)
      make.height.equalTo(card.frameLayoutGuide).priority(249)
    }

    // 제목·설명과 버튼을 카드 행보다 8pt 안쪽에 맞춘다.
    let header = UIStackView()
    header.axis = .vertical
    header.spacing = 2
    header.isLayoutMarginsRelativeArrangement = true
    header.directionalLayoutMargins = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
    // 닫기 버튼은 시스템 기호와 별도의 접근성 이름을 사용한다.
    let closeButton = UIButton(type: .system)
    closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
    closeButton.tintColor = color("#4A4455", dark: .label)
    closeButton.backgroundColor = color("#E5EEFF", dark: .tertiarySystemBackground)
    closeButton.layer.cornerRadius = 16
    closeButton.accessibilityLabel = FuturesText.text("settings_close")
    closeButton.accessibilityIdentifier = "pushSettings.close"
    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    closeButton.snp.makeConstraints { $0.size.equalTo(32) }
    // 제목은 VoiceOver 헤더 탐색에 포함한다.
    let title = label("push_settings_dialog", style: .headline)
    title.accessibilityTraits.insert(.header)
    // 오른쪽 닫기 버튼은 제목이 길어져도 고유 너비를 유지한다.
    let heading = UIStackView(arrangedSubviews: [title, closeButton])
    heading.alignment = .center
    heading.spacing = 8
    header.addArrangedSubview(heading)
    header.addArrangedSubview(label("push_settings_intro", style: .subheadline))
    content.addArrangedSubview(header)
    content.setCustomSpacing(16, after: header)

    for category in PushCategory.allCases {
      // 서버 구독이 실패하면 해당 항목의 선택만 되돌린다.
      let toggle = PushSettingsToggle()
      topicSwitches[category] = toggle
      toggle.control.accessibilityIdentifier = category.rawValue
      toggle.control.addAction(UIAction { action in
        guard let control = action.sender as? UISwitch else { return }
        (UIApplication.shared.delegate as? AppDelegate)?.setPushCategory(category, enabled: control.isOn)
      }, for: .valueChanged)
      content.addArrangedSubview(row(
        title: category.titleKey,
        detail: category == .announcement ? "push_settings_notice_detail" : "push_settings_price_detail",
        toggle: toggle
      ))
    }
    holdingSwitch.control.accessibilityIdentifier = "holdingAlerts"
    holdingSwitch.control.addAction(UIAction { action in
      guard let control = action.sender as? UISwitch else { return }
      HoldingAlertSync.shared.setEnabled(control.isOn)
    }, for: .valueChanged)
    content.addArrangedSubview(row(title: "holding_sync_title", detail: "push_settings_holding_detail", toggle: holdingSwitch))

    // 오류가 없으면 안내와 시스템 설정 버튼 모두 레이아웃에서 빠진다.
    let footer = UIStackView()
    footer.axis = .vertical
    footer.spacing = 10
    footer.isLayoutMarginsRelativeArrangement = true
    footer.directionalLayoutMargins = .init(top: 24, leading: 8, bottom: 0, trailing: 8)
    errorLabel.accessibilityIdentifier = "pushSettings.error"
    errorLabel.font = .preferredFont(forTextStyle: .footnote)
    errorLabel.adjustsFontForContentSizeCategory = true
    errorLabel.numberOfLines = 0
    errorLabel.textColor = color("#BA1A1A", dark: .systemRed)
    footer.addArrangedSubview(errorLabel)
    systemButton.setTitle(FuturesText.text("push_settings_system"), for: .normal)
    systemButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
    footer.addArrangedSubview(systemButton)
    // 확인은 이미 반영된 설정을 유지하고 팝업만 닫는다.
    let confirm = UIButton(type: .system)
    // Dynamic Type에 맞춰 확인 버튼의 콘텐츠 높이도 늘어난다.
    var configuration = UIButton.Configuration.filled()
    configuration.title = FuturesText.text("common_confirm")
    configuration.baseBackgroundColor = pushSettingsActionColor
    configuration.baseForegroundColor = color("#FFFFFF", dark: .label)
    configuration.background.cornerRadius = 16
    configuration.cornerStyle = .fixed
    confirm.accessibilityIdentifier = "pushSettings.confirm"
    confirm.configuration = configuration
    confirm.snp.makeConstraints { $0.height.greaterThanOrEqualTo(48) }
    confirm.addTarget(self, action: #selector(close), for: .touchUpInside)
    footer.addArrangedSubview(confirm)
    content.addArrangedSubview(footer)
  }

  private func row(title: String, detail: String, toggle: PushSettingsToggle) -> UIView {
    // 스위치와 설명을 하나의 알림 카드로 묶는다.
    let texts = UIStackView()
    texts.axis = .vertical
    texts.alignment = .leading
    texts.spacing = 4
    texts.addArrangedSubview(label(title, style: .headline))
    texts.addArrangedSubview(label(detail, style: .subheadline))
    texts.accessibilityElementsHidden = true
    toggle.control.accessibilityLabel = FuturesText.text(title)
    toggle.control.accessibilityHint = FuturesText.text(detail)
    // 모든 행에 같은 안쪽 여백을 적용하고 내용이 길면 높이를 늘린다.
    let card = UIStackView(arrangedSubviews: [texts, toggle])
    card.spacing = 10
    card.alignment = .center
    card.isLayoutMarginsRelativeArrangement = true
    card.directionalLayoutMargins = .init(top: 14, leading: 14, bottom: 14, trailing: 14)
    card.layer.cornerRadius = 16
    card.backgroundColor = color("#F8F9FF", dark: .tertiarySystemBackground)
    card.snp.makeConstraints { $0.height.greaterThanOrEqualTo(72) }
    return card
  }

  private func color(_ light: String, dark: UIColor) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? dark : UIColor(hex: light) }
  }

  private func label(_ key: String, style: UIFont.TextStyle) -> UILabel {
    // 화면의 텍스트 스타일을 기준으로 시스템 글씨 크기에 맞춘다.
    let label = UILabel()
    label.text = FuturesText.text(key)
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textColor = style == .headline ? color("#0B1C30", dark: .label) : color("#565E74", dark: .secondaryLabel)
    return label
  }

  @objc private func refresh() {
    // 등록을 처리하는 객체에서 현재 설정과 오류를 한 번에 읽는다.
    let app = UIApplication.shared.delegate as? AppDelegate
    render(
      permission: permission,
      holdingFailure: HoldingAlertSync.shared.failure,
      topicFailures: app?.topicFailures ?? [:],
      changingTopics: app?.changingTopics ?? []
    )
  }

  func render(
    permission: UNAuthorizationStatus?,
    holdingFailure: PushSettingFailure?,
    topicFailures: [PushCategory: PushSettingFailure],
    changingTopics: Set<PushCategory>
  ) {
    // OS 권한과 항목별 선호를 함께 반영한다.
    let allowed = permission?.allowsPush == true
    for (category, toggle) in topicSwitches {
      toggle.show(on: allowed && category.isEnabled, enabled: allowed && !changingTopics.contains(category))
    }
    holdingSwitch.show(on: allowed && HoldingAlertSync.enabled, enabled: allowed)
    systemButton.isHidden = permission?.allowsPush != false
    // 권한 안내가 필요하면 개별 오류보다 먼저 표시한다.
    let failedTitle = holdingFailure != nil ? "holding_sync_title" :
      PushCategory.allCases.first { topicFailures[$0] != nil }?.titleKey
    // 정상 상태에서는 하단 안내 영역을 접는다.
    let message: String?
    if !systemButton.isHidden {
      message = FuturesText.text("push_settings_permission")
    } else {
      message = failedTitle.map { String(format: FuturesText.text("push_settings_failure"), FuturesText.text($0)) }
    }
    if let message, message != errorLabel.text, view.window != nil {
      UIAccessibility.post(notification: .announcement, argument: message)
    }
    errorLabel.text = message
    errorLabel.isHidden = message == nil
  }

  @objc private func openSettings() {
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
  }

  @objc private func close() { dismiss(animated: true) }
}

private extension PushCategory {
  // 각 토픽의 스위치와 오류 안내에 같은 이름을 사용한다.
  var titleKey: String { self == .announcement ? "push_settings_announcement" : "push_settings_price" }
}

private final class PushSettingsToggle: UIView {
  // 조작과 VoiceOver 상태 전달은 기본 시스템 스위치가 담당한다.
  let control = UISwitch()
  // 켜진 상태를 색과 함께 표시하는 체크 기호다.
  private let checkmark = UIImageView(image: UIImage(
    systemName: "checkmark",
    withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
  ))

  init() {
    super.init(frame: .zero)
    control.onTintColor = pushSettingsActionColor
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .horizontal)
    addSubview(control)
    control.snp.makeConstraints { $0.edges.equalToSuperview() }
    checkmark.isAccessibilityElement = false
    checkmark.isUserInteractionEnabled = false
    checkmark.tintColor = control.onTintColor
    addSubview(checkmark)
    checkmark.snp.makeConstraints { make in
      make.centerY.equalTo(control)
      make.centerX.equalTo(control.snp.trailing).offset(-15)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func show(on: Bool, enabled: Bool) {
    control.isEnabled = enabled
    control.setOn(on, animated: window != nil)
    checkmark.isHidden = !on || UIAccessibility.isOnOffSwitchLabelsEnabled
  }
}
