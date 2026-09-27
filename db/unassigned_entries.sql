-- Amount first, student later. Cash amounts and dates remain unchanged on assignment.
alter table public.gl_payments alter column student_id drop not null;
alter table public.gl_charges alter column student_id drop not null;
alter table public.gl_charges add constraint gl_unassigned_manual_only check (
 student_id is not null or (reason in ('adjustment','opening_balance') and enrollment_id is null and attendance_id is null and package_id is null)
);
create or replace function public.gl_assign_entry(p_kind text,p_entry uuid,p_student uuid)
returns void language plpgsql security invoker set search_path = public as $$
declare
 v_owner constant uuid := '2caeaaaa-ae3c-45b9-8868-8b562d344622';
 v_student uuid;
begin
 if not exists(select 1 from public.gl_students where id=p_student and owner_id=v_owner) then
  raise exception 'Student not found';
 end if;
 if p_kind='payment' then
  select student_id into v_student from public.gl_payments where id=p_entry and owner_id=v_owner for update;
 elsif p_kind='charge' then
  select student_id into v_student from public.gl_charges where id=p_entry and owner_id=v_owner for update;
 else raise exception 'Invalid entry type';
 end if;
 if not found then raise exception 'Entry not found'; end if;
 if v_student is not null then
  if v_student=p_student then return; end if;
  raise exception 'Entry already has a student';
 end if;
 if p_kind='payment' then
  update public.gl_payments set student_id=p_student where id=p_entry and owner_id=v_owner;
 else
  update public.gl_charges set student_id=p_student where id=p_entry and owner_id=v_owner;
 end if;
end; $$;
revoke all on function public.gl_assign_entry(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.gl_assign_entry(text,uuid,uuid) to service_role;
