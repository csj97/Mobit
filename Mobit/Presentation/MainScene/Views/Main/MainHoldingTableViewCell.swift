//
//  MainHoldingTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 7/3/26.
//

import UIKit
import SnapKit
import Then

/// 거래소 "보유" 탭 전용 셀. [자산명 / 평가금액·보유량 / 평균매수가 / 수익률·평가손익]
final class MainHoldingTableViewCell: UITableViewCell {

  static let reuseIdentifier = "MainHoldingTableViewCell"

  private let cryptoNameLabel = UILabel().then {
    $0.font = .systemFont(ofSize: 14, weight: .medium)
    $0.textColor = .black
  }
  private let cryptoSymbolLabel = UILabel().then {
	$0.font = .systemFont(ofSize: 12, weight: .regular)
	$0.textColor = .lightGray
  }

  private let evaluationPriceLabel = valueLabel(size: 12, weight: .medium)
  private let holdingQuantityLabel = subLabel()

  private let averageBuyPriceLabel = valueLabel(size: 11, weight: .medium)

  private let profitRateLabel = valueLabel(size: 12, weight: .medium)
  private let profitLossLabel = subLabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setUp()
  }

  required init?(coder: NSCoder) { fatalError() }

  private func setUp() {
    selectionStyle = .none

    let nameStack = UIStackView(arrangedSubviews: [cryptoNameLabel, cryptoSymbolLabel]).then {
      $0.axis = .vertical
      $0.alignment = .leading
      $0.spacing = 0
    }
    let evalStack = UIStackView(arrangedSubviews: [evaluationPriceLabel, holdingQuantityLabel]).then {
      $0.axis = .vertical
      $0.alignment = .trailing
      $0.spacing = 0
    }
    let profitStack = UIStackView(arrangedSubviews: [profitRateLabel, profitLossLabel]).then {
      $0.axis = .vertical
      $0.alignment = .trailing
      $0.spacing = 0
    }
    averageBuyPriceLabel.textAlignment = .right

    // 평균매수가는 단일 값이지만, 옆 2줄 컬럼의 윗줄과 높이를 맞추기 위해
    // 컨테이너에 담아 상단(top)에 고정한다. (라벨은 세로 중앙에 그려지므로 직접 상단정렬 불가)
    let avgContainer = UIView()
    avgContainer.addSubview(averageBuyPriceLabel)
    averageBuyPriceLabel.snp.makeConstraints { make in
      make.top.leading.trailing.equalToSuperview()
    }

    let contentStack = UIStackView(
      arrangedSubviews: [nameStack, evalStack, avgContainer, profitStack]
    ).then {
      $0.axis = .horizontal
      $0.alignment = .fill
      $0.distribution = .fillEqually
      $0.spacing = 0
    }

    contentView.addSubview(contentStack)
    contentStack.snp.makeConstraints { make in
      make.leading.equalToSuperview().inset(10)
      make.trailing.equalToSuperview().inset(10)
      make.top.equalToSuperview().offset(10)
      make.bottom.equalToSuperview().offset(-10)
    }
  }

  func configure(crypto: CryptoCellInfo) {
    cryptoNameLabel.text = crypto.cryptoName
    cryptoSymbolLabel.text = crypto.market

    evaluationPriceLabel.text = Self.formatPrice(crypto.evaluationPrice ?? 0)
    holdingQuantityLabel.text = Self.formatQuantity(crypto.holdingQuantity ?? 0)
    averageBuyPriceLabel.text = Self.formatPrice(crypto.averageBuyPrice ?? 0)

    let rate = crypto.profitRate ?? 0
    profitRateLabel.text = String(format: "%.2f%%", rate)
    profitLossLabel.text = Self.formatSignedAmount(crypto.evaluationProfitLoss ?? 0)

    let color = Self.signColor(rate)
    profitRateLabel.textColor = color
    profitLossLabel.textColor = color
  }

  // MARK: - Formatting

  /// 금액 표시용 소수점 자리수. 세 자리수(100) 이상이면 소수점을 버린다.
  /// 예: 80.5 → 유지, 104 → 정수. 1 미만(BTC 마켓 등)은 소수점 유지.
  private static func priceFractionDigits(for value: Double) -> Int {
    let magnitude = abs(value)
    if magnitude >= 100 { return 0 }
    if magnitude >= 1 { return 2 }
    return 8
  }

  private static func formatPrice(_ value: Double) -> String {
    guard value != 0 else { return "0" }
    return formatNumber(value, maxFraction: priceFractionDigits(for: value))
  }

  private static func formatQuantity(_ value: Double) -> String {
    return formatNumber(value, maxFraction: 8)
  }

  private static func formatSignedAmount(_ value: Double) -> String {
    guard value != 0 else { return "0" }
    let prefix = value > 0 ? "+" : ""
    return prefix + formatNumber(value, maxFraction: priceFractionDigits(for: value))
  }

  private static func formatNumber(_ value: Double, maxFraction: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maxFraction
    return formatter.string(from: NSNumber(value: value)) ?? "0"
  }

  // 국내 관례: 이익=빨강, 손실=파랑
  private static func signColor(_ value: Double) -> UIColor {
    MarketColorPalette.color(forSignedValue: value)
  }

  private static func valueLabel(size: CGFloat, weight: UIFont.Weight) -> UILabel {
    let label = UILabel()
    label.font = UIFont(name: "SUIT-SemiBold", size: size) ?? .systemFont(ofSize: size, weight: weight)
    label.textColor = .black
    label.textAlignment = .right
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    return label
  }

  private static func subLabel() -> UILabel {
    let label = UILabel()
    label.font = UIFont(name: "SUIT-Medium", size: 11) ?? .systemFont(ofSize: 11)
    label.textColor = .gray
    label.textAlignment = .right
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    return label
  }
}
