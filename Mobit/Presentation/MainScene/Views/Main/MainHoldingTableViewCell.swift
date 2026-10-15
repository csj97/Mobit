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
    $0.textColor = .mobitColors(.textPrimary)
  }
  private let cryptoSymbolLabel = UILabel().then {
	$0.font = .systemFont(ofSize: 12, weight: .regular)
	$0.textColor = .mobitColors(.textTertiary)
  }

  private let evaluationPriceLabel = valueLabel(size: 12, weight: .semibold)
  private let holdingQuantityLabel = subLabel()

  private let averageBuyPriceLabel = valueLabel(size: 11, weight: .semibold)

  private let profitRateLabel = valueLabel(size: 12, weight: .semibold)
  private let profitLossLabel = subLabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setUp()
  }

  required init?(coder: NSCoder) { fatalError() }

  private func setUp() {
    selectionStyle = .none
	backgroundColor = .mobitColors(.backgroundPrimary)
	contentView.backgroundColor = .mobitColors(.backgroundPrimary)

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

  func configure(
	crypto: CryptoCellInfo,
	product: TradingProduct = .spot
  ) {
    cryptoNameLabel.text = crypto.cryptoName
    cryptoSymbolLabel.text = crypto.market

    evaluationPriceLabel.text = Self.formatPrice(crypto.evaluationPrice ?? 0)
    holdingQuantityLabel.text = Self.formatQuantity(crypto.holdingQuantity ?? 0)
    averageBuyPriceLabel.text = Self.formatPrice(crypto.averageBuyPrice ?? 0)

    let rate = crypto.profitRate ?? 0
    profitRateLabel.text = String(format: "%.2f%%", rate)
    profitLossLabel.text = Self.formatSignedAmount(crypto.evaluationProfitLoss ?? 0)

	if product == .perpetual {
	  evaluationPriceLabel.text = crypto.evaluationPrice.map(Self.formatPrice) ?? "—"
	  profitRateLabel.text = crypto.profitRate.map { String(format: "%.2f%%", $0) } ?? "—"
	  profitLossLabel.text = crypto.evaluationProfitLoss.map(Self.formatSignedAmount) ?? "—"
	}

    let color = Self.signColor(rate)
    profitRateLabel.textColor = color
    profitLossLabel.textColor = color
  }

  // MARK: - Formatting

  private static func formatPrice(_ value: Double) -> String {
    value.formatTradingValue()
  }

  private static func formatQuantity(_ value: Double) -> String {
    value.formatTradingValue()
  }

  private static func formatSignedAmount(_ value: Double) -> String {
    guard value != 0 else { return "0" }
    let prefix = value > 0 ? "+" : ""
    return prefix + value.formatTradingValue()
  }

  // 국내 관례: 이익=빨강, 손실=파랑
  private static func signColor(_ value: Double) -> UIColor {
    MarketColorPalette.color(forSignedValue: value)
  }

  private static func valueLabel(size: CGFloat, weight: UIFont.Weight) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = .mobitColors(.textPrimary)
    label.textAlignment = .right
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    return label
  }

  private static func subLabel() -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = .mobitColors(.textSecondary)
    label.textAlignment = .right
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    return label
  }
}
