//
//  InvestmentTableViewCell.swift
//  Mobit
//
//  Created by 조성재 on 4/9/25.
//

import UIKit

class InvestmentTableViewCell: UITableViewCell {
  @IBOutlet weak var cryptoName: UILabel!
  @IBOutlet weak var cryptoAmount: UILabel!
  @IBOutlet weak var cryptoEvalPrice: UILabel!
  @IBOutlet weak var cryptoEvalLoss: UILabel!
  @IBOutlet weak var cryptoAveragePrice: UILabel!
  @IBOutlet weak var cryptoBuyPrice: UILabel!
  @IBOutlet weak var cryptoProfitRate: UILabel!
  @IBOutlet weak var bgView: UIView!
  @IBOutlet weak var dividerView: UIView!
  @IBOutlet weak var metricsStackView: UIStackView!
  private var currentProfitRate: Double?
  private let unsupportedBadgeView = UIView()
  private let unsupportedBadgeIcon = UIImageView()
  private let unsupportedBadgeLabel = UILabel()
  private let unsupportedNoticeView = UIView()
  private let unsupportedNoticeDot = UIView()
  private let unsupportedNoticeLabel = UILabel()
  private var badgeLeadingConstraint: NSLayoutConstraint?
  private var normalBottomConstraint: NSLayoutConstraint?
  private var unsupportedNoticeTopConstraint: NSLayoutConstraint?
    
  override func awakeFromNib() {
	super.awakeFromNib()
	setupUnsupportedStatusViews()
	updateThemeColors()
  }

  override func prepareForReuse() {
	super.prepareForReuse()
	setTradingUnsupported(false)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	updateThemeColors()
  }

  private func updateThemeColors() {
	self.backgroundColor = .mobitColors(.investmentBackground)
	self.contentView.backgroundColor = .mobitColors(.investmentBackground)
	self.bgView.backgroundColor = .mobitColors(.investmentBackground)
	self.dividerView.backgroundColor = .mobitColors(.investmentSeparator)
	self.unsupportedBadgeView.backgroundColor = Self.unsupportedBadgeBackgroundColor
	self.unsupportedBadgeView.layer.borderColor = Self.unsupportedBadgeBorderColor
	  .resolvedColor(with: self.traitCollection).cgColor
	self.unsupportedBadgeIcon.tintColor = Self.unsupportedBadgeTextColor
	self.unsupportedBadgeLabel.textColor = Self.unsupportedBadgeTextColor
	self.unsupportedNoticeView.backgroundColor = Self.unsupportedNoticeBackgroundColor
	self.unsupportedNoticeView.layer.borderColor = Self.unsupportedNoticeBorderColor
	  .resolvedColor(with: self.traitCollection).cgColor
	self.unsupportedNoticeDot.backgroundColor = Self.unsupportedNoticeTextColor
	self.unsupportedNoticeLabel.textColor = Self.unsupportedNoticeTextColor
	[
	  self.cryptoName,
	  self.cryptoAmount,
	  self.cryptoEvalPrice,
	  self.cryptoAveragePrice,
	  self.cryptoBuyPrice
	].forEach { $0?.textColor = .mobitColors(.investmentTextPrimary) }
	if let currentProfitRate {
	  let pnlColor = MarketColorPalette.color(forSignedValue: currentProfitRate)
	  self.cryptoProfitRate.textColor = pnlColor
	  self.cryptoEvalLoss.textColor = pnlColor
	}
  }
  
  override func setSelected(_ selected: Bool, animated: Bool) {
	super.setSelected(selected, animated: animated)
	
	// Configure the view for the selected state
  }
  
	func configure(
	  crypto: CryptoTransactionDataModel,
	  isLast: Bool,
	  isTradingUnsupported: Bool = false
	) {
    let valuation = PortfolioCalculator.valuation(
      of: crypto, btcKRWPrice: AppDataManager.shared.lastBTCKRWPrice(for: crypto.staticData.exchange)
    )
    let currency = crypto.settlementCurrency
    self.cryptoName.text = crypto.staticData.marketName
    self.cryptoAmount.text = crypto.staticData.holdingQuantity.formatSignificantDigits()
    if currency == .btc {
      self.cryptoAveragePrice.text = crypto.staticData.averageBuyPrice.formatSignificantDigits(digits: 8)
    } else {
      self.cryptoAveragePrice.text = valuation.averagePriceKRW.map {
        $0.formatSignificantDigits(digits: 4)
      } ?? "-"
    }
    self.cryptoBuyPrice.text = Self.krwText(valuation.costBasisKRW)
    self.cryptoEvalPrice.text = Self.krwText(valuation.evaluationKRW)
    self.cryptoEvalLoss.text = Self.krwText(valuation.profitLossKRW)
    self.cryptoProfitRate.text = valuation.profitRate.map { $0.formatSignificantDigits(digits: 2) + " %" } ?? "-"
    self.currentProfitRate = valuation.profitLossKRW
    let color = MarketColorPalette.color(forSignedValue: valuation.profitLossKRW ?? 0)
    self.cryptoProfitRate.textColor = color
    self.cryptoEvalLoss.textColor = color
	self.setTradingUnsupported(isTradingUnsupported)
    self.dividerView.isHidden = isLast
  }

  private func setupUnsupportedStatusViews() {
	self.unsupportedBadgeView.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedBadgeView.layer.cornerRadius = 8
	self.unsupportedBadgeView.layer.borderWidth = 1
	self.unsupportedBadgeView.isAccessibilityElement = true
	self.unsupportedBadgeView.accessibilityLabel = "거래지원 종료"

	self.unsupportedBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedBadgeIcon.image = UIImage(systemName: "exclamationmark.triangle")
	self.unsupportedBadgeIcon.contentMode = .scaleAspectFit
	self.unsupportedBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedBadgeLabel.text = "거래지원 종료"
	self.unsupportedBadgeLabel.font = .preferredFont(forTextStyle: .subheadline)
	self.unsupportedBadgeLabel.adjustsFontForContentSizeCategory = true
	self.unsupportedBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
	self.cryptoName.setContentCompressionResistancePriority(
	  UILayoutPriority(rawValue: UILayoutPriority.defaultHigh.rawValue - 1),
	  for: .horizontal
	)

	let badgeStack = UIStackView(arrangedSubviews: [unsupportedBadgeIcon, unsupportedBadgeLabel])
	badgeStack.translatesAutoresizingMaskIntoConstraints = false
	badgeStack.axis = .horizontal
	badgeStack.alignment = .center
	badgeStack.spacing = 6
	self.unsupportedBadgeView.addSubview(badgeStack)
	self.bgView.addSubview(self.unsupportedBadgeView)

	self.unsupportedNoticeView.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedNoticeView.layer.cornerRadius = 10
	self.unsupportedNoticeView.layer.borderWidth = 1
	self.unsupportedNoticeView.isAccessibilityElement = true
	self.unsupportedNoticeView.accessibilityLabel = "거래소에서 지원하지 않는 코인입니다."
	self.unsupportedNoticeDot.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedNoticeDot.layer.cornerRadius = 4
	self.unsupportedNoticeLabel.translatesAutoresizingMaskIntoConstraints = false
	self.unsupportedNoticeLabel.text = "거래소에서 지원하지 않는 코인입니다."
	self.unsupportedNoticeLabel.font = .preferredFont(forTextStyle: .subheadline)
	self.unsupportedNoticeLabel.adjustsFontForContentSizeCategory = true
	self.unsupportedNoticeLabel.numberOfLines = 0
	self.unsupportedNoticeView.addSubview(self.unsupportedNoticeDot)
	self.unsupportedNoticeView.addSubview(self.unsupportedNoticeLabel)
	self.bgView.addSubview(self.unsupportedNoticeView)

	self.badgeLeadingConstraint = self.cryptoName.trailingAnchor.constraint(
	  lessThanOrEqualTo: self.unsupportedBadgeView.leadingAnchor,
	  constant: -8
	)
	self.normalBottomConstraint = self.bgView.bottomAnchor.constraint(
	  equalTo: self.metricsStackView.bottomAnchor,
	  constant: 15
	)
	self.unsupportedNoticeTopConstraint = self.unsupportedNoticeView.topAnchor.constraint(
	  equalTo: self.metricsStackView.bottomAnchor,
	  constant: 20
	)

	NSLayoutConstraint.activate([
	  self.unsupportedBadgeView.topAnchor.constraint(equalTo: self.bgView.topAnchor, constant: 14),
	  self.unsupportedBadgeView.trailingAnchor.constraint(equalTo: self.bgView.trailingAnchor, constant: -20),
	  badgeStack.leadingAnchor.constraint(equalTo: self.unsupportedBadgeView.leadingAnchor, constant: 10),
	  badgeStack.trailingAnchor.constraint(equalTo: self.unsupportedBadgeView.trailingAnchor, constant: -10),
	  badgeStack.topAnchor.constraint(equalTo: self.unsupportedBadgeView.topAnchor, constant: 6),
	  badgeStack.bottomAnchor.constraint(equalTo: self.unsupportedBadgeView.bottomAnchor, constant: -6),
	  self.unsupportedBadgeIcon.widthAnchor.constraint(equalToConstant: 17),
	  self.unsupportedBadgeIcon.heightAnchor.constraint(equalToConstant: 17),
	  self.unsupportedNoticeView.leadingAnchor.constraint(equalTo: self.bgView.leadingAnchor, constant: 15),
	  self.unsupportedNoticeView.trailingAnchor.constraint(equalTo: self.bgView.trailingAnchor, constant: -15),
	  self.unsupportedNoticeView.bottomAnchor.constraint(equalTo: self.bgView.bottomAnchor, constant: -15),
	  self.unsupportedNoticeDot.leadingAnchor.constraint(equalTo: self.unsupportedNoticeView.leadingAnchor, constant: 14),
	  self.unsupportedNoticeDot.centerYAnchor.constraint(equalTo: self.unsupportedNoticeView.centerYAnchor),
	  self.unsupportedNoticeDot.widthAnchor.constraint(equalToConstant: 8),
	  self.unsupportedNoticeDot.heightAnchor.constraint(equalToConstant: 8),
	  self.unsupportedNoticeLabel.leadingAnchor.constraint(equalTo: self.unsupportedNoticeDot.trailingAnchor, constant: 10),
	  self.unsupportedNoticeLabel.trailingAnchor.constraint(equalTo: self.unsupportedNoticeView.trailingAnchor, constant: -14),
	  self.unsupportedNoticeLabel.topAnchor.constraint(equalTo: self.unsupportedNoticeView.topAnchor, constant: 14),
	  self.unsupportedNoticeLabel.bottomAnchor.constraint(equalTo: self.unsupportedNoticeView.bottomAnchor, constant: -14)
	])

	self.setTradingUnsupported(false)
  }

  private func setTradingUnsupported(_ isUnsupported: Bool) {
	self.unsupportedBadgeView.isHidden = !isUnsupported
	self.unsupportedNoticeView.isHidden = !isUnsupported
	self.badgeLeadingConstraint?.isActive = isUnsupported
	self.normalBottomConstraint?.isActive = !isUnsupported
	self.unsupportedNoticeTopConstraint?.isActive = isUnsupported
	self.setNeedsUpdateConstraints()
  }

  private static var unsupportedBadgeBackgroundColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.29, green: 0.06, blue: 0.08, alpha: 1) : UIColor(red: 1, green: 0.95, blue: 0.96, alpha: 1) }
  }

  private static var unsupportedBadgeBorderColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.70, green: 0.16, blue: 0.17, alpha: 1) : UIColor(red: 1, green: 0.77, blue: 0.81, alpha: 1) }
  }

  private static var unsupportedBadgeTextColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.64, blue: 0.68, alpha: 1) : UIColor(red: 0.93, green: 0.12, blue: 0.27, alpha: 1) }
  }

  private static var unsupportedNoticeBackgroundColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 1, green: 0.97, blue: 0.97, alpha: 1) }
  }

  private static var unsupportedNoticeBorderColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.20, green: 0.09, blue: 0.11, alpha: 1) : UIColor(red: 1, green: 0.84, blue: 0.86, alpha: 1) }
  }

  private static var unsupportedNoticeTextColor: UIColor {
	UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.59, blue: 0.62, alpha: 1) : UIColor(red: 0.82, green: 0.08, blue: 0.20, alpha: 1) }
  }

  private static func krwText(_ amount: Double?) -> String {
    amount.map { $0.formatSignificantDigits(digits: 0) } ?? "-"
  }
}
