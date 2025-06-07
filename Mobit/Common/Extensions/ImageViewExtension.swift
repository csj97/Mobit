//
//  ImageViewExtension.swift
//  Mobit
//
//  Created by 조성재 on 6/6/25.
//

import Foundation
import UIKit

extension UIImageView {
  func load(from url: URL) {
	DispatchQueue.global().async { [weak self] in
	  guard let data = try? Data(contentsOf: url),
			let image = UIImage(data: data) else { return }
	  
	  DispatchQueue.main.async {
		self?.image = image
	  }
	}
  }
}
