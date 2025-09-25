//
//  MobitLottieView.swift
//  Mobit
//
//  Created by 조성재 on 9/25/25.
//

import Foundation
import UIKit
import Then
import Lottie
import SnapKit

class MobitLottieView: UIView {
  
  private let lottieView = LottieAnimationView()
  var lottieName: String
  var loopMode: LottieLoopMode
  var isPlaying: Bool = false
  var lottieSpeed: Double = 1.0
  var bgColor: UIColor = .black.withAlphaComponent(0.2)
  
  deinit {
	  print("deinit : " + String(describing: type(of: self)))
  }
  
  init(
	lottieName: String,
	loopMode: LottieLoopMode,
	lottieSpeed: Double = 1.0,
	bgColor: UIColor = .black.withAlphaComponent(0.2)
  ) {
	self.lottieName = lottieName
	self.loopMode = loopMode
	self.lottieSpeed = lottieSpeed
	self.bgColor = bgColor
	
	super.init(frame: .zero)
  }
  
  required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
  }
  
  func configure() {
	self.addSubview(lottieView)
	
	self.backgroundColor = bgColor
	
	lottieView.snp.makeConstraints { make in
	  make.width.height.equalTo(120)
	  make.centerX.equalToSuperview()
	  make.centerY.equalToSuperview()
	}
	
	lottieView.animation = LottieAnimation.named(self.lottieName)
	lottieView.animationSpeed = lottieSpeed
	lottieView.loopMode = self.loopMode
	lottieView.contentMode = .scaleAspectFill
  }
  
  func playLottie(completion: (() -> ())? = nil) {
	self.lottieView.play { _ in
	  completion?()
	}
	self.isPlaying = true
  }
  
  func stopLottie() {
	self.lottieView.stop()
	self.isPlaying = false
  }
}
