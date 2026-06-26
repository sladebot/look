# Look Support

Look is a self-hosted photo library app for iPhone and iPad. It connects to a Look server that you run on a private network, usually through Tailscale.

## Requirements

- A running Look server
- Your iPhone or iPad connected to the same Tailnet or trusted private network
- A reachable server URL, such as:
  - `http://machine.tailnet-name.ts.net:5678`
  - `http://100.x.y.z:5678`
- An API key if your Look server has `API_KEY` enabled

## Common Setup Steps

1. Start the Look server on your host machine.
2. Confirm the server is reachable from another device on your Tailnet.
3. Open Look on iPhone or iPad.
4. Enter the server URL.
5. Enter the API key only if your server requires one.
6. Tap Test connection.

## Troubleshooting

If Look cannot connect:

- Confirm Tailscale is running on both devices.
- Confirm both devices are signed into the correct Tailnet.
- Open the server URL in Safari on the same iPhone or iPad.
- Confirm the Look server is bound to a reachable private interface.
- Confirm port `5678` is allowed by the host firewall.
- If using an API key, confirm the key matches the server's `API_KEY`.

## Privacy

Look does not provide cloud photo hosting. Your photos stay on your self-hosted server unless you choose to save a photo to your device.

## Contact

For support, contact:

YOUR_SUPPORT_EMAIL
