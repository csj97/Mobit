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
  let isPlus: Bool
  
  var body: some View {
	
	let color = isPlus ? Color.blue : Color.red
	let basePrice = candleEntries.first?.close ?? 0
	let percentChanges = candleEntries.map { ($0.close - basePrice) / basePrice * 100 }
		
	Chart {
		  ForEach(Array(candleEntries.enumerated()), id: \.offset) { index, entry in
			let percentChange = (entry.close - basePrice) / basePrice * 100
			
			// 먼저 AreaMark (배경)
			AreaMark(
			  x: .value("Date", entry.date),
			  y: .value("Percent", percentChange)
			)
			.interpolationMethod(.catmullRom)
			.foregroundStyle(
			  .linearGradient(
				colors: [
				  color.opacity(0.6),
				  color.opacity(0.05)
				],
				startPoint: .top,
				endPoint: .bottom
			  )
			)
			
			// 그 다음 LineMark (선)
			LineMark(
			  x: .value("Date", entry.date),
			  y: .value("Percent", percentChange)
			)
			.interpolationMethod(.catmullRom)
			.foregroundStyle(color)
			.lineStyle(StrokeStyle(lineWidth: 2))
		  }
		}
		.chartXAxis(.hidden)
		.chartYAxis(.hidden)
  }
}

/**
 
//	.chartXAxis {
//	  AxisMarks(values: .stride(by: .hour, count: 1))
//	}
//	.chartYAxis {
//	  AxisMarks(position: .leading)
//	}
 */
