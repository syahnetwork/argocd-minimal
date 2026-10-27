# argocd-minimal — Post-Mortem & Remediation

Post-mortem for the local ArgoCD GitOps demo (k3d + ArgoCD + nginx manifest), covering what went wrong, remediation, and improvements.

## What Went Wrong & Post-Mortem Remediation

| # | Issue | Root Cause | Impact | Remediation |
|---|-------|-----------|--------|-------------|
| 1 | **GitHub personal access token pasted into chat / commits** | Token shared in plaintext during collaboration | Credential leak; anyone with the token can read/write the repo | Immediately **revoke and rotate** the token at GitHub → Settings → Developer settings. Never paste tokens in chat, issues, or commit messages. Use a secrets manager and least-privilege, short-lived tokens. |
| 2 | Deployment named `nginxdeploywebhookkkkkk2` | Name mutated by ad-hoc webhook test commits instead of a proper change process | Confusing resource identity; churn in ArgoCD sync history; hard to correlate with intent | Establish a naming convention (`nginx-demo`), protect `main` with branch protection, and require pull requests for manifest changes. |
| 3 | `repoURL: 'https://github.com/syahnetwork/argocd-minimal.git' # CHANGE THIS` shipped as-is | Placeholder never replaced before applying | Application can fail to resolve its source if the repo URL is wrong/private; copy-paste hazard | Replace placeholders with real values via Kustomize/Helm parameters or templated bootstrap; add a CI check that fails on `CHANGE THIS`. |
| 4 | No `demo` namespace manifest committed | Relied solely on ArgoCD's `CreateNamespace=true` sync option | If sync options drift or project whitelists change, deployment silently fails; unclear ownership of the namespace | Commit an explicit `manifests/namespace.yaml`; keep `CreateNamespace=true` only as a convenience, not the source of truth. |
| 5 | CI validation gaps (ArgoCD files only YAML-syntax checked; no policy checks) | kubeconform lacks ArgoCD CRD schemas; no OPA/Kyverno step added | Invalid `Application`/`AppProject` fields and policy violations merge unchecked | Add ArgoCD CRD schemas to kubeconform (`--schema`), run `argo-cd`-aware linting, and add Kyverno/OPA policy tests to the workflow. |
| 6 | `selfHeal: true` + `prune: true` with no manual-drift guardrails | Aggressive automated sync policy from day one | Any emergency `kubectl edit` hotfix is instantly reverted, escalating incidents | Document drift-handling procedure; use `managedNamespaceMetadata`/ignoreDifferences where needed; disable selfHeal during declared incident windows. |
| 7 | Bootstrap script pins `ARGOCD_VERSION=stable` | Floating tag instead of immutable release | Non-reproducible clusters; a new "stable" can break previously working bootstraps | Pin an exact release (e.g. `v2.11.7`), upgrade deliberately via Renovate/dependabot-style automation. |
| 8 | Webhook/test commits pushed directly to the branch (`#testwebhook`) | Testing CI/webhooks against the real repo without isolation | Dirty history, accidental live syncs of half-baked changes | Test webhooks against a throwaway fork/repo; require signed-off PRs before anything touches `main`. |
| 9 | No Service/route exposure path documented beyond `port-forward` | Docs lived only in shell `echo` lines at the end of the script | Users can't reliably reach the app or ArgoCD UI; admin password retrieval undocumented | Write proper docs (this README) including `argocd admin initial-password`, port-forward steps, and how to reach the nginx Service. |
| 10 | Single-commit history with no review trail | Everything landed in one squashed commit straight to the branch | No peer review, no traceable decision record for manifest changes | Branch-per-change + PR workflow (like this one); require at least one approving review and green CI before merge. |

## Things to Improve

1. **Explicit Namespace manifest** — commit `manifests/namespace.yaml` so the `demo` namespace is declarative, not a side effect of sync options.
2. **Pin ArgoCD version** — replace `stable` with an exact release tag in `bootstrap-local.sh` for reproducible setups.
3. **Resource quotas & LimitRanges** — add a `ResourceQuota` and `LimitRange` in `demo` so the nginx limits are enforced contextually and cluster RAM stays protected.
4. **Liveness/readiness probes** — add `livenessProbe`/`readinessProbe` to the nginx container for graceful failure handling.
5. ** Harden the CI workflow** — add hadolint-style YAML linting, `kube-linter` or Kyverno policy checks, and ArgoCD CRD-aware schema validation; make failures block merges.
6. **Kustomize overlay structure** — split `base/` and `overlays/dev|prod` so the same app promotes across environments instead of editing manifests per environment.
7. **Sealed external URLs** — parameterize `repoURL` (Kustomize helmChart/vars or envsubst in bootstrap) so forks don't need manual edits and placeholders can't ship.
8. **Health checks for ArgoCD itself** — bootstrap should wait on specific deployments (`argocd-application-controller`, `argocd-server`) rather than blanket pod readiness, and verify the App reaches `Synced/Healthy`.
9. **Observability** — scrape ArgoCD and app metrics with Prometheus, alert on `OutOfSync`/`Degraded`, and add basic logging for the demo namespace.
10. **Runbooks & hygiene** — document incident/drift procedures, token rotation policy (no secrets in chat/history — rotate the leaked token!), and branch protection requiring PRs and green CI for all changes.

## Quick Start

```bash
./bootstrap-local.sh                       # k3d cluster + ArgoCD + AppProject/Application
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d   # admin password
kubectl port-forward -n argocd svc/argocd-server 8080:443   # https://localhost:8080
kubectl get applications -n argocd          # watch nginx-demo go Synced/Healthy
```
