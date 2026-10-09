-- =====================================================================
-- ARITI TRANSPORTATION PLC  -  Supabase database setup (run ONCE)
-- Supabase Dashboard > SQL Editor > New query > paste all > Run
--
-- BEFORE running: change 'manager@example.com' in section 2 to the email
-- you will use to sign in to the manager portal.
-- Safe to run again: everything uses IF NOT EXISTS / ON CONFLICT.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------
create table if not exists public.settings (
  id          int primary key check (id = 1),
  phone       text    not null default '+251 911 000 000',
  telegram    text    not null default 'AritiTransportation',
  city        text    not null default 'Addis Ababa, Ethiopia',
  base_trip   numeric not null default 4000 check (base_trip >= 0),
  per_km      numeric not null default 120  check (per_km >= 0),
  multipliers jsonb   not null default '{"sand":1,"clay":0.9,"stone":1.15,"rental":1.6,"haul":1.3}'
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.admins (
  email text primary key
);

create table if not exists public.drivers (
  id         bigint generated always as identity primary key,
  name       text not null check (char_length(name) between 1 and 60),
  phone      text not null check (char_length(phone) between 1 and 20),
  license    text not null default '' check (char_length(license) <= 30),
  created_at timestamptz not null default now()
);

create table if not exists public.fleet (
  id          bigint generated always as identity primary key,
  plate       text not null unique check (char_length(plate) between 1 and 20),
  model       text not null check (char_length(model) between 1 and 80),
  capacity    text not null check (char_length(capacity) between 1 and 40),
  status      text not null default 'Active' check (status in ('Active','Standby','Maintenance')),
  driver_id   bigint references public.drivers(id) on delete set null,
  service_due date,
  img_url     text not null default '',
  created_at  timestamptz not null default now()
);

create table if not exists public.trips (
  id          bigint generated always as identity primary key,
  trip_date   date    not null,
  plate       text    not null,
  driver      text    not null,
  material    text    not null,
  origin      text    not null check (char_length(origin) <= 80),
  destination text    not null check (char_length(destination) <= 80),
  loads       int     not null default 1 check (loads >= 1),
  distance_km numeric not null default 0 check (distance_km >= 0),
  price       numeric not null default 0 check (price >= 0),
  status      text    not null default 'Scheduled' check (status in ('Scheduled','In Transit','Delivered','Cancelled')),
  paid        boolean not null default false,
  notes       text    not null default '' check (char_length(notes) <= 200),
  quote_ref   text,
  created_at  timestamptz not null default now()
);
create index if not exists trips_date_idx on public.trips (trip_date desc);

create table if not exists public.quotes (
  id         bigint generated always as identity primary key,
  ref        text not null unique check (char_length(ref) between 6 and 30),
  name       text not null check (char_length(name) between 1 and 80),
  phone      text not null check (char_length(phone) between 7 and 20),
  service    text not null check (char_length(service) <= 120),
  volume     text not null check (char_length(volume) <= 80),
  location   text not null check (char_length(location) between 1 and 120),
  details    text not null default '' check (char_length(details) <= 500),
  status     text not null default 'New' check (status in ('New','Contacted','Quoted','Confirmed','Completed','Lost')),
  created_at timestamptz not null default now()
);
create index if not exists quotes_created_idx on public.quotes (created_at desc);

create table if not exists public.news (
  id        bigint generated always as identity primary key,
  news_date date    not null default current_date,
  title     text    not null check (char_length(title) between 1 and 100),
  content   text    not null check (char_length(content) between 1 and 600),
  published boolean not null default true
);

-- ---------------------------------------------------------------------
-- 2. WHO IS A MANAGER?  (only emails listed here get admin rights)
-- ---------------------------------------------------------------------
insert into public.admins (email) values ('manager@example.com')   -- <== CHANGE THIS
on conflict (email) do nothing;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. PUBLIC VIEW OF THE FLEET (hides driver and service dates from visitors)
-- ---------------------------------------------------------------------
create or replace view public.public_fleet as
  select id, plate, model, capacity, status, img_url
  from public.fleet
  where status <> 'Maintenance';

-- ---------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
--    Visitors (anon)  : read settings / public_fleet / published news,
--                       and INSERT a quote request. Nothing else.
--    Managers         : full access (must be listed in public.admins).
-- ---------------------------------------------------------------------
alter table public.settings enable row level security;
alter table public.admins   enable row level security;   -- no policy = nobody can read it directly
alter table public.drivers  enable row level security;
alter table public.fleet    enable row level security;
alter table public.trips    enable row level security;
alter table public.quotes   enable row level security;
alter table public.news     enable row level security;

drop policy if exists settings_read   on public.settings;
drop policy if exists settings_admin  on public.settings;
create policy settings_read  on public.settings for select to anon, authenticated using (true);
create policy settings_admin on public.settings for all    to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists news_read   on public.news;
drop policy if exists news_admin  on public.news;
create policy news_read  on public.news for select to anon, authenticated using (published = true or public.is_admin());
create policy news_admin on public.news for all    to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists quotes_insert on public.quotes;
drop policy if exists quotes_admin  on public.quotes;
create policy quotes_insert on public.quotes for insert to anon, authenticated with check (status = 'New');
create policy quotes_admin  on public.quotes for all    to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists drivers_admin on public.drivers;
drop policy if exists fleet_admin   on public.fleet;
drop policy if exists trips_admin   on public.trips;
create policy drivers_admin on public.drivers for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy fleet_admin   on public.fleet   for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy trips_admin   on public.trips   for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Table privileges (RLS above still decides which rows are visible)
grant usage on schema public to anon, authenticated;
grant select on public.settings, public.news, public.public_fleet to anon, authenticated;
grant insert on public.quotes to anon, authenticated;
grant select, insert, update, delete on public.settings, public.drivers, public.fleet,
      public.trips, public.quotes, public.news to authenticated;

-- ---------------------------------------------------------------------
-- 5. TRUCK PHOTO STORAGE  (public read, managers write, 2 MB images only)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('truck-photos', 'truck-photos', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists truck_photos_read   on storage.objects;
drop policy if exists truck_photos_insert on storage.objects;
drop policy if exists truck_photos_update on storage.objects;
drop policy if exists truck_photos_delete on storage.objects;
create policy truck_photos_read   on storage.objects for select to anon, authenticated using (bucket_id = 'truck-photos');
create policy truck_photos_insert on storage.objects for insert to authenticated with check (bucket_id = 'truck-photos' and public.is_admin());
create policy truck_photos_update on storage.objects for update to authenticated using (bucket_id = 'truck-photos' and public.is_admin());
create policy truck_photos_delete on storage.objects for delete to authenticated using (bucket_id = 'truck-photos' and public.is_admin());

-- ---------------------------------------------------------------------
-- 6. LIVE NOTIFICATIONS for new quote requests in the manager portal
-- ---------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.quotes;
exception when duplicate_object then null;
end $$;

-- Done. You should see "Success. No rows returned".
