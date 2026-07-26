# Security

## Reporting

Report vulnerabilities privately via GitHub Security Advisories
(Security tab, "Report a vulnerability") on this repository. Please do
not open public issues for security reports.

## Scope notes for deployers

callbook ships deployment recipes, not a service. The security posture
of what you deploy is yours; the recipes encode these defaults:

- **TLS is required from day one** on anything beyond localhost. The
  chart sets `require_secure_transport` and serves certificates from
  the Dolt process itself (MySQL TLS is in-protocol; there is no
  terminating proxy to lean on).
- **The public SQL listener will be scanned.** Auth plus required TLS
  are the access controls; failed-auth monitoring is part of the
  production gate, and source-range allowlists can be added without
  redesign.
- **root never leaves platform automation.** Humans and agents use
  tiered accounts; enrollment grants read access to a credential-store
  path, never a copied secret. See docs/enrollment.md.
- **The kit fails closed.** enroll.sh writes per-machine files (mode
  600, outside any repo) and never falls back to prompts or defaults
  on a failed credential fetch.

## Upstream

Vulnerabilities in beads or Dolt themselves belong upstream
(gastownhall/beads, dolthub/dolt). If a callbook recipe makes an
upstream weakness worse, that is in scope here; tell us.
