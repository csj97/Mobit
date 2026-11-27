-- 빈 PostgreSQL에서 psql -v ON_ERROR_STOP=1 -f operations/test/cron-history.sql
begin;
create schema cron;
create table cron.job(jobid bigserial primary key, jobname text, username text default current_user,
  schedule text, command text, active boolean default true, unique(jobname, username));
create table cron.job_run_details(runid int primary key, jobid bigint, username text, end_time timestamptz);
create function cron.schedule(text,text,text) returns bigint language sql as $$
  insert into cron.job(jobname,schedule,command) values($1,$2,$3) returning jobid
$$;
create function cron.alter_job(jobid bigint, schedule text, command text) returns void language sql as $$
  update cron.job j set schedule=$2,command=$3 where j.jobid=$1
$$;
set local cron.timezone = 'GMT';
\ir ../cron-history.sql
do $$begin
  if (select schedule from cron.job where active) is distinct from '0 19 * * *' then raise exception 'UTC schedule'; end if;
end$$;
update cron.job set active=false;
set local cron.timezone = 'Asia/Seoul';
\ir ../cron-history.sql
do $qa$
declare
  task cron.job;
  holding_job bigint;
  other_job bigint;
  old timestamptz := now()-interval '8 days';
begin
  select * into strict task from cron.job;
  if task.active or task.schedule <> '0 4 * * *' then raise exception 'redeploy or KST schedule'; end if;
  holding_job := cron.schedule('mobit-holding-alerts','* * * * *','select 1');
  other_job := cron.schedule('unrelated','* * * * *','select 1');
  insert into cron.job_run_details values (1,holding_job,current_user,old),(2,task.jobid,current_user,old),
    (3,holding_job,current_user,now()-interval '7 days'),(4,holding_job,current_user,null),
    (5,other_job,current_user,old),(6,holding_job,'another_owner',old),(7,holding_job,current_user,now());
  execute task.command;
  execute task.command;
  if (select array_agg(runid order by runid) from cron.job_run_details) is distinct from array[3,4,5,6,7]
    then raise exception 'cleanup scope'; end if;
end $qa$;
set local cron.timezone = 'UTC';
\ir ../holding-cleanup-schedule.sql
do $$begin
  if not exists(select from cron.job where jobname='mobit-cleanup-closed-holdings' and active
      and schedule='0 19 * * *' and command='select mobit_ops.cleanup_closed_holdings()') then raise exception 'cleanup UTC'; end if;
end$$;
update cron.job set active=false where jobname='mobit-cleanup-closed-holdings';
set local cron.timezone = 'Asia/Seoul';
\ir ../holding-cleanup-schedule.sql
do $$begin
  if not exists(select from cron.job where jobname='mobit-cleanup-closed-holdings' and not active
      and schedule='0 4 * * *') then raise exception 'cleanup KST redeploy'; end if;
end$$;
rollback;
