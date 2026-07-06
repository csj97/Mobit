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
  @IBOutlet weak var settingsButton: UIButton!
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
	self.expandSettingsRowTouchArea()
  }

  /// "설정" 행 전체를 터치 영역으로 만든다 (행 위에 투명 버튼을 덮음)
  private func expandSettingsRowTouchArea() {
	guard let settingsRow = self.settingsButton.superview else { return }
	let overlayButton = UIButton(type: .custom)
	overlayButton.backgroundColor = .clear
	overlayButton.addTarget(
	  self, action: #selector(self.tapOnSettingsButton(_:)), for: .touchUpInside
	)
	settingsRow.addSubview(overlayButton)
	overlayButton.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
  }

  func setData() {
	self.updateVersionLabel()
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
  
  @IBAction func tapOnSettingsButton(_ sender: UIButton) {
	let settingsViewController = AppSettingsViewController()
	settingsViewController.modalPresentationStyle = .overFullScreen
	settingsViewController.modalTransitionStyle = .crossDissolve
	self.present(settingsViewController, animated: true)
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
}

private final class AppSettingsViewController: UIViewController {
  private var pendingTheme: UserDataManager.MarketColorTheme = UserDataManager.marketColorTheme

  private let dimView = UIView()
  private let containerView = UIView()
  private let titleLabel = UILabel()
  private let descriptionLabel = UILabel()
  private let optionsStackView = UIStackView()
  private let tintRow = UIView()
  private let tintTitleLabel = UILabel()
  private let tintSwitch = UISwitch()
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
  
  init() {
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
	
	self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.15)
	self.view.addSubview(self.dimView)

	// 앱 표준 alert(MobitAlertViewController)와 동일한 라이트 스타일
	self.containerView.backgroundColor = .white
	self.containerView.layer.cornerRadius = 8
	self.containerView.clipsToBounds = true
	self.view.addSubview(self.containerView)

	self.titleLabel.text = "설정"
	self.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
	self.titleLabel.textColor = .black
	self.titleLabel.numberOfLines = 0

	// 캔들 색상 섹션 헤더
	self.descriptionLabel.text = "캔들 색상"
	self.descriptionLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
	self.descriptionLabel.textColor = UIColor(white: 0.33, alpha: 1)
	self.descriptionLabel.numberOfLines = 0

	self.optionsStackView.axis = .vertical
	self.optionsStackView.spacing = 12

	self.tintTitleLabel.text = "시세 배경 색상 표시"
	self.tintTitleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
	self.tintTitleLabel.textColor = .black
	self.tintSwitch.onTintColor = UIColor.systemBlue
	self.tintSwitch.isOn = UserDataManager.marketCellTintEnabled
	self.tintSwitch.setContentHuggingPriority(.required, for: .horizontal)

	self.cancelButton.setTitle("취소", for: .normal)
	self.cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 18)
	self.cancelButton.setTitleColor(UIColor(hex: "#F85858"), for: .normal)
	self.cancelButton.backgroundColor = .white

	self.confirmButton.setTitle("변경하기", for: .normal)
	self.confirmButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
	self.confirmButton.setTitleColor(UIColor.hexStringToUIColor(hex: "#006cd1"), for: .normal)
	self.confirmButton.backgroundColor = .white
	
	// 버튼 위 구분선 + 버튼 사이 세로 구분선 (MobitAlert 버튼 행 스타일)
	let topDivider = UIView()
	topDivider.backgroundColor = UIColor(white: 0.33, alpha: 0.1)
	let buttonDivider = UIView()
	buttonDivider.backgroundColor = UIColor(white: 0.66, alpha: 0.26)

	self.tintRow.addSubview(self.tintTitleLabel)
	self.tintRow.addSubview(self.tintSwitch)

	[self.titleLabel, self.descriptionLabel, self.optionsStackView, self.tintRow, topDivider, self.cancelButton, buttonDivider, self.confirmButton]
	  .forEach { self.containerView.addSubview($0) }

	self.optionViews.forEach { optionView in
	  self.optionsStackView.addArrangedSubview(optionView)
	}

	self.dimView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}

	self.containerView.snp.makeConstraints { make in
	  make.leading.trailing.equalToSuperview().inset(25)
	  make.centerY.equalToSuperview()
	}

	self.titleLabel.snp.makeConstraints { make in
	  make.top.equalToSuperview().inset(24)
	  make.leading.trailing.equalToSuperview().inset(20)
	}

	self.descriptionLabel.snp.makeConstraints { make in
	  make.top.equalTo(self.titleLabel.snp.bottom).offset(10)
	  make.leading.trailing.equalToSuperview().inset(20)
	}

	self.optionsStackView.snp.makeConstraints { make in
	  make.top.equalTo(self.descriptionLabel.snp.bottom).offset(12)
	  make.leading.trailing.equalToSuperview().inset(20)
	}

	// 시세 배경 색상 표시 토글 행
	self.tintRow.snp.makeConstraints { make in
	  make.top.equalTo(self.optionsStackView.snp.bottom).offset(18)
	  make.leading.trailing.equalToSuperview().inset(20)
	}
	self.tintTitleLabel.snp.makeConstraints { make in
	  make.leading.centerY.equalToSuperview()
	}
	self.tintSwitch.snp.makeConstraints { make in
	  make.trailing.top.bottom.equalToSuperview()
	  make.leading.greaterThanOrEqualTo(self.tintTitleLabel.snp.trailing).offset(12)
	}

	topDivider.snp.makeConstraints { make in
	  make.top.equalTo(self.tintRow.snp.bottom).offset(18)
	  make.leading.trailing.equalToSuperview()
	  make.height.equalTo(1)
	}

	self.cancelButton.snp.makeConstraints { make in
	  make.top.equalTo(topDivider.snp.bottom)
	  make.leading.bottom.equalToSuperview()
	  make.height.equalTo(52)
	}

	buttonDivider.snp.makeConstraints { make in
	  make.top.bottom.equalTo(self.cancelButton)
	  make.leading.equalTo(self.cancelButton.snp.trailing)
	  make.width.equalTo(1)
	}

	self.confirmButton.snp.makeConstraints { make in
	  make.top.bottom.equalTo(self.cancelButton)
	  make.leading.equalTo(buttonDivider.snp.trailing)
	  make.trailing.equalToSuperview()
	  make.width.equalTo(self.cancelButton)
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
	UserDataManager.marketColorTheme = self.pendingTheme
	UserDataManager.marketCellTintEnabled = self.tintSwitch.isOn
	self.dismiss(animated: true)
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
	let textStack = UIStackView(arrangedSubviews: [self.titleLabel, self.descriptionLabel])
	textStack.axis = .vertical
	textStack.alignment = .leading
	textStack.spacing = 4
	self.cardView.addSubview(textStack)
	self.cardView.addSubview(self.radioOuterView)
	self.radioOuterView.addSubview(self.radioInnerView)
	
	self.cardView.backgroundColor = UIColor.mobitColors(.lightGrayBG)
	self.cardView.layer.cornerRadius = 12
	// 카드/하위 뷰가 터치를 가로채면 UIControl(touchUpInside)이 동작하지 않으므로 비활성화
	self.cardView.isUserInteractionEnabled = false
	
	[self.firstPaletteView, self.secondPaletteView].forEach { paletteView in
	  paletteView.layer.cornerRadius = 12
	  paletteView.layer.shadowColor = UIColor.black.withAlphaComponent(0.22).cgColor
	  paletteView.layer.shadowOpacity = 1
	  paletteView.layer.shadowRadius = 4
	  paletteView.layer.shadowOffset = CGSize(width: 0, height: 2)
	}
	self.firstPaletteView.backgroundColor = riseColor
	self.secondPaletteView.backgroundColor = fallColor
	
	self.titleLabel.text = title
	self.titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
	self.titleLabel.textColor = .black
	
	self.descriptionLabel.text = description
	self.descriptionLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
	self.descriptionLabel.textColor = .darkGray
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
	  make.width.height.equalTo(24)
	}
	
	self.secondPaletteView.snp.makeConstraints { make in
	  make.leading.equalTo(self.firstPaletteView.snp.trailing).offset(-10)
	  make.centerY.equalTo(self.firstPaletteView)
	  make.width.height.equalTo(24)
	}
	
	textStack.snp.makeConstraints { make in
	  make.leading.equalTo(self.secondPaletteView.snp.trailing).offset(22)
	  make.trailing.lessThanOrEqualTo(self.radioOuterView.snp.leading).offset(-16)
	  make.centerY.equalToSuperview()
	  make.top.greaterThanOrEqualToSuperview().inset(14)
	  make.bottom.lessThanOrEqualToSuperview().inset(14)
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
	  self.cardView.layer.borderWidth = 1.5
	  self.cardView.layer.borderColor = UIColor.hexStringToUIColor(hex: "#006cd1").cgColor
	  self.cardView.backgroundColor = UIColor.mobitColors(.blue_E8F9FF)
	  self.radioOuterView.layer.borderColor = UIColor.hexStringToUIColor(hex: "#006cd1").cgColor
	  self.radioInnerView.backgroundColor = UIColor.hexStringToUIColor(hex: "#006cd1")
	} else {
	  self.cardView.layer.borderWidth = 0
	  self.cardView.layer.borderColor = UIColor.clear.cgColor
	  self.cardView.backgroundColor = UIColor.hexStringToUIColor(hex: "#f2f2f2")
	  self.radioOuterView.layer.borderColor = UIColor.mobitColors(.lineLightGray).cgColor
	  self.radioInnerView.backgroundColor = .clear
	}
  }
  
  override var intrinsicContentSize: CGSize {
	CGSize(width: UIView.noIntrinsicMetric, height: 88)
  }
}
