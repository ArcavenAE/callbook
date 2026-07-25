# Azure (AKS) notes

Untested translation of the AWS recipe — the chart itself is
cloud-neutral; these are the seams. Verify and PR corrections.

- **LoadBalancer:** AKS provisions Azure Load Balancer (TCP passthrough)
  for `type: LoadBalancer`. Annotate
  `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` for
  internal. external-dns supports Azure DNS.
- **Certificates:** cert-manager + Azure DNS DNS-01 solver; CNAME
  delegation pattern unchanged.
- **Storage:** `persistence.storageClass` → `managed-csi-premium`
  (or a Premium SSD v2 class). Not Azure Files (SMB/NFS) —
  single-writer constraint.
- **Workload identity:** Azure Workload Identity on the ServiceAccount.
  Same caveat as GCP for the `aws://` logical-backup remote — use an
  S3-compatible endpoint, or lean on disk snapshots + the git channel.
- **Credentials:** Key Vault. Kit plumbing:
  `CALLBOOK_CRED_COMMAND='az keyvault secret show --vault-name <vault> --name dolt-{project}-{account} --query value -o tsv'`
