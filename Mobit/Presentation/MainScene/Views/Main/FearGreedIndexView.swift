//
//  FearGreedIndexView.swift
//  Mobit
//
//  Created by 조성재 on 7/1/26.
//

import UIKit
import SnapKit
import Then

/// 거래소 화면 하단에 고정 노출되는 시장 공포·탐욕 지수 카드.
/// 색상만으로 상태를 구분하지 않도록 값(숫자)과 한글 단계 라벨을 함께 표시한다.
final class FearGreedIndexView: UIView {

  /// (i) 버튼 탭 시 설명 화면을 띄우기 위한 콜백
  var onInfoTapped: (() -> Void)?

  private let titleLabel = UILabel().then {
    $0.text = "시장 공포·탐욕 지수"
    $0.font = UIFont(name: "SUIT-SemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
    $0.textColor = .black
  }

  private let infoButton = UIButton(type: .system).then {
    $0.setImage(UIImage(systemName: "info.circle"), for: .normal)
    $0.tintColor = UIColor(hex: "#868E96")
    $0.accessibilityLabel = "공포·탐욕 지수 설명"
  }

  private let badgeContainer = UIView().then {
    $0.layer.cornerRadius = 11
    $0.clipsToBounds = true
  }

  private let badgeLabel = UILabel().then {
    $0.font = UIFont(name: "SUIT-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .bold)
    $0.textColor = .white
    $0.textAlignment = .center
  }

  private let track = UIView().then {
    $0.backgroundColor = UIColor(hex: "#E9ECEF")
    $0.clipsToBounds = true
  }

  private let fillView = UIView().then {
    $0.clipsToBounds = true
  }

  // 그라디언트는 트랙 전체 폭(파랑→빨강) 기준으로 그리고, fillView가 지수 위치까지만 잘라 보여준다.
  private let gradientLayer = CAGradientLayer()

  private let fearLabel = FearGreedIndexView.captionLabel(text: "공포")
  private let neutralLabel = FearGreedIndexView.captionLabel(text: "중립")
  private let greedLabel = FearGreedIndexView.captionLabel(text: "탐욕")

  private var ratio: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) { fatalError() }

  private func setUp() {
    backgroundColor = UIColor(hex: "#F2F4F6")
    layer.cornerRadius = 12
    isAccessibilityElement = true

    gradientLayer.colors = [UIColor(hex: "#4C6EF5").cgColor, UIColor(hex: "#FA5252").cgColor]
    gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
    gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
    fillView.layer.addSublayer(gradientLayer)

    infoButton.addTarget(self, action: #selector(didTapInfo), for: .touchUpInside)

    badgeContainer.addSubview(badgeLabel)
    track.addSubview(fillView)
    [titleLabel, infoButton, badgeContainer, track, fearLabel, neutralLabel, greedLabel].forEach { addSubview($0) }

    titleLabel.snp.makeConstraints { make in
      make.top.equalToSuperview().inset(14)
      make.leading.equalToSuperview().inset(16)
    }
    infoButton.snp.makeConstraints { make in
      make.leading.equalTo(titleLabel.snp.trailing).offset(4)
      make.centerY.equalTo(titleLabel)
      make.width.height.equalTo(20)
    }
    badgeContainer.snp.makeConstraints { make in
      make.centerY.equalTo(titleLabel)
      make.trailing.equalToSuperview().inset(16)
    }
    badgeLabel.snp.makeConstraints { make in
      make.top.bottom.equalToSuperview().inset(4)
      make.leading.trailing.equalToSuperview().inset(10)
    }
    track.snp.makeConstraints { make in
      make.top.equalTo(titleLabel.snp.bottom).offset(14)
      make.leading.trailing.equalToSuperview().inset(16)
      make.height.equalTo(6)
    }
    fearLabel.snp.makeConstraints { make in
      make.top.equalTo(track.snp.bottom).offset(8)
      make.leading.equalToSuperview().inset(16)
    }
    neutralLabel.snp.makeConstraints { make in
      make.top.equalTo(fearLabel)
      make.centerX.equalToSuperview()
    }
    greedLabel.snp.makeConstraints { make in
      make.top.equalTo(fearLabel)
      make.trailing.equalToSuperview().inset(16)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    track.layer.cornerRadius = track.bounds.height / 2
    let filledWidth = track.bounds.width * ratio
    fillView.frame = CGRect(x: 0, y: 0, width: filledWidth, height: track.bounds.height)
    fillView.layer.cornerRadius = track.bounds.height / 2
    gradientLayer.frame = CGRect(x: 0, y: 0, width: track.bounds.width, height: track.bounds.height)
  }

  @objc private func didTapInfo() {
    onInfoTapped?()
  }

  // 설명 시트 안에서 재사용할 때는 (i) 버튼이 필요 없다.
  func setInfoButtonHidden(_ hidden: Bool) {
    infoButton.isHidden = hidden
  }

  func configure(with index: FearGreedIndex) {
    let value = max(0, min(100, index.value))
    ratio = CGFloat(value) / 100
    let level = FearGreedLevel(value: value)
    badgeLabel.text = "\(value) · \(level.title)"
    badgeContainer.backgroundColor = level.color
    accessibilityLabel = "시장 공포탐욕 지수 \(value), \(level.title)"
    setNeedsLayout()
  }

  private static func captionLabel(text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont(name: "SUIT-Medium", size: 11) ?? .systemFont(ofSize: 11, weight: .medium)
    label.textColor = UIColor(hex: "#868E96")
    return label
  }
}

enum FearGreedLevel: CaseIterable {
  case extremeFear, fear, neutral, greed, extremeGreed

  init(value: Int) {
    switch value {
    case ..<25: self = .extremeFear
    case ..<45: self = .fear
    case ..<55: self = .neutral
    case ..<75: self = .greed
    default: self = .extremeGreed
    }
  }

  var title: String {
    switch self {
    case .extremeFear: return "극단적 공포"
    case .fear: return "공포"
    case .neutral: return "중립"
    case .greed: return "탐욕"
    case .extremeGreed: return "극단적 탐욕"
    }
  }

  var range: String {
    switch self {
    case .extremeFear: return "0 – 24"
    case .fear: return "25 – 44"
    case .neutral: return "45 – 54"
    case .greed: return "55 – 74"
    case .extremeGreed: return "75 – 100"
    }
  }

  var summary: String {
    switch self {
    case .extremeFear: return "투매·과매도 분위기. 역발상 관점에서 저점 매수 관심 구간."
    case .fear: return "불안 심리가 우세하고 매도 압력이 큰 상태."
    case .neutral: return "매수·매도 심리가 균형을 이룬 상태."
    case .greed: return "기대·매수 심리가 우세한 상태."
    case .extremeGreed: return "과열·FOMO 분위기. 조정 가능성에 유의할 구간."
    }
  }

  // 국내 관례상 하락/공포는 파랑, 상승/탐욕은 빨강
  var color: UIColor {
    switch self {
    case .extremeFear: return UIColor(hex: "#2B4AC9")
    case .fear: return UIColor(hex: "#4C6EF5")
    case .neutral: return UIColor(hex: "#868E96")
    case .greed: return UIColor(hex: "#FA5252")
    case .extremeGreed: return UIColor(hex: "#E03131")
    }
  }
}
