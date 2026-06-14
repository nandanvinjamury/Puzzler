# Using Puzzler as a Sleep as Android alarm CAPTCHA

Puzzler registers itself as a **third‑party CAPTCHA** for [Sleep as Android](https://play.google.com/store/apps/details?id=com.urbandroid.sleep).
When an alarm fires, Sleep launches Puzzler, you solve chess puzzle(s), and that
dismisses the alarm.

In Sleep's CAPTCHA list it shows up as **“Chess puzzle”** (that's the captcha's
label) — **not** “Puzzler”. That naming is the #1 reason people think it's
missing.

---

## Setup (step by step)

1. **Install both apps** on the same phone:
   - Puzzler (this app — install the release build).
   - Sleep as Android (a recent version; third‑party captcha support and
     Android 11+ package visibility need an up‑to‑date Sleep).

2. **Open Sleep as Android** at least once *after* installing Puzzler. Sleep
   scans for installed captcha apps when it starts and when you open the captcha
   picker; if Puzzler was installed while Sleep was already running, it won't see
   it until Sleep is reopened (see Troubleshooting).

3. **Pick the captcha on an alarm** (most reliable):
   - Go to the **Alarms** tab and tap an alarm to expand/edit it.
   - Tap **CAPTCHA**.
   - In the list of captcha types, choose **“Chess puzzle”**.
   - (Optional) set the **difficulty** — Puzzler maps it to *how many puzzles*
     you must solve: difficulty 1 → 1 puzzle … difficulty 5 → 5 puzzles.

   You can also set a global default at **Settings → Alarms → CAPTCHA**, but the
   per‑alarm setting above is the surest place to find it.

4. **Test it** without waiting for morning:
   - Many Sleep versions have a **Preview/Test** next to the CAPTCHA setting —
     use it to dry‑run. (In preview, solving won't *actually* dismiss anything —
     that's expected.)
   - Or set an alarm a couple of minutes ahead and let it ring.

When the alarm rings, Puzzler opens straight into the puzzle(s). Solve them and
the alarm turns off. (Backing out without solving tells Sleep to keep ringing.)

---

## Troubleshooting — “Chess puzzle” isn't in the list

Work through these in order:

1. **You're looking for the wrong name.** It's **“Chess puzzle”**, not
   “Puzzler”. The CAPTCHA list is alphabetical-ish and mixes built‑ins (Math,
   Sheep, QR…) with installed apps.

2. **Make Sleep re‑scan.** Sleep caches the captcha list. Force a refresh:
   - Android **Settings → Apps → Sleep as Android → Force stop**, then reopen
     Sleep and check the CAPTCHA list again.
   - Re-opening the captcha picker also triggers a re‑scan in recent versions.

3. **Update Sleep as Android.** Third‑party captcha discovery on Android 11+
   relies on package‑visibility queries that only recent Sleep builds declare.
   Update Sleep from the Play Store.

4. **Confirm Puzzler is actually installed** (not just running from a dev/IDE
   session) and that you didn't install it to a *work profile* while Sleep is in
   your personal profile (cross‑profile apps aren't visible to each other).

5. **Reboot** once if all else fails — clears any stale package‑manager cache.

---

## How it works (for the curious)

- Puzzler declares a dedicated `CaptchaActivity` with the intent filter
  `com.urbandroid.sleep.captcha.intent.action.OPEN` and
  `meta-data com.urbandroid.sleep.captcha.meta.has_difficulty = true`. Sleep
  discovers captchas by querying for that `OPEN` action.
- Sleep launches that activity and passes pre‑built callback `Intent`s (keyed
  `solved` / `unsolved` / `alive`) as extras. Puzzler fires the `solved` callback
  when you finish, sends periodic `alive` heartbeats while you think, and
  `unsolved` if you bail — exactly per Sleep's published captcha contract.
- It's a real, dedicated captcha activity (the canonical pattern), separate from
  Puzzler's normal launcher screen.

If it still won't show after all of the above, tell me your Sleep as Android
version and I'll dig in further.
