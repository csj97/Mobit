create table if not exists mobit_ops.usage_daily (
  report_day date primary key,
  edge_calls bigint not null check (edge_calls >= 0)
);

create or replace function public.mobit_usage_report(p_day date, p_calls bigint, p_preview boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  database_bytes bigint;
begin
  select sum(pg_database_size(datname)) into database_bytes from pg_database;
  if not p_preview then
    delete from mobit_ops.usage_daily where report_day < p_day - 29;
    if p_calls is not null then
      insert into mobit_ops.usage_daily values (p_day, p_calls)
        on conflict (report_day) do update set edge_calls=excluded.edge_calls;
    end if;
  end if;
  return (select jsonb_build_object('database_bytes',database_bytes,'days',count(*),'calls',coalesce(sum(edge_calls),0))
    from mobit_ops.usage_daily where report_day between p_day - 29 and p_day);
end $$;
revoke all on function public.mobit_usage_report(date,bigint,boolean) from public,anon,authenticated;
grant execute on function public.mobit_usage_report(date,bigint,boolean) to service_role;
notify pgrst,'reload schema';

create or replace function mobit_ops.enqueue_usage_report(endpoint text) returns bigint
language sql set search_path='' as $$
  select net.http_post(url:=endpoint,headers:=jsonb_build_object('Authorization','Bearer '||decrypted_secret,
    'Content-Type','application/json'),body:='{"mode":"usage"}'::jsonb,timeout_milliseconds:=60000)
  from vault.decrypted_secrets where name='mobit_community_cron_token';
$$;
revoke all on function mobit_ops.enqueue_usage_report(text) from public,anon,authenticated;
