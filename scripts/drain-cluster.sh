#!/usr/bin/env bash
# Runs before `terraform destroy`. Usage: drain-cluster.sh <cluster-name>
#
# Kubernetes itself creates cloud resources that Terraform knows nothing about:
# load balancers for LoadBalancer Services and disks for PersistentVolumeClaims.
# If the cluster is deleted first, they are left behind: they keep costing money and,
# on AWS, block deletion of the VPC. So: let Argo CD delete everything it deployed,
# then sweep whatever is left, while the cluster's cloud controllers are still running.
set -uo pipefail

# This script deletes things cluster-wide. Refuse to touch anything but the expected cluster:
# on a laptop the current kubectl context may well be a work cluster.
expected="${1:?usage: drain-cluster.sh <cluster-name>}"
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2> /dev/null || true)
case "$current" in
  # Exact (AKS), ".../<name>" (EKS ARN) or "..._<name>" (gke_<project>_<zone>_<name>).
  "$expected" | */"$expected" | *_"$expected") ;;
  *)
    echo "Refusing to run: kubectl points at cluster '${current:-<none>}', expected '$expected'." >&2
    exit 1
    ;;
esac

if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "Cluster is not reachable, nothing to drain."
  exit 0
fi

echo "Deleting the root Argo CD application (cascades to every child application)..."
kubectl -n argocd delete application root --ignore-not-found --wait=true --timeout=15m

echo "Removing any remaining LoadBalancer Services..."
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
  while read -r ns name; do
    [ -n "$name" ] && kubectl -n "$ns" delete svc "$name" --wait=true --timeout=10m
  done

echo "Removing any remaining PersistentVolumeClaims..."
kubectl delete pvc -A --all --wait=true --timeout=10m

echo "Waiting for the volumes to be released..."
for _ in $(seq 1 60); do
  [ -z "$(kubectl get pv -o name 2> /dev/null)" ] && break
  sleep 5
done

kubectl get svc -A --field-selector spec.type=LoadBalancer 2> /dev/null
kubectl get pv 2> /dev/null
echo "Drain finished."
