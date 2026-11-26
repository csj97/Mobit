-- 빈 PostgreSQL에서 psql -v ON_ERROR_STOP=1 -f operations/test/holding-alerts.sql
begin;
create schema auth;
create role anon;
create role authenticated;
create role service_role;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql as $$select current_setting('test.uid', true)::uuid$$;
create schema mobit_ops;
create schema net;
create schema vault;
create table vault.decrypted_secrets(name text,decrypted_secret text);
insert into vault.decrypted_secrets values ('mobit_push_cron_token','fixture');
create table net.requests(id bigserial primary key,url text,payload jsonb);
create table net._http_response(id bigint,content text,status_code int);
create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int) returns bigint language sql
 as $$insert into net.requests(url,payload) values($1,$3) returning id$$;
create function net.http_get(url text,params jsonb,timeout_milliseconds int) returns bigint language sql
 as $$insert into net.requests(url,payload) values($1,$2) returning id$$;
\ir ../holding-alerts.sql
\ir ../holding-cron.sql

do $qa$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); position uuid:=gen_random_uuid();
  t timestamptz:=date_trunc('minute',now());
  candle jsonb:=jsonb_build_object('market','KRW-BTC','unit',1,'trade_price',105,'low_price',100,'high_price',105,
    'candle_date_time_utc',to_char((t-interval '1 minute') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS'));
  event uuid; msg jsonb; request bigint;
begin
  if has_function_privilege('authenticated','public.mobit_claim_holding_event(uuid)','execute')
    or has_function_privilege('anon','public.mobit_set_push_device(bigint,text)','execute') then raise exception 'RPC grants'; end if;
  insert into auth.users values(a),(b);
  perform set_config('test.uid',a::text,true);
  perform public.mobit_set_push_device(1,'fixture:a-123456789');
  perform public.mobit_sync_holding(position,1,false,t-interval '2 minutes','bithumb','KRW-BTC','spot',100,100);
  perform public.mobit_sync_holding(position,2,false,t-interval '1 minute','bithumb','KRW-BTC','spot',99,100);
  perform public.mobit_sync_holding(position,1,true,t);
  perform set_config('test.uid',b::text,true);
  perform public.mobit_set_push_device(1,'fixture:b-123456789');
  perform public.mobit_sync_holding(position,1,false,t-interval '1 minute','bithumb','KRW-BTC','short',105,null,1,105,3);
  perform mobit_ops.check_holdings('push');
  if (select count(*) from net.requests)<>1 then raise exception 'shared quote request'; end if;
  select id into request from net.requests;
  insert into net._http_response values(request,jsonb_build_array(candle)::text,200);
  perform mobit_ops.check_holdings('push');
  perform mobit_ops.check_holdings('push');
  select id into strict event from mobit_ops.holding_event;
  msg:=public.mobit_claim_holding_event(event);
  if msg->>'token' is distinct from 'fixture:a-123456789' or (msg->>'level')::numeric<>5
    or public.mobit_claim_holding_event(event) is not null then raise exception 'claim or duplicate'; end if;
  -- 저점에서 반등했더라도 숏의 청산가는 분봉 고가로 검사한다.
  update mobit_ops.holding_watch set checked_until=t-interval '1 minute' where owner=b;
  perform mobit_ops.apply_holding_quotes('bithumb','KRW-BTC',t-interval '1 minute',t,
    jsonb_build_array(candle||'{"high_price":109,"trade_price":102}'));
  if not (select paused from mobit_ops.holding_watch where owner=b) then raise exception 'missed liquidation'; end if;
  perform set_config('test.uid',a::text,true);
  update mobit_ops.holding_watch set checked_until=t-interval '1 minute' where owner=a;
  perform mobit_ops.apply_holding_quotes('bithumb','KRW-BTC',t-interval '1 minute',t,
    jsonb_build_array(candle||'{"high_price":119,"trade_price":119}'));
  select id into strict event from mobit_ops.holding_event where level=15;
  perform public.mobit_sync_holding(position,3,true,t);
  perform public.mobit_sync_holding(position,2,false,t,'bithumb','KRW-BTC','spot',100,100);
  if public.mobit_claim_holding_event(event) is not null then raise exception 'sent after close'; end if;
  -- 정확히 5%인 순환비와 손실 방향도 소수 나눗셈 없이 판정한다.
  position:=gen_random_uuid();
  perform public.mobit_sync_holding(position,1,false,t-interval '1 minute','upbit','KRW-BTC','long',30,null,1,30,3);
  perform mobit_ops.apply_holding_quotes('upbit','KRW-BTC',t-interval '1 minute',t,jsonb_build_array(
    candle||'{"low_price":29.85,"high_price":30,"trade_price":29.85}'));
  select id into strict event from mobit_ops.holding_event where level=-5;
  perform public.mobit_set_push_device(2,null);
  perform public.mobit_set_push_device(1,'fixture:a-123456789');
  if public.mobit_claim_holding_event(event) is not null then raise exception 'sent after opt out'; end if;
  -- 재등록된 기기에 미검증 과거 구간이 있더라도 현재 시세와 다른 보유 건을 섞지 않는다.
  perform public.mobit_set_push_device(3,'fixture:a-new-token');
  perform public.mobit_sync_holding(gen_random_uuid(),1,false,t-interval '1 day','upbit','KRW-BTC','long',30,null,1,30,3);
  perform mobit_ops.check_holdings('push');
  if (select count(*) from mobit_ops.holding_quote_request where exchange='upbit')<>2
    then raise exception 'history catch-up starved recent watches'; end if;
  perform mobit_ops.apply_holding_quotes('upbit','KRW-BTC',t,t+interval '1 minute','[]'::jsonb);
  if not (select paused from mobit_ops.holding_watch where owner=a and holding=position)
    then raise exception 'missing futures minute did not pause'; end if;
  perform public.mobit_sync_holding(position,2,false,t,'upbit','KRW-BTC','long',30,null,1,30,3);
  if (select paused from mobit_ops.holding_watch where owner=a and holding=position)
    then raise exception 'verified snapshot did not resume'; end if;
end $qa$;
-- 동일 토큰 재연결과 토큰 교체 모두 이전 등록의 발송 대기를 무효화한다.
do $cycle$
declare
  owner_id uuid := gen_random_uuid();
  holding_id uuid := gen_random_uuid();
  minute_end timestamptz := date_trunc('minute', now());
  first_minute timestamptz := minute_end - interval '3 minutes';
  candle jsonb := '{"market":"KRW-SOL","unit":1,"low_price":100,"high_price":106,"trade_price":106}';
  old_event uuid;
  new_event uuid;
begin
  insert into auth.users values(owner_id);
  perform set_config('test.uid',owner_id::text,true);
  perform public.mobit_sync_holding(holding_id,1,false,first_minute,'upbit','KRW-SOL','spot',100,100);
  perform public.mobit_set_push_device(1,'fixture:initial-sol');
  perform mobit_ops.apply_holding_quotes('upbit','KRW-SOL',first_minute,first_minute+interval '1 minute',
    jsonb_build_array(candle||jsonb_build_object('candle_date_time_utc',to_char(first_minute at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS'))));
  select id into strict old_event from mobit_ops.holding_event where owner=owner_id and level=5;

  perform public.mobit_set_push_device(2,null);
  perform mobit_ops.apply_holding_quotes('upbit','KRW-SOL',first_minute+interval '1 minute',minute_end-interval '1 minute',
    jsonb_build_array(candle||jsonb_build_object('high_price',120,'trade_price',120,'candle_date_time_utc',
      to_char((first_minute+interval '1 minute') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS'))));
  if (select count(*) from mobit_ops.holding_event where owner=owner_id) <> 1 then raise exception 'event generated while off'; end if;
  perform public.mobit_set_push_device(3,'fixture:initial-sol');
  perform public.mobit_set_push_device(2,null);
  if public.mobit_claim_holding_event(old_event) is not null then raise exception 'old push after same-token reactivation'; end if;
  if (select token from mobit_ops.push_device where owner=owner_id) is distinct from 'fixture:initial-sol'
    then raise exception 'stale opt out superseded reactivation'; end if;

  perform public.mobit_set_push_device(4,'fixture:rotated-sol');
  perform mobit_ops.apply_holding_quotes('upbit','KRW-SOL',minute_end-interval '1 minute',minute_end,
    jsonb_build_array(candle||jsonb_build_object('high_price',111,'trade_price',111,'candle_date_time_utc',
      to_char((minute_end-interval '1 minute') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS'))));
  select id into strict new_event from mobit_ops.holding_event where owner=owner_id and level=10;
  if public.mobit_claim_holding_event(new_event)->>'token' is distinct from 'fixture:rotated-sol'
    then raise exception 'new alert not routed to latest token'; end if;
end $cycle$;
do $reinstall$
declare
  old_id uuid:=gen_random_uuid(); new_id uuid:=gen_random_uuid(); position uuid:=gen_random_uuid();
  event_id uuid:=gen_random_uuid(); shared_token text:='fixture:reinstall-token';
begin
  if has_function_privilege('anon','public.mobit_retire_holding_installation()','execute')
    or not has_function_privilege('authenticated','public.mobit_retire_holding_installation()','execute')
    or has_function_privilege('authenticated','public.mobit_clear_invalid_holding_token(uuid,bigint,text)','execute')
    then raise exception 'reinstall RPC grants'; end if;
  insert into auth.users values(old_id),(new_id);
  perform set_config('test.uid',old_id::text,true);
  perform public.mobit_sync_holding(position,1,false,now(),'upbit','KRW-BTC','spot',100,100);
  perform public.mobit_set_push_device(1,shared_token);
  insert into mobit_ops.holding_event(id,owner,holding,revision,device_revision,level,observed_at)
    values(event_id,old_id,position,1,1,5,now());
  perform public.mobit_retire_holding_installation();
  perform set_config('test.uid',new_id::text,true);
  perform public.mobit_set_push_device(1,shared_token);
  perform public.mobit_sync_holding(position,1,false,now(),'upbit','KRW-ETH','spot',10,10);
  perform set_config('test.uid',old_id::text,true);
  perform public.mobit_retire_holding_installation();
  perform public.mobit_sync_holding(position,1000,false,now(),'upbit','KRW-BTC','spot',100,100);
  perform public.mobit_set_push_device(1000,'fixture:stale-token');
  if public.mobit_claim_holding_event(event_id) is not null or exists(select from mobit_ops.holding_watch where owner=old_id)
    or exists(select from mobit_ops.push_device where owner=old_id and token is not null)
    or not exists(select from mobit_ops.holding_watch where owner=new_id and market='KRW-ETH')
    then raise exception 'reinstall owner isolation'; end if;
  perform public.mobit_clear_invalid_holding_token(old_id,1,shared_token);
  perform public.mobit_clear_invalid_holding_token(new_id,2,shared_token);
  perform public.mobit_clear_invalid_holding_token(new_id,1,'fixture:stale-token');
  if (select token from mobit_ops.push_device where owner=new_id) is distinct from shared_token
    then raise exception 'outdated FCM rejection disabled new registration'; end if;
  perform public.mobit_clear_invalid_holding_token(new_id,1,shared_token);
  if exists(select from mobit_ops.push_device where owner=new_id and token is not null)
    then raise exception 'invalid token retained'; end if;
end $reinstall$;
rollback;
