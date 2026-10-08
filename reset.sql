-- =====================================================================
-- Dwellr: remove everything schema.sql created, so you can run it again.
--
-- This deletes all profiles, swipes, connections and messages.
-- It does NOT delete login accounts (Authentication > Users) or photo
-- files (Storage > profile-photos). Delete test accounts in the
-- dashboard if you want to reuse their emails. Delete a student's photo
-- files first, because Supabase won't delete an account that owns files.
-- =====================================================================

drop trigger if exists on_auth_user_created on auth.users;

drop policy if exists "Students upload to their own photo folder" on storage.objects;
drop policy if exists "Students can see their own photo files" on storage.objects;
drop policy if exists "Students delete their own photo files" on storage.objects;

drop view if exists public.profile_cards cascade;

drop table if exists
  public.messages, public.connections, public.decision, public.photos,
  public.housing_preferences, public.living_preferences, public.user_interests,
  public.profile, public.interest
  cascade;

drop function if exists public.handle_new_user();
drop function if exists public.create_connection_on_match();
drop function if exists public.set_message_receiver();
drop function if exists public.check_photo_limit();
drop function if exists public.decide(uuid, text);
drop function if exists public.get_deck(text, int);
drop function if exists public.get_connection_requests();
drop function if exists public.get_my_contact();
drop function if exists public.unmatch(bigint);
drop function if exists public.delete_my_account();
