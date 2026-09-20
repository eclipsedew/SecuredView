# WarpVPN - Free Cross-Platform VPN

A free, beautiful VPN app powered by Cloudflare WARP. No subscription needed.

## Features

- Free & unlimited VPN
- AES-256 encryption
- No logs policy
- Cross-platform (Android, Linux, Windows)
- Beautiful modern UI with animations
- Custom server support
- Kill switch & auto-connect
- Connection statistics

## Platforms

| Platform | Status |
|----------|--------|
| Android  | Full VPN service with kill switch |
| Linux    | Uses `warp-cli` (install Cloudflare WARP) |
| Windows  | Uses `warp-cli` (install Cloudflare WARP) |

## Prerequisites

### Android
- Android Studio
- Flutter SDK
- Android SDK 24+

### Linux
```bash
# Install Flutter
sudo snap install flutter --classic

# Install Cloudflare WARP
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg arch=amd64] https://pkg.cloudflareclient.com/ bookworm main' | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update && sudo apt install -y cloudflare-warp
sudo systemctl enable --now warp-svc
sudo warp-cli registration new
```

### Windows
1. Download Cloudflare WARP from https://1.1.1.1
2. Install and register

## Build Instructions

```bash
# Clone / navigate to project
cd WarpVPN

# Get dependencies
flutter pub get

# Run on connected device
flutter run -d <device_id>

# Build Android APK
flutter build apk --release

# Build Linux
flutter build linux --release

# Build Windows
flutter build windows --release
```

## Architecture

```
lib/
├── main.dart                    # App entry point
├── theme/
│   └── app_theme.dart           # Dark theme with gradients
├── models/
│   └── vpn_models.dart          # Server, stats, state models
├── services/
│   └── vpn_service.dart         # VPN connection logic
├── screens/
│   ├── home_screen.dart         # Main connect screen
│   ├── servers_screen.dart      # Server list & management
│   └── settings_screen.dart     # App settings
└── widgets/
    ├── connection_button.dart   # Animated power button
    └── stats_card.dart          # Connection statistics
```

## How It Works

1. **Android**: Uses Android's `VpnService` API to create a local VPN tunnel
2. **Linux/Windows**: Wraps `warp-cli` to manage Cloudflare WARP connection
3. All traffic is encrypted with AES-256 through Cloudflare's global network

## Disclaimer

This app uses Cloudflare WARP, a free encrypted DNS and traffic routing service. It does not guarantee bypassing all network restrictions. Use responsibly.
