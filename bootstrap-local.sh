#!/usr/bin/env bash
set -euo pipefail

CLUSTER=k3d-local
ARGOCD_VERSION=stable

echo "==> Creating k3d cluster ($CLUSTER) with minimal resources..."
k3d cluster create "$CLUSTER" \
  --agents 0 \
  --servers-memory 2g \
  --wait

echo "==> Setting kubectl context to $CLUSTER..."
kubectl config use-context "k3d-$CLUSTER"

echo "==> Installing ArgoCD (server-side apply to avoid CRD size limit)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD pods..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s

echo "==> Bootstrapping AppProject + Application..."
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application.yaml

echo "==> Done."
echo
echo "    ArgoCD UI:  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "    Open:       https://localhost:8080  "
echo
echo "    Check sync: kubectl get applications -n argocd"
