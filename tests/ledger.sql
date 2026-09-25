-- Run only against the dedicated ledger project after replacing the owner placeholder.
-- Entire test rolls back, including all fixture rows.
begin;
set local role service_role;
select set_config('request.jwt.claim.sub','2caeaaaa-ae3c-45b9-8868-8b562d344622',true);
do $$
declare st uuid; pe uuid; se uuid; me uuid; sess uuid; individual uuid; n numeric; before_count int;
begin
 insert into gl_students(full_name) values('__ledger_transaction_test__') returning id into st;
 insert into gl_enrollments(student_id,billing_model,price,package_size) values(st,'package',1600,8) returning id into pe;
 insert into gl_enrollments(student_id,billing_model,price) values(st,'per_session',200) returning id into se;
 insert into gl_sessions(enrollment_id,held_on) values(pe,current_date) returning id into sess;
 perform gl_record_attendance(sess,jsonb_build_array(jsonb_build_object('enrollment_id',pe,'status','present')));
 select sessions_remaining into n from gl_package_status where enrollment_id=pe;
 if n<>-1 then raise exception 'Overdraft must be -1'; end if;
 perform gl_sell_package(pe,8,1600,1200,'cash',current_date,null);
 select sessions_remaining into n from gl_package_status where enrollment_id=pe;
 if n<>7 then raise exception 'Package must absorb overdraft'; end if;
 select balance into n from gl_student_balances where student_id=st;
 if n<>-400 then raise exception 'Package partial-payment balance'; end if;
 perform gl_record_attendance(sess,jsonb_build_array(jsonb_build_object('enrollment_id',pe,'status','absent_excused')));
 select sessions_remaining into n from gl_package_status where enrollment_id=pe;
 if n<>8 then raise exception 'Excused must restore credit'; end if;
 perform gl_record_attendance(sess,jsonb_build_array(jsonb_build_object('enrollment_id',pe,'status','absent_charged')));
 perform gl_cancel_session(sess);
 select sessions_remaining into n from gl_package_status where enrollment_id=pe;
 if n<>8 then raise exception 'Cancelled must restore credit'; end if;
 insert into gl_sessions(enrollment_id,held_on) values(se,current_date) returning id into individual;
 perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','present')));
 perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','present')));
 select count(*) into n from gl_charges where enrollment_id=se;
 if n<>1 then raise exception 'Duplicate attendance charge'; end if;
 update gl_enrollments set price=350 where id=se;
 perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','present')));
 select amount into n from gl_charges where enrollment_id=se;
 if n<>200 then raise exception 'Existing charge price changed'; end if;
 perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','absent_excused')));
 select count(*) into n from gl_charges where enrollment_id=se;
 if n<>0 then raise exception 'Excused must remove charge'; end if;
 perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','present')));
 select amount into n from gl_charges where enrollment_id=se;
 if n<>200 then raise exception 'Attendance edit must retain price snapshot'; end if;
 -- Invalid second row must roll back the otherwise valid first row.
 begin
  perform gl_record_attendance(individual,jsonb_build_array(jsonb_build_object('enrollment_id',se,'status','absent_excused'),jsonb_build_object('enrollment_id',pe,'status','present')));
  raise exception 'Expected membership failure';
 exception when raise_exception then
  if sqlerrm='Expected membership failure' then raise; end if;
 end;
 select count(*) into n from gl_charges where enrollment_id=se;
 if n<>1 then raise exception 'Attendance was not atomic'; end if;
 perform gl_cancel_session(individual);
 select count(*) into n from gl_charges where enrollment_id=se;
 if n<>0 then raise exception 'Cancellation must remove charge'; end if;
 insert into gl_enrollments(student_id,billing_model,price,billing_day,start_date) values(st,'monthly',1000,1,date_trunc('month',current_date)::date) returning id into me;
 perform gl_generate_monthly_charges(); perform gl_generate_monthly_charges();
 select count(*) into n from gl_charges where enrollment_id=me;
 if n<>1 then raise exception 'Monthly charge must be unique'; end if;
end $$;
rollback;
