# GitOps with Argo CD

Argo CD is the single source of truth for the **application** layer. Git holds
the desired state; Argo CD continuously reconciles the cluster to match it.
No more `kubectl apply` by hand.

## Responsibility split

| Layer | Tool | Why |
| --- | --- | --- |
| VPC, EKS, IAM, KMS | Terraform | Needs cloud APIs / IAM. |
| LB Controller, Argo CD | Terraform (Helm) | Platform addons that depend on IRSA / cluster identity. |
| httpbin + future apps | **Argo CD** | Pure Kubernetes workloads — reconciled from Git. |

## Layout

```
gitops/
├── appproject.yaml     # RBAC boundary: allowed repos / namespaces / kinds
├── root-app.yaml       # app-of-apps: watches gitops/apps/*
└── apps/
    └── httpbin.yaml     # child Application -> ../../k8s (kustomize)
```

Add a new app by dropping one more file in `apps/` and committing — the root
app picks it up automatically.

## Bootstrap (one time)

Terraform already installed Argo CD (see `terraform/argocd.tf`). Seed the
app-of-apps once:

```bash
# 1. Point kubectl at the cluster
aws eks update-kubeconfig --region <region> --name <cluster-name>

# 2. Update the repoURL placeholders (CHANGE-ME) in the three YAMLs to your repo,
#    commit, and push.

# 3. Seed the project + root app. From then on, everything is Git-driven.
kubectl apply -f gitops/appproject.yaml
kubectl apply -f gitops/root-app.yaml
```

> The seed step is a deliberate `kubectl apply` rather than a Terraform
> `kubernetes_manifest`: the latter checks CRDs at plan time, which don't exist
> until Argo CD is installed — a well-known ordering footgun. Seeding two files
> by hand once is the clean, standard bootstrap.

## Access the UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Open https://localhost:8080 (user: `admin`).

## Verify

```bash
kubectl -n argocd get applications
# root      Synced   Healthy
# httpbin   Synced   Healthy
```

`selfHeal: true` means if someone manually edits the httpbin Deployment, Argo CD
reverts it to the Git state within seconds. `prune: true` means deleting a
manifest from Git deletes it from the cluster on the next sync.
