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
