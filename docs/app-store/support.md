# Look Support

Look is a self-hosted photo library app for iPhone and iPad. It requires a Look server that you run on a private network, usually through Tailscale. Look does not provide cloud photo hosting and does not scan your iPhone photo library.

## Contact Support

For questions, setup help, bug reports, or App Store review support, open a support request here:

**https://github.com/sladebot/look/issues**

If you prefer email support, add the support email address to this hosted page before submitting it as the App Store Support URL.

When requesting support, include:

- The Look app version
- Your iPhone or iPad model and iOS/iPadOS version
- The server URL format you are using, such as a Tailscale MagicDNS name or private `100.x.y.z` address
- Whether the server opens in Safari on the same device
- Any error message shown by Look

Do not send private API keys, passwords, full photo libraries, or sensitive photos in a support request. If a screenshot is helpful, remove or blur private server names, filenames, and personal content first.

## Quick Connection Check

If Look cannot connect, first open your Look server URL in Safari on the same iPhone or iPad.

If Safari cannot open the URL, fix Tailscale, the server process, the host firewall, or the server address before retrying in Look. If Safari can open the URL but Look cannot connect, check the API key and app settings.

## Requirements

- A running Look server
- Your iPhone or iPad connected to the same Tailscale network or trusted private network
- A reachable server URL, such as:
  - `http://machine.tailnet-name.ts.net:5678`
  - `http://100.x.y.z:5678`
- An API key if your Look server has `API_KEY` enabled

## Common Setup Steps

1. Start the Look server on your host machine.
2. Confirm the server is reachable from another device on your Tailscale network.
3. Open Look on iPhone or iPad.
4. Enter the server URL.
5. Enter the API key only if your server requires one.
6. Tap Test connection.

## Troubleshooting

If Look cannot connect:

- Confirm Tailscale is running on both devices.
- Confirm both devices are signed into the correct Tailscale network.
- Open the server URL in Safari on the same iPhone or iPad.
- Confirm the Look server is bound to a reachable private interface.
- Confirm port `5678` is allowed by the host firewall.
- If using an API key, confirm the key matches the server's `API_KEY`.

If photos or thumbnails do not appear:

- Confirm the server has imported the folder that contains your photos.
- Refresh the photo list in Look.
- Check that the server can read the photo files and create thumbnails.
- Try opening the same photo from the Look web UI on your private network.

If saving a photo to the device fails:

- Confirm iOS has granted Look permission to add photos to the Photos library.
- Try saving one photo at a time.
- Confirm the server can serve the original image or JPEG download.

## App Review Notes

Look is a client for a self-hosted server. It does not create public user accounts, provide developer-operated cloud photo storage, or scan the review device's local photo library.

For App Review, provide a reachable demo or test server URL and API key, if required, in App Store Connect review notes. Reviewers should enter the server URL in Look, then enter the API key only if the provided server requires one.

## Privacy

Look does not provide cloud photo hosting. Your photos stay on your self-hosted server unless you choose to save a photo to your device.

Read the privacy policy: [Look Privacy Policy](privacy-policy.md)
