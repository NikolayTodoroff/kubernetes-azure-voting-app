# kubernetes-azure-voting-app

A two-tier voting application (Python/Flask frontend + Redis backend) deployed on Azure Kubernetes Service via Azure DevOps Pipelines, using Terraform for cluster infrastructure, Helm for application packaging, and Azure AD-integrated Kubernetes RBAC for access control.

---

## Highlights

- AKS cluster with system and user node pools, Azure CNI Overlay networking, and Azure AD-integrated RBAC
- Kubelet managed identity for credential-free ACR image pulls — no stored secrets anywhere in the image pull path
- Two-tier application: Python/Flask frontend + Redis backend with a PersistentVolumeClaim backed by an Azure Disk
- nginx Ingress controller as the single external entry point — one Load Balancer, one public IP, routing HTTP traffic to the frontend Service
- Horizontal Pod Autoscaler on the frontend Deployment, validated under real load
- Kubernetes RBAC (Role/RoleBinding + ClusterRole/ClusterRoleBinding) mapped to Azure AD groups
- Helm chart for the voting app with per-environment values files (values-dev.yml / values-prod.yml)
- Multi-stage Azure DevOps Pipeline: Build (Docker → ACR) → Validate → Plan → Deploy Infra → Deploy App, with environment-specific ACR references and a manual approval gate on production

---

## Repository Structure

```
kubernetes-azure-voting-app/
├── app/
│   └── azure-vote/                   
│       ├── Dockerfile
|       └── azure-vote/ 
│           ├── main.py
│           └── templates/
├── helm/
│   └── voting-app/
│       ├── Chart.yaml
│       ├── values.yml
│       ├── values-dev.yml
│       ├── values-prod.yml
│       └── templates/
│           ├── redis-pvc.yml
│           ├── redis-deployment.yml
│           ├── redis-service.yml
│           ├── frontend-deployment.yml
│           ├── frontend-service.yml
│           ├── ingress.yml
│           ├── hpa.yml
│           ├── role.yml
│           ├── rolebinding.yml
│           ├── clusterrole.yml
│           └── clusterrolebinding.yml
├── k8s/
│   ├── base/                         
│   └── rbac/                         
├── infra/
│   ├── main/
│   ├── modules/
│   │   ├── aks/
│   │   ├── container-registry/
│   │   └── monitoring/
│   └── env/
├── pipelines/
│   └── aks-voting-app.yml
├── scripts/
│   ├── bootstrap.sh
│   └── assign-roles.ps1
└── README.md
```

`k8s/base/` and `k8s/rbac/` contain the raw manifests written during development as a learning scaffold and debugging reference — the authoritative deployment is managed entirely by the Helm chart in `helm/`.

---

## Infrastructure

Both `dev` and `prod` environments provision identical resources:

| Resource | Name Pattern |
|---|---|
| Resource Group | `rg-main-aksvoter-{env}` |
| Virtual Network | `vnet-aksvoter-{env}` |
| AKS Node Subnet | `snet-aks-aksvoter-{env}` |
| AKS Cluster | `aks-aksvoter-{env}` |
| Container Registry | `acraksvoter{env}` |

The AKS cluster provisions two node pools: a system pool (`Standard_D2s_v3`, 1 node) running cluster-internal components only, and a user pool (`Standard_D2s_v3`, 1 node) running all application workloads. Azure automatically provisions a managed resource group (`MC_rg-main-aksvoter-{env}_aks-aksvoter-{env}_westeurope`) containing the underlying VMSSs, NSGs, Load Balancers, and managed identities.

Terraform state is stored separately per environment in Azure Blob Storage (`staksvoter{env}`).

---

## CI/CD Architecture

```
Build
  └── Docker build → push to acraksvoter{env}
        ↓
Validate
  └── terraform install / init / validate / tflint
        ↓
Plan
  └── terraform plan → published as pipeline artifact
        ↓
DeployInfra  (deployment job → infrastructure-{env} environment)
  └── terraform apply (saved plan)
        ↓
DeployApp  (deployment job → application-{env} environment)
  ├── az aks install-cli  (kubectl + kubelogin)
  ├── az aks get-credentials + kubelogin convert-kubeconfig
  └── helm upgrade --install with --set frontend.image.tag=$(Build.BuildId)
```

Parameterized by `environment` (`dev`/`prod`) and `runDeploy` (boolean — unchecked = build and validate only). 

---

## Application Architecture

```
Internet
    ↓
Azure Load Balancer (auto-provisioned in MC_ resource group)
    ↓
nginx Ingress Controller (Layer 7 — reads HTTP headers, applies routing rules)
    ↓
frontend Service (ClusterIP: stable internal DNS name)
    ↓
frontend Pod (Python/Flask, pulls from ACR via kubelet managed identity)
    ↓
redis Service (ClusterIP: "redis" DNS name, resolved by CoreDNS)
    ↓
Redis Pod (persists vote counts to Azure Disk via PVC)
```

The nginx ingress controller is the single external entry point — one Azure Load Balancer and one public IP serve all HTTP traffic regardless of how many Services exist inside the cluster. The Load Balancer operates at Layer 4 (TCP forwarding); nginx is the first component that reads HTTP content and applies path/host-based routing rules.

---

## Kubernetes RBAC

Two RBAC pairs are configured, mapped to an Azure AD group:

**Namespace-scoped (voting namespace):**
- `voting-viewer` Role — read-only access to pods, services, endpoints, PVCs, deployments, replicasets
- `voting-viewer-binding` RoleBinding — grants the Role to the AAD admin group

**Cluster-scoped:**
- `cluster-observer` ClusterRole — read-only access to nodes, namespaces, persistent volumes, storage classes, and metrics
- `cluster-observer-binding` ClusterRoleBinding — grants the ClusterRole to the AAD admin group

With `azure_rbac_enabled = true` on the cluster, Azure RBAC is evaluated before native Kubernetes RBAC — the pipeline SP needs both `Azure Kubernetes Service Cluster Admin Role` (management plane, for `az aks get-credentials`) and `Azure Kubernetes Service RBAC Cluster Admin` (data plane, for actual Kubernetes API calls).

---

## Security

### Identity and Authentication

- Workload identity federation on the ARM service connection — no client secrets stored anywhere
- Kubelet managed identity with `AcrPull` — pods pull images from ACR without any stored credential
- Pipeline SP has `AcrPush` at ACR scope and `Azure Kubernetes Service RBAC Cluster Admin` at cluster scope
- Azure AD-integrated cluster RBAC — `kubectl` authenticates via `az login` token, no static kubeconfig credentials
- `kubelogin convert-kubeconfig -l azurecli` converts the kubeconfig for non-interactive pipeline use

### Security Tooling

| Tool | Purpose |
|---|---|
| TFLint | Terraform static analysis, run in the Validate stage |
| Azure RBAC (AKS) | Data-plane access via Azure AD group membership, not static credentials |
| kubelet managed identity | Credential-free ACR pulls — no image pull secrets in any manifest |

---

## Key Design Decisions

- **Raw manifests before Helm** — `k8s/base/` and `k8s/rbac/` were validated first to verify each resource independently before introducing Helm templating. Avoid mixing `kubectl apply` and Helm in the same namespace—Helm tracks ownership through annotations and won't adopt existing resources.

- **Azure CNI Overlay over kubenet** — pods use a private overlay network without consuming VNet IP space, while retaining Azure CNI performance and network policy support. Microsoft's recommended networking mode for new AKS clusters.

- **System/User node pool separation** — the system pool uses `only_critical_addons_enabled = true` to reserve it for Kubernetes components. Application workloads are scheduled only on the labeled user node pool via `nodeSelector`.

- **HPA on the frontend only** — the frontend is stateless and scales horizontally. Redis is stateful, so multiple replicas require additional clustering (for example, Redis Sentinel) to maintain consistency.

- **ClusterIP Services with a shared Ingress** — frontend and Redis use `ClusterIP` Services. External traffic enters through a single NGINX Ingress, avoiding one Azure Load Balancer per Service.

- **`kubelogin` for AAD-integrated pipeline authentication** — on Entra ID–integrated clusters, `az aks get-credentials` alone isn't sufficient for headless agents. `kubelogin convert-kubeconfig -l azurecli` reuses the Azure CLI token and avoids interactive authentication.

- **Separate Azure RBAC roles for management and data planes** — the pipeline service principal requires both **Azure Kubernetes Service Cluster Admin Role** (retrieve cluster credentials) and **Azure Kubernetes Service RBAC Cluster Admin** (access the Kubernetes API). Granting only the first results in authorization failures after authentication succeeds.

---

## Technologies

- **Terraform** — IaC with modules pattern (AKS, ACR, networking, monitoring)
- **Azure DevOps Pipelines** — multi-stage YAML, environment-gated approvals, Build.BuildId image tagging
- **Azure Boards** — Epic → Feature → Story → Task hierarchy, AB#N commit linking
- **Helm** — application packaging, per-environment values overrides, `helm upgrade --install` idempotent deploys
- **Azure Kubernetes Service** — managed Kubernetes, system+user node pools, Azure CNI Overlay, AAD-integrated RBAC
- **Azure Container Registry** — image hosting, kubelet managed identity pull, pipeline SP push
- **nginx Ingress Controller** — Layer 7 routing, single external entry point
- **Horizontal Pod Autoscaler** — CPU-based replica scaling, validated under load
- **Kubernetes RBAC** — custom Role/ClusterRole mapped to Azure AD groups
- **Python/Flask** — voting app frontend
- **Redis** — vote count persistence, PVC-backed Azure Disk storage
- **Azure Monitor** — Log Analytics, Action Groups, metric alerts
- **TFLint** — Terraform static analysis
- **Docker** — image build, pushed to ACR via pipeline

---
