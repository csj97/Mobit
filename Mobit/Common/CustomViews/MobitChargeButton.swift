//
//  MobitChargeButton.swift
//  Mobit
//
//  Created by 조성재 on 7/10/25.
//

import UIKit

final class MobitChargeButton: UIButton {
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupStyle()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupStyle()
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    updateConfiguration()
  }

  private func setupStyle() {
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
    layer.masksToBounds = false
    layer.shadowOffset = CGSize(width: 0, height: 1)
    layer.shadowRadius = 1
    titleLabel?.adjustsFontForContentSizeCategory = true
    updateConfiguration()
  }

  override func updateConfiguration() {
    super.updateConfiguration()
    // 진한 버튼 배경에서도 충전 문구를 또렷하게 표시한다.
    let foregroundColor = UIColor.mobitColors(.investmentChargeButtonText).resolvedColor(with: traitCollection)
    // 더보기와 같은 계좌 충전용 포인트 컬러를 따른다.
    let fillColor = UIColor.mobitColors(.accountAction).resolvedColor(with: traitCollection)
    // 버튼 높이와 문구 너비를 글자 크기에 맞춰 함께 늘린다.
    let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
    // 현물과 선물의 충전 버튼에 같은 문구와 모서리 형태를 적용한다.
    var style = UIButton.Configuration.plain()
    // 앱이 사용 중인 언어별 문자열 테이블에서 충전 문구를 읽는다.
    let table = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "Localizable(KO)" : "Localizable(EN)"
    style.title = NSLocalizedString(
      "investment_recharge",
      tableName: table,
      bundle: .main,
      value: "",
      comment: ""
    )
    style.image = UIImage(systemName: "plus")
    style.imagePadding = 4
    style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    style.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    style.cornerStyle = .fixed
    style.background.cornerRadius = 8
    style.baseForegroundColor = foregroundColor.withAlphaComponent(isEnabled ? 1 : 0.6)
    style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      // 글자 크기 설정에 맞춰 충전 문구의 폰트를 적용한다.
      var updated = attributes
      updated.font = font
      return updated
    }
    style.background.backgroundColor = fillColor.withAlphaComponent(isEnabled ? (isHighlighted ? 0.86 : 1) : 0.45)
    style.background.strokeWidth = 1
    // 어두운 화면에서도 버튼 외곽이 묻히지 않도록 얇은 밝은 테두리를 둔다.
    style.background.strokeColor = foregroundColor.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.3 : 0.08)
    configuration = style
    backgroundColor = .clear
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = isEnabled && !isHighlighted && traitCollection.userInterfaceStyle != .dark ? 0.12 : 0
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = 8
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    setNeedsUpdateConfiguration()
  }
}
