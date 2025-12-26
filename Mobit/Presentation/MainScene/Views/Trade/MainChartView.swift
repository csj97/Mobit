//
//  MainChartView.swift
//  Mobit
//
//  Created by 조성재 on 12/19/25.
//

import Charts
import SwiftUI

struct MainChartView: View {
  @State private var visibleCandleCount: Int = 50	// 한 화면에 보여줄 수 있는 캔들 수
  @State private var endIndex: Int					// 현재 시작 위치 (값이 커질 수록 과거로 이동)
  @State private var lastDragX: CGFloat = 0
  @State private var isLoadingPast = false
  
  let candleEntries: [any CandleModel]
  let onRequestPastCandles: (_ oldestTimestamp: String) -> Void
  
  init(
	candleEntries: [any CandleModel],
	onRequestPastCandles: @escaping (_ oldestTimestamp: String) -> Void
  ) {
	self.candleEntries = candleEntries
	self.onRequestPastCandles = onRequestPastCandles
	// _endIndex = State(initialValue: candleEntries.count)
	let rightPaddingCandles = 6   // ← 우측 여백 느낌
	_endIndex = State(
		initialValue: max(
			candleEntries.count - rightPaddingCandles,
			50
		)
	)
  }
  
  private var visibleCandles: [any CandleModel] {
	guard !candleEntries.isEmpty else { return [] }
	
	let safeEnd = min(max(endIndex, visibleCandleCount), candleEntries.count)
	let start = safeEnd - visibleCandleCount
	
	return Array(candleEntries[start..<safeEnd])
  }
  
  private func yAxisRange() -> ClosedRange<Double> {
	guard !visibleCandles.isEmpty else { return 0...1 }
	
	let lows = visibleCandles.map { $0.low_price }
	let highs = visibleCandles.map { $0.high_price }
	
	let minPrice = lows.min() ?? 0
	let maxPrice = highs.max() ?? 1
	
	let padding = (maxPrice - minPrice) * 0.05 // 5% 여유
	
	return (minPrice - padding)...(maxPrice + padding)
  }
  
  var body: some View {
	Chart {
	  ForEach(visibleCandles, id: \.timestamp) { candle in
		let isUp = candle.trade_price > candle.opening_price
		
		RuleMark(
		  x: .value("Time", candle.candle_date_time_kst),
		  yStart: .value("Low", candle.low_price),
		  yEnd: .value("High", candle.high_price)
		)
		.foregroundStyle(isUp ? .blue : .red)
		
		RectangleMark(
		  x: .value("Time", candle.candle_date_time_kst),
		  yStart: .value("Open", candle.opening_price),
		  yEnd: .value("Close", candle.trade_price),
		  width: 6
		)
		.foregroundStyle(isUp ? .blue : .red)
	  }
	}
	.chartXAxis(.hidden)
	.chartYAxis(.hidden)
	.chartYScale(domain: yAxisRange())
	.gesture(
	  DragGesture()
		.onChanged { value in
		  let deltaX = value.translation.width - lastDragX
		  lastDragX = value.translation.width
		  
		  let pixelsPerCandle: CGFloat = 8   // 감도 조절 핵심
		  let candleDelta = Int(deltaX / pixelsPerCandle)
		  
		  guard candleDelta != 0 else { return }
		  
		  let newEndIndex = endIndex - candleDelta
		  
		  endIndex = min(
			max(newEndIndex, visibleCandleCount),
			candleEntries.count
		  )
		  
		  // 왼쪽 끝 근접 시 과거 데이터 요청
		  let reloadMarginValue = 10
		  if endIndex <= visibleCandleCount + reloadMarginValue {
			// TODO: 과거 데이터 요청
			if let oldest = self.candleEntries.first {
			  self.onRequestPastCandles(oldest.candle_date_time_kst)
			}
		  }
		}
		.onEnded { _ in
		  lastDragX = 0
		}
	)
  }
}
