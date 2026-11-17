-- =====================================================================
-- Sijin's Fitness App: update 05 (for app v2.1)
-- Run once in Supabase > SQL Editor > New query. Safe to re-run.
-- ALL-OR-NOTHING: if anything fails, nothing is changed.
-- Your logged workouts, sets, weights, foods and food logs are NOT touched.
-- Only adds: 2 new tables, 2 new columns, and tidies the back exercises.
-- =====================================================================
begin;

-- A. which muscles each exercise works (percent split, editable in the app)
create table if not exists public.exercise_muscles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  muscle      text not null,
  percent     numeric(5,2) not null check (percent > 0 and percent <= 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (exercise_id, muscle)
);

-- B. the exercises inside the workouts you create (strength or cardio)
create table if not exists public.template_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  template_id    uuid not null references public.workout_templates(id) on delete cascade,
  kind           text not null default 'strength' check (kind in ('strength','cardio')),
  exercise_id    uuid references public.exercises(id) on delete cascade,
  cardio_machine text references public.cardio_machines(name) on update cascade,
  position       int  not null default 1,
  target_sets    int  not null default 3 check (target_sets between 1 and 20),
  rep_min        int  check (rep_min > 0),
  rep_max        int  check (rep_max > 0),
  planned_min    numeric(5,1) check (planned_min > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ((kind = 'strength' and exercise_id is not null) or (kind = 'cardio' and cardio_machine is not null))
);
create index if not exists template_items_tpl on public.template_items (template_id, position);

-- C. two new columns (nothing existing is altered)
alter table public.workout_templates add column if not exists usual_days int[] not null default '{}'
  check (usual_days <@ array[1,2,3,4,5,6,7]);
alter table public.cardio_intervals add column if not exists machine_speed numeric(5,1) check (machine_speed >= 0);

-- D. security + timestamps for the new tables
do $$
declare t text;
begin
  foreach t in array array['exercise_muscles','template_items'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format('create policy "own rows" on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$s', t);
    execute format('create trigger trg_%1$s_updated before update on public.%1$s for each row execute function public.set_updated_at()', t);
  end loop;
end $$;
grant select, insert, update, delete on public.exercise_muscles, public.template_items to authenticated;

-- E. back exercises tidy-up (exercise library only; no logged sets are changed)
-- E1. Lat Pulldown is a cable machine at your gym -> cable (new sets default to lbs)
update public.exercises set equipment = 'cable'
 where lower(name) = 'lat pulldown' and equipment <> 'cable';
-- E2. the duplicate "Cable Lat Pulldown" is hidden (never deleted), only if it has no sets of its own
update public.exercises set archived = true
 where lower(name) = 'cable lat pulldown' and archived = false
   and not exists (select 1 from public.workout_sets s where s.exercise_id = exercises.id);
-- E3. your existing Seated Row sets were on the cable -> rename (sets stay attached)
update public.exercises set name = 'Seated Row (Cable)', equipment = 'cable'
 where lower(name) = 'seated row'
   and not exists (select 1 from public.exercises x where lower(x.name) = 'seated row (cable)');
-- E4. new machine exercises (kg)
insert into public.exercises (user_id, name, muscle_group, equipment, load_type, is_compound, increment_kg)
select u.id, v.n, 'back', 'machine', 'total', v.c, 2.5
  from (select id from auth.users order by created_at limit 1) u,
       (values ('Seated Row (Machine)', true), ('High Row Machine', true), ('Shrug Machine', false)) as v(n, c)
on conflict do nothing;

-- F. default muscle percentages (only for exercises that have none yet)
insert into public.exercise_muscles (user_id, exercise_id, muscle, percent)
select e.user_id, e.id, v.m, v.p
  from (values
    ('Incline Barbell Press','chest',55),
    ('Incline Barbell Press','delt_front',25),
    ('Incline Barbell Press','triceps',20),
    ('Incline Dumbbell Press','chest',55),
    ('Incline Dumbbell Press','delt_front',25),
    ('Incline Dumbbell Press','triceps',20),
    ('Machine Incline Press','chest',55),
    ('Machine Incline Press','delt_front',25),
    ('Machine Incline Press','triceps',20),
    ('Flat Barbell Press','chest',70),
    ('Flat Barbell Press','delt_front',10),
    ('Flat Barbell Press','triceps',20),
    ('Flat Dumbbell Press','chest',70),
    ('Flat Dumbbell Press','delt_front',10),
    ('Flat Dumbbell Press','triceps',20),
    ('Machine Flat Press','chest',70),
    ('Machine Flat Press','delt_front',10),
    ('Machine Flat Press','triceps',20),
    ('Chest Press (Seated)','chest',70),
    ('Chest Press (Seated)','delt_front',10),
    ('Chest Press (Seated)','triceps',20),
    ('Cable Chest Fly','chest',90),
    ('Cable Chest Fly','delt_front',10),
    ('Pec Deck','chest',90),
    ('Pec Deck','delt_front',10),
    ('Weighted Pushups','chest',55),
    ('Weighted Pushups','delt_front',15),
    ('Weighted Pushups','triceps',25),
    ('Weighted Pushups','abs',5),
    ('Dumbbell Shoulder Press','delt_front',45),
    ('Dumbbell Shoulder Press','delt_side',25),
    ('Dumbbell Shoulder Press','triceps',25),
    ('Dumbbell Shoulder Press','traps',5),
    ('Barbell Shoulder Press','delt_front',45),
    ('Barbell Shoulder Press','delt_side',25),
    ('Barbell Shoulder Press','triceps',25),
    ('Barbell Shoulder Press','traps',5),
    ('Machine Shoulder Press','delt_front',45),
    ('Machine Shoulder Press','delt_side',30),
    ('Machine Shoulder Press','triceps',25),
    ('Machine Lateral Raise','delt_side',90),
    ('Machine Lateral Raise','traps',10),
    ('Dumbbell Lateral Raise','delt_side',90),
    ('Dumbbell Lateral Raise','traps',10),
    ('Cable Lateral Raise','delt_side',90),
    ('Cable Lateral Raise','traps',10),
    ('Rear Delt Fly','delt_rear',75),
    ('Rear Delt Fly','upper_back',25),
    ('Cable Extensions','triceps',100),
    ('Overhead Extensions','triceps',100),
    ('Cable Kickbacks','triceps',100),
    ('Dumbbell Extension','triceps',100),
    ('Barbell Extension','triceps',100),
    ('Skullcrushers','triceps',100),
    ('Dip Machine','triceps',60),
    ('Dip Machine','chest',25),
    ('Dip Machine','delt_front',15),
    ('Dips','triceps',50),
    ('Dips','chest',35),
    ('Dips','delt_front',15),
    ('Lat Pulldown','lats',60),
    ('Lat Pulldown','biceps',20),
    ('Lat Pulldown','upper_back',15),
    ('Lat Pulldown','delt_rear',5),
    ('Cable Lat Pulldown','lats',60),
    ('Cable Lat Pulldown','biceps',20),
    ('Cable Lat Pulldown','upper_back',15),
    ('Cable Lat Pulldown','delt_rear',5),
    ('T-Bar Row','lats',35),
    ('T-Bar Row','upper_back',35),
    ('T-Bar Row','lower_back',10),
    ('T-Bar Row','biceps',10),
    ('T-Bar Row','delt_rear',10),
    ('Shrugs','traps',85),
    ('Shrugs','forearms',15),
    ('Shrug Machine','traps',90),
    ('Shrug Machine','upper_back',10),
    ('Seated Row (Cable)','upper_back',40),
    ('Seated Row (Cable)','lats',30),
    ('Seated Row (Cable)','biceps',15),
    ('Seated Row (Cable)','delt_rear',15),
    ('Seated Row (Machine)','upper_back',40),
    ('Seated Row (Machine)','lats',30),
    ('Seated Row (Machine)','biceps',15),
    ('Seated Row (Machine)','delt_rear',15),
    ('High Row Machine','lats',40),
    ('High Row Machine','upper_back',35),
    ('High Row Machine','biceps',15),
    ('High Row Machine','delt_rear',10),
    ('Bent Over Dumbbell Row','lats',35),
    ('Bent Over Dumbbell Row','upper_back',30),
    ('Bent Over Dumbbell Row','lower_back',10),
    ('Bent Over Dumbbell Row','biceps',15),
    ('Bent Over Dumbbell Row','delt_rear',10),
    ('Pullups','lats',55),
    ('Pullups','biceps',25),
    ('Pullups','upper_back',15),
    ('Pullups','forearms',5),
    ('Dumbbell Curl','biceps',90),
    ('Dumbbell Curl','forearms',10),
    ('Preacher Curl','biceps',90),
    ('Preacher Curl','forearms',10),
    ('Cable Curl','biceps',90),
    ('Cable Curl','forearms',10),
    ('Machine Preacher Curl','biceps',100),
    ('Spider Curl','biceps',100),
    ('Machine Wrist Curl','forearms',100),
    ('Machine Wrist Extension','forearms',100),
    ('Dumbbell Wrist Curl','forearms',100),
    ('Dumbbell Wrist Extension','forearms',100),
    ('Reverse Curls','forearms',60),
    ('Reverse Curls','biceps',40),
    ('Hammer Curls','biceps',50),
    ('Hammer Curls','forearms',50),
    ('Machine Crunch','abs',90),
    ('Machine Crunch','obliques',10),
    ('Leg Raise','abs',90),
    ('Leg Raise','obliques',10),
    ('Cable Crunch','abs',90),
    ('Cable Crunch','obliques',10),
    ('Squat','quads',55),
    ('Squat','glutes',30),
    ('Squat','lower_back',10),
    ('Squat','hamstrings',5),
    ('Smith Squat','quads',60),
    ('Smith Squat','glutes',30),
    ('Smith Squat','hamstrings',5),
    ('Smith Squat','calves',5),
    ('Leg Extension','quads',100),
    ('Pendulum Squat','quads',70),
    ('Pendulum Squat','glutes',25),
    ('Pendulum Squat','hamstrings',5),
    ('Bulgarian Split Squats','quads',50),
    ('Bulgarian Split Squats','glutes',40),
    ('Bulgarian Split Squats','hamstrings',10),
    ('Leg Press','quads',60),
    ('Leg Press','glutes',30),
    ('Leg Press','hamstrings',10),
    ('Romanian Deadlifts','hamstrings',45),
    ('Romanian Deadlifts','glutes',30),
    ('Romanian Deadlifts','lower_back',25),
    ('Leg Curl','hamstrings',100),
    ('Hip Thrust','glutes',80),
    ('Hip Thrust','hamstrings',20),
    ('Hip Abductors','glutes',100),
    ('Standing Calf Raises','calves',100)
  ) as v(n, m, p)
  join public.exercises e on lower(e.name) = lower(v.n)
 where not exists (select 1 from public.exercise_muscles x where x.exercise_id = e.id)
on conflict (exercise_id, muscle) do nothing;

insert into public.app_schema_version (version, name)
values (3, 'app v2.1: muscle map, saved workouts, bike speed, back exercises')
on conflict do nothing;

notify pgrst, 'reload schema';
commit;

-- result: your back exercises after the update (history counts must match what you had)
select e.name, e.equipment, e.archived as hidden, e.load_type,
       (select count(*) from public.workout_sets s where s.exercise_id = e.id) as logged_sets
  from public.exercises e
 where e.muscle_group = 'back'
 order by e.name;
