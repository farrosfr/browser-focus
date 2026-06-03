# browser-focus Allowlist Strategy

## Objective

Create a strict browser-only focus mode for technical learning and cybersecurity labs.

The browser should allow local/lab resources by default. Internet domains should be added explicitly in a private local allowlist. Everything else should be blocked by default.

This policy is intentionally browser-scoped. It should not interfere with:

- OpenVPN or TryHackMe VPN
- SSH
- Git
- VS Code
- Burp Suite
- Nmap, RustScan, Gobuster, ffuf
- curl, wget, terminal tools
- Localhost development
- System-level networking

## Model

The policy uses default-deny navigation:

```text
Block all URLs
Allow only approved URLs
```

Chrome and Edge:

```text
URLBlocklist = *
URLAllowlist = approved URL patterns
```

Firefox:

```text
WebsiteFilter.Block = <all_urls>
WebsiteFilter.Exceptions = approved URL patterns
```

## Supported Browsers

### Google Chrome

Implemented through Windows registry policy:

```text
HKLM:\SOFTWARE\Policies\Google\Chrome\URLBlocklist
HKLM:\SOFTWARE\Policies\Google\Chrome\URLAllowlist
```

Verify:

```text
chrome://policy
```

### Microsoft Edge

Implemented through Windows registry policy:

```text
HKLM:\SOFTWARE\Policies\Microsoft\Edge\URLBlocklist
HKLM:\SOFTWARE\Policies\Microsoft\Edge\URLAllowlist
```

Verify:

```text
edge://policy
```

### Mozilla Firefox

Implemented through machine-wide Mozilla policy:

```text
HKLM:\SOFTWARE\Policies\Mozilla\Firefox\WebsiteFilter\Block
HKLM:\SOFTWARE\Policies\Mozilla\Firefox\WebsiteFilter\Exceptions
```

Verify:

```text
about:policies
```

### Microsoft Store Firefox

Supported through the same Mozilla registry policy path:

```text
HKLM:\SOFTWARE\Policies\Mozilla\Firefox
```

The Microsoft Store package installs under `C:\Program Files\WindowsApps`, which is protected. Writing `policies.json` inside the app package is not a good maintenance path. Registry policy is the better implementation for Store Firefox.

### Firefox Developer Edition

Supported in two ways:

```text
HKLM:\SOFTWARE\Policies\Mozilla\Firefox
C:\Program Files\Firefox Developer Edition\distribution\policies.json
```

The script writes both. The registry policy covers Mozilla Firefox broadly, and `policies.json` makes the Developer Edition install explicit.

## Default Allowlist

The public default is intentionally neutral. It only includes local and private-network targets that are commonly needed for labs and local development.

```text
10.*
172.*
192.168.*
localhost
127.0.0.1
```

These entries are for browser access to internal lab web services and local development servers. They do not change VPN routing or system networking.

Internet sites such as learning platforms, search engines, AI assistants, code hosts, and professional networks should be added by each user in `allowlist.local.txt`.

## Usage

Run PowerShell as Administrator.

Enable:

```powershell
cd path\to\browser-focus
.\scripts\Enable-AllowlistOnlyBrowserPolicy.ps1 -RestartBrowsers
```

Short form:

```powershell
.\scripts\Enable-AllowlistOnlyBrowserPolicy.ps1 -r
```

`-RestartBrowsers` / `-r` immediately closes and reopens currently running Chrome, Edge, and Firefox processes so policy changes take effect.

Disable:

```powershell
cd path\to\browser-focus
.\scripts\Disable-AllowlistOnlyBrowserPolicy.ps1 -RestartBrowsers
```

Short form:

```powershell
.\scripts\Disable-AllowlistOnlyBrowserPolicy.ps1 -r
```

The enable script creates registry backups before writing policy:

```text
policy-backups/
```

## Private Custom Allowlist

Machine-specific or work-specific entries should live in:

```text
allowlist.local.txt
```

This file is ignored by Git so private domains and VPS ranges are not published.

Start from the example:

```powershell
Copy-Item .\allowlist.local.example.txt .\allowlist.local.txt
```

Supported entries:

```text
tryhackme.com
google.com
chatgpt.com
github.com
youtube.com
solar-nusantara.id
sonushub.id
217.15.160.*
203.0.113.10
*.example.com
https://example.com/specific/path/*
```

The enable script converts plain domains into both root and subdomain patterns:

```text
solar-nusantara.id
*.solar-nusantara.id
```

For IP prefixes, use an explicit wildcard:

```text
217.15.160.*
```

The script writes browser-specific formats. Chrome and Edge use Chromium URL filter syntax such as:

```text
google.com
https://server:8080/path
```

Firefox uses WebExtension-style match patterns such as:

```text
*://google.com/*
<all_urls>
```

## Expected Result

Allowed:

- Private lab target IPs
- Localhost web applications
- Any domains added to `allowlist.local.txt`

Blocked:

- Facebook
- Instagram
- TikTok
- Reddit
- Discord
- Twitch
- Pinterest
- Netflix
- Any other site not explicitly allowlisted

## Maintenance Rules

- Keep default-deny behavior.
- Keep the allowlist small.
- Add domains only when they serve a clear learning, research, documentation, publishing, or professional purpose.
- If an allowed site breaks, inspect its required third-party domains and add only the minimum needed.
- Prefer allowing exact product domains over broad infrastructure domains.

## Known Limits

This is not a firewall and not a DNS filter. It is a browser navigation policy.

It will not block:

- Non-browser apps
- Terminal tools
- Custom clients
- Malware
- Traffic outside the managed browsers

That limitation is intentional for lab workflows, because VPN, SSH, scanners, proxies, and command-line tools should keep working.
