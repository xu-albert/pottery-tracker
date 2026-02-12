# Pottery Tracker — Cost Analysis

**Date:** February 2026
**Scope:** Monetary costs only (no labor/time estimates)

---

## 1. One-Time Launch Costs

| Item | Cost | Notes |
|------|------|-------|
| Google Play Developer Account | $25 | One-time registration fee |
| **Total one-time** | **$25** | |

---

## 2. Recurring Annual Costs (Fixed)

| Item | Cost/Year | Notes |
|------|-----------|-------|
| Apple Developer Program | $99 | Required to publish on the App Store; auto-renewing |
| **Total fixed annual** | **$99** | |

---

## 3. Infrastructure Costs (Variable — Firebase)

The app uses Firebase for auth, Firestore (metadata), and Cloud Storage (photos). Costs depend entirely on user scale.

### 3.1 Firebase Free Tier Allowances (Spark / Blaze no-cost quota)

| Resource | Free Allowance |
|----------|----------------|
| Authentication | 50,000 MAUs (email/social login) |
| Firestore reads | 50,000/day |
| Firestore writes | 20,000/day |
| Firestore deletes | 20,000/day |
| Firestore storage | 1 GB |
| Cloud Storage (stored) | 1 GB |
| Cloud Storage (download) | 10 GB/month |

**Important (Feb 2026 change):** Projects using a `*.appspot.com` default Cloud Storage bucket must be on the Blaze (pay-as-you-go) plan to retain access. The Blaze plan still includes the same free quotas above — you only pay for usage beyond them.

### 3.2 Blaze Plan Unit Prices (Beyond Free Tier)

| Resource | Price |
|----------|-------|
| Firestore reads | $0.18 / 100K reads |
| Firestore writes | $0.18 / 100K writes |
| Firestore deletes | $0.02 / 100K deletes |
| Firestore storage | $0.108 / GB (first tier) |
| Cloud Storage (stored) | $0.026 / GB / month |
| Cloud Storage (download) | $0.15 / GB |
| Authentication | Free up to 50K MAUs; ~$0.0055/MAU beyond |

### 3.3 Cost Scenarios by User Scale

Assumptions per active user:
- ~50 pieces, ~3 photos each = ~150 photos
- Each photo ~150 KB compressed = ~22 MB cloud storage per user
- ~20 Firestore reads/day per active user (album loads, detail views)
- ~5 Firestore writes/day per active user (creates, edits)
- ~10 MB cloud storage download/month per active user

#### Scenario A: Hobby / Small Launch (≤100 DAU)

| Resource | Usage | Free Tier Covers? | Monthly Cost |
|----------|-------|-------------------|-------------|
| Authentication | < 500 MAUs | Yes | $0 |
| Firestore reads | ~2,000/day | Yes (50K free) | $0 |
| Firestore writes | ~500/day | Yes (20K free) | $0 |
| Firestore storage | ~11 GB total | ~10 GB over free | ~$1.08 |
| Cloud Storage (stored) | ~11 GB | ~10 GB over free | ~$0.26 |
| Cloud Storage (download) | ~1 GB/month | Yes (10 GB free) | $0 |
| **Monthly Firebase total** | | | **~$1.34** |
| **Annual Firebase total** | | | **~$16** |

#### Scenario B: Growing App (~1,000 DAU)

| Resource | Usage | Monthly Cost |
|----------|-------|-------------|
| Authentication | ~5,000 MAUs | $0 (under 50K) |
| Firestore reads | ~20,000/day = 600K/month | ~$1.08 |
| Firestore writes | ~5,000/day = 150K/month | ~$0.27 |
| Firestore storage | ~110 GB | ~$11.77 |
| Cloud Storage (stored) | ~110 GB | ~$2.86 |
| Cloud Storage (download) | ~10 GB/month | $0 (within free) |
| **Monthly Firebase total** | | **~$16** |
| **Annual Firebase total** | | **~$192** |

#### Scenario C: Moderate Success (~10,000 DAU)

| Resource | Usage | Monthly Cost |
|----------|-------|-------------|
| Authentication | ~50,000 MAUs | $0 (at limit) |
| Firestore reads | ~200,000/day = 6M/month | ~$10.80 |
| Firestore writes | ~50,000/day = 1.5M/month | ~$2.70 |
| Firestore storage | ~1.1 TB | ~$118.80 |
| Cloud Storage (stored) | ~1.1 TB | ~$28.60 |
| Cloud Storage (download) | ~100 GB/month | ~$13.50 |
| **Monthly Firebase total** | | **~$174** |
| **Annual Firebase total** | | **~$2,090** |

---

## 4. App Store Commission (on Donations / Tips)

If the app includes a tip jar via in-app purchases:

| Platform | Commission Rate | Notes |
|----------|----------------|-------|
| Apple App Store | **15%** | Via App Store Small Business Program (< $1M revenue/year) |
| Google Play | **15%** | First $1M earned/year; 30% above that |

If using an external link (Ko-fi, Buy Me a Coffee) instead of IAP:
- **Ko-fi:** 0% platform fee (they take no cut; payment processor fees still apply ~2.9% + $0.30)
- **Buy Me a Coffee:** 5% platform fee + payment processor fees

---

## 5. Optional / Conditional Costs

| Item | Cost | When Needed |
|------|------|-------------|
| Custom domain (for privacy policy / support site) | ~$10–15/year | If you want a branded URL; free alternatives exist (GitHub Pages) |
| Privacy policy generator | $0–50 | Free generators exist; paid ones offer better legal coverage |
| App Store screenshots / promo art | $0 | Can be self-made; only a cost if outsourced |
| Push notifications (Firebase Cloud Messaging) | $0 | FCM is free; relevant for Phase 2 sync notifications |
| Firebase Crashlytics | $0 | Free crash reporting |
| Firebase Analytics | $0 | Free basic analytics |

---

## 6. Summary: Total Cost by Year

### Year 1

| Scenario | One-Time | Fixed Annual | Variable (Firebase) | **Total Year 1** |
|----------|----------|-------------|--------------------|-|
| A: ≤100 DAU | $25 | $99 | ~$16 | **~$140** |
| B: ~1,000 DAU | $25 | $99 | ~$192 | **~$316** |
| C: ~10,000 DAU | $25 | $99 | ~$2,090 | **~$2,214** |

### Year 2+

| Scenario | Fixed Annual | Variable (Firebase) | **Total/Year** |
|----------|-------------|--------------------|-|
| A: ≤100 DAU | $99 | ~$16 | **~$115** |
| B: ~1,000 DAU | $99 | ~$192 | **~$291** |
| C: ~10,000 DAU | $99 | ~$2,090 | **~$2,189** |

---

## 7. Key Takeaways

1. **Launch is cheap.** For a small hobby app, total Year 1 cost is roughly **$140** — the Apple Developer fee is the single largest expense.
2. **Firebase free tier is generous.** With ≤100 daily active users, nearly everything fits within the no-cost quota. The main cost driver is stored photos in Cloud Storage and Firestore.
3. **Storage is the scaling bottleneck.** Photo-heavy apps accumulate cloud storage quickly. At 10K DAU with ~150 photos each, you're looking at ~1 TB of stored images — the biggest line item.
4. **Tip jar commissions are modest.** The 15% Small Business Program rate on both stores keeps donation-based revenue viable. External platforms like Ko-fi avoid app store commissions entirely but require directing users out of the app.
5. **No ongoing server costs.** Firebase is fully managed — there are no VMs, containers, or servers to maintain. Costs scale linearly with usage.

---

## Sources

- [Apple Developer Program — Membership](https://developer.apple.com/programs/whats-included/)
- [Google Play Console — Registration](https://support.google.com/googleplay/android-developer/answer/6112435)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Firebase Auth Pricing & Limits](https://firebase.google.com/docs/auth/limits)
- [Cloud Firestore Billing](https://firebase.google.com/docs/firestore/pricing)
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Cloud Storage Pricing Changes (Feb 2026)](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
