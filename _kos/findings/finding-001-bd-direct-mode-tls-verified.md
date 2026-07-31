# finding-001: bd direct server mode negotiates TLS on released builds; the proxied-mode premise was wrong

Date: 2026-07-30
Status: verified
Supersedes: the "bd <= 1.1.0 server mode cannot speak TLS" claim in
docs/design/dolt-service.md (corrected in place) and the version-pin
rationale in charter F2.

## Summary

The production recipe standardized on bd's proxied-server mode because a
2026-07-25 compatibility test concluded that bd server mode could not
negotiate TLS and was rejected by the listener. Re-testing with a
method that separates TLS failure from auth failure shows the claim was
an over-generalization: only the `bd init` path drops TLS. Runtime
commands negotiate TLS on every released bd since v0.53.0. Proxied mode
is an alternative (and the only client-certificate path), not a
requirement.

## Method

Dummy-password discrimination against a deployed TLS-required Dolt
2.2.2 instance (publicly trusted certificate, `require_secure_transport`
listener). If a connection with a deliberately wrong password fails
with `Error 1045 Access denied`, the TLS handshake completed and MySQL
auth ran; if it fails with a TLS or insecure-connection error, TLS is
the blocker. No real credentials are needed.

## Results

| Path | bd build | TLS env | Result | Reading |
|---|---|---|---|---|
| runtime (`bd list`, hand-written workspace config) | 1.1.0 (Homebrew) | `BEADS_DOLT_SERVER_TLS=1` | `Error 1045 Access denied` | TLS negotiated |
| runtime, same | 1.1.0 | `BEADS_DOLT_SERVER_TLS=0` | `server does not allow insecure connections` | control |
| `bd init --server --external` | 1.1.0 | `BEADS_DOLT_SERVER_TLS=1` | `server does not allow insecure connections` | init drops TLS |
| `bd init --server --external` | 1.1.2 (release binary) | `BEADS_DOLT_SERVER_TLS=1` | `server does not allow insecure connections` | still broken in latest release |

Source archaeology (upstream gastownhall/beads):

- Direct-mode TLS shipped in commit c34742920 (2026-02-16, "feat: add
  Hosted Dolt support"), contained in v0.53.0 and every later release.
  Config `dolt_server_tls` / env `BEADS_DOLT_SERVER_TLS`; DSN sets the
  driver to full verification against system roots.
- The init gap is upstream #3895; fix #3679 merged to main 2026-07-04.
  v1.1.2 (published 2026-07-26) was cut from a base 691 commits behind
  main and does not contain it. No release carries the fix.
- Custom CA and client certificates (mutual TLS) exist only in the
  proxied external stack (`ExternalDoltConfig`: TLSCACert, TLSCert,
  TLSKey). Direct mode has no surface for either.
- Discoverability: no CLI flag, no help text for the TLS env/config
  (upstream #5011; docs PR #5144 open). The 2026-07-25 test flowed
  from visible flags to a wrong conclusion; this finding is the
  correction.

Incidental discovery: `BEADS_DOLT_SERVER_PORT` in the environment
silently overrides an explicit `--server-port` flag at `bd init`
(env-over-flag resolution inversion). Draft filing exists.

## Consequences applied

- docs/design/dolt-service.md client-compatibility section rewritten;
  hybrid database-policy paragraph gains the proxied-only scope note.
- docs/enrollment.md: direct-mode enrollment is primary; known-gaps
  list extended; version-channel decision reframed.
- kit/enroll.sh writes direct-mode variables first, proxied variables
  alongside; kit/doctor.sh version warning retargeted at the init gap.
- charter: B2 scope note, F2 reframed, F6 items (d) through (g).

## Open

- Fresh-run generic repro scripts for the upstream filings (custom CA,
  mutual TLS, flag precedence) before posting; gated on reviewing
  engagement with our existing upstream issues.
- Re-verify the init path when upstream cuts a release containing
  #3679, then simplify enroll flow back to `bd init`.
