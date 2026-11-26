"""개인 보유 알림의 로컬 정책 모형. python3 operations/test/test_holding_alert_policy.py -v"""
from dataclasses import dataclass
from fractions import Fraction
from itertools import permutations
import unittest


@dataclass(frozen=True)
class Holding:
    exchange: str = "bithumb"
    market: str = "KRW-BTC"
    average: Fraction = Fraction(100)
    side: str = "spot"
    # 수량이나 증거금의 원본 대신 두 값의 비율을 정확한 분수로 비교한다.
    quantity_per_margin: Fraction | None = None

    def percent(self, price):
        change = Fraction(price) - self.average
        if self.side == "spot":
            return change * 100 / self.average
        return change * self.quantity_per_margin * 100 * (1 if self.side == "long" else -1)


@dataclass
class State:
    revision: int
    holding: Holding | None
    last_time: int
    up: int = 0
    down: int = 0


class PolicyModel:
    """기기·보유 건별 최신 스냅샷과 발송 단계만 보관한다. 실제 통신은 수행하지 않는다."""
    def __init__(self):
        self.states = {}

    def sync(self, key, revision, holding, fill_time, fill_price=None):
        old = self.states.get(key)
        if old and (revision <= old.revision or old.holding is None):
            return
        state = State(revision, holding, fill_time, old.up if old else 0, old.down if old else 0)
        self.states[key] = state
        if holding:
            # 체결 자체로 넘어간 단계는 기준만 갱신하고 발송하지 않는다.
            self.advance(state, fill_price)

    @staticmethod
    def advance(state, price):
        rate = state.holding.percent(price)
        level = int(abs(rate) // 5) * 5
        if rate > 0 and level > state.up:
            state.up = level
            return level
        if rate < 0 and level > state.down:
            state.down = level
            return -level
        return None

    def quote(self, exchange, market, price, time):
        alerts = []
        for key, state in self.states.items():
            holding = state.holding
            if not holding or (holding.exchange, holding.market) != (exchange, market):
                continue
            if time <= state.last_time or price <= 0:
                continue
            state.last_time = time
            if holding.side != "spot" and holding.percent(price) <= -100:
                state.holding = None
                continue
            level = self.advance(state, price)
            if level is not None:
                alerts.append((key, level))
        return alerts


class HoldingAlertPolicyTests(unittest.TestCase):
    def setUp(self):
        self.model = PolicyModel()
        self.key = ("install-a", "holding-1")
        self.spot = Holding()
        self.model.sync(self.key, 1, self.spot, 1, 100)

    def levels(self, price, time):
        return [level for key, level in self.model.quote("bithumb", "KRW-BTC", price, time) if key == self.key]

    def test_split_buy_replaces_average_and_fills_emit_no_push(self):
        self.assertEqual(self.levels(105, 2), [5])
        self.model.sync(self.key, 2, Holding(average=90), 3, 80)
        self.assertEqual(self.levels(80, 4), [])  # 평단 변경으로만 생긴 손실
        self.assertEqual(self.levels(Fraction("94.5"), 5), [])  # 기존 +5 유지
        self.assertEqual(self.levels(99, 6), [10])
        self.assertEqual(self.levels(76, 7), [-15])

    def test_partial_spot_sale_needs_no_sync_until_final_sale(self):
        self.assertEqual(self.levels(105, 2), [5])
        # 일부 매도에는 평단 변경과 서버 요청이 없다.
        self.assertEqual(self.levels(110, 3), [10])
        self.model.sync(self.key, 2, None, 4)
        self.assertEqual(self.levels(120, 5), [])

    def test_both_directions_and_skipped_levels(self):
        prices = [104, 117, 105, 115, 95, 89, 105, 120, 80]
        expected = [[], [15], [], [], [-5], [-10], [], [20], [-20]]
        self.assertEqual([self.levels(p, i+2) for i, p in enumerate(prices)], expected)

    def test_raw_thresholds_on_both_sides_and_duplicate_ticks(self):
        for i, (p, expected) in enumerate([("104.999", []), ("105", [5]), ("95.009", []), ("95", [-5])]):
            self.assertEqual(self.levels(Fraction(p), i+2), expected)
            self.assertEqual(self.levels(Fraction(p), i+2), [])

    def test_quote_before_fill_or_older_than_latest_quote(self):
        self.model.sync(self.key, 2, Holding(average=90), 10, 90)
        for t in (9, 10):
            self.assertEqual(self.levels(130, t), [])
        self.assertEqual(self.levels(99, 12), [10])
        self.assertEqual(self.levels(120, 11), [])

    def test_revision_order_retry_and_close_before_open(self):
        updates = [(1, self.spot, 1, 100), (2, Holding(average=90), 2, 90), (3, None, 3, None)]
        for order in permutations(updates):
            model = PolicyModel()
            for update in (*order, *order):
                model.sync(self.key, *update)
            self.assertEqual(model.states[self.key].revision, 3)
            self.assertEqual(model.quote("bithumb", "KRW-BTC", 125, 10), [])

    def test_closed_holding_is_terminal_and_reentry_is_new(self):
        self.assertEqual(self.levels(105, 2), [5])
        self.model.sync(self.key, 2, None, 3)
        self.model.sync(self.key, 3, self.spot, 4, 100)
        new_key = ("install-a", "holding-2")
        self.model.sync(new_key, 1, self.spot, 5, 100)
        self.assertEqual(self.model.quote("bithumb", "KRW-BTC", 105, 6), [(new_key, 5)])
        self.model.sync(self.key, 2, None, 3)  # 이전 보유 건의 지연된 종료 재요청
        self.assertEqual(self.model.quote("bithumb", "KRW-BTC", 110, 7), [(new_key, 10)])

    def test_duplicate_snapshot_after_alert_does_not_reset_levels(self):
        self.assertEqual(self.levels(110, 3), [10])
        self.model.sync(self.key, 1, self.spot, 1, 100)
        self.assertEqual(self.levels(110, 4), [])
        self.assertEqual(self.levels(115, 5), [15])

    def test_invalid_price_leaves_next_valid_observation_available(self):
        for bad in (0, -1):
            self.assertEqual(self.levels(bad, 5), [])
        self.assertEqual(self.levels(105, 5), [5])

    def test_high_leverage_does_not_use_requested_quantity_before_step_rounding(self):
        # 목표 수량을 주문 단위로 내린 뒤에는 명목 레버리지와 실제 가격 민감도가 다르다.
        holding = Holding(average=30, side="long", quantity_per_margin=Fraction("3.33333333") / 10)
        self.assertEqual(holding.percent(Fraction("30.15")), Fraction("4.999999995"))
        self.assertEqual((Fraction("30.15") / 30 - 1) * 100 * 10, 5)

    def test_install_exchange_market_and_product_are_isolated(self):
        other_device = ("install-b", "holding-1")
        self.model.sync(other_device, 1, Holding(average=110), 1, 110)
        self.model.sync(("install-a", "upbit-btc"), 1, Holding(exchange="upbit"), 1, 100)
        self.model.sync(("install-a", "bithumb-eth"), 1, Holding(market="KRW-ETH"), 1, 100)
        short = ("install-a", "btc-short")
        self.model.sync(short, 1, Holding(side="short", quantity_per_margin=Fraction(1, 10)), 1, 100)
        self.assertCountEqual(self.model.quote("bithumb", "KRW-BTC", 105, 2),
                              [(self.key, 5), (short, -50)])
        self.assertEqual(self.model.quote("upbit", "KRW-BTC", 105, 3), [(("install-a", "upbit-btc"), 5)])

    def test_futures_partial_close_and_addition_against_remaining_principal(self):
        # 10개(평단 100, 증거금 100)에서 2.5개 종료한 뒤 200원에 5개 추가.
        for sign, side in [(1, "long"), (-1, "short")]:
            for quantity, cost, margin in [(10, 1000, 100), (Fraction("7.5"), 750, 75),
                                           (Fraction("12.5"), 1750, 175)]:
                holding = Holding(side=side, average=Fraction(cost, quantity),
                                  quantity_per_margin=Fraction(quantity, margin))
                for price in range(85, 156):
                    full_rate = sign * (price*quantity-cost)*100 / Fraction(margin)
                    self.assertEqual(holding.percent(price), full_rate)

    def test_leverage_sign_and_liquidation_precedes_price_alert(self):
        for leverage in (1, 10, 50, 100):
            for side, sign in [("long", 1), ("short", -1)]:
                key = ("install-f", "position")
                model = PolicyModel()
                model.sync(key, 1, Holding(side=side, quantity_per_margin=Fraction(leverage, 100)), 1, 100)
                def quotes(change, time):
                    return model.quote("bithumb", "KRW-BTC", 100+sign*Fraction(change, leverage), time)
                self.assertEqual(quotes(5, 2), [(key, 5)])
                # 1배 롱의 청산 경계는 가격 0으로 정상 시세 범위 밖이다.
                if side == "long" and leverage == 1:
                    continue
                self.assertEqual(quotes(-100, 3), [])
                self.assertIsNone(model.states[key].holding)
                self.assertEqual(quotes(15, 4), [])

    def test_unsynced_offline_sale_is_invisible_to_server(self):
        # 사용자가 이미 전량 매도했더라도 종료 요청이 도착하기 전에는 옛 기준이 살아 있다.
        self.assertEqual(self.levels(105, 3), [5])
        self.model.sync(self.key, 2, None, 2)
        self.assertEqual(self.levels(110, 4), [])

    def test_polling_cannot_infer_liquidation_between_two_quotes(self):
        model = PolicyModel()
        long = Holding(side="long", quantity_per_margin=Fraction(1, 10))
        model.sync(self.key, 1, long, 1, 100)
        self.assertEqual(long.percent(89), -110)  # 관측 사이 실제 저점
        self.assertEqual(model.quote("bithumb", "KRW-BTC", 101, 3), [(self.key, 10)])


if __name__ == "__main__":
    unittest.main()
