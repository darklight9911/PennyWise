# Releasing pennyWise on Google Play

What is ready in the repository, and the steps only the owner can do.

## Ready

- Production server files: `deploy/` (HTTPS, backups, see `deploy/README.md`).
- Privacy policy and account-deletion web pages: `deploy/site/`, served at
  `/privacy` and `/delete-account` on the API domain.
- In-app account deletion: Settings → Delete account (server erases rows
  and files).
- Release signing: Gradle reads `mobile/android/key.properties`; CI signs
  when the secrets below exist. Every build uploads the `.aab` as a CI
  artifact.

## Still needed before the first upload

1. **Email provider** (the API refuses `MAILER=log` in production).
2. **Domain** for the API and pages; fill the `[...]` placeholders in
   `deploy/site/*.html`.
3. **Firebase project** if push reminders should reach phones (until then
   they are only logged).

## 1. Upload key (once, keep it safe)

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Store the file and passwords in a password manager, **outside the
repository**. For local release builds create `mobile/android/key.properties`
(git-ignored):

```properties
storeFile=../upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

For CI, add repository secrets (GitHub → Settings → Secrets → Actions):
`ANDROID_KEYSTORE_BASE64` (output of `base64 -w0 upload-keystore.jks`),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
Turn on **Play App Signing** when creating the app: Google keeps the real
signing key; a lost upload key can then be reset.

## 2. Play Console

1. Developer account ($25 once). Check that "pennyWise" is free as a name.
2. Create the app: free, app (not game).
3. **App content**:
   - Privacy policy: `https://YOUR_DOMAIN/privacy`
   - Account deletion: in-app path *Settings → Delete account*, web link
     `https://YOUR_DOMAIN/delete-account`
   - Ads: **no ads**
   - Financial features: personal finance tracker / budgeting; no loans,
     no payments, no trading
   - Content rating questionnaire (utility app, no user-to-user content)
   - Target audience: 18+ (or 13+), not designed for children
4. **Data safety** (matches the privacy policy):

| Data type | Collected | Shared | Why | Optional |
|---|---|---|---|---|
| Email address | Yes | No | Account management | No |
| Name | Yes | No | Account management | Yes |
| User IDs (Google account ID) | Yes | No | Account management | Yes (Google sign-in only) |
| Financial info: other financial info (what the user enters) | Yes | No | App functionality | No |
| Photos (receipts) | Yes | No | App functionality | Yes |
| App activity: other actions (sign-ins, exports) | Yes | No | Security, fraud prevention | No |
| Device or other IDs (push token) | Yes | No | App functionality (reminders) | Yes |

   Data is encrypted in transit: **yes**. Users can request deletion:
   **yes**. Cloudflare and the host process data for us, which is not
   "sharing" under Play's definition. No crash or analytics SDK is in the
   app, so nothing is declared for those.
5. **Store listing**: icon 512×512, feature graphic 1024×500, at least 4
   phone screenshots, short (80 chars) and full description.
6. **Closed testing first** (new personal accounts must): at least 12
   testers opted in for 14 days. Upload the signed `.aab` from CI.
7. Then apply for production access and release.

## Each release

1. Raise `version:` in `mobile/pubspec.yaml` (`1.2.0+12`: the number after
   `+` must always grow).
2. Push to `main`; CI tests and builds the signed `.aab`.
3. Download the artifact (`app-release-aab`) and upload it in Play Console.
