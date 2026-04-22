# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- OpenSSF Scorecard analysis workflow (`.github/workflows/scorecard.yml`).
  Runs weekly on Tuesdays at 06:00 UTC (after the Monday rebuild and cleanup
  workflows), on every push to `main`, and on branch-protection-rule changes.
  Publishes results to the public OpenSSF API (scorecard.dev viewer) and
  uploads SARIF to the GitHub Security tab. README badge added next to the
  license badge; the badge populates automatically after the first run
  completes on `main`.
- Weekly `Docker Hub Tag Cleanup` GitHub Actions workflow
  (`.github/workflows/dockerhub-tag-cleanup.yml`). Deletes `sha-*` image tags
  older than 90 days on Mondays at 07:00 UTC (one hour after the publish
  rebuild), preventing unbounded tag accumulation on Docker Hub. Scheduled
  runs auto-delete; manual `workflow_dispatch` defaults to dry-run for safety.
- `scripts/cleanup-legacy-tags.sh` — one-shot local cleanup for legacy
  long-SHA (40-char hex) tags from the pre-Phase-1 CI era. Dry-run by default;
  `--execute` requires typed `DELETE` confirmation. The 19 target tags are
  hardcoded in the script so the operation is auditable in version control.

### Removed
- 19 legacy long-SHA image tags from Docker Hub (ranging from ~5 months to
  ~2 years old, all from the pre-Phase-1 CI era). These were never documented
  as stable pins and carried accumulated CVE noise. Current-generation
  consumers use semver tags (`:2.0.0`, `:2.0`, `:2`), floating channels
  (`:latest`, `:edge`, `:v1-maintenance`), the `kube-vX.Y.Z` pin, or short
  `sha-*` tags for the last 90 days of builds. Cosign `.sig` tags were
  preserved.

## [2.0.0] - 2026-04-21

### BREAKING CHANGES
- Container now runs as non-root user (UID 10001, GID 0) by default. Users who depend
  on running as root must override with `--user 0:0`. Volume mounts may require
  adjusted file ownership or `--user "$(id -u):0"` so the container can read the
  mounted host files. See the README "Breaking Changes in v2.0" section for the full
  migration guide.
- Default `WORKDIR` changed from `/` to `/home/app`. Scripts that assumed a specific
  working directory should set it explicitly via `-w` or `WORKDIR`.
- Default mount paths for AWS and kube configs documented as `/home/app/.aws` and
  `/home/app/.kube` (previously `/root/.aws` and `/root/.kube`). The old paths still
  work if you mount there **and** override with `--user 0:0`, but are no longer the
  documented contract.

### Added
- Non-root runtime user `app` (UID 10001, primary GID 0) created via `useradd
  --system`. Home directory `/home/app` is owned by UID 10001, GID 0 with group-write
  permissions (`chmod g=u`) for OpenShift SCC `restricted-v2` compatibility.
- `HOME=/home/app` set via `ENV` so kubectl and AWS CLI cache directories
  (`~/.kube/cache`, `~/.aws/cli/cache`, `~/.aws/sso/cache`) resolve correctly for
  users who override `--user`.
- Compatibility with OpenShift Security Context Constraints (SCC) `restricted-v2`
  profile and Kubernetes `restricted` Pod Security Standard.
- README "Breaking Changes in v2.0" section at the top of the document, with Docker
  and Kubernetes migration examples and the `v1-maintenance` escape hatch.
- README "Run as root (override)" section documenting `--user 0:0` for workflows that
  need root inside the container.
- Workflow tag patterns `type=semver,pattern={{major}}` (produces `2`) and
  `type=ref,event=tag` (produces `v2.0.0`), so consumers can pin at three granularities:
  `heyvaldemar/aws-kubectl:2`, `:2.0`, or `:2.0.0`.
- Multi-stage `Dockerfile` with a dedicated `builder` stage. Build-only intermediate
  artefacts (the downloaded AWS CLI zip, its extracted tree, the kubectl archive and
  its checksum file) no longer pollute the final image.
- `# syntax=docker/dockerfile:1.7` directive for modern BuildKit features.
- Full OCI image labels: `org.opencontainers.image.{title,description,authors,vendor,source,documentation,url,licenses,revision,created}`
  plus `io.heyvaldemar.kubectl.version`.
- Resolved kubectl release is written to `/etc/kube-version` inside the image for runtime
  inspection and drift detection.
- Build arguments `VCS_REF` and `BUILD_DATE` stamped into image labels on every build.
- `.hadolint.yaml` configuration (with a documented exception for `DL3008`; weekly rebuilds
  pick up Ubuntu security updates).
- `CHANGELOG.md` following the Keep a Changelog format.
- README badges for Docker Pulls, image size, build status, and license.
- README "Supply chain" section describing the Phase 1 hardening work and teasing Phase 2
  (Cosign signatures, SBOM attestations, SLSA provenance) and Phase 3 (non-root runtime).
- GitHub Actions workflow `publish.yml` replacing the previous single-job pipeline, now
  with a separate `lint` job (`hadolint` + `shellcheck`) that blocks the build, metadata
  via `docker/metadata-action`, multi-arch build (`linux/amd64`, `linux/arm64`),
  GitHub Actions cache (`type=gha,mode=max`), weekly rebuild schedule (Mondays 06:00 UTC),
  pull-request dry-run builds (`push=false`), and a Docker Hub description sync step on
  pushes to `main`.
- All third-party GitHub Actions pinned to a commit SHA with a `# vX` version comment.
- Cosign keyless image signatures (Sigstore OIDC) on every published digest.
- SBOM attached to every published image (SPDX format via BuildKit).
- SLSA build provenance attestation (`provenance: mode=max`) on every published image.
- GitHub native build provenance attestation via `actions/attest-build-provenance`.
- Trivy vulnerability scan on every published image, uploading SARIF to the GitHub
  Security tab (CRITICAL and HIGH severities, fixable CVEs only).
- `SECURITY.md` — vulnerability disclosure policy and supply-chain verification
  instructions.
- `LICENSE` — canonical MIT license text at repo root.
- `.dockerignore` — excludes repo metadata from the build context.
- README "Upgrade Notes" section — flags the `v2.0` non-root breaking change on the
  horizon.
- README "Verifying signatures" subsection — `cosign verify` invocation for the
  published image.

### Changed
- Default `USER` directive changed from root (implicit) to `10001:0`.
- Default `WORKDIR` changed to `/home/app`.
- README volume-mount examples updated to mount under `/home/app/.aws` and
  `/home/app/.kube` with `--user "$(id -u):0"` so host files remain readable by the
  container's non-root user.
- README `## Run as non-root (optional)` section renamed to `## Run as root
  (override)` and rewritten — non-root is now the default, the escape hatch is root.
- `scripts/smoke-test.sh` now fails hard on missing tools (no `|| true` fallbacks for core
  checks), asserts that `/etc/kube-version` matches `kubectl version --client`, and prefers
  `sh -c` over `bash -lc`.
- README "Build Instructions" section documents the new `VCS_REF` and `BUILD_DATE` build
  arguments and recommends stamping them for release builds.
- Workflow triggers expanded from "push to main" only to include pull requests, semver
  tags `v*.*.*`, a weekly cron, and manual dispatch.
- Workflow permissions tightened to the least-privilege set required for each action
  (`contents: read`, `packages: write`, `id-token: write`, `attestations: write`,
  `security-events: write`).
- Workflow concurrency is keyed per-ref; in-progress runs are cancelled only for pull
  requests so branch/tag builds always complete.
- CI: explicit `flavor: latest=false` in metadata-action — `:latest` now only bumps on
  main pushes, not on semver tag pushes.
- `unzip` is installed into the final image via an explicit multi-stage `COPY`/install
  path rather than side-effect-ing from the AWS CLI extraction step, but remains present
  in the runtime toolchain. Retained **for backwards compatibility** with users of
  `heyvaldemar/aws-kubectl:latest` who rely on `unzip` for ad-hoc zip extraction in CI
  pipelines; removal is deferred to a future major release after a deprecation notice.
- Dockerfile base image pinned by digest (`ubuntu:24.04@sha256:…`) for reproducible,
  auditable builds. Dependabot's `docker` ecosystem tracks upstream digest bumps weekly.
- CI permissions narrowed from workflow-scope to per-job least-privilege. `lint`:
  `contents: read`; `build`: `contents: read`, `packages: write`, `id-token: write`,
  `attestations: write`, `security-events: write`; `scan-trivy`: `contents: read`,
  `security-events: write`; `dockerhub-description`: default (empty) permissions.
- CI jobs and the long-running build step gained explicit `timeout-minutes` ceilings
  (`lint: 5`, `build: 30`, `Build and push` step: `20`, `scan-trivy: 10`,
  `dockerhub-description: 5`) replacing the GitHub default of 360 minutes.
- Dependabot groups minor/patch `github-actions` and `docker` ecosystem bumps into a
  single PR each week; major bumps continue to open individual PRs.
- Docs: unified About footer with canonical block (reusable across heyvaldemar public
  repos); Docker Hub short-description trimmed from 109 bytes to 82 bytes so it stops
  being silently truncated by Docker Hub.
- CI: `actions/attest-build-provenance` no longer pushes attestations as OCI referrers
  to Docker Hub (unreliable credential handoff); attestations remain available via
  GitHub Attestations storage at
  `https://github.com/heyvaldemar/aws-kubectl-docker/attestations`.

### Removed
- `.github/FUNDING.yml` — sponsor discovery moves to heyvaldemar.com.
- Legacy README sections: first-person bio, paid-membership tier references, affiliate
  links (VPN/password-manager partner links, Udemy), `kit.co` gear shortcuts,
  cryptocurrency wallet addresses, Discord invite, octocat gif, and footer SVG.

### Security
- `kubectl` binaries continue to be verified against the upstream SHA-256 checksum
  published at `dl.k8s.io` before installation. Verification now happens inside the
  isolated builder stage.
- Non-root runtime by default removes an implicit privilege-escalation risk in
  workflows that previously inherited root from `:latest`.

### Migration
- Existing `v1.x` users: pin to `heyvaldemar/aws-kubectl:v1-maintenance` for 90 days
  (through **2026-07-20**) of security updates while migrating. After that date the
  `v1-maintenance` tag is frozen — no further rebuilds.
- Most CI workflows (no volume mount, one-shot `aws`/`kubectl` commands) will work
  unchanged.
- Docker volume-mount workflows: add `--user "$(id -u):0"` and change the mount path
  from `/root/.aws` → `/home/app/.aws` (same for `.kube`).
- Kubernetes workloads: set `securityContext.runAsUser: 10001`,
  `runAsGroup: 0`, `fsGroup: 0`. See the README "Breaking Changes in v2.0" section
  for the full spec.

[Unreleased]: https://github.com/heyvaldemar/aws-kubectl-docker/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/heyvaldemar/aws-kubectl-docker/releases/tag/v2.0.0
