-- 빈 로컬 테스트 DB에서 psql -v ON_ERROR_STOP=1 -f operations/test/price-alerts.sql 로 실행한다.
begin;
create schema mobit_ops;
create schema net;
create schema vault;
create role anon;
create role authenticated;
create table vault.decrypted_secrets(name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('mobit_push_cron_token','test');
create table net._http_response(id bigint, content text, status_code int, timed_out boolean);
create table net.requests(id bigserial primary key, path text, payload jsonb);
create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int)
returns bigint language sql as $$ insert into net.requests(path,payload) values (url,body) returning id $$;
create function net.http_get(url text, params jsonb, timeout_milliseconds int)
returns bigint language sql as $$ insert into net.requests(path,payload) values (url,params) returning id $$;
\ir ../price-alerts.sql

create function sample(venue text, minutes int, price numeric, rate numeric, symbol text default 'KRW-BTC')
returns void language sql as $$
  select mobit_ops.record_price_alerts(venue,t,jsonb_build_object('market',symbol,'trade_price',price,
    'signed_change_rate',rate,'trade_timestamp',extract(epoch from t)*1000),'push')
    from (select timestamptz '2026-11-25 00:00Z' + minutes*interval '1 minute' as t) clock
$$;
create function check_alerts(venue text, symbol text, comparison text, expected numeric[]) returns void language plpgsql as $$
declare actual numeric[];
begin
  select array(select (payload->>(comparison || 'Level'))::numeric from net.requests
    where payload->>'market'=symbol and payload->>'exchange'=venue and payload ? (comparison || 'Level') order by id) into actual;
  if actual <> expected then raise exception '% % % expected %, got %',venue,symbol,comparison,expected,actual; end if;
end $$;

do $test$
begin
  if (select array_agg(market order by market) from mobit_ops.price_rule) <>
    array['KRW-AVAX','KRW-BTC','KRW-ETH','KRW-HYPE','KRW-SOL','KRW-TRX'] then raise exception 'market list'; end if;

  perform sample('upbit',0,100,0.04999);
  perform sample('upbit',5,100,0.05);
  perform sample('upbit',10,100,0.109);
  perform sample('upbit',10,100,0.109);
  perform sample('upbit',15,100,0.05);
  perform sample('upbit',20,100,0);
  perform sample('upbit',25,100,0.10);
  perform sample('upbit',30,100,-0.05);
  perform sample('upbit',35,100,0.10);
  perform sample('upbit',40,100,-0.214);
  perform sample('upbit',45,100,-0.15);
  perform sample('upbit',50,100,0.158);
  perform sample('upbit',55,100,0.20);
  perform check_alerts('upbit','KRW-BTC','exchange',array[5,10,-5,-20,15,20]);
  perform check_alerts('upbit','KRW-BTC','hour',array[]::numeric[]);
  perform sample('upbit',5,150,0.26,'KRW-SOL');
  perform check_alerts('upbit','KRW-SOL','exchange',array[25]);
  perform sample('bithumb',0,100,0,'KRW-HYPE');
  perform sample('bithumb',60,117,0.109,'KRW-HYPE');
  perform check_alerts('bithumb','KRW-HYPE','exchange',array[10]);
  perform check_alerts('bithumb','KRW-HYPE','hour',array[15]);

  -- 같은 UTC 날짜라도 빗썸은 한국 자정에, 업비트는 UTC 자정에 새로 시작한다.
  perform sample('bithumb',895,100,0.10);
  perform sample('bithumb',900,100,0.05);
  perform sample('bithumb',1440,110,0.05);
  perform check_alerts('bithumb','KRW-BTC','exchange',array[10,5]);
  perform sample('upbit',900,100,0.05);
  perform sample('upbit',1440,100,0.05);
  perform check_alerts('upbit','KRW-BTC','exchange',array[5,10,-5,-20,15,20,5]);

  -- 비정각에 1시간 전 표본이 있어도 일간 기준만 발송한다.
  perform sample('upbit',0,100,0,'KRW-ETH');
  perform sample('upbit',5,100,0,'KRW-ETH');
  perform sample('upbit',60,105,0,'KRW-ETH');
  perform sample('upbit',65,120,0.10,'KRW-ETH');
  perform sample('upbit',120,110.25,0.10,'KRW-ETH');
  perform sample('upbit',120,110.25,0.10,'KRW-ETH');
  perform sample('upbit',180,99,-0.06,'KRW-ETH');
  perform sample('upbit',300,80,-0.16,'KRW-ETH'); -- 240분 정각 표본 누락
  perform check_alerts('upbit','KRW-ETH','hour',array[5,5,-10]);
  perform check_alerts('upbit','KRW-ETH','exchange',array[10,-5,-15]);
  if (select count(*) from net.requests where payload->>'market'='KRW-HYPE') <> 1
    or not exists (select 1 from net.requests where payload->>'market'='KRW-HYPE'
      and payload @> '{"hourLevel":15,"exchangeLevel":10,"endHourKst":10}')
    then raise exception 'combined send'; end if;
  perform sample('bithumb',120,123,-0.15,'KRW-HYPE');
  if not exists (select 1 from net.requests where payload->>'market'='KRW-HYPE'
    and payload @> '{"hourLevel":5,"exchangeLevel":-15,"endHourKst":11}') then raise exception 'opposite directions'; end if;

  update mobit_ops.price_rule set exchange_percent=7 where market='KRW-TRX';
  perform sample('upbit',5,100,0.18,'KRW-TRX');
  perform check_alerts('upbit','KRW-TRX','exchange',array[14]);
  perform sample('upbit',10,100,0.1,'KRW-BNB');
  perform check_alerts('upbit','KRW-BNB','exchange',array[]::numeric[]);
  perform mobit_ops.record_price_alerts('upbit','2026-11-25 02:00Z',
    '{"market":"KRW-BTC","trade_price":200,"signed_change_rate":0.5,"trade_timestamp":0}','push');
  if exists (select 1 from mobit_ops.price_sample where market='KRW-BTC' and slot='2026-11-25 02:00Z')
    then raise exception 'stale trade accepted'; end if;
end $test$;
rollback;
