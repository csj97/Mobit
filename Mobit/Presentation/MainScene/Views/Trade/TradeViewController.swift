//
//  TradeViewController.swift
//  Mobit
//
//  Created by 조성재 on 2/4/25.
//

import UIKit
import SnapKit

class TradeViewController: UIViewController, ViewRule {
  
  @IBOutlet weak var segmentedControl: UISegmentedControl!
  @IBOutlet weak var segmentedContainerView: UIView!
  @IBOutlet weak var chartView: UIView!
  @IBOutlet weak var informationView: UIView!
  @IBOutlet weak var bidOrderView: UIView!
  @IBOutlet weak var askOrderView: UIView!
  @IBOutlet weak var tradeHistoryView: UIView!
  @IBOutlet weak var tradeHistoryTableView: UITableView!
  
  weak var coordinator: CryptoDetailCoordinator?
  let orderView: TradeOrderView = TradeOrderView()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setUI()
    setData()
  }
  
  func setUI() {
    
    self.segmentedContainerView.addSubview(orderView)
    self.segmentedContainerView.addSubview(self.chartView)
    self.segmentedContainerView.addSubview(self.informationView)
    
    orderView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }
    self.chartView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }
    self.informationView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }
    
    self.segmentedControl.selectedSegmentIndex = 0
  }
  
  func setData() {
    
    self.tradeHistoryTableView.delegate = self
    self.tradeHistoryTableView.dataSource = self
  }
  
  @IBAction func tapOnSegmentedControl(_ sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
      orderView.isHidden = false
      self.chartView.isHidden = true
      self.informationView.isHidden = true
    case 1:
      orderView.isHidden = true
      self.chartView.isHidden = false
      self.informationView.isHidden = true
    case 2:
      orderView.isHidden = true
      self.chartView.isHidden = true
      self.informationView.isHidden = false
      
    default:
      break
    }
  }
  
}

extension TradeViewController: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if tableView == self.tradeHistoryTableView {
      return 0
    } else {
      return 0
    }
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if tableView == self.tradeHistoryTableView {
      
    } else {
      
    }
    
    return UITableViewCell()
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if tableView == self.tradeHistoryTableView {
      
    } else {
      
    }
  }
}
