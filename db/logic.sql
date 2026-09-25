create or replace function public.gl_record_attendance(p_session uuid,p_rows jsonb) returns void language plpgsql security invoker set search_path=public as $$
declare s gl_sessions; e gl_enrollments; r jsonb; a gl_attendance; charged boolean;
begin
 select * into strict s from gl_sessions where id=p_session for update;
 if s.status='cancelled' then raise exception 'Session is cancelled'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Attendance required'; end if;
 for r in select * from jsonb_array_elements(p_rows) loop
  select * into strict e from gl_enrollments where id=(r->>'enrollment_id')::uuid;
  if not ((s.group_id is not null and e.group_id=s.group_id) or s.enrollment_id=e.id) then raise exception 'Enrollment does not belong to session'; end if;
  if r->>'status' not in ('present','absent_charged','absent_excused') then raise exception 'Invalid attendance'; end if;
  charged := r->>'status' in ('present','absent_charged');
  insert into gl_attendance(session_id,student_id,enrollment_id,status,consumes_credit,price_snapshot)
  values(s.id,e.student_id,e.id,r->>'status',charged and e.billing_model='package',e.price)
  on conflict(session_id,student_id) do update set status=excluded.status,consumes_credit=excluded.consumes_credit
  returning * into a;
  if e.billing_model='per_session' and charged then
   insert into gl_charges(student_id,enrollment_id,charged_on,amount,reason,attendance_id,note)
   values(e.student_id,e.id,s.held_on,a.price_snapshot,'session',a.id,coalesce(s.topic,'Session'))
   on conflict(attendance_id) where attendance_id is not null do nothing;
  else delete from gl_charges where attendance_id=a.id; end if;
 end loop;
end $$;
create or replace function public.gl_cancel_session(p_session uuid) returns void language plpgsql security invoker set search_path=public as $$
begin
 perform 1 from gl_sessions where id=p_session for update;
 if not found then raise exception 'Session not found'; end if;
 update gl_sessions set status='cancelled' where id=p_session;
 delete from gl_charges where attendance_id in (select id from gl_attendance where session_id=p_session);
end $$;
create or replace function public.gl_sell_package(p_enrollment uuid,p_sessions integer,p_price numeric,p_paid numeric,p_method text,p_date date,p_expiry date default null) returns uuid language plpgsql security invoker set search_path=public as $$
declare e gl_enrollments; pk uuid;
begin
 select * into strict e from gl_enrollments where id=p_enrollment for update;
 if e.billing_model<>'package' then raise exception 'Choose a package enrollment'; end if;
 if p_sessions<=0 or p_price<0 or p_paid<0 or p_expiry<p_date then raise exception 'Invalid package values'; end if;
 insert into gl_packages(student_id,enrollment_id,sessions_total,price,purchased_on,expires_on) values(e.student_id,e.id,p_sessions,p_price,p_date,p_expiry) returning id into pk;
 insert into gl_charges(student_id,enrollment_id,charged_on,amount,reason,package_id,note) values(e.student_id,e.id,p_date,p_price,'package',pk,p_sessions||' sessions');
 if p_paid>0 then insert into gl_payments(student_id,paid_on,amount,method,note) values(e.student_id,p_date,p_paid,p_method,'Package payment'); end if;
 return pk;
end $$;
create or replace function public.gl_generate_monthly_charges() returns void language plpgsql security invoker set search_path=public as $$
declare e gl_enrollments; m date; due date; today date := (now() at time zone 'Africa/Cairo')::date;
begin
 for e in select * from gl_enrollments where billing_model='monthly' and active and billing_day is not null for update loop
  for m in select generate_series(date_trunc('month',e.start_date),date_trunc('month',least(today,coalesce(e.end_date,today))),interval '1 month')::date loop
   due:= m+e.billing_day-1;
   if due>=e.start_date and due<=today and due<=coalesce(e.end_date,today) then
    insert into gl_charges(student_id,enrollment_id,charged_on,amount,reason,billing_month,note) values(e.student_id,e.id,due,e.price,'monthly',m,to_char(m,'Mon YYYY')) on conflict(enrollment_id,billing_month) where reason='monthly' do nothing;
   end if;
  end loop;
 end loop;
end $$;
create or replace function public.gl_generate_recurring_expenses() returns void language plpgsql security invoker set search_path=public as $$
declare r gl_recurring_expenses; m date; due date; today date := (now() at time zone 'Africa/Cairo')::date; sc text;
begin
 for r in select * from gl_recurring_expenses where active for update loop
  select scope into strict sc from gl_expense_categories where id=r.category_id;
  for m in select generate_series(date_trunc('month',r.start_date),date_trunc('month',today),interval '1 month')::date loop
   due:=m+r.day_of_month-1;
   if due>=r.start_date and due<=today then
    insert into gl_expenses(spent_on,amount,category_id,scope,description,recurring_id) values(due,r.amount,r.category_id,sc,r.name,r.id) on conflict(recurring_id,spent_on) where recurring_id is not null do nothing;
   end if;
  end loop;
  update gl_recurring_expenses set last_generated_on=today where id=r.id;
 end loop;
end $$;
create view gl_student_balances with (security_invoker=true) as
select s.id as student_id,s.full_name,coalesce(p.paid,0) total_paid,coalesce(c.charged,0) total_charged,coalesce(p.paid,0)-coalesce(c.charged,0) balance
from gl_students s left join (select student_id,sum(amount) paid from gl_payments group by student_id) p on p.student_id=s.id
left join (select student_id,sum(amount) charged from gl_charges group by student_id) c on c.student_id=s.id;
create view gl_package_status with (security_invoker=true) as
select e.id enrollment_id,e.student_id,coalesce(p.bought,0) sessions_bought,coalesce(a.used,0) sessions_used,coalesce(p.bought,0)-coalesce(a.used,0) sessions_remaining
from gl_enrollments e left join (select enrollment_id,sum(sessions_total) bought from gl_packages group by enrollment_id) p on p.enrollment_id=e.id
left join(select a.enrollment_id,count(*) used from gl_attendance a join gl_sessions s on s.id=a.session_id where a.consumes_credit and s.status='held' group by a.enrollment_id) a on a.enrollment_id=e.id where e.billing_model='package';
grant select on gl_student_balances,gl_package_status to service_role;
revoke all on gl_student_balances,gl_package_status from anon,authenticated;
create function gl_no_history_delete() returns trigger language plpgsql set search_path=public as $$ begin
 if exists(select 1 from gl_enrollments where student_id=old.id) or exists(select 1 from gl_payments where student_id=old.id) or exists(select 1 from gl_charges where student_id=old.id) then raise exception 'Archive students with history'; end if; return old; end $$;
create trigger gl_preserve_students before delete on gl_students for each row execute function gl_no_history_delete();
-- Pin every API function to authenticated users. RLS still enforces the one owner.
do $$ declare f record; begin for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname like 'gl_%' loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated'; execute 'grant execute on function '||f.signature||' to service_role'; end loop; end $$;
-- Private receipt photos, with owner-specific object paths.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('ghoneem-ledger-receipts','ghoneem-ledger-receipts',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
