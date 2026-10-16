import SkeletonView
import UIKit

final class AdBannerLoadingView: UIView {
  // 광고를 기다리는 동안만 자리를 확보하고 수신 후에는 SDK 높이를 따른다.
  private var loadingHeightConstraint: NSLayoutConstraint?

  init(height: CGFloat) {
    super.init(frame: .zero)
    isHidden = true
    isSkeletonable = true
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    loadingHeightConstraint = heightAnchor.constraint(equalToConstant: height)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateSkeletonVisibility()
  }

  func setLoading(_ loading: Bool) {
    loadingHeightConstraint?.isActive = loading
    isHidden = !loading
    updateSkeletonVisibility()
  }

  private func updateSkeletonVisibility() {
    guard !isHidden, window != nil else {
      if sk.isSkeletonActive {
        hideSkeleton(reloadDataAfter: false, transition: .none)
      }
      return
    }
    guard !sk.isSkeletonActive else { return }
    showAnimatedGradientSkeleton(transition: .none)
  }
}
