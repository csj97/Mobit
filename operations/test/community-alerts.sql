-- 빈 PostgreSQL에서 psql -v ON_ERROR_STOP=1 -f operations/test/community-alerts.sql
begin;
create role anon;
create role authenticated;
create role service_role;
create schema vault;
create schema net;
create table vault.decrypted_secrets(name text,decrypted_secret text);
create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int)
  returns bigint language sql as $$select 1::bigint$$;
\ir ../community-alerts.sql
do $qa$
declare first_run uuid:=gen_random_uuid(); next_run uuid:=gen_random_uuid();
  ids text[]:=array['old','1','2','3','4','5','6','7']; summary jsonb;
begin
  if has_function_privilege('anon','public.mobit_claim_community_digest(text[],uuid,boolean)','execute')
    or has_function_privilege('authenticated','public.mobit_finish_community_digest(uuid)','execute')
    then raise exception 'public access'; end if;
  perform public.mobit_claim_community_digest(array['old'],first_run,true);
  perform public.mobit_claim_community_digest(ids,next_run,true);
  summary:=public.mobit_claim_community_digest(ids,first_run,false);
  if summary <> '{"total":7,"preview_ids":["7","6","5","4","3"]}'::jsonb then raise exception 'daily digest or redeploy'; end if;
  if (public.mobit_claim_community_digest(ids,next_run,false)->>'total')::int <> 0 then raise exception 'overlap'; end if;
  update mobit_ops.community_alert_post set claimed_at=now()-interval '1 day' where not done;
  summary:=public.mobit_claim_community_digest(array_remove(ids,'7'),next_run,false);
  if (summary->>'total')::int <> 6 then raise exception 'retry included deleted post'; end if;
  perform public.mobit_finish_community_digest(first_run);
  if (select done from mobit_ops.community_alert_post where post_id='1') then raise exception 'stale receipt'; end if;
  perform public.mobit_finish_community_digest(next_run);
  if (public.mobit_claim_community_digest(array_remove(ids,'7'),first_run,false)->>'total')::int <> 0
    then raise exception 'duplicate after delivery or admin reply'; end if;
end $qa$;
rollback;
