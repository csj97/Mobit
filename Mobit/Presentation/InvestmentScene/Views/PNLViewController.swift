//
//  PNLViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit

class PNLViewController: MobitBaseViewController {
  
  @IBOutlet weak var pnlTableView: SelfSizingTableView!
  
  weak var coordinator: PNLCoordinator?
  weak var delegate: MainCoordinatorDelegate?

  var pnlHistoryDatas: [UserPNLHistoryModel]? = []
  
  override func viewDidLoad() {
	super.viewDidLoad()
	self.setUI()
	self.setData()
  }
  
  override func viewWillDisappear(_ animated: Bool) {
	super.viewWillDisappear(animated)
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }
  
  func setUI() {
	self.pnlTableView.delegate = self
	self.pnlTableView.dataSource = self
	
	self.pnlTableView.register(
	  UINib(nibName: "PNLTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "PNLTableViewCell"
	)
  }
  
  func setData() {
	self.pnlHistoryDatas = UserDataManager.userPNLHistory ?? []
	self.pnlTableView.reloadData()
  }
  
  @IBAction func tapOnBackButton(_ sender: UIButton) {
	self.coordinator?.navigationController.popViewController(animated: true)
  }
}


extension PNLViewController: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
	
	return self.pnlHistoryDatas?.count ?? 0
  }
  
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
	guard let cell = tableView.dequeueReusableCell(withIdentifier: "PNLTableViewCell",for: indexPath) as? PNLTableViewCell,
		  let pnlHistory = self.pnlHistoryDatas?[indexPath.row]
	else {
	  return UITableViewCell()
	}
	
	cell.configure(pnlHistory: pnlHistory)
	cell.selectionStyle = .none
	
	return cell
  }
}
