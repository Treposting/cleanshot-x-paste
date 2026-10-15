# Signing releases (optional)

Marquee builds are signed **ad hoc** by default. They work, but macOS identifies an ad-hoc app by its exact binary. After every update it treats Marquee as a new app and asks for **Screen Recording** and **Accessibility** again.

Signing every release with one stable certificate fixes that. A self-signed certificate is enough; it doesn't need to come from Apple.

## Set it up once

1. Run (on a Mac or Linux, anywhere with `openssl`):
   ```sh
   ./scripts/create-signing-cert.sh
   ```
   This creates `marquee-signing.p12` and prints three values.
2. In GitHub, open **Settings → Secrets and variables → Actions → New repository secret** and add:

   | Secret | Value |
   |---|---|
   | `MACOS_SIGNING_IDENTITY` | The certificate name, `Marquee Code Signing` by default |
   | `MACOS_SIGNING_CERT_PASSWORD` | The password the script printed |
   | `MACOS_SIGNING_CERT_P12` | The long base64 text the script printed |

3. Keep `marquee-signing.p12` somewhere safe and private. If you lose it, users have to grant permissions once more when you switch to a new certificate.

The next run of **Actions → Release** signs the app with this certificate. A self-signed certificate isn't trusted by macOS, so the workflow signs by the certificate's SHA-1 hash, and it fails the release if the app still comes out ad-hoc signed. CI checks on every push that self-signed signing works.

## How it interacts with in-app updates

- The updater only installs an update whose code signature is valid.
- Once the installed app is signed with your certificate, it also requires every update to be signed with the **same** certificate. A tampered or foreign build is rejected.
- Moving from an ad-hoc build to the first certificate-signed build works normally. After that, users keep their permissions across updates.

## Notarization

Notarizing with an Apple Developer ID ($99/year) would also remove the "right-click → Open" step on first launch. It isn't set up yet.
