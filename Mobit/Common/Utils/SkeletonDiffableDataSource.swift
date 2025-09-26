//
//  SkeletonDiffableDataSource.swift
//  Mobit
//
//  Created by 조성재 on 9/25/25.
//

import Foundation
import UIKit
import SkeletonView

class SkeletonDiffableDataSource<SectionIdentifierType: Hashable, ItemIdentifierType: Hashable>:
	UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>,
	SkeletonTableViewDataSource {
  
  private let skeletonCellIdentifier: String
  private let skeletonRowCount: Int
  
  init(tableView: UITableView,
	   skeletonCellIdentifier: String,
	   skeletonRowCount: Int = 10,
	   cellProvider: @escaping UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider) {
	
	self.skeletonCellIdentifier = skeletonCellIdentifier
	self.skeletonRowCount = skeletonRowCount
	super.init(tableView: tableView, cellProvider: cellProvider)
  }
  
  // MARK: - SkeletonTableViewDataSource
  
  // 스켈레톤 상태에서 보여줄 셀 수
  func collectionSkeletonView(_ skeletonView: UITableView,
							  numberOfRowsInSection section: Int) -> Int {
	return skeletonRowCount
  }
  
  // 실제 등록해둔 셀 identifier 사용
  func collectionSkeletonView(_ skeletonView: UITableView,
							  cellIdentifierForRowAt indexPath: IndexPath) -> ReusableCellIdentifier {
	return skeletonCellIdentifier
  }
}
