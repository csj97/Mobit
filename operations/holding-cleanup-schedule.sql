do $schedule$
declare
  job_name constant text := 'mobit-cleanup-closed-holdings';
  task constant text := 'select mobit_ops.cleanup_closed_holdings()';
  zone text := coalesce(nullif(current_setting('cron.timezone',true),''),'GMT');
  schedule_at text;
  job_id bigint;
begin
  if zone not in ('UTC','GMT','Etc/UTC','Etc/GMT','Asia/Seoul') then
    raise exception '지원하지 않는 Cron 시간대 %', zone;
  end if;
  schedule_at := case when zone='Asia/Seoul' then '0 4 * * *' else '0 19 * * *' end;
  perform pg_advisory_xact_lock(hashtextextended(job_name,0));
  select jobid into job_id from cron.job where jobname=job_name and username=current_user;
  if found then
    perform cron.alter_job(job_id, schedule := schedule_at, command := task);
  else
    perform cron.schedule(job_name,schedule_at,task);
  end if;
end $schedule$;
