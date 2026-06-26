# Look Privacy Policy

Effective date: 2026-06-26

Look is a self-hosted photo library client for iPhone and iPad. It is designed to connect to a Look server that you control on a private network, such as Tailscale.

## Summary

Look does not collect your personal data for the developer.

The app connects directly from your device to your configured Look server. Your photos, photo metadata, tags, albums, server URL, and optional API key stay on your device and your self-hosted server. They are not sent to a developer-operated cloud service by the app.

## Data You Provide

Look may store the following information locally on your device:

- The server URL you enter
- An optional API key, stored in the iOS Keychain
- Local app preferences, such as sync settings
- Cached thumbnails and responses used to make browsing faster

This information is used only to connect to and browse your configured Look server.

## Photos and Photo Metadata

Look displays photos and metadata served by your self-hosted Look server. This can include filenames, dimensions, file types, EXIF metadata, tags, albums, and location metadata if your server provides it. Look does not scan your iPhone photo library.

Look does not upload your photos or metadata to a developer-operated service.

## Photos Permission

If you choose to save a photo from Look to your device, iOS may ask for permission to add the image to your Photos library. Look uses that permission only to save photos you explicitly choose to save.

## Network Connections

Look connects to the server URL you configure. The app is intended for private networks such as Tailscale. If you use a Tailscale MagicDNS name or private Tailscale IP address, traffic is routed according to your Tailscale configuration.

## Analytics and Tracking

Look does not include advertising SDKs, third-party analytics SDKs, or cross-app tracking.

## Data Sharing

Look does not sell personal data and does not share your photos or library metadata with third parties.

## Security

The optional server API key is stored locally in the iOS Keychain. You are responsible for securing your self-hosted Look server, Tailscale membership, Tailscale ACLs, and any server-side API key configuration.

## Changes

This policy may be updated when Look's features change. The updated policy will be published with a new effective date.

## Contact

For privacy questions, contact:

YOUR_PRIVACY_CONTACT_EMAIL
