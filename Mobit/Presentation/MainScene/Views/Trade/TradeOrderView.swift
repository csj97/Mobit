//
//  TradeOrderView.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import UIKit

class TradeOrderView: UIView {
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    loadNib()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    loadNib()
  }
  
  private func loadNib() {
    let nib = UINib(nibName: "TradeOrderView", bundle: nil)
    if let view = nib.instantiate(withOwner: self, options: nil).first as? UIView {
      view.frame = self.bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(view)
    }
  }
}
