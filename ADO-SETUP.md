# EntraOps on Azure DevOps

This guide covers running EntraOps in Azure DevOps (ADO) using Microsoft-hosted agents and Workload Identity Federation (WIF).

## Prerequisites

1. **Azure DevOps Project** with Pipelines enabled
2. **Azure Subscription** where you can create an App Registration (or use an existing one)
3. **Permissions** in Entra ID: Global Administrator or Application Administrator + User Access Administrator (for RBAC assignments)

## Quick Start

### 1. Import the EntraOps PowerShell module

```powershell
Import-Module ./EntraOps
```

### 2. Create the configuration file

```powershell
New-EntraOpsConfigFile -TenantName "contoso.onmicrosoft.com" -DevOpsPlatform "AzureDevOps"
```

This generates `EntraOpsConfig.json` with `DevOpsPlatform` set to `AzureDevOps`.

### 3. Create the workload identity with an ADO federated credential

```powershell
New-EntraOpsWorkloadIdentity `
  -AppDisplayName "EntraOps-ADO" `
  -CreateFederatedCredential `
  -AdoOrgName "my-org" `
  -AdoProjectName "my-project" `
  -AdoServiceConnectionName "EntraOps-ServiceConnection"
```

This creates an App Registration and adds a federated credential with:
- **Issuer**: `https://login.microsoftonline.com/<tenant-id>/v2.0` (Microsoft Entra issuer)
- **Subject**: `sc://my-org/my-project/EntraOps-ServiceConnection`

> If your ADO org still uses the legacy Azure DevOps issuer, override it with `-AdoFederatedCredentialIssuer`.

### 4. Create the ADO Service Connection

1. In Azure DevOps, go to **Project Settings -> Service Connections -> New Service Connection**
2. Select **Azure Resource Manager -> Workload Identity Federation (manual)**
3. Choose **App registration (single tenant)**
4. Enter the **Application (client) ID** and **Tenant ID** from the App Registration created in step 3
5. For **Issuer**, use the same issuer URL shown above
6. For **Subject identifier**, use `sc://<org>/<project>/<service-connection-name>`
7. Save the connection as `EntraOps-ServiceConnection` (or match the name used in step 3)

### 5. Configure pipeline variables

Create the following pipeline variables (or use a Variable Group):

| Variable | Example Value | Description |
|---|---|---|
| `EntraOpsTenantName` | `contoso.onmicrosoft.com` | Entra ID tenant FQDN |
| `EntraOpsAzureServiceConnection` | `EntraOps-ServiceConnection` | ADO Service Connection name |
| `EntraOpsApplyAutomatedClassificationUpdate` | `false` | Auto-update classification templates |
| `EntraOpsApplyAutomatedControlPlaneScopeUpdate` | `false` | Auto-update Control Plane scope |
| `EntraOpsApplyAutomatedEntraOpsUpdate` | `true` | Auto-update EntraOps module |

### 6. Import and run the pipelines

1. In Azure DevOps Pipelines, select **New pipeline -> Existing Azure Pipelines YAML file**
2. Choose `azure-pipelines-pull.yml` for the core monitoring/classification pipeline
3. Choose `azure-pipelines-update.yml` for the module self-update pipeline
4. Save and run

## Pipeline Files

| File | Purpose | Trigger |
|---|---|---|
| `azure-pipelines-pull.yml` | Collects privileged access data, classifies it, and commits JSON back to the repo | Scheduled (default: daily 09:30 UTC) + manual |
| `azure-pipelines-update.yml` | Updates EntraOps module and resources from upstream | Scheduled (default: Wed 09:00 UTC) + manual |

## Authentication Flow

ADO pipelines use the `AzurePowerShell@5` task with a WIF service connection. The task authenticates to Azure PowerShell automatically. EntraOps then uses `Connect-EntraOps -AuthenticationType FederatedCredentials`, which calls `Get-AzAccessToken` to acquire a Microsoft Graph token.

No secrets (client secrets or PATs) are required for the runtime authentication.

## Git Push from Pipelines

Both pipelines commit generated data back to the repository using `scripts/ado/Ado-GitPush.ps1`. This script uses the built-in `$(System.AccessToken)` with `persistCredentials: true` on the checkout step.

## Upstream Updates

By default, `Update-EntraOps` clones from `https://github.com/Cloud-Architekt/EntraOps.git`. To use an ADO Git mirror instead:

```powershell
Update-EntraOps -UpstreamUrl "https://dev.azure.com/my-org/my-project/_git/entraOps"
```

## Differences from GitHub Actions

| Feature | GitHub Actions | Azure DevOps |
|---|---|---|
| CI/CD YAML | `.github/workflows/*.yaml` | `azure-pipelines-*.yml` |
| Auth | GitHub OIDC + `azure/login@v2` | `AzurePowerShell@5` + Service Connection |
| Federated credential issuer | `https://token.actions.githubusercontent.com` | `https://login.microsoftonline.com/<tenant>/v2.0` |
| Federated credential subject | `repo:<org>/<repo>:ref:refs/heads/<branch>` | `sc://<org>/<project>/<service-connection>` |
| Commit/push | `secrets.GITHUB_TOKEN` | `$(System.AccessToken)` |
| Workflow parameters | Self-modifying YAML (`Update-EntraOpsRequiredWorkflowParameters`) | Pipeline variables / variable groups |

## Scope

The ADO pipelines in this port cover **core monitoring and classification** only:
- `Save-EntraOpsPrivilegedEAMJson`
- Optional `Update-EntraOpsClassificationFiles`
- Optional `Update-EntraOpsClassificationControlPlaneScope`

Push features (Sentinel ingestion, Conditional Access group automation, Administrative Unit management) are not included in the ADO YAML but can be added by extending the pipelines using the existing EntraOps cmdlets.
