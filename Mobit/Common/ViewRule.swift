//
//  ViewRule.swift
//  Mobit
//
//  Created by 조성재 on 2/5/25.
//

import Foundation

@objc protocol ViewRule {
  @objc optional func setUI()
  @objc optional func setData()
}
