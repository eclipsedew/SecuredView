# WarpVPN / SecuredView VPN

Premium cross-platform VPN built on Cloudflare WARP **MASQUE** (Connect-IP). Same tunnel tech on Android and Windows — survives WireGuard/UDP DPI blocks (GFW).

## Features

- Cloudflare WARP MASQUE (QUIC/HTTP3) — not plain WireGuard UDP
- Kill switch & auto-reconnect
- Connection statistics, modern dark UI
- Premium subscriptions (Paystack) + free trial tiers
- Cross-platform: Android, Windows, Linux

## Platforms

| Platform | Tunnel | Notes |
|----------|--------|--------|
| Android  | MASQUE via `usque.aar` in `VpnService` | Works behind GFW |
| Windows  | MASQUE via bundled `usque.exe` (TUN) | **Run as Administrator** (Wintun + routes); UAC manifest |
| Linux    | usque if bundled, else `warp-cli` | Prefer usque MASQUE |

### API base URL
All platforms call **`https://securedviewvpn.com`** first (`ApiService.publicDomainUrl`), then fall back to `https://securedview-api.onrender.com` and (last resort) `https://meridianglobal.site`.
Production is the full site + API on Render (custom domain → same FastAPI root). API stays under `/api`; marketing pages are public.

## Prerequisites

### Android
- Android Studio, Flutter SDK, Android SDK 26+

### Windows
1. No Cloudflare WARP client install required — `usque.exe` is bundled
2. App requests administrator (MASQUE TUN)
3. VC++ redistributable (`vc_redist.x64.exe` in the release zip)

### Linux (warp-cli fallback)
```bash
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg arch=amd64] https://pkg.cloudflareclient.com/ bookworm main' | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update && sudo apt install -y cloudflare-warp
sudo systemctl enable --now warp-svc
sudo warp-cli registration new
```

To build usque for Linux instead:
```bash
git clone https://github.com/justinwoo280/usque.git
git -C usque checkout db42acb8ee902daba516e765321aa279a57fc2db
cd usque && CGO_ENABLED=0 go build -o securedview/linux/bundled/usque .
```

## Build Instructions

```bash
cd WarpVPN
flutter pub get

# Android
flutter build apk --release

# Windows (CI builds usque.exe into windows/bundled/ then CMake installs it)
flutter build windows --release

# Linux
flutter build linux --release
```

CI (`.github/workflows/build.yml`) builds `usque.exe` from the pinned ref (`windows/bundled/usque.ref` / commit `db42acb…`), copies it into the Release folder, and packages `SecuredView-Windows.zip`.

## Architecture

```
lib/
├── main.dart
├── services/
│   ├── vpn_service.dart      # connect/disconnect + kill switch
│   ├── usque_service.dart    # desktop MASQUE (usque CLI)
│   ├── warp_service.dart     # Android MASQUE (MethodChannel)
│   └── api_service.dart      # public tunnel base URL
└── screens/ …
```

## How It Works

1. **Android / Windows**: usque registers a free WARP account once, then `usque run` opens a MASQUE TUN with auto-route
2. **Linux**: same usque path when the binary is present; otherwise `warp-cli`
3. Traffic rides Cloudflare’s Connect-IP (QUIC), which the GFW does not fingerprint like WireGuard UDP

## Disclaimer

Uses Cloudflare WARP. Not a guarantee of bypassing all restrictions. Use responsibly.

