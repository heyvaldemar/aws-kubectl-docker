# aws-kubectl Docker Image

This image streamlines work with Amazon Web Services (AWS) and Kubernetes by bundling **AWS CLI v2** (`aws`) and **kubectl** on **Ubuntu 24.04**. It also includes `jq`, `curl`, `unzip`, and `envsubst` (from `gettext-base`). Perfect for CI/CD steps, automation, and reproducible local scripting.

🐳 Docker Hub: [heyvaldemar/aws-kubectl](https://hub.docker.com/r/heyvaldemar/aws-kubectl)

## Features

- **Ubuntu 24.04** base for stability.
- **AWS CLI v2** for full AWS management.
- **kubectl** (pin a specific version or use the latest stable at build time).
- `jq`, `curl`, `unzip`, `envsubst`, and `ca-certificates` preinstalled.
- **Checksum verification** for `kubectl` during build.
- **Multi-arch ready** (amd64/arm64) when built/pushed with `buildx`.

> Default user is **root**. See **Run as non-root (optional)** for a hardened runtime.

## Use Cases

- **CI/CD**: run `aws`/`kubectl` steps in pipelines.
- **Local dev**: test commands before rolling into automation.
- **Scripting**: consistent, portable tooling wrapper.

## Prerequisites

- `~/.aws` – AWS credentials/config (`credentials`, `config`)
- `~/.kube` – kubeconfig(s)

## Running the Container

Interactive shell with both configs:
```bash
docker run -it \
  -v ~/.aws:/root/.aws \
  -v ~/.kube:/root/.kube \
  heyvaldemar/aws-kubectl bash
```

If you pulled an **amd64-only** tag on an ARM/M-series Mac:

```bash
docker run --platform linux/amd64 -it \
  -v ~/.aws:/root/.aws \
  -v ~/.kube:/root/.kube \
  heyvaldemar/aws-kubectl bash
```

### Execute commands directly (no shell)

```bash
# List S3 buckets
docker run --rm -v ~/.aws:/root/.aws \
  heyvaldemar/aws-kubectl aws s3 ls

# Get Kubernetes nodes
docker run --rm -v ~/.kube:/root/.kube \
  heyvaldemar/aws-kubectl kubectl get nodes
```

## Build Instructions

### Local single-arch (dev)

```bash
# From the folder with the Dockerfile
docker build -t aws-kubectl:local .
```

### Pin a specific kubectl

```bash
docker build --build-arg KUBE_VERSION=v1.30.6 \
  -t aws-kubectl:local .
```

If `KUBE_VERSION` is omitted, the build fetches the **latest stable** from `dl.k8s.io`.

### Multi-arch build & push (amd64 + arm64)

```bash
docker buildx create --name x --use || docker buildx use x

# Generic tag (no OS name in the tag)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t heyvaldemar/aws-kubectl:latest \
  --push .

# Or pin kubectl in a tag users can reason about
KUBE_VERSION=v1.30.6
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg KUBE_VERSION=$KUBE_VERSION \
  -t heyvaldemar/aws-kubectl:kube-$KUBE_VERSION \
  --push .
```

Verify:

```bash
docker buildx imagetools inspect heyvaldemar/aws-kubectl:latest
```

> Optional supply-chain flags (if you want SBOM/provenance):
> `--sbom=true --provenance=true`

## Local Build & Test (using the repo script)

This repo includes `scripts/smoke-test.sh` to validate the tools in the image.

1. **Build locally**

```bash
docker build -t aws-kubectl:local .
```

2. **Run the smoke test**

```bash
chmod +x scripts/smoke-test.sh
./scripts/smoke-test.sh                # defaults to aws-kubectl:local
./scripts/smoke-test.sh your/tag:dev   # test any tag you pass
```

The script checks:

- OS/arch
- Versions: AWS CLI, kubectl (client), jq, envsubst, curl, unzip
- Binary locations & CA bundle
- HTTPS reachability (header-only)
- (Optional) AWS STS + `kubectl` cluster calls if you mount `~/.aws` / `~/.kube`

## Quick Verification (manual one-liners)

```bash
IMG=aws-kubectl:local

# OS/arch
docker run --rm $IMG sh -lc 'uname -a; echo -n "Arch: "; uname -m'

# Core tools & versions
docker run --rm $IMG aws --version
docker run --rm $IMG kubectl version --client --output=yaml
docker run --rm $IMG jq --version
docker run --rm $IMG envsubst --version || true
docker run --rm $IMG sh -lc 'curl --version | head -n1'
docker run --rm $IMG sh -lc 'unzip -v | head -n2'

# Binaries present where expected
docker run --rm $IMG sh -lc 'ls -l /usr/local/bin/kubectl; which aws jq envsubst curl unzip'

# CA bundle present + HTTPS sanity
docker run --rm $IMG sh -lc 'ls -lh /etc/ssl/certs/ca-certificates.crt || true'
docker run --rm $IMG sh -lc 'curl -fsSI -o /dev/null -w "HTTPS OK (%{http_code})\n" https://kubernetes.io'
```

### Optional “real” checks (with mounted config)

```bash
# AWS identity (requires valid creds)
docker run --rm -v ~/.aws:/root/.aws aws-kubectl:local aws sts get-caller-identity

# Current k8s context & nodes (requires valid kubeconfig)
docker run --rm -v ~/.kube:/root/.kube aws-kubectl:local kubectl config current-context
docker run --rm -v ~/.kube:/root/.kube aws-kubectl:local kubectl get nodes -o wide
```

## Tagging / Versioning Policy

To avoid OS-specific tags in docs and keep usage predictable:

- `latest` – rolling, multi-arch build with current defaults.
- `kube-<X.Y.Z>` – pinned `kubectl` version (e.g., `kube-1.30.6`).
- `<commit-sha>` – immutable builds tied to the Git commit (CI-friendly).
- Optional **minor** rolling tag:

  - `kube-<X.Y>` → floats to the newest patch for that minor (e.g., `kube-1.30` → `1.30.6`)

> Tip: match `kubectl` to your cluster’s version skew policy (n-1 / n / n+1).

## Security Notes

- `kubectl` binaries are **checksum-verified** during build.
- APT is minimal (`--no-install-recommends`) and lists are cleaned.
- Consider running as **non-root** and pinning `KUBE_VERSION` in CI for reproducibility.

## Run as non-root (optional)

```bash
# Map host user, set HOME, and mount configs under that HOME
docker run --rm -it \
  --user $(id -u):$(id -g) \
  -e HOME=/home/dev \
  -v ~/.aws:/home/dev/.aws \
  -v ~/.kube:/home/dev/.kube \
  -w /home/dev \
  heyvaldemar/aws-kubectl bash
```

## About

I'm Vladimir Mikhalev, an [AWS Community Builder](https://builder.aws.com/connect/community/community-builders), [HashiCorp Ambassador](https://www.hashicorp.com/en/ambassador/directory), [Snyk Ambassador](https://snyk.io/snyk-ambassadors/directory/), [Cypress Ambassador](https://www.cypress.io/ambassadors), [GitKraken Ambassador](https://www.gitkraken.com/meet-the-gitkraken-ambassadors), [Notion Ambassador](https://www.notion.so/notion/Notion-Ambassador-Program-45448f9b8e704c7bab254bd505c4717c), and [Docker Captain](https://www.docker.com/captains/vladimir-mikhalev/), but my friends can call me Valdemar.

💾 I've been in the IT game for over 20 years, cutting my teeth with some big names like IBM, Thales, and Amazon. These days, I wear the hat of a DevOps Engineer and Team Lead, but what really gets me going is Docker and container technology I'm kind of obsessed!

💛 I have my own IT blog, where I've built a community of DevOps enthusiasts who share my love for all things Docker, containers, and IT technologies in general. And to make sure everyone can jump on this awesome DevOps train, I write super detailed guides (seriously, they're foolproof!) that help even newbies deploy and manage complex IT solutions.

🚀 My dream is to empower every single person in the DevOps community to squeeze every last drop of potential out of Docker and container tech.

🐳 As a [Docker Captain](https://www.docker.com/captains/vladimir-mikhalev/), I'm stoked to share my knowledge, experiences, and a good dose of passion for the tech. My aim is to encourage learning, innovation, and growth, and to inspire the next generation of IT whizz-kids to push Docker and container tech to its limits.

Let's do this together!

## 2D Portfolio

🕹️ Click into [sre.gg](https://www.sre.gg/) - my virtual space is a 2D pixel-art portfolio inviting you to interact with elements that encapsulate the milestones of my DevOps career.

## Learn with Me

🎓 Check out my [courses on Udemy](https://www.udemy.com/user/heyvaldemar/) - built for engineers who want real skills, not just theory.
From Docker and Kubernetes to DevOps fundamentals, everything is hands-on and based on real-world scenarios.

🔑 Every course is created from scratch by me - no fluff, no shortcuts. Whether you're just starting out or leveling up, you'll get practical experience you can actually use.

## Patreon Exclusives

🏆 Join my [Patreon](https://www.patreon.com/heyvaldemar) and dive deep into the world of Docker and DevOps with exclusive content tailored for IT enthusiasts and professionals. As your experienced guide, I offer a range of membership tiers designed to suit everyone from newbies to IT experts.

## Tools I Personally Trust

If you're building things, breaking things, and trying to keep your digital life a little saner (like every good DevOps engineer), these are two tools that I trust and use daily:

🛸 [Proton VPN](https://go.getproton.me/SH1e9) - My shield on the internet. It keeps your Wi-Fi secure, hides your IP, and blocks those creepy trackers. Even if I'm hacking away on free café Wi-Fi, I know I'm safe.

🔑 [Proton Pass](https://go.getproton.me/SH1dl) - My password vault. Proper on-device encryption, 2FA codes, logins, secrets - all mine and only mine. No compromises.

_These are partner links - you won't pay a cent more, but you'll be supporting DevOps Compass. Thanks a ton - it helps me keep this compass pointing the right way 💜_

## Gear & Books I Trust

📕 [Essential DevOps books](https://kit.co/heyvaldemar/essential-devops-books)  
🖥️ [Studio streaming & recording kit](https://kit.co/heyvaldemar/my-studio-streaming-and-recording-kit)  
📡 [Streaming starter kit](https://kit.co/heyvaldemar/streaming-starter-kit)

## Social Channels

🎬 [YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1)  
🐦 [X (Twitter)](https://x.com/heyvaldemar)  
🎨 [Instagram](https://www.instagram.com/heyvaldemar/)  
🐘 [Mastodon](https://mastodon.social/@heyvaldemar)  
🧵 [Threads](https://www.threads.net/@heyvaldemar)  
🎸 [Facebook](https://www.facebook.com/heyvaldemarFB/)  
🦋 [Bluesky](https://bsky.app/profile/heyvaldemar.com)  
🎥 [TikTok](https://www.tiktok.com/@heyvaldemar)  
💻 [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)  
📣 [daily.dev Squad](https://app.daily.dev/squads/devopscompass)  
✈️ [Telegram](https://t.me/heyvaldemar)  
🐈 [GitHub](https://github.com/heyvaldemar)

## Community of IT Experts

👾 [Discord](https://devops.army/)

## Refill My Coffee Supplies

💖 [PayPal](https://www.paypal.com/paypalme/heyvaldemarcom)  
🏆 [Patreon](https://www.patreon.com/heyvaldemar)  
🥤 [BuyMeaCoffee](https://www.buymeacoffee.com/heyvaldemar)  
🍪 [Ko-fi](https://ko-fi.com/heyvaldemar)  
💎 [GitHub](https://github.com/sponsors/heyvaldemar)  
⚡ [Telegram Boost](https://t.me/heyvaldemar?boost)

🌟 Bitcoin (BTC): bc1q2fq0k2lvdythdrj4ep20metjwnjuf7wccpckxc  
🔹 Ethereum (ETH): 0x76C936F9366Fad39769CA5285b0Af1d975adacB8  
🪙 Binance Coin (BNB): bnb1xnn6gg63lr2dgufngfr0lkq39kz8qltjt2v2g6  
💠 Litecoin (LTC): LMGrhx8Jsx73h1pWY9FE8GB46nBytjvz8g

<div align="center">

### Show some 💜 by starring some of the [repositories](https://github.com/heyValdemar?tab=repositories)!

![octocat](https://user-images.githubusercontent.com/10498744/210113490-e2fad07f-4488-4da8-a656-b9abbdd8cb26.gif)

</div>

![footer](https://user-images.githubusercontent.com/10498744/210157572-1fca0242-8af2-46a6-bfa3-666ffd40ebde.svg)
