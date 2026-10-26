# voting-infra-aws

EKS cluster for the multi-cloud [voting-app](https://github.com/anddr13/voting-app): `make up`, play, `make down`.
A pay-per-hour sandbox that lives for a few hours.

Related: [voting-gitops](https://github.com/anddr13/voting-gitops) (what runs in the cluster) ·
[voting-infra-azure](https://github.com/anddr13/voting-infra-azure) · [voting-infra-gcp](https://github.com/anddr13/voting-infra-gcp) ·
[voting-infra-local](https://github.com/anddr13/voting-infra-local)

## Why this one runs from a laptop

The Azure and GCP stacks are applied by GitHub Actions with keyless OIDC trust and destroyed by a nightly cron.
This AWS account lives in an AWS-managed organization (the console's *projects*), and its service control policies
change the picture. Checked with `--dry-run` calls and a throw-away IAM role:

| What | Result | Consequence |
|---|---|---|
| `iam:CreateOpenIDConnectProvider` | denied | no GitHub OIDC trust; long-lived keys in GitHub were ruled out, so Terraform runs locally with short-lived `aws login` credentials |
| Spot `RunInstances` | denied | nodes are On-Demand |
| On-Demand instances, EBS volumes, load balancers | denied **only while the project's spend limit was about to be reached** (a `DenyCompute` SCP is how the console "pauses resources") | allowed again once the limit was lifted; the budget below replaces it as the safety net |

CI still runs `fmt`, `validate`, `tflint` and `shellcheck` on every push.

## What gets created

```
bootstrap/   once, local state:  S3 bucket for state · monthly budget with e-mail alerts
infra/       per session (make up / make down):
  VPC 10.20.0.0/16, 2 public subnets in 2 AZs, no NAT gateway
  EKS (access entries, standard support) + managed node group: 2 On-Demand m6i.large (2 vCPU / 8 GiB)
  add-ons: eks-pod-identity-agent, aws-ebs-csi-driver (permissions via Pod Identity) · gp3 StorageClass
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/NLB, KEDA, Strimzi, Kafka, Redis, Mongo, app)
```

**Cost (approximate, eu-north-1):** control plane $0.10/h + 2 × m6i.large ~$0.18/h + NLB, public IPv4 and disks ~$0.05/h
≈ **$0.33/h**, about $1.3 for a 4-hour session. Skipping the NAT gateway saves ~$1/day plus traffic.

## Usage (WSL / Linux)

Requires `aws` CLI v2 with an `aws login` profile, `terraform` ≥ 1.10, `kubectl`, `helm`, `make`.
The Makefile uses the profile `gpu-lab-terraform` (a `credential_process` profile on top of `aws login`), override
with `AWS_PROFILE=...`.

```bash
aws login --remote --profile gpu-lab      # the session behind the short-lived credentials

make bootstrap   # once: S3 state bucket + budget alerts to your git e-mail; writes infra/backend.hcl (not committed)
make up          # ~20 min; waits until the app answers and prints its URL
make down        # removes what Kubernetes created (NLB, EBS), then terraform destroy
make leftovers   # EKS / EC2 / EBS / LB still in the region?
```

There is no nightly destroy here, so `make down` is on you; the budget e-mails you when the forecast for the month
crosses the limit (default $10).

## Things to look at once it is up

```bash
export KUBECONFIG=~/.kube/voting-aws                  # separate file, ~/.kube/config stays untouched
kubectl -n argocd get applications                     # waves: traefik/keda/strimzi → data → voting
kubectl -n voting get kafka,kafkatopic,pods
kubectl -n voting get scaledobject,hpa -w              # run the k6 test from voting-app in another terminal
kubectl -n argocd port-forward svc/argocd-server 8443:443
```

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  The cluster's credentials go to `~/.kube/voting-aws`, so `~/.kube/config` and its current context are never modified.
- **`make down` drains before it destroys.** The NLB and EBS volumes are created by Kubernetes, not Terraform.
  If the cluster were deleted first, the NLB and its security group would be left behind and the VPC deletion would fail
  on dependencies. The script deletes the `root` Application (cascading to everything else), then any remaining
  LoadBalancer Services and PVCs.
- **No NAT gateway.** Nodes run in public subnets with public IPs; the security group blocks inbound internet traffic
  except the ports a LoadBalancer opens.
- **`upgrade_policy = STANDARD`.** Otherwise a version that leaves standard support silently moves to extended support,
  which costs 6x more.
- **EBS CSI via Pod Identity**, with no cluster OIDC provider or IRSA (creating one is denied here anyway).
- **`infra/backend.hcl` is not committed**: the bucket name contains the account ID, and only the laptop needs it.
