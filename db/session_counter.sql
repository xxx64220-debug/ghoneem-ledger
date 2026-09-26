-- Ledger only. Manual session counter independent of financial charges/attendance.
alter table public.gl_students
 add column session_rate numeric(10,2) check(session_rate > 0),
 add column session_counter_used numeric(10,2) not null default 0 check(session_counter_used >= 0);
