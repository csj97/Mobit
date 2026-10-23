//
//  MobitAlertViewController.swift
//  Mobit
//
//  Created by 조성재 on 5/18/25.
//

import UIKit

enum AlertType {
  case onlyConfirm    // 확인 버튼
  case canCancel      // 확인 + 취소 버튼
}

class MobitAlertViewController: UIViewController {
  @IBOutlet weak var labelStackView: UIStackView!
  @IBOutlet weak var buttonStackView: UIStackView!
  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var contentLabel: UILabel!
  @IBOutlet weak var cancelButton: UIButton!
  @IBOutlet weak var confirmButton: UIButton!
  @IBOutlet weak var dividerView: UIView!
  @IBOutlet weak var buttonDividerView: UIView!
  @IBOutlet weak var dimView: UIView!
  
  var callBack: ((Bool) -> ())? = nil
  // 재시도처럼 화면마다 다른 확인 동작의 문구를 유지한다.
  private let confirmTitle: String
  // 닫기 동작에도 호출 화면에서 지정한 문구를 사용한다.
  private let cancelTitle: String
  
  var alertType: AlertType
  var titleString: String
  var content: String
  var titleAlignment: NSTextAlignment = .left
  var contentAlignment: NSTextAlignment = .left
  
  init(
	alertType: AlertType,
	titleAlignment: NSTextAlignment = .left,
	title: String,
	contentAlignment: NSTextAlignment = .left,
	content: String,
    confirmTitle: String = FuturesText.text("common_confirm"),
    cancelTitle: String = FuturesText.text("common_cancel"),
	callBack: ((Bool) -> ())? = nil
  ) {
	self.alertType = alertType
	self.titleString = title
	self.content = content
	self.callBack = callBack
	self.titleAlignment = titleAlignment
	self.contentAlignment = contentAlignment
    self.confirmTitle = confirmTitle
    self.cancelTitle = cancelTitle

	super.init(nibName: "MobitAlertViewController", bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.accessibilityIdentifier = "mobitAlert"
    self.view.accessibilityViewIsModal = true
    self.contentLabel.accessibilityIdentifier = "mobitAlert.content"
    self.cancelButton.accessibilityIdentifier = "mobitAlert.cancel"
    self.confirmButton.accessibilityIdentifier = "mobitAlert.confirm"
    self.cancelButton.configurationUpdateHandler = { [weak self] button in
      self?.applyButtonStyle(button)
    }
    self.confirmButton.configurationUpdateHandler = { [weak self] button in
      self?.applyButtonStyle(button)
    }
    self.configure(alertType: alertType, title: titleString, content: content, callBack: callBack)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // 실제 카드 크기에 맞춰 그림자를 그려 스크롤 시에도 모서리 형태를 유지한다.
    guard let card = labelStackView.superview else { return }
    card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: 24).cgPath
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
    guard isViewLoaded,
      previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true
        || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
    applyThemeColors()
  }

  private func applyThemeColors() {
    self.view.backgroundColor = .clear
    // 첨부 디자인의 청회색 배경을 사용하고 다크 모드에서는 대비를 보강한다.
    let darkAppearance = traitCollection.userInterfaceStyle == .dark
    self.dimView.alpha = 1
    self.dimView.backgroundColor = UIColor(hex: "#213145").withAlphaComponent(darkAppearance ? 0.6 : 0.45)
    self.labelStackView.superview?.backgroundColor = .mobitColors(.surfaceElevated)
    self.labelStackView.superview?.layer.cornerRadius = 24
    self.labelStackView.superview?.layer.cornerCurve = .continuous
    self.labelStackView.superview?.layer.shadowColor = UIColor.black.cgColor
    self.labelStackView.superview?.layer.shadowOffset = CGSize(width: 0, height: 12)
    self.labelStackView.superview?.layer.shadowRadius = 20
    self.labelStackView.superview?.layer.shadowOpacity = darkAppearance ? 0.24 : 0.14
    self.labelStackView.backgroundColor = .clear
    self.buttonStackView.backgroundColor = .clear
    self.titleLabel.textColor = darkAppearance ? .mobitColors(.textPrimary) : UIColor(hex: "#0B1C30")
    self.contentLabel.textColor = darkAppearance ? .mobitColors(.textSecondary) : UIColor(hex: "#4A4455")
    applyTypography()
    applyButtonStyle(cancelButton)
    applyButtonStyle(confirmButton)
  }

  private func applyTypography() {
    titleLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
      for: .systemFont(ofSize: 20, weight: .bold),
      compatibleWith: traitCollection
    )
    contentLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
      for: .systemFont(ofSize: 15, weight: .medium),
      compatibleWith: traitCollection
    )
    titleLabel.adjustsFontForContentSizeCategory = true
    contentLabel.adjustsFontForContentSizeCategory = true
    titleLabel.attributedText = makeText(
      titleString,
      label: titleLabel,
      alignment: titleAlignment,
      lineHeight: UIFontMetrics(forTextStyle: .title3).scaledValue(for: 28, compatibleWith: traitCollection)
    )
    contentLabel.attributedText = makeText(
      content,
      label: contentLabel,
      alignment: contentAlignment,
      lineHeight: UIFontMetrics(forTextStyle: .body).scaledValue(for: 24, compatibleWith: traitCollection)
    )
    // 큰 글자에서는 두 동작을 별도 행에 두어 문구가 좁은 반폭에 갇히지 않게 한다.
    buttonStackView.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
  }

  private func makeText(
    _ text: String,
    label: UILabel,
    alignment: NSTextAlignment,
    lineHeight: CGFloat
  ) -> NSAttributedString {
    // 첨부 시안의 행간을 유지하면서 호출자가 지정한 정렬을 보존한다.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    paragraph.lineBreakMode = .byWordWrapping
    return NSAttributedString(
      string: text,
      attributes: [
        .font: label.font ?? UIFont.systemFont(ofSize: 15),
        .foregroundColor: label.textColor ?? UIColor.black,
        .paragraphStyle: paragraph
      ]
    )
  }

  private func applyButtonStyle(_ button: UIButton) {
    // 기존 알림의 primary 토큰을 유지하고 밝은 다크 모드 accent에는 어두운 글자를 사용한다.
    let darkAppearance = traitCollection.userInterfaceStyle == .dark
    // 확인과 취소의 강조 수준만 분리하며 기존 액션과 문구는 유지한다.
    let primaryAction = button === confirmButton
    // 배경 토큰에 맞춰 버튼 제목의 명암 대비를 유지한다.
    let foregroundColor: UIColor = primaryAction
      ? (darkAppearance ? .mobitColors(.backgroundPrimary) : .white)
      : (darkAppearance ? .mobitColors(.textSecondary) : UIColor(hex: "#4A4455"))
    // 취소 버튼은 시안의 옅은 배경을 사용하고 다크 모드에서는 기존 표면색을 따른다.
    let backgroundColor: UIColor = primaryAction
      ? .mobitColors(.accentPrimary)
      : (darkAppearance ? .mobitColors(.surfacePrimary) : UIColor(hex: "#EFF4FF"))
    // 상태 갱신마다 기준 글꼴에서 확대해 중복 스케일링을 피한다.
    let font = UIFontMetrics(forTextStyle: .callout).scaledFont(
      for: .systemFont(ofSize: 14, weight: .semibold),
      compatibleWith: traitCollection
    )
    // 상태나 테마가 바뀌어도 호출 화면의 동작 문구를 보존한다.
    var style = button.configuration ?? .plain()
    style.title = primaryAction ? confirmTitle : cancelTitle
    style.baseForegroundColor = foregroundColor
    style.background.backgroundColor = backgroundColor.withAlphaComponent(button.isHighlighted ? 0.85 : 1)
    style.background.cornerRadius = 14
    style.cornerStyle = .fixed
    style.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10)
    style.titleLineBreakMode = .byWordWrapping
    style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      // 버튼 상태가 바뀌어도 현재 글자 크기 설정을 유지한다.
      var updated = attributes
      updated.font = font
      return updated
    }
    button.configuration = style
    button.backgroundColor = .clear
    button.titleLabel?.numberOfLines = 0
    button.titleLabel?.adjustsFontForContentSizeCategory = true
  }
  
  func configure(
	alertType: AlertType,
	title: String?,
	content: String,
	callBack: ((Bool) -> ())?
  ) {
	self.callBack = callBack
    self.alertType = alertType
    self.titleString = title ?? ""
    self.content = content
	
	self.titleLabel.textAlignment = titleAlignment
	self.contentLabel.textAlignment = contentAlignment
	
	self.cancelButton.isHidden = alertType == .onlyConfirm
    self.buttonDividerView.isHidden = true
    self.titleLabel.isHidden = titleString.isEmpty
    self.dividerView.isHidden = true
    applyThemeColors()
  }
  
  @IBAction func tapOnCancelButton(_ sender: UIButton) {
    dismissAlert(confirmed: false)
  }
  
  @IBAction func tapOnConfirmButton(_ sender: UIButton) {
    dismissAlert(confirmed: true)
  }

  private func dismissAlert(confirmed: Bool) {
    guard confirmButton.isEnabled else { return }
    confirmButton.isEnabled = false
    cancelButton.isEnabled = false
    // 빠른 연속 입력에도 화면이 닫힌 뒤 선택 결과를 한 번만 전달한다.
    let completion = callBack
    callBack = nil
    dismiss(animated: true) { completion?(confirmed) }
  }
}

extension UIViewController {
  @discardableResult
  func show(
	alertType: AlertType,
	titleAlignment: NSTextAlignment = .left,
	title: String? = nil,
	contentAlignment: NSTextAlignment = .left,
	content: String,
    confirmTitle: String = FuturesText.text("common_confirm"),
    cancelTitle: String = FuturesText.text("common_cancel"),
    completion: (() -> Void)? = nil,
	callBack: ((Bool) -> ())?
  ) -> MobitAlertViewController? {
    guard presentedViewController == nil, !isBeingDismissed else { return nil }
	// 모든 화면이 같은 표시 방식과 중복 방지 경로를 사용한다.
	let mobitAlertViewController = MobitAlertViewController(
	  alertType: alertType,
	  titleAlignment: titleAlignment,
	  title: title ?? "",
	  contentAlignment: contentAlignment,
	  content: content,
      confirmTitle: confirmTitle,
      cancelTitle: cancelTitle,
	  callBack: callBack
	)
	self.present(mobitAlertViewController, animated: true, completion: completion)
    return mobitAlertViewController
  }
}
