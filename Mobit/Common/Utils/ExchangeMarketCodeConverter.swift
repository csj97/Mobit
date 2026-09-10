//
//  ExchangeMarketCodeConverter.swift
//  Mobit
//
//  Created by 조성재 on 7/8/26.
//

import Foundation

enum ExchangeMarketCodeConverter {
  static let defaultExchange: Exchange = .upbit

  static func pairID(
    fromDisplayMarket displayMarket: String,
    exchange: Exchange = defaultExchange
  ) -> ExchangePairID {
    ExchangePairID(
      exchange: exchange,
      rawMarketCode: self.rawMarketCode(
        fromDisplayMarket: displayMarket,
        exchange: exchange
      )
    )
  }

  static func pairID(
    fromRawMarketCode rawMarketCode: String,
    exchange: Exchange
  ) -> ExchangePairID {
    ExchangePairID(exchange: exchange, rawMarketCode: rawMarketCode)
  }

  static func rawMarketCode(
    fromDisplayMarket displayMarket: String,
    exchange: Exchange = defaultExchange
  ) -> String {
    let components = self.displayComponents(from: displayMarket)
      ?? self.normalizedComponents(fromAnyMarketCode: displayMarket)
    guard let components else { return displayMarket }

    switch exchange {
    case .upbit:
      return "\(components.quote)-\(components.base)"

    case .bithumb:
      return "\(components.quote)-\(components.base)"

    case .binance, .okx:
      return displayMarket
    }
  }

  /// 마켓의 결제 통화. 지원하지 않는 통화면 nil을 돌려 호출 측이 주문을 거절하도록 한다.
  static func settlementCurrency(
    fromDisplayMarket displayMarket: String,
    exchange: Exchange = defaultExchange
  ) -> SettlementCurrency? {
    let components = self.displayComponents(from: displayMarket)
      ?? self.normalizedComponents(fromAnyMarketCode: displayMarket)
    guard let quote = components?.quote else { return nil }

    return SettlementCurrency(rawValue: quote.uppercased())
  }

  static func displayMarket(
    fromRawMarketCode rawMarketCode: String,
    exchange: Exchange = defaultExchange
  ) -> String {
    guard let components = self.rawComponents(
      from: rawMarketCode,
      exchange: exchange
    ) else {
      return rawMarketCode
    }

    return "\(components.base)/\(components.quote)"
  }

  private static func displayComponents(
    from displayMarket: String
  ) -> (base: String, quote: String)? {
    let components = displayMarket.split(separator: "/").map(String.init)
    guard components.count == 2 else { return nil }
    return (base: components[0], quote: components[1])
  }

  // 거래소 전환 중에는 display market뿐 아니라 이전 거래소 raw code가 다시 들어올 수 있다.
  // 입력 포맷을 가리지 않고 base/quote를 먼저 정규화해 두어야 역방향 전환에서도 잘못된 raw code가 남지 않는다.
  private static func normalizedComponents(
    fromAnyMarketCode marketCode: String
  ) -> (base: String, quote: String)? {
    if let displayComponents = self.displayComponents(from: marketCode) {
      return displayComponents
    }

    if let upbitComponents = self.rawComponents(from: marketCode, exchange: .upbit) {
      return upbitComponents
    }

    if let bithumbComponents = self.rawComponents(from: marketCode, exchange: .bithumb) {
      return bithumbComponents
    }

    return nil
  }

  private static func rawComponents(
    from rawMarketCode: String,
    exchange: Exchange
  ) -> (base: String, quote: String)? {
    switch exchange {
    case .upbit:
      let components = rawMarketCode.split(separator: "-").map(String.init)
      guard components.count == 2 else { return nil }
      return (base: components[1], quote: components[0])

    case .bithumb:
      if rawMarketCode.contains("-") {
        let components = rawMarketCode.split(separator: "-").map(String.init)
        guard components.count == 2 else { return nil }
        return (base: components[1], quote: components[0])
      }

      if rawMarketCode.contains("_") {
        let components = rawMarketCode.split(separator: "_").map(String.init)
        guard components.count == 2 else { return nil }
        return (base: components[0], quote: components[1])
      }

      return nil

    case .binance, .okx:
      return nil
    }
  }
}

extension ExchangePairID {
  var displayMarket: String {
    guard let exchange = self.exchange,
          let rawMarketCode = self.rawMarketCode else {
      return self.rawValue
    }

    return ExchangeMarketCodeConverter.displayMarket(
      fromRawMarketCode: rawMarketCode,
      exchange: exchange
    )
  }
}

extension CryptoCellInfo {
  var exchange: Exchange {
    ExchangeSelectionStore.currentExchange
  }

  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.market,
      exchange: self.exchange
    )
  }
}

extension CryptoTransactionDataModel {
  /// 보유 종목의 평단·매수금액·평가금액이 어느 통화로 기록됐는지 나타낸다.
  var settlementCurrency: SettlementCurrency {
    ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: self.staticData.marketName,
      exchange: self.staticData.exchange
    ) ?? .krw
  }
}

extension CryptoTransactionDataModel.CryptoTransactionStaticData {
  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    )
  }
}

extension CryptoTransactionDataModel.CryptoTransactionDynamicData {
  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    )
  }
}

extension TransactionInfo {
  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    )
  }
}

extension ValidTransactionInfo {
  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    )
  }
}

extension UserPNLHistoryModel {
  var exchangePairID: ExchangePairID {
    ExchangeMarketCodeConverter.pairID(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    )
  }

  /// 실현손익과 진입·청산 가격이 기록된 통화. BTC 마켓 손익은 BTC 단위다.
  var settlementCurrency: SettlementCurrency {
    ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    ) ?? .krw
  }
}

extension TransactionInfo {
  /// 체결가·체결금액이 기록된 통화.
  var settlementCurrency: SettlementCurrency {
    ExchangeMarketCodeConverter.settlementCurrency(
      fromDisplayMarket: self.marketName,
      exchange: self.exchange
    ) ?? .krw
  }
}
