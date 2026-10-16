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
  // 실제 데이터와 섞지 않고 로딩 전용 셀의 표시만 준비한다.
  private let prepareSkeletonCell: (UITableViewCell) -> Void
  
  init(
    tableView: UITableView,
    skeletonCellIdentifier: String,
    skeletonRowCount: Int = UITableView.automaticNumberOfSkeletonRows,
    prepareCellForSkeleton: @escaping (UITableViewCell) -> Void = { _ in },
    cellProvider: @escaping UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider
  ) {
	
	self.skeletonCellIdentifier = skeletonCellIdentifier
	self.skeletonRowCount = skeletonRowCount
	self.prepareSkeletonCell = prepareCellForSkeleton
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

  func collectionSkeletonView(
    _ skeletonView: UITableView,
    prepareCellForSkeleton cell: UITableViewCell,
    at indexPath: IndexPath
  ) {
    prepareSkeletonCell(cell)
  }
}
