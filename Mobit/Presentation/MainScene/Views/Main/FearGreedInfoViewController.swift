//
//  FearGreedInfoViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/2/26.
//

import UIKit
import SnapKit
import Then
import RxSwift

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
    $0.tintColor = .mobitColors(.textTertiary)
    $0.accessibilityLabel = "닫기"
  }

  // 시트를 열 때 메인의 최근 지수를 확인하고 필요한 경우 조회한다.
  private let reactor: MainReactor
  // 시트가 닫히면 화면 상태 구독도 해제한다.
  private let disposeBag = DisposeBag()

  init(reactor: MainReactor) {
    self.reactor = reactor
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .mobitColors(.backgroundPrimary)
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

    bindIndexCard()

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

  private func bindIndexCard() {
    // 로딩 중에도 같은 카드와 트랙을 사용해 아래 설명의 위치를 유지한다.
    let gauge = FearGreedIndexView()
    // 실패 후에는 다음 시트 진입 때 재시도한다.
    let errorLabel = makeBodyLabel(FuturesText.text("fear_greed_load_failed"))
    gauge.setInfoButtonHidden(true)
    contentStack.addArrangedSubview(gauge)
    contentStack.addArrangedSubview(errorLabel)
    // 숨겨진 스택 뷰의 높이 제약과 충돌하지 않게 한다.
    gauge.snp.makeConstraints { $0.height.equalTo(88).priority(999) }

    reactor.state.map(\.fearGreedState)
      .distinctUntilChanged()
      .observe(on: MainScheduler.instance)
      .subscribe(onNext: { state in
        gauge.isHidden = state == .failed
        errorLabel.isHidden = state != .failed
        gauge.setLoading(state == .idle || state == .loading)
        if case .loaded(let index, _) = state {
          gauge.configure(with: index)
        }
      })
      .disposed(by: disposeBag)
    reactor.action.onNext(.loadFearGreedIndex)
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
    label.font = .systemFont(ofSize: 20, weight: .bold)
    label.textColor = .mobitColors(.textPrimary)
    label.numberOfLines = 0
    return label
  }

  func makeSectionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: 16, weight: .bold)
    label.textColor = .mobitColors(.textPrimary)
    return label
  }

  func makeBodyLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .mobitColors(.textSecondary)
    label.numberOfLines = 0
    return label
  }

  func makeCaptionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .mobitColors(.textTertiary)
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
    nameLabel.font = .systemFont(ofSize: 14, weight: .bold)
    nameLabel.textColor = .mobitColors(.textPrimary)

    let descLabel = UILabel()
    descLabel.text = level.summary
    descLabel.font = .systemFont(ofSize: 13, weight: .medium)
    descLabel.textColor = .mobitColors(.textSecondary)
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
