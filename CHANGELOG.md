# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

### Removed
- `.github/FUNDING.yml` — sponsor discovery moves to heyvaldemar.com.
- Legacy README sections: first-person bio, paid-membership tier references, affiliate
  links (VPN/password-manager partner links, Udemy), `kit.co` gear shortcuts,
  cryptocurrency wallet addresses, Discord invite, octocat gif, and footer SVG.

### Security
- `kubectl` binaries continue to be verified against the upstream SHA-256 checksum
  published at `dl.k8s.io` before installation. Verification now happens inside the
  isolated builder stage.

### Backwards compatibility
- No breaking changes for users pulling `heyvaldemar/aws-kubectl:latest`. The image name,
  default `latest` tag, default `CMD ["bash"]`, default `root` user, and full toolchain
  contract (`aws`, `kubectl`, `jq`, `envsubst`, `curl`, `unzip`, `ca-certificates`) are
  unchanged.

[Unreleased]: https://github.com/heyvaldemar/aws-kubectl-docker/commits/main
