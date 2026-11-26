-- pg_net 성공은 큐 등록을 의미하므로 실제 Edge 응답으로 재시도 여부를 판단한다.
create schema if not exists mobit_ops;
revoke all on schema mobit_ops from public, anon, authenticated;

create table if not exists mobit_ops.coin_refresh (
  singleton boolean primary key check (singleton),
  scheduled_day date not null,
  request_id bigint not null,
  submitted_at timestamptz not null
);

create or replace function mobit_ops.enqueue_coin_refresh(endpoint text, deployment boolean default false)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  -- 각 예약 시각(:05) 이후의 성공만 해당 회차의 재시도를 막는다.
  scheduled_start timestamptz := date_trunc('hour', now(), 'Asia/Seoul') + interval '5 minutes';
  previous mobit_ops.coin_refresh%rowtype;
  token text;
  queued bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('mobit_ops.coin_refresh', 0));
  select * into previous from mobit_ops.coin_refresh where singleton;
  if previous.scheduled_day = today and (
    (previous.submitted_at > now() - interval '3 minutes' and not exists (
      select 1 from net._http_response where id = previous.request_id
    )) or (not deployment and previous.submitted_at >= scheduled_start and exists (
      select 1 from net._http_response
       where id = previous.request_id and status_code between 200 and 299
    ))
  ) then
    return previous.request_id;
  end if;

  select decrypted_secret into strict token from vault.decrypted_secrets where name = 'mobit_coin_cron_token';
  select net.http_post(
    url := endpoint,
    headers := jsonb_build_object('Authorization', 'Bearer ' || token, 'Content-Type', 'application/json',
                                  'x-region', 'ap-northeast-2'),
    body := '{}'::jsonb, timeout_milliseconds := 145000
  ) into queued;
  insert into mobit_ops.coin_refresh values (true, today, queued, now())
    on conflict (singleton) do update set scheduled_day = excluded.scheduled_day,
      request_id = excluded.request_id, submitted_at = excluded.submitted_at;
  return queued;
end;
$$;
revoke all on function mobit_ops.enqueue_coin_refresh(text, boolean) from public, anon, authenticated;
