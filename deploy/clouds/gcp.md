# GCP (GKE) notes

Untested translation of the AWS recipe — the chart itself is
cloud-neutral; these are the seams. Verify and PR corrections.

- **LoadBalancer:** GKE provisions a TCP passthrough Network Load
  Balancer for `type: LoadBalancer` natively. Use
  `networking.gke.io/load-balancer-type: "Internal"` for internal.
  external-dns supports Cloud DNS for the hostname.
- **Certificates:** cert-manager + Cloud DNS DNS-01 solver. The CNAME
  delegation pattern (and `cnameStrategy: Follow`) works identically if
  your public zone is separate from the cluster's zone.
- **Storage:** `persistence.storageClass` → a `pd-ssd`-backed class with
  encryption. Not Filestore (NFS) — single-writer constraint.
- **Workload identity:** GKE Workload Identity on the ServiceAccount
  replaces IRSA. Dolt's cloud remotes are `aws://`-shaped — for logical
  backups on GCP, either run against an S3-compatible endpoint or use
  a file remote + object-storage sync sidecar; alternatively rely on
  PD snapshot schedules and `bd dolt push` git-channel redundancy.
  (This is the least-translated corner; treat it as open.)
- **Credentials:** Secret Manager. Kit plumbing:
  `CALLBOOK_CRED_COMMAND='gcloud secrets versions access latest --secret=dolt-{project}-{account}'`
