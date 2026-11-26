create table if not exists mobit_ops.holding_quote_request (
  exchange text not null, market text not null, lane text not null, start_at timestamptz not null, end_at timestamptz not null,
  request_id bigint not null, sent_at timestamptz not null, processed boolean not null,
  primary key(exchange,market,lane)
);

create or replace function mobit_ops.apply_holding_quotes(
  venue text, pair text, window_start timestamptz, window_end timestamptz, candles jsonb
) returns void language plpgsql set search_path='' as $apply$
declare
  h record; extrema record; level numeric;
  samples jsonb;
begin
  if jsonb_typeof(candles) is distinct from 'array' or jsonb_array_length(candles)>200 then
    raise exception 'Invalid holding candles' using errcode='22000'; end if;
  -- 숫자는 JS Double을 거치지 않는다. 거래소의 UTC 분봉만 검증해 사용한다.
  if exists(select 1 from jsonb_to_recordset(candles) as c(market text,candle_date_time_utc text,
      low_price numeric,high_price numeric,trade_price numeric,unit int)
    where market is distinct from pair or unit is distinct from 1 or candle_date_time_utc is null
      or candle_date_time_utc !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00$'
      or low_price is null or high_price is null or trade_price is null or not
      (low_price>0 and low_price<=trade_price and trade_price<=high_price and high_price<1e80)
      or (candle_date_time_utc||'Z')::timestamptz >= window_end)
    or exists(select 1 from jsonb_array_elements(candles) c group by c->>'candle_date_time_utc' having count(*)>1)
    then raise exception 'Invalid holding candle values' using errcode='22000'; end if;
  select coalesce(jsonb_agg(c),'[]'::jsonb) into samples from jsonb_array_elements(candles) c
    where (c->>'candle_date_time_utc'||'Z')::timestamptz>=window_start;
  for h in select w.*,d.revision as device_revision from mobit_ops.holding_watch w
    join mobit_ops.push_device d using(owner) where d.token is not null and not w.closed and not w.paused
      and w.exchange=venue and w.market=pair and w.checked_until<window_end
      and (w.side='spot' or w.checked_until>=window_start)
    order by w.owner,w.holding for update of w
  loop
    select min(c.low_price) as low,max(c.high_price) as high,count(*) as minutes,
      (array_agg(c.trade_price order by c.candle_date_time_utc desc))[1] as close_price,
      max((c.candle_date_time_utc||'Z')::timestamptz) as last_minute into extrema
    from jsonb_to_recordset(samples) as c(low_price numeric,high_price numeric,trade_price numeric,candle_date_time_utc text)
    where (c.candle_date_time_utc||'Z')::timestamptz>=date_trunc('minute',h.checked_until);
    -- 진입한 첫 분의 선후 관계나 빈 구간을 확인할 수 없으면 앱이 검증한 새 스냅샷까지 보류한다.
    if h.side<>'spot' and (extrema.minutes <> extract(epoch from window_end-date_trunc('minute',h.checked_until))/60
        or (h.side='long' and extrema.low*h.units-h.cost<=-h.margin)
        or (h.side='short' and h.cost-extrema.high*h.units<=-h.margin)) then
      update mobit_ops.holding_watch set paused=true where owner=h.owner and holding=h.holding;
      continue;
    end if;
    update mobit_ops.holding_watch set checked_until=window_end where owner=h.owner and holding=h.holding;
    if extrema.last_minute is null or extrema.last_minute<h.effective_at or extrema.last_minute<>window_end-interval '1 minute'
      or window_end<now()-interval '5 minutes' then continue; end if;
    level := div((extrema.close_price*h.units-h.cost)*100,h.margin*5)*5 * case when h.side='short' then -1 else 1 end;
    if level<=h.up_level and -level<=h.down_level then continue; end if;
    update mobit_ops.holding_watch set up_level=greatest(up_level,level),down_level=greatest(down_level,-level)
      where owner=h.owner and holding=h.holding;
    insert into mobit_ops.holding_event(owner,holding,revision,device_revision,level,observed_at)
      values(h.owner,h.holding,h.revision,h.device_revision,level,window_end);
  end loop;
end $apply$;

create or replace function mobit_ops.check_holdings(endpoint text)
returns void language plpgsql set search_path='' as $check$
declare
  slot timestamptz:=date_trunc('minute',now());
  pending record; pair record; event_id uuid; secret text; first_minute timestamptz; until_minute timestamptz; queued bigint;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('mobit-holding-alerts',0)) then return; end if;
  delete from mobit_ops.holding_event where observed_at<slot-interval '10 minutes';
  for pending in select p.*,r.status_code,r.content from mobit_ops.holding_quote_request p
    join net._http_response r on r.id=p.request_id where not p.processed
  loop
    if pending.status_code=200 then
      begin
        perform mobit_ops.apply_holding_quotes(pending.exchange,pending.market,pending.start_at,pending.end_at,pending.content::jsonb);
      exception when data_exception then raise warning 'Invalid holding candles: % %',pending.exchange,pending.market;
      end;
    else raise warning 'Holding quote failed: % % HTTP %',pending.exchange,pending.market,pending.status_code;
    end if;
    update mobit_ops.holding_quote_request set processed=true where request_id=pending.request_id;
  end loop;
  -- 인수되기 전에 HTTP 요청이 실패한 경우만 재시도한다. 인수된 이벤트는 즉시 삭제된다.
  for event_id in update mobit_ops.holding_event set queued_at=slot
    where queued_at is null or queued_at<=slot-interval '2 minutes' returning id
  loop
    if secret is null then
      select decrypted_secret into strict secret from vault.decrypted_secrets where name='mobit_push_cron_token';
    end if;
    perform net.http_post(url:=endpoint,headers:=jsonb_build_object('Authorization','Bearer '||secret,'Content-Type','application/json'),
      body:=jsonb_build_object('mode','holding-alert','event',event_id),timeout_milliseconds:=45000);
  end loop;
  -- 거래소별로 오래 기다린 마켓부터 조회해 보유 기기 수와 무관하게 시세 요청을 공유한다.
  for pair in with watches as (
    select w.*,case when w.side<>'spot' and w.checked_until<slot-interval '175 minutes'
      then 'history' else 'recent' end as lane
      from mobit_ops.holding_watch w join mobit_ops.push_device d using(owner)
      where not w.closed and not w.paused and d.token is not null
  ), markets as (
    select exchange,market,lane,min(checked_until) filter(where side<>'spot') as earliest
      from watches group by exchange,market,lane
  ), ranked as (
    select m.*,row_number() over(partition by m.exchange order by p.sent_at nulls first,m.market,m.lane) as priority
    from markets m left join mobit_ops.holding_quote_request p using(exchange,market,lane)
    where p.sent_at is null or p.sent_at<=slot-interval '5 minutes'
  ) select * from ranked where priority<=5
  loop
    first_minute:=least(date_trunc('minute',pair.earliest),slot-interval '5 minutes');
    until_minute:=least(slot,first_minute+interval '180 minutes');
    queued:=net.http_get(url:='https://api.'||pair.exchange||'.com/v1/candles/minutes/1',
      params:=jsonb_build_object('market',pair.market,'count',(extract(epoch from until_minute-first_minute)/60)::int,
        'to',to_char(until_minute at time zone (case when pair.exchange='bithumb' then 'Asia/Seoul' else 'UTC' end),
        'YYYY-MM-DD"T"HH24:MI:SS')),timeout_milliseconds:=12000);
    insert into mobit_ops.holding_quote_request values(pair.exchange,pair.market,pair.lane,first_minute,until_minute,queued,slot,false)
      on conflict(exchange,market,lane) do update set start_at=excluded.start_at,end_at=excluded.end_at,request_id=excluded.request_id,
        sent_at=excluded.sent_at,processed=false;
  end loop;
end $check$;
revoke all on function mobit_ops.check_holdings(text),
  mobit_ops.apply_holding_quotes(text,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
