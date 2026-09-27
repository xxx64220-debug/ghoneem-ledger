-- Ledger only: optional teaching location, editable in the student list.
alter table public.gl_students add column teaching_place text not null default '' check(length(teaching_place)<=180);
