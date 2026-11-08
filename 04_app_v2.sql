-- =====================================================================
-- Sijin's Fitness App: update 04 (for app v2)
-- Run once in Supabase > SQL Editor > New query. Safe to re-run.
-- Adds: lb/kg memory for sets, body measurements, new calorie modes.
-- =====================================================================

-- remember what you typed (45 lb stays 45 lb, weight_kg is the converted value)
alter table public.workout_sets add column if not exists entered_unit   text not null default 'kg' check (entered_unit in ('kg','lb'));
alter table public.workout_sets add column if not exists entered_weight numeric(7,2);

-- body measurements for the Navy body fat estimate
alter table public.body_metrics add column if not exists height_cm    numeric(5,1) check (height_cm > 0);
alter table public.body_metrics add column if not exists neck_cm      numeric(5,1) check (neck_cm > 0);
alter table public.body_metrics add column if not exists waist_cm     numeric(5,1) check (waist_cm > 0);
alter table public.body_metrics add column if not exists body_fat_pct numeric(4,1) check (body_fat_pct between 0 and 70);

-- calorie modes: maintain / loss / gain (old values still allowed)
alter table public.goals drop constraint if exists goals_goal_type_check;
alter table public.goals add constraint goals_goal_type_check
  check (goal_type in ('maintain','loss','gain','bulk','cut','lose'));

insert into public.app_schema_version (version, name)
values (2, 'app v2: units, body measurements, goal modes')
on conflict do nothing;

notify pgrst, 'reload schema';
