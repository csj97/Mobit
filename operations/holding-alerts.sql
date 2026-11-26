-- 앱에는 본인 소유 정보를 변경하는 RPC만 노출한다. 테이블과 발송 함수는 비공개다.
create table if not exists mobit_ops.push_device (
  owner uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null, token text unique
);
create table if not exists mobit_ops.holding_watch (
  owner uuid not null references auth.users(id) on delete cascade, holding uuid not null,
  revision bigint not null, closed boolean not null, paused boolean not null default false,
  exchange text, market text, side text, units numeric, cost numeric, margin numeric,
  effective_at timestamptz not null, checked_until timestamptz not null,
  up_level numeric not null default 0, down_level numeric not null default 0,
  primary key(owner,holding)
);
create index if not exists holding_watch_market on mobit_ops.holding_watch(exchange,market) where not closed and not paused;
create table if not exists mobit_ops.holding_event (
  id uuid primary key default gen_random_uuid(), owner uuid not null, holding uuid not null,
  revision bigint not null, device_revision bigint not null, level numeric not null,
  observed_at timestamptz not null, queued_at timestamptz, foreign key(owner,holding) references mobit_ops.holding_watch on delete cascade
);

create or replace function public.mobit_set_push_device(p_revision bigint, p_token text)
returns void language plpgsql security definer set search_path='' as $device$
begin
  if auth.uid() is null or p_revision is null or p_revision < 1
    or (p_token is not null and (length(p_token) not between 16 and 4096 or p_token !~ '^[A-Za-z0-9_:-]+$'))
    then raise exception 'Invalid device registration'; end if;
  insert into mobit_ops.push_device as d values(auth.uid(),p_revision,p_token)
    on conflict(owner) do update set revision=excluded.revision,token=excluded.token where d.revision < excluded.revision;
exception when unique_violation then
  raise exception 'Device token already registered';
end $device$;

create or replace function public.mobit_sync_holding(
  p_holding uuid, p_revision bigint, p_closed boolean, p_effective_at timestamptz,
  p_exchange text default null, p_market text default null, p_side text default null,
  p_fill_price numeric default null, p_average numeric default null, p_units numeric default null,
  p_cost numeric default null, p_margin numeric default null
) returns void language plpgsql security definer set search_path='' as $sync$
declare
  baseline numeric := 0;
begin
  if auth.uid() is null or p_holding is null or p_revision is null or p_revision < 1 or p_closed is null
    or p_effective_at is null or not isfinite(p_effective_at) or p_effective_at < '2000-01-01'::timestamptz
    or p_effective_at > now()+interval '1 minute' then raise exception 'Invalid snapshot'; end if;
  if not p_closed then
    if p_exchange is null or p_exchange not in ('upbit','bithumb') or p_market is null or p_market !~ '^(KRW|BTC)-[A-Z0-9]{1,20}$'
      or p_side is null or p_side not in ('spot','long','short') or (p_side <> 'spot' and p_market not like 'KRW-%')
      then raise exception 'Invalid market or side'; end if;
    if p_side='spot' then p_units:=1; p_cost:=p_average; p_margin:=p_average; end if;
    if exists(select 1 from unnest(array[p_fill_price,p_cost,p_units,p_margin]) n
      where n is null or not (n > 0 and n <= 1e80) or scale(n)>80) then raise exception 'Invalid price data'; end if;
    baseline := div((p_fill_price*p_units-p_cost)*100,5*p_margin)*5 * case when p_side='short' then -1 else 1 end;
    if p_side <> 'spot' and baseline <= -100 then raise exception 'Position already liquidated'; end if;
  end if;
  insert into mobit_ops.holding_watch as h(owner,holding,revision,closed,exchange,market,side,units,cost,margin,
    effective_at,checked_until,up_level,down_level)
    values(auth.uid(),p_holding,p_revision,p_closed,p_exchange,p_market,p_side,p_units,p_cost,p_margin,
      p_effective_at,p_effective_at,greatest(baseline,0),greatest(-baseline,0))
    on conflict(owner,holding) do update set revision=excluded.revision,closed=excluded.closed,paused=false,
      exchange=excluded.exchange,market=excluded.market,side=excluded.side,units=excluded.units,
      cost=excluded.cost,margin=excluded.margin,effective_at=excluded.effective_at,checked_until=excluded.checked_until,
      up_level=greatest(h.up_level,excluded.up_level),down_level=greatest(h.down_level,excluded.down_level)
    where not h.closed and excluded.revision>h.revision and (excluded.closed or
      (excluded.effective_at>=h.effective_at and excluded.exchange=h.exchange and excluded.market=h.market and excluded.side=h.side));
end $sync$;

-- 큐에 넣은 이후 매도·설정 변경·토큰 교체가 일어나면 실제 발송 직전에 폐기한다.
create or replace function public.mobit_claim_holding_event(p_event uuid) returns jsonb
language sql volatile security definer set search_path='' as $claim$
  with claimed as (delete from mobit_ops.holding_event where id=p_event returning *)
  select jsonb_build_object('token',d.token,'holding',h.holding,'exchange',h.exchange,'market',h.market,
    'side',h.side,'level',e.level::text)
  from claimed e join mobit_ops.holding_watch h using(owner,holding) join mobit_ops.push_device d using(owner)
  where h.revision=e.revision and not h.closed and not h.paused and d.revision=e.device_revision and d.token is not null
    and e.observed_at >= now()-interval '10 minutes';
$claim$;
revoke all on function public.mobit_set_push_device(bigint,text),
  public.mobit_sync_holding(uuid,bigint,boolean,timestamptz,text,text,text,numeric,numeric,numeric,numeric,numeric),
  public.mobit_claim_holding_event(uuid) from public,anon,authenticated;
grant execute on function public.mobit_set_push_device(bigint,text),
  public.mobit_sync_holding(uuid,bigint,boolean,timestamptz,text,text,text,numeric,numeric,numeric,numeric,numeric)
  to authenticated;
grant execute on function public.mobit_claim_holding_event(uuid) to service_role;
notify pgrst, 'reload schema';
