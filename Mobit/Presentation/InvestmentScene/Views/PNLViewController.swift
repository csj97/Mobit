//
//  PNLViewController.swift
//  Mobit
//
//  Created by 조성재 on 7/29/25.
//

import UIKit
import Photos
import RxSwift

class PNLViewController: MobitBaseViewController {
  
  @IBOutlet weak var pnlTableView: UITableView!
    @IBOutlet weak var noResultView: UIView!
    @IBOutlet weak var emptyLabel: UILabel!

  var futuresReactor: FuturesAccountReactor?
  private let futuresBag = DisposeBag()
  private var futuresRecords: [(record: FuturesTransactionRecord, position: FuturesPosition)] = []
    
  weak var coordinator: PNLCoordinator?
  weak var delegate: MainCoordinatorDelegate?

  var pnlHistoryDatas: [UserPNLHistoryModel]? = []
  
  override func viewDidLoad() {
	super.viewDidLoad()
	self.setUI()
	self.setData()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    MobitAnalyticsUtil.sendScreenEvent(
      location: "실현손익_내역_화면",
      stepDepth01: "실현손익_내역",
      stepDepth02: "실현손익_조회",
      account: futuresReactor?.account ?? .spot(for: ExchangeSelectionStore.currentExchange)
    )
  }

  override func viewWillAppear(_ animated: Bool) {
	super.viewWillAppear(animated)
	applyThemeColors()
	pnlTableView.reloadData()
  }
  
  override func viewWillDisappear(_ animated: Bool) {
	super.viewWillDisappear(animated)
	self.delegate?.mainCoordinatorDidRequestShowTabBar()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
	super.traitCollectionDidChange(previousTraitCollection)
	guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
	applyThemeColors()
	pnlTableView.reloadData()
  }
  
  func setUI() {
	applyThemeColors()
	self.pnlTableView.delegate = self
	self.pnlTableView.dataSource = self
	
	self.pnlTableView.register(
	  UINib(nibName: "PNLTableViewCell", bundle: nil),
	  forCellReuseIdentifier: "PNLTableViewCell"
	)
  }

  private func applyThemeColors() {
	self.view.backgroundColor = .mobitColors(.backgroundPrimary)
	self.pnlTableView.backgroundColor = .mobitColors(.investmentSurface)
	self.noResultView.backgroundColor = .mobitColors(.investmentSurface)
  }

  func setData() {
    if let futuresReactor {
      pnlTableView.rowHeight = UITableView.automaticDimension
      pnlTableView.estimatedRowHeight = 200
      futuresReactor.state.observe(on: MainScheduler.instance)
        .subscribe(onNext: { [weak self] _ in self?.renderFutures() }).disposed(by: futuresBag)
      return
    }
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
	self.navigationController?.popViewController(animated: true)
  }
}


extension PNLViewController: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
	
	return futuresReactor != nil ? futuresRecords.count : self.pnlHistoryDatas?.count ?? 0
  }
  
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if futuresReactor != nil { return futuresCell(tableView, at: indexPath) }
	guard let cell = tableView.dequeueReusableCell(withIdentifier: "PNLTableViewCell",for: indexPath) as? PNLTableViewCell,
		  let pnlHistory = self.pnlHistoryDatas?[indexPath.row]
	else {
	  return UITableViewCell()
	}
	
	cell.configure(pnlHistory: pnlHistory)
	cell.selectionStyle = .none
	
	cell.shareCallBack = { [weak self] in
	  guard let self = self else { return }
	  
      self.showShare(PNLShareUnit.spot(pnlHistory))
	}

	return cell
  }

  private func showShare(_ pnlShareUnit: PNLShareUnit) {
	  let shareView = PNLShareView.instanceFromNib(
		pnlShareUnit: pnlShareUnit
	  ) { [weak self] button in
        guard let self else { return }
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
		  if pnlShareUnit.pnl > 0 { pnlSign = "+" }
		  var roiSign = ""
		  if pnlShareUnit.roi > 0 { roiSign = "+" }
		  
		  let entryPrice = TradingNumberFormat.string(pnlShareUnit.entryPrice)
		  let exitPrice = TradingNumberFormat.string(pnlShareUnit.exitPrice)
		  let pnl = pnlSign + TradingNumberFormat.string(pnlShareUnit.pnl) + " ₩"
		  let roi = roiSign + "\(PortfolioCalculator.double(pnlShareUnit.roi).formatSignificantDigits(digits: 2)) %"
		  
		  let image = shareImg
          let entryTitle = FuturesText.text(pnlShareUnit.product == .perpetual ? "futures_entry" : "investment_average_price")
          let exitTitle = FuturesText.text(pnlShareUnit.product == .perpetual ? "futures_exit_price" : "investment_exit_price")
		  let message = """
📈 MOBIT 실현손익
* 코인명 : \(pnlShareUnit.marketDescription)
* 수익률 : \(roi) 
* P&L  : \(pnl)
* \(entryTitle) : \(entryPrice)
* \(exitTitle) : \(exitPrice)
* 거래일 : \(pnlShareUnit.transactionDate)
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
    MobitAnalyticsUtil.sendScreenEvent(
      location: "실현손익_내역_화면",
      stepDepth01: "실현손익_공유",
      stepDepth02: "공유_미리보기_열기",
      account: pnlShareUnit.exchange.map { TradingAccountID(exchange: $0, product: pnlShareUnit.product, currency: .krw) }
    )
	  self.showPNLShareView(shareView: shareView)
  }

  private func renderFutures() {
    guard let reactor = futuresReactor else { return }
    futuresRecords = []
    emptyLabel.numberOfLines = 0
    emptyLabel.text = FuturesText.text("futures_no_history")
    do {
      if let snapshot = reactor.currentState.snapshot {
        let records = try snapshot.transactionHistory(for: reactor.account).filter { $0.realizedPnL != nil }.reversed()
        futuresRecords = records.compactMap { record in
          snapshot.positions.first(where: { $0.id == record.positionID }).map { (record, $0) }
        }
      } else {
        emptyLabel.text = FuturesText.text("futures_loading")
      }
      if reactor.currentState.loadFailed { emptyLabel.text = FuturesText.text("futures_storage_error") }
    } catch {
      emptyLabel.text = FuturesText.text("futures_storage_error")
    }
    noResultView.isHidden = !futuresRecords.isEmpty
    pnlTableView.reloadData()
  }

  private func futuresCell(_ table: UITableView, at path: IndexPath) -> UITableViewCell {
    guard futuresRecords.indices.contains(path.row),
          let cell = table.dequeueReusableCell(withIdentifier: "PNLTableViewCell", for: path) as? PNLTableViewCell else { return UITableViewCell() }
    let item = futuresRecords[path.row]
    cell.configure(record: item.record, position: item.position)
    cell.selectionStyle = .none
    cell.shareCallBack = { [weak self] in
      guard let self else { return }
      do { showShare(try FuturesText.shareUnit(item.record, position: item.position)) }
      catch { show(alertType: .onlyConfirm, title: FuturesText.text("futures_realized"), content: FuturesText.text("futures_storage_error"), callBack: nil) }
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
