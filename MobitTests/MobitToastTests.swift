import XCTest
import UIKit
@testable import Mobit

final class MobitToastTests: XCTestCase {
  @MainActor
  func testTopAndBottomRespectSafeAreaAnchorAndThemesWithoutBlockingScreen() throws {
    // 실제 뷰 계층에 색상과 Auto Layout을 전달한다.
    let window = makeWindow()
    defer { window.isHidden = true }
    // 토스트가 특정 주문 패널 대신 화면 전체 너비를 기준으로 배치되는지 확인한다.
    let host = try XCTUnwrap(window.rootViewController?.view)
    // 하단 배너 등 토스트가 가리면 안 되는 영역을 나타낸다.
    let banner = UIView()
    host.addSubview(banner)
    banner.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      banner.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      banner.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      banner.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor),
      banner.heightAnchor.constraint(equalToConstant: 50)
    ])
    // 같은 소유자가 새 안내로 교체하는 실제 사용 방식을 유지한다.
    let presenter = MobitToastPresenter()
    defer { presenter.dismiss() }
    for style in [UIUserInterfaceStyle.light, .dark, .light] {
      window.overrideUserInterfaceStyle = style
      if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
      for position in [MobitToastPresenter.Position.top, .bottom] {
        presenter.show("포지션을 종료했어요", in: host, position: position, above: banner.topAnchor)
        if #available(iOS 17.0, *) { window.updateTraitsIfNeeded() }
        host.layoutIfNeeded()
        // 표시된 뷰를 통해 위치·터치·색상을 관찰한다.
        let toast = try toast(in: host)
        // 화면에 실제 그려지는 메시지의 대비를 확인한다.
        let label = try messageLabel(in: toast)
        XCTAssertEqual(toast.traitCollection.userInterfaceStyle, style)
        XCTAssertEqual(toast.frame.midX, host.safeAreaLayoutGuide.layoutFrame.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(toast.frame.minX, host.safeAreaLayoutGuide.layoutFrame.minX + 19.5)
        XCTAssertLessThanOrEqual(toast.frame.maxX, host.safeAreaLayoutGuide.layoutFrame.maxX - 19.5)
        XCTAssertFalse(toast.hasAmbiguousLayout)
        XCTAssertEqual(label.text, "포지션을 종료했어요")
        XCTAssertEqual(toast.accessibilityLabel, label.text)
        XCTAssertEqual(toast.layer.cornerRadius, toast.bounds.height / 2, accuracy: 0.5)
        if position == .top {
          XCTAssertEqual(toast.frame.minY, host.safeAreaLayoutGuide.layoutFrame.minY + 10, accuracy: 0.5)
        } else {
          XCTAssertEqual(toast.frame.maxY, banner.frame.minY - 20, accuracy: 0.5)
        }
        XCTAssertGreaterThanOrEqual(contrast(of: label.textColor, against: try XCTUnwrap(toast.backgroundColor), traits: toast.traitCollection), 4.5)
        XCTAssertTrue(host.hitTest(CGPoint(x: 5, y: host.bounds.midY), with: nil) === host)
        XCTAssertEqual(host.subviews.filter { $0.accessibilityIdentifier == "mobitToast" }.count, 1)
        XCTAssertEqual((toast.gestureRecognizers?.first as? UISwipeGestureRecognizer)?.direction, position == .top ? .up : .down)
      }
    }
  }

  @MainActor
  func testLongMessageWrapsAtAccessibilityTextSizeOnSmallScreen() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("traitOverrides 검증은 iOS 17 이상에서 실행합니다.") }
    // 접근성 글자 크기를 실제 뷰 트리에 적용한다.
    let window = makeWindow()
    defer { window.isHidden = true }
    window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    window.updateTraitsIfNeeded()
    // 320pt 화면에서도 메시지를 한 줄로 줄이거나 자르지 않아야 한다.
    let host = try XCTUnwrap(window.rootViewController?.view)
    // 번역으로 길어진 종료 결과를 재현한다.
    let message = "Your position is closed. Check your history."
    // 두 표시 위치 모두 같은 줄바꿈 정책을 사용한다.
    let presenter = MobitToastPresenter()
    defer { presenter.dismiss() }
    for position in [MobitToastPresenter.Position.top, .bottom] {
      presenter.show(message, in: host, position: position)
      window.updateTraitsIfNeeded()
      host.layoutIfNeeded()
      // 실제 라벨의 글자 크기와 필요한 높이를 비교한다.
      let toast = try toast(in: host)
      // 접근성 확대에도 원문이 보존된 라벨이다.
      let label = try messageLabel(in: toast)
      XCTAssertEqual(label.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
      XCTAssertGreaterThan(label.font.pointSize, 15)
      XCTAssertEqual(label.numberOfLines, 0)
      XCTAssertEqual(label.text, message)
      XCTAssertGreaterThan(label.bounds.height, label.font.lineHeight)
      XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
      XCTAssertTrue(host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(toast.frame))
    }
  }

  @MainActor
  func testReplacementCancelsOldDeadlineAndEachMessageRemainsForThreeSeconds() throws {
    // 애니메이션 시간과 표시 유지 시간을 분리해 실제 타이머를 검증한다.
    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(false)
    defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
    // 자동 닫기와 교체가 같은 표시 영역에서 발생하도록 한다.
    let window = makeWindow()
    defer { window.isHidden = true }
    // 토스트를 올릴 실제 화면이다.
    let host = try XCTUnwrap(window.rootViewController?.view)
    // 늦게 실행되는 이전 작업이 현재 메시지를 닫아서는 안 된다.
    let presenter = MobitToastPresenter()
    defer { presenter.dismiss() }
    XCTAssertEqual(MobitToastPresenter.displayDuration, 3)
    presenter.show("첫 번째 결과", in: host)
    waitForUpdates(2.7)
    XCTAssertEqual(try toast(in: host).accessibilityLabel, "첫 번째 결과")
    presenter.show("새로운 결과", in: host)
    waitForUpdates(0.6)
    XCTAssertEqual(try toast(in: host).accessibilityLabel, "새로운 결과")
    waitForUpdates(2.6)
    XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
  }

  @MainActor
  func testDismissEscapeAndOwnerReleaseRemoveToastImmediately() throws {
    // 접근성 닫기의 제거 결과를 애니메이션과 분리한다.
    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(false)
    defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
    // 화면 이탈과 소유자 해제 상황을 재현한다.
    let window = makeWindow()
    defer { window.isHidden = true }
    // 닫힌 토스트가 화면에 남지 않는지 확인할 호스트다.
    let host = try XCTUnwrap(window.rootViewController?.view)
    // 표시 중 해제를 통해 타이머의 강한 참조 누수도 확인한다.
    var presenter: MobitToastPresenter? = MobitToastPresenter()
    // 토스트가 표시 소유자를 붙잡지 않아야 한다.
    weak var releasedPresenter: MobitToastPresenter?
    releasedPresenter = presenter
    presenter?.show("결과", in: host)
    XCTAssertTrue(try toast(in: host).accessibilityPerformEscape())
    // 접근성 닫기는 퇴장 완료에서 제거하므로 3초 자동 닫기보다 먼저 끝나는지 기다린다.
    let escaped = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        !host.subviews.contains { $0.accessibilityIdentifier == "mobitToast" }
      },
      object: nil
    )
    wait(for: [escaped], timeout: 2)
    XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
    presenter?.show("다음 결과", in: host)
    presenter?.dismiss()
    XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
    presenter?.show("해제할 결과", in: host)
    presenter = nil
    XCTAssertNil(releasedPresenter)
    XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "mobitToast" })
  }

  @MainActor
  private func makeWindow() -> UIWindow {
    // 외부 화면·네트워크 동작 없이 작은 화면의 UIKit 배치를 구성한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
  }

  @MainActor
  private func toast(in host: UIView) throws -> UIView {
    try XCTUnwrap(host.subviews.first { $0.accessibilityIdentifier == "mobitToast" })
  }

  @MainActor
  private func messageLabel(in toast: UIView) throws -> UILabel {
    try XCTUnwrap(toast.subviews.first { $0.accessibilityIdentifier == "mobitToastMessage" } as? UILabel)
  }

  @MainActor
  private func waitForUpdates(_ duration: TimeInterval) {
    // 메인 큐에서 자동 닫기 작업이 실제로 실행되도록 기다린다.
    let update = expectation(description: "Toast timer")
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { update.fulfill() }
    wait(for: [update], timeout: duration + 1)
  }

  private func contrast(of foreground: UIColor, against background: UIColor, traits: UITraitCollection) -> Double {
    func linearComponent(_ value: CGFloat) -> Double {
      // 명시적인 Double 계산으로 sRGB 감마 보정의 타입 추론을 제한한다.
      let component = Double(value)
      if component <= 0.04045 { return component / 12.92 }
      return pow((component + 0.055) / 1.055, 2.4)
    }
    func luminance(_ color: UIColor) -> Double {
      // 동적 색상을 현재 테마의 RGB 성분으로 변환한다.
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      return linearComponent(red) * 0.2126 + linearComponent(green) * 0.7152 + linearComponent(blue) * 0.0722
    }
    // 밝은 쪽을 분자로 두어 두 색상의 명암 대비를 비교한다.
    let foregroundLuminance = luminance(foreground), backgroundLuminance = luminance(background)
    return (max(foregroundLuminance, backgroundLuminance) + 0.05) / (min(foregroundLuminance, backgroundLuminance) + 0.05)
  }
}
