-- add-admin-records.sql
-- Lets Dwellr admins maintain records from the Admin > Maintain Records page.
-- Run once in the Supabase SQL editor (safe to run again).
--
-- Tables an admin can maintain:
--   interest: the hobbies and interests students pick from (add, edit, delete).
--             Everyone could already read this list; now admins can change it.
--
-- Who counts as an admin: any account listed in public.admin_users.

-- ------------------------------------------------------------
-- 1. is_admin(): true when the logged-in account is an admin.
-- ------------------------------------------------------------
-- "security definer" lets the check read admin_users even though each
-- account can normally see only its own admin_users row.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users where user_id = (select auth.uid())
  );
$$;

-- Only logged-in accounts may call it (it answers "no" for everyone else anyway).
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- ------------------------------------------------------------
-- 2. interest: admins can add, edit, and delete interests.
-- ------------------------------------------------------------
-- The table permission lets logged-in accounts try; the policies below
-- make sure only admins actually succeed. Students still only read.
grant insert, update, delete on public.interest to authenticated;

drop policy if exists "Admins can add interests" on public.interest;
create policy "Admins can add interests"
  on public.interest for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists "Admins can edit interests" on public.interest;
create policy "Admins can edit interests"
  on public.interest for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Deleting an interest also removes it from every student who picked it
-- (user_interests has ON DELETE CASCADE). The page warns before deleting.
drop policy if exists "Admins can delete interests" on public.interest;
create policy "Admins can delete interests"
  on public.interest for delete
  to authenticated
  using ((select public.is_admin()));

-- Interest names: 1 to 30 characters, no blank names.
alter table public.interest drop constraint if exists interest_name_length;
alter table public.interest add constraint interest_name_length
  check (char_length(btrim(interest_name)) between 1 and 30);
