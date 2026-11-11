# IAPGate

A native macOS app for discovering Google Cloud Compute Engine
instances you can access and connecting to them through
Identity-Aware Proxy (IAP) — SSH for Linux, RDP for Windows — without
living in the terminal.

IAPGate runs entirely on your Mac. It has no vendor backend, no
mandatory account, and no telemetry. Authentication and connections use
Google's official mechanisms and your existing Google Cloud
permissions.

---

## Install IAPGate (for everyone)

You don't need to compile anything or touch the Terminal. Just download
the app and install the one tool it relies on.

### Step 1 — Install the Google Cloud CLI (gcloud)

IAPGate uses Google's official **gcloud** tool under the hood to sign in
and to open the secure tunnels. Install it once:

- Easiest: download Google's installer and follow it —
  <https://cloud.google.com/sdk/docs/install>
- Or, if you use [Homebrew](https://brew.sh):
  `brew install --cask google-cloud-sdk`

### Step 2 — Download and install IAPGate

1. Go to the [**Releases** page](https://github.com/serargi/IAPGate/releases).
2. Download the latest **`IAPGate.zip`**.
3. Double-click the zip to unzip it. You'll get **`IAPGate.app`**.
4. Drag `IAPGate.app` into your **Applications** folder.

### Step 3 — Open it the first time (important)

IAPGate is not yet signed with a paid Apple certificate, so the first
time you open it macOS blocks it with a message like *"Apple could not
verify IAPGate is free of malware."* This is expected. You only have to
clear it once.

On **macOS Sequoia (15) and later**, the old right-click → Open trick
no longer works. Do this instead:

1. Double-click `IAPGate.app`. When the warning appears, click
   **Done** / **OK** (do **not** click "Move to Trash").
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section. You'll see a line like
   *"IAPGate was blocked to protect your Mac."* Click
   **Open Anyway**.
4. Confirm with your password / Touch ID, then click **Open** in the
   final dialog.

After this, IAPGate opens normally like any other app.

**Faster alternative (Terminal).** If you're comfortable with the
Terminal, you can clear the download quarantine in one command, then
just double-click the app:

```sh
xattr -dr com.apple.quarantine /Applications/IAPGate.app
```

> On **macOS 14 (Sonoma)** only, the older method also works:
> right-click (or Control-click) `IAPGate.app` → **Open** → **Open**.

Either way, you only do this **once**. After it's cleared, IAPGate opens
with a normal double-click. You'd only repeat it if you download the app
again (for example a new version from Releases), since a fresh download
is quarantined again.

### Step 4 — Sign in and connect

- Click **"Sign in with Google"**. Your browser opens for the normal
  Google sign-in, then you're back in the app.
- Pick an organization, find a VM, and **double-click it** to connect:
  - **Linux** VMs open an SSH session in the app.
  - **Windows** VMs open your RDP client (see below).

### For Windows VMs (RDP): install an RDP client

To connect to Windows machines you also need a Remote Desktop app.
Install **Windows App** (formerly *Microsoft Remote Desktop*) from the
Mac App Store:
<https://apps.apple.com/app/windows-app/id1295203466>

IAPGate opens it automatically when you connect to a Windows VM. For the
username and password, use the **"Generate Windows credentials"** option
(right-click the VM) if you don't already have them.

> If IAPGate says gcloud isn't found, finish Step 1 and reopen the app.

---

## Features

- Sign in with your Google account via gcloud; the session persists
  across launches and is managed entirely by gcloud (IAPGate stores no
  credentials of its own).
- Browse your real GCP hierarchy: pick an organization, then expand
  folders and subfolders down to projects and their VMs. Search filters
  the tree without flattening it.
- Favorite folders and projects for quick access (favorited folders
  stay fully navigable).
- VM list shows name, zone, OS (Linux/Windows), status, and IPs.
- Connect over IAP with a double-click, or right-click for a menu:
  - **SSH** for Linux VMs, in an embedded terminal.
  - **RDP** for Windows VMs, via your system RDP client.
  - **Connect on a custom port** when a service listens off the
    standard port.
- Generate/reset Windows credentials for a VM (with an explicit
  confirmation, since it modifies the instance).

## Requirements

- macOS 14 or later (Apple Silicon).
- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install)
  installed. IAPGate uses it for sign-in and to establish IAP tunnels.
- A Google account with access to the Google Cloud resources you want
  to reach, and the relevant IAM permissions (resource viewing and
  `roles/iap.tunnelResourceAccessor` for connecting).
- For Windows VMs only: an RDP client — **Windows App** (formerly
  Microsoft Remote Desktop) from the Mac App Store.

No OAuth client, client secret, or other configuration is required:
sign-in is delegated to gcloud.

## For developers (build from source)

Prerequisites: macOS 14+, and Xcode (or at least the Command Line
Tools: `xcode-select --install`). Also gcloud, as above.

```sh
git clone https://github.com/serargi/IAPGate.git
cd IAPGate
swift build                   # compile all targets
swift run CloudGateTests      # run the test suite
./scripts/make-app.sh release # package build/IAPGate.app
open build/IAPGate.app
```

`make-app.sh release` produces an optimized build and a distributable
`build/IAPGate.zip`; `debug` compiles faster. Full Xcode is needed for
the app bundle; the library modules and tests build with the Command
Line Tools alone. For cutting and (optionally) signing/notarizing a
release, see [`docs/RELEASE.md`](docs/RELEASE.md).

### How sign-in works

Clicking **"Sign in with Google"** runs `gcloud auth login`, which opens
the browser for the standard Google sign-in. gcloud stores and refreshes
the session; IAPGate stores no credentials of its own. If an active
gcloud session already exists, the app signs you in automatically on
launch. Signing out runs `gcloud auth revoke`.

## Security

- IAPGate stores no credentials of its own: the Google session lives in
  gcloud's own store (`~/.config/gcloud`), managed and refreshed by
  gcloud. Access tokens are requested on demand and only cached briefly
  in memory.
- Preferences and favorites (non-secret) live in UserDefaults.
- No telemetry, no analytics, no vendor backend.
- IAP tunnels bind to loopback only; sessions are torn down when a tab
  is closed, on sign-out, and on quit.
- Logs are redacted; tokens and passwords are never written to disk or
  logs.

See [`docs/SECURITY.md`](docs/SECURITY.md) and
[`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md).

## How it works

- **Authentication** is delegated to gcloud: sign-in runs
  `gcloud auth login`, and API calls get a token from
  `gcloud auth print-access-token`.
- **Discovery** uses the Cloud Resource Manager and Compute Engine
  REST APIs with that token.
- **IAP connectivity** delegates to
  `gcloud compute ssh --tunnel-through-iap` and
  `gcloud compute start-iap-tunnel`, which handle key propagation,
  username resolution, and the tunnel. A direct WebSocket implementation
  of the IAP relay protocol is also included and tested, as the path to
  a future gcloud-free mode. See [`docs/IAP_TRANSPORT.md`](docs/IAP_TRANSPORT.md).

## Known limitations

- The app is not yet signed/notarized, so macOS warns about an
  unidentified developer. Developer ID signing + notarization will
  remove this.
- Authentication and SSH/RDP depend on an installed `gcloud`. If the
  gcloud session expires, sign in again from the app.
- In projects without OS Login, connecting publishes your SSH key to
  project metadata (a Google-audited action). Enabling OS Login avoids
  this.
- The embedded terminal is a basic emulator; full-screen TUIs (vim,
  htop) are out of scope.

More detail in [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md).

## Project layout

```
Sources/
  CloudGateCore/   models, error model, redaction, preferences
  Diagnostics/     redacting structured logger
  Auth/            gcloud-based sign-in, access-token provider, session
  Discovery/       Resource Manager + Compute clients, hierarchy, favorites
  Transport/       IAP relay (WebSocket) + gcloud-based connection manager
  IAPGateApp/      SwiftUI app
  TestKit/         minimal test harness
  CloudGateTests/  test suites
docs/              architecture, security, planning
```

## Acknowledgements

Studied as functional references (no code, branding, or assets reused):
[GoogleCloudPlatform/iap-desktop](https://github.com/GoogleCloudPlatform/iap-desktop)
and [cedws/iapc](https://github.com/cedws/iapc). See
[`docs/PRODUCT_RESEARCH.md`](docs/PRODUCT_RESEARCH.md).

Built with vibe coding: an AI coding agent wrote most of the code,
paired with a human directing the design, reviewing the changes, and
testing against real Google Cloud infrastructure.

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
