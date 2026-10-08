# Dwellr

Roommate matching for BYU students in Provo and Utah Valley.
Module 3 project, Section 2, Group 8.

Students who need a roommate usually find one through social media groups, friends and family, or random assignment by their apartment complex. None of these show how someone actually lives before you sign a lease together. Dwellr lets students compare cleanliness, sleep schedules, guest habits, and friendship expectations, and it only opens a chat when both people say yes.

## Tech stack

**We chose a backend as a service: Supabase.** It connects to a front end we write ourselves in plain HTML, CSS, and JavaScript. GitHub stores our code and can host the site with GitHub Pages.

### Why it fits our team

- **We keep the screens we already designed.** Our pages are plain HTML, CSS, and JavaScript. Supabase has a JavaScript library we add with one script tag, so we didn't have to rebuild the site in a framework.
- **It covers our must-have features.** Each must-have in our PRD maps to something Supabase already provides (see the table below), so we spend our time on the matching experience instead of building login systems and servers.
- **Real-time chat without our own server.** Supabase Realtime delivers new messages and new matches to the other person as they happen.
- **The database enforces our safety rules.** Row Level Security rules live inside the database, such as "only two connected students can message each other" and "only you can see your phone number." They hold even if someone tries to get around the website.
- **We still learn real database design.** Supabase runs on PostgreSQL, so we designed real tables from our ERD and wrote SQL.

### What we're giving up

- We depend on Supabase's service. Moving to our own server later would take work, although our data is standard PostgreSQL.
- Our security depends on our Row Level Security rules being right. We tested them with separate student accounts.
- We write less backend code than with a fully hand-built stack, so we learn less about building servers.

### Options we didn't choose

- **Hand-built (Express, Node, PostgreSQL):** Building login, photo uploads, and real-time chat ourselves would take more time than this project allows.
- **AI app builder (Lovable):** It would regenerate the site in its own code instead of using the screens we designed.
- **Cloud workspace (Replit):** It's mainly a place to write and host code. We would still have to choose how to build the backend.

## How our features map to Supabase

| Feature (from our PRD) | Supabase piece |
|---|---|
| Sign up and log in (email and password) | Supabase Auth |
| Profiles, interests, living and housing preferences | `profile`, `interest`, `user_interests`, `living_preferences`, `housing_preferences` tables |
| Profile photos (up to 5) | `photos` table and the `profile-photos` storage bucket |
| Swiping right or left | `decision` table |
| Connection requests inbox | Yes decisions on you that you haven't answered |
| Mutual matching | A database trigger creates a `connections` row when both students say yes |
| Messaging between matched students only | `messages` table, Realtime, and Row Level Security |
| Unmatch | Sets the connection to `unmatched`, deletes the chat for both, and blocks new messages |
| Close account | Deletes the student's photos, then their account and all of their rows |

## Changes from our ERD

Update the ERD to match the database:

- Table names are lowercase (`profile`, `user_interests`, `living_preferences`, `housing_preferences`, `photos`, `decision`, `connections`, `messages`, `interest`), so queries don't need quotes.
- `living_preferences` and `housing_preferences` are one-to-one with `profile`, with `user_id` as their primary key.
- `housing_preferences` has two new columns from our notes: `housing_type` (apartment, house, or dorms) and `household_size` (people living together, including the student).
- `photos` has a new `display_order` column. 0 is the main photo.
- `decision.decider_id`, `decision.target_id`, and `messages.receiver_id` are foreign keys to `profile`. `reciever_ID` is now spelled `receiver_id` and is filled in automatically.
- `connections.user_1` and `user_2` are the foreign keys to `profile`. Decisions create connections through a trigger, not a foreign key, so the line between Decision and Connections is a process, not a relationship.
- `connections.status` is either `connected` or `unmatched`.
- There's no username or password column. Supabase Auth stores passwords, and students log in with their email.
- `profile.phone` and `profile.email` can only be read by the student they belong to.

Not built yet: the Blocked and Archives pages from Settings.

## Files

| File | What it does |
|---|---|
| `index.html` | All nine screens |
| `styles.css` | The design |
| `app.js` | How the screens work |
| `db.js` | Every call to Supabase |
| `config.js` | Our Supabase project URL and publishable key |
| `supabase/schema.sql` | Creates the tables, security rules, matching trigger, photo storage, and realtime |
| `supabase/reset.sql` | Removes everything `schema.sql` created so it can be run again |

## Setting up Supabase

Already done for our project. To set up a new one:

1. Create a project at [supabase.com](https://supabase.com). Leave the Data API turned on.
2. Open **SQL Editor**, paste all of `supabase/schema.sql`, and click **Run**. Run it once.
3. Go to **Authentication → Sign In / Providers** and turn off **Confirm email** while we're testing. Otherwise every sign-up needs an email confirmation, and Supabase's built-in email service only sends a few emails per hour.
4. Copy the **Project URL** and **publishable key** from **Settings → API Keys** into `config.js`.

The publishable key is safe to commit to GitHub because the security rules decide what it can do. Never put the secret key (`sb_secret_...`), the `service_role` key, or the database password in this repo.

## Running the site

**On GitHub Pages:** In the repo, go to **Settings → Pages**, set the source to **Deploy from a branch**, choose `main` and `/ (root)`, and save. The site will be live at `https://ehess29.github.io/Dwellr/` within a few minutes. Then, in Supabase, go to **Authentication → URL Configuration** and set the **Site URL** to that address.

**On your computer:** Open the folder in VS Code and use the Live Server extension, or open `index.html` in a browser. The site needs an internet connection because it loads the Supabase library and talks to our project.

## Testing it

Make two accounts (two different emails, same gender) with at least one hobby or living-habit answer in common. Use two browsers, or one normal window and one private window, so both can be logged in at once. Swipe right from one, accept the request from the other, and chat.

To start over with an empty database, run `supabase/reset.sql` and then `supabase/schema.sql`. Delete old test accounts under **Authentication → Users** if you want to reuse their emails.
