import UIKit

final class InvestmentChargeButton: UIButton {
  // 상태·테마 갱신 후에도 XIB에서 정한 투자내역 전용 글꼴을 유지한다.
  private var titleFont: UIFont?

  override init(frame: CGRect) {
    super.init(frame: frame)
    titleFont = .systemFont(ofSize: 12, weight: .semibold)
    setupStyle()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    titleFont = titleLabel?.font ?? .systemFont(ofSize: 12, weight: .semibold)
    setupStyle()
  }

  private func setupStyle() {
    layer.masksToBounds = false
    layer.shadowOffset = CGSize(width: 0, height: 1)
    layer.shadowRadius = 1
    // 크기와 글꼴은 투자내역 XIB가 관리한다.
    titleLabel?.adjustsFontForContentSizeCategory = false
    updateConfiguration()
  }

  override func updateConfiguration() {
    super.updateConfiguration()
    guard let titleFont else { return }
    // 공통 충전 버튼과 같은 테마별 글자·아이콘 색상을 사용한다.
    let foregroundColor = UIColor.mobitColors(.investmentChargeButtonText).resolvedColor(with: traitCollection)
    // 공통 충전 버튼과 같은 포인트 배경색을 사용한다.
    let fillColor = UIColor.mobitColors(.accountAction).resolvedColor(with: traitCollection)
    // 작은 버튼의 콘텐츠 간격만 투자내역에 맞게 줄인다.
    var style = UIButton.Configuration.plain()
    style.title = FuturesText.text("investment_recharge")
    style.image = UIImage(systemName: "plus")
    style.imagePadding = 3
    style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    style.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 3, bottom: 4, trailing: 3)
    style.titleLineBreakMode = .byTruncatingTail
    style.cornerStyle = .fixed
    style.background.cornerRadius = 8
    style.baseForegroundColor = foregroundColor.withAlphaComponent(isEnabled ? 1 : 0.6)
    style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      // XIB 글꼴에 공통 버튼의 Dynamic Type 배율을 다시 적용하지 않는다.
      var updated = attributes
      updated.font = titleFont
      return updated
    }
    style.background.backgroundColor = fillColor.withAlphaComponent(isEnabled ? (isHighlighted ? 0.86 : 1) : 0.45)
    style.background.strokeWidth = 1
    style.background.strokeColor = foregroundColor.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.3 : 0.08)
    configuration = style
    titleLabel?.numberOfLines = 1
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
