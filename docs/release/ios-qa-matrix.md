# Look iOS Production QA Matrix

Use this matrix as the release gate for TestFlight and production submissions. Every release candidate should run the P0 and P1 coverage before upload; P2 coverage can be sampled unless the changed area touches that flow.

## Test Environments

| Environment | Required Coverage |
| --- | --- |
| Physical iPhone | At least one real iPhone on cellular plus Tailscale, and one real iPhone on Wi-Fi plus Tailscale. Simulator-only sign-off is not acceptable. |
| iOS versions | Current public iOS release and the oldest supported deployment target available to QA. The app target currently declares iOS 17.0+. |
| Server | Look server on the private tailnet at `http://studio.taila3f2b.ts.net:5678` or the release candidate's configured MagicDNS host. |
| API key modes | One run with `API_KEY` unset and one run with `API_KEY` set on the server. |
| Library sizes | Smoke library under 500 photos, standard library around 5,000 photos, and huge library at 50,000+ photos where available. |
| Network profiles | Healthy tailnet, slow tailnet, tailnet disconnected, and server process stopped. |

Record device model, iOS version, server URL, server commit/build, app build number, library size, API key mode, and network profile for each run.

## P0 Release Gates

| Area | Setup | Steps | Expected Result |
| --- | --- | --- | --- |
| Physical iPhone first launch | Install fresh build on a physical iPhone with Tailscale connected. | Launch app, enter MagicDNS or 100.x server URL, tap Test Connection. | Connection succeeds, saved URL is used, library tabs unlock, no fallback to an unexpected host. |
| Physical iPhone reconnect | Kill and relaunch the app after a successful connection. | Relaunch from home screen, wait for automatic health check. | App uses the saved server URL, remains connected, and does not require re-entry of settings. |
| API key disabled | Server has no `API_KEY`. | Leave API key field blank, test connection, browse photos, create and delete a temporary album. | Read and write actions succeed without prompting for a key. |
| API key enabled: valid key | Server has `API_KEY` set. | Enter the release test key, test connection, create album, add photo to album, add tag, remove tag, delete album. | All writes succeed; key persists through relaunch; no key is shown in plaintext after leaving the field. |
| API key enabled: missing or wrong key | Server has `API_KEY` set. | Clear or enter wrong key, then attempt a write action such as create album or add tag. | App shows an unauthorized/error state, does not claim success, and remains usable for correcting settings. |
| Server unavailable on launch | Stop `uvicorn` or block the server host. | Launch app with previously saved server URL. | App shows disconnected/server unavailable state, does not hang, and Settings remains reachable. |
| Server unavailable during browsing | Start connected, then stop server while viewing Photos. | Pull to refresh, open Settings, test connection. | App surfaces failure, keeps existing UI responsive, and recovers after server restart and retest. |
| Huge library initial load | Server has 50,000+ photos and generated thumbnails where possible. | Connect, open Photos, scroll through at least 1,000 items, open detail and full-screen image. | Pagination continues without duplicate rows or runaway memory; thumbnails load progressively; detail/full-screen remains responsive. |
| Huge library search | Server has 50,000+ photos with mixed filenames/tags/camera metadata. | Search by filename fragment, tag, camera text, and path-like text. | Search completes without freezing the UI; results match server expectations; clearing search returns to full library. |
| Background/foreground while idle | Connected app is on Photos tab. | Send app to background for 1 minute, foreground it, switch tabs. | App resumes cleanly, no stale blocking spinner, no crash, connection state remains accurate. |
| Background/foreground during sync | Start Sync and Import Now on a library with import work pending. | Background during progress, wait 30 seconds, foreground. | Sync state is coherent, polling resumes or final state is shown, app remains interactive. |
| Slow Tailscale browse | Use Network Link Conditioner, router throttling, or a constrained tailnet route. | Browse Photos, open detail, refresh, and search. | Loading states appear; failures are recoverable; no view blocks indefinitely. |
| Dark and light appearance | Test on physical iPhone. | Run Photos, Library, Search, Settings, photo detail, and modal sheets in Light and Dark appearances. | Text contrast is readable, controls remain visible, system bars are legible, and image content is not obscured. |
| Supported screen sizes | Test at least compact, standard, and large physical iPhone classes. | Verify iPhone SE-size, standard iPhone, and Pro Max-size layouts; include portrait and landscape where supported. | No clipped controls, overlapping text, unreachable buttons, broken grids, or unsafe-area regressions. |

## P1 Functional Matrix

| Area | Setup | Steps | Expected Result |
| --- | --- | --- | --- |
| Library pagination | Standard or huge library. | Scroll Photos until multiple pages load; return to top; pull to refresh. | Items remain unique, total count is stable, and refresh resets pagination correctly. |
| Thumbnail cache | Browse several hundred thumbnails. | Open Settings, clear thumbnail cache, return to Photos. | Cache clear does not crash; thumbnails reload normally. |
| Photo detail | Use photos with EXIF, GPS, tags, and RAW originals where possible. | Open detail, inspect metadata, save JPEG, export RAW if supported. | Metadata renders; save/export success or permission failure is correctly reported. |
| Photo library permission | Fresh install with no Photos permission decision. | Save JPEG from detail, respond to iOS permission prompt, repeat after denied and allowed states. | Permission prompt appears with correct purpose string; denied state does not crash; allowed state saves. |
| Albums | Connected app with write access. | Create album, add one photo, remove photo, delete album. | Counts update; photos are not deleted when album is deleted. |
| Smart albums | Server has smart collections enabled. | Create a simple rule, view smart album, run Evaluate, delete it. | Rule is saved, detail loads matched photos, evaluation result is visible or failure is clear. |
| Tags | Photo with existing tags and suggestions. | Add tag, remove tag, auto-tag from EXIF, inspect tag history. | Tag list updates; failures are visible; tag history reflects changes when enabled. |
| Tag cleanup | Server has similar/duplicate tags. | Open Settings, Tag Cleanup, merge a safe test pair. | Merge completes and counts update; wrong-key/API failures do not claim success. |
| Duplicates | Server has dedup enabled and a safe duplicate set. | Open Duplicates, run scan, inspect merge/archive action with test data only. | Scan result is understandable; destructive action requires intentional confirmation and does not affect unrelated photos. |
| Watch directories | Server has write access to watch-list endpoints. | Open Watch Directories, add a test directory, remove it. | List updates; invalid paths fail clearly. |
| Server feature toggles | API key valid if required. | Toggle Smart Albums, Deduplication, Tag History, Auto-tag GPS, Auto-tag Camera. | Toggle state is persisted on server and reflected after refresh/relaunch. |
| App relaunch state | Connected and populated app. | Force quit, relaunch, switch across all tabs. | Saved connection and API key state are preserved; no blank permanent loading state. |

## P2 Exploratory Coverage

| Area | Prompts |
| --- | --- |
| Large text accessibility | Test larger Dynamic Type settings for Settings, cards, modal sheets, and detail metadata. |
| VoiceOver | Verify tab labels, primary buttons, photo cards, Settings fields, destructive actions, and error banners. |
| Rotation | Check portrait and landscape transitions on Photos, detail, full-screen image, and Settings. |
| Interrupted network | Toggle Tailscale off/on while a thumbnail grid is loading and while detail image is loading. |
| Mixed media | Include JPEG, PNG, HEIC, RAW with sidecar JPEG, missing EXIF, malformed EXIF, GPS/no-GPS samples. |
| Long strings | Test long filenames, long tag names, long album names, and long server URLs. |

## Network Fault Recipes

| Scenario | How to Simulate | Notes |
| --- | --- | --- |
| Slow Tailscale | Enable Network Link Conditioner on the iPhone or route through a constrained network. | Prefer high latency plus low bandwidth; capture the profile used in notes. |
| Tailnet disconnected | Stop Tailscale on the iPhone or sign out temporarily. | Verify error copy does not imply the server is misconfigured. |
| Server unavailable | Stop the Look server process or block port 5678 on the host. | Confirm recovery after restarting the server. |
| Wrong server URL | Enter an unreachable 100.x address or typo in MagicDNS host. | Confirm the app does not silently connect to another server. |
| API unauthorized | Set server `API_KEY`, clear the app key, and attempt writes. | Reads may still work depending on endpoint; writes must fail clearly. |

## Sign-off Template

```
Release candidate:
App build:
Server commit/build:
Server URL:
Library size:
API key mode:
Devices and iOS versions:
Network profiles tested:
P0 result:
P1 result:
Known issues accepted:
Tester:
Date:
```

