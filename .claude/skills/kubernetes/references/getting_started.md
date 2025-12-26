# Kubernetes - Getting Started

**Pages:** 43

---

## Creating Highly Available Clusters with kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/

**Contents:**
- Creating Highly Available Clusters with kubeadm
    - Caution:
- Before you begin
  - Container images
  - Command line interface
- First steps for both methods
  - Create load balancer for kube-apiserver
    - Note:
- Stacked control plane and etcd nodes
  - Steps for the first control plane node

This page explains two different approaches to setting up a highly available Kubernetes cluster using kubeadm:

Before proceeding, you should carefully consider which approach best meets the needs of your applications and environment. Options for Highly Available topology outlines the advantages and disadvantages of each.

If you encounter issues with setting up the HA cluster, please report these in the kubeadm issue tracker.

See also the upgrade documentation.

The prerequisites depend on which topology you have selected for your cluster's control plane:

You need:Three or more machines that meet kubeadm's minimum requirements for the control-plane nodes. Having an odd number of control plane nodes can help with leader selection in the case of machine or zone failure.including a container runtime, already set up and workingThree or more machines that meet kubeadm's minimum requirements for the workersincluding a container runtime, already set up and workingFull network connectivity between all machines in the cluster (public or private network)Superuser privileges on all machines using sudoYou can use a different tool; this guide uses sudo in the examples.SSH access from one device to all nodes in the systemkubeadm and kubelet already installed on all machines.See Stacked etcd topology for context.

See Stacked etcd topology for context.

You need:Three or more machines that meet kubeadm's minimum requirements for the control-plane nodes. Having an odd number of control plane nodes can help with leader selection in the case of machine or zone failure.including a container runtime, already set up and workingThree or more machines that meet kubeadm's minimum requirements for the workersincluding a container runtime, already set up and workingFull network connectivity between all machines in the cluster (public or private network)Superuser privileges on all machines using sudoYou can use a different tool; this guide uses sudo in the examples.SSH access from one device to all nodes in the systemkubeadm and kubelet already installed on all machines.And you also need:Three or more additional machines, that will become etcd cluster members. Having an odd number of members in the etcd cluster is a requirement for achieving optimal voting quorum.These machines again need to have kubeadm and kubelet installed.These machines also require a container runtime, that is already set up and working.See External etcd topology for context.

See External etcd topology for 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc -zv -w 2 <LOAD_BALANCER_IP> <PORT>
```

Example 2 (sh):
```sh
sudo kubeadm init --control-plane-endpoint "LOAD_BALANCER_DNS:LOAD_BALANCER_PORT" --upload-certs
```

Example 3 (sh):
```sh
...
You can now join any number of control-plane node by running the following command on each as a root:
    kubeadm join 192.168.0.200:6443 --token 9vr73a.a8uxyaju799qwdjv --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866 --control-plane --certificate-key f8902e114ef118304e561c3ecd4d0b543adc226b7a07f675f56564185ffe0c07

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use kubeadm init phase upload-certs to reload c
...
```

Example 4 (sh):
```sh
sudo kubeadm init phase upload-certs --upload-certs
```

---

## Creating a cluster with kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/

**Contents:**
- Creating a cluster with kubeadm
- Before you begin
    - Note:
- Objectives
- Instructions
  - Preparing the hosts
    - Component installation
    - Note:
    - Network setup
    - Note:

Using kubeadm, you can create a minimum viable Kubernetes cluster that conforms to best practices. In fact, you can use kubeadm to set up a cluster that will pass the Kubernetes Conformance tests. kubeadm also supports other cluster lifecycle functions, such as bootstrap tokens and cluster upgrades.

The kubeadm tool is good if you need:

You can install and use kubeadm on various machines: your laptop, a set of cloud servers, a Raspberry Pi, and more. Whether you're deploying into the cloud or on-premises, you can integrate kubeadm into provisioning systems such as Ansible or Terraform.

To follow this guide, you need:

You also need to use a version of kubeadm that can deploy the version of Kubernetes that you want to use in your new cluster.

Kubernetes' version and version skew support policy applies to kubeadm as well as to Kubernetes overall. Check that policy to learn about what versions of Kubernetes and kubeadm are supported. This page is written for Kubernetes v1.34.

The kubeadm tool's overall feature state is General Availability (GA). Some sub-features are still under active development. The implementation of creating the cluster may change slightly as the tool evolves, but the overall implementation should be pretty stable.

Install a container runtime and kubeadm on all the hosts. For detailed instructions and other prerequisites, see Installing kubeadm.

If you have already installed kubeadm, see the first two steps of the Upgrading Linux nodes document for instructions on how to upgrade kubeadm.

When you upgrade, the kubelet restarts every few seconds as it waits in a crashloop for kubeadm to tell it what to do. This crashloop is expected and normal. After you initialize your control-plane, the kubelet runs normally.

kubeadm similarly to other Kubernetes components tries to find a usable IP on the network interfaces associated with a default gateway on a host. Such an IP is then used for the advertising and/or listening performed by a component.

To find out what this IP is on a Linux host you can use:

Kubernetes components do not accept custom network interface as an option, therefore a custom IP address must be passed as a flag to all components instances that need such a custom configuration.

To configure the API server advertise address for control plane nodes created with both init and join, the flag --apiserver-advertise-address can be used. Preferably, this option can be set in the kubeadm API as InitConfiguration.localAPIEndpoi

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
ip route show # Look for a line starting with "default via"
```

Example 2 (bash):
```bash
kubeadm init <args>
```

Example 3 (unknown):
```unknown
192.168.0.102 cluster-endpoint
```

Example 4 (none):
```none
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a Pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  /docs/concepts/cluster-administration/addons/

You can now join any number of machines by running the following on each node
as root:

  kubeadm join <control-plane-host>:<control-plane-port> --tok
...
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#operating-system-version-check-0

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Installing Kubernetes with deployment tools

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/

**Contents:**
- Installing Kubernetes with deployment tools
- Feedback

There are many methods and tools for setting up your own production Kubernetes cluster. For example:

Cluster API: A Kubernetes sub-project focused on providing declarative APIs and tooling to simplify provisioning, upgrading, and operating multiple Kubernetes clusters.

kops: An automated cluster provisioning tool. For tutorials, best practices, configuration options and information on reaching out to the community, please check the kOps website for details.

kubespray: A composition of Ansible playbooks, inventory, provisioning tools, and domain knowledge for generic OS/Kubernetes clusters configuration management tasks. You can reach out to the community on Slack channel #kubespray.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Bootstrapping clusters with kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

**Contents:**
- Bootstrapping clusters with kubeadm
      - Installing kubeadm
      - Troubleshooting kubeadm
      - Creating a cluster with kubeadm
      - Customizing components with the kubeadm API
      - Options for Highly Available Topology
      - Creating Highly Available Clusters with kubeadm
      - Set up a High Availability etcd Cluster with kubeadm
      - Configuring each kubelet in your cluster using kubeadm
      - Dual-stack support with kubeadm

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#check-required-ports

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Container Runtimes

**URL:** https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers

**Contents:**
- Container Runtimes
    - Note:
- Install and configure prerequisites
  - Network configuration
  - Enable IPv4 packet forwarding
- cgroup drivers
  - cgroupfs driver
  - systemd cgroup driver
    - Note:
    - Caution:

You need to install a container runtime into each node in the cluster so that Pods can run there. This page outlines what is involved and describes related tasks for setting up nodes.

Kubernetes 1.34 requires that you use a runtime that conforms with the Container Runtime Interface (CRI).

See CRI version support for more information.

This page provides an outline of how to use several common container runtimes with Kubernetes.

Kubernetes releases before v1.24 included a direct integration with Docker Engine, using a component named dockershim. That special direct integration is no longer part of Kubernetes (this removal was announced as part of the v1.20 release). You can read Check whether Dockershim removal affects you to understand how this removal might affect you. To learn about migrating from using dockershim, see Migrating from dockershim.

If you are running a version of Kubernetes other than v1.34, check the documentation for that version.

By default, the Linux kernel does not allow IPv4 packets to be routed between interfaces. Most Kubernetes cluster networking implementations will change this setting (if needed), but some might expect the administrator to do it for them. (Some might also expect other sysctl parameters to be set, kernel modules to be loaded, etc; consult the documentation for your specific network implementation.)

To manually enable IPv4 packet forwarding:

Verify that net.ipv4.ip_forward is set to 1 with:

On Linux, control groups are used to constrain resources that are allocated to processes.

Both the kubelet and the underlying container runtime need to interface with control groups to enforce resource management for pods and containers and set resources such as cpu/memory requests and limits. To interface with control groups, the kubelet and the container runtime need to use a cgroup driver. It's critical that the kubelet and the container runtime use the same cgroup driver and are configured the same.

There are two cgroup drivers available:

The cgroupfs driver is the default cgroup driver in the kubelet. When the cgroupfs driver is used, the kubelet and the container runtime directly interface with the cgroup filesystem to configure cgroups.

The cgroupfs driver is not recommended when systemd is the init system because systemd expects a single cgroup manager on the system. Additionally, if you use cgroup v2, use the systemd cgroup driver instead of cgroupfs.

When systemd is chosen as the init system for a Linux di

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
```

Example 2 (bash):
```bash
sysctl net.ipv4.ip_forward
```

Example 3 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
...
cgroupDriver: systemd
```

Example 4 (unknown):
```unknown
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

---

## kubeadm alpha

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-alpha/

**Contents:**
- kubeadm alpha
    - Caution:
- What's next
- Feedback

Currently there are no experimental commands under kubeadm alpha.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## kubeadm version

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-version/

**Contents:**
- kubeadm version
  - Synopsis
  - Options
  - Options inherited from parent commands
- Feedback

This command prints the version of kubeadm.

Print the version of kubeadm

Output format; available options are 'yaml', 'json' and 'short'

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (unknown):
```unknown
kubeadm version [flags]
```

---

## kubeadm upgrade

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-upgrade/

**Contents:**
- kubeadm upgrade
- kubeadm upgrade guidance
    - Note:
- kubeadm upgrade plan
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm upgrade apply
  - Synopsis
  - Options

kubeadm upgrade is a user-friendly command that wraps complex upgrading logic behind one command, with support for both planning an upgrade and actually performing it.

The steps for performing an upgrade using kubeadm are outlined in this document. For older versions of kubeadm, please refer to older documentation sets of the Kubernetes website.

You can use kubeadm upgrade diff to see the changes that would be applied to static pod manifests.

In Kubernetes v1.15.0 and later, kubeadm upgrade apply and kubeadm upgrade node will also automatically renew the kubeadm managed certificates on this node, including those stored in kubeconfig files. To opt-out, it is possible to pass the flag --certificate-renewal=false. For more details about certificate renewal see the certificate management documentation.

Check which versions are available to upgrade to and validate whether your current cluster is upgradeable. This command can only run on the control plane nodes where the kubeconfig file "admin.conf" exists. To skip the internet check, pass in the optional [version] parameter.

Show unstable versions of Kubernetes as an upgrade alternative and allow upgrading to an alpha/beta/release candidate versions of Kubernetes.

If true, ignore any errors in templates when a field or map key is missing in the template. Only applies to golang and jsonpath output formats.

Show release candidate versions of Kubernetes as an upgrade alternative and allow upgrading to a release candidate versions of Kubernetes.

Path to a kubeadm configuration file.

Perform the upgrade of etcd.

A list of checks whose errors will be shown as warnings. Example: 'IsPrivilegedUser,Swap'. Value 'all' ignores errors from all checks.

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

Output format. One of: text|json|yaml|go-template|go-template-file|template|templatefile|jsonpath|jsonpath-as-json|jsonpath-file.

Specifies whether the configuration file that will be used in the upgrade should be printed or not.

If true, keep the managedFields when printing objects in JSON or YAML format.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Upgrade your Kubernetes cluster to the specified version

The "apply [version]" command executes the following phases:

Show unstable versions of Kubernetes as an upgrade alternative and allow upgrading

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
kubeadm upgrade plan [version] [flags]
```

Example 2 (javascript):
```javascript
preflight        Run preflight checks before upgrade
control-plane    Upgrade the control plane
upload-config    Upload the kubeadm and kubelet configurations to ConfigMaps
  /kubeadm         Upload the kubeadm ClusterConfiguration to a ConfigMap
  /kubelet         Upload the kubelet configuration to a ConfigMap
kubelet-config   Upgrade the kubelet configuration for this node
bootstrap-token  Configures bootstrap token and cluster-info RBAC rules
addon            Upgrade the default kubeadm addons
  /coredns         Upgrade the CoreDNS addon
  /kube-proxy      Upgrade the kube-proxy addon
post
...
```

Example 3 (unknown):
```unknown
kubeadm upgrade apply [version]
```

Example 4 (unknown):
```unknown
kubeadm upgrade diff [version] [flags]
```

---

## kubeadm init

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/

**Contents:**
- kubeadm init
  - Synopsis
  - Options
  - Options inherited from parent commands
  - Init workflow
    - Warning:
  - Using init phases with kubeadm
  - Using kubeadm init with a configuration file
    - Caution:
  - Using kubeadm init with feature gates

This command initializes a Kubernetes control plane node.

Run this command in order to set up the Kubernetes control plane

The "init" command executes the following phases:

The IP address the API Server will advertise it's listening on. If not set the default network interface will be used.

Port for the API Server to bind to.

Optional extra Subject Alternative Names (SANs) to use for the API Server serving certificate. Can be both IP addresses and DNS names.

The path where to save and store the certificates.

Key used to encrypt the control-plane certificates in the kubeadm-certs Secret. The certificate key is a hex encoded string that is an AES key of size 32 bytes.

Path to a kubeadm configuration file.

Specify a stable IP address or DNS name for the control plane.

Path to the CRI socket to connect. If empty kubeadm will try to auto-detect this value; use this option only if you have more than one CRI installed or if you have non-standard CRI socket.

Don't apply any changes; just output what would be done.

A set of key=value pairs that describe feature gates for various features. Options are:ControlPlaneKubeletLocalMode=true|false (BETA - default=true)NodeLocalCRISocket=true|false (BETA - default=true)PublicKeysECDSA=true|false (DEPRECATED - default=false)RootlessControlPlane=true|false (ALPHA - default=false)WaitForAllControlPlaneComponents=true|false (default=true)

A list of checks whose errors will be shown as warnings. Example: 'IsPrivilegedUser,Swap'. Value 'all' ignores errors from all checks.

Choose a container registry to pull control plane images from

Choose a specific Kubernetes version for the control plane.

Specify the node name.

Path to a directory that contains files named "target[suffix][+patchtype].extension". For example, "kube-apiserver0+merge.yaml" or just "etcd.json". "target" can be one of "kube-apiserver", "kube-controller-manager", "kube-scheduler", "etcd", "kubeletconfiguration", "corednsdeployment". "patchtype" can be one of "strategic", "merge" or "json" and they match the patch formats supported by kubectl. The default "patchtype" is "strategic". "extension" must be either "json" or "yaml". "suffix" is an optional string that can be used to determine which patches are applied first alpha-numerically.

Specify range of IP addresses for the pod network. If set, the control plane will automatically allocate CIDRs for every node.

Use alternative range of IP address for service VIPs.

Use alternative domain for servi

*[Content truncated]*

**Examples:**

Example 1 (javascript):
```javascript
preflight                     Run pre-flight checks
certs                         Certificate generation
  /ca                           Generate the self-signed Kubernetes CA to provision identities for other Kubernetes components
  /apiserver                    Generate the certificate for serving the Kubernetes API
  /apiserver-kubelet-client     Generate the certificate for the API server to connect to kubelet
  /front-proxy-ca               Generate the self-signed CA to provision identities for front proxy
  /front-proxy-client           Generate the certificate for the front proxy clien
...
```

Example 2 (unknown):
```unknown
kubeadm init [flags]
```

Example 3 (shell):
```shell
sudo kubeadm init phase control-plane controller-manager --help
```

Example 4 (shell):
```shell
sudo kubeadm init phase control-plane --help
```

---

## Best practices

**URL:** https://kubernetes.io/docs/setup/best-practices/

**Contents:**
- Best practices
      - Considerations for large clusters
      - Running in multiple zones
      - Validate node setup
      - Enforcing Pod Security Standards
      - PKI certificates and requirements
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Set up an Extension API Server

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/setup-extension-api-server/

**Contents:**
- Set up an Extension API Server
- Before you begin
- Set up an extension api-server to work with the aggregation layer
- What's next
- Feedback

Setting up an extension API server to work with the aggregation layer allows the Kubernetes apiserver to be extended with additional APIs, which are not part of the core Kubernetes APIs.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The following steps describe how to set up an extension-apiserver at a high level. These steps apply regardless if you're using YAML configs or using APIs. An attempt is made to specifically identify any differences between the two. For a concrete example of how they can be implemented using YAML configs, you can look at the sample-apiserver in the Kubernetes repo.

Alternatively, you can use an existing 3rd party solution, such as apiserver-builder, which should generate a skeleton and automate all of the following steps for you.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## kubeadm certs

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-certs/

**Contents:**
- kubeadm certs
- kubeadm certs
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm certs renew
  - Synopsis
  - Options
  - Options inherited from parent commands
  - Synopsis

kubeadm certs provides utilities for managing certificates. For more details on how these commands can be used, see Certificate Management with kubeadm.

A collection of operations for operating Kubernetes certificates.

SynopsisCommands related to handling Kubernetes certificateskubeadm certs [flags] Options-h, --helphelp for certsOptions inherited from parent commands--rootfs stringThe path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Commands related to handling Kubernetes certificates

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

You can renew all Kubernetes certificates using the all subcommand or renew them selectively. For more details see Manual certificate renewal.

SynopsisRenew certificates for a Kubernetes clusterkubeadm certs renew [flags] Options-h, --helphelp for renewOptions inherited from parent commands--rootfs stringThe path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Renew certificates for a Kubernetes cluster

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Renew all available certificatesSynopsisRenew all known certificates necessary to run the control plane. Renewals are run unconditionally, regardless of expiration date. Renewals can also be run individually for more control.kubeadm certs renew all [flags] Options--cert-dir string Default: "/etc/kubernetes/pki"The path where to save the certificates--config stringPath to a kubeadm configuration file.-h, --helphelp for all--kubeconfig string Default: "/etc/kubernetes/admin.conf"The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.Options inherited from parent commands--rootfs stringThe path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Renew all available certificates

Renew all known certificates necessary to run the control plane. Renewals are run unconditionally, regardless of expiration date. Renewals can also be run individually for more control.

The path where to save the certificates

Path to a kubeadm configuration file.

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

The path to the 'real' host root file

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
kubeadm certs [flags]
```

Example 2 (unknown):
```unknown
kubeadm certs renew [flags]
```

Example 3 (unknown):
```unknown
kubeadm certs renew all [flags]
```

Example 4 (unknown):
```unknown
kubeadm certs renew admin.conf [flags]
```

---

## Container Runtimes

**URL:** https://kubernetes.io/docs/setup/production-environment/container-runtimes

**Contents:**
- Container Runtimes
    - Note:
- Install and configure prerequisites
  - Network configuration
  - Enable IPv4 packet forwarding
- cgroup drivers
  - cgroupfs driver
  - systemd cgroup driver
    - Note:
    - Caution:

You need to install a container runtime into each node in the cluster so that Pods can run there. This page outlines what is involved and describes related tasks for setting up nodes.

Kubernetes 1.34 requires that you use a runtime that conforms with the Container Runtime Interface (CRI).

See CRI version support for more information.

This page provides an outline of how to use several common container runtimes with Kubernetes.

Kubernetes releases before v1.24 included a direct integration with Docker Engine, using a component named dockershim. That special direct integration is no longer part of Kubernetes (this removal was announced as part of the v1.20 release). You can read Check whether Dockershim removal affects you to understand how this removal might affect you. To learn about migrating from using dockershim, see Migrating from dockershim.

If you are running a version of Kubernetes other than v1.34, check the documentation for that version.

By default, the Linux kernel does not allow IPv4 packets to be routed between interfaces. Most Kubernetes cluster networking implementations will change this setting (if needed), but some might expect the administrator to do it for them. (Some might also expect other sysctl parameters to be set, kernel modules to be loaded, etc; consult the documentation for your specific network implementation.)

To manually enable IPv4 packet forwarding:

Verify that net.ipv4.ip_forward is set to 1 with:

On Linux, control groups are used to constrain resources that are allocated to processes.

Both the kubelet and the underlying container runtime need to interface with control groups to enforce resource management for pods and containers and set resources such as cpu/memory requests and limits. To interface with control groups, the kubelet and the container runtime need to use a cgroup driver. It's critical that the kubelet and the container runtime use the same cgroup driver and are configured the same.

There are two cgroup drivers available:

The cgroupfs driver is the default cgroup driver in the kubelet. When the cgroupfs driver is used, the kubelet and the container runtime directly interface with the cgroup filesystem to configure cgroups.

The cgroupfs driver is not recommended when systemd is the init system because systemd expects a single cgroup manager on the system. Additionally, if you use cgroup v2, use the systemd cgroup driver instead of cgroupfs.

When systemd is chosen as the init system for a Linux di

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
```

Example 2 (bash):
```bash
sysctl net.ipv4.ip_forward
```

Example 3 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
...
cgroupDriver: systemd
```

Example 4 (unknown):
```unknown
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#verify-mac-address

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#container-runtime-0

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## kubeadm join

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/

**Contents:**
- kubeadm join
  - Synopsis
  - Options
  - Options inherited from parent commands
  - The join workflow
  - Using join phases with kubeadm
  - Discovering what cluster CA to trust
    - Token-based discovery with CA pinning
    - Token-based discovery without CA pinning
    - File or HTTPS-based discovery

This command initializes a new Kubernetes node and joins it to the existing cluster.

Run this on any machine you wish to join an existing cluster

When joining a kubeadm initialized cluster, we need to establish bidirectional trust. This is split into discovery (having the Node trust the Kubernetes Control Plane) and TLS bootstrap (having the Kubernetes Control Plane trust the Node).

There are 2 main schemes for discovery. The first is to use a shared token along with the IP address of the API server. The second is to provide a file - a subset of the standard kubeconfig file. The discovery/kubeconfig file supports token, client-go authentication plugins ("exec"), "tokenFile", and "authProvider". This file can be a local file or downloaded via an HTTPS URL. The forms are kubeadm join --discovery-token abcdef.1234567890abcdef 1.2.3.4:6443, kubeadm join --discovery-file path/to/file.conf, or kubeadm join --discovery-file https://url/file.conf. Only one form can be used. If the discovery information is loaded from a URL, HTTPS must be used. Also, in that case the host installed CA bundle is used to verify the connection.

If you use a shared token for discovery, you should also pass the --discovery-token-ca-cert-hash flag to validate the public key of the root certificate authority (CA) presented by the Kubernetes Control Plane. The value of this flag is specified as "<hash-type>:<hex-encoded-value>", where the supported hash type is "sha256". The hash is calculated over the bytes of the Subject Public Key Info (SPKI) object (as in RFC7469). This value is available in the output of "kubeadm init" or can be calculated using standard tools. The --discovery-token-ca-cert-hash flag may be repeated multiple times to allow more than one public key.

If you cannot know the CA public key hash ahead of time, you can pass the --discovery-token-unsafe-skip-ca-verification flag to disable this verification. This weakens the kubeadm security model since other nodes can potentially impersonate the Kubernetes Control Plane.

The TLS bootstrap mechanism is also driven via a shared token. This is used to temporarily authenticate with the Kubernetes Control Plane to submit a certificate signing request (CSR) for a locally created key pair. By default, kubeadm will set up the Kubernetes Control Plane to automatically approve these signing requests. This token is passed in with the --tls-bootstrap-token abcdef.1234567890abcdef flag.

Often times the same token is used for both 

*[Content truncated]*

**Examples:**

Example 1 (javascript):
```javascript
preflight              Run join pre-flight checks
control-plane-prepare  Prepare the machine for serving a control plane
  /download-certs        Download certificates shared among control-plane nodes from the kubeadm-certs Secret
  /certs                 Generate the certificates for the new control plane components
  /kubeconfig            Generate the kubeconfig for the new control plane components
  /control-plane         Generate the manifests for the new control plane components
kubelet-start          Write kubelet settings, certificates and (re)start the kubelet
control-plane-join     J
...
```

Example 2 (unknown):
```unknown
kubeadm join [api-server-endpoint] [flags]
```

Example 3 (shell):
```shell
kubeadm join phase kubelet-start --help
```

Example 4 (shell):
```shell
sudo kubeadm join --skip-phases=preflight --config=config.yaml
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#k8s-install-1

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## kubeadm token

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/

**Contents:**
- kubeadm token
- kubeadm token create
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm token delete
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm token generate

Bootstrap tokens are used for establishing bidirectional trust between a node joining the cluster and a control-plane node, as described in authenticating with bootstrap tokens.

kubeadm init creates an initial token with a 24-hour TTL. The following commands allow you to manage such a token and also to create and manage new ones.

Create bootstrap tokens on the server

This command will create a bootstrap token for you. You can specify the usages for this token, the "time to live" and an optional human friendly description.

The [token] is the actual token to write. This should be a securely generated random token of the form "[a-z0-9]{6}.[a-z0-9]{16}". If no [token] is given, kubeadm will generate a random token instead.

When used together with '--print-join-command', print the full 'kubeadm join' flag needed to join the cluster as a control-plane. To create a new certificate key you must use 'kubeadm init phase upload-certs --upload-certs'.

Path to a kubeadm configuration file.

A human friendly description of how this token is used.

Extra groups that this token will authenticate as when used for authentication. Must match "\Asystem:bootstrappers:[a-z0-9:-]{0,255}[a-z0-9]\z"

Instead of printing only the token, print the full 'kubeadm join' flag needed to join the cluster using the token.

The duration before the token is automatically deleted (e.g. 1s, 2m, 3h). If set to '0', the token will never expire

Describes the ways in which this token can be used. You can pass --usages multiple times or provide a comma separated list of options. Valid options: [signing,authentication]

Whether to enable dry-run mode or not

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Delete bootstrap tokens on the server

This command will delete a list of bootstrap tokens for you.

The [token-value] is the full Token of the form "[a-z0-9]{6}.[a-z0-9]{16}" or the Token ID of the form "[a-z0-9]{6}" to delete.

Whether to enable dry-run mode or not

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Generate and print a bootstrap token, but do not create i

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
kubeadm token create [token]
```

Example 2 (unknown):
```unknown
kubeadm token delete [token-value] ...
```

Example 3 (unknown):
```unknown
kubeadm token generate [flags]
```

Example 4 (unknown):
```unknown
kubeadm token list [flags]
```

---

## Getting started

**URL:** https://kubernetes.io/docs/setup/

**Contents:**
- Learning environment
- Production environment
- What's next
- Feedback

This section lists the different ways to set up and run Kubernetes. When you install Kubernetes, choose an installation type based on: ease of maintenance, security, control, available resources, and expertise required to operate and manage a cluster.

You can download Kubernetes to deploy a Kubernetes cluster on a local machine, into the cloud, or for your own datacenter.

Several Kubernetes components such as kube-apiserver or kube-proxy can also be deployed as container images within the cluster.

It is recommended to run Kubernetes components as container images wherever that is possible, and to have Kubernetes manage those components. Components that run containers - notably, the kubelet - can't be included in this category.

If you don't want to manage a Kubernetes cluster yourself, you could pick a managed service, including certified platforms. There are also other standardized and custom solutions across a wide range of cloud and bare metal environments.

If you're learning Kubernetes, use the tools supported by the Kubernetes community, or tools in the ecosystem to set up a Kubernetes cluster on a local machine. See Install tools.

When evaluating a solution for a production environment, consider which aspects of operating a Kubernetes cluster (or abstractions) you want to manage yourself and which you prefer to hand off to a provider.

For a cluster you're managing yourself, the officially supported tool for deploying Kubernetes is kubeadm.

Kubernetes is designed for its control plane to run on Linux. Within your cluster you can run applications on Linux or other operating systems, including Windows.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Container Runtimes

**URL:** https://kubernetes.io/docs/setup/production-environment/container-runtimes/

**Contents:**
- Container Runtimes
    - Note:
- Install and configure prerequisites
  - Network configuration
  - Enable IPv4 packet forwarding
- cgroup drivers
  - cgroupfs driver
  - systemd cgroup driver
    - Note:
    - Caution:

You need to install a container runtime into each node in the cluster so that Pods can run there. This page outlines what is involved and describes related tasks for setting up nodes.

Kubernetes 1.34 requires that you use a runtime that conforms with the Container Runtime Interface (CRI).

See CRI version support for more information.

This page provides an outline of how to use several common container runtimes with Kubernetes.

Kubernetes releases before v1.24 included a direct integration with Docker Engine, using a component named dockershim. That special direct integration is no longer part of Kubernetes (this removal was announced as part of the v1.20 release). You can read Check whether Dockershim removal affects you to understand how this removal might affect you. To learn about migrating from using dockershim, see Migrating from dockershim.

If you are running a version of Kubernetes other than v1.34, check the documentation for that version.

By default, the Linux kernel does not allow IPv4 packets to be routed between interfaces. Most Kubernetes cluster networking implementations will change this setting (if needed), but some might expect the administrator to do it for them. (Some might also expect other sysctl parameters to be set, kernel modules to be loaded, etc; consult the documentation for your specific network implementation.)

To manually enable IPv4 packet forwarding:

Verify that net.ipv4.ip_forward is set to 1 with:

On Linux, control groups are used to constrain resources that are allocated to processes.

Both the kubelet and the underlying container runtime need to interface with control groups to enforce resource management for pods and containers and set resources such as cpu/memory requests and limits. To interface with control groups, the kubelet and the container runtime need to use a cgroup driver. It's critical that the kubelet and the container runtime use the same cgroup driver and are configured the same.

There are two cgroup drivers available:

The cgroupfs driver is the default cgroup driver in the kubelet. When the cgroupfs driver is used, the kubelet and the container runtime directly interface with the cgroup filesystem to configure cgroups.

The cgroupfs driver is not recommended when systemd is the init system because systemd expects a single cgroup manager on the system. Additionally, if you use cgroup v2, use the systemd cgroup driver instead of cgroupfs.

When systemd is chosen as the init system for a Linux di

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
```

Example 2 (bash):
```bash
sysctl net.ipv4.ip_forward
```

Example 3 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
...
cgroupDriver: systemd
```

Example 4 (unknown):
```unknown
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

---

## Production environment

**URL:** https://kubernetes.io/docs/setup/production-environment/

**Contents:**
- Production environment
- Production considerations
- Production cluster setup
  - Production control plane
  - Production worker nodes
- Production user management
- Set limits on workload resources
- What's next
- Feedback

A production-quality Kubernetes cluster requires planning and preparation. If your Kubernetes cluster is to run critical workloads, it must be configured to be resilient. This page explains steps you can take to set up a production-ready cluster, or to promote an existing cluster for production use. If you're already familiar with production setup and want the links, skip to What's next.

Typically, a production Kubernetes cluster environment has more requirements than a personal learning, development, or test environment Kubernetes. A production environment may require secure access by many users, consistent availability, and the resources to adapt to changing demands.

As you decide where you want your production Kubernetes environment to live (on premises or in a cloud) and the amount of management you want to take on or hand to others, consider how your requirements for a Kubernetes cluster are influenced by the following issues:

Availability: A single-machine Kubernetes learning environment has a single point of failure. Creating a highly available cluster means considering:

Scale: If you expect your production Kubernetes environment to receive a stable amount of demand, you might be able to set up for the capacity you need and be done. However, if you expect demand to grow over time or change dramatically based on things like season or special events, you need to plan how to scale to relieve increased pressure from more requests to the control plane and worker nodes or scale down to reduce unused resources.

Security and access management: You have full admin privileges on your own Kubernetes learning cluster. But shared clusters with important workloads, and more than one or two users, require a more refined approach to who and what can access cluster resources. You can use role-based access control (RBAC) and other security mechanisms to make sure that users and workloads can get access to the resources they need, while keeping workloads, and the cluster itself, secure. You can set limits on the resources that users and workloads can access by managing policies and container resources.

Before building a Kubernetes production environment on your own, consider handing off some or all of this job to Turnkey Cloud Solutions providers or other Kubernetes Partners. Options include:

Whether you build a production Kubernetes cluster yourself or work with partners, review the following sections to evaluate your needs as they relate to your cluster’s con

*[Content truncated]*

---

## Troubleshooting kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/

**Contents:**
- Troubleshooting kubeadm
- Not possible to join a v1.18 Node to a v1.17 cluster due to missing RBAC
- ebtables or some similar executable not found during installation
- kubeadm blocks waiting for control plane during installation
- kubeadm blocks when removing managed containers
- Pods in RunContainerError, CrashLoopBackOff or Error state
- coredns is stuck in the Pending state
- HostPort services do not work
- Pods are not accessible via their Service IP
- TLS certificate errors

As with any program, you might run into an error installing or running kubeadm. This page lists some common failure scenarios and have provided steps that can help you understand and fix the problem.

If your problem is not listed below, please follow the following steps:

If you think your problem is a bug with kubeadm:

If you are unsure about how kubeadm works, you can ask on Slack in #kubeadm, or open a question on StackOverflow. Please include relevant tags like #kubernetes and #kubeadm so folks can help you.

In v1.18 kubeadm added prevention for joining a Node in the cluster if a Node with the same name already exists. This required adding RBAC for the bootstrap-token user to be able to GET a Node object.

However this causes an issue where kubeadm join from v1.18 cannot join a cluster created by kubeadm v1.17.

To workaround the issue you have two options:

Execute kubeadm init phase bootstrap-token on a control-plane node using kubeadm v1.18. Note that this enables the rest of the bootstrap-token permissions as well.

Apply the following RBAC manually using kubectl apply -f ...:

If you see the following warnings while running kubeadm init

Then you may be missing ebtables, ethtool or a similar executable on your node. You can install them with the following commands:

If you notice that kubeadm init hangs after printing out the following line:

This may be caused by a number of problems. The most common are:

The following could happen if the container runtime halts and does not remove any Kubernetes-managed containers:

A possible solution is to restart the container runtime and then re-run kubeadm reset. You can also use crictl to debug the state of the container runtime. See Debugging Kubernetes nodes with crictl.

Right after kubeadm init there should not be any pods in these states.

This is expected and part of the design. kubeadm is network provider-agnostic, so the admin should install the pod network add-on of choice. You have to install a Pod Network before CoreDNS may be deployed fully. Hence the Pending state before the network is set up.

The HostPort and HostIP functionality is available depending on your Pod Network provider. Please contact the author of the Pod Network add-on to find out whether HostPort and HostIP functionality are available.

Calico, Canal, and Flannel CNI providers are verified to support HostPort.

For more information, see the CNI portmap documentation.

If your network provider does not support the portmap C

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeadm:get-nodes
rules:
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:get-nodes
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubeadm:get-nodes
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: system:bootstrappers:kubeadm:default-node-token
```

Example 2 (console):
```console
[preflight] WARNING: ebtables not found in system path
[preflight] WARNING: ethtool not found in system path
```

Example 3 (console):
```console
[apiclient] Created API client, waiting for the control plane to become ready
```

Example 4 (shell):
```shell
sudo kubeadm reset
```

---

## Turnkey Cloud Solutions

**URL:** https://kubernetes.io/docs/setup/production-environment/turnkey-solutions/

**Contents:**
- Turnkey Cloud Solutions
- Feedback

This page provides a list of Kubernetes certified solution providers. From each provider page, you can learn how to install and setup production ready clusters.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#third-party-content-disclaimer

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## kubeadm config

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-config/

**Contents:**
- kubeadm config
    - Note:
- kubeadm config print
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm config print init-defaults
  - Synopsis
  - Options
  - Options inherited from parent commands

During kubeadm init, kubeadm uploads the ClusterConfiguration object to your cluster in a ConfigMap called kubeadm-config in the kube-system namespace. This configuration is then read during kubeadm join, kubeadm reset and kubeadm upgrade.

You can use kubeadm config print to print the default static configuration that kubeadm uses for kubeadm init and kubeadm join.

For more information on init and join navigate to Using kubeadm init with a configuration file or Using kubeadm join with a configuration file.

For more information on using the kubeadm configuration API navigate to Customizing components with the kubeadm API.

You can use kubeadm config migrate to convert your old configuration files that contain a deprecated API version to a newer, supported API version.

kubeadm config validate can be used for validating a configuration file.

kubeadm config images list and kubeadm config images pull can be used to list and pull the images that kubeadm requires.

This command prints configurations for subcommands provided. For details, see: https://pkg.go.dev/k8s.io/kubernetes/cmd/kubeadm/app/apis/kubeadm#section-directories

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Print default init configuration, that can be used for 'kubeadm init'

This command prints objects such as the default init configuration that is used for 'kubeadm init'.

Note that sensitive values like the Bootstrap Token fields are replaced with placeholder values like "abcdef.0123456789abcdef" in order to pass validation but not perform the real computation for creating a token.

A comma-separated list for component config API objects to print the default values for. Available values: [KubeProxyConfiguration KubeletConfiguration]. If this flag is not set, no component configs will be printed.

help for init-defaults

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Print default join configuration, that can be used for 'kubeadm join'

This command prints objects such as the default join configuration that is used for 'kubeadm join'.

Note that sensitive values like

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
kubeadm config print [flags]
```

Example 2 (unknown):
```unknown
kubeadm config print init-defaults [flags]
```

Example 3 (unknown):
```unknown
kubeadm config print join-defaults [flags]
```

Example 4 (unknown):
```unknown
kubeadm config migrate [flags]
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#container-runtime-1

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Setup tools

**URL:** https://kubernetes.io/docs/reference/setup-tools/

**Contents:**
- Setup tools
      - Kubeadm
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#k8s-install-2

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Creating a cluster with kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#version-skew-policy

**Contents:**
- Creating a cluster with kubeadm
- Before you begin
    - Note:
- Objectives
- Instructions
  - Preparing the hosts
    - Component installation
    - Note:
    - Network setup
    - Note:

Using kubeadm, you can create a minimum viable Kubernetes cluster that conforms to best practices. In fact, you can use kubeadm to set up a cluster that will pass the Kubernetes Conformance tests. kubeadm also supports other cluster lifecycle functions, such as bootstrap tokens and cluster upgrades.

The kubeadm tool is good if you need:

You can install and use kubeadm on various machines: your laptop, a set of cloud servers, a Raspberry Pi, and more. Whether you're deploying into the cloud or on-premises, you can integrate kubeadm into provisioning systems such as Ansible or Terraform.

To follow this guide, you need:

You also need to use a version of kubeadm that can deploy the version of Kubernetes that you want to use in your new cluster.

Kubernetes' version and version skew support policy applies to kubeadm as well as to Kubernetes overall. Check that policy to learn about what versions of Kubernetes and kubeadm are supported. This page is written for Kubernetes v1.34.

The kubeadm tool's overall feature state is General Availability (GA). Some sub-features are still under active development. The implementation of creating the cluster may change slightly as the tool evolves, but the overall implementation should be pretty stable.

Install a container runtime and kubeadm on all the hosts. For detailed instructions and other prerequisites, see Installing kubeadm.

If you have already installed kubeadm, see the first two steps of the Upgrading Linux nodes document for instructions on how to upgrade kubeadm.

When you upgrade, the kubelet restarts every few seconds as it waits in a crashloop for kubeadm to tell it what to do. This crashloop is expected and normal. After you initialize your control-plane, the kubelet runs normally.

kubeadm similarly to other Kubernetes components tries to find a usable IP on the network interfaces associated with a default gateway on a host. Such an IP is then used for the advertising and/or listening performed by a component.

To find out what this IP is on a Linux host you can use:

Kubernetes components do not accept custom network interface as an option, therefore a custom IP address must be passed as a flag to all components instances that need such a custom configuration.

To configure the API server advertise address for control plane nodes created with both init and join, the flag --apiserver-advertise-address can be used. Preferably, this option can be set in the kubeadm API as InitConfiguration.localAPIEndpoi

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
ip route show # Look for a line starting with "default via"
```

Example 2 (bash):
```bash
kubeadm init <args>
```

Example 3 (unknown):
```unknown
192.168.0.102 cluster-endpoint
```

Example 4 (none):
```none
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a Pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  /docs/concepts/cluster-administration/addons/

You can now join any number of machines by running the following on each node
as root:

  kubeadm join <control-plane-host>:<control-plane-port> --tok
...
```

---

## Getting started

**URL:** https://kubernetes.io/docs/setup/#learning-environment

**Contents:**
- Learning environment
- Production environment
- What's next
- Feedback

This section lists the different ways to set up and run Kubernetes. When you install Kubernetes, choose an installation type based on: ease of maintenance, security, control, available resources, and expertise required to operate and manage a cluster.

You can download Kubernetes to deploy a Kubernetes cluster on a local machine, into the cloud, or for your own datacenter.

Several Kubernetes components such as kube-apiserver or kube-proxy can also be deployed as container images within the cluster.

It is recommended to run Kubernetes components as container images wherever that is possible, and to have Kubernetes manage those components. Components that run containers - notably, the kubelet - can't be included in this category.

If you don't want to manage a Kubernetes cluster yourself, you could pick a managed service, including certified platforms. There are also other standardized and custom solutions across a wide range of cloud and bare metal environments.

If you're learning Kubernetes, use the tools supported by the Kubernetes community, or tools in the ecosystem to set up a Kubernetes cluster on a local machine. See Install tools.

When evaluating a solution for a production environment, consider which aspects of operating a Kubernetes cluster (or abstractions) you want to manage yourself and which you prefer to hand off to a provider.

For a cluster you're managing yourself, the officially supported tool for deploying Kubernetes is kubeadm.

Kubernetes is designed for its control plane to run on Linux. Within your cluster you can run applications on Linux or other operating systems, including Windows.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Version Skew Policy

**URL:** https://kubernetes.io/docs/setup/release/version-skew-policy/

**Contents:**
- Version Skew Policy
- Supported versions
- Supported version skew
  - kube-apiserver
  - kubelet
    - Note:
  - kube-proxy
    - Note:
  - kube-controller-manager, kube-scheduler, and cloud-controller-manager
    - Note:

This document describes the maximum version skew supported between various Kubernetes components. Specific cluster deployment tools may place additional restrictions on version skew.

Kubernetes versions are expressed as x.y.z, where x is the major version, y is the minor version, and z is the patch version, following Semantic Versioning terminology. For more information, see Kubernetes Release Versioning.

The Kubernetes project maintains release branches for the most recent three minor releases (1.34, 1.33, 1.32). Kubernetes 1.19 and newer receive approximately 1 year of patch support. Kubernetes 1.18 and older received approximately 9 months of patch support.

Applicable fixes, including security fixes, may be backported to those three release branches, depending on severity and feasibility. Patch releases are cut from those branches at a regular cadence, plus additional urgent releases, when required.

The Release Managers group owns this decision.

For more information, see the Kubernetes patch releases page.

In highly-available (HA) clusters, the newest and oldest kube-apiserver instances must be within one minor version.

kube-controller-manager, kube-scheduler, and cloud-controller-manager must not be newer than the kube-apiserver instances they communicate with. They are expected to match the kube-apiserver minor version, but may be up to one minor version older (to allow live upgrades).

kubectl is supported within one minor version (older or newer) of kube-apiserver.

The supported version skew between components has implications on the order in which components must be upgraded. This section describes the order in which components must be upgraded to transition an existing cluster from version 1.33 to version 1.34.

Optionally, when preparing to upgrade, the Kubernetes project recommends that you do the following to benefit from as many regression and bug fixes as possible during your upgrade:

For example, if you're running version 1.33, ensure that you're on the most recent patch version. Then, upgrade to the most recent patch version of 1.34.

Upgrade kube-apiserver to 1.34

Upgrade kube-controller-manager, kube-scheduler, and cloud-controller-manager to 1.34. There is no required upgrade order between kube-controller-manager, kube-scheduler, and cloud-controller-manager. You can upgrade these components in any order, or even simultaneously.

Optionally upgrade kubelet instances to 1.34 (or they can be left at 1.33, 1.32, or 1.31)

Optional

*[Content truncated]*

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#operating-system-version-check-1

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## kubeadm kubeconfig

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-kubeconfig/

**Contents:**
- kubeadm kubeconfig
- kubeadm kubeconfig
  - Synopsis
  - Options
  - Options inherited from parent commands
- kubeadm kubeconfig user
  - Synopsis
  - Examples
  - Options
  - Options inherited from parent commands

kubeadm kubeconfig provides utilities for managing kubeconfig files.

For examples on how to use kubeadm kubeconfig user see Generating kubeconfig files for additional users.

SynopsisKubeconfig file utilities.Options-h, --helphelp for kubeconfigOptions inherited from parent commands--rootfs stringThe path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Kubeconfig file utilities.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

This command can be used to output a kubeconfig file for an additional user.

SynopsisOutput a kubeconfig file for an additional user.kubeadm kubeconfig user [flags] Examples # Output a kubeconfig file for an additional user named foo kubeadm kubeconfig user --client-name=foo # Output a kubeconfig file for an additional user named foo using a kubeadm config file bar kubeadm kubeconfig user --client-name=foo --config=bar Options--client-name stringThe name of user. It will be used as the CN if client certificates are created--config stringPath to a kubeadm configuration file.-h, --helphelp for user--org stringsThe organizations of the client certificate. It will be used as the O if client certificates are created--token stringThe token that should be used as the authentication mechanism for this kubeconfig, instead of client certificates--validity-period duration Default: 8760h0m0sThe validity period of the client certificate. It is an offset from the current time.Options inherited from parent commands--rootfs stringThe path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Output a kubeconfig file for an additional user.

The name of user. It will be used as the CN if client certificates are created

Path to a kubeadm configuration file.

The organizations of the client certificate. It will be used as the O if client certificates are created

The token that should be used as the authentication mechanism for this kubeconfig, instead of client certificates

The validity period of the client certificate. It is an offset from the current time.

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (unknown):
```unknown
kubeadm kubeconfig user [flags]
```

Example 2 (unknown):
```unknown
# Output a kubeconfig file for an additional user named foo
  kubeadm kubeconfig user --client-name=foo
  
  # Output a kubeconfig file for an additional user named foo using a kubeadm config file bar
  kubeadm kubeconfig user --client-name=foo --config=bar
```

---

## Kubeadm

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/

**Contents:**
- Kubeadm
- How to install
- What's next
- Feedback

Kubeadm is a tool built to provide kubeadm init and kubeadm join as best-practice "fast paths" for creating Kubernetes clusters.

kubeadm performs the actions necessary to get a minimum viable cluster up and running. By design, it cares only about bootstrapping, not about provisioning machines. Likewise, installing various nice-to-have addons, like the Kubernetes Dashboard, monitoring solutions, and cloud-specific addons, is not in scope.

Instead, we expect higher-level and more tailored tooling to be built on top of kubeadm, and ideally, using kubeadm as the basis of all deployments will make it easier to create conformant clusters.

To install kubeadm, see the installation guide.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Set up Konnectivity service

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/

**Contents:**
- Set up Konnectivity service
- Before you begin
- Configure the Konnectivity service
- Feedback

The Konnectivity service provides a TCP level proxy for the control plane to cluster communication.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube.

The following steps require an egress configuration, for example:

You need to configure the API Server to use the Konnectivity service and direct the network traffic to the cluster nodes:

Generate or obtain a certificate and kubeconfig for konnectivity-server. For example, you can use the OpenSSL command line tool to issue a X.509 certificate, using the cluster CA certificate /etc/kubernetes/pki/ca.crt from a control-plane host.

Next, you need to deploy the Konnectivity server and agents. kubernetes-sigs/apiserver-network-proxy is a reference implementation.

Deploy the Konnectivity server on your control plane node. The provided konnectivity-server.yaml manifest assumes that the Kubernetes components are deployed as a static Pod in your cluster. If not, you can deploy the Konnectivity server as a DaemonSet.

Then deploy the Konnectivity agents in your cluster:

Last, if RBAC is enabled in your cluster, create the relevant RBAC rules:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apiserver.k8s.io/v1beta1
kind: EgressSelectorConfiguration
egressSelections:
# Since we want to control the egress traffic to the cluster, we use the
# "cluster" as the name. Other supported values are "etcd", and "controlplane".
- name: cluster
  connection:
    # This controls the protocol between the API Server and the Konnectivity
    # server. Supported values are "GRPC" and "HTTPConnect". There is no
    # end user visible difference between the two modes. You need to set the
    # Konnectivity server to work in the same mode.
    proxyProtocol: GRPC
    transport:
      # Th
...
```

Example 2 (yaml):
```yaml
spec:
  containers:
    volumeMounts:
    - name: konnectivity-uds
      mountPath: /etc/kubernetes/konnectivity-server
      readOnly: false
  volumes:
  - name: konnectivity-uds
    hostPath:
      path: /etc/kubernetes/konnectivity-server
      type: DirectoryOrCreate
```

Example 3 (bash):
```bash
openssl req -subj "/CN=system:konnectivity-server" -new -newkey rsa:2048 -nodes -out konnectivity.csr -keyout konnectivity.key
openssl x509 -req -in konnectivity.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out konnectivity.crt -days 375 -sha256
SERVER=$(kubectl config view -o jsonpath='{.clusters..server}')
kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config set-credentials system:konnectivity-server --client-certificate konnectivity.crt --client-key konnectivity.key --embed-certs=true
kubectl --kubeconfig /etc/kubernetes/konnectivity-
...
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: konnectivity-server
  namespace: kube-system
spec:
  priorityClassName: system-cluster-critical
  hostNetwork: true
  containers:
  - name: konnectivity-server-container
    image: registry.k8s.io/kas-network-proxy/proxy-server:v0.0.37
    command: ["/proxy-server"]
    args: [
            "--logtostderr=true",
            # This needs to be consistent with the value set in egressSelectorConfiguration.
            "--uds-name=/etc/kubernetes/konnectivity-server/konnectivity-server.socket",
            "--delete-existing-uds-file",
            # The fo
...
```

---

## Installing kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#k8s-install-0

**Contents:**
- Installing kubeadm
- Before you begin
    - Note:
- Check your OS version
- Verify the MAC address and product_uuid are unique for every node
- Check network adapters
- Check required ports
- Swap configuration
- Installing a container runtime
    - Note:

This page shows how to install the kubeadm toolbox. For information on how to create a cluster with kubeadm once you have performed this installation process, see the Creating a cluster with kubeadm page.

This installation guide is for Kubernetes v1.34. If you want to use a different Kubernetes version, please refer to the following pages instead:

The kubeadm project supports LTS kernels. See List of LTS kernels.You can get the kernel version using the command uname -rFor more information, see Linux Kernel Requirements.

For more information, see Linux Kernel Requirements.

The kubeadm project supports recent kernel versions. For a list of recent kernels, see Windows Server Release Information.You can get the kernel version (also called the OS version) using the command systeminfoFor more information, see Windows OS version compatibility.

For more information, see Windows OS version compatibility.

A Kubernetes cluster created by kubeadm depends on software that use kernel features. This software includes, but is not limited to the container runtime, the kubelet, and a Container Network Interface plugin.

To help you avoid unexpected errors as a result of an unsupported kernel version, kubeadm runs the SystemVerification pre-flight check. This check fails if the kernel version is not supported.

You may choose to skip the check, if you know that your kernel provides the required features, even though kubeadm does not support its version.

It is very likely that hardware devices will have unique addresses, although some virtual machines may have identical values. Kubernetes uses these values to uniquely identify the nodes in the cluster. If these values are not unique to each node, the installation process may fail.

If you have more than one network adapter, and your Kubernetes components are not reachable on the default route, we recommend you add IP route(s) so Kubernetes cluster addresses go via the appropriate adapter.

These required ports need to be open in order for Kubernetes components to communicate with each other. You can use tools like netcat to check if a port is open. For example:

The pod network plugin you use may also require certain ports to be open. Since this differs with each pod network plugin, please see the documentation for the plugins about what port(s) those need.

The default behavior of a kubelet is to fail to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
nc 127.0.0.1 6443 -zv -w 2
```

Example 2 (shell):
```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Example 3 (shell):
```shell
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Example 4 (shell):
```shell
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

---

## Troubleshooting kubeadm

**URL:** https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/#usr-mounted-read-only

**Contents:**
- Troubleshooting kubeadm
- Not possible to join a v1.18 Node to a v1.17 cluster due to missing RBAC
- ebtables or some similar executable not found during installation
- kubeadm blocks waiting for control plane during installation
- kubeadm blocks when removing managed containers
- Pods in RunContainerError, CrashLoopBackOff or Error state
- coredns is stuck in the Pending state
- HostPort services do not work
- Pods are not accessible via their Service IP
- TLS certificate errors

As with any program, you might run into an error installing or running kubeadm. This page lists some common failure scenarios and have provided steps that can help you understand and fix the problem.

If your problem is not listed below, please follow the following steps:

If you think your problem is a bug with kubeadm:

If you are unsure about how kubeadm works, you can ask on Slack in #kubeadm, or open a question on StackOverflow. Please include relevant tags like #kubernetes and #kubeadm so folks can help you.

In v1.18 kubeadm added prevention for joining a Node in the cluster if a Node with the same name already exists. This required adding RBAC for the bootstrap-token user to be able to GET a Node object.

However this causes an issue where kubeadm join from v1.18 cannot join a cluster created by kubeadm v1.17.

To workaround the issue you have two options:

Execute kubeadm init phase bootstrap-token on a control-plane node using kubeadm v1.18. Note that this enables the rest of the bootstrap-token permissions as well.

Apply the following RBAC manually using kubectl apply -f ...:

If you see the following warnings while running kubeadm init

Then you may be missing ebtables, ethtool or a similar executable on your node. You can install them with the following commands:

If you notice that kubeadm init hangs after printing out the following line:

This may be caused by a number of problems. The most common are:

The following could happen if the container runtime halts and does not remove any Kubernetes-managed containers:

A possible solution is to restart the container runtime and then re-run kubeadm reset. You can also use crictl to debug the state of the container runtime. See Debugging Kubernetes nodes with crictl.

Right after kubeadm init there should not be any pods in these states.

This is expected and part of the design. kubeadm is network provider-agnostic, so the admin should install the pod network add-on of choice. You have to install a Pod Network before CoreDNS may be deployed fully. Hence the Pending state before the network is set up.

The HostPort and HostIP functionality is available depending on your Pod Network provider. Please contact the author of the Pod Network add-on to find out whether HostPort and HostIP functionality are available.

Calico, Canal, and Flannel CNI providers are verified to support HostPort.

For more information, see the CNI portmap documentation.

If your network provider does not support the portmap C

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubeadm:get-nodes
rules:
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:get-nodes
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubeadm:get-nodes
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: system:bootstrappers:kubeadm:default-node-token
```

Example 2 (console):
```console
[preflight] WARNING: ebtables not found in system path
[preflight] WARNING: ethtool not found in system path
```

Example 3 (console):
```console
[apiclient] Created API client, waiting for the control plane to become ready
```

Example 4 (shell):
```shell
sudo kubeadm reset
```

---

## Getting started

**URL:** https://kubernetes.io/docs/setup/#production-environment

**Contents:**
- Learning environment
- Production environment
- What's next
- Feedback

This section lists the different ways to set up and run Kubernetes. When you install Kubernetes, choose an installation type based on: ease of maintenance, security, control, available resources, and expertise required to operate and manage a cluster.

You can download Kubernetes to deploy a Kubernetes cluster on a local machine, into the cloud, or for your own datacenter.

Several Kubernetes components such as kube-apiserver or kube-proxy can also be deployed as container images within the cluster.

It is recommended to run Kubernetes components as container images wherever that is possible, and to have Kubernetes manage those components. Components that run containers - notably, the kubelet - can't be included in this category.

If you don't want to manage a Kubernetes cluster yourself, you could pick a managed service, including certified platforms. There are also other standardized and custom solutions across a wide range of cloud and bare metal environments.

If you're learning Kubernetes, use the tools supported by the Kubernetes community, or tools in the ecosystem to set up a Kubernetes cluster on a local machine. See Install tools.

When evaluating a solution for a production environment, consider which aspects of operating a Kubernetes cluster (or abstractions) you want to manage yourself and which you prefer to hand off to a provider.

For a cluster you're managing yourself, the officially supported tool for deploying Kubernetes is kubeadm.

Kubernetes is designed for its control plane to run on Linux. Within your cluster you can run applications on Linux or other operating systems, including Windows.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## kubeadm reset

**URL:** https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/

**Contents:**
- kubeadm reset
  - Synopsis
  - Options
  - Options inherited from parent commands
  - Reset workflow
  - Cleanup of external etcd members
  - Cleanup of CNI configuration
  - Cleanup of network traffic rules
  - Cleanup of $HOME/.kube
  - Graceful kube-apiserver shutdown

Performs a best effort revert of changes made by kubeadm init or kubeadm join.

Performs a best effort revert of changes made to this host by 'kubeadm init' or 'kubeadm join'

The "reset" command executes the following phases:

The path to the directory where the certificates are stored. If specified, clean this directory.

Cleanup the "/etc/kubernetes/tmp" directory

Path to a kubeadm configuration file.

Path to the CRI socket to connect. If empty kubeadm will try to auto-detect this value; use this option only if you have more than one CRI installed or if you have non-standard CRI socket.

Don't apply any changes; just output what would be done.

Reset the node without prompting for confirmation.

A list of checks whose errors will be shown as warnings. Example: 'IsPrivilegedUser,Swap'. Value 'all' ignores errors from all checks.

The kubeconfig file to use when talking to the cluster. If the flag is not set, a set of standard locations can be searched for an existing kubeconfig file.

List of phases to be skipped

The path to the 'real' host root filesystem. This will cause kubeadm to chroot into the provided path.

kubeadm reset is responsible for cleaning up a node local file system from files that were created using the kubeadm init or kubeadm join commands. For control-plane nodes reset also removes the local stacked etcd member of this node from the etcd cluster.

kubeadm reset phase can be used to execute the separate phases of the above workflow. To skip a list of phases you can use the --skip-phases flag, which works in a similar way to the kubeadm join and kubeadm init phase runners.

kubeadm reset also supports the --config flag for passing a ResetConfiguration structure.

kubeadm reset will not delete any etcd data if external etcd is used. This means that if you run kubeadm init again using the same etcd endpoints, you will see state from previous clusters.

To wipe etcd data it is recommended you use a client like etcdctl, such as:

See the etcd documentation for more information.

CNI plugins use the directory /etc/cni/net.d to store their configuration. The kubeadm reset command does not cleanup that directory. Leaving the configuration of a CNI plugin on a host can be problematic if the same host is later used as a new Kubernetes node and a different CNI plugin happens to be deployed in that cluster. It can result in a configuration conflict between CNI plugins.

To cleanup the directory, backup its contents if needed and then execute t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
preflight           Run reset pre-flight checks
remove-etcd-member  Remove a local etcd member.
cleanup-node        Run cleanup node.
```

Example 2 (unknown):
```unknown
kubeadm reset [flags]
```

Example 3 (bash):
```bash
etcdctl del "" --prefix
```

Example 4 (bash):
```bash
sudo rm -rf /etc/cni/net.d
```

---
