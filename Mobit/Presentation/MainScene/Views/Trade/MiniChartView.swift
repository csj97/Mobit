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
  
  var body: some View {
	 Text("Hello, World!")
  }
}

