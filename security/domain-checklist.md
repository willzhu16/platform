# Domain hygiene checklist (dormant)

**Status: dormant until the first domain purchase** — the hatch fires when D-15 hatch 1
(custom domains) is reached. No Artemis project owns a domain yet, so nothing here runs
today. It lives in the repo now (spec 12 §2.6) so the future model executes the whole thing
in one sitting instead of rediscovering it.

Run **at domain purchase**, before pointing any DNS at it. All free / registrar-included.

## At the registrar

- [ ] **DNSSEC on** — publish the DS record at the registrar so responses can't be spoofed.
- [ ] **Registrar lock on** (`clientTransferProhibited`) — blocks unauthorized transfers.
- [ ] **WHOIS privacy on** — no personal contact details in public WHOIS.

## In the Cloudflare zone

- [ ] **CAA record** limiting cert issuance to your CA(s) only, e.g.
      `0 issue "letsencrypt.org"` and `0 issue "pki.goog"` — nobody else can mint a cert.
- [ ] **DNSSEC** activated on the Cloudflare side to match the registrar DS record.

## Email anti-spoofing — even if the domain sends no mail

A domain that sends no mail is the *easiest* to spoof, so lock it down hardest:

- [ ] **SPF** `-all` (hard fail): `v=spf1 -all` for a non-sending domain, or
      `v=spf1 include:<provider> -all` if it does send.
- [ ] **DKIM** — publish the provider's signing key if the domain sends mail.
- [ ] **DMARC** `p=reject`: `v=DMARC1; p=reject; rua=mailto:<you>` — spoofed mail is dropped
      and you get aggregate reports.
- [ ] **MTA-STS** (optional) — enforce TLS on inbound mail if the domain has MX records.

## Verify

- [ ] `dig +short DS <domain>` returns the DNSSEC delegation.
- [ ] `dig +short TXT <domain>` shows the SPF record; `dig +short TXT _dmarc.<domain>` shows
      `p=reject`.
- [ ] `dig +short CAA <domain>` lists only your CA(s).
- [ ] An external checker (e.g. an SPF/DMARC validator) reports no gaps.
