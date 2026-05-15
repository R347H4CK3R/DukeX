# DukeX Insignia Profile Research

Last updated: 2026-05-13

## Goal

Build the Profile tab without scraping Insignia's website. The preferred design is a local bridge that observes the authenticated Xbox dashboard/game session already running inside DukeX and uses that session to populate friends, presence, last played, achievements, and leaderboards.

## Current App State

- Profile tab exists in the Swift UI.
- Sign-in currently stores a local gamertag only; it does not authenticate to Insignia.
- Settings > Network includes `Force NAT to Insignia`, enabled by default.
- The Settings UI no longer exposes packet capture. The low-level capture hook is still documented here for future diagnostics.
- If the capture hook is re-enabled in code, the core writes `Documents/InsigniaCaptures/latest.pcap` through a QEMU `filter-dump` object attached to `xemu-netdev`.
- The profile tab fetches Insignia's public DNS route list from `https://insignia.live/dns_zones.json` and public homepage status from `https://insignia.live/`.
- The profile tab now opens `https://insignia.live/dashboard/` in an official SafariServices sheet for full account sign-in, so DukeX does not collect or store Insignia passwords.

## Live Friends Capture

Capture path on Mac:

```text
/tmp/dukex-device/latest.pcap
```

The capture was taken while the Xbox dashboard was running and the user opened Friends.

Observed DNS/Kerberos path:

```text
10.0.2.15:1256 -> 46.101.64.175:53      A? TGS.XBOXLIVE.COM
46.101.64.175:53 -> 10.0.2.15:1256      TGS.XBOXLIVE.COM A 49.13.57.101
10.0.2.15:1257 -> 49.13.57.101:88       Kerberos/TGS request
49.13.57.101:88 -> 10.0.2.15:1257       Kerberos/TGS response
```

Reverse DNS from the same run:

```text
51.68.122.14    vps-ffa76fd9.vps.ovh.net.
49.13.14.21     static.21.14.13.49.clients.your-server.de.
49.13.57.101    macs.insig.uk.
```

Observed secure-gateway traffic:

```text
170 packets  51.68.122.14:3074 -> 10.0.2.15:3074
112 packets  10.0.2.15:3074 -> 51.68.122.14:3074
  7 packets  10.0.2.15:3074 -> 49.13.14.21:3074
  6 packets  49.13.14.21:3074 -> 10.0.2.15:3074
```

The large client-to-server secure-gateway packets contain Kerberos AP-REQ/service-ticket material. Visible markers from this capture:

```text
sg/S1
sg/S4
XBOX.COM
krbtgt
insignia.live
Xbox Version=1.00.5849.3 Title=0xFFFE0000 TitleVersion=408857856
```

Dashboard title ID `0xFFFE0000` confirms the traffic came from the dashboard, not a game title.

No friend names, gamertags, presence strings, leaderboard strings, or achievement strings were visible with `strings` against the pcap. After Kerberos/TGS and the initial secure-gateway handshake, payloads appear to be binary/encrypted secure-gateway frames.

## Interpretation

The capture confirms DukeX is reaching Insignia through the same broad path documented for original Xbox Live:

1. DNS routes Xbox Live hostnames to Insignia.
2. Kerberos obtains service tickets.
3. Secure Gateway traffic on UDP/3074 carries the useful service traffic.

This matches public protocol notes that original Xbox Live used Kerberos authentication plus a Secure Gateway for services such as matchmaking, statistics/leaderboards, custom game services, and related online features.

The important practical finding is that website scraping is not necessary in principle, but packet capture alone is not enough. The Profile tab needs a secure-gateway bridge/parser that can identify the session keys and decode or proxy the post-handshake service traffic.

The public Insignia website exposes aggregate service/game status pages, including active games and public game feature descriptions. That is useful for general status UI, but it is not a substitute for private friends/presence data and should not be treated as a profile API.

## Likely Implementation Path

1. Keep the capture hook as the diagnostic source of truth.
2. Add a local protocol analyzer for `latest.pcap` so DukeX can report:
   - DNS route used.
   - TGS host used.
   - Secure Gateway endpoints seen.
   - Service tickets requested, currently `sg/S1` and `sg/S4`.
3. Identify where the dashboard stores or derives the TGS/session keys in guest memory or in the Kerberos exchange.
4. Decode secure-gateway framing after AP-REQ.
5. Once decrypted/framed, map the underlying service calls into Profile tab models:
   - Friends.
   - Presence / last online.
   - Last played.
   - Stats / leaderboards.
   - Game-specific data where available.

## Open Questions

- Which service IDs map to `S1` and `S4` for dashboard Friends.
- Whether the needed session keys can be extracted cleanly from emulated RAM, the Xbox account material on the HDD, or the Kerberos exchange without invasive guest patching.
- Whether Friends/presence traffic is HTTP-like behind the secure gateway in this dashboard path, or another compact binary service format.
- Whether games expose achievements-like data through Insignia. Original Xbox titles usually expose stats/leaderboards rather than modern achievement systems, so the app may need to label this area carefully.

## Useful Commands

Pull current capture from the device:

```sh
xcrun devicectl device copy from --device 00008140-000825E12E68801C \
  --domain-type appDataContainer --domain-identifier com.mafty.DukeX \
  --source Documents/InsigniaCaptures/latest.pcap \
  --destination /tmp/dukex-device/latest.pcap
```

Summarize secure-gateway flows:

```sh
tcpdump -nn -tttt -r /tmp/dukex-device/latest.pcap 'udp port 3074' 2>/dev/null \
  | awk '{print $4" -> "$6" len "$NF}' \
  | sed 's/:$//' \
  | sort | uniq -c | sort -nr
```

Show Kerberos/DNS:

```sh
tcpdump -nn -vvv -r /tmp/dukex-device/latest.pcap 'udp port 53 or udp port 88'
```

Search visible strings:

```sh
strings -a /tmp/dukex-device/latest.pcap \
  | rg -i '(xboxlive|insig|macs|tgs|sg[0-9]|friends|presence|gamertag|krbtgt|leader|achievement)'
```

## Sources

- xboxdevwiki, `Xbox Live`: architecture overview, XOnline functions, service-ticket flow. <https://xboxdevwiki.net/Xbox_Live>
- DEF CON 30, Tristan Miller, `Reversing the Original Xbox Live Protocols`: protocol architecture overview. <https://av.tib.eu/media/62261>
- Insignia public DNS route list: `https://insignia.live/dns_zones.json`.
- Insignia public site/game status pages: <https://insignia.live/> and <https://insignia.live/games/FFFE0000>.
