// db.js: every call the website makes to Supabase lives in this file.
// app.js only calls these functions. Each one returns plain data or throws
// an Error whose message is safe to show to the student.
window.db = (() => {
  "use strict";

  const { supabaseUrl, supabasePublishableKey } = window.DWELLR_CONFIG;
  const sb = window.supabase.createClient(supabaseUrl, supabasePublishableKey);
  const PHOTO_BUCKET = "profile-photos";
  const PHOTO_PREFIX = `${supabaseUrl}/storage/v1/object/public/${PHOTO_BUCKET}/`;
  const COLORS = ["#6F8F72", "#C7835A", "#5878A6", "#A9677F", "#B08E2E", "#5F8597", "#7E68A8", "#4E8B80"];

  /* ---------- Errors ---------- */
  const FRIENDLY = [
    [/invalid login credentials/i, "That email and password don't match an account."],
    [/already registered|already been registered|already exists/i, "An account with this email already exists. Log in instead."],
    [/email not confirmed/i, "Confirm your email first. Check your inbox for a link from Supabase."],
    [/database error saving new user/i, "We couldn't create your profile. Check your answers and try again."],
    [/rate limit/i, "Too many attempts. Wait a few minutes and try again."],
    [/failed to fetch|network|load failed/i, "Can't reach Dwellr right now. Check your internet connection."],
    [/jwt expired|invalid jwt|not authenticated/i, "Your session ended. Log in again."],
    [/up to 5 photos/i, "You can have up to 5 photos."],
    [/only message students you are connected with|row-level security.*messages/i, "You can only message students you're connected with."],
  ];

  function toError(error) {
    const raw = (error && (error.message || error.error_description || String(error))) || "Something went wrong.";
    const match = FRIENDLY.find(([re]) => re.test(raw));
    const err = new Error(match ? match[1] : raw);
    err.cause = error;
    return err;
  }

  async function run(request) {
    let result;
    try { result = await request; } catch (e) { throw toError(e); }
    if (result.error) throw toError(result.error);
    return result.data;
  }

  async function myId() {
    const { data } = await sb.auth.getSession();
    const id = data.session && data.session.user.id;
    if (!id) throw new Error("Your session ended. Log in again.");
    return id;
  }

  /* ---------- Shape data the way app.js expects ---------- */
  function colorFor(id) {
    let h = 0;
    for (const ch of String(id)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    return COLORS[h % COLORS.length];
  }

  // Only show photos stored in this project's photo bucket.
  const safePhotos = (urls) => (urls || []).filter((u) => typeof u === "string" && u.startsWith(PHOTO_PREFIX));

  function toPerson(row) {
    return {
      id: row.user_id,
      first: row.first_name,
      last: row.last_name,
      age: row.age,
      gender: row.gender,
      from: `${row.city}, ${row.state}`,
      intro: row.introduce,
      location: row.living_location,
      housing: { moveIn: row.move_in_date, lease: row.lease_length, budget: row.monthly_budget },
      prefs: {
        clean: row.cleanliness_level,
        sleep: row.sleep_schedule,
        guests: row.guest_frequency,
        friend: row.friendship_expectation,
      },
      hobbies: row.interests || [],
      photos: safePhotos(row.photo_urls),
      style: row.housing_type,
      size: row.household_size,
      color: colorFor(row.user_id),
    };
  }

  function toMessage(row) {
    return {
      id: row.message_id,
      connectionId: row.connection_id,
      senderId: row.sender_id,
      text: row.text_message,
      sentAt: row.message_date,
    };
  }

  async function cardsFor(ids) {
    if (!ids.length) return [];
    const rows = await run(sb.from("profile_cards").select("*").in("user_id", ids));
    return rows.map(toPerson);
  }

  /* ---------- Accounts ---------- */
  async function getInterests() {
    const rows = await run(sb.from("interest").select("interest_id, interest_name").order("interest_id"));
    return rows.map((r) => ({ id: r.interest_id, name: r.interest_name }));
  }

  async function hasSession() {
    const { data } = await sb.auth.getSession();
    return Boolean(data.session);
  }

  function onSignedOut(callback) {
    sb.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") callback();
    });
  }

  // form: { email, password, first, last, age, gender, city, state, intro, phone,
  //         location, moveIn ("YYYY-MM-01"), lease, budget, clean, sleep, guests,
  //         friend, interestIds }
  // The sign-up trigger in schema.sql copies this into the profile tables.
  async function signUp(form) {
    const data = await run(sb.auth.signUp({
      email: form.email,
      password: form.password,
      options: {
        data: {
          first_name: form.first,
          last_name: form.last,
          age: form.age,
          gender: form.gender,
          city: form.city,
          state: form.state,
          introduce: form.intro,
          phone: form.phone,
          living_location: form.location,
          move_in_date: form.moveIn,
          lease_length: form.lease,
          monthly_budget: form.budget,
          cleanliness_level: form.clean,
          sleep_schedule: form.sleep,
          guest_frequency: form.guests,
          friendship_expectation: form.friend,
          interest_ids: form.interestIds,
        },
      },
    }));
    // With "Confirm email" turned on, Supabase returns no session until the
    // student clicks the link in their email.
    return { needsEmailConfirmation: !data.session };
  }

  async function logIn(email, password) {
    await run(sb.auth.signInWithPassword({ email, password }));
  }

  async function logOut() {
    await sb.auth.signOut({ scope: "local" });
  }

  async function getMe() {
    const id = await myId();
    const row = await run(sb.from("profile_cards").select("*").eq("user_id", id).maybeSingle());
    return row ? toPerson(row) : null;
  }

  /* ---------- Find roommates ---------- */
  async function saveSearch(style, size) {
    const id = await myId();
    await run(sb.from("housing_preferences")
      .update({ housing_type: style, household_size: size })
      .eq("user_id", id));
  }

  async function getDeck(style, size) {
    const rows = await run(sb.rpc("get_deck", { p_housing_type: style || null, p_household_size: size || null }));
    return rows.map(toPerson);
  }

  // Returns the connection id when this "yes" completes a mutual match.
  async function decide(targetId, yes) {
    return run(sb.rpc("decide", { p_target: targetId, p_status: yes ? "yes" : "no" }));
  }

  /* ---------- Requests, connections, messages ---------- */
  async function getRequests() {
    const rows = await run(sb.rpc("get_connection_requests"));
    return rows.map(toPerson);
  }

  // Every active connection, newest first, with the other student's profile
  // and the chat history.
  async function getConnections() {
    const me = await myId();
    const conns = await run(sb.from("connections")
      .select("connection_id, user_1, user_2, connection_date")
      .eq("status", "connected")
      .order("connection_date", { ascending: false }));
    if (!conns.length) return [];

    const otherOf = (c) => (c.user_1 === me ? c.user_2 : c.user_1);
    const ids = conns.map((c) => c.connection_id);
    const [people, messages] = await Promise.all([
      cardsFor(conns.map(otherOf)),
      run(sb.from("messages")
        .select("message_id, connection_id, sender_id, text_message, message_date")
        .in("connection_id", ids)
        .order("message_date", { ascending: true })
        .limit(2000)),
    ]);

    return conns
      .map((c) => ({
        connectionId: c.connection_id,
        connectedAt: c.connection_date,
        person: people.find((p) => p.id === otherOf(c)),
        messages: messages.filter((m) => m.connection_id === c.connection_id).map(toMessage),
      }))
      .filter((c) => c.person);
  }

  async function sendMessage(connectionId, text) {
    const row = await run(sb.from("messages")
      .insert({ connection_id: connectionId, text_message: text })
      .select("message_id, connection_id, sender_id, text_message, message_date")
      .single());
    return toMessage(row);
  }

  async function unmatch(connectionId) {
    await run(sb.rpc("unmatch", { p_connection_id: connectionId }));
  }

  // Live updates. The database's security rules make sure each student
  // only receives their own messages and connections.
  function subscribe({ onMessage, onConnection }) {
    const channel = sb.channel("dwellr-live")
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages" },
        (payload) => onMessage(toMessage(payload.new)))
      .on("postgres_changes", { event: "*", schema: "public", table: "connections" },
        (payload) => payload.new && onConnection({
          connectionId: payload.new.connection_id,
          status: payload.new.status,
        }))
      .subscribe();
    return () => sb.removeChannel(channel);
  }

  /* ---------- Photos ---------- */
  const pathOf = (url) => url.slice(PHOTO_PREFIX.length);

  async function getMyPhotos() {
    const id = await myId();
    const rows = await run(sb.from("photos")
      .select("photo_id, photo_url, display_order")
      .eq("user_id", id)
      .order("display_order")
      .order("photo_id"));
    return rows.map((r) => ({ id: r.photo_id, url: r.photo_url }));
  }

  function newFileName(file) {
    const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
    const rand = (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    return `${rand}.${ext}`;
  }

  async function addPhoto(file) {
    const id = await myId();
    if (file.size > 5 * 1024 * 1024) throw new Error(`${file.name} is over 5 MB. Choose a smaller photo.`);
    const existing = await getMyPhotos();
    if (existing.length >= 5) throw new Error("You can have up to 5 photos.");

    const path = `${id}/${newFileName(file)}`;
    await run(sb.storage.from(PHOTO_BUCKET).upload(path, file, { contentType: file.type, upsert: false }));
    const url = sb.storage.from(PHOTO_BUCKET).getPublicUrl(path).data.publicUrl;
    try {
      await run(sb.from("photos").insert({ photo_url: url, display_order: existing.length }));
    } catch (e) {
      await sb.storage.from(PHOTO_BUCKET).remove([path]);
      throw e;
    }
  }

  async function setPhotoOrder(photos) {
    for (let i = 0; i < photos.length; i++) {
      await run(sb.from("photos").update({ display_order: i }).eq("photo_id", photos[i].id));
    }
  }

  async function removePhoto(photoId) {
    const photos = await getMyPhotos();
    const photo = photos.find((p) => p.id === photoId);
    if (!photo) return;
    await run(sb.from("photos").delete().eq("photo_id", photoId));
    if (photo.url.startsWith(PHOTO_PREFIX)) await sb.storage.from(PHOTO_BUCKET).remove([pathOf(photo.url)]);
    await setPhotoOrder(photos.filter((p) => p.id !== photoId));
  }

  async function makeMainPhoto(photoId) {
    const photos = await getMyPhotos();
    const chosen = photos.find((p) => p.id === photoId);
    if (!chosen) return;
    await setPhotoOrder([chosen, ...photos.filter((p) => p.id !== photoId)]);
  }

  /* ---------- Close account ---------- */
  async function closeAccount() {
    const id = await myId();
    // Supabase won't delete an account that still owns stored files,
    // so remove every file in the student's photo folder first.
    const files = await run(sb.storage.from(PHOTO_BUCKET).list(id, { limit: 100 }));
    if (files.length) {
      await run(sb.storage.from(PHOTO_BUCKET).remove(files.map((f) => `${id}/${f.name}`)));
    }
    await run(sb.rpc("delete_my_account"));
    await sb.auth.signOut({ scope: "local" });
  }

  return {
    getInterests, hasSession, onSignedOut, signUp, logIn, logOut, getMe,
    saveSearch, getDeck, decide, getRequests, getConnections, sendMessage, unmatch, subscribe,
    getMyPhotos, addPhoto, removePhoto, makeMainPhoto, closeAccount,
  };
})();
