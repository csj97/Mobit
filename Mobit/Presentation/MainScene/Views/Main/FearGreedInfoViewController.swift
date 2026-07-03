//
//  FearGreedInfoViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/2/26.
//

import UIKit
import SnapKit
import Then

/// 공포·탐욕 지수의 의미를 설명하는 바텀 시트.
/// 매매 신호가 아닌 '참고용 심리 지표'임을 명확히 안내한다.
final class FearGreedInfoViewController: UIViewController {

  private let scrollView = UIScrollView()
  private let contentStack = UIStackView().then {
    $0.axis = .vertical
    $0.alignment = .fill
    $0.spacing = 16
  }

  private let closeButton = UIButton(type: .system).then {
    $0.setImage(UIImage(systemName: "xmark"), for: .normal)
    $0.tintColor = UIColor(hex: "#868E96")
    $0.accessibilityLabel = "닫기"
  }

  private let fearGreedIndex: FearGreedIndex?

  init(fearGreedIndex: FearGreedIndex?) {
    self.fearGreedIndex = fearGreedIndex
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white
    setUp()
  }

  private func setUp() {
    closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

    view.addSubview(closeButton)
    view.addSubview(scrollView)
    scrollView.addSubview(contentStack)

    closeButton.snp.makeConstraints { make in
      make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
      make.trailing.equalToSuperview().inset(16)
      make.width.height.equalTo(28)
    }
    scrollView.snp.makeConstraints { make in
      make.top.equalTo(closeButton.snp.bottom).offset(4)
      make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
    }
    contentStack.snp.makeConstraints { make in
      make.top.bottom.equalToSuperview().inset(4)
      make.leading.trailing.equalToSuperview().inset(20)
      make.width.equalTo(scrollView.frameLayoutGuide).offset(-40)
    }

    // 지수 값이 있으면 최상단에 게이지 카드를 배치한다.
    if let index = fearGreedIndex {
      let gaugeView = FearGreedIndexView()
      gaugeView.configure(with: index)
      gaugeView.setInfoButtonHidden(true)
      gaugeView.snp.makeConstraints { $0.height.equalTo(88) }
      contentStack.addArrangedSubview(gaugeView)
    }

    contentStack.addArrangedSubview(makeTitleLabel("공포·탐욕 지수란?"))
    contentStack.addArrangedSubview(makeBodyLabel(
      "시장 전체의 투자 심리를 0부터 100까지 숫자로 나타낸 지표입니다. "
      + "숫자가 낮을수록 공포(불안), 높을수록 탐욕(과열)에 가깝습니다."
    ))

    contentStack.addArrangedSubview(makeSectionLabel("단계별 의미"))
    FearGreedLevel.allCases.forEach { contentStack.addArrangedSubview(makeLegendRow(level: $0)) }

    contentStack.addArrangedSubview(makeSectionLabel("어떻게 활용하나요?"))
    contentStack.addArrangedSubview(makeBodyLabel(
      "군중이 극단적 공포일 때가 오히려 저점 매수 기회로, 극단적 탐욕일 때가 조정 신호로 해석되기도 합니다. "
      + "다만 절대적인 매매 신호가 아니라 시장 분위기를 참고하는 지표로만 활용하세요."
    ))

    contentStack.addArrangedSubview(makeCaptionLabel("데이터 제공: CoinMarketCap"))
  }

  @objc private func didTapClose() {
    dismiss(animated: true)
  }
}

// MARK: - View Builders
private extension FearGreedInfoViewController {

  func makeTitleLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont(name: "SUIT-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
    label.textColor = .black
    label.numberOfLines = 0
    return label
  }

  func makeSectionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont(name: "SUIT-Bold", size: 16) ?? .systemFont(ofSize: 16, weight: .bold)
    label.textColor = .black
    return label
  }

  func makeBodyLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont(name: "SUIT-Medium", size: 14) ?? .systemFont(ofSize: 14)
    label.textColor = UIColor(hex: "#495057")
    label.numberOfLines = 0
    return label
  }

  func makeCaptionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont(name: "SUIT-Medium", size: 12) ?? .systemFont(ofSize: 12)
    label.textColor = UIColor(hex: "#ADB5BD")
    return label
  }

  func makeLegendRow(level: FearGreedLevel) -> UIView {
    let dot = UIView()
    dot.backgroundColor = level.color
    dot.layer.cornerRadius = 6

    let dotContainer = UIView()
    dotContainer.addSubview(dot)
    dot.snp.makeConstraints { make in
      make.top.equalToSuperview().offset(3)
      make.leading.trailing.equalToSuperview()
      make.width.height.equalTo(12)
    }

    let nameLabel = UILabel()
    nameLabel.text = "\(level.title)  (\(level.range))"
    nameLabel.font = UIFont(name: "SUIT-Bold", size: 14) ?? .systemFont(ofSize: 14, weight: .bold)
    nameLabel.textColor = .black

    let descLabel = UILabel()
    descLabel.text = level.summary
    descLabel.font = UIFont(name: "SUIT-Medium", size: 13) ?? .systemFont(ofSize: 13)
    descLabel.textColor = UIColor(hex: "#868E96")
    descLabel.numberOfLines = 0

    let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
    textStack.axis = .vertical
    textStack.spacing = 2

    let row = UIStackView(arrangedSubviews: [dotContainer, textStack])
    row.axis = .horizontal
    row.alignment = .top
    row.spacing = 10
    dotContainer.snp.makeConstraints { $0.width.equalTo(12) }
    return row
  }
}
