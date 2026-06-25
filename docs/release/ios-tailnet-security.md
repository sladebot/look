# Look iOS Tailnet HTTP and Security Posture

Look iOS is built for a private Tailscale network, not for exposing the photo server directly to the public internet. The current app transport posture allows plain HTTP only for the private-network routes needed to reach the self-hosted Look server.

## Current App Transport Security Configuration

As of this document, `ios/Look/Info.plist` and `ios/project.yml` declare:

| Setting | Current Value | Meaning |
| --- | --- | --- |
| `NSAllowsArbitraryLoads` | `false` | The app does not allow unrestricted insecure HTTP loads. |
| `NSAllowsLocalNetworking` | `true` | HTTP to local/private network hosts is permitted. |
| `NSExceptionDomains.ts.net.NSExceptionAllowsInsecureHTTPLoads` | `true` | HTTP is permitted for Tailscale MagicDNS names. |
| `NSExceptionDomains.ts.net.NSIncludesSubdomains` | `true` | The `ts.net` exception applies to MagicDNS subdomains such as `machine.tailnet.ts.net`. |
| `NSExceptionDomains.100.86.254.112.NSExceptionAllowsInsecureHTTPLoads` | `true` | HTTP is permitted for the explicitly listed tailnet IP. |

Any change to these settings must update this document and rerun the QA security checks in `docs/release/ios-release-checklist.md`.

## Why HTTP Is Currently Allowed

The Look server is designed to run on a private tailnet and currently serves the FastAPI app over HTTP on port 5678. Tailscale provides private network reachability and encrypted transport between tailnet nodes, while the app uses HTTP at the application layer to reach the local service.

This means the acceptable deployment assumption is:

- iPhone is signed into the trusted tailnet.
- Look server is reachable only on the private tailnet or trusted local network.
- The server is not published directly to the open internet.
- Optional server `API_KEY` is enabled when write access should be constrained beyond tailnet membership.

## Boundaries and Non-goals

- Tailnet membership is treated as the primary network boundary.
- The app should not require public DNS or a public TLS certificate for the default private deployment.
- The app should not broaden ATS to arbitrary HTTP hosts.
- The app should not silently fall back to LAN, localhost, or hardcoded alternate hosts after the user has configured a server URL.
- The app should not store the API key in plaintext app preferences; the current client stores it in Keychain and migrates legacy `UserDefaults` values.

## Risk Register

| Risk | Current Mitigation | Release Check |
| --- | --- | --- |
| Server exposed outside tailnet | Deployment guidance assumes Tailscale/private network only. | Confirm firewall/router/public DNS do not expose port 5678. |
| HTTP exception accidentally broadened | `NSAllowsArbitraryLoads` is false and exceptions are scoped. | Diff `Info.plist` and `project.yml` before release. |
| Unauthorized writes on shared tailnet | Server can set `API_KEY`; iOS sends `X-API-Key` when configured. | Run QA with API key enabled, valid key, missing key, and wrong key. |
| API key leakage | Keychain storage is used by the iOS client. | Check logs, screenshots, crash reports, and UI do not expose the key. |
| Wrong server reached | User-configured URL is authoritative. | QA wrong URL and reconnect flows; verify no unexpected fallback host. |
| Private metadata exposure | Photos, EXIF, GPS, tags, and paths are sensitive library data. | Avoid public server deployment; review screenshots and release notes. |

## Recommended Production Defaults

- Prefer MagicDNS URLs such as `http://machine.tailnet.ts.net:5678` over hardcoded tailnet IPs for tester instructions.
- Enable `API_KEY` for any tailnet with multiple users or devices that should not all have write access.
- Restrict the Look server process to the tailnet interface or trusted LAN where practical.
- Keep the Tailscale ACL for the Look server narrow: only intended users/devices should reach port 5678.
- Keep the server and iOS app versions paired in release notes when API behavior changes.
- Use HTTPS in front of the server only if deployment moves beyond private tailnet assumptions; do not broaden ATS as a shortcut.

## Release Verification

Before shipping:

- Confirm the app connects to the intended MagicDNS or approved 100.x address.
- Confirm a typo in the server URL fails visibly instead of connecting elsewhere.
- Confirm writes fail with `401 Unauthorized` or equivalent UI when API key is required and absent.
- Confirm writes succeed when the correct API key is stored.
- Confirm server unavailable, slow tailnet, and tailnet disconnected states are user-recoverable.
- Confirm no screenshots, logs, analytics, or feedback payloads include API keys or unnecessary private EXIF/path data.

