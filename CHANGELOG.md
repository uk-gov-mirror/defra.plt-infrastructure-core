# Changelog

All notable changes to this repository should be documented in this file.

## [1.1.0] - 2026-04-14

### Added

- **`additionalDnsZonesToLink`** — Optional. Supply a JSON string listing private DNS zones that should be **linked to the hub networks** during platform deploy (in addition to zones the framework already manages). Use a JSON array of objects with **`PrivateDnsZoneName`** and **`ResourceGroupName`** (property names are case-insensitive). You may still pass a legacy array of **zone name strings**; those are resolved using your region’s DNS resource group from the existing regional mapping. Omit the variable, set it to `[]`, or leave it empty to skip this step entirely.
- **Container Apps–ready networking** — The shared virtual network template can delegate the appropriate subnet to **`Microsoft.App/environments`**, so that subnet can host Azure Container Apps environments without a separate manual delegation step.

### Changed

- **Triggered CCoE pipelines** (private DNS zone linking and VNet peering) now report success and failure more reliably in Azure Pipelines: build completion is detected in a way that tolerates different API casing, and the job exit code reflects a failed remote run when `TF_BUILD` is set (including when the agent reports `True` rather than `true`). When a triggered **external** pipeline run does **not** succeed, the framework now downloads that run’s logs, bundles them, and **publishes them to your job as a pipeline artifact** (so you can open the parent run in Azure DevOps and inspect the child logs without switching projects first).

## [1.0.0] - 2026-03-25

### Added

- Initial revision.
