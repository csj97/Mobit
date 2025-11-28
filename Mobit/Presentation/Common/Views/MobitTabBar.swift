//
//  MobitTabBar.swift
//  Mobit
//
//  Created by 조성재 on 6/15/25.
//

import UIKit
import SnapKit

enum MobitTabItem: Int {
  case exchange
  case wallet
  case news
  case more
  
  var normalImage: UIImage? {
	switch self {
	case .exchange:
	  return UIImage(named: "tab_exchange")
	case .wallet:
	  return UIImage(named: "tab_wallet")
	case .news:
	  return UIImage(named: "tab_news")
	case .more:
	  return UIImage(named: "tab_more")
	}
  }
  
  var selectedImage: UIImage? {
	switch self {
	case .exchange:
	  return UIImage(named: "tab_exchange_selected")
	case .wallet:
	  return UIImage(named: "tab_wallet_selected")
	case .news:
	  return UIImage(named: "tab_news_selected")
	case .more:
	  return UIImage(named: "tab_more_selected")
	}
  }
}

final class MobitTabBar: UIView {
  private let stackView: UIStackView = UIStackView().then({ stackView in
	stackView.axis = .horizontal
	stackView.distribution = .fillEqually
	stackView.alignment = .fill
  })
  
  var didSelectItem: ((Int) -> Void)?
  private let tabItems: [MobitTabItem]
  private var tabImageViews = [UIImageView]()
  private var tabLabels = [UILabel]()
  private let tabLabelsText: [String] = ["거래소", "투자내역", "뉴스", "더보기"]
  private var selectedIndex = 0 {
	didSet { updateUI() }
  }
  
  init(tabItems: [MobitTabItem]) {
	self.tabItems = tabItems
	super.init(frame: .zero)
	setUp()
  }
  
  required init?(coder: NSCoder) {
	fatalError()
  }
  
  private func setUp() {
	defer { updateUI() }
	
	tabItems
	  .enumerated()
	  .forEach { i, item in
		let container = UIView()
		
		let itemStackView = UIStackView().then { stackView in
		  stackView.axis = . vertical
		  stackView.distribution = .fill
		  stackView.alignment = .fill
		}
		let imageView = UIImageView().then { imgView in
		  imgView.image = item.normalImage
		  imgView.contentMode = .center
		}
		let textLabel = UILabel().then { label in
		  label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
		  label.textAlignment = .center
		  label.text = self.tabLabelsText[i]
		}
		
		itemStackView.addArrangedSubview(imageView)
		itemStackView.addArrangedSubview(textLabel)
		
		tabImageViews.append(imageView)
		tabLabels.append(textLabel)
		
		container.addSubview(itemStackView)
		itemStackView.snp.makeConstraints { make in
		  make.edges.equalToSuperview()
		}
		
		let button = UIButton().then { button in
		  button.backgroundColor = .clear
		  button.addAction { [weak self] in
			self?.selectedIndex = i
			self?.didSelectItem?(i)
		  }
		}
		
		container.addSubview(button)
		button.snp.makeConstraints { make in
		  make.edges.equalToSuperview()
		}
	
		stackView.addArrangedSubview(container)
	  }
	
	backgroundColor = .white
	
	addSubview(stackView)
	stackView.translatesAutoresizingMaskIntoConstraints = false
	
	stackView.snp.makeConstraints { make in
	  make.leading.trailing.equalToSuperview()
	  make.top.equalToSuperview().inset(10)
	  make.bottom.equalToSuperview().inset(15)
	}
	
  }
  
  private func updateUI() {
	tabItems
	  .enumerated()
	  .forEach { i, item in
		let isButtonSelected = selectedIndex == i
		let image = isButtonSelected ? item.selectedImage : item.normalImage
		let textColor = isButtonSelected ? UIColor(hex: "#657fe6") : .black
		let font = isButtonSelected ? UIFont.systemFont(ofSize: 14, weight: .bold) : UIFont.systemFont(ofSize: 12, weight: .regular)
		let selectedImage = tabImageViews[i]
		let selectedTextLabel = tabLabels[i]
		
		selectedImage.image = image
		selectedTextLabel.font = font
		selectedTextLabel.textColor = textColor
	  }
  }
}

public extension UIControl {
  // Closure 처리방식 (addTarget X)
  func addAction(for controlEvents: UIControl.Event = .touchUpInside, _ closure: @escaping () -> ()) {
	@objc class ClosureSleeve: NSObject {
	  let closure: () -> ()
	  
	  init(_ closure: @escaping () -> ()) {
		self.closure = closure
	  }
	  
	  @objc func invoke() {
		closure()
	  }
	}
	
	let sleeve = ClosureSleeve(closure)
	addTarget(sleeve, action: #selector(ClosureSleeve.invoke), for: controlEvents)
	objc_setAssociatedObject(self, "\(UUID())", sleeve, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
  }
}

extension UIImage {
  func alpha(_ value:CGFloat) -> UIImage {
	UIGraphicsBeginImageContextWithOptions(size, false, scale)
	draw(at: CGPoint.zero, blendMode: .normal, alpha: value)
	let newImage = UIGraphicsGetImageFromCurrentImageContext()
	UIGraphicsEndImageContext()
	return newImage!
  }
  
  func resize(to size: CGSize) -> UIImage? {
	  UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
	  draw(in: CGRect(origin: .zero, size: size))
	  let newImage = UIGraphicsGetImageFromCurrentImageContext()
	  UIGraphicsEndImageContext()
	  return newImage
  }
}
