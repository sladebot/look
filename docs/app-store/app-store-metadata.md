# Look App Store Metadata

Use this as the paste-ready submission packet for App Store Connect.

## Required Product Page Fields

### Primary Category

Photo & Video

### Secondary Category

Utilities

### Promotional Text

Browse your self-hosted photo library from your iPhone or iPad over your private Tailnet.

### Description

Look is a private photo library app for people who run their own photo server.

Connect your iPhone or iPad to a Look server on your Tailscale network, then browse, search, organize, and inspect your photo archive without moving your library into a public cloud service.

Look is built for private, self-hosted libraries:

- Browse a fast, full-screen photo grid
- Search by filename, tag, camera metadata, and path
- View albums and smart collections from your server
- Open photo details with EXIF, dimensions, file type, tags, and location metadata
- Long-press photos to enter multi-select
- Save selected photos back to your device when you choose
- Connect with a Tailscale MagicDNS name or a private 100.x Tailnet address
- Use an optional API key when your server requires one

Look does not provide cloud photo hosting. You need a running Look server that your device can reach over Tailscale or another trusted private network.

### Keywords

photos,self-hosted,tailscale,tailnet,gallery,albums,exif,tags,private,library

### Support URL

Use the hosted support page URL.

Recommended URL after hosting:

https://YOUR_DOMAIN/look/support

### Marketing URL

Optional.

Recommended URL after hosting:

https://YOUR_DOMAIN/look

### Privacy Policy URL

Use the hosted privacy policy URL.

Recommended URL after hosting:

https://YOUR_DOMAIN/look/privacy

### Version

1.0

### Copyright

2026 Souranil Sen

## App Review Information

### Sign-In Information

Sign-in required: No

Look connects to a self-hosted server on a private Tailnet. The app itself does not use an account sign-in flow. If the review build points at a test server with an API key enabled, provide the server URL and API key in App Review Notes.

### Contact Information

Use the developer contact information for Souranil Sen.

Required fields in App Store Connect:

- First name: Souranil
- Last name: Sen
- Phone: YOUR_PHONE_NUMBER
- Email: YOUR_REVIEW_CONTACT_EMAIL

### Notes

Look is designed for self-hosted photo libraries on a private Tailscale network.

For review, please use the included demo/test server details if provided with the build. The app accepts either a Tailscale MagicDNS URL, such as `http://machine.tailnet.ts.net:5678`, or a private Tailscale `100.x.y.z` address.

The app does not create a public account and does not include cloud-hosted photo storage. If an API key is required by the configured test server, enter the API key in the Settings screen after entering the server URL.

## App Privacy

If the submitted app has no third-party analytics, ads, telemetry, crash SDK, or developer-operated cloud backend, select:

Data Not Collected

Rationale:

- Photos and metadata are loaded from the user's self-hosted Look server.
- The developer does not receive, collect, sell, track, or centrally process the user's photos, EXIF data, server URL, API key, or library metadata.
- The optional API key is stored locally in the iOS Keychain.
- Downloaded photos are saved to the user's Photos library only when the user explicitly chooses to save them.

If analytics, crash reporting, hosted sync, support uploads, or any developer-operated service is added later, update the App Privacy answers before submission.

## Age Rating

Recommended target rating: 4+

Suggested answers for the required age-rating questionnaire:

- Cartoon or Fantasy Violence: None
- Realistic Violence: None
- Prolonged Graphic or Sadistic Realistic Violence: None
- Profanity or Crude Humor: None
- Mature or Suggestive Themes: None
- Horror/Fear Themes: None
- Medical/Treatment Information: None
- Alcohol, Tobacco, or Drug Use or References: None
- Simulated Gambling: None
- Sexual Content or Nudity: None
- Graphic Sexual Content and Nudity: None
- Contests: No
- Gambling: No
- Loot Boxes: No
- Unrestricted Web Access: No
- Kids Category: No

Note: Look displays the user's private photo library from their own server. It does not provide public feeds, social sharing, or unrestricted web browsing.

## Build

This cannot be generated in metadata. Upload a signed build through Xcode, Transporter, or the existing CI/TestFlight workflow, then choose it under Build > Add Build.
