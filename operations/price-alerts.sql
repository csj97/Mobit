-- 푸시 배포 스크립트가 mobit_ops 스키마를 준비한 뒤 한 트랜잭션에서 실행한다.
create table if not exists mobit_ops.price_rule (
  market text primary key check (market ~ '^KRW-[A-Z0-9]+$'),
  hour_percent numeric not null check (hour_percent > 0 and hour_percent < 'Infinity'),
  exchange_percent numeric not null check (exchange_percent > 0 and exchange_percent < 'Infinity')
);
insert into mobit_ops.price_rule
select 'KRW-' || symbol, 5, 5 from unnest(array['BTC','ETH','SOL','TRX','AVAX','HYPE']) as symbol
on conflict do nothing;
delete from mobit_ops.price_rule where market='KRW-BNB';

create table if not exists mobit_ops.price_sample (
  exchange text not null, market text not null references mobit_ops.price_rule on delete cascade,
  slot timestamptz not null, price numeric not null check (price > 0),
  primary key (exchange, market, slot)
);
create table if not exists mobit_ops.price_alert_state (
  exchange text not null, market text not null references mobit_ops.price_rule on delete cascade,
  basis text not null, primary key (exchange, market, basis)
);
alter table mobit_ops.price_alert_state
  add column if not exists up_percent numeric not null default 0,
  add column if not exists down_percent numeric not null default 0,
  add column if not exists last_slot timestamptz,
  add column if not exists trade_day date,
  drop column if exists direction;
create table if not exists mobit_ops.price_request (
  exchange text not null, market text not null references mobit_ops.price_rule on delete cascade,
  slot timestamptz not null, request_id bigint not null, processed boolean not null, retry_after timestamptz,
  primary key (exchange, market)
);

create or replace function mobit_ops.record_price_alerts(
  venue text, sampled_at timestamptz, ticker jsonb, endpoint text
) returns void language plpgsql security invoker set search_path = '' as $record$
declare
  rule mobit_ops.price_rule%rowtype;
  prior_price numeric;
  current_price numeric;
  state mobit_ops.price_alert_state%rowtype;
  trade_time timestamptz;
  venue_day date;
  hour_level numeric;
  exchange_level numeric;
  observed_level numeric;
  push_token text;
begin
  select * into rule from mobit_ops.price_rule where market = ticker->>'market';
  if not found or jsonb_typeof(ticker->'trade_price') is distinct from 'number'
    or jsonb_typeof(ticker->'trade_timestamp') is distinct from 'number' then return; end if;
  current_price := (ticker->>'trade_price')::numeric;
  -- 거래가 오래 끊긴 종목 및 지연 응답을 현재 시세로 기록하지 않는다.
  if current_price <= 0 or abs((ticker->>'trade_timestamp')::numeric / 1000 - extract(epoch from sampled_at)) > 60
    then return; end if;
  trade_time := to_timestamp((ticker->>'trade_timestamp')::numeric / 1000);
  venue_day := (trade_time at time zone (case when venue='bithumb' then 'Asia/Seoul' else 'UTC' end))::date;
  insert into mobit_ops.price_sample values (venue, rule.market, sampled_at, current_price)
    on conflict do nothing;
  if not found then return; end if;
  -- 같은 거래소에서 연속된 두 정각에 관측한 가격만 비교한다.
  if sampled_at = date_trunc('hour', sampled_at, 'UTC') then
    select price into prior_price from mobit_ops.price_sample where exchange=venue and market=rule.market
      and slot=sampled_at - interval '1 hour';
    hour_level := nullif(div((current_price-prior_price)*100, prior_price*rule.hour_percent)*rule.hour_percent, 0);
  end if;

  if jsonb_typeof(ticker->'signed_change_rate') = 'number' then
    observed_level := div((ticker->>'signed_change_rate')::numeric * 100, rule.exchange_percent) * rule.exchange_percent;
    insert into mobit_ops.price_alert_state(exchange,market,basis) values (venue,rule.market,'exchange')
      on conflict do nothing;
    select * into strict state from mobit_ops.price_alert_state
      where exchange=venue and market=rule.market and basis='exchange' for update;
    if state.last_slot is null or sampled_at > state.last_slot then
      if state.trade_day is distinct from venue_day then
        state.up_percent := 0;
        state.down_percent := 0;
      end if;
      if observed_level > state.up_percent then
        state.up_percent := observed_level;
        exchange_level := observed_level;
      elsif -observed_level > state.down_percent then
        state.down_percent := -observed_level;
        exchange_level := observed_level;
      end if;
      update mobit_ops.price_alert_state set up_percent=state.up_percent, down_percent=state.down_percent,
        trade_day=venue_day, last_slot=sampled_at
        where exchange=venue and market=rule.market and basis='exchange';
    end if;
  end if;
  if hour_level is null and exchange_level is null then return; end if;
  select decrypted_secret into strict push_token from vault.decrypted_secrets where name='mobit_push_cron_token';
  -- 같은 관측에서 나온 두 결과를 한 요청에 담고 표본·단계 기록과 함께 커밋한다.
  perform net.http_post(url := endpoint,
    headers := jsonb_build_object('Authorization','Bearer ' || push_token,'Content-Type','application/json'),
    body := jsonb_strip_nulls(jsonb_build_object('mode','price-alert','exchange',venue,'market',rule.market,
      'hourLevel',hour_level,'exchangeLevel',exchange_level,
      'endHourKst',case when hour_level is not null then extract(hour from sampled_at at time zone 'Asia/Seoul') end)),
    timeout_milliseconds := 45000);
end $record$;

create or replace function mobit_ops.check_price_alerts(endpoint text)
returns void language plpgsql security invoker set search_path = '' as $check$
declare
  minute_slot timestamptz := date_trunc('minute', now());
  pair record;
  pending record;
  ticker jsonb;
  queued bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('mobit-price-alerts',0));
  -- pg_net은 커밋 후 호출하므로 다음 분에 각 거래소의 응답을 독립적으로 처리한다.
  for pending in select p.*, r.status_code, r.content, r.timed_out
    from mobit_ops.price_request p join net._http_response r on r.id=p.request_id
    where not p.processed and p.slot >= minute_slot - interval '4 minutes'
  loop
    if pending.status_code = 200 and not coalesce(pending.timed_out,false) then
      begin
        for ticker in select value from jsonb_array_elements(pending.content::jsonb)
          where value->>'market' = pending.market loop
          perform mobit_ops.record_price_alerts(pending.exchange,pending.slot,ticker,endpoint);
        end loop;
      exception when data_exception then
        raise warning 'Invalid price response: % %', pending.exchange, pending.market;
      end;
    else
      raise warning 'Price lookup failed: % % HTTP %', pending.exchange, pending.market, pending.status_code;
    end if;
    update mobit_ops.price_request set processed=true,
      retry_after=case when pending.status_code=404 then pending.slot + interval '1 hour' end
      where request_id=pending.request_id;
  end loop;
  if extract(minute from minute_slot)::int % 5 <> 0 then return; end if;
  delete from mobit_ops.price_sample where slot < minute_slot - interval '65 minutes';
  -- 거래소에 없는 페어 하나가 다른 종목 조회까지 실패시키지 않도록 분리한다.
  for pair in select venue, r.market from unnest(array['upbit','bithumb']) as venue
    cross join mobit_ops.price_rule r
    where not exists (select 1 from mobit_ops.price_request p where p.exchange=venue
      and p.market=r.market and (p.slot >= minute_slot or p.retry_after > minute_slot))
  loop
    queued := net.http_get(url := 'https://api.' || pair.venue || '.com/v1/ticker',
      params := jsonb_build_object('markets',pair.market), timeout_milliseconds := 12000);
    insert into mobit_ops.price_request(exchange,market,slot,request_id,processed)
      values (pair.venue,pair.market,minute_slot,queued,false)
      on conflict (exchange,market) do update set slot=excluded.slot,request_id=excluded.request_id,
        processed=false,retry_after=null;
  end loop;
end $check$;
revoke all on function mobit_ops.record_price_alerts(text,timestamptz,jsonb,text),
  mobit_ops.check_price_alerts(text) from public, anon, authenticated;
