# Security Policy

## Supported Versions

Security fixes are provided for the latest released version only. Deployments that pin
`AutomatedEntraOpsUpdate.Branch` to an older tag should update to the latest release before
reporting an issue.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |
| `main` between releases | Best effort |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue in this project, **please do not open a public GitHub issue**.

### How to Report

Send details to the repository maintainers via mail to: security@entraops.com

You can expect an acknowledgement within 5 business days. This is a community project without a
commercial support agreement, so remediation timelines depend on severity and maintainer availability.

### What to Include

To help us triage and resolve the issue quickly, please include:

- A clear description of the vulnerability
- Steps to reproduce the issue
- The potential impact and attack scenarios
- Any suggested mitigations or fixes (optional)
- Your name/handle if you'd like to be credited in the changelog

## Scope

This security policy applies to the source code and scripts maintained in this repository. It does **not** cover:

- Third-party dependencies (report those upstream)
- Your own infrastructure or Azure tenant configuration
- Issues arising from misconfiguration outside the scope of this project

## Trust model and supply chain

Operators should be aware of the external content EntraOps trusts at runtime:

- **Classification templates** are downloaded from [`Cloud-Architekt/AzurePrivilegedIAM`](https://github.com/Cloud-Architekt/AzurePrivilegedIAM) by `Update-EntraOpsClassificationFiles`, by default from the mutable `main` branch. These files decide which roles and actions are treated as Control Plane, so anyone able to modify that repository can influence tiering results. Downloads are validated as well-formed JSON, but there is no signature or hash pinning. Pin `AutomatedClassificationUpdate` to a release tag if you require reproducible classification.
- **Reference data** is retrieved from `merill/microsoft-info` and `merill/graphpermissions.github.io` (third-party), `MicrosoftDocs/entra-docs`, and `Cloud-Architekt/AzureSentinel`, all from mutable `main` refs.
- **Module self-update** (`Update-EntraOps`) replaces the module, documentation, report and workflow files from a Cloud-Architekt distribution repository declared in `EntraOpsUpdateContract.json` (`EntraOps`, public, no credentials; `EntraOps-Insiders`, private, `EntraOpsUpdatePat` secret). It is **disabled by default**. The `Update-EntraOps` workflow resolves an immutable commit without executing candidate code, validates the candidate in a separate job that has no write token, no secrets, and a sparse checkout limited to the trusted validator scripts (so candidate tests cannot read generated tenant data), and applies it with trusted workflow code that never imports the downloaded module. In `PullRequest` mode the result is pushed to an update branch with a commit status for the validation run; no workflow is dispatched on that branch because its workflow files are candidate-controlled, so candidate workflows only run after a human merges the pull request. `DirectPush` skips that review. Generated configurations track `main`; a warning is emitted for that mutable ref, and operators who require reproducibility should use a release tag or full commit SHA instead.
- **Generated tenant data** (object IDs, UPNs, role assignments, policy configuration) must stay in a **private** repository. The `Git-Push` action and the reporting workflow both refuse to commit or publish this data when the repository is public.

## Acknowledgements

We appreciate the efforts of security researchers and community members who responsibly disclose vulnerabilities. Contributors who report valid issues will be credited in the changelog.
