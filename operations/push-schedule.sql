do $schedule$
declare
  zone text := coalesce(nullif(current_setting('cron.timezone', true), ''), 'GMT');
  task text := 'select mobit_ops.enqueue_push(''https://__PROJECT_REF__.supabase.co/functions/v1/send-mobit-push'')';
  monday text := 'mobit-weekly-push';
  slot record;
  job_id bigint;
  monday_active boolean;
begin
  if zone not in ('UTC', 'GMT', 'Etc/UTC', 'Etc/GMT', 'Asia/Seoul') then
    raise exception '지원하지 않는 Cron 시간대 %', zone;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(monday, 0));
  select active into monday_active from cron.job where jobname = monday and username = current_user;
  for slot in select * from (values
    (monday, case when zone = 'Asia/Seoul' then '0 9 * * 1' else '0 0 * * 1' end),
    ('mobit-weekly-push-sat', case when zone = 'Asia/Seoul' then '0 19 * * 6' else '0 10 * * 6' end)
  ) as slots(name, schedule)
  loop
    select jobid into job_id from cron.job where jobname = slot.name and username = current_user;
    if found then
      perform cron.alter_job(job_id, schedule := slot.schedule, command := task);
    else
      job_id := cron.schedule(slot.name, slot.schedule, task);
      -- 기존 예약이 일시 중지 상태라면 새 회차도 중지 상태로 추가한다.
      if monday_active is false then
        perform cron.alter_job(job_id, active := false);
      end if;
    end if;
  end loop;
end $schedule$;
