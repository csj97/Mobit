//
//  SelfSizingViews.swift
//  Mobit
//
//  Created by 조성재 on 7/16/25.
//

import Foundation
import UIKit

/// CollectionView
class SelfSizingCollectionView: UICollectionView {
  override var intrinsicContentSize: CGSize {
	return contentSize
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	self.backgroundColor = .white
	invalidateIntrinsicContentSize()
  }
}

/// TableView
class SelfSizingTableView: UITableView {
  override var intrinsicContentSize: CGSize {
	return contentSize
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	self.backgroundColor = .white
	invalidateIntrinsicContentSize()
  }
}

/// ScrollView
class SelfSizingScrollView: UIScrollView {
  override var intrinsicContentSize: CGSize {
	return contentSize
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	invalidateIntrinsicContentSize()
  }
}

/// TextView
class SelfSizingTextView: UITextView {
  override var intrinsicContentSize: CGSize {
	return contentSize
  }
  
  override func layoutSubviews() {
	super.layoutSubviews()
	invalidateIntrinsicContentSize()
  }
}
