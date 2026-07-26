# AWS (EKS) notes

The most-verified path: the Helm chart was extracted from a service
deployed and drilled on EKS. What you supply around the chart:

## LoadBalancer

Use the AWS Load Balancer Controller with an internet-facing (or
internal) NLB in instance/IP mode. Typical service annotations:

```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    external-dns.alpha.kubernetes.io/hostname: dolt-myproject.trackers.example.com
```

Cost: one NLB per project, order-of $16/mo + LCU: linear, no
port-multiplexing complexity.

## DNS + certificate

external-dns manages the tracker name in a Route53 zone the cluster
owns. If the public name lives on a corporate zone the cluster must NOT
write to, CNAME-delegate both the name and its `_acme-challenge` into
the cluster-owned zone, and set `cnameStrategy: Follow` on your
cert-manager issuer. Full chain in
[docs/design/dolt-service.md](../../docs/design/dolt-service.md).

## Storage

`persistence.storageClass: gp3` (encrypted). Not EFS: Dolt is
single-writer per data directory and multi-attach storage is
unsupported.

## Backups

Two layers:

1. EBS snapshots via AWS Backup (tag-based enrollment of the PVC-backed
   volumes).
2. The chart's logical-backup CronJob against a Dolt `aws://` remote:
   an S3 bucket (versioned, KMS) + a DynamoDB manifest table
   (partition key `db`), IAM scoped to the per-project prefix
   `aws://[table:bucket]/dolt-<project>/<db>`. Grant via IRSA on the
   chart's ServiceAccount (`serviceAccount.annotations`). Restore is
   `dolt clone aws://...` from any credentialed host; drill it.

## Credentials

Store account passwords in SSM Parameter Store
(`/dolt/<project>/users/<account>`); enrollment = attaching a read
policy for that path to the person's role. Kit plumbing:

```sh
export CALLBOOK_CRED_COMMAND='aws ssm get-parameter --with-decryption --query Parameter.Value --output text --name /dolt/{project}/users/{account}'
```

## Node consolidation (Karpenter)

Safe with the chart's required anti-affinity + PDB + warm standby;
consolidation can never evict primary and standby together.
