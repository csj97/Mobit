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
  private var currentProfitRate: Double?
    
  override func awakeFromNib() {
	super.awakeFromNib()
	updateThemeColors()
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
  
  func configure(crypto: CryptoTransactionDataModel, isLast: Bool) {
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
    self.dividerView.isHidden = isLast
  }

  private static func krwText(_ amount: Double?) -> String {
    amount.map { $0.formatSignificantDigits(digits: 0) } ?? "-"
  }
}
