-- =====================================================================
-- Dwellr: Shorter names and About section
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql before this change. (A brand-new project only needs
-- schema.sql, which already includes it.)
--
-- Very long names and About text were breaking the layout on phones.
-- New limits, matching the counters on the sign-up and Edit Profile forms:
--   * First name: 1 to 20 characters (was 50)
--   * Last name:  1 to 25 characters (was 50), room for hyphenated names
--   * About:      50 to 300 characters (was 500)
-- Every existing student already fits these limits.
-- =====================================================================

alter table public.profile drop constraint if exists profile_first_name_check;
alter table public.profile add constraint profile_first_name_check
  check (char_length(first_name) between 1 and 20);

alter table public.profile drop constraint if exists profile_last_name_check;
alter table public.profile add constraint profile_last_name_check
  check (char_length(last_name) between 1 and 25);

alter table public.profile drop constraint if exists profile_introduce_check;
alter table public.profile add constraint profile_introduce_check
  check (char_length(introduce) between 50 and 300);
