-- ============================================================
-- T07: plans / plan_revisions / todos / run_logs / completion_events
-- 에 user_id 컬럼 추가 + RLS(행 단위 보안) 적용
--
-- 실행 방법: Supabase 대시보드 > SQL Editor 에 이 파일 내용을
-- 그대로 붙여넣고 실행하세요. 위에서부터 순서대로 실행되어야 합니다.
--
-- 주의: 이미 저장된 기존 데이터(시드 데이터 등)가 있다면
-- 2단계(백필)에서 반드시 소유자를 지정하거나 삭제해야
-- 3단계의 NOT NULL 제약이 걸립니다. 그냥 통째로 실행하면
-- 기존 행이 남아있는 테이블에서 에러가 납니다.
-- ============================================================


-- ============================================================
-- 1단계. 각 테이블에 user_id 컬럼 추가 (일단 nullable)
-- ============================================================

alter table public.plans
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.plan_revisions
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.todos
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.run_logs
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.completion_events
  add column if not exists user_id uuid references auth.users(id) on delete cascade;


-- ============================================================
-- 2단계. 기존 데이터 백필 (필요한 경우에만)
--
-- 아래 두 줄 중 하나를 선택해서 실행하세요.
-- 계속 쌓아둘 데이터가 없다면(테스트용 시드 데이터뿐이라면) A를,
-- 기존 데이터를 특정 계정 소유로 넘기고 싶다면 B를 사용하세요.
-- ============================================================

-- [옵션 A] 기존 데이터를 전부 정리하고 새로 시작 (가장 간단)
-- delete from public.completion_events where user_id is null;
-- delete from public.run_logs where user_id is null;
-- delete from public.plan_revisions where user_id is null;
-- delete from public.todos where user_id is null;
-- delete from public.plans where user_id is null;

-- [옵션 B] 기존 데이터를 내 계정 소유로 지정
-- 1) 본인 계정의 uuid 조회
-- select id, email from auth.users;
-- 2) 조회한 id를 아래 '내-uuid-여기에' 자리에 넣고 실행
-- update public.plans            set user_id = '내-uuid-여기에' where user_id is null;
-- update public.plan_revisions   set user_id = '내-uuid-여기에' where user_id is null;
-- update public.todos            set user_id = '내-uuid-여기에' where user_id is null;
-- update public.run_logs         set user_id = '내-uuid-여기에' where user_id is null;
-- update public.completion_events set user_id = '내-uuid-여기에' where user_id is null;


-- ============================================================
-- 3단계. user_id를 필수값으로 잠그고, 새 행에는 자동으로
-- 로그인한 사용자의 uid가 채워지도록 기본값 지정
-- ============================================================

alter table public.plans
  alter column user_id set default auth.uid(),
  alter column user_id set not null;

alter table public.plan_revisions
  alter column user_id set default auth.uid(),
  alter column user_id set not null;

alter table public.todos
  alter column user_id set default auth.uid(),
  alter column user_id set not null;

alter table public.run_logs
  alter column user_id set default auth.uid(),
  alter column user_id set not null;

alter table public.completion_events
  alter column user_id set default auth.uid(),
  alter column user_id set not null;


-- ============================================================
-- 4단계. plans 스냅샷 트리거 함수가 user_id도 같이 남기도록 수정
--
-- plan_revisions는 앱이 직접 insert하지 않고, plans에 UPDATE가
-- 일어나기 직전에 트리거(fn_snapshot_plan_before_update)가 대신
-- 써준다. 이 함수도 OLD 행의 user_id를 그대로 복사해야
-- plan_revisions의 user_id NOT NULL / RLS 조건을 만족한다.
--
-- 기존 함수 본문을 알 수 없어 스키마 문서(contracts/pds-schema-v2.json)
-- 기준으로 재작성했습니다. 실제 트리거 로직이 이것과 다르다면
-- (예: 다른 컬럼을 더 남긴다면) 아래 컬럼 목록만 맞춰 조정하세요.
-- ============================================================

create or replace function public.fn_snapshot_plan_before_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.plan_revisions (
    plan_id, user_id, period_start, period_end,
    priority, success_criteria, estimated_minutes, revised_at
  ) values (
    old.id, old.user_id, old.period_start, old.period_end,
    old.priority, old.success_criteria, old.estimated_minutes, now()
  );
  return new;
end;
$$;

-- 트리거가 이미 있다면 그대로 두고, 없다면 새로 건다.
drop trigger if exists trg_snapshot_plan_before_update on public.plans;
create trigger trg_snapshot_plan_before_update
  before update on public.plans
  for each row
  execute function public.fn_snapshot_plan_before_update();


-- ============================================================
-- 5단계. RLS 활성화
-- ============================================================

alter table public.plans enable row level security;
alter table public.plan_revisions enable row level security;
alter table public.todos enable row level security;
alter table public.run_logs enable row level security;
alter table public.completion_events enable row level security;


-- ============================================================
-- 6단계. 정책: 로그인한 사용자는 자신의 행만 읽기/쓰기/수정/삭제
-- ============================================================

-- plans
drop policy if exists "plans_select_own" on public.plans;
create policy "plans_select_own" on public.plans
  for select using (auth.uid() = user_id);

drop policy if exists "plans_insert_own" on public.plans;
create policy "plans_insert_own" on public.plans
  for insert with check (auth.uid() = user_id);

drop policy if exists "plans_update_own" on public.plans;
create policy "plans_update_own" on public.plans
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "plans_delete_own" on public.plans;
create policy "plans_delete_own" on public.plans
  for delete using (auth.uid() = user_id);

-- plan_revisions (앱은 읽기만 함, 쓰기는 트리거가 SECURITY DEFINER로 수행)
drop policy if exists "plan_revisions_select_own" on public.plan_revisions;
create policy "plan_revisions_select_own" on public.plan_revisions
  for select using (auth.uid() = user_id);

drop policy if exists "plan_revisions_insert_own" on public.plan_revisions;
create policy "plan_revisions_insert_own" on public.plan_revisions
  for insert with check (auth.uid() = user_id);

-- todos
drop policy if exists "todos_select_own" on public.todos;
create policy "todos_select_own" on public.todos
  for select using (auth.uid() = user_id);

drop policy if exists "todos_insert_own" on public.todos;
create policy "todos_insert_own" on public.todos
  for insert with check (auth.uid() = user_id);

drop policy if exists "todos_update_own" on public.todos;
create policy "todos_update_own" on public.todos
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "todos_delete_own" on public.todos;
create policy "todos_delete_own" on public.todos
  for delete using (auth.uid() = user_id);

-- run_logs
drop policy if exists "run_logs_select_own" on public.run_logs;
create policy "run_logs_select_own" on public.run_logs
  for select using (auth.uid() = user_id);

drop policy if exists "run_logs_insert_own" on public.run_logs;
create policy "run_logs_insert_own" on public.run_logs
  for insert with check (auth.uid() = user_id);

drop policy if exists "run_logs_update_own" on public.run_logs;
create policy "run_logs_update_own" on public.run_logs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "run_logs_delete_own" on public.run_logs;
create policy "run_logs_delete_own" on public.run_logs
  for delete using (auth.uid() = user_id);

-- completion_events
drop policy if exists "completion_events_select_own" on public.completion_events;
create policy "completion_events_select_own" on public.completion_events
  for select using (auth.uid() = user_id);

drop policy if exists "completion_events_insert_own" on public.completion_events;
create policy "completion_events_insert_own" on public.completion_events
  for insert with check (auth.uid() = user_id);

drop policy if exists "completion_events_delete_own" on public.completion_events;
create policy "completion_events_delete_own" on public.completion_events
  for delete using (auth.uid() = user_id);
