create schema if not exists mobit_ops;
revoke all on schema mobit_ops from public,anon,authenticated;

-- 글이 없는 게시판도 최초 기준점 등록과 재배포를 구분한다.
create table if not exists mobit_ops.community_alert_start (
  singleton boolean primary key check(singleton)
);
create table if not exists mobit_ops.community_alert_post (
  post_id text primary key, done boolean not null, run_id uuid, claimed_at timestamptz
);
create index if not exists community_alert_pending on mobit_ops.community_alert_post(post_id) where not done;

create or replace function public.mobit_claim_community_digest(p_ids text[], p_run uuid, p_initialize boolean)
returns jsonb language plpgsql security definer set search_path='' as $claim$
declare summary jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('mobit-community-alerts',0));
  if p_initialize then
    insert into mobit_ops.community_alert_start values(true) on conflict do nothing;
    if found then
      insert into mobit_ops.community_alert_post(post_id,done) select id,true from unnest(p_ids) id;
    end if;
    return jsonb_build_object('total',0,'preview_ids','[]'::jsonb);
  end if;
  if not exists(select from mobit_ops.community_alert_start) then raise exception 'Initialize community alerts first'; end if;
  insert into mobit_ops.community_alert_post(post_id,done)
    select id,false from unnest(p_ids) id on conflict do nothing;
  -- 당일 확인한 새 글 전체를 한 묶음으로 예약하고, 본문은 최근 5건만 읽는다.
  with claimed as (
    update mobit_ops.community_alert_post set run_id=p_run,claimed_at=now()
    where not done and post_id=any(p_ids) and (claimed_at is null or claimed_at < now()-interval '4 minutes')
    returning post_id
  )
  select jsonb_build_object('total',(select count(*) from claimed),
    'preview_ids',array(select post_id from claimed order by post_id collate "C" desc limit 5)) into summary;
  return summary;
end $claim$;
create or replace function public.mobit_finish_community_digest(p_run uuid)
returns void language sql security definer set search_path='' as $finish$
  update mobit_ops.community_alert_post set done=true,run_id=null,claimed_at=null where run_id=p_run and not done;
$finish$;
revoke all on function public.mobit_claim_community_digest(text[],uuid,boolean),public.mobit_finish_community_digest(uuid)
  from public, anon, authenticated;
grant execute on function public.mobit_claim_community_digest(text[],uuid,boolean),public.mobit_finish_community_digest(uuid)
  to service_role;
notify pgrst,'reload schema';

create or replace function mobit_ops.enqueue_community_alerts(endpoint text) returns bigint
language sql set search_path='' as $enqueue$
  select net.http_post(url:=endpoint,headers:=jsonb_build_object('Authorization','Bearer '||decrypted_secret,
    'Content-Type','application/json'),body:='{"mode":"poll"}'::jsonb,timeout_milliseconds:=150000)
  from vault.decrypted_secrets where name='mobit_community_cron_token';
$enqueue$;
revoke all on function mobit_ops.enqueue_community_alerts(text) from public,anon,authenticated;
