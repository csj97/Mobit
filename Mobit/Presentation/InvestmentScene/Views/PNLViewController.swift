//
//  PNLViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit
import Photos

class PNLViewController: MobitBaseViewController {
  
  @IBOutlet weak var pnlTableView: SelfSizingTableView!
    @IBOutlet weak var noResultView: UIView!
    
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
	// 최신순을 위해 reversed
    let currentExchange = ExchangeSelectionStore.currentExchange
    let datas = UserDataManager.userPNLHistory?.filter {
      $0.exchange == currentExchange
    } ?? []

	if datas.count > 0 {
	  self.noResultView.isHidden = true
	  self.pnlHistoryDatas = datas.reversed()
	  self.pnlTableView.reloadData()
	} else {
	  self.noResultView.isHidden = false
	}
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
	
	cell.shareCallBack = { [weak self] in
	  guard let self = self else { return }
	  
	  let roi = ((pnlHistory.exitPrice - pnlHistory.entryPrice) / pnlHistory.entryPrice) * 100
	  let pnlShareUnit = PNLShareUnit(
		marketName: pnlHistory.marketName,
		roi: roi,
		pnl: pnlHistory.pnl,
		quantity: pnlHistory.orderQuantity,
		entryPrice: pnlHistory.entryPrice,
		exitPrice: pnlHistory.exitPrice,
		transactionDate: pnlHistory.transactionDate
	  )
	  
	  let shareView = PNLShareView.instanceFromNib(
		pnlShareUnit: pnlShareUnit
	  ) { button in
		switch button {
		case .save(let saveImg):
		  self.checkPhotoPermission { isAuthorized in
			if isAuthorized {
			  UIImageWriteToSavedPhotosAlbum(
				saveImg, self,
				#selector(self.imageSaveCompleted(_:didFinishSavingWithError:contextInfo:)),
				Unmanaged.passUnretained(self).toOpaque()
			  )
			} else {
			  if let appSettings = URL(string: UIApplication.openSettingsURLString) {
				UIApplication.shared.open(appSettings)
			  }
			}
		  }
		  
		case .share(let shareImg):
		  var pnlSign = ""
		  if pnlHistory.pnl > 0 { pnlSign = "+" }
		  var roiSign = ""
		  if roi > 0 { roiSign = "+" }
		  
		  let entryPrice = "\(pnlHistory.entryPrice.formatSignificantDigits(digits: 2))".addComma()
		  let exitPrice = "\(pnlHistory.exitPrice.formatSignificantDigits(digits: 2))".addComma()
		  let pnl = pnlSign + "\(pnlHistory.pnl.formatSignificantDigits(digits: 2))".addComma() + " ₩"
		  let roi = roiSign + "\(pnlShareUnit.roi.formatSignificantDigits(digits: 2)) %"
		  
		  let image = shareImg
		  let message = """
📈 MOBIT 실현손익
* 코인명 : \(pnlHistory.marketName)
* 수익률 : \(roi) 
* P&L  : \(pnl)
* 매수평균가 : \(entryPrice)
* 매도가 : \(exitPrice)
* 거래일 : \(pnlHistory.transactionDate)
"""
		  
		  let activityVC = UIActivityViewController(
			activityItems: [image, message],
			applicationActivities: nil
		  )
		  
		  // iPad 대응 (아이패드에서는 반드시 팝오버로 표시되어야함)
		  if let popover = activityVC.popoverPresentationController {
			popover.sourceView = self.view
			popover.sourceRect = CGRect(
			  x: self.view.bounds.midX,
			  y: self.view.bounds.midY,
			  width: 0,
			  height: 0
			)
			popover.permittedArrowDirections = []
		  }

		  self.present(activityVC, animated: true, completion: nil)
		}
	  }
	  self.showPNLShareView(shareView: shareView)
	}
	
	return cell
  }

  /// UIView Image로 앨범 저장 Handler
  @objc private func imageSaveCompleted(
	_ image: UIImage,
	didFinishSavingWithError error: Error?,
	contextInfo: UnsafeRawPointer
  ) {
	let title = (error == nil) ? "저장 완료" : "저장 실패"
	let content = (error == nil) ? "사진이 앨범에 저장되었습니다." : error?.localizedDescription ?? "알 수 없는 오류가 발생했습니다."
	self.show(
	  alertType: .onlyConfirm,
	  title: title,
	  content: content,
	  callBack: nil
	)
  }
}

extension PNLViewController {
  private func showPNLShareView(shareView: UIView) {
	self.view.addSubview(shareView)
	
	shareView.alpha = 0
	shareView.translatesAutoresizingMaskIntoConstraints = false
	
	shareView.snp.makeConstraints { make in
	  make.edges.equalToSuperview()
	}
	
	UIView.animate(withDuration: 0.25) {
	  shareView.alpha = 1
	}
  }
}

extension PNLViewController {
  
  private func checkPhotoPermission(completion: @escaping (Bool) -> Void) {
	let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
	
	switch status {
	case .notDetermined:
	  PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
		DispatchQueue.main.async {
		  completion(newStatus == .authorized || newStatus == .limited)
		}
	  }
	  
	case .authorized, .limited:
	  completion(true)
	  
	case .denied, .restricted:
	  completion(false)
	  
	@unknown default:
	  completion(false)
	}
  }
  
}
