-- =====================================================================
-- Dwellr: Report a student
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql before this change. (A brand-new project only needs
-- schema.sql, which already includes it.)
--
-- Any logged-in student can report another student from their full
-- profile or from a chat. A report saves who reported whom, the reason
-- they picked, and their explanation.
--   * Students can only file reports as themselves.
--   * Students can't read, change or delete any reports, including their
--     own, so the person reported never finds out who reported them.
--   * Our team reviews reports in Table Editor > reports and marks each
--     one 'reviewed' or 'dismissed'.
-- =====================================================================

create table if not exists public.reports (
  report_id   bigint generated always as identity primary key,
  reporter_id uuid not null default auth.uid() references public.profile (user_id) on delete cascade,
  reported_id uuid not null references public.profile (user_id) on delete cascade,
  reason      text not null check (reason in (
                'Fake profile', 'Inappropriate photos', 'Harassment or rude messages',
                'Spam or scam', 'Makes me feel unsafe', 'Other')),
  details     text not null check (char_length(btrim(details)) between 20 and 1000),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at  timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

create index if not exists reports_reported_idx on public.reports (reported_id);
create index if not exists reports_reporter_idx on public.reports (reporter_id);


-- Students can add a report and nothing else.
revoke all on public.reports from anon, authenticated;
grant insert (reported_id, reason, details) on public.reports to authenticated;
grant usage on all sequences in schema public to authenticated;
grant all on public.reports to service_role;

alter table public.reports enable row level security;

drop policy if exists "Students can report as themselves" on public.reports;
create policy "Students can report as themselves"
  on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()));


-- See open reports, newest first:
-- select r.created_at, r.reason, r.details,
--        reporter.first_name || ' ' || reporter.last_name as reported_by,
--        reported.first_name || ' ' || reported.last_name as reported_student
-- from public.reports r
-- join public.profile reporter on reporter.user_id = r.reporter_id
-- join public.profile reported on reported.user_id = r.reported_id
-- where r.status = 'open'
-- order by r.created_at desc;
