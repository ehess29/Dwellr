# Dwellr

Roommate matching for BYU students in Provo and Utah Valley.
Module 3 project, Section 2, Group 8.

## App Summary

Many students come to BYU without a roommate lined up, whether they're new to Provo, transferring, or just don't know anyone yet. Finding someone compatible through random posts or word of mouth is hit-or-miss, and living with the wrong person can make the school year miserable. Dwellr helps BYU students in Provo and Utah Valley find roommates they're actually likely to get along with. Students create a profile with their interests, living habits, and housing preferences, then swipe through other students' profiles. When two students both swipe right, they're matched and can message each other in the app. From there they can decide whether they'd really want to live together. Dwellr works for students looking for their first roommate and for those who want a new one.

## Tech stack

**We chose a backend as a service: Supabase.** It connects to a front end we write ourselves in plain HTML, CSS, and JavaScript. GitHub stores our code and can host the site with GitHub Pages.

### Why it fits our team

- **We keep the screens we already designed.** Our pages are plain HTML, CSS, and JavaScript. Supabase has a JavaScript library we add with one script tag, so we didn't have to rebuild the site in a framework.
- **It covers our must-have features.** Each must-have in our PRD maps to something Supabase already provides (see the table below), so we spend our time on the matching experience instead of building login systems and servers.
- **Real-time chat without our own server.** Supabase Realtime delivers new messages and new matches to the other person as they happen.
- **The database enforces our safety rules.** Row Level Security rules live inside the database, such as "only two connected students can message each other" and "only you can see your phone number." They hold even if someone tries to get around the website.
- **We still learn real database design.** Supabase runs on PostgreSQL, so we designed real tables from our ERD and wrote SQL.


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


Not built yet: the Blocked and Archives pages from Settings.

## Database design (ERD)

<img width="3200" height="1760" alt="Dwellr ERD" src="https://github.com/user-attachments/assets/f36465da-375b-40e9-a864-c2c9fbf24a58" />


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

## Verifying the Vertical Slice

Our working button is the **Create Profile button** on a student's profile card. After entering in all of your information and interests. You should be able to press "Create Profile" which will save all of your information into our database (supabase). You should be able to confirm your changes by signing in using your email and password.
