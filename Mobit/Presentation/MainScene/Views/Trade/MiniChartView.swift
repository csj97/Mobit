//
//  MiniChartView.swift
//  Mobit
//
//  Created by 조성재 on 8/11/25.
//

import Charts
import SwiftUI

struct CandleEntry: Identifiable {
  let id = UUID()
  let date: Date
  let close: Double
}

struct MiniChartView: View {
  let candleEntries: [CandleEntry]
  
  private var areaGradient: LinearGradient {
	let prices = candleEntries.map { $0.close }
	let minPrice = prices.min() ?? 0
	let maxPrice = prices.max() ?? 0
	let basePrice = candleEntries.sorted { $0.date < $1.date }.first?.close ?? 0
	
	let range = max(maxPrice - minPrice, 0.0001)
	let location = (basePrice - minPrice) / range
	let clamped = min(max(location, 0), 1)
	let upper = min(clamped + 0.0001, 1.0)
	
	return LinearGradient(
	  gradient: Gradient(stops: [
		.init(color: .blue.opacity(0.18), location: 0.0),
		.init(color: .blue.opacity(0.18), location: clamped),
		.init(color: .red.opacity(0.18), location: upper),
		.init(color: .red.opacity(0.18), location: 1.0)
	  ]),
	  startPoint: .bottom,
	  endPoint: .top
	)
  }
  
  private var lineGradient: LinearGradient {
	let prices = candleEntries.map { $0.close }
	let minPrice = prices.min() ?? 0
	let maxPrice = prices.max() ?? 0
	let basePrice = candleEntries.sorted { $0.date < $1.date }.first?.close ?? 0
	
	let range = max(maxPrice - minPrice, 0.0001)
	// 기준 가격이 차트 전체 높이에서 어디쯤에 위치하고 있는지
	let location = (basePrice - minPrice) / range
	// location을 무조건 0~1 사이로 강제 보정해주는 역할
	let clamped = min(max(location, 0), 1)
	let upper = min(clamped + 0.0001, 1.0)
	
	return LinearGradient(
	  gradient: Gradient(stops: [
		.init(color: .blue.opacity(0.65), location: 0.0),
		.init(color: .blue.opacity(0.65), location: clamped),
		.init(color: .red.opacity(0.65), location: upper),
		.init(color: .red.opacity(0.65), location: 1.0)
	  ]),
	  startPoint: .bottom,
	  endPoint: .top
	)
  }
  
  var body: some View {
	
	let prices = candleEntries.map { $0.close }
	let minPrice = prices.min() ?? 0
	let maxPrice = prices.max() ?? 0
	let sortedEntries = candleEntries.sorted { $0.date < $1.date }
	let basePrice = sortedEntries.first?.close ?? 0
	
	Chart {
	  RuleMark(
		y: .value("Base", basePrice)
	  )
	  .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
	  .foregroundStyle(Color.lineLightGray)
	  
	  // Area
	  ForEach(sortedEntries) { entry in
		AreaMark(
		  x: .value("Date", entry.date),
		  yStart: .value("Base", basePrice),
		  yEnd: .value("Price", entry.close)
		)
		.interpolationMethod(.linear)
		.foregroundStyle(areaGradient)
	  }
	  
	  // Line
	  ForEach(sortedEntries) { entry in
		LineMark(
		  x: .value("Date", entry.date),
		  y: .value("Price", entry.close)
		)
		.interpolationMethod(.linear)
		.foregroundStyle(lineGradient)
		.lineStyle(.init(lineWidth: 1))
	  }
	}
	.background(.clear)
	.chartXAxis(.hidden)
	.chartYAxis(.hidden)
	.chartYScale(domain: min(minPrice, basePrice) ... max(maxPrice, basePrice))
  }
}
