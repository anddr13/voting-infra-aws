#!/usr/bin/env bash
# Runs after `terraform apply`. Usage: wait-for-app.sh <cluster-name>
# Waits until Argo CD has rolled everything out and the app answers on the load balancer
# address, then prints the URL (also to the job summary).
set -euo pipefail

# Make sure we are looking at the cluster we just created, not whatever context is current.
expected="${1:?usage: wait-for-app.sh <cluster-name>}"
current=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2> /dev/null || true)
case "$current" in
  # Exact (AKS), ".../<name>" (EKS ARN) or "..._<name>" (gke_<project>_<zone>_<name>).
  "$expected" | */"$expected" | *_"$expected") ;;
  *)
    echo "Refusing to run: kubectl points at cluster '${current:-<none>}', expected '$expected'." >&2
    exit 1
    ;;
esac

addr=""
for i in $(seq 1 60); do
  addr=$(kubectl -n traefik get svc traefik \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2> /dev/null || true)
  [ -n "$addr" ] && break
  echo "Waiting for the load balancer address... ($i/60)"
  sleep 10
done

if [ -z "$addr" ]; then
  echo "The load balancer did not get an address."
  kubectl -n argocd get applications || true
  exit 1
fi

url="http://$addr"
for i in $(seq 1 90); do
  if curl -fsS --max-time 5 "$url/api/results" > /dev/null 2>&1; then
    echo "The app is up: $url"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "### Voting app: $url" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi
  echo "Waiting for the app at $url... ($i/90)"
  sleep 10
done

echo "The app did not come up in time."
kubectl -n argocd get applications || true
kubectl -n voting get pods || true
exit 1
