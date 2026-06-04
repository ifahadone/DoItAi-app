# DoIT — App Store Submission Checklist (Phase 6 / P6-5)

The code-side launch readiness is done. The remaining items require an **Apple Developer
account + signing** and a human in App Store Connect — they cannot be completed from code.

## Done in code
- [x] **Privacy manifest** — `App/PrivacyInfo.xcprivacy` (bundled; verified in the build product).
      Declares: no cross-app tracking; collected data = user content, user id, email, purchase
      history (all linked, app-functionality only); required-reason API = UserDefaults (CA92.1).
- [x] **In-app account deletion** — Settings → Account → *Delete account* (Apple guideline 5.1.1(v)),
      backed by `DELETE /account` (full server-side purge, idempotent).
- [x] **Data export / portability** — Settings → Account → *Export my data* (JSON share sheet),
      backed by `POST /account/export`.
- [x] **StoreKit 2 paywall + server-validated entitlement** — `PaywallView` + `Entitlements`
      (server is the source of truth via `/billing/receipt` + `/billing/status`).
- [x] **Graceful degradation** everywhere (AI off / no key, no products, offline) — no crashes.
- [x] **Accessibility** — SwiftUI Dynamic Type throughout; VoiceOver labels on the sectograph
      (P2-6), toolbar buttons, and controls.

## Requires an Apple Developer account (human + signing)
- [ ] Real bundle id + team; enable **Sign in with Apple**, **Time-Sensitive Notifications**, and
      (if pursuing louder alarms) request the **Critical Alerts** entitlement.
- [ ] Add the **Widget Extension** + **App Group** targets and move the shared models into a
      framework (see `Widget/README.md`) — turns the reference widgets/Live Activities into shippable ones.
- [ ] App Store Connect: create the **`app.doit.pro.monthly` / `app.doit.pro.annual`** auto-renewable
      subscriptions; add a **StoreKit configuration file** to the scheme for local purchase testing.
- [ ] Point the App Store Server **Notifications V2** URL at `POST /api/v1/billing/notifications`.
- [ ] **Re-harden the backend**: `NODE_ENV=production`, `APPLE_STUB_VERIFICATION=false`,
      `BILLING_STUB_VERIFICATION=false`; set `ANTHROPIC_API_KEY` to enable cloud AI.
- [ ] Fill the App Store **privacy "nutrition label"** to match `PrivacyInfo.xcprivacy`.
- [ ] Screenshots, description, keywords; TestFlight beta; device matrix pass (alarms / DST / timezones).
