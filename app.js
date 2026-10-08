// app.js: screens and interactions. All data comes from db.js (Supabase).
(() => {
  "use strict";

  const STYLE_LABEL = { apartment: "Apartment", house: "House / townhome", dorms: "Dorms" };
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"];

  /* ======================================================
     State
     ====================================================== */
  const state = {
    me: null,               // the logged-in student
    screen: "loading",
    interests: [],          // [{ id, name }] from the interest table
    search: { style: null, size: null },
    deck: [], deckTotal: 0, deckLoading: false,
    requests: [],           // people who said yes to you
    connections: [],        // [{ connectionId, person, connectedAt, messages }]
    unread: {},             // connectionId -> count, this visit only
    activeChat: null,       // connectionId
    viewing: null,          // person shown in the profile dialog
    myPhotos: [],           // [{ id, url }] in the photo manager
    justMatched: new Set(), // matches made in this tab (skip duplicate alerts)
    unsubscribe: null,
    signingOut: false,
  };

  /* ======================================================
     Helpers
     ====================================================== */
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fullName = (p) => `${p.first} ${p.last}`;
  const initials = (p) => ((p.first || "?")[0] + ((p.last || "")[0] || "")).toUpperCase();
  const clamp01 = (n) => Math.max(0, Math.min(1, n));
  const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const icon = (name) => `<svg class="i" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const joinList = (arr) => arr.length < 2 ? (arr[0] || "") : `${arr.slice(0, -1).join(", ")} and ${arr[arr.length - 1]}`;
  const sizeLabel = (n) => (n >= 6 ? "6+" : String(n));
  const findConn = (id) => state.connections.find((c) => c.connectionId === id);

  // "2027-08-01" -> "August 2027"
  function formatMonth(dateStr) {
    const [y, m] = String(dateStr || "").split("-");
    return MONTHS[Number(m) - 1] ? `${MONTHS[Number(m) - 1]} ${y}` : "";
  }

  function avatar(p, cls = "") {
    const src = p.photos && p.photos[0];
    if (src) return `<span class="avatar ${cls}"><img src="${esc(src)}" alt=""></span>`;
    return `<span class="avatar ${cls}" style="--c:${p.color}" aria-hidden="true">${esc(initials(p))}</span>`;
  }

  function photoOrInitials(p) {
    return `<span class="photo-initials" aria-hidden="true">${esc(initials(p))}</span>`
      + (p.photos && p.photos[0] ? `<img src="${esc(p.photos[0])}" alt="Photo of ${esc(p.first)}">` : "");
  }

  const sharedHobbies = (p) => p.hobbies.filter((h) => state.me.hobbies.includes(h));

  let toastTimer;
  function toast(msg) {
    const t = $("#toast");
    t.textContent = msg;
    t.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove("show"), 4000);
  }

  function handleError(e) {
    const msg = (e && e.message) || "Something went wrong.";
    toast(msg);
    if (/session ended/i.test(msg)) endSession();
  }

  function busy(btn, on, label) {
    if (!btn) return;
    if (on) {
      btn.dataset.label = btn.innerHTML;
      btn.disabled = true;
      btn.setAttribute("aria-busy", "true");
      if (label) btn.textContent = label;
    } else {
      btn.disabled = false;
      btn.removeAttribute("aria-busy");
      if (btn.dataset.label) btn.innerHTML = btn.dataset.label;
    }
  }

  function openDialog(d) {
    if (d.open) d.close();
    d.showModal();
  }

  function confirmBox({ title, body, confirm }) {
    const d = $("#dlg-confirm");
    $("#confirm-title").textContent = title;
    $("#confirm-body").textContent = body;
    $("#confirm-ok").textContent = confirm;
    d.returnValue = "";
    openDialog(d);
    return new Promise((resolve) => {
      d.addEventListener("close", () => resolve(d.returnValue === "ok"), { once: true });
    });
  }

  function emptyState(title, body, btnLabel, go) {
    const btn = btnLabel ? `<button type="button" class="btn btn-outline btn-sm" data-go="${go}">${btnLabel}</button>` : "";
    return `<li class="empty"><strong>${title}</strong><p>${body}</p>${btn}</li>`;
  }

  /* ---------- Form errors ---------- */
  function setError(el, msg) {
    const field = el.closest(".field");
    if (!field) return;
    field.classList.add("has-error");
    const m = $(".error-msg", field);
    m.textContent = msg;
    if (!m.id) m.id = "err-" + Math.random().toString(36).slice(2, 9);
    $$("input, select, textarea", field).forEach((i) => {
      i.setAttribute("aria-invalid", "true");
      i.setAttribute("aria-describedby", m.id);
    });
  }

  function clearErrors(form) {
    $$(".has-error", form).forEach((f) => f.classList.remove("has-error"));
    $$("[aria-invalid]", form).forEach((i) => i.removeAttribute("aria-invalid"));
  }

  function focusFirstError(form) {
    const field = $(".has-error", form);
    if (!field) return;
    field.scrollIntoView({ behavior: reduceMotion() ? "auto" : "smooth", block: "center" });
    const input = $("input:not([disabled]), select, textarea", field);
    if (input) input.focus({ preventScroll: true });
  }

  function showSummary(el, msg, kind = "error") {
    el.textContent = msg;
    el.classList.toggle("is-info", kind === "info");
    el.hidden = false;
  }

  // Clear a field's error as soon as the student fixes it.
  document.addEventListener("input", (e) => {
    const field = e.target.closest && e.target.closest(".field.has-error");
    if (!field) return;
    field.classList.remove("has-error");
    $$("[aria-invalid]", field).forEach((i) => i.removeAttribute("aria-invalid"));
  });

  /* ======================================================
     Navigation
     ====================================================== */
  const NEEDS_USER = new Set(["dashboard", "search", "swipe", "requests", "messages", "settings", "profile"]);
  const RENDER = {
    dashboard: async () => { renderDashboard(); await refreshInbox(); if (state.screen === "dashboard") renderDashboard(); },
    search: renderSearch,
    swipe: renderDeck,
    requests: async () => { selectTab("req"); renderRequests(); await refreshInbox(); if (state.screen === "requests") renderRequests(); },
    messages: async () => { renderMessages(); await refreshInbox(); if (state.screen === "messages") renderMessages(); },
    profile: async () => {
      renderProfile();
      const fresh = await db.getMe();
      if (fresh) { state.me = fresh; if (state.screen === "profile") renderProfile(); }
    },
  };

  function show(name) {
    if (NEEDS_USER.has(name) && !state.me) name = "login";
    $$(".screen").forEach((s) => s.classList.toggle("is-active", s.id === `screen-${name}`));
    state.screen = name;
    if (RENDER[name]) Promise.resolve().then(RENDER[name]).catch(handleError);
    window.scrollTo(0, 0);
    const h = $(`#screen-${name} h1`);
    if (h) { h.tabIndex = -1; h.focus({ preventScroll: true }); }
  }

  function rerenderCurrent() {
    const now = {
      dashboard: renderDashboard, requests: renderRequests, messages: renderMessages,
      swipe: renderDeck, profile: renderProfile,
    }[state.screen];
    if (now) now();
  }

  document.addEventListener("click", (e) => {
    const el = e.target.closest("[data-go],[data-view],[data-chat],[data-clear-filters],[data-chat-open]");
    if (!el) return;
    const d = el.dataset;

    if (d.go) {
      e.preventDefault();
      show(d.go);
    } else if (d.view) {
      const p = state.requests.find((r) => r.id === d.view);
      if (p) openProfile(p, "request");
    } else if (d.chat) {
      state.activeChat = Number(d.chat);
      show("messages");
    } else if ("clearFilters" in d) {
      state.search = { style: null, size: null };
      loadDeck();
    } else if (d.chatOpen) {
      state.activeChat = Number(d.chatOpen);
      renderChatList();
      renderChatPane();
    }
  });

  /* ======================================================
     Session
     ====================================================== */
  function resetState() {
    if (state.unsubscribe) { state.unsubscribe(); state.unsubscribe = null; }
    Object.assign(state, {
      me: null, search: { style: null, size: null }, deck: [], deckTotal: 0, deckLoading: false,
      requests: [], connections: [], unread: {}, activeChat: null, viewing: null, myPhotos: [],
      justMatched: new Set(),
    });
    $$("dialog[open]").forEach((d) => d.close());
  }

  async function startSession() {
    const me = await db.getMe();
    if (!me) {
      state.signingOut = true;
      await db.logOut();
      state.signingOut = false;
      show("login");
      showSummary($("#login-summary"), "This account doesn't have a Dwellr profile yet. Sign up to create one.");
      return;
    }
    resetState();
    state.me = me;
    state.search = { style: me.style, size: me.size };
    state.unsubscribe = db.subscribe({ onMessage: handleIncomingMessage, onConnection: handleConnectionChange });
    show("dashboard");
  }

  function endSession(message) {
    if (!state.me) return;
    resetState();
    show("landing");
    if (message) toast(message);
  }

  async function refreshInbox() {
    if (!state.me) return;
    const [requests, connections] = await Promise.all([db.getRequests(), db.getConnections()]);
    state.requests = requests;
    state.connections = connections;
  }

  db.onSignedOut(() => {
    if (!state.signingOut) endSession("You've been logged out.");
  });

  /* ---------- Login ---------- */
  $("#login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = e.currentTarget;
    const summary = $("#login-summary");
    clearErrors(f);
    summary.hidden = true;
    $$("[data-required]", f).forEach((i) => { if (!i.value.trim()) setError(i, "This field is required"); });
    const email = f.elements.namedItem("email").value.trim();
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) setError(f.elements.namedItem("email"), "Email needs an @ and a domain, like name@byu.edu");
    if ($(".has-error", f)) return focusFirstError(f);

    const btn = $('button[type="submit"]', f);
    busy(btn, true, "Logging in");
    try {
      await db.logIn(email, f.elements.namedItem("password").value);
      f.reset();
      await startSession();
    } catch (err) {
      showSummary(summary, err.message);
    } finally {
      busy(btn, false);
    }
  });

  /* ======================================================
     Page 2: Sign-up
     ====================================================== */
  const signupForm = $("#signup-form");
  const hobbyGrid = $("#hobby-grid");
  let signupPhotos = [];   // [{ file, src }] uploaded after the account exists

  // Move-in year: this year and the next two.
  const thisYear = new Date().getFullYear();
  $("#su-move-year").insertAdjacentHTML("beforeend",
    [0, 1, 2].map((n) => `<option value="${thisYear + n}">${thisYear + n}</option>`).join(""));

  async function loadInterests() {
    try {
      state.interests = await db.getInterests();
      hobbyGrid.innerHTML = state.interests.map((h) =>
        `<label class="choice"><input type="checkbox" name="hobbies" value="${h.id}"><span>${esc(h.name)}</span></label>`
      ).join("");
      updateHobbyLimit();
    } catch (e) {
      hobbyGrid.innerHTML = `<p class="muted">Couldn't load interests. ${esc(e.message)} <button type="button" class="link-btn" id="retry-interests">Try again</button></p>`;
    }
  }
  hobbyGrid.addEventListener("click", (e) => {
    if (e.target.id === "retry-interests") {
      hobbyGrid.innerHTML = '<p class="muted">Loading interests</p>';
      loadInterests();
    }
  });

  function updateHobbyLimit() {
    const checked = $$("input:checked", hobbyGrid).length;
    $$("input", hobbyGrid).forEach((i) => { if (!i.checked) i.disabled = checked >= 5; });
    const counter = $("#hobby-count");
    counter.textContent = `${checked} of 5 selected`;
    counter.classList.toggle("is-full", checked >= 3);
  }
  hobbyGrid.addEventListener("change", updateHobbyLimit);

  const introEl = $("#su-intro");
  introEl.addEventListener("input", () => {
    $("#intro-count").textContent = `${introEl.value.trim().length} / 500 (50 minimum)`;
  });

  /* ---------- Photo grids (sign-up and My Profile) ---------- */
  function photoGridHTML(srcs) {
    const slots = srcs.map((src, i) => `
      <div class="photo-slot">
        <img src="${esc(src)}" alt="Photo ${i + 1}">
        ${i === 0
          ? '<span class="photo-tag">Main</span>'
          : `<button type="button" class="photo-main" data-main="${i}">Make main</button>`}
        <button type="button" class="photo-remove" data-remove="${i}" aria-label="Remove photo ${i + 1}">${icon("x")}</button>
      </div>`).join("");
    const add = srcs.length < 5
      ? `<label class="photo-slot photo-add">
           <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" multiple class="sr-only" aria-label="Add photos">
           ${icon("plus")}<span>Add photo</span>
         </label>`
      : "";
    return slots + add;
  }

  function wirePhotoGrid(grid, actions) {
    grid.addEventListener("change", (e) => {
      if (!e.target.matches('input[type="file"]')) return;
      const files = [...e.target.files].filter((f) => f.type.startsWith("image/"));
      e.target.value = "";
      if (files.length) actions.add(files);
    });
    grid.addEventListener("click", (e) => {
      const rm = e.target.closest("[data-remove]");
      const mk = e.target.closest("[data-main]");
      if (rm) actions.remove(Number(rm.dataset.remove));
      if (mk) actions.main(Number(mk.dataset.main));
    });
  }

  const signupGrid = $("#signup-photo-grid");
  const renderSignupPhotos = () => { signupGrid.innerHTML = photoGridHTML(signupPhotos.map((p) => p.src)); };
  wirePhotoGrid(signupGrid, {
    add(files) {
      const room = 5 - signupPhotos.length;
      files.slice(0, room).forEach((file) => {
        if (file.size > 5 * 1024 * 1024) return toast(`${file.name} is over 5 MB. Choose a smaller photo.`);
        signupPhotos.push({ file, src: URL.createObjectURL(file) });
      });
      renderSignupPhotos();
    },
    remove(i) {
      URL.revokeObjectURL(signupPhotos[i].src);
      signupPhotos.splice(i, 1);
      renderSignupPhotos();
    },
    main(i) {
      const [p] = signupPhotos.splice(i, 1);
      signupPhotos.unshift(p);
      renderSignupPhotos();
    },
  });
  renderSignupPhotos();

  function resetSignupForm() {
    signupForm.reset();
    signupPhotos.forEach((p) => URL.revokeObjectURL(p.src));
    signupPhotos = [];
    renderSignupPhotos();
    updateHobbyLimit();
    clearErrors(signupForm);
    $("#signup-summary").hidden = true;
    $("#intro-count").textContent = "0 / 500 (50 minimum)";
  }

  /* ---------- Sign-up validation (matches the database rules) ---------- */
  signupForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = signupForm;
    const el = (name) => f.elements.namedItem(name);
    const v = (name) => String(el(name).value || "").trim();
    const summary = $("#signup-summary");
    clearErrors(f);

    $$("[data-required]", f).forEach((i) => { if (!i.value.trim()) setError(i, "This field is required"); });
    $$("[data-radio]", f).forEach((group) => {
      if (!$("input:checked", group)) setError($("input", group), "This field is required");
    });

    if (v("password") && v("password").length < 8) setError(el("password"), "Password needs at least 8 characters");
    if (v("email") && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v("email"))) {
      setError(el("email"), "Email needs an @ and a domain, like name@byu.edu");
    }
    const digits = v("phone").replace(/\D/g, "");
    if (v("phone") && digits.length !== 10) setError(el("phone"), "Phone number must be 10 digits");
    const age = Number(v("age"));
    if (v("age") && (!Number.isInteger(age) || age < 17 || age > 99)) setError(el("age"), "Enter an age between 17 and 99");
    const intro = v("intro");
    if (intro && (intro.length < 50 || intro.length > 500)) {
      setError(el("intro"), `Write between 50 and 500 characters. You have ${intro.length}.`);
    }
    const month = Number(v("moveMonth")), year = Number(v("moveYear"));
    const now = new Date();
    if (month && year && (year < now.getFullYear() || (year === now.getFullYear() && month < now.getMonth() + 1))) {
      setError(el("moveMonth"), "Choose a month that hasn't passed yet");
    }
    const interestIds = $$("input:checked", hobbyGrid).map((i) => Number(i.value));
    if (!state.interests.length) {
      setError(hobbyGrid, "Interests haven't loaded yet. Check your connection and try again.");
    } else if (interestIds.length < 3) {
      setError($("input", hobbyGrid), `Choose at least 3 hobbies. You've chosen ${interestIds.length}.`);
    }

    const errors = $$(".field.has-error", f).length;
    if (errors) {
      showSummary(summary, `${errors} ${errors === 1 ? "field needs" : "fields need"} attention before we can create your profile.`);
      focusFirstError(f);
      return;
    }
    summary.hidden = true;

    const btn = $('button[type="submit"]', f);
    busy(btn, true, "Creating your profile");
    try {
      const { needsEmailConfirmation } = await db.signUp({
        email: v("email"), password: el("password").value,
        first: v("first"), last: v("last"), age, gender: v("gender"),
        city: v("city"), state: v("state"), intro, phone: digits,
        location: v("location"),
        moveIn: `${year}-${String(month).padStart(2, "0")}-01`,
        lease: Number(v("lease")), budget: v("budget"),
        clean: Number(v("clean")), sleep: v("sleep"), guests: v("guests"), friend: v("friend"),
        interestIds,
      });

      if (needsEmailConfirmation) {
        const hadPhotos = signupPhotos.length > 0;
        resetSignupForm();
        show("login");
        showSummary($("#login-summary"),
          `Check your email and click the confirmation link, then log in here.${hadPhotos ? " Add your photos from My Profile once you're in." : ""}`, "info");
        return;
      }

      let failed = 0;
      for (let i = 0; i < signupPhotos.length; i++) {
        btn.textContent = `Uploading photo ${i + 1} of ${signupPhotos.length}`;
        try { await db.addPhoto(signupPhotos[i].file); } catch { failed++; }
      }
      resetSignupForm();
      await startSession();
      toast(failed
        ? `Profile created, but ${failed} ${failed === 1 ? "photo" : "photos"} didn't upload. Add them from My Profile.`
        : "Profile created. Students who share your interests can now find you.");
    } catch (err) {
      showSummary(summary, err.message);
      summary.scrollIntoView({ behavior: reduceMotion() ? "auto" : "smooth", block: "center" });
    } finally {
      busy(btn, false);
    }
  });

  /* ======================================================
     Page 3: Dashboard
     ====================================================== */
  function setBadge(sel, n) {
    const b = $(sel);
    b.hidden = !n;
    b.textContent = n;
    b.setAttribute("aria-label", `${n} new`);
  }

  function renderDashboard() {
    const u = state.me;
    if (!u) return;
    $("#dash-name").textContent = u.first;
    $("#dash-sub").textContent = `Looking for a place in ${u.location} starting ${formatMonth(u.housing.moveIn)}.`;

    const req = state.requests.length;
    const chats = state.connections;
    const unread = chats.reduce((n, c) => n + (state.unread[c.connectionId] || 0), 0);
    setBadge("#badge-req", req);
    setBadge("#badge-msg", unread);

    $("#dash-req-meta").textContent = req
      ? `${req} ${req === 1 ? "person wants" : "people want"} to room with you`
      : "No new requests right now";
    $("#dash-msg-meta").textContent = chats.length
      ? `${chats.length} ${chats.length === 1 ? "conversation" : "conversations"}${unread ? `, ${unread} unread` : ""}`
      : "Chats open once you connect with someone";
  }

  /* ======================================================
     Page 4: Search preferences
     ====================================================== */
  function renderSearch() {
    const f = $("#search-form");
    clearErrors(f);
    $$('input[name="size"]', f).forEach((i) => { i.checked = Number(i.value) === state.me.size; });
    $$('input[name="style"]', f).forEach((i) => { i.checked = i.value === state.me.style; });
  }

  $("#search-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = e.currentTarget;
    clearErrors(f);
    $$("[data-radio]", f).forEach((g) => { if (!$("input:checked", g)) setError($("input", g), "Choose one to continue"); });
    if ($(".has-error", f)) return focusFirstError(f);

    const size = Number(f.elements.namedItem("size").value);
    const style = f.elements.namedItem("style").value;
    const btn = $('button[type="submit"]', f);
    busy(btn, true, "Saving");
    try {
      await db.saveSearch(style, size);   // shown on My Profile and used by other students' searches
      state.me.size = size;
      state.me.style = style;
      state.search = { style, size };
      show("swipe");
      loadDeck();
    } catch (err) {
      handleError(err);
    } finally {
      busy(btn, false);
    }
  });

  /* ======================================================
     Page 5: Swipe deck
     ====================================================== */
  async function loadDeck() {
    state.deckLoading = true;
    renderDeck();
    try {
      const deck = await db.getDeck(state.search.style, state.search.size);
      state.deck = deck;
      state.deckTotal = deck.length;
    } catch (err) {
      state.deck = [];
      handleError(err);
    } finally {
      state.deckLoading = false;
      if (state.screen === "swipe") renderDeck();
    }
  }

  function filterSummary() {
    const s = state.search;
    const parts = [];
    if (s.style) parts.push(STYLE_LABEL[s.style]);
    if (s.size) parts.push(`${sizeLabel(s.size)} people`);
    return parts.length ? `Showing: ${parts.join(", ")}` : "Showing: everyone";
  }

  function makeCard(p, behind) {
    const shared = sharedHobbies(p);
    const card = document.createElement("article");
    card.className = "swipe-card" + (behind ? " is-behind" : "");
    card.setAttribute("aria-label", `${fullName(p)}, ${p.age}`);
    if (behind) card.setAttribute("aria-hidden", "true");
    card.innerHTML = `
      <div class="swipe-photo" style="--c:${p.color}">
        ${photoOrInitials(p)}
        <span class="stamp stamp-yes" aria-hidden="true">Interested</span>
        <span class="stamp stamp-no" aria-hidden="true">Pass</span>
        <div class="swipe-name">
          <h2>${esc(fullName(p))}, ${esc(p.age)}</h2>
          <p>From ${esc(p.from)}. Looking in ${esc(p.location)}.</p>
        </div>
      </div>
      <div class="swipe-info">
        <ul class="chips" aria-label="Hobbies">
          ${p.hobbies.map((h) => `<li class="chip${shared.includes(h) ? " is-shared" : ""}">${esc(h)}</li>`).join("")}
        </ul>
        <div class="swipe-info-foot">
          <p class="shared-note">${shared.length ? `You both like ${esc(joinList(shared))}` : ""}</p>
          <button type="button" class="link-btn" data-profile${behind ? ' tabindex="-1"' : ""}>Full profile</button>
        </div>
      </div>`;
    $$("img", card).forEach((img) => { img.draggable = false; });
    return card;
  }

  function deckEmptyHTML() {
    if (state.deckLoading) return `<div class="deck-loading">Finding roommates</div>`;
    const filtered = state.search.style || state.search.size;
    if (filtered && state.deckTotal === 0) {
      return `<div class="deck-empty">
        <h2>No matches found</h2>
        <p>No one fits this search yet. Try a different kind of place, or clear your filters to see everyone.</p>
        <div class="btn-row">
          <button type="button" class="btn btn-ink" data-clear-filters>Clear filters</button>
          <button type="button" class="btn btn-outline" data-go="search">Change search</button>
        </div></div>`;
    }
    if (filtered) {
      return `<div class="deck-empty">
        <h2>You've seen everyone in this search</h2>
        <p>Clear your filters to see more students, or check back as more people sign up.</p>
        <div class="btn-row">
          <button type="button" class="btn btn-ink" data-clear-filters>Clear filters</button>
          <button type="button" class="btn btn-outline" data-go="dashboard">Back to dashboard</button>
        </div></div>`;
    }
    return `<div class="deck-empty">
      <h2>You're all caught up</h2>
      <p>You've seen everyone looking right now. Check your requests while more students sign up.</p>
      <div class="btn-row">
        <button type="button" class="btn btn-ink" data-go="requests">See connection requests</button>
        <button type="button" class="btn btn-outline" data-go="dashboard">Back to dashboard</button>
      </div></div>`;
  }

  function renderDeck() {
    $("#filter-summary").textContent = filterSummary();
    const deck = $("#deck");
    deck.innerHTML = "";
    const [top, next] = state.deckLoading ? [] : state.deck;
    $("#swipe-actions").hidden = !top;
    $("#swipe-help").hidden = !top;
    if (!top) { deck.innerHTML = deckEmptyHTML(); return; }
    if (next) deck.append(makeCard(next, true));
    const card = makeCard(top, false);
    deck.append(card);
    attachDrag(card, top);
  }

  let swiping = false;

  function attachDrag(card, p) {
    let x0 = 0, dx = 0, active = false;
    const reset = () => {
      card.style.transform = "";
      card.style.setProperty("--yes", 0);
      card.style.setProperty("--no", 0);
    };
    card.addEventListener("pointerdown", (e) => {
      if (e.button !== 0 || swiping || e.target.closest("button")) return;
      active = true; x0 = e.clientX; dx = 0;
      card.setPointerCapture(e.pointerId);
      card.classList.add("is-dragging");
    });
    card.addEventListener("pointermove", (e) => {
      if (!active) return;
      dx = e.clientX - x0;
      card.style.transform = `translateX(${dx}px) rotate(${dx / 20}deg)`;
      card.style.setProperty("--yes", clamp01(dx / 120));
      card.style.setProperty("--no", clamp01(-dx / 120));
    });
    const end = () => {
      if (!active) return;
      active = false;
      card.classList.remove("is-dragging");
      if (dx > 110) swipe("right");
      else if (dx < -110) swipe("left");
      else reset();
    };
    card.addEventListener("pointerup", end);
    card.addEventListener("pointercancel", () => { dx = 0; end(); });
    card.addEventListener("click", (e) => {
      if (e.target.closest("[data-profile]")) openProfile(p, "view");
    });
  }

  function swipe(dir) {
    const p = state.deck[0];
    const card = $("#deck .swipe-card:not(.is-behind)");
    if (!p || !card || swiping) return;
    swiping = true;
    const finish = () => {
      swiping = false;
      state.deck.shift();
      renderDeck();
      recordSwipe(p, dir === "right");
    };
    if (reduceMotion()) return finish();
    const right = dir === "right";
    card.style.transition = "transform 0.3s ease-in, opacity 0.3s ease-in";
    card.style.transform = `translateX(${right ? 140 : -140}%) rotate(${right ? 16 : -16}deg)`;
    card.style.opacity = "0";
    card.style.setProperty(right ? "--yes" : "--no", 1);
    setTimeout(finish, 280);
  }

  // The card is already gone; save the swipe in the background.
  async function recordSwipe(p, yes) {
    try {
      const connectionId = await db.decide(p.id, yes);
      if (!yes) return;
      if (connectionId) {
        // Mutual match: they had already said yes to you.
        state.justMatched.add(connectionId);
        state.requests = state.requests.filter((r) => r.id !== p.id);
        openMatch(p, connectionId);
      } else {
        toast(`Request sent to ${p.first}`);
      }
    } catch (err) {
      state.deck.unshift(p);
      if (state.screen === "swipe") renderDeck();
      toast(`Couldn't save that swipe. ${err.message}`);
    }
  }

  $("#btn-pass").addEventListener("click", () => swipe("left"));
  $("#btn-like").addEventListener("click", () => swipe("right"));

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeMenus();
    if (state.screen !== "swipe" || $("dialog[open]")) return;
    if (e.target.matches && e.target.matches("input, textarea, select")) return;
    if (e.key === "ArrowRight") swipe("right");
    if (e.key === "ArrowLeft") swipe("left");
  });

  function openMatch(p, connectionId) {
    $("#match-title").textContent = `You and ${p.first} both said yes`;
    $("#match-avatars").innerHTML = avatar(state.me, "avatar-lg") + avatar(p, "avatar-lg");
    openDialog($("#dlg-match"));
    $("#match-chat").onclick = () => {
      $("#dlg-match").close();
      state.activeChat = connectionId;
      show("messages");
    };
  }

  /* ======================================================
     Profile viewer (requests, chats, swipe cards)
     ====================================================== */
  function compareRows(p) {
    const u = state.me.prefs, t = p.prefs;
    const rows = [
      ["Cleanliness", `${u.clean} of 5`, `${t.clean} of 5`, Math.abs(u.clean - t.clean) <= 1],
      ["Sleep schedule", u.sleep, t.sleep, u.sleep === t.sleep || u.sleep === "Varies" || t.sleep === "Varies"],
      ["Guests over", u.guests, t.guests, u.guests === t.guests],
      ["Friendship", u.friend, t.friend, u.friend === t.friend],
    ];
    return rows.map(([label, mine, theirs, ok]) => `
      <li class="compare-row">
        <div class="compare-top">
          <strong>${label}</strong>
          <span class="pill ${ok ? "pill-ok" : "pill-talk"}">${ok ? "Lines up" : "Talk about this"}</span>
        </div>
        <p>You: ${esc(mine)}. ${esc(p.first)}: ${esc(theirs)}.</p>
      </li>`).join("");
  }

  function housingSentence(p) {
    const place = p.style
      ? `Wants ${p.style === "dorms" ? "the dorms" : `a ${STYLE_LABEL[p.style].toLowerCase()}`}${p.size ? ` with ${sizeLabel(p.size)} people total` : ""}. `
      : "";
    return `${place}Moving in ${formatMonth(p.housing.moveIn)}, ${p.housing.lease}-month lease, ${p.housing.budget} a month.`;
  }

  function profileDetailHTML(p) {
    const shared = sharedHobbies(p);
    return `
      <div class="detail-photo" style="--c:${p.color}">${photoOrInitials(p)}</div>
      <div class="detail-body">
        <h2 id="dlg-profile-title">${esc(fullName(p))}, ${esc(p.age)}</h2>
        <p class="muted">From ${esc(p.from)}. Looking in ${esc(p.location)}.</p>
        <p class="detail-intro">${esc(p.intro)}</p>

        <h3>Hobbies</h3>
        <ul class="chips">${p.hobbies.map((h) => `<li class="chip${shared.includes(h) ? " is-shared" : ""}">${esc(h)}</li>`).join("")}</ul>
        ${shared.length ? `<p class="shared-note">Highlighted hobbies are ones you share.</p>` : ""}

        <h3>Housing</h3>
        <p>${esc(housingSentence(p))}</p>

        <h3>How your habits compare</h3>
        <ul class="compare">${compareRows(p)}</ul>
      </div>`;
  }

  function openProfile(p, mode) {
    state.viewing = p;
    $("#dlg-profile-body").innerHTML = profileDetailHTML(p);
    $("#dlg-profile-actions").hidden = mode !== "request";
    openDialog($("#dlg-profile"));
  }

  $("#dlg-connect").addEventListener("click", async (e) => {
    const p = state.viewing;
    const btn = e.currentTarget;
    busy(btn, true, "Connecting");
    try {
      const connectionId = await db.decide(p.id, true);
      if (connectionId) state.justMatched.add(connectionId);
      $("#dlg-profile").close();
      await refreshInbox();
      renderRequests();
      if (connectionId) {
        selectTab("con");
        toast(`You and ${p.first} are connected. Your chat is in Messages.`);
      } else {
        toast(`${p.first}'s request is no longer available.`);
      }
    } catch (err) {
      handleError(err);
    } finally {
      busy(btn, false);
    }
  });

  $("#dlg-decline").addEventListener("click", async (e) => {
    const p = state.viewing;
    const btn = e.currentTarget;
    busy(btn, true, "Declining");
    try {
      await db.decide(p.id, false);
      state.requests = state.requests.filter((x) => x.id !== p.id);
      $("#dlg-profile").close();
      renderRequests();
      toast(`Declined ${p.first}'s request`);
    } catch (err) {
      handleError(err);
    } finally {
      busy(btn, false);
    }
  });

  /* ======================================================
     Page 6: Connection requests
     ====================================================== */
  function selectTab(which) {
    const req = which === "req";
    $("#tab-req").setAttribute("aria-selected", String(req));
    $("#tab-con").setAttribute("aria-selected", String(!req));
    $("#panel-req").hidden = !req;
    $("#panel-con").hidden = req;
  }
  $("#tab-req").addEventListener("click", () => selectTab("req"));
  $("#tab-con").addEventListener("click", () => selectTab("con"));

  function renderRequests() {
    if (!state.me) return;
    $("#count-req").textContent = state.requests.length || "";
    $("#count-con").textContent = state.connections.length || "";

    $("#req-list").innerHTML = state.requests.length
      ? state.requests.map((p) => {
          const shared = sharedHobbies(p);
          const sub = shared.length ? `Wants to room with you. You both like ${joinList(shared)}.` : "Wants to room with you.";
          return `<li>
            <button type="button" class="row row-btn" data-view="${esc(p.id)}">
              ${avatar(p)}
              <span class="row-text"><strong>${esc(fullName(p))}</strong><span>${esc(sub)}</span></span>
              <span class="row-cta">View profile${icon("chevron")}</span>
            </button></li>`;
        }).join("")
      : emptyState("No requests right now", "When someone swipes right on you, they'll show up here.", "Find roommates", "search");

    $("#con-list").innerHTML = state.connections.length
      ? state.connections.map((c) => `<li class="row">
            ${avatar(c.person)}
            <span class="row-text"><strong>You and ${esc(c.person.first)} connected</strong><span>Your chat is open in Messages</span></span>
            <button type="button" class="btn btn-outline btn-sm" data-chat="${c.connectionId}">Message</button>
          </li>`).join("")
      : emptyState("No connections yet", "Connect with someone from your requests, or swipe right on people you'd live with.", "Find roommates", "search");
  }

  /* ======================================================
     Page 7: Messages
     ====================================================== */
  function renderMessages() {
    if (!state.me) return;
    const ids = state.connections.map((c) => c.connectionId);
    if (state.activeChat && !ids.includes(state.activeChat)) state.activeChat = null;
    if (!state.activeChat && ids.length && window.matchMedia("(min-width: 760px)").matches) state.activeChat = ids[0];
    renderChatList();
    renderChatPane();
  }

  function renderChatList() {
    $("#chat-list").innerHTML = state.connections.length
      ? state.connections.map((c) => {
          const last = c.messages[c.messages.length - 1];
          const preview = last ? (last.senderId === state.me.id ? "You: " : "") + last.text : "New connection. Say hi.";
          const unread = state.unread[c.connectionId];
          return `<li>
            <button type="button" class="chat-item${c.connectionId === state.activeChat ? " is-active" : ""}" data-chat-open="${c.connectionId}">
              ${avatar(c.person)}
              <span class="row-text"><strong>${esc(fullName(c.person))}</strong><span>${esc(preview)}</span></span>
              ${unread ? `<span class="dot"></span><span class="sr-only">${unread} unread</span>` : ""}
            </button></li>`;
        }).join("")
      : emptyState("No chats yet", "A chat opens when you and another student both say yes.", "Find roommates", "search");
  }

  function messagesHTML(c) {
    const hint = c.messages.length ? "" : `<p class="chat-hint">Good first topics: move-in dates, how you'd split chores, and quiet hours.</p>`;
    return `<p class="chat-system">You and ${esc(c.person.first)} connected</p>${hint}`
      + c.messages.map((m) => `<p class="bubble ${m.senderId === state.me.id ? "me" : "them"}">${esc(m.text)}</p>`).join("");
  }

  function scrollChat() {
    const body = $("#chat-body");
    if (body) body.scrollTop = body.scrollHeight;
  }

  function renderChatPane() {
    const pane = $("#chat-pane");
    const c = findConn(state.activeChat);
    $("#msg-layout").classList.toggle("is-chat-open", Boolean(c));
    if (!c) {
      pane.innerHTML = `<div class="chat-empty"><p>Pick a conversation to start chatting.</p></div>`;
      return;
    }
    const p = c.person;
    state.unread[c.connectionId] = 0;
    pane.innerHTML = `
      <header class="chat-head">
        <button type="button" class="icon-btn chat-back" data-chat-back aria-label="Back to conversations">${icon("back")}</button>
        ${avatar(p, "avatar-sm")}
        <div class="chat-who"><strong>${esc(fullName(p))}</strong><span>Connected</span></div>
        <div class="menu">
          <button type="button" class="icon-btn" data-menu-toggle aria-haspopup="true" aria-expanded="false" aria-label="Chat options">${icon("more")}</button>
          <div class="menu-pop" role="menu" hidden>
            <button type="button" role="menuitem" data-act="profile">View profile</button>
            <button type="button" role="menuitem" class="is-danger" data-act="unmatch">Unmatch</button>
          </div>
        </div>
      </header>
      <div class="chat-body" id="chat-body" aria-live="polite">${messagesHTML(c)}</div>
      <form class="composer" id="composer">
        <label class="sr-only" for="composer-input">Message ${esc(p.first)}</label>
        <input id="composer-input" autocomplete="off" maxlength="2000" placeholder="Message ${esc(p.first)}">
        <button type="submit" class="btn btn-ink" aria-label="Send">${icon("send")}</button>
      </form>`;
    scrollChat();
  }

  function refreshOpenChat() {
    const c = findConn(state.activeChat);
    const body = $("#chat-body");
    if (c && body) { body.innerHTML = messagesHTML(c); scrollChat(); }
  }

  // Add a message once, whether it came from sending or from a live update.
  function addMessage(msg) {
    const c = findConn(msg.connectionId);
    if (!c || c.messages.some((m) => m.id === msg.id)) return;
    c.messages.push(msg);
    const viewing = state.screen === "messages" && state.activeChat === c.connectionId;
    if (viewing) {
      refreshOpenChat();
    } else if (msg.senderId !== state.me.id) {
      state.unread[c.connectionId] = (state.unread[c.connectionId] || 0) + 1;
      if (state.screen !== "messages") toast(`New message from ${c.person.first}`);
    }
    if (state.screen === "messages") renderChatList();
    if (state.screen === "dashboard") renderDashboard();
  }

  async function handleIncomingMessage(msg) {
    if (!state.me) return;
    if (!findConn(msg.connectionId)) {
      try { await refreshInbox(); } catch { return; }
    }
    addMessage(msg);
  }

  async function handleConnectionChange({ connectionId, status }) {
    if (!state.me) return;
    if (status === "connected") {
      if (findConn(connectionId)) return;
      try { await refreshInbox(); } catch { return; }
      const c = findConn(connectionId);
      // PRD: both students are notified when they match.
      if (c && !state.justMatched.has(connectionId)) toast(`You and ${c.person.first} are connected. Say hi in Messages.`);
      rerenderCurrent();
    } else if (status === "unmatched") {
      const c = findConn(connectionId);
      if (!c) return;
      state.connections = state.connections.filter((x) => x.connectionId !== connectionId);
      delete state.unread[connectionId];
      if (state.activeChat === connectionId) state.activeChat = null;
      if (state.screen === "messages") renderMessages();
      else rerenderCurrent();
    }
  }

  function closeMenus() {
    $$(".menu-pop").forEach((m) => {
      m.hidden = true;
      const t = m.previousElementSibling;
      if (t) t.setAttribute("aria-expanded", "false");
    });
  }
  document.addEventListener("click", (e) => { if (!e.target.closest(".menu")) closeMenus(); });

  const pane = $("#chat-pane");

  pane.addEventListener("click", (e) => {
    if (e.target.closest("[data-chat-back]")) {
      state.activeChat = null;
      renderChatList();
      renderChatPane();
      return;
    }
    const toggle = e.target.closest("[data-menu-toggle]");
    if (toggle) {
      const pop = toggle.nextElementSibling;
      const open = pop.hidden;
      closeMenus();
      pop.hidden = !open;
      toggle.setAttribute("aria-expanded", String(open));
      return;
    }
    const act = e.target.closest("[data-act]");
    if (act) {
      closeMenus();
      handleChatAction(act.dataset.act, state.activeChat);
    }
  });

  pane.addEventListener("submit", async (e) => {
    e.preventDefault();
    const input = $("#composer-input");
    const text = input.value.trim();
    const c = findConn(state.activeChat);
    if (!text || !c) return;
    input.value = "";
    try {
      addMessage(await db.sendMessage(c.connectionId, text));
    } catch (err) {
      if (!input.value) input.value = text;
      handleError(err);
    }
  });

  async function handleChatAction(act, connectionId) {
    const c = findConn(connectionId);
    if (!c) return;
    if (act === "profile") return openProfile(c.person, "view");
    if (act === "unmatch") {
      const ok = await confirmBox({
        title: `Unmatch with ${c.person.first}?`,
        body: "Your chat will be removed for both of you and neither of you can send new messages. Either of you can swipe right again later to reconnect.",
        confirm: "Unmatch",
      });
      if (!ok) return;
      try {
        await db.unmatch(connectionId);
        state.connections = state.connections.filter((x) => x.connectionId !== connectionId);
        state.activeChat = null;
        renderMessages();
        toast(`Unmatched with ${c.person.first}`);
      } catch (err) {
        handleError(err);
      }
    }
  }

  /* ======================================================
     Page 8: Settings
     ====================================================== */
  $("#btn-close-account").addEventListener("click", async (e) => {
    const ok = await confirmBox({
      title: "Close your account?",
      body: "Your profile, photos, connections, and chats will be deleted and other students won't be able to find you. This can't be undone.",
      confirm: "Close account",
    });
    if (!ok) return;
    const btn = e.currentTarget;
    busy(btn, true);
    state.signingOut = true;
    try {
      await db.closeAccount();
      endSession("Your account is closed");
    } catch (err) {
      handleError(err);
    } finally {
      state.signingOut = false;
      busy(btn, false);
    }
  });

  $("#btn-logout").addEventListener("click", async () => {
    state.signingOut = true;
    endSession("You're logged out");
    try { await db.logOut(); } finally { state.signingOut = false; }
  });

  /* ======================================================
     Page 9: My profile
     ====================================================== */
  function renderProfile() {
    const u = state.me;
    if (!u) return;
    const btn = $("#profile-photo-btn");
    btn.style.setProperty("--c", u.color);
    btn.setAttribute("aria-label", u.photos.length ? `Manage photos, ${u.photos.length} of 5 added` : "Add photos");
    btn.innerHTML = (u.photos[0]
      ? `<img src="${esc(u.photos[0])}" alt="">`
      : `<span class="photo-initials" aria-hidden="true">${esc(initials(u))}</span>`)
      + `<span class="photo-manage" aria-hidden="true">${icon("camera")}${u.photos.length ? `Photos (${u.photos.length}/5)` : "Add photos"}</span>`;

    $("#profile-name").textContent = fullName(u);
    $("#profile-meta").textContent = `${u.age}, from ${u.from}`;

    const notSet = `<button type="button" class="link-btn" data-go="search">Choose in Find roommates</button>`;
    const fact = (label, value) => `<div><dt>${label}</dt><dd>${value}</dd></div>`;

    $("#profile-body").innerHTML = `
      <section class="panel">
        <h2>About</h2>
        <p>${esc(u.intro)}</p>
      </section>
      <section class="panel">
        <h2>Hobbies and interests</h2>
        <ul class="chips">${u.hobbies.map((h) => `<li class="chip">${esc(h)}</li>`).join("")}</ul>
      </section>
      <section class="panel">
        <h2>Housing</h2>
        <dl class="facts">
          ${fact("Kind of place", u.style ? STYLE_LABEL[u.style] : notSet)}
          ${fact("People living together", u.size ? `${sizeLabel(u.size)}, including you` : notSet)}
          ${fact("Preferred location", esc(u.location))}
          ${fact("Move-in month", esc(formatMonth(u.housing.moveIn)))}
          ${fact("Lease length", `${esc(u.housing.lease)} months`)}
          ${fact("Monthly budget", esc(u.housing.budget))}
        </dl>
      </section>
      <section class="panel">
        <h2>Living habits</h2>
        <dl class="facts">
          ${fact("Cleanliness", `${esc(u.prefs.clean)} of 5`)}
          ${fact("Sleep schedule", esc(u.prefs.sleep))}
          ${fact("Guests over", esc(u.prefs.guests))}
          ${fact("Friendship", esc(u.prefs.friend))}
        </dl>
      </section>`;
  }

  /* ---------- Manage photos (saved to Supabase right away) ---------- */
  const manageGrid = $("#manage-photo-grid");
  const photoStatus = $("#photo-status");
  const renderManageGrid = () => { manageGrid.innerHTML = photoGridHTML(state.myPhotos.map((p) => p.url)); };

  async function photoTask(label, task) {
    manageGrid.classList.add("is-busy");
    photoStatus.textContent = label;
    try {
      await task();
    } catch (err) {
      toast(err.message);
    } finally {
      try { state.myPhotos = await db.getMyPhotos(); } catch (err) { toast(err.message); }
      renderManageGrid();
      manageGrid.classList.remove("is-busy");
      photoStatus.textContent = "";
    }
  }

  wirePhotoGrid(manageGrid, {
    add: (files) => photoTask("Uploading", async () => {
      const room = 5 - state.myPhotos.length;
      for (const [i, file] of files.slice(0, room).entries()) {
        photoStatus.textContent = `Uploading photo ${i + 1} of ${Math.min(files.length, room)}`;
        await db.addPhoto(file);
      }
    }),
    remove: (i) => photoTask("Removing photo", () => db.removePhoto(state.myPhotos[i].id)),
    main: (i) => photoTask("Saving", () => db.makeMainPhoto(state.myPhotos[i].id)),
  });

  $("#profile-photo-btn").addEventListener("click", () => {
    state.myPhotos = [];
    manageGrid.innerHTML = "";
    openDialog($("#dlg-photos"));
    photoTask("Loading your photos", async () => {});
  });

  $("#dlg-photos").addEventListener("close", async () => {
    try {
      const fresh = await db.getMe();
      if (fresh) { state.me = fresh; renderProfile(); }
    } catch (err) {
      handleError(err);
    }
  });

  /* ======================================================
     Start
     ====================================================== */
  async function boot() {
    loadInterests();
    try {
      if (await db.hasSession()) {
        await startSession();
        return;
      }
    } catch (err) {
      toast(err.message);
    }
    show("landing");
  }
  boot();
})();
