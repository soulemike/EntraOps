# Data Handling and Privacy

EntraOps is source code and does not provide a hosted EntraOps service. By default, it runs in the operator's local environment, automation worker, or GitHub Actions environment selected by the operator.

## Data Processed

Depending on enabled features, EntraOps can read and generate tenant-specific data such as tenant and object identifiers, display names, UPNs, group membership, role assignments, Conditional Access configuration, Intune configuration, Tenant Governance snapshots, and classification results. This data can be sensitive and may include personal data.

## Operator-Controlled Storage and Transfers

The operator controls whether generated data is stored locally, committed to a private GitHub repository, included in static reporting bundles, or sent to optional destinations such as Microsoft Sentinel, Log Analytics, or WatchLists. EntraOps does not include product telemetry.

EntraOps workflows refuse to commit generated tenant data to public repositories. This control does not replace the operator's responsibility to review repository visibility, access controls, retention, exports, artifacts, logs, backups, and configured Azure destinations.

Before sharing a checkout or publishing report files, remove tenant-specific reporting data with `Remove-EntraOpsReportingData` and review all generated content. Treat configuration files, logs, reports, and exported JSON as potentially sensitive.

## Third-Party Services

When EntraOps is used with Microsoft Graph, Azure, GitHub, Microsoft Sentinel, Log Analytics, BloodHound, or other services, their terms and privacy policies apply to data sent to those services. Operators are responsible for confirming that their use complies with their organization's privacy, security, retention, and data-residency requirements.

This document describes the repository's intended behavior and is not legal advice.
