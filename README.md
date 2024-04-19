# aws-kubectl Docker Image

This Docker image is designed to streamline operations on Amazon Web Services (AWS) and Kubernetes by bundling AWS CLI version 2 (`aws`) and the Kubernetes Command-Line Tool (`kubectl`). Based on Ubuntu 22.04, it includes all necessary dependencies such as `jq` for optimal functionality. This image is ideal for CI/CD pipelines, automation tasks, and environments that require seamless management of AWS resources and Kubernetes clusters.

🐳 You can find the Docker image on [Docker Hub](https://hub.docker.com/r/heyvaldemar/aws-kubectl).

# Features

- **Ubuntu 22.04**: Provides a stable and secure base for consistent performance.
- **AWS CLI v2**: Equipped with the latest capabilities for comprehensive AWS management.
- **kubectl**: Enables robust management of Kubernetes clusters, ensuring compatibility with the latest releases.
- **jq**: A lightweight and flexible command-line JSON processor, enhancing scripting capabilities.
- **Non-root User Configuration**: Enhances security by running commands as a non-root user.

# Use Cases

- **CI/CD**: Automates deployment and management tasks within continuous integration and deployment pipelines.
- **Local Development**: Tests AWS and Kubernetes commands locally to ensure scripts function correctly before deployment.
- **Automation Scripts**: Facilitates automatic interactions with AWS services and Kubernetes clusters, reducing manual input.

# Prerequisites

Ensure that `.aws` and `.kube` directories are present on your local machine:
- `.aws`: Contains your AWS credentials and configuration.
- `.kube`: Contains your Kubernetes configuration files.

# Running the Container

## For x86/Non-ARM Users

Run the container interactively, binding the local configuration directories without specifying a platform (default is x86):

```
docker run -it -v ~/.aws:/root/.aws -v ~/.kube:/root/.kube heyvaldemar/aws-kubectl bash
```

## For ARM/M1 Mac Users

To ensure compatibility on ARM-based M1 MacBooks, include the `--platform linux/amd64` flag when running the container:

```
docker run --platform linux/amd64 -it -v ~/.aws:/root/.aws -v ~/.kube:/root/.kube heyvaldemar/aws-kubectl bash
```

# Executing Commands Without Interactive Mode

## For x86/Non-ARM Users

Execute AWS CLI and kubectl commands directly:

- **List all S3 buckets**:
  ```
  docker run --rm -v ~/.aws:/root/.aws heyvaldemar/aws-kubectl aws s3 ls
  ```
- **Get nodes in your Kubernetes cluster**:
  ```
  docker run --rm -v ~/.kube:/root/.kube heyvaldemar/aws-kubectl kubectl get nodes
  ```

## For ARM/M1 Mac Users

Include the `--platform linux/amd64` flag when executing commands directly:

- **List all S3 buckets**:
  ```
  docker run --platform linux/amd64 --rm -v ~/.aws:/root/.aws heyvaldemar/aws-kubectl aws s3 ls
  ```
- **Get nodes in your Kubernetes cluster**:
  ```
  docker run --platform linux/amd64 --rm -v ~/.kube:/root/.kube heyvaldemar/aws-kubectl kubectl get nodes
  ```

# Specifying Kubernetes Version

To use a specific version of `kubectl` when building the Docker image, you can provide the version number through a build argument:

```
docker build --build-arg KUBE_VERSION=v1.29.3 -t heyvaldemar/aws-kubectl .
```

By default, the Dockerfile uses the latest available version of `kubectl`. If no version is specified, it will automatically fetch the latest stable release.

# Tags

- `latest`: Always incorporates the latest updates and enhancements.
- `<commit-sha>`: Version-specific tags linked to Git commit SHAs for precise version tracking and rollback.
- `vX.Y.Z`: Docker tags that correspond to specific versions of Kubernetes, allowing users to select a specific version if required.

# Security

The image undergoes regular vulnerability scanning to ensure it remains secure and up-to-date with the latest security patches. This proactive approach helps maintain the integrity and security of your deployments.

# Author

I’m Vladimir Mikhalev, the [Docker Captain](https://www.docker.com/captains/vladimir-mikhalev/), but my friends can call me Valdemar.

🌐 My [website](https://www.heyvaldemar.com/) with detailed IT guides\
🎬 Follow me on [YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1)\
🐦 Follow me on [Twitter](https://twitter.com/heyValdemar)\
🎨 Follow me on [Instagram](https://www.instagram.com/heyvaldemar/)\
🧵 Follow me on [Threads](https://www.threads.net/@heyvaldemar)\
🐘 Follow me on [Mastodon](https://mastodon.social/@heyvaldemar)\
🧊 Follow me on [Bluesky](https://bsky.app/profile/heyvaldemar.bsky.social)\
🎸 Follow me on [Facebook](https://www.facebook.com/heyValdemarFB/)\
🎥 Follow me on [TikTok](https://www.tiktok.com/@heyvaldemar)\
💻 Follow me on [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)\
🐈 Follow me on [GitHub](https://github.com/heyvaldemar)

# Communication

👾 Chat with IT pros on [Discord](https://discord.gg/AJQGCCBcqf)\
📧 Reach me at ask@sre.gg

# Give Thanks

💎 Support on [GitHub](https://github.com/sponsors/heyValdemar)\
🏆 Support on [Patreon](https://www.patreon.com/heyValdemar)\
🥤 Support on [BuyMeaCoffee](https://www.buymeacoffee.com/heyValdemar)\
🍪 Support on [Ko-fi](https://ko-fi.com/heyValdemar)\
💖 Support on [PayPal](https://www.paypal.com/paypalme/heyValdemarCOM)
