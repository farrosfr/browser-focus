# browser-focus

browser-focus is a small Windows policy toolkit for creating a strict browsing environment for learning, research, writing, and cybersecurity labs.

It uses browser enterprise policies to block all browser navigation by default, then allow only local/lab targets plus any private entries you add.

The goal is focus: keep the browser useful for technical work while reducing low-value browsing and distraction.

## What It Does

The enable script applies a default-deny browser policy:

```text
Block everything
Allow only approved domains
```

It affects browser navigation only. It does not modify system DNS, firewall rules, VPN settings, hosts file entries, SSH, Git, Nmap, Burp Suite, curl, wget, or terminal networking.

## Supported Browsers

Implemented:

```text
Google Chrome
Microsoft Edge
Mozilla Firefox
Firefox Developer Edition
Microsoft Store Firefox
```

Chrome and Edge are configured through Windows registry policy:

```text
HKLM:\SOFTWARE\Policies\Google\Chrome
HKLM:\SOFTWARE\Policies\Microsoft\Edge
```

Firefox is configured through machine-wide Mozilla registry policy:

```text
HKLM:\SOFTWARE\Policies\Mozilla\Firefox
```

Firefox Developer Edition is also configured through:

```text
C:\Program Files\Firefox Developer Edition\distribution\policies.json
```

Microsoft Store Firefox is covered by the Mozilla registry policy path. Its install folder lives under `C:\Program Files\WindowsApps`, which is protected, so registry policy is the practical route.

## Default Allowlist

The published default is intentionally small:

```text
localhost
127.0.0.1
10.*
172.*
192.168.*
browser policy pages
```

See [allowlist-only.md](allowlist-only.md) for the detailed strategy.

## Enable

Run PowerShell as Administrator:

```powershell
cd path\to\browser-focus
.\scripts\Enable-AllowlistOnlyBrowserPolicy.ps1 -RestartBrowsers
```

Short form:

```powershell
.\scripts\Enable-AllowlistOnlyBrowserPolicy.ps1 -r
```

`-RestartBrowsers` / `-r` immediately closes and reopens currently running Chrome, Edge, and Firefox processes so policy changes take effect.

## Private Allowlist

For work-specific domains, VPS IPs, or private URLs, create:

```text
allowlist.local.txt
```

This file is ignored by Git. A template is provided:

```text
allowlist.local.example.txt
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

The enable script automatically merges `allowlist.local.txt` into the browser allowlist.

The script converts entries into browser-specific policy formats. Chrome and Edge use Chromium URL filter syntax such as `google.com` or `https://server:8080/path`. Firefox uses WebExtension-style patterns such as `*://google.com/*` and `<all_urls>` for the default block.

The script creates registry backups in:

```text
policy-backups/
```

Backups are ignored by Git.

## Disable

Run PowerShell as Administrator:

```powershell
cd path\to\browser-focus
.\scripts\Disable-AllowlistOnlyBrowserPolicy.ps1 -RestartBrowsers
```

Short form:

```powershell
.\scripts\Disable-AllowlistOnlyBrowserPolicy.ps1 -r
```

This removes the strict allowlist policy keys and Firefox policy files created by the script.

## Verify

Chrome:

```text
chrome://policy
```

Edge:

```text
edge://policy
```

Firefox:

```text
about:policies
```

Expected policy shape:

```text
URLBlocklist = *
URLAllowlist = approved sites only
```

Firefox equivalent:

```text
WebsiteFilter.Block = <all_urls>
WebsiteFilter.Exceptions = approved sites only
```

## Notes

Browser policies are not a replacement for network controls. They are a local productivity and focus layer.

If an allowed site breaks, it probably depends on another domain that is not currently allowlisted. Add only the minimum required domain after verifying why it is needed.

## References

- Chrome URL block/allow filter format: https://support.google.com/chrome/a/answer/9942583
- Chrome allow or block access to websites: https://support.google.com/chrome/a/answer/7532419
- Microsoft Edge URLBlocklist policy: https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/urlblocklist
- Firefox WebsiteFilter policy: https://firefox-admin-docs.mozilla.org/reference/policies/websitefilter/
