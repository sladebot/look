# Look iOS Release Checklist

This checklist is the release owner workflow for a TestFlight or App Store candidate. It complements `ios/SETUP_TESTFLIGHT.md`, which documents signing secrets and upload automation.

## Before Building

- Confirm the release scope and known risks are written down.
- Confirm the Look server candidate is deployed on the intended tailnet host.
- Confirm the app's configured default server URL, visible examples, and QA server URL match the release environment.
- Confirm `ios/project.yml` and the generated Xcode project agree on bundle ID, team ID, marketing version, and build number.
- Confirm `ios/Look/Info.plist` and `ios/project.yml` have the same App Transport Security settings.
- Confirm no secrets are committed in source, docs, screenshots, or workflow logs.
- Confirm API key behavior has a test key available when the server runs with `API_KEY`.
- Confirm release notes call out server compatibility requirements and any migration expectations.

## Build and Upload

- Run the iOS unit test target locally or in CI.
- Build an archive with the same signing path used for release.
- Export the IPA with `ios/ExportOptions.plist`.
- Upload to TestFlight using the GitHub workflow or Xcode Organizer.
- Verify App Store Connect processing completes without missing compliance, encryption, privacy, or signing warnings.
- Install the processed TestFlight build on at least one physical iPhone before QA sign-off.

## Required QA Sign-off

- Complete every P0 row in `docs/release/ios-qa-matrix.md`.
- Complete P1 rows that touch changed areas in the release.
- Run at least one pass with API key disabled and one pass with API key enabled.
- Run at least one pass with the server unavailable and one pass with slow Tailscale.
- Run at least one pass on physical iPhone in Light appearance and one in Dark appearance.
- Run at least one compact screen-size pass and one large screen-size pass.
- Run huge-library coverage against 50,000+ photos when the release changes loading, search, thumbnails, caching, or sync.
- Document all accepted issues in the sign-off template from the QA matrix.

## Security and Privacy Review

- Review `docs/release/ios-tailnet-security.md` for any drift from current `Info.plist`.
- Confirm `NSAllowsArbitraryLoads` remains false.
- Confirm HTTP exceptions remain limited to local networking, the tailnet MagicDNS domain, and explicitly approved tailnet IPs.
- Confirm the app does not log the API key, server key, full private file paths in user-facing diagnostics, or raw EXIF beyond intended UI.
- Confirm the API key is stored in Keychain and not in `UserDefaults` except for one-time legacy migration.
- Confirm destructive server actions are intentionally triggered and visibly scoped, especially dedup merge/archive and tag merge.
- Confirm the release does not introduce public internet server assumptions; Look is designed for private tailnet access.

## App Store Connect Checks

- Confirm app name, bundle ID, category, screenshots, privacy nutrition labels, and support URL are current.
- Confirm the Photos permission usage text matches the feature: saving downloaded library photos to the user's Photos app.
- Confirm export compliance answers are still correct for an app using HTTPS-capable system networking plus private tailnet HTTP exceptions.
- Confirm TestFlight beta notes include:
  - Required Tailscale connection.
  - Expected server URL format.
  - Whether API key is required.
  - Known limitations for large libraries or slow networks.

## Release Decision

Ship only when:

- P0 QA is passing or every exception has explicit release-owner acceptance.
- Security posture has no unexplained drift from `docs/release/ios-tailnet-security.md`.
- The release build was installed from TestFlight on a physical iPhone.
- Rollback path is known: keep the previous TestFlight/App Store build available and keep the previous server deployment or database backup available.

## Post-release

- Monitor tester feedback for connection failures, unauthorized writes, huge-library hangs, thumbnail loading failures, and crashes after background/foreground cycles.
- Record any production-only issue as a new QA matrix row if it should become a future release gate.
- Archive the signed-off matrix with the release notes.

