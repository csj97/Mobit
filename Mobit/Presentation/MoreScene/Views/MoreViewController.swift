//
//  MoreViewController.swift
//  Mobit
//
//  Created by 조성재 on 5/18/25.
//

import RxCocoa
import RxSwift
import SnapKit
import UIKit

class MoreViewController: MobitBaseViewController {
  
  @IBOutlet weak var naviBar: UIView!
  @IBOutlet weak var marketColorThemeButton: UIButton!
  @IBOutlet weak var riseColorPreviewView: UIView!
  @IBOutlet weak var fallColorPreviewView: UIView!
  @IBOutlet weak var chargeMoneyButton: UIButton!
  @IBOutlet weak var userNoticeButton: UIButton!
  @IBOutlet weak var investInitButton: UIButton!
  @IBOutlet weak var versionLabel: UILabel!
  
  weak var coordinator: MoreCoordinator?
  
  override func viewDidLoad() {
	super.viewDidLoad()
	
	self.setUI()
	self.setData()
  }
  
  override func viewDidLayoutSubviews() {
	super.viewDidLayoutSubviews()
  }
  
  func setUI() {
	self.navigationController?.navigationBar.isHidden = true
	self.naviBar.layer.applyShadow(color: .lightGray, alpha: 0.3, x: 0, y: 10, blur: 20)
	self.marketColorThemeButton.contentHorizontalAlignment = .leading
	self.configurePreviewViews()
  }
  
  func setData() {
	self.updateVersionLabel()
	self.updateMarketColorThemeButtonTitle()
  }
  
  @IBAction func tapOnChargeMoney(_ sender: UIButton) {
	
	MobitAnalyticsUtil.sendClickEvent(event: .more_charge)
	
	self.show(
	  alertType: .canCancel,
	  title: "안내",
	  content: "본 광고를 시청하시면 모의투자 금액\n10,000,000원이 보유 금액으로 추가됩니다."
	) { isOk in
	  if isOk {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_confirm)
		RewardedAdManager.shared.showAd(from: self) {
		  self.show(alertType: .onlyConfirm, content: "충전이 완료 되었습니다.", callBack: nil)
		  UserDataManager.userInformation?.userAvailableBalance += 10_000_000
		}
	  } else {
		MobitAnalyticsUtil.sendClickEvent(event: .ad_click_cancel)
	  }
	}
  }
  
  @IBAction func tapOnUserNoticeButton(_ sender: UIButton) {
	let noticeContent = """
   사용자는 이 앱에서 실제 금전적인 자산을 입금하거나 출금할 수 없으며,
   모든 거래 및 수익/손실은 가상의 수치일 뿐, 
   
   ⭐️ 현실의 자산에 어떤 영향도 미치지 않습니다.
   
   앱 내 정보 및 결과는 학습 또는 참고 목적으로 제공되며,
   실제 투자 판단의 근거로 삼을 수 없으며, 
   
   ⭐️ 그로 인해 발생한 어떠한 손실에 대해서도 본 앱은 책임지지 않습니다.
   """
	
	MobitAnalyticsUtil.sendClickEvent(event: .more_notice)
	
	self.show(
	  alertType: .onlyConfirm,
	  titleAlignment: .center,
	  title: "🚨 사용자 안내사항 🚨",
	  content: noticeContent,
	  callBack: nil
	)
  }
  
  @IBAction func tapOnInvestInitButton(_ sender: UIButton) {
	
	let noticeContent = """
  투자하신 거래 내역이 모두 초기화되며,
  보유 금액도 0원이 됩니다.
 """
	
	MobitAnalyticsUtil.sendClickEvent(event: .more_init_data)
	
	self.show(
	  alertType: .canCancel,
	  titleAlignment: .center,
	  title: "🚨 투자내역 초기화 안내 🚨",
	  content: noticeContent
	) { isPositive in
	  if isPositive {
		UserDataManager.resetInvestmentData()
		
		self.show(alertType: .onlyConfirm, content: "초기화 되었습니다.", callBack: nil)
	  }
	}
  }
  
  @IBAction func tapOnMarketColorThemeButton(_ sender: UIButton) {
	let selectionViewController = MarketColorThemeSelectionViewController(
	  selectedTheme: UserDataManager.marketColorTheme
	) { [weak self] selectedTheme in
	  UserDataManager.marketColorTheme = selectedTheme
	  self?.updateMarketColorThemeButtonTitle()
	}
	selectionViewController.modalPresentationStyle = .overFullScreen
	selectionViewController.modalTransitionStyle = .crossDissolve
	self.present(selectionViewController, animated: true)
  }
  
  /// MOBIT 이용자 커뮤니티
  @IBAction func tapOnCommunity(_ sender: UIButton) {
	
	MobitAnalyticsUtil.sendClickEvent(event: .more_community)
	self.coordinator?.pushMobitCommunityViewController()
  }
  
  /// 현재 사용 중인 앱 버전
  func updateVersionLabel() {
	let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
	let versionParts = currentVersion.split(separator: ".")
	var fixedVersion = currentVersion
	
	if versionParts.count == 2 {
	  // 1.2 → 1.2.0 으로 변환
	  fixedVersion = currentVersion + ".0"
	}
	
	self.versionLabel.text = "앱 버전: \(fixedVersion)"
  }
  
  private func updateMarketColorThemeButtonTitle() {
	self.marketColorThemeButton.setTitle("캔들 색상 변경", for: .normal)
	self.riseColorPreviewView.backgroundColor = MarketColorPalette.riseColor
	self.fallColorPreviewView.backgroundColor = MarketColorPalette.fallColor
  }
  
  private func configurePreviewViews() {
	[self.riseColorPreviewView, self.fallColorPreviewView].forEach { previewView in
	  previewView?.layer.cornerRadius = 5
	  previewView?.layer.borderWidth = 0.5
	  previewView?.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
	  previewView?.clipsToBounds = true
	}
  }
}

private final class MarketColorThemeSelectionViewController: UIViewController {
  private let applyHandler: (UserDataManager.MarketColorTheme) -> Void
  private var pendingTheme: UserDataManager.MarketColorTheme
  
  private let dimView = UIView()
  private let containerView = UIView()
  private let titleLabel = UILabel()
  private let descriptionLabel = UILabel()
  private let optionsStackView = UIStackView()
  private let cancelButton = UIButton(type: .system)
  private let confirmButton = UIButton(type: .system)
  
  private lazy var optionViews: [MarketColorThemeOptionView] = [
	MarketColorThemeOptionView(
	  title: "한국형",
	  description: "(상승 빨강 / 하락 파랑)",
	  riseColor: MarketColorPalette.riseRedFallBlueRiseColor,
	  fallColor: MarketColorPalette.riseRedFallBlueFallColor,
	  theme: .riseRedFallBlue
	),
	MarketColorThemeOptionView(
	  title: "글로벌",
	  description: "(상승 초록 / 하락 빨강)",
	  riseColor: MarketColorPalette.riseGreenFallRedRiseColor,
	  fallColor: MarketColorPalette.riseGreenFallRedFallColor,
	  theme: .riseGreenFallRed
	)
  ]
  
  init(
	selectedTheme: UserDataManager.MarketColorTheme,
	applyHandler: @escaping (UserDataManager.MarketColorTheme) -> Void
  ) {
	self.pendingTheme = selectedTheme
	self.applyHandler = applyHandler
	super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
	super.viewDidLoad()
	self.configureUI()
	self.bindActions()
	self.updateSelectionUI()
  }
  
  private func configureUI() {
	self.view.backgroundColor = .clear
	
	self.dimView.backgroundColor = UIColor(red: 0.01, green: 0.06, blue: 0.11, alpha: 0.82)
	self.view.addSubview(self.dimView)
	
	self.containerView.backgroundColor = UIColor(hex: "#1C2636")
	self.containerView.layer.cornerRadius = 28
	self.containerView.layer.borderWidth = 1
	self.containerView.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
	self.containerView.layer.shadowColor = UIColor.black.withAlphaComponent(0.35).cgColor
	self.containerView.layer.shadowOpacity = 1
	self.containerView.layer.shadowRadius = 24
	self.containerView.layer.shadowOffset = CGSize(width: 0, height: 12)
	self.view.addSubview(self.containerView)
	
	self.titleLabel.text = "상승/하락 색상 설정"
	self.titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
	self.titleLabel.textColor = UIColor(hex: "#E8F1FF")
	self.titleLabel.numberOfLines = 0
	
	self.descriptionLabel.text = "차트와 가격의 상승/하락 지표 색상을 선택하세요."
	self.descriptionLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
	self.descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.76)
	self.descriptionLabel.numberOfLines = 0
	
	self.optionsStackView.axis = .vertical
	self.optionsStackView.spacing = 16
	
	self.cancelButton.setTitle("취소", for: .normal)
	self.cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
	self.cancelButton.setTitleColor(UIColor(hex: "#DCE7F8"), for: .normal)
	self.cancelButton.backgroundColor = UIColor(hex: "#253247")
	self.cancelButton.layer.cornerRadius = 18
	
	self.confirmButton.setTitle("변경하기", for: .normal)
	self.confirmButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
	self.confirmButton.setTitleColor(UIColor(hex: "#183247"), for: .normal)
	self.confirmButton.backgroundColor = UIColor(hex: "#79C9FF")
	self.confirmButton.layer.cornerRadius = 18
	self.confirmButton.layer.shadowColor = UIColor(hex: "#79C9FF").withAlphaComponent(0.45).cgColor
	self.confirmButton.layer.shadowOpacity = 1
	self.confirmButton.layer.shadowRadius = 14
	self.confirmButton.layer.shadowOffset = CGSize(width: 0, height: 8)
	
	[self.titleLabel, self.descriptionLabel, self.optionsStackView, self.cancelButton, self.confirmButton]
	  .forEach { self.containerView.addSubview($0) }
	
	self.optionViews.forEach { optionView in
	  self.optionsStackView.addArrangedSubview(optionView)
	}
	
	self.dimView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	self.containerView.snp.makeConstraints { make in
	  make.leading.trailing.equalToSuperview().inset(24)
	  make.centerY.equalToSuperview().offset(12)
	}
	
	self.titleLabel.snp.makeConstraints { make in
	  make.top.equalToSuperview().inset(28)
	  make.leading.trailing.equalToSuperview().inset(24)
	}
	
	self.descriptionLabel.snp.makeConstraints { make in
	  make.top.equalTo(self.titleLabel.snp.bottom).offset(16)
	  make.leading.trailing.equalToSuperview().inset(24)
	}
	
	self.optionsStackView.snp.makeConstraints { make in
	  make.top.equalTo(self.descriptionLabel.snp.bottom).offset(28)
	  make.leading.trailing.equalToSuperview().inset(24)
	}
	
	self.cancelButton.snp.makeConstraints { make in
	  make.top.equalTo(self.optionsStackView.snp.bottom).offset(28)
	  make.leading.equalToSuperview().inset(24)
	  make.height.equalTo(56)
	  make.bottom.equalToSuperview().inset(24)
	}
	
	self.confirmButton.snp.makeConstraints { make in
	  make.top.equalTo(self.cancelButton)
	  make.leading.equalTo(self.cancelButton.snp.trailing).offset(16)
	  make.trailing.equalToSuperview().inset(24)
	  make.width.equalTo(self.cancelButton)
	  make.height.equalTo(56)
	}
  }
  
  private func bindActions() {
	self.cancelButton.addTarget(self, action: #selector(self.tapOnCancelButton), for: .touchUpInside)
	self.confirmButton.addTarget(self, action: #selector(self.tapOnConfirmButton), for: .touchUpInside)
	self.optionViews.forEach { optionView in
	  optionView.addTarget(self, action: #selector(self.tapOnOptionView(_:)), for: .touchUpInside)
	}
  }
  
  private func updateSelectionUI() {
	self.optionViews.forEach { optionView in
	  optionView.isSelectedTheme = optionView.theme == self.pendingTheme
	}
  }
  
  @objc private func tapOnCancelButton() {
	self.dismiss(animated: true)
  }
  
  @objc private func tapOnConfirmButton() {
	self.dismiss(animated: true) {
	  self.applyHandler(self.pendingTheme)
	}
  }
  
  @objc private func tapOnOptionView(_ sender: MarketColorThemeOptionView) {
	self.pendingTheme = sender.theme
	self.updateSelectionUI()
  }
}

private final class MarketColorThemeOptionView: UIControl {
  let theme: UserDataManager.MarketColorTheme
  private let cardView = UIView()
  private let titleLabel = UILabel()
  private let descriptionLabel = UILabel()
  private let radioOuterView = UIView()
  private let radioInnerView = UIView()
  private let firstPaletteView = UIView()
  private let secondPaletteView = UIView()
  
  var isSelectedTheme: Bool = false {
	didSet {
	  self.updateSelectionStyle()
	}
  }
  
  init(
	title: String,
	description: String,
	riseColor: UIColor,
	fallColor: UIColor,
	theme: UserDataManager.MarketColorTheme
  ) {
	self.theme = theme
	super.init(frame: .zero)
	self.configureUI(title: title, description: description, riseColor: riseColor, fallColor: fallColor)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  private func configureUI(
	title: String,
	description: String,
	riseColor: UIColor,
	fallColor: UIColor
  ) {
	self.addSubview(self.cardView)
	self.cardView.addSubview(self.firstPaletteView)
	self.cardView.addSubview(self.secondPaletteView)
	self.cardView.addSubview(self.titleLabel)
	self.cardView.addSubview(self.descriptionLabel)
	self.cardView.addSubview(self.radioOuterView)
	self.radioOuterView.addSubview(self.radioInnerView)
	
	self.cardView.backgroundColor = UIColor(hex: "#223146")
	self.cardView.layer.cornerRadius = 22
	
	[self.firstPaletteView, self.secondPaletteView].forEach { paletteView in
	  paletteView.layer.cornerRadius = 18
	  paletteView.layer.shadowColor = UIColor.black.withAlphaComponent(0.22).cgColor
	  paletteView.layer.shadowOpacity = 1
	  paletteView.layer.shadowRadius = 4
	  paletteView.layer.shadowOffset = CGSize(width: 0, height: 2)
	}
	self.firstPaletteView.backgroundColor = riseColor
	self.secondPaletteView.backgroundColor = fallColor
	
	self.titleLabel.text = title
	self.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
	self.titleLabel.textColor = UIColor(hex: "#E6F0FF")
	
	self.descriptionLabel.text = description
	self.descriptionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
	self.descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.93)
	self.descriptionLabel.numberOfLines = 0
	
	self.radioOuterView.layer.cornerRadius = 14
	self.radioOuterView.layer.borderWidth = 2.5
	self.radioInnerView.layer.cornerRadius = 7
	
	self.cardView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	self.firstPaletteView.snp.makeConstraints { make in
	  make.leading.equalToSuperview().inset(18)
	  make.centerY.equalToSuperview()
	  make.width.height.equalTo(36)
	}
	
	self.secondPaletteView.snp.makeConstraints { make in
	  make.leading.equalTo(self.firstPaletteView.snp.trailing).offset(-10)
	  make.centerY.equalTo(self.firstPaletteView)
	  make.width.height.equalTo(36)
	}
	
	self.titleLabel.snp.makeConstraints { make in
	  make.top.equalToSuperview().inset(18)
	  make.leading.equalTo(self.secondPaletteView.snp.trailing).offset(22)
	  make.trailing.lessThanOrEqualTo(self.radioOuterView.snp.leading).offset(-16)
	}
	
	self.descriptionLabel.snp.makeConstraints { make in
	  make.top.equalTo(self.titleLabel.snp.bottom).offset(4)
	  make.leading.equalTo(self.titleLabel)
	  make.trailing.lessThanOrEqualTo(self.radioOuterView.snp.leading).offset(-16)
	  make.bottom.equalToSuperview().inset(18)
	}
	
	self.radioOuterView.snp.makeConstraints { make in
	  make.trailing.equalToSuperview().inset(18)
	  make.centerY.equalToSuperview()
	  make.width.height.equalTo(28)
	}
	
	self.radioInnerView.snp.makeConstraints { make in
	  make.center.equalToSuperview()
	  make.width.height.equalTo(14)
	}
  }
  
  private func updateSelectionStyle() {
	if self.isSelectedTheme {
	  self.cardView.layer.borderWidth = 2
	  self.cardView.layer.borderColor = UIColor(hex: "#7FCBFF").cgColor
	  self.cardView.backgroundColor = UIColor(hex: "#2A384E")
	  self.radioOuterView.layer.borderColor = UIColor(hex: "#7FCBFF").cgColor
	  self.radioInnerView.backgroundColor = UIColor(hex: "#7FCBFF")
	} else {
	  self.cardView.layer.borderWidth = 0
	  self.cardView.layer.borderColor = UIColor.clear.cgColor
	  self.cardView.backgroundColor = UIColor(hex: "#223146")
	  self.radioOuterView.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
	  self.radioInnerView.backgroundColor = .clear
	}
  }
  
  override var intrinsicContentSize: CGSize {
	CGSize(width: UIView.noIntrinsicMetric, height: 118)
  }
}
