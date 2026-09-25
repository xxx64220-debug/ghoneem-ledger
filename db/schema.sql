
-- ============ People & enrollment ============
create table gl_students (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  full_name    text not null,
  phone        text,
  parent_phone text,
  track        text not null default 'Other'
               check (track in ('EST','SAT','ACT','Programming','Engineering','Other')),
  status       text not null default 'active'
               check (status in ('active','paused','archived')),
  notes        text,
  created_at   timestamptz not null default now()
);

create table gl_groups (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  name          text not null,
  track         text not null default 'Other',
  default_price numeric(10,2),
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table gl_enrollments (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  student_id    uuid not null references gl_students(id),
  group_id      uuid references gl_groups(id),        -- null = individual
  billing_model text not null check (billing_model in ('package','per_session','monthly')),
  price         numeric(10,2) not null,             -- per session / per month / default package price
  package_size  int,                                -- default gl_sessions per package
  billing_day   int check (billing_day between 1 and 28), -- monthly model only
  start_date    date not null default current_date,
  end_date      date,
  active        boolean not null default true
);

-- ============ Sessions & gl_attendance ============
create table gl_sessions (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  group_id      uuid references gl_groups(id),
  enrollment_id uuid references gl_enrollments(id),    -- set for individual gl_sessions
  held_on       date not null,
  starts_at     time,
  duration_min  int default 90,
  topic         text,
  status        text not null default 'held' check (status in ('held','cancelled')),
  check (group_id is not null or enrollment_id is not null)
);

create table gl_attendance (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  session_id      uuid not null references gl_sessions(id) on delete cascade,
  student_id      uuid not null references gl_students(id),
  enrollment_id   uuid not null references gl_enrollments(id),
  status          text not null check (status in ('present','absent_charged','absent_excused')),
  consumes_credit boolean not null default false,   -- set by record_attendance()
  price_snapshot numeric(10,2),
  unique (session_id, student_id)
);

-- ============ Money in ============
create table gl_packages (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  student_id     uuid not null references gl_students(id),
  enrollment_id  uuid not null references gl_enrollments(id),
  sessions_total int  not null check (sessions_total > 0),
  price          numeric(10,2) not null,
  purchased_on   date not null default current_date,
  expires_on     date
);

create table gl_charges (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  student_id    uuid not null references gl_students(id),
  enrollment_id uuid references gl_enrollments(id),
  charged_on    date not null default current_date,
  amount        numeric(10,2) not null,             -- negative = discount / credit
  reason        text not null check (reason in ('session','package','monthly','adjustment','opening_balance')),
  attendance_id uuid references gl_attendance(id) on delete cascade,
  package_id    uuid references gl_packages(id) on delete cascade,
  note          text
);

create table gl_payments (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  student_id uuid not null references gl_students(id),
  paid_on    date not null default current_date,
  amount     numeric(10,2) not null,                -- negative = refund
  method     text not null default 'cash'
             check (method in ('cash','instapay','vodafone_cash','bank','other')),
  reference  text,
  note       text,
  created_at timestamptz not null default now()
);

-- ============ Money out ============
create table gl_expense_categories (
  id       uuid primary key default gen_random_uuid(),
  owner_id uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  name     text not null,
  scope    text not null check (scope in ('business','personal'))
);

create table gl_expenses (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  spent_on     date not null default current_date,
  amount       numeric(10,2) not null check (amount > 0),
  category_id  uuid not null references gl_expense_categories(id),
  scope        text not null check (scope in ('business','personal')),
  description  text,
  method       text default 'cash',
  receipt_path text,                                -- Supabase Storage path
  recurring_id uuid,
  created_at   timestamptz not null default now()
);

create table gl_recurring_expenses (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid,
  name              text not null,
  amount            numeric(10,2) not null,
  category_id       uuid not null references gl_expense_categories(id),
  day_of_month      int not null check (day_of_month between 1 and 28),
  active            boolean not null default true,
  last_generated_on date
);

create table gl_settings (id uuid primary key default gen_random_uuid(),owner_id uuid not null default '2caeaaaa-ae3c-45b9-8868-8b562d344622'::uuid unique, arabic_template text,english_template text);

alter table gl_students enable row level security; create policy owner_all on gl_students to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_students to service_role; revoke all on gl_students from anon,authenticated; create index on gl_students(owner_id);

alter table gl_groups enable row level security; create policy owner_all on gl_groups to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_groups to service_role; revoke all on gl_groups from anon,authenticated; create index on gl_groups(owner_id);

alter table gl_enrollments enable row level security; create policy owner_all on gl_enrollments to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_enrollments to service_role; revoke all on gl_enrollments from anon,authenticated; create index on gl_enrollments(owner_id);

alter table gl_sessions enable row level security; create policy owner_all on gl_sessions to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_sessions to service_role; revoke all on gl_sessions from anon,authenticated; create index on gl_sessions(owner_id);

alter table gl_attendance enable row level security; create policy owner_all on gl_attendance to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_attendance to service_role; revoke all on gl_attendance from anon,authenticated; create index on gl_attendance(owner_id);

alter table gl_packages enable row level security; create policy owner_all on gl_packages to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_packages to service_role; revoke all on gl_packages from anon,authenticated; create index on gl_packages(owner_id);

alter table gl_charges enable row level security; create policy owner_all on gl_charges to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_charges to service_role; revoke all on gl_charges from anon,authenticated; create index on gl_charges(owner_id);

alter table gl_payments enable row level security; create policy owner_all on gl_payments to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_payments to service_role; revoke all on gl_payments from anon,authenticated; create index on gl_payments(owner_id);

alter table gl_expense_categories enable row level security; create policy owner_all on gl_expense_categories to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_expense_categories to service_role; revoke all on gl_expense_categories from anon,authenticated; create index on gl_expense_categories(owner_id);

alter table gl_expenses enable row level security; create policy owner_all on gl_expenses to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_expenses to service_role; revoke all on gl_expenses from anon,authenticated; create index on gl_expenses(owner_id);

alter table gl_recurring_expenses enable row level security; create policy owner_all on gl_recurring_expenses to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_recurring_expenses to service_role; revoke all on gl_recurring_expenses from anon,authenticated; create index on gl_recurring_expenses(owner_id);

alter table gl_settings enable row level security; create policy owner_all on gl_settings to authenticated using (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622') with check (owner_id=(select auth.uid()) and owner_id='2caeaaaa-ae3c-45b9-8868-8b562d344622'); grant select,insert,update,delete on gl_settings to service_role; revoke all on gl_settings from anon,authenticated; create index on gl_settings(owner_id);

alter table gl_enrollments add check(price>=0);
alter table gl_packages add check(price>=0);
alter table gl_sessions add check ((group_id is null) <> (enrollment_id is null));
alter table gl_sessions add check(duration_min>0);
alter table gl_recurring_expenses add column start_date date not null default (now() at time zone 'Africa/Cairo')::date;
alter table gl_recurring_expenses add check(amount>0);
alter table gl_charges add column billing_month date;
create unique index gl_one_attendance_charge on gl_charges(attendance_id) where attendance_id is not null;
create unique index gl_one_month_charge on gl_charges(enrollment_id,billing_month) where reason='monthly';
create unique index gl_one_recurring on gl_expenses(recurring_id,spent_on) where recurring_id is not null;
