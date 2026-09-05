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

### 3. Create the workload identity

```powershell
New-EntraOpsWorkloadIdentity `
  -AppDisplayName "EntraOps-ADO" `
  -CreateFederatedCredential `
  -AdoOrgName "my-org" `
  -AdoProjectName "my-project" `
  -AdoServiceConnectionName "EntraOps-ServiceConnection"
```

This creates an App Registration with the required Microsoft Graph permissions. Do not create the federated credential yet; the correct issuer and subject are provided by Azure DevOps in the next step.

### 4. Create the ADO Service Connection

1. In Azure DevOps, go to **Project Settings -> Service Connections -> New Service Connection**
2. Select **Azure Resource Manager -> Workload Identity Federation (manual)**
3. Choose **App registration (single tenant)**
4. Enter the **Application (client) ID** and **Tenant ID** from the App Registration created in step 3
5. Save the connection as `EntraOps-ServiceConnection` (or match the name used in step 3)
6. Copy the **Issuer** and **Subject identifier** values displayed on the service connection page

#### Cross-tenant scenario (ADO org in a different tenant than the app registration)

If your Azure DevOps organization is backed by a different Microsoft Entra tenant than the one containing the EntraOps app registration, the automatic subscription discovery will not work. Use **Workload Identity Federation (manual)** and enter all values by hand:

| Field | Value |
|-------|-------|
| **Environment** | AzureCloud |
| **Scope level** | Subscription |
| **Subscription Id** | `<Azure-Subscription-ID>` |
| **Subscription name** | `<Azure-Subscription-Name>` |
| **Tenant ID** | `<Tenant-ID-of-app-registration>` |
| **Service Principal Id** | `<Application-(client)-ID>` |

Copy the **Issuer** and **Subject identifier** values displayed by ADO, then add a matching federated credential in the app registration:

1. Open the Azure Portal in the tenant that owns the app registration.
2. Go to **Microsoft Entra ID -> App registrations -> Certificates & secrets -> Federated credentials -> Add credential**.
3. Select **Other issuer**.
4. Paste the exact **Issuer** and **Subject identifier** from the ADO service connection page.
5. Set **Audience** to `api://AzureADTokenExchange`.
6. Save, return to ADO, and click **Verify and Save**.

### 5. Import the pipelines

1. In Azure DevOps, go to **Pipelines -> New pipeline**.
2. Select **Azure Repos Git** (or your connected repository).
3. Choose **Existing Azure Pipelines YAML file**.
4. Select `azure-pipelines-pull.yml` and save the pipeline (do not run yet).
5. Repeat steps 1-4 for `azure-pipelines-update.yml`.

### 6. Configure pipeline variables

Create the following pipeline variables for **each** imported pipeline (or create a single Variable Group and link it to both pipelines):

| Variable | Required | Example Value | Description |
|---|---|---|---|
| `EntraOpsTenantName` | **Yes** | `contoso.onmicrosoft.com` | Entra ID tenant FQDN |
| `EntraOpsAzureServiceConnection` | **Yes** | `EntraOps-ServiceConnection` | Exact ADO Service Connection name |
| `EntraOpsApplyAutomatedClassificationUpdate` | No | `false` | Auto-update classification templates |
| `EntraOpsApplyAutomatedControlPlaneScopeUpdate` | No | `false` | Auto-update Control Plane scope |
| `EntraOpsApplyAutomatedEntraOpsUpdate` | No | `true` | Auto-update EntraOps module (used by `azure-pipelines-update.yml`) |
| `EntraOpsUpdatePat` | No | `***` | Personal Access Token for private upstream repos (used by `azure-pipelines-update.yml`) |

> **Note:** Optional variables that are left undefined default to empty. The pipelines use `eq(variables.<Name>, 'true')` conditions, so undefined variables are safely treated as `false`.

### 7. Authorize the service connection on first run

The first time a pipeline runs, ADO will display a banner during the run:

- **"This pipeline needs permission to access a resource before this run can continue"**.
- Click **View** and then **Permit** to authorize the service connection for this pipeline.

Alternatively, pre-authorize the pipeline:
1. Go to **Project Settings -> Service Connections**.
2. Select your `EntraOps-ServiceConnection`.
3. Under **Pipeline permissions**, click **+** and add both `azure-pipelines-pull.yml` and `azure-pipelines-update.yml`.

### 8. Grant the Build Service contributor permissions

Both pipelines commit generated JSON back to the repository. The Build Service identity needs write access:

1. Go to **Project Settings -> Repositories -> Security**.
2. Under **Users**, find **`<Project> Build Service (<Organization>)`** (e.g., `MyProject Build Service (my-organization)`).
3. Set **Contribute** to **Allow**.
4. If your `main` branch has branch policies, also set **Bypass policies when pushing** to **Allow** (or add the Build Service to the policy bypass list).

## Pipeline Files

| File | Purpose | Trigger |
|---|---|---|
| `azure-pipelines-pull.yml` | Collects privileged access data, classifies it, and commits JSON back to the repo | Scheduled (default: daily 09:30 UTC) + manual |
| `azure-pipelines-push.yml` | Ingests collected JSON to Log Analytics via DCR/DCE | Build completion after `azure-pipelines-pull` on `ado/main`, or manual |
| `azure-pipelines-update.yml` | Updates EntraOps module and resources from upstream | Scheduled (default: Wed 09:00 UTC) + manual |

## Log Analytics Ingestion Prerequisites

If you use `azure-pipelines-push.yml` to ingest data into a Log Analytics custom table, the following Azure resources must exist **before** the pipeline runs:

1. **Log Analytics Workspace**
2. **Custom Table** named `PrivilegedEAM_CL`
3. **Data Collection Endpoint (DCE)**
4. **Data Collection Rule (DCR)** with a data flow for `Custom-PrivilegedEAM_CL`
5. **RBAC roles** on the DCR resource group:
   - `Monitoring Metrics Publisher` (required for the Logs Ingestion API)
   - `Reader` (to read DCR/DCE metadata)

See the [Log Analytics Ingestion Setup section in README.md](./README.md#log-analytics-ingestion-setup) for detailed, step-by-step instructions on provisioning these resources and assigning roles.

> **Note:** The service principal used by the ADO Service Connection must have the roles above on the DCR resource group. `Log Analytics Contributor` is **not sufficient** for the Logs Ingestion API.

## Authentication Flow

ADO pipelines use the `AzurePowerShell@5` task with a WIF service connection. The task authenticates to Azure PowerShell automatically. EntraOps then uses `Connect-EntraOps -AuthenticationType FederatedCredentials`, which calls `Get-AzAccessToken` to acquire a Microsoft Graph token.

No secrets (client secrets or PATs) are required for the runtime authentication.

## Git Push from Pipelines

Both pipelines commit generated data back to the repository using `scripts/ado/Ado-GitPush.ps1`. This script uses the built-in `$(System.AccessToken)` with `persistCredentials: true` on the checkout step.

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

## Workbook Deployment

After data collection and ingestion are operational, deploy the EntraOps workbooks to your Microsoft Sentinel workspace. See the [Workbook Deployment section in README.md](./README.md#workbook-for-visualization-of-entraops-classification-data) for prerequisites and step-by-step instructions.
