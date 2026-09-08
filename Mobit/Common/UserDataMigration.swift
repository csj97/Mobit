//
//  UserDataMigration.swift
//  Mobit
//
//  Created by 조성재 on 7/10/26.
//

import Foundation

enum UserDataMigration {
  static func migrateFavoritePairs(from legacy: [String]) -> [FavoritePair] {
    legacy.map {
      FavoritePair(displayMarket: $0, exchange: .upbit)
    }
  }

  static func migrateUserCryptoList(
    from legacy: [LegacyModel]
  ) -> [CryptoTransactionDataModel] {
    legacy.map { item in
      let staticData = CryptoTransactionDataModel.CryptoTransactionStaticData(
        identifier: UUID(),
        marketName: item.staticData.marketName,
        cryptoName: item.staticData.cryptoName,
        holdingQuantity: item.staticData.holdingQuantity,
        averageBuyPrice: item.staticData.averageBuyPrice,
        buyAmount: item.staticData.buyAmount
      )
      let dynamicData = CryptoTransactionDataModel.CryptoTransactionDynamicData(
        identifier: UUID(),
        marketName: item.dynamicData.marketName,
        profitRate: item.dynamicData.profitRate,
        evaluationProfitLoss: item.dynamicData.evaluationProfitLoss,
        evaluationPrice: item.dynamicData.evaluationPrice
      )
      return CryptoTransactionDataModel(
        identifier: UUID(),
        staticData: staticData,
        dynamicData: dynamicData
      )
    }
  }

  static func migrateUserInformationStore(
    from legacy: MobitUserInformation
  ) -> [String: MobitUserInformation] {
    [Exchange.upbit.rawValue: legacy]
  }
}
