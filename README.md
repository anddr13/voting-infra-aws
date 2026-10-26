# voting-infra-aws

EKS cluster for the multi-cloud [voting-app](https://github.com/anddr13/voting-app).
Created with one click, destroyed with one click, and destroyed automatically every night: this is a pay-per-hour sandbox.

Related: [voting-gitops](https://github.com/anddr13/voting-gitops) (what runs in the cluster) ·
[voting-infra-azure](https://github.com/anddr13/voting-infra-azure) · [voting-infra-gcp](https://github.com/anddr13/voting-infra-gcp)

## What gets created

```
bootstrap/   once, local state:  S3 bucket for state · GitHub OIDC provider · IAM role for Actions
infra/       daily (apply/destroy):
  VPC 10.20.0.0/16, 2 public subnets in 2 AZs, no NAT gateway
  EKS (access entries, standard support) + managed node group: 2 spot nodes, 2 vCPU / 8 GiB
  add-ons: eks-pod-identity-agent, aws-ebs-csi-driver (permissions via Pod Identity) · gp3 StorageClass
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/NLB, KEDA, Strimzi, Kafka, Redis, Mongo, app)
```

**Cost (approximate):** control plane $0.10/h + 2 spot nodes ~$0.08/h + NLB ~$0.025/h + public IPv4 and disks
≈ **$0.23/h**, i.e. ~$1 for a 4-hour session or ~$5.5 per day. The biggest savings are spot nodes and skipping the
NAT gateway (~$1/day plus traffic).

## One-time bootstrap

Requires the `aws` CLI (logged in as an account administrator), `terraform` ≥ 1.10 and `gh`.

```bash
cd bootstrap
terraform init
terraform apply
terraform output -raw next_steps   # run the printed commands: repository variables + commit backend.hcl
```

- If the account already has a GitHub OIDC provider: `terraform import aws_iam_openid_connect_provider.github <arn>`.
- `EKS_ADMIN_ARNS` gives you `kubectl` access from your laptop. If you sign in through SSO, use the **role** ARN
  (`arn:aws:iam::<acc>:role/AWSReservedSSO_...`), not the `arn:aws:sts::...:assumed-role/...` session ARN.
- Keep `bootstrap/` around: it costs next to nothing and the S3 bucket holds the state.

## Create / destroy

GitHub → **Actions → terraform → Run workflow**:
- `apply`: ~25 minutes (EKS ~12, nodes and add-ons ~5, Argo CD + Kafka ~8). The job waits until the app responds
  and writes its URL to the job summary.
- `destroy`: removes everything. Two nightly crons (01:23 and 03:53 UTC) run it in case you forget; they avoid the top of the hour,
  where GitHub delays scheduled runs (a 01:00 run once started at 05:42).

The same from a laptop:

```bash
cd infra
terraform init -backend-config=backend.hcl
terraform apply
eval "$(terraform output -raw kubeconfig_command)"   # separate kubeconfig file, ~/.kube/config stays untouched
kubectl -n argocd get applications
```

## Things to look at once it is up

```bash
kubectl -n argocd get applications                     # waves: traefik/keda/strimzi → data → voting
kubectl -n voting get kafka,kafkatopic,pods
kubectl -n voting get scaledobject,hpa -w              # run the k6 test from voting-app in another terminal
kubectl -n argocd port-forward svc/argocd-server 8443:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  `kubeconfig_command` writes credentials to a separate file (`~/.kube/voting-<cloud>`), so `~/.kube/config`
  and its current context are never modified.
- **`scripts/drain-cluster.sh` runs before `destroy`.** The NLB and EBS volumes are created by Kubernetes, not Terraform.
  If the cluster were deleted first, the NLB and its security group would be left behind and the VPC deletion would fail
  on dependencies. The script deletes the `root` Application (cascading to everything else), then any remaining
  LoadBalancer Services and PVCs.
- **No NAT gateway.** Nodes run in public subnets with public IPs; the security group blocks inbound internet traffic
  except the ports a LoadBalancer opens.
- **`upgrade_policy = STANDARD`.** Otherwise a version that leaves standard support silently moves to extended support,
  which costs 6x more.
- **Several instance types** in the spot node group, so a shortage of one type does not block node creation.
- **EBS CSI via Pod Identity**, with no cluster OIDC provider or IRSA.
- **No long-lived keys:** GitHub Actions gets temporary credentials through OIDC, trusted only for `main` of this repository.
- **Immutable GitHub OIDC subjects.** Repositories created after 2026-07-15 present
  `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...` instead of `repo:<owner>/<repo>:ref:...`, so a
  re-created repository with the same name cannot reuse the trust. `bootstrap/github.tf` looks the IDs up
  in the GitHub API and the AWS trust policy uses them; the old name-only form would be rejected with `AADSTS700213`-style
  "no matching federated identity" errors.
- `AdministratorAccess` on the role is a deliberate shortcut for a sandbox account; scope it down for anything real.
