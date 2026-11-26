create schema if not exists mobit_ops;
revoke all on schema mobit_ops from public, anon, authenticated;

-- 큐 등록과 회차 기록을 같은 트랜잭션에 두어 중복 호출을 막는다.
create table if not exists mobit_ops.push_run (
  singleton boolean primary key check (singleton),
  submitted_minute timestamptz not null,
  request_id bigint not null
);

create or replace function mobit_ops.enqueue_push(endpoint text)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  slot timestamptz := date_trunc('minute', now());
  previous mobit_ops.push_run%rowtype;
  token text;
  queued bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('mobit_ops.push_run', 0));
  select * into previous from mobit_ops.push_run where singleton;
  if previous.submitted_minute >= slot then
    return previous.request_id;
  end if;
  select decrypted_secret into strict token from vault.decrypted_secrets where name = 'mobit_push_cron_token';
  select net.http_post(url := endpoint,
    headers := jsonb_build_object('Authorization', 'Bearer ' || token, 'Content-Type', 'application/json'),
    body := '{"mode":"send"}'::jsonb, timeout_milliseconds := 45000) into queued;
  insert into mobit_ops.push_run values (true, slot, queued)
    on conflict (singleton) do update set submitted_minute = excluded.submitted_minute,
      request_id = excluded.request_id;
  return queued;
end;
$$;
revoke all on function mobit_ops.enqueue_push(text) from public, anon, authenticated;
