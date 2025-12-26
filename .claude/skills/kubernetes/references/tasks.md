# Kubernetes - Tasks

**Pages:** 102

---

## Encrypting Confidential Data at Rest

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/

**Contents:**
- Encrypting Confidential Data at Rest
    - Note:
- Before you begin
- Determine whether encryption at rest is already enabled
- Understanding the encryption at rest configuration
    - Note:
    - Caution:
  - Available providers
  - Key storage
    - Local key storage

All of the APIs in Kubernetes that let you write persistent API resource data support at-rest encryption. For example, you can enable at-rest encryption for Secrets. This at-rest encryption is additional to any system-level encryption for the etcd cluster or for the filesystem(s) on hosts where you are running the kube-apiserver.

This page shows how to enable and configure encryption of API data at rest.

This task covers encryption for resource data stored using the Kubernetes API. For example, you can encrypt Secret objects, including the key-value data they contain.

If you want to encrypt data in filesystems that are mounted into containers, you instead need to either:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

This task assumes that you are running the Kubernetes API server as a static pod on each control plane node.

Your cluster's control plane must use etcd v3.x (major version 3, any minor version).

To encrypt a custom resource, your cluster must be running Kubernetes v1.26 or newer.

To use a wildcard to match resources, your cluster must be running Kubernetes v1.27 or newer.

To check the version, enter kubectl version.

By default, the API server stores plain-text representations of resources into etcd, with no at-rest encryption.

The kube-apiserver process accepts an argument --encryption-provider-config that specifies a path to a configuration file. The contents of that file, if you specify one, control how Kubernetes API data is encrypted in etcd. If you are running the kube-apiserver without the --encryption-provider-config command line argument, you do not have encryption at rest enabled. If you are running the kube-apiserver with the --encryption-provider-config command line argument, and the file that it references specifies the identity provider as the first encryption provider in the list, then you do not have at-rest encryption enabled (the default identity provider does not provide any confidentiality protection.)

If you are running the kube-apiserver with the --encryption-provider-config command line argument, and the file that it references specifies a provider other than identity as the first encryptio

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
---
#
# CAUTION: this is an example configuration.
#          Do not use this for your own cluster!
#
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps
      - pandas.awesome.bears.example # a custom resource API
    providers:
      # This configuration does not provide data confidentiality. The first
      # configured provider is specifying the "identity" mechanism, which
      # stores resources as plain text.
      #
      - identity: {} # plain text, in other words NO encryption
      - aesgcm:
          keys
...
```

Example 2 (yaml):
```yaml
...
  - resources:
      - configmaps. # specifically from the core API group,
                    # because of trailing "."
      - events
    providers:
      - identity: {}
  # and then other entries in resources
```

Example 3 (shell):
```shell
head -c 32 /dev/urandom | base64
```

Example 4 (shell):
```shell
head -c 32 /dev/urandom | base64
```

---

## Utilizing the NUMA-aware Memory Manager

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/memory-manager/#windows-support

**Contents:**
- Utilizing the NUMA-aware Memory Manager
- Before you begin
- How does the Memory Manager Operate?
  - Startup
  - Runtime
  - Windows Support
- Memory Manager configuration
  - Policies
    - None policy
    - Static policy

The Kubernetes Memory Manager enables the feature of guaranteed memory (and hugepages) allocation for pods in the Guaranteed QoS class.

The Memory Manager employs hint generation protocol to yield the most suitable NUMA affinity for a pod. The Memory Manager feeds the central manager (Topology Manager) with these affinity hints. Based on both the hints and Topology Manager policy, the pod is rejected or admitted to the node.

Moreover, the Memory Manager ensures that the memory which a pod requests is allocated from a minimum number of NUMA nodes.

The Memory Manager is only pertinent to Linux based hosts.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.32.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To align memory resources with other requested resources in a Pod spec:

Starting from v1.22, the Memory Manager is enabled by default through MemoryManager feature gate.

Preceding v1.22, the kubelet must be started with the following flag:

--feature-gates=MemoryManager=true

in order to enable the Memory Manager feature.

The Memory Manager currently offers the guaranteed memory (and hugepages) allocation for Pods in Guaranteed QoS class. To immediately put the Memory Manager into operation follow the guidelines in the section Memory Manager configuration, and subsequently, prepare and deploy a Guaranteed pod as illustrated in the section Placing a Pod in the Guaranteed QoS class.

The Memory Manager is a Hint Provider, and it provides topology hints for the Topology Manager which then aligns the requested resources according to these topology hints. On Linux, it also enforces cgroups (i.e. cpuset.mems) for pods. The

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
--kube-reserved=cpu=4,memory=4Gi
--system-reserved=cpu=1,memory=1Gi
--memory-manager-policy=Static
--reserved-memory '0:memory=3Gi;1:memory=2148Mi'
```

Example 2 (shell):
```shell
--feature-gates=MemoryManager=true
```

Example 3 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      limits:
        memory: "200Mi"
        cpu: "2"
        example.com/device: "1"
      requests:
        memory: "200Mi"
        cpu: "2"
        example.com/device: "1"
```

Example 4 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      limits:
        memory: "200Mi"
        cpu: "300m"
        example.com/device: "1"
      requests:
        memory: "200Mi"
        cpu: "300m"
        example.com/device: "1"
```

---

## Migrating from dockershim

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/

**Contents:**
- Migrating from dockershim
- What's next
- Feedback

This section presents information you need to know when migrating from dockershim to other container runtimes.

Since the announcement of dockershim deprecation in Kubernetes 1.20, there were questions on how this will affect various workloads and Kubernetes installations. Our Dockershim Removal FAQ is there to help you to understand the problem better.

Dockershim was removed from Kubernetes with the release of v1.24. If you use Docker Engine via dockershim as your container runtime and wish to upgrade to v1.24, it is recommended that you either migrate to another runtime or find an alternative means to obtain Docker Engine support. Check out the container runtimes section to know your options.

The version of Kubernetes with dockershim (1.23) is out of support and the v1.24 will run out of support soon. Make sure to report issues you encountered with the migration so the issues can be fixed in a timely manner and your cluster would be ready for dockershim removal. After v1.24 running out of support, you will need to contact your Kubernetes provider for support or upgrade multiple versions at a time if there are critical issues affecting your cluster.

Your cluster might have more than one kind of node, although this is not a common configuration.

These tasks will help you to migrate:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Run Applications

**URL:** https://kubernetes.io/docs/tasks/run-application/

**Contents:**
- Run Applications
      - Run a Stateless Application Using a Deployment
      - Run a Single-Instance Stateful Application
      - Run a Replicated Stateful Application
      - Scale a StatefulSet
      - Delete a StatefulSet
      - Force Delete StatefulSet Pods
      - Horizontal Pod Autoscaling
      - HorizontalPodAutoscaler Walkthrough
      - Specifying a Disruption Budget for your Application

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Manage HugePages

**URL:** https://kubernetes.io/docs/tasks/manage-hugepages/scheduling-hugepages/

**Contents:**
- Manage HugePages
- Before you begin
    - Note:
- API
- Feedback

Kubernetes supports the allocation and consumption of pre-allocated huge pages by applications in a Pod. This page describes how users can consume huge pages.

Kubernetes nodes must pre-allocate huge pages in order for the node to report its huge page capacity.

A node can pre-allocate huge pages for multiple sizes, for instance, the following line in /etc/default/grub allocates 2*1GiB of 1 GiB and 512*2 MiB of 2 MiB pages:

The nodes will automatically discover and report all huge page resources as schedulable resources.

When you describe the Node, you should see something similar to the following in the following in the Capacity and Allocatable sections:

Huge pages can be consumed via container level resource requirements using the resource name hugepages-<size>, where <size> is the most compact binary notation using integer values supported on a particular node. For example, if a node supports 2048KiB and 1048576KiB page sizes, it will expose a schedulable resources hugepages-2Mi and hugepages-1Gi. Unlike CPU or memory, huge pages do not support overcommit. Note that when requesting hugepage resources, either memory or CPU resources must be requested as well.

A pod may consume multiple huge page sizes in a single pod spec. In this case it must use medium: HugePages-<hugepagesize> notation for all volume mounts.

A pod may use medium: HugePages only if it requests huge pages of one size.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (unknown):
```unknown
GRUB_CMDLINE_LINUX="hugepagesz=1G hugepages=2 hugepagesz=2M hugepages=512"
```

Example 2 (unknown):
```unknown
Capacity:
  cpu:                ...
  ephemeral-storage:  ...
  hugepages-1Gi:      2Gi
  hugepages-2Mi:      1Gi
  memory:             ...
  pods:               ...
Allocatable:
  cpu:                ...
  ephemeral-storage:  ...
  hugepages-1Gi:      2Gi
  hugepages-2Mi:      1Gi
  memory:             ...
  pods:               ...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: huge-pages-example
spec:
  containers:
  - name: example
    image: fedora:latest
    command:
    - sleep
    - inf
    volumeMounts:
    - mountPath: /hugepages-2Mi
      name: hugepage-2mi
    - mountPath: /hugepages-1Gi
      name: hugepage-1gi
    resources:
      limits:
        hugepages-2Mi: 100Mi
        hugepages-1Gi: 2Gi
        memory: 100Mi
      requests:
        memory: 100Mi
  volumes:
  - name: hugepage-2mi
    emptyDir:
      medium: HugePages-2Mi
  - name: hugepage-1gi
    emptyDir:
      medium: HugePages-1Gi
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: huge-pages-example
spec:
  containers:
  - name: example
    image: fedora:latest
    command:
    - sleep
    - inf
    volumeMounts:
    - mountPath: /hugepages
      name: hugepage
    resources:
      limits:
        hugepages-2Mi: 100Mi
        memory: 100Mi
      requests:
        memory: 100Mi
  volumes:
  - name: hugepage
    emptyDir:
      medium: HugePages
```

---

## Install and Set Up kubectl on Linux

**URL:** https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

**Contents:**
- Install and Set Up kubectl on Linux
- Before you begin
- Install kubectl on Linux
  - Install kubectl binary with curl on Linux
    - Note:
    - Note:
    - Note:
  - Install using native package management
    - Note:
    - Note:

You must use a kubectl version that is within one minor version difference of your cluster. For example, a v1.34 client can communicate with v1.33, v1.34, and v1.35 control planes. Using the latest compatible version of kubectl helps avoid unforeseen issues.

The following methods exist for installing kubectl on Linux:

Download the latest release with the command:

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"

To download a specific version, replace the $(curl -L -s https://dl.k8s.io/release/stable.txt) portion of the command with the specific version.

For example, to download version 1.34.0 on Linux x86-64, type:

And for Linux ARM64, type:

Validate the binary (optional)

Download the kubectl checksum file:

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl.sha256"

Validate the kubectl binary against the checksum file:

If valid, the output is:

If the check fails, sha256 exits with nonzero status and prints output similar to:

If you do not have root access on the target system, you can still install kubectl to the ~/.local/bin directory:

Test to ensure the version you installed is up-to-date:

Or use this for detailed view of version:

Update the apt package index and install packages needed to use the Kubernetes apt repository:sudo apt-get update # apt-transport-https may be a dummy package; if so, you can skip that package sudo apt-get install -y apt-transport-https ca-certificates curl gnupg Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:# If the folder `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below. # sudo mkdir -p -m 755 /etc/apt/keyrings curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring Note:In releases older than Debian 12 and Ubuntu 22.04, folder /etc/apt/keyrings does not exist by default, and it should be created be

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

Example 2 (bash):
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
```

Example 3 (bash):
```bash
curl -LO https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl
```

Example 4 (bash):
```bash
curl -LO https://dl.k8s.io/release/v1.34.0/bin/linux/arm64/kubectl
```

---

## Manage Cluster Daemons

**URL:** https://kubernetes.io/docs/tasks/manage-daemon/

**Contents:**
- Manage Cluster Daemons
      - Building a Basic DaemonSet
      - Perform a Rolling Update on a DaemonSet
      - Perform a Rollback on a DaemonSet
      - Running Pods on Only Some Nodes
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Overprovision Node Capacity For A Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/node-overprovisioning/

**Contents:**
- Overprovision Node Capacity For A Cluster
- Before you begin
- Create a PriorityClass
- Run Pods that request node capacity
  - Pick a namespace for the placeholder pods
  - Create the placeholder deployment
- Adjust placeholder resource requests
- Set the desired replica count
  - Calculate the total reserved resources
    - Note:

This page guides you through configuring Node overprovisioning in your Kubernetes cluster. Node overprovisioning is a strategy that proactively reserves a portion of your cluster's compute resources. This reservation helps reduce the time required to schedule new pods during scaling events, enhancing your cluster's responsiveness to sudden spikes in traffic or workload demands.

By maintaining some unused capacity, you ensure that resources are immediately available when new pods are created, preventing them from entering a pending state while the cluster scales up.

Begin by defining a PriorityClass for the placeholder Pods. First, create a PriorityClass with a negative priority value, that you will shortly assign to the placeholder pods. Later, you will set up a Deployment that uses this PriorityClass

Then create the PriorityClass:

You will next define a Deployment that uses the negative-priority PriorityClass and runs a minimal container. When you add this to your cluster, Kubernetes runs those placeholder pods to reserve capacity. Any time there is a capacity shortage, the control plane will pick one these placeholder pods as the first candidate to preempt.

Review the sample manifest:

You should select, or create, a namespace that the placeholder Pods will go into.

Create a Deployment based on that manifest:

Configure the resource requests and limits for the placeholder pods to define the amount of overprovisioned resources you want to maintain. This reservation ensures that a specific amount of CPU and memory is kept available for new pods.

To edit the Deployment, modify the resources section in the Deployment manifest file to set appropriate requests and limits. You can download that file locally and then edit it with whichever text editor you prefer.

You can also edit the Deployment using kubectl:

For example, to reserve a total of a 0.5 CPU and 1GiB of memory across 5 placeholder pods, define the resource requests and limits for a single placeholder pod as follows:

For example, with 5 replicas each reserving 0.1 CPU and 200MiB of memory:Total CPU reserved: 5 × 0.1 = 0.5 (in the Pod specification, you'll write the quantity 500m)Total memory reserved: 5 × 200MiB = 1GiB (in the Pod specification, you'll write 1 Gi)

To scale the Deployment, adjust the number of replicas based on your cluster's size and expected workload:

The output should reflect the updated number of replicas:

Was this page helpful?

Thanks for the feedback. If you have a

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: placeholder # these Pods represent placeholder capacity
value: -1000
globalDefault: false
description: "Negative priority for placeholder pods to enable overprovisioning."
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/priorityclass/low-priority-class.yaml
```

Example 3 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capacity-reservation
  # You should decide what namespace to deploy this into
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: capacity-placeholder
  template:
    metadata:
      labels:
        app.kubernetes.io/name: capacity-placeholder
      annotations:
        kubernetes.io/description: "Capacity reservation"
    spec:
      priorityClassName: placeholder
      affinity: # Try to place these overhead Pods on different nodes
                # if possible
        podAntiAffinity:
          preferredDuring
...
```

Example 4 (shell):
```shell
# Change the namespace name "example"
kubectl --namespace example apply -f https://k8s.io/examples/deployments/deployment-with-capacity-reservation.yaml
```

---

## Decrypt Confidential Data that is Already Encrypted at Rest

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/decrypt-data/

**Contents:**
- Decrypt Confidential Data that is Already Encrypted at Rest
    - Note:
- Before you begin
- Determine whether encryption at rest is already enabled
- Decrypt all data
  - Locate the encryption configuration file
  - Configure the API server to decrypt objects
  - Reconfigure other control plane hosts
  - Force decryption
  - Reconfigure other control plane hosts

All of the APIs in Kubernetes that let you write persistent API resource data support at-rest encryption. For example, you can enable at-rest encryption for Secrets. This at-rest encryption is additional to any system-level encryption for the etcd cluster or for the filesystem(s) on hosts where you are running the kube-apiserver.

This page shows how to switch from encryption of API data at rest, so that API data are stored unencrypted. You might want to do this to improve performance; usually, though, if it was a good idea to encrypt some data, it's also a good idea to leave them encrypted.

This task covers encryption for resource data stored using the Kubernetes API. For example, you can encrypt Secret objects, including the key-value data they contain.

If you wanted to manage encryption for data in filesystems that are mounted into containers, you instead need to either:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

This task assumes that you are running the Kubernetes API server as a static pod on each control plane node.

Your cluster's control plane must use etcd v3.x (major version 3, any minor version).

To encrypt a custom resource, your cluster must be running Kubernetes v1.26 or newer.

You should have some API data that are already encrypted.

To check the version, enter kubectl version.

By default, the API server uses an identity provider that stores plain-text representations of resources. The default identity provider does not provide any confidentiality protection.

The kube-apiserver process accepts an argument --encryption-provider-config that specifies a path to a configuration file. The contents of that file, if you specify one, control how Kubernetes API data is encrypted in etcd. If it is not specified, you do not have encryption at rest enabled.

The format of that configuration file is YAML, representing a configuration API kind named EncryptionConfiguration. You can see an example configuration in Encryption at rest configuration.

If --encryption-provider-config is set, check which resources (such as secrets) are configured for encryption, and what provider is used. Make sure that the preferred provider f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
---
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            # Do not use this (invalid) example key for encryption
            - name: example
              secret: 2KfZgdiq2K0g2YrYpyDYs9mF2LPZhQ==
```

Example 2 (yaml):
```yaml
---
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - identity: {} # add this line
      - aescbc:
          keys:
            - name: example
              secret: 2KfZgdiq2K0g2YrYpyDYs9mF2LPZhQ==
```

Example 3 (shell):
```shell
# If you are decrypting a different kind of object, change "secrets" to match.
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

---

## IP Masquerade Agent User Guide

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/ip-masq-agent/

**Contents:**
- IP Masquerade Agent User Guide
- Before you begin
- IP Masquerade Agent User Guide
  - Key Terms
- Create an ip-masq-agent
    - Note:
- Feedback

This page shows how to configure and enable the ip-masq-agent.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The ip-masq-agent configures iptables rules to hide a pod's IP address behind the cluster node's IP address. This is typically done when sending traffic to destinations outside the cluster's pod CIDR range.

The ip-masq-agent configures iptables rules to handle masquerading node/pod IP addresses when sending traffic to destinations outside the cluster node's IP and the Cluster IP range. This essentially hides pod IP addresses behind the cluster node's IP address. In some environments, traffic to "external" addresses must come from a known machine address. For example, in Google Cloud, any traffic to the internet must come from a VM's IP. When containers are used, as in Google Kubernetes Engine, the Pod IP will be rejected for egress. To avoid this, we must hide the Pod IP behind the VM's own IP address - generally known as "masquerade". By default, the agent is configured to treat the three private IP ranges specified by RFC 1918 as non-masquerade CIDR. These ranges are 10.0.0.0/8, 172.16.0.0/12, and 192.168.0.0/16. The agent will also treat link-local (169.254.0.0/16) as a non-masquerade CIDR by default. The agent is configured to reload its configuration from the location /etc/config/ip-masq-agent every 60 seconds, which is also configurable.

The agent configuration file must be written in YAML or JSON syntax, and may contain three optional keys:

Traffic to 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16 ranges will NOT be masqueraded. Any other traffic (assumed to be internet) will be masqueraded. An example of a local 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
iptables -t nat -L IP-MASQ-AGENT
```

Example 2 (none):
```none
target     prot opt source               destination
RETURN     all  --  anywhere             169.254.0.0/16       /* ip-masq-agent: cluster-local traffic should not be subject to MASQUERADE */ ADDRTYPE match dst-type !LOCAL
RETURN     all  --  anywhere             10.0.0.0/8           /* ip-masq-agent: cluster-local traffic should not be subject to MASQUERADE */ ADDRTYPE match dst-type !LOCAL
RETURN     all  --  anywhere             172.16.0.0/12        /* ip-masq-agent: cluster-local traffic should not be subject to MASQUERADE */ ADDRTYPE match dst-type !LOCAL
RETURN     all  --  anywhere   
...
```

Example 3 (shell):
```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/ip-masq-agent/master/ip-masq-agent.yaml
```

Example 4 (shell):
```shell
kubectl label nodes my-node node.kubernetes.io/masq-agent-ds-ready=true
```

---

## Use Custom Resources

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/

**Contents:**
- Use Custom Resources
      - Extend the Kubernetes API with CustomResourceDefinitions
      - Versions in CustomResourceDefinitions
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Declarative Management of Kubernetes Objects Using Kustomize

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/

**Contents:**
- Declarative Management of Kubernetes Objects Using Kustomize
- Before you begin
- Overview of Kustomize
  - Generating Resources
    - configMapGenerator
    - Note:
    - secretGenerator
    - generatorOptions
  - Setting cross-cutting fields
  - Composing and Customizing Resources

Kustomize is a standalone tool to customize Kubernetes objects through a kustomization file.

Since 1.14, kubectl also supports the management of Kubernetes objects using a kustomization file. To view resources found in a directory containing a kustomization file, run the following command:

To apply those resources, run kubectl apply with --kustomize or -k flag:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Kustomize is a tool for customizing Kubernetes configurations. It has the following features to manage application configuration files:

ConfigMaps and Secrets hold configuration or sensitive data that are used by other Kubernetes objects, such as Pods. The source of truth of ConfigMaps or Secrets are usually external to a cluster, such as a .properties file or an SSH keyfile. Kustomize has secretGenerator and configMapGenerator, which generate Secret and ConfigMap from files or literals.

To generate a ConfigMap from a file, add an entry to the files list in configMapGenerator. Here is an example of generating a ConfigMap with a data item from a .properties file:

The generated ConfigMap can be examined with the following command:

The generated ConfigMap is:

To generate a ConfigMap from an env file, add an entry to the envs list in configMapGenerator. Here is an example of generating a ConfigMap with a data item from a .env file:

The generated ConfigMap can be examined with the following command:

The generated ConfigMap is:

ConfigMaps can also be generated from literal key-value pairs. To generate a ConfigMap from a literal key-value pair, add an entry to the literals list in configMapGenerator. Here is an example of g

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl kustomize <kustomization_directory>
```

Example 2 (shell):
```shell
kubectl apply -k <kustomization_directory>
```

Example 3 (shell):
```shell
# Create a application.properties file
cat <<EOF >application.properties
FOO=Bar
EOF

cat <<EOF >./kustomization.yaml
configMapGenerator:
- name: example-configmap-1
  files:
  - application.properties
EOF
```

Example 4 (shell):
```shell
kubectl kustomize ./
```

---

## Run a Single-Instance Stateful Application

**URL:** https://kubernetes.io/docs/tasks/run-application/run-single-instance-stateful-application/

**Contents:**
- Run a Single-Instance Stateful Application
- Objectives
- Before you begin
- Deploy MySQL
- Accessing the MySQL instance
- Updating
- Deleting a deployment
- What's next
- Feedback

This page shows you how to run a single-instance stateful application in Kubernetes using a PersistentVolume and a Deployment. The application is MySQL.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

You need to either have a dynamic PersistentVolume provisioner with a default StorageClass, or statically provision PersistentVolumes yourself to satisfy the PersistentVolumeClaims used here.

You can run a stateful application by creating a Kubernetes Deployment and connecting it to an existing PersistentVolume using a PersistentVolumeClaim. For example, this YAML file describes a Deployment that runs MySQL and references the PersistentVolumeClaim. The file defines a volume mount for /var/lib/mysql, and then creates a PersistentVolumeClaim that looks for a 20G volume. This claim is satisfied by any existing volume that meets the requirements, or by a dynamic provisioner.

Note: The password is defined in the config yaml, and this is insecure. See Kubernetes Secrets for a secure solution.

Deploy the PV and PVC of the YAML file:

Deploy the contents of the YAML file:

Display information about the Deployment:

The output is similar to this:

List the pods created by the Deployment:

The output is similar to this:

Inspect the PersistentVolumeClaim:

The output is similar to this:

The preceding YAML file creates a service that allows other Pods in the cluster to access the database. The Service option clusterIP: None lets the Service DNS name resolve directly to the Pod's IP address. This is optimal when you have only one Pod behind a Service and you don't intend to increase the number of Pods.

Run a MySQL client to connect to the s

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  ports:
  - port: 3306
  selector:
    app: mysql
  clusterIP: None
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - image: mysql:9
        name: mysql
        env:
          # Use secret in real usage
        - name: MYSQL_ROOT_PASSWORD
          value: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeM
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv-volume
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/mysql/mysql-pv.yaml
```

Example 4 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/mysql/mysql-deployment.yaml
```

---

## Share Process Namespace between Containers in a Pod

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/

**Contents:**
- Share Process Namespace between Containers in a Pod
- Before you begin
- Configure a Pod
- Understanding process namespace sharing
- Feedback

This page shows how to configure process namespace sharing for a pod. When process namespace sharing is enabled, processes in a container are visible to all other containers in the same pod.

You can use this feature to configure cooperating containers, such as a log handler sidecar container, or to troubleshoot container images that don't include debugging utilities like a shell.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Process namespace sharing is enabled using the shareProcessNamespace field of .spec for a Pod. For example:

Create the pod nginx on your cluster:

Attach to the shell container and run ps:

If you don't see a command prompt, try pressing enter. In the container shell:

The output is similar to this:

You can signal processes in other containers. For example, send SIGHUP to nginx to restart the worker process. This requires the SYS_PTRACE capability.

The output is similar to this:

It's even possible to access the file system of another container using the /proc/$pid/root link.

The output is similar to this:

Pods share many resources so it makes sense they would also share a process namespace. Some containers may expect to be isolated from others, though, so it's important to understand the differences:

The container process no longer has PID 1. Some containers refuse to start without PID 1 (for example, containers using systemd) or run commands like kill -HUP 1 to signal the container process. In pods with a shared process namespace, kill -HUP 1 will signal the pod sandbox (/pause in the above example).

Processes are visible to other containers in the pod. This includes all information visible in /proc, such as passwords that were passed as arguments or environment variables. These are protected only by regular Unix permissions.

Container filesystems are visible to other containers in the pod through the /proc/$pid/root link. This makes debugging easier, but it also means that filesystem secrets are protected only by filesystem permissions.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in t

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  shareProcessNamespace: true
  containers:
  - name: nginx
    image: nginx
  - name: shell
    image: busybox:1.28
    command: ["sleep", "3600"]
    securityContext:
      capabilities:
        add:
        - SYS_PTRACE
    stdin: true
    tty: true
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/share-process-namespace.yaml
```

Example 3 (shell):
```shell
kubectl exec -it nginx -c shell -- /bin/sh
```

Example 4 (shell):
```shell
# run this inside the "shell" container
ps ax
```

---

## Attach Handlers to Container Lifecycle Events

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/

**Contents:**
- Attach Handlers to Container Lifecycle Events
- Before you begin
- Define postStart and preStop handlers
- Discussion
    - Note:
- What's next
  - Reference
- Feedback

This page shows how to attach handlers to Container lifecycle events. Kubernetes supports the postStart and preStop events. Kubernetes sends the postStart event immediately after a Container is started, and it sends the preStop event immediately before the Container is terminated. A Container may specify one handler per event.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise, you create a Pod that has one Container. The Container has handlers for the postStart and preStop events.

Here is the configuration file for the Pod:

In the configuration file, you can see that the postStart command writes a message file to the Container's /usr/share directory. The preStop command shuts down nginx gracefully. This is helpful if the Container is being terminated because of a failure.

Verify that the Container in the Pod is running:

Get a shell into the Container running in your Pod:

In your shell, verify that the postStart handler created the message file:

The output shows the text written by the postStart handler:

Kubernetes sends the postStart event immediately after the Container is created. There is no guarantee, however, that the postStart handler is called before the Container's entrypoint is called. The postStart handler runs asynchronously relative to the Container's code, but Kubernetes' management of the container blocks until the postStart handler completes. The Container's status is not set to RUNNING until the postStart handler completes.

Kubernetes sends the preStop event immediately before the Container is terminated. Kubernetes' management of the Container blocks until the preStop handler completes, unle

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-demo
spec:
  containers:
  - name: lifecycle-demo-container
    image: nginx
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]
      preStop:
        exec:
          command: ["/bin/sh","-c","nginx -s quit; while killall -0 nginx; do sleep 1; done"]
```

Example 2 (unknown):
```unknown
kubectl apply -f https://k8s.io/examples/pods/lifecycle-events.yaml
```

Example 3 (unknown):
```unknown
kubectl get pod lifecycle-demo
```

Example 4 (unknown):
```unknown
kubectl exec -it lifecycle-demo -- /bin/bash
```

---

## Logging in Kubernetes

**URL:** https://kubernetes.io/docs/tasks/debug/logging/

**Contents:**
- Logging in Kubernetes
- Feedback

This page provides resources that describe logging in Kubernetes. You can learn how to collect, access, and analyze logs using built-in tools and popular logging stacks:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Troubleshooting Clusters

**URL:** https://kubernetes.io/docs/tasks/debug/debug-cluster/

**Contents:**
- Troubleshooting Clusters
- Listing your cluster
  - Example: debugging a down/unreachable node
- Looking at logs
  - Control Plane nodes
  - Worker Nodes
- Cluster failure modes
  - Contributing causes
  - Specific scenarios
  - Mitigations

This doc is about cluster troubleshooting; we assume you have already ruled out your application as the root cause of the problem you are experiencing. See the application troubleshooting guide for tips on application debugging. You may also visit the troubleshooting overview document for more information.

For troubleshooting kubectl, refer to Troubleshooting kubectl.

The first thing to debug in your cluster is if your nodes are all registered correctly.

Run the following command:

And verify that all of the nodes you expect to see are present and that they are all in the Ready state.

To get detailed information about the overall health of your cluster, you can run:

Sometimes when debugging it can be useful to look at the status of a node -- for example, because you've noticed strange behavior of a Pod that's running on the node, or to find out why a Pod won't schedule onto the node. As with Pods, you can use kubectl describe node and kubectl get node -o yaml to retrieve detailed information about nodes. For example, here's what you'll see if a node is down (disconnected from the network, or kubelet dies and won't restart, etc.). Notice the events that show the node is NotReady, and also notice that the pods are no longer running (they are evicted after five minutes of NotReady status).

For now, digging deeper into the cluster requires logging into the relevant machines. Here are the locations of the relevant log files. On systemd-based systems, you may need to use journalctl instead of examining log files.

This is an incomplete list of things that could go wrong, and how to adjust your cluster setup to mitigate the problems.

Action: Use the IaaS provider's automatic VM restarting feature for IaaS VMs

Action: Use IaaS providers reliable storage (e.g. GCE PD or AWS EBS volume) for VMs with apiserver+etcd

Action: Use high-availability configuration

Action: Snapshot apiserver PDs/EBS-volumes periodically

Action: use replication controller and services in front of pods

Action: applications (containers) designed to tolerate unexpected restarts

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes
```

Example 2 (shell):
```shell
kubectl cluster-info dump
```

Example 3 (shell):
```shell
kubectl get nodes
```

Example 4 (none):
```none
NAME                     STATUS       ROLES     AGE     VERSION
kube-worker-1            NotReady     <none>    1h      v1.23.3
kubernetes-node-bols     Ready        <none>    1h      v1.23.3
kubernetes-node-st6x     Ready        <none>    1h      v1.23.3
kubernetes-node-unaj     Ready        <none>    1h      v1.23.3
```

---

## Using sysctls in a Kubernetes Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/

**Contents:**
- Using sysctls in a Kubernetes Cluster
    - Note:
- Before you begin
    - Note:
- Listing all Sysctl Parameters
- Safe and Unsafe Sysctls
    - Note:
  - Enabling Unsafe Sysctls
- Setting Sysctls for a Pod
    - Warning:

This document describes how to configure and use kernel parameters within a Kubernetes cluster using the sysctl interface.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

For some steps, you also need to be able to reconfigure the command line options for the kubelets running on your cluster.

In Linux, the sysctl interface allows an administrator to modify kernel parameters at runtime. Parameters are available via the /proc/sys/ virtual process file system. The parameters cover various subsystems such as:

To get a list of all parameters, you can run

Kubernetes classes sysctls as either safe or unsafe. In addition to proper namespacing, a safe sysctl must be properly isolated between pods on the same node. This means that setting a safe sysctl for one pod

By far, most of the namespaced sysctls are not necessarily considered safe. The following sysctls are supported in the safe set:

There are some exceptions to the set of safe sysctls:

This list will be extended in future Kubernetes versions when the kubelet supports better isolation mechanisms.

All safe sysctls are enabled by default.

All unsafe sysctls are disabled by default and must be allowed manually by the cluster admin on a per-node basis. Pods with disabled unsafe sysctls will be scheduled, but will fail to launch.

With the warning above in mind, the cluster admin can allow certain unsafe sysctls for very special situations such as high-performance or real-time application tuning. Unsafe sysctls are enabled on a node-by-node basis with a flag of the kubelet; for example:

For Minikube, this can be done via the extra-config flag:

Only namespaced sysctls can be enabled this way.

A number of sysctls are namespaced in today's Linux kernels. This means that they can be set independently for each pod on a node. Only namespaced sysctls are configurable via the pod securityContext within Kubernetes.

The following sysctls are known to be namespaced. This list could change in future versions of the Linux kernel.

Sysctls with no namespace are called node-level sysctls. If you need to set them, you must manually configure them on each node's operating system, or by using a Daem

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
sudo sysctl -a
```

Example 2 (shell):
```shell
kubelet --allowed-unsafe-sysctls \
  'kernel.msg*,net.core.somaxconn' ...
```

Example 3 (shell):
```shell
minikube start --extra-config="kubelet.allowed-unsafe-sysctls=kernel.msg*,net.core.somaxconn"...
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sysctl-example
spec:
  securityContext:
    sysctls:
    - name: kernel.shm_rmid_forced
      value: "0"
    - name: net.core.somaxconn
      value: "1024"
    - name: kernel.msgmax
      value: "65536"
  ...
```

---

## Advertise Extended Resources for a Node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/extended-resource-node/

**Contents:**
- Advertise Extended Resources for a Node
- Before you begin
- Get the names of your Nodes
- Advertise a new extended resource on one of your Nodes
    - Note:
- Discussion
  - Storage example
- Clean up
- What's next
  - For application developers

This page shows how to specify extended resources for a Node. Extended resources allow cluster administrators to advertise node-level resources that would otherwise be unknown to Kubernetes.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Choose one of your Nodes to use for this exercise.

To advertise a new extended resource on a Node, send an HTTP PATCH request to the Kubernetes API server. For example, suppose one of your Nodes has four dongles attached. Here's an example of a PATCH request that advertises four dongle resources for your Node.

Note that Kubernetes does not need to know what a dongle is or what a dongle is for. The preceding PATCH request tells Kubernetes that your Node has four things that you call dongles.

Start a proxy, so that you can easily send requests to the Kubernetes API server:

In another command window, send the HTTP PATCH request. Replace <your-node-name> with the name of your Node:

The output shows that the Node has a capacity of 4 dongles:

Once again, the output shows the dongle resource:

Now, application developers can create Pods that request a certain number of dongles. See Assign Extended Resources to a Container.

Extended resources are similar to memory and CPU resources. For example, just as a Node has a certain amount of memory and CPU to be shared by all components running on the Node, it can have a certain number of dongles to be shared by all components running on the Node. And just as application developers can create Pods that request a certain amount of memory and CPU, they can create Pods that request a certain number of dongles.

Extended resources are opaque to Kubernetes; Ku

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes
```

Example 2 (unknown):
```unknown
PATCH /api/v1/nodes/<your-node-name>/status HTTP/1.1
Accept: application/json
Content-Type: application/json-patch+json
Host: k8s-master:8080

[
  {
    "op": "add",
    "path": "/status/capacity/example.com~1dongle",
    "value": "4"
  }
]
```

Example 3 (shell):
```shell
kubectl proxy
```

Example 4 (shell):
```shell
curl --header "Content-Type: application/json-patch+json" \
  --request PATCH \
  --data '[{"op": "add", "path": "/status/capacity/example.com~1dongle", "value": "4"}]' \
  http://localhost:8001/api/v1/nodes/<your-node-name>/status
```

---

## Cloud Controller Manager Administration

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/running-cloud-controller/

**Contents:**
- Cloud Controller Manager Administration
- Administration
  - Requirements
  - Running cloud-controller-manager
- Examples
- Limitations
  - Support for Volumes
  - Scalability
  - Chicken and Egg
- What's next

Since cloud providers develop and release at a different pace compared to the Kubernetes project, abstracting the provider-specific code to the cloud-controller-manager binary allows cloud vendors to evolve independently from the core Kubernetes code.

The cloud-controller-manager can be linked to any cloud provider that satisfies cloudprovider.Interface. For backwards compatibility, the cloud-controller-manager provided in the core Kubernetes project uses the same cloud libraries as kube-controller-manager. Cloud providers already supported in Kubernetes core are expected to use the in-tree cloud-controller-manager to transition out of Kubernetes core.

Every cloud has their own set of requirements for running their own cloud provider integration, it should not be too different from the requirements when running kube-controller-manager. As a general rule of thumb you'll need:

Successfully running cloud-controller-manager requires some changes to your cluster configuration.

Keep in mind that setting up your cluster to use cloud controller manager will change your cluster behaviour in a few ways:

The cloud controller manager can implement:

If you are using a cloud that is currently supported in Kubernetes core and would like to adopt cloud controller manager, see the cloud controller manager in kubernetes core.

For cloud controller managers not in Kubernetes core, you can find the respective projects in repositories maintained by cloud vendors or by SIGs.

For providers already in Kubernetes core, you can run the in-tree cloud controller manager as a DaemonSet in your cluster, use the following as a guideline:

Running cloud controller manager comes with a few possible limitations. Although these limitations are being addressed in upcoming releases, it's important that you are aware of these limitations for production workloads.

Cloud controller manager does not implement any of the volume controllers found in kube-controller-manager as the volume integrations also require coordination with kubelets. As we evolve CSI (container storage interface) and add stronger support for flex volume plugins, necessary support will be added to cloud controller manager so that clouds can fully integrate with volumes. Learn more about out-of-tree CSI volume plugins here.

The cloud-controller-manager queries your cloud provider's APIs to retrieve information for all nodes. For very large clusters, consider possible bottlenecks such as resource requirements and API ra

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# This is an example of how to set up cloud-controller-manager as a Daemonset in your cluster.
# It assumes that your masters can run pods and has the role node-role.kubernetes.io/master
# Note that this Daemonset will not work straight out of the box for your cloud, this is
# meant to be a guideline.

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
 
...
```

---

## Job with Pod-to-Pod Communication

**URL:** https://kubernetes.io/docs/tasks/job/job-with-pod-to-pod-communication/

**Contents:**
- Job with Pod-to-Pod Communication
- Before you begin
    - Note:
- Starting a Job with pod-to-pod communication
  - Example
    - Note:
    - Note:
- Feedback

In this example, you will run a Job in Indexed completion mode configured such that the pods created by the Job can communicate with each other using pod hostnames rather than pod IP addresses.

Pods within a Job might need to communicate among themselves. The user workload running in each pod could query the Kubernetes API server to learn the IPs of the other Pods, but it's much simpler to rely on Kubernetes' built-in DNS resolution.

Jobs in Indexed completion mode automatically set the pods' hostname to be in the format of ${jobName}-${completionIndex}. You can use this format to deterministically build pod hostnames and enable pod communication without needing to create a client connection to the Kubernetes control plane to obtain pod hostnames/IPs via API requests.

This configuration is useful for use cases where pod networking is required but you don't want to depend on a network connection with the Kubernetes API server.

You should already be familiar with the basic use of Job.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.21.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To enable pod-to-pod communication using pod hostnames in a Job, you must do the following:

Set up a headless Service with a valid label selector for the pods created by your Job. The headless service must be in the same namespace as the Job. One easy way to do this is to use the job-name: <your-job-name> selector, since the job-name label will be automatically added by Kubernetes. This configuration will trigger the DNS system to create records of the hostnames of the pods running your Job.

Configure the headless service as subdomain ser

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
subdomain: <headless-svc-name>
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: headless-svc
spec:
  clusterIP: None # clusterIP must be None to create a headless service
  selector:
    job-name: example-job # must match Job name
---
apiVersion: batch/v1
kind: Job
metadata:
  name: example-job
spec:
  completions: 3
  parallelism: 3
  completionMode: Indexed
  template:
    spec:
      subdomain: headless-svc # has to match Service name
      restartPolicy: Never
      containers:
      - name: example-workload
        image: bash:latest
        command:
        - bash
        - -c
        - |
          for i in 0 1 2
      
...
```

Example 3 (shell):
```shell
kubectl logs example-job-0-qws42
```

Example 4 (unknown):
```unknown
Failed to ping pod example-job-0.headless-svc, retrying in 1 second...
Successfully pinged pod: example-job-0.headless-svc
Successfully pinged pod: example-job-1.headless-svc
Successfully pinged pod: example-job-2.headless-svc
```

---

## Migrate Replicated Control Plane To Use Cloud Controller Manager

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/controller-manager-leader-migration/

**Contents:**
- Migrate Replicated Control Plane To Use Cloud Controller Manager
- Background
- Before you begin
  - Grant access to Migration Lease
  - Initial Leader Migration configuration
  - Deploy Cloud Controller Manager
  - Upgrade Control Plane
  - (Optional) Disable Leader Migration
  - Default Configuration
  - Special case: migrating the Node IPAM controller

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

By decoupling the interoperability logic between Kubernetes and the underlying cloud infrastructure, the cloud-controller-manager component enables cloud providers to release features at a different pace compared to the main Kubernetes project.

As part of the cloud provider extraction effort, all cloud specific controllers must be moved out of the kube-controller-manager. All existing clusters that run cloud controllers in the kube-controller-manager must migrate to instead run the controllers in a cloud provider specific cloud-controller-manager.

Leader Migration provides a mechanism in which HA clusters can safely migrate "cloud specific" controllers between the kube-controller-manager and the cloud-controller-manager via a shared resource lock between the two components while upgrading the replicated control plane. For a single-node control plane, or if unavailability of controller managers can be tolerated during the upgrade, Leader Migration is not needed and this guide can be ignored.

Leader Migration can be enabled by setting --enable-leader-migration on kube-controller-manager or cloud-controller-manager. Leader Migration only applies during the upgrade and can be safely disabled or left enabled after the upgrade is complete.

This guide walks you through the manual process of upgrading the control plane from kube-controller-manager with built-in cloud provider to running both kube-controller-manager and cloud-controller-manager. If you use a tool to deploy and manage the cluster, please refer to the documentation of the tool and the cloud provider for specific instructions of the migration.

It is assumed that the control plane is running Kubernetes version N and to be upgraded to version N + 1. Although it is possible to migrate within the same version, ideally the migration should be performed as part o

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl patch -n kube-system role 'system::leader-locking-kube-controller-manager' -p '{"rules": [ {"apiGroups":[ "coordination.k8s.io"], "resources": ["leases"], "resourceNames": ["cloud-provider-extraction-migration"], "verbs": ["create", "list", "get", "update"] } ]}' --type=merge`
```

Example 2 (shell):
```shell
kubectl patch -n kube-system role 'system::leader-locking-cloud-controller-manager' -p '{"rules": [ {"apiGroups":[ "coordination.k8s.io"], "resources": ["leases"], "resourceNames": ["cloud-provider-extraction-migration"], "verbs": ["create", "list", "get", "update"] } ]}' --type=merge`
```

Example 3 (yaml):
```yaml
kind: LeaderMigrationConfiguration
apiVersion: controllermanager.config.k8s.io/v1
leaderName: cloud-provider-extraction-migration
resourceLock: leases
controllerLeaders:
  - name: route
    component: kube-controller-manager
  - name: service
    component: kube-controller-manager
  - name: cloud-node-lifecycle
    component: kube-controller-manager
```

Example 4 (yaml):
```yaml
# wildcard version
kind: LeaderMigrationConfiguration
apiVersion: controllermanager.config.k8s.io/v1
leaderName: cloud-provider-extraction-migration
resourceLock: leases
controllerLeaders:
  - name: route
    component: *
  - name: service
    component: *
  - name: cloud-node-lifecycle
    component: *
```

---

## Verify Signed Kubernetes Artifacts

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/

**Contents:**
- Verify Signed Kubernetes Artifacts
- Before you begin
- Verifying binary signatures
    - Note:
- Verifying image signatures
  - Verifying images for all control plane components
- Verifying Image Signatures with Admission Controller
- Verify the Software Bill Of Materials
- Feedback

You will need to have the following tools installed:

The Kubernetes release process signs all binary artifacts (tarballs, SPDX files, standalone binaries) by using cosign's keyless signing. To verify a particular binary, retrieve it together with its signature and certificate:

Then verify the blob by using cosign verify-blob:

Cosign 2.0 requires the --certificate-identity and --certificate-oidc-issuer options.

To learn more about keyless signing, please refer to Keyless Signatures.

Previous versions of Cosign required that you set COSIGN_EXPERIMENTAL=1.

For additional information, please refer to the sigstore Blog

For a complete list of images that are signed please refer to Releases.

Pick one image from this list and verify its signature using the cosign verify command:

To verify all signed control plane images for the latest stable version (v1.34.0), please run the following commands:

Once you have verified an image, you can specify the image by its digest in your Pod manifests as per this example:

For more information, please refer to the Image Pull Policy section.

For non-control plane images (for example conformance image), signatures can also be verified at deploy time using sigstore policy-controller admission controller.

Here are some helpful resources to get started with policy-controller:

You can verify the Kubernetes Software Bill of Materials (SBOM) by using the sigstore certificate and signature, or the corresponding SHA files:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (bash):
```bash
URL=https://dl.k8s.io/release/v1.34.0/bin/linux/amd64
BINARY=kubectl

FILES=(
    "$BINARY"
    "$BINARY.sig"
    "$BINARY.cert"
)

for FILE in "${FILES[@]}"; do
    curl -sSfL --retry 3 --retry-delay 3 "$URL/$FILE" -o "$FILE"
done
```

Example 2 (shell):
```shell
cosign verify-blob "$BINARY" \
  --signature "$BINARY".sig \
  --certificate "$BINARY".cert \
  --certificate-identity krel-staging@k8s-releng-prod.iam.gserviceaccount.com \
  --certificate-oidc-issuer https://accounts.google.com
```

Example 3 (shell):
```shell
cosign verify registry.k8s.io/kube-apiserver-amd64:v1.34.0 \
  --certificate-identity krel-trust@k8s-releng-prod.iam.gserviceaccount.com \
  --certificate-oidc-issuer https://accounts.google.com \
  | jq .
```

Example 4 (shell):
```shell
curl -Ls "https://sbom.k8s.io/$(curl -Ls https://dl.k8s.io/release/stable.txt)/release" \
  | grep "SPDXID: SPDXRef-Package-registry.k8s.io" \
  | grep -v sha256 | cut -d- -f3- | sed 's/-/\//' | sed 's/-v1/:v1/' \
  | sort > images.txt
input=images.txt
while IFS= read -r image
do
  cosign verify "$image" \
    --certificate-identity krel-trust@k8s-releng-prod.iam.gserviceaccount.com \
    --certificate-oidc-issuer https://accounts.google.com \
    | jq .
done < "$input"
```

---

## Operating etcd clusters for Kubernetes

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster

**Contents:**
- Operating etcd clusters for Kubernetes
- Before you begin
  - Resource requirements for etcd
  - Tools
- Understanding etcdctl and etcdutl
- Starting etcd clusters
  - Single-node etcd cluster
  - Multi-node etcd cluster
  - Multi-node etcd cluster with load balancer
- Securing etcd clusters

etcd is a consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

etcd is a consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth information about etcd in the official documentation.

Before you follow steps in this page to deploy, manage, back up or restore etcd, you need to understand the typical expectations for operating an etcd cluster. Refer to the etcd documentation for more context.

The minimum recommended etcd versions to run in production are 3.4.22+ and 3.5.6+.

etcd is a leader-based distributed system. Ensure that the leader periodically send heartbeats on time to all followers to keep the cluster stable.

You should run etcd as a cluster with an odd number of members.

Aim to ensure that no resource starvation occurs.

Performance and stability of the cluster is sensitive to network and disk I/O. Any resource starvation can lead to heartbeat timeout, causing instability of the cluster. An unstable etcd indicates that no leader is elected. Under such circumstances, a cluster cannot make any changes to its current state, which implies no new pods can be scheduled.

Operating etcd with limited resources is suitable only for testing purposes. For deploying in production, advanced hardware configuration is required. Before deploying etcd in production, see resource requirement reference.

Keeping etcd clusters stable is critical to the stability of Kubernetes clusters. Therefore, run etcd clusters on dedicated machines or isolated environments for guaranteed resource requirements.

Depending on which specific outcome you're working on, you will need the etcdctl tool or the etcdutl tool (you may need both).

etcdctl and etcdutl are command-line tools used to interact with etcd clusters, but they serve different purposes:

etcdctl: This is the primary command-line client for interacting with etcd over a network. It is used for day-to-day operations such as managing keys and values, administering the cluster, checking health, and more.

etcdutl: This is an administration utility designed to operate directly on etcd data files, including migrating data between etcd versions, defragmenting the database, restoring snapshots, and validating data consistency. For network operations, etcdctl should be used.

For more information

*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
etcd --listen-client-urls=http://$PRIVATE_IP:2379 \
   --advertise-client-urls=http://$PRIVATE_IP:2379
```

Example 2 (shell):
```shell
etcd --listen-client-urls=http://$IP1:2379,http://$IP2:2379,http://$IP3:2379,http://$IP4:2379,http://$IP5:2379 --advertise-client-urls=http://$IP1:2379,http://$IP2:2379,http://$IP3:2379,http://$IP4:2379,http://$IP5:2379
```

Example 3 (unknown):
```unknown
ETCDCTL_API=3 etcdctl --endpoints 10.2.0.9:2379 \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member list
```

Example 4 (shell):
```shell
etcdctl --endpoints=http://10.0.0.2,http://10.0.0.3 member list
```

---

## Monitoring in Kubernetes

**URL:** https://kubernetes.io/docs/tasks/debug/monitoring/

**Contents:**
- Monitoring in Kubernetes
- Feedback

This page provides resources that describe monitoring in Kubernetes. You can learn how to collect system metrics and traces for Kubernetes system components:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Configure Pod Initialization

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-initialization/

**Contents:**
- Configure Pod Initialization
- Before you begin
- Create a Pod that has an Init Container
- What's next
- Feedback

This page shows how to use an Init Container to initialize a Pod before an application Container runs.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise you create a Pod that has one application Container and one Init Container. The init container runs to completion before the application container starts.

Here is the configuration file for the Pod:

In the configuration file, you can see that the Pod has a Volume that the init container and the application container share.

The init container mounts the shared Volume at /work-dir, and the application container mounts the shared Volume at /usr/share/nginx/html. The init container runs the following command and then terminates:

Notice that the init container writes the index.html file in the root directory of the nginx server.

Verify that the nginx container is running:

The output shows that the nginx container is running:

Get a shell into the nginx container running in the init-demo Pod:

In your shell, send a GET request to the nginx server:

The output shows that nginx is serving the web page that was written by the init container:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: workdir
      mountPath: /usr/share/nginx/html
  # These containers are run during pod initialization
  initContainers:
  - name: install
    image: busybox:1.28
    command:
    - wget
    - "-O"
    - "/work-dir/index.html"
    - http://info.cern.ch
    volumeMounts:
    - name: workdir
      mountPath: "/work-dir"
  dnsPolicy: Default
  volumes:
  - name: workdir
    emptyDir: {}
```

Example 2 (shell):
```shell
wget -O /work-dir/index.html http://info.cern.ch
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/init-containers.yaml
```

Example 4 (shell):
```shell
kubectl get pod init-demo
```

---

## Share a Cluster with Namespaces

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/namespaces/

**Contents:**
- Share a Cluster with Namespaces
- Before you begin
- Viewing namespaces
- Creating a new namespace
    - Note:
- Deleting a namespace
    - Warning:
- Subdividing your cluster using Kubernetes namespaces
  - Create new namespaces
  - Create pods in each namespace

This page shows how to view, work in, and delete namespaces. The page also shows how to use Kubernetes namespaces to subdivide your cluster.

List the current namespaces in a cluster using:

Kubernetes starts with four initial namespaces:

You can also get the summary of a specific namespace using:

Or you can get detailed information with:

Note that these details show both resource quota (if present) as well as resource limit ranges.

Resource quota tracks aggregate usage of resources in the Namespace and allows cluster operators to define Hard resource usage limits that a Namespace may consume.

A limit range defines min/max constraints on the amount of resources a single entity can consume in a Namespace.

See Admission control: Limit Range

A namespace can be in one of two phases:

For more details, see Namespace in the API reference.

Create a new YAML file called my-namespace.yaml with the contents:

Alternatively, you can create namespace using below command:

The name of your namespace must be a valid DNS label.

There's an optional field finalizers, which allows observables to purge resources whenever the namespace is deleted. Keep in mind that if you specify a nonexistent finalizer, the namespace will be created but will get stuck in the Terminating state if the user tries to delete it.

More information on finalizers can be found in the namespace design doc.

Delete a namespace with

This delete is asynchronous, so for a time you will see the namespace in the Terminating state.

By default, a Kubernetes cluster will instantiate a default namespace when provisioning the cluster to hold the default set of Pods, Services, and Deployments used by the cluster.

Assuming you have a fresh cluster, you can introspect the available namespaces by doing the following:

For this exercise, we will create two additional Kubernetes namespaces to hold our content.

In a scenario where an organization is using a shared Kubernetes cluster for development and production use cases:

The development team would like to maintain a space in the cluster where they can get a view on the list of Pods, Services, and Deployments they use to build and run their application. In this space, Kubernetes resources come and go, and the restrictions on who can or cannot modify resources are relaxed to enable agile development.

The operations team would like to maintain a space in the cluster where they can enforce strict procedures on who can or cannot manipulate the set of Pods,

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get namespaces
```

Example 2 (console):
```console
NAME              STATUS   AGE
default           Active   11d
kube-node-lease   Active   11d
kube-public       Active   11d
kube-system       Active   11d
```

Example 3 (shell):
```shell
kubectl get namespaces <name>
```

Example 4 (shell):
```shell
kubectl describe namespaces <name>
```

---

## Run a Stateless Application Using a Deployment

**URL:** https://kubernetes.io/docs/tasks/run-application/run-stateless-application-deployment/

**Contents:**
- Run a Stateless Application Using a Deployment
- Objectives
- Before you begin
- Creating and exploring an nginx deployment
- Updating the deployment
- Scaling the application by increasing the replica count
- Deleting a deployment
- ReplicationControllers -- the Old Way
- What's next
- Feedback

This page shows how to run an application using a Kubernetes Deployment object.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.9.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

You can run an application by creating a Kubernetes Deployment object, and you can describe a Deployment in a YAML file. For example, this YAML file describes a Deployment that runs the nginx:1.14.2 Docker image:

Create a Deployment based on the YAML file:

Display information about the Deployment:

The output is similar to this:

List the Pods created by the deployment:

The output is similar to this:

Display information about a Pod:

where <pod-name> is the name of one of your Pods.

You can update the deployment by applying a new YAML file. This YAML file specifies that the deployment should be updated to use nginx 1.16.1.

Apply the new YAML file:

Watch the deployment create pods with new names and delete the old pods:

You can increase the number of Pods in your Deployment by applying a new YAML file. This YAML file sets replicas to 4, which specifies that the Deployment should have four Pods:

Apply the new YAML file:

Verify that the Deployment has four Pods:

The output is similar to this:

Delete the deployment by name:

The preferred way to create a replicated application is to use a Deployment, which in turn uses a ReplicaSet. Before the Deployment and ReplicaSet were added to Kubernetes, replicated applications were configured using a ReplicationController.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2 # tells deployment to run 2 pods matching the template
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/deployment.yaml
```

Example 3 (shell):
```shell
kubectl describe deployment nginx-deployment
```

Example 4 (unknown):
```unknown
Name:     nginx-deployment
Namespace:    default
CreationTimestamp:  Tue, 30 Aug 2016 18:11:37 -0700
Labels:     app=nginx
Annotations:    deployment.kubernetes.io/revision=1
Selector:   app=nginx
Replicas:   2 desired | 2 updated | 2 total | 2 available | 0 unavailable
StrategyType:   RollingUpdate
MinReadySeconds:  0
RollingUpdateStrategy:  1 max unavailable, 1 max surge
Pod Template:
  Labels:       app=nginx
  Containers:
    nginx:
    Image:              nginx:1.14.2
    Port:               80/TCP
    Environment:        <none>
    Mounts:             <none>
  Volumes:              <none
...
```

---

## Declare Network Policy

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/

**Contents:**
- Declare Network Policy
- Before you begin
- Create an nginx deployment and expose it via a service
- Test the service by accessing it from another Pod
- Limit access to the nginx service
    - Note:
- Assign the policy to the service
- Test access to the service when access label is not defined
- Define access label and test again
- Feedback

This document helps you get started using the Kubernetes NetworkPolicy API to declare network policies that govern how pods communicate with each other.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.8.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Make sure you've configured a network provider with network policy support. There are a number of network providers that support NetworkPolicy, including:

To see how Kubernetes network policy works, start off by creating an nginx Deployment.

Expose the Deployment through a Service called nginx.

The above commands create a Deployment with an nginx Pod and expose the Deployment through a Service named nginx. The nginx Pod and Deployment are found in the default namespace.

You should be able to access the new nginx service from other Pods. To access the nginx Service from another Pod in the default namespace, start a busybox container:

In your shell, run the following command:

To limit the access to the nginx service so that only Pods with the label access: true can query it, create a NetworkPolicy object as follows:

The name of a NetworkPolicy object must be a valid DNS subdomain name.

Use kubectl to create a NetworkPolicy from the above nginx-policy.yaml file:

When you attempt to access the nginx Service from a Pod without the correct labels, the request times out:

In your shell, run the command:

You can create a Pod with the correct labels to see that the request is allowed:

In your shell, run the command:

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't respons

*[Content truncated]*

**Examples:**

Example 1 (console):
```console
kubectl create deployment nginx --image=nginx
```

Example 2 (none):
```none
deployment.apps/nginx created
```

Example 3 (console):
```console
kubectl expose deployment nginx --port=80
```

Example 4 (none):
```none
service/nginx exposed
```

---

## Install Tools

**URL:** https://kubernetes.io/docs/tasks/tools/#minikube

**Contents:**
- Install Tools
- kubectl
- kind
- minikube
- kubeadm
- Feedback

The Kubernetes command-line tool, kubectl, allows you to run commands against Kubernetes clusters. You can use kubectl to deploy applications, inspect and manage cluster resources, and view logs. For more information including a complete list of kubectl operations, see the kubectl reference documentation.

kubectl is installable on a variety of Linux platforms, macOS and Windows. Find your preferred operating system below.

kind lets you run Kubernetes on your local computer. This tool requires that you have either Docker or Podman installed.

The kind Quick Start page shows you what you need to do to get up and running with kind.

View kind Quick Start Guide

Like kind, minikube is a tool that lets you run Kubernetes locally. minikube runs an all-in-one or a multi-node local Kubernetes cluster on your personal computer (including Windows, macOS and Linux PCs) so that you can try out Kubernetes, or for daily development work.

You can follow the official Get Started! guide if your focus is on getting the tool installed.

View minikube Get Started! Guide

Once you have minikube working, you can use it to run a sample application.

You can use the kubeadm tool to create and manage Kubernetes clusters. It performs the actions necessary to get a minimum viable, secure cluster up and running in a user friendly way.

Installing kubeadm shows you how to install kubeadm. Once installed, you can use it to create a cluster.

View kubeadm Install Guide

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Debugging DNS Resolution

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/

**Contents:**
- Debugging DNS Resolution
- Before you begin
  - Create a simple Pod to use as a test environment
    - Note:
  - Check the local DNS configuration first
  - Check if the DNS pod is running
    - Note:
  - Check for errors in the DNS pod
  - Is DNS service up?
    - Note:

This page provides hints on diagnosing DNS problems.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour cluster must be configured to use the CoreDNS addon or its precursor, kube-dns.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Your Kubernetes server must be at or later than version v1.6.

To check the version, enter kubectl version.

Use that manifest to create a Pod:

…and verify its status:

Once that Pod is running, you can exec nslookup in that environment. If you see something like the following, DNS is working correctly.

If the nslookup command fails, check the following:

Take a look inside the resolv.conf file. (See Customizing DNS Service and Known issues below for more information)

Verify that the search path and name server are set up like the following (note that search path may vary for different cloud providers):

Errors such as the following indicate a problem with the CoreDNS (or kube-dns) add-on or with associated Services:

Use the kubectl get pods command to verify that the DNS pod is running.

If you see that no CoreDNS Pod is running or that the Pod has failed/completed, the DNS add-on may not be deployed by default in your current environment and you will have to deploy it manually.

Use the kubectl logs command to see logs for the DNS containers.

Here is an example of a healthy CoreDNS log:

See if there are any suspicious or unexpected messages in the logs.

Verify that the DNS service is up by using the kubectl get service command.

If you have created the Service or in the case it should be created by default but it does not appear, see debugging Services for more information.

You can verify that DNS endpoints are exposed by using the kubectl get endpointslice command.

If you do not see the endpoints, see the endpoints section in

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dnsutils
  namespace: default
spec:
  containers:
  - name: dnsutils
    image: registry.k8s.io/e2e-test-images/agnhost:2.39
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
```

Example 3 (unknown):
```unknown
pod/dnsutils created
```

Example 4 (shell):
```shell
kubectl get pods dnsutils
```

---

## Windows debugging tips

**URL:** https://kubernetes.io/docs/tasks/debug/debug-cluster/windows/

**Contents:**
- Windows debugging tips
- Node-level troubleshooting
    - Note:
- Network troubleshooting
  - Flannel troubleshooting
  - Further investigation
- Feedback

My Pods are stuck at "Container Creating" or restarting over and over

Ensure that your pause image is compatible with your Windows OS version. See Pause container to see the latest / recommended pause image and/or get more information.

My pods show status as ErrImgPull or ImagePullBackOff

Ensure that your Pod is getting scheduled to a compatible Windows Node.

More information on how to specify a compatible node for your Pod can be found in this guide.

My Windows Pods do not have network connectivity

If you are using virtual machines, ensure that MAC spoofing is enabled on all the VM network adapter(s).

My Windows Pods cannot ping external resources

Windows Pods do not have outbound rules programmed for the ICMP protocol. However, TCP/UDP is supported. When trying to demonstrate connectivity to resources outside of the cluster, substitute ping <IP> with corresponding curl <IP> commands.

If you are still facing problems, most likely your network configuration in cni.conf deserves some extra attention. You can always edit this static file. The configuration update will apply to any new Kubernetes resources.

One of the Kubernetes networking requirements (see Kubernetes model) is for cluster communication to occur without NAT internally. To honor this requirement, there is an ExceptionList for all the communication where you do not want outbound NAT to occur. However, this also means that you need to exclude the external IP you are trying to query from the ExceptionList. Only then will the traffic originating from your Windows pods be SNAT'ed correctly to receive a response from the outside world. In this regard, your ExceptionList in cni.conf should look as follows:

My Windows node cannot access NodePort type Services

Local NodePort access from the node itself fails. This is a known limitation. NodePort access works from other nodes or external clients.

vNICs and HNS endpoints of containers are being deleted

This issue can be caused when the hostname-override parameter is not passed to kube-proxy. To resolve it, users need to pass the hostname to kube-proxy as follows:

My Windows node cannot access my services using the service IP

This is a known limitation of the networking stack on Windows. However, Windows Pods can access the Service IP.

No network adapter is found when starting the kubelet

The Windows networking stack needs a virtual adapter for Kubernetes networking to work. If the following commands return no results (in an admin shell)

*[Content truncated]*

**Examples:**

Example 1 (conf):
```conf
"ExceptionList": [
                "10.244.0.0/16",  # Cluster subnet
                "10.96.0.0/12",   # Service subnet
                "10.127.130.0/24" # Management (host) subnet
            ]
```

Example 2 (powershell):
```powershell
C:\k\kube-proxy.exe --hostname-override=$(hostname)
```

Example 3 (powershell):
```powershell
Get-HnsNetwork | ? Name -ieq "cbr0"
Get-NetAdapter | ? Name -Like "vEthernet (Ethernet*"
```

Example 4 (PowerShell):
```PowerShell
[Environment]::SetEnvironmentVariable("HTTP_PROXY", "http://proxy.example.com:80/", [EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", "http://proxy.example.com:443/", [EnvironmentVariableTarget]::Machine)
```

---

## Generate Certificates Manually

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/certificates/

**Contents:**
- Generate Certificates Manually
  - easyrsa
  - openssl
  - cfssl
- Distributing Self-Signed CA Certificate
- Certificates API
- Feedback

When using client certificate authentication, you can generate certificates manually through easyrsa, openssl or cfssl.

easyrsa can manually generate certificates for your cluster.

Download, unpack, and initialize the patched version of easyrsa3.

Generate a new certificate authority (CA). --batch sets automatic mode; --req-cn specifies the Common Name (CN) for the CA's new root certificate.

Generate server certificate and key.

The argument --subject-alt-name sets the possible IPs and DNS names the API server will be accessed with. The MASTER_CLUSTER_IP is usually the first IP from the service CIDR that is specified as the --service-cluster-ip-range argument for both the API server and the controller manager component. The argument --days is used to set the number of days after which the certificate expires. The sample below also assumes that you are using cluster.local as the default DNS domain name.

Copy pki/ca.crt, pki/issued/server.crt, and pki/private/server.key to your directory.

Fill in and add the following parameters into the API server start parameters:

openssl can manually generate certificates for your cluster.

Generate a ca.key with 2048bit:

According to the ca.key generate a ca.crt (use -days to set the certificate effective time):

Generate a server.key with 2048bit:

Create a config file for generating a Certificate Signing Request (CSR).

Be sure to substitute the values marked with angle brackets (e.g. <MASTER_IP>) with real values before saving this to a file (e.g. csr.conf). Note that the value for MASTER_CLUSTER_IP is the service cluster IP for the API server as described in previous subsection. The sample below also assumes that you are using cluster.local as the default DNS domain name.

Generate the certificate signing request based on the config file:

Generate the server certificate using the ca.key, ca.crt and server.csr:

View the certificate signing request:

View the certificate:

Finally, add the same parameters into the API server start parameters.

cfssl is another tool for certificate generation.

Download, unpack and prepare the command line tools as shown below.

Note that you may need to adapt the sample commands based on the hardware architecture and cfssl version you are using.

Create a directory to hold the artifacts and initialize cfssl:

Create a JSON config file for generating the CA file, for example, ca-config.json:

Create a JSON config file for CA certificate signing request (CSR), for example, ca-cs

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
curl -LO https://dl.k8s.io/easy-rsa/easy-rsa.tar.gz
tar xzf easy-rsa.tar.gz
cd easy-rsa-master/easyrsa3
./easyrsa init-pki
```

Example 2 (shell):
```shell
./easyrsa --batch "--req-cn=${MASTER_IP}@`date +%s`" build-ca nopass
```

Example 3 (shell):
```shell
./easyrsa --subject-alt-name="IP:${MASTER_IP},"\
"IP:${MASTER_CLUSTER_IP},"\
"DNS:kubernetes,"\
"DNS:kubernetes.default,"\
"DNS:kubernetes.default.svc,"\
"DNS:kubernetes.default.svc.cluster,"\
"DNS:kubernetes.default.svc.cluster.local" \
--days=10000 \
build-server-full server nopass
```

Example 4 (shell):
```shell
--client-ca-file=/yourdirectory/ca.crt
--tls-cert-file=/yourdirectory/server.crt
--tls-private-key-file=/yourdirectory/server.key
```

---

## Safely Drain a Node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/

**Contents:**
- Safely Drain a Node
- Before you begin
- (Optional) Configure a disruption budget
- Use kubectl drain to remove a node from service
    - Note:
    - Note:
- Draining multiple nodes in parallel
- The Eviction API
- What's next
- Feedback

This page shows how to safely drain a node, optionally respecting the PodDisruptionBudget you have defined.

This task assumes that you have met the following prerequisites:

To ensure that your workloads remain available during maintenance, you can configure a PodDisruptionBudget.

If availability is important for any applications that run or could run on the node(s) that you are draining, configure a PodDisruptionBudgets first and then continue following this guide.

It is recommended to set AlwaysAllow Unhealthy Pod Eviction Policy to your PodDisruptionBudgets to support eviction of misbehaving applications during a node drain. The default behavior is to wait for the application pods to become healthy before the drain can proceed.

You can use kubectl drain to safely evict all of your pods from a node before you perform maintenance on the node (e.g. kernel upgrade, hardware maintenance, etc.). Safe evictions allow the pod's containers to gracefully terminate and will respect the PodDisruptionBudgets you have specified.

When kubectl drain returns successfully, that indicates that all of the pods (except the ones excluded as described in the previous paragraph) have been safely evicted (respecting the desired graceful termination period, and respecting the PodDisruptionBudget you have defined). It is then safe to bring down the node by powering down its physical machine or, if running on a cloud platform, deleting its virtual machine.

If any new Pods tolerate the node.kubernetes.io/unschedulable taint, then those Pods might be scheduled to the node you have drained. Avoid tolerating that taint other than for DaemonSets.

If you or another API user directly set the nodeName field for a Pod (bypassing the scheduler), then the Pod is bound to the specified node and will run there, even though you have drained that node and marked it unschedulable.

First, identify the name of the node you wish to drain. You can list all of the nodes in your cluster with

Next, tell Kubernetes to drain the node:

If there are pods managed by a DaemonSet, you will need to specify --ignore-daemonsets with kubectl to successfully drain the node. The kubectl drain subcommand on its own does not actually drain a node of its DaemonSet pods: the DaemonSet controller (part of the control plane) immediately replaces missing Pods with new equivalent Pods. The DaemonSet controller also creates Pods that ignore unschedulable taints, which allows the new Pods to launch onto a node that 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes
```

Example 2 (shell):
```shell
kubectl drain --ignore-daemonsets <node name>
```

Example 3 (shell):
```shell
kubectl uncordon <node name>
```

---

## TLS

**URL:** https://kubernetes.io/docs/tasks/tls/

**Contents:**
- TLS
      - Issue a Certificate for a Kubernetes API Client Using A CertificateSigningRequest
      - Configure Certificate Rotation for the Kubelet
      - Manage TLS Certificates in a Cluster
      - Manual Rotation of CA Certificates
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Schedule GPUs

**URL:** https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/#third-party-content-disclaimer

**Contents:**
- Schedule GPUs
- Using device plugins
- Manage clusters with different types of GPUs
- Automatic node labelling
    - GPU vendor implementations
- Feedback

Kubernetes includes stable support for managing AMD and NVIDIA GPUs (graphical processing units) across different nodes in your cluster, using device plugins.

This page describes how users can consume GPUs, and outlines some of the limitations in the implementation.

Kubernetes implements device plugins to let Pods access specialized hardware features such as GPUs.

As an administrator, you have to install GPU drivers from the corresponding hardware vendor on the nodes and run the corresponding device plugin from the GPU vendor. Here are some links to vendors' instructions:

Once you have installed the plugin, your cluster exposes a custom schedulable resource such as amd.com/gpu or nvidia.com/gpu.

You can consume these GPUs from your containers by requesting the custom GPU resource, the same way you request cpu or memory. However, there are some limitations in how you specify the resource requirements for custom devices.

GPUs are only supposed to be specified in the limits section, which means:

Here's an example manifest for a Pod that requests a GPU:

If different nodes in your cluster have different types of GPUs, then you can use Node Labels and Node Selectors to schedule pods to appropriate nodes.

That label key accelerator is just an example; you can use a different label key if you prefer.

As an administrator, you can automatically discover and label all your GPU enabled nodes by deploying Kubernetes Node Feature Discovery (NFD). NFD detects the hardware features that are available on each node in a Kubernetes cluster. Typically, NFD is configured to advertise those features as node labels, but NFD can also add extended resources, annotations, and node taints. NFD is compatible with all supported versions of Kubernetes. By default NFD create the feature labels for the detected features. Administrators can leverage NFD to also taint nodes with specific features, so that only pods that request those features can be scheduled on those nodes.

You also need a plugin for NFD that adds appropriate labels to your nodes; these might be generic labels or they could be vendor specific. Your GPU vendor may provide a third party plugin for NFD; check their documentation for more details.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should rea

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-vector-add
spec:
  restartPolicy: OnFailure
  containers:
    - name: example-vector-add
      image: "registry.example/example-vector-add:v42"
      resources:
        limits:
          gpu-vendor.example/example-gpu: 1 # requesting 1 GPU
```

Example 2 (shell):
```shell
# Label your nodes with the accelerator type they have.
kubectl label nodes node1 accelerator=example-gpu-x100
kubectl label nodes node2 accelerator=other-gpu-k915
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-vector-add
spec:
  restartPolicy: OnFailure
  # You can use Kubernetes node affinity to schedule this Pod onto a node
  # that provides the kind of GPU that its container needs in order to work
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "gpu.gpu-vendor.example/installed-memory"
            operator: Gt # (greater than)
            values: ["40535"]
          - key: "feature.node.kubernetes.io/pci-10.present" # NFD Feature label
    
...
```

---

## Configure Default Memory Requests and Limits for a Namespace

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/

**Contents:**
- Configure Default Memory Requests and Limits for a Namespace
- Before you begin
- Create a namespace
- Create a LimitRange and a Pod
- What if you specify a container's limit, but not its request?
- What if you specify a container's request, but not its limit?
    - Note:
- Motivation for default memory limits and requests
- Clean up
- What's next

This page shows how to configure default memory requests and limits for a namespace.

A Kubernetes cluster can be divided into namespaces. Once you have a namespace that has a default memory limit, and you then try to create a Pod with a container that does not specify its own memory limit, then the control plane assigns the default memory limit to that container.

Kubernetes assigns a default memory request under certain conditions that are explained later in this topic.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You must have access to create namespaces in your cluster.

Each node in your cluster must have at least 2 GiB of memory.

Create a namespace so that the resources you create in this exercise are isolated from the rest of your cluster.

Here's a manifest for an example LimitRange. The manifest specifies a default memory request and a default memory limit.

Create the LimitRange in the default-mem-example namespace:

Now if you create a Pod in the default-mem-example namespace, and any container within that Pod does not specify its own values for memory request and memory limit, then the control plane applies default values: a memory request of 256MiB and a memory limit of 512MiB.

Here's an example manifest for a Pod that has one container. The container does not specify a memory request and limit.

View detailed information about the Pod:

The output shows that the Pod's container has a memory request of 256 MiB and a memory limit of 512 MiB. These are the default values specified by the LimitRange.

Here's a manifest for a Pod that has one container. The container specifies a memory limit, but not a request:

View detailed information about the Pod:

The output shows that the container's memory request is set to match its memory limit. Notice that the container was not assigned the default memory request value of 256Mi.

Here's a manifest for a Pod that has one container. The container specifies a memory request, but not a limit:

View the Pod's specification:

The output shows that the container's memory request is set to the value specified in the container's manifest. The container is limited to use no more than 512

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create namespace default-mem-example
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: mem-limit-range
spec:
  limits:
  - default:
      memory: 512Mi
    defaultRequest:
      memory: 256Mi
    type: Container
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/admin/resource/memory-defaults.yaml --namespace=default-mem-example
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: default-mem-demo
spec:
  containers:
  - name: default-mem-demo-ctr
    image: nginx
```

---

## Using NodeLocal DNSCache in Kubernetes Clusters

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/

**Contents:**
- Using NodeLocal DNSCache in Kubernetes Clusters
- Before you begin
- Introduction
- Motivation
- Architecture Diagram
    - Nodelocal DNSCache flow
- Configuration
    - Note:
- StubDomains and Upstream server Configuration
- Setting memory limits

This page provides an overview of NodeLocal DNSCache feature in Kubernetes.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

NodeLocal DNSCache improves Cluster DNS performance by running a DNS caching agent on cluster nodes as a DaemonSet. In today's architecture, Pods in 'ClusterFirst' DNS mode reach out to a kube-dns serviceIP for DNS queries. This is translated to a kube-dns/CoreDNS endpoint via iptables rules added by kube-proxy. With this new architecture, Pods will reach out to the DNS caching agent running on the same node, thereby avoiding iptables DNAT rules and connection tracking. The local caching agent will query kube-dns service for cache misses of cluster hostnames ("cluster.local" suffix by default).

With the current DNS architecture, it is possible that Pods with the highest DNS QPS have to reach out to a different node, if there is no local kube-dns/CoreDNS instance. Having a local cache will help improve the latency in such scenarios.

Skipping iptables DNAT and connection tracking will help reduce conntrack races and avoid UDP DNS entries filling up conntrack table.

Connections from the local caching agent to kube-dns service can be upgraded to TCP. TCP conntrack entries will be removed on connection close in contrast with UDP entries that have to timeout (default nf_conntrack_udp_timeout is 30 seconds)

Upgrading DNS queries from UDP to TCP would reduce tail latency attributed to dropped UDP packets and DNS timeouts usually up to 30s (3 retries + 10s timeout). Since the nodelocal cache listens for UDP DNS queries, applications don't need to be changed.

Metrics & visibility into DNS requests at a node level.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubedns=`kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}`
domain=<cluster-domain>
localdns=<node-local-address>
```

Example 2 (bash):
```bash
sed -i "s/__PILLAR__LOCAL__DNS__/$localdns/g; s/__PILLAR__DNS__DOMAIN__/$domain/g; s/__PILLAR__DNS__SERVER__/$kubedns/g" nodelocaldns.yaml
```

Example 3 (bash):
```bash
sed -i "s/__PILLAR__LOCAL__DNS__/$localdns/g; s/__PILLAR__DNS__DOMAIN__/$domain/g; s/,__PILLAR__DNS__SERVER__//g; s/__PILLAR__CLUSTER__DNS__/$kubedns/g" nodelocaldns.yaml
```

---

## Run a Replicated Stateful Application

**URL:** https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/

**Contents:**
- Run a Replicated Stateful Application
    - Note:
- Before you begin
- Objectives
- Deploy MySQL
  - Create a ConfigMap
  - Create Services
  - Create the StatefulSet
    - Note:
- Understanding stateful Pod initialization

This page shows how to run a replicated stateful application using a StatefulSet. This application is a replicated MySQL database. The example topology has a single primary server and multiple replicas, using asynchronous row-based replication.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to either have a dynamic PersistentVolume provisioner with a default StorageClass, or statically provision PersistentVolumes yourself to satisfy the PersistentVolumeClaims used here.

The example MySQL deployment consists of a ConfigMap, two Services, and a StatefulSet.

Create the ConfigMap from the following YAML configuration file:

This ConfigMap provides my.cnf overrides that let you independently control configuration on the primary MySQL server and its replicas. In this case, you want the primary server to be able to serve replication logs to replicas and you want replicas to reject any writes that don't come via replication.

There's nothing special about the ConfigMap itself that causes different portions to apply to different Pods. Each Pod decides which portion to look at as it's initializing, based on information provided by the StatefulSet controller.

Create the Services from the following YAML configuration file:

The headless Service provides a home for the DNS entries that the StatefulSet controllers creates for each Pod that's part of the set. Because the headless Service is named mysql, the Pods are accessible by resolving <pod-name>.mysql from within any other Pod in the same Kubernetes cluster and namespace.

The client Service, called mysql-read, is a normal Service with its own cluster IP that distributes connections across all MySQL Pods that report being Ready. The set of potential endpoints includes the primary MySQL server and all replicas.

Note that only read queries can use the load-balanced client Service. Because there is only one primary MySQL server, clients should connect directly to the primary MySQL Pod (through its DNS entry within the headless Service) to execute writes.

Finally, create the StatefulSet from the following YAML configuration file:

You can watch the startup progress by running:

After 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql
  labels:
    app: mysql
    app.kubernetes.io/name: mysql
data:
  primary.cnf: |
    # Apply this config only on the primary.
    [mysqld]
    log-bin    
  replica.cnf: |
    # Apply this config only on replicas.
    [mysqld]
    super-read-only
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/mysql/mysql-configmap.yaml
```

Example 3 (yaml):
```yaml
# Headless service for stable DNS entries of StatefulSet members.
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql
    app.kubernetes.io/name: mysql
spec:
  ports:
  - name: mysql
    port: 3306
  clusterIP: None
  selector:
    app: mysql
---
# Client service for connecting to any MySQL instance for reads.
# For writes, you must instead connect to the primary: mysql-0.mysql.
apiVersion: v1
kind: Service
metadata:
  name: mysql-read
  labels:
    app: mysql
    app.kubernetes.io/name: mysql
    readonly: "true"
spec:
  ports:
  - name: mysql
    port: 3306
  select
...
```

Example 4 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/mysql/mysql-services.yaml
```

---

## Install Tools

**URL:** https://kubernetes.io/docs/tasks/tools/

**Contents:**
- Install Tools
- kubectl
- kind
- minikube
- kubeadm
- Feedback

The Kubernetes command-line tool, kubectl, allows you to run commands against Kubernetes clusters. You can use kubectl to deploy applications, inspect and manage cluster resources, and view logs. For more information including a complete list of kubectl operations, see the kubectl reference documentation.

kubectl is installable on a variety of Linux platforms, macOS and Windows. Find your preferred operating system below.

kind lets you run Kubernetes on your local computer. This tool requires that you have either Docker or Podman installed.

The kind Quick Start page shows you what you need to do to get up and running with kind.

View kind Quick Start Guide

Like kind, minikube is a tool that lets you run Kubernetes locally. minikube runs an all-in-one or a multi-node local Kubernetes cluster on your personal computer (including Windows, macOS and Linux PCs) so that you can try out Kubernetes, or for daily development work.

You can follow the official Get Started! guide if your focus is on getting the tool installed.

View minikube Get Started! Guide

Once you have minikube working, you can use it to run a sample application.

You can use the kubeadm tool to create and manage Kubernetes clusters. It performs the actions necessary to get a minimum viable, secure cluster up and running in a user friendly way.

Installing kubeadm shows you how to install kubeadm. Once installed, you can use it to create a cluster.

View kubeadm Install Guide

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Resource metrics pipeline

**URL:** https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/

**Contents:**
- Resource metrics pipeline
    - Note:
    - Note:
- Metrics API
    - Note:
- Measuring resource usage
  - CPU
  - Memory
- Metrics Server
- What's next

For Kubernetes, the Metrics API offers a basic set of metrics to support automatic scaling and similar use cases. This API makes information available about resource usage for node and pod, including metrics for CPU and memory. If you deploy the Metrics API into your cluster, clients of the Kubernetes API can then query for this information, and you can use Kubernetes' access control mechanisms to manage permissions to do so.

The HorizontalPodAutoscaler (HPA) and VerticalPodAutoscaler (VPA) use data from the metrics API to adjust workload replicas and resources to meet customer demand.

You can also view the resource metrics using the kubectl top command.

Figure 1 illustrates the architecture of the resource metrics pipeline.

Figure 1. Resource Metrics Pipeline

The architecture components, from right to left in the figure, consist of the following:

cAdvisor: Daemon for collecting, aggregating and exposing container metrics included in Kubelet.

kubelet: Node agent for managing container resources. Resource metrics are accessible using the /metrics/resource and /stats kubelet API endpoints.

node level resource metrics: API provided by the kubelet for discovering and retrieving per-node summarized stats available through the /metrics/resource endpoint.

metrics-server: Cluster addon component that collects and aggregates resource metrics pulled from each kubelet. The API server serves Metrics API for use by HPA, VPA, and by the kubectl top command. Metrics Server is a reference implementation of the Metrics API.

Metrics API: Kubernetes API supporting access to CPU and memory used for workload autoscaling. To make this work in your cluster, you need an API extension server that provides the Metrics API.

The metrics-server implements the Metrics API. This API allows you to access CPU and memory usage for the nodes and pods in your cluster. Its primary role is to feed resource usage metrics to K8s autoscaler components.

Here is an example of the Metrics API request for a minikube node piped through jq for easier reading:

Here is the same API call using curl:

Here is an example of the Metrics API request for a kube-scheduler-minikube pod contained in the kube-system namespace and piped through jq for easier reading:

Here is the same API call using curl:

The Metrics API is defined in the k8s.io/metrics repository. You must enable the API aggregation layer and register an APIService for the metrics.k8s.io API.

To learn more about the Metrics API, see

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes/minikube" | jq '.'
```

Example 2 (shell):
```shell
curl http://localhost:8080/apis/metrics.k8s.io/v1beta1/nodes/minikube
```

Example 3 (json):
```json
{
  "kind": "NodeMetrics",
  "apiVersion": "metrics.k8s.io/v1beta1",
  "metadata": {
    "name": "minikube",
    "selfLink": "/apis/metrics.k8s.io/v1beta1/nodes/minikube",
    "creationTimestamp": "2022-01-27T18:48:43Z"
  },
  "timestamp": "2022-01-27T18:48:33Z",
  "window": "30s",
  "usage": {
    "cpu": "487558164n",
    "memory": "732212Ki"
  }
}
```

Example 4 (shell):
```shell
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/kube-system/pods/kube-scheduler-minikube" | jq '.'
```

---

## Install Tools

**URL:** https://kubernetes.io/docs/tasks/tools/#kubectl

**Contents:**
- Install Tools
- kubectl
- kind
- minikube
- kubeadm
- Feedback

The Kubernetes command-line tool, kubectl, allows you to run commands against Kubernetes clusters. You can use kubectl to deploy applications, inspect and manage cluster resources, and view logs. For more information including a complete list of kubectl operations, see the kubectl reference documentation.

kubectl is installable on a variety of Linux platforms, macOS and Windows. Find your preferred operating system below.

kind lets you run Kubernetes on your local computer. This tool requires that you have either Docker or Podman installed.

The kind Quick Start page shows you what you need to do to get up and running with kind.

View kind Quick Start Guide

Like kind, minikube is a tool that lets you run Kubernetes locally. minikube runs an all-in-one or a multi-node local Kubernetes cluster on your personal computer (including Windows, macOS and Linux PCs) so that you can try out Kubernetes, or for daily development work.

You can follow the official Get Started! guide if your focus is on getting the tool installed.

View minikube Get Started! Guide

Once you have minikube working, you can use it to run a sample application.

You can use the kubeadm tool to create and manage Kubernetes clusters. It performs the actions necessary to get a minimum viable, secure cluster up and running in a user friendly way.

Installing kubeadm shows you how to install kubeadm. Once installed, you can use it to create a cluster.

View kubeadm Install Guide

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Tasks

**URL:** https://kubernetes.io/docs/tasks/

**Contents:**
      - Install Tools
      - Administer a Cluster
      - Configure Pods and Containers
      - Monitoring, Logging, and Debugging
      - Manage Kubernetes Objects
      - Managing Secrets
      - Inject Data Into Applications
      - Run Applications
      - Run Jobs
      - Access Applications in a Cluster

This section of the Kubernetes documentation contains pages that show how to do individual tasks. A task page shows how to do a single thing, typically by giving a short sequence of steps.

If you would like to write a task page, see Creating a Documentation Pull Request.

Set up Kubernetes tools on your computer.

Learn common tasks for administering a cluster.

Perform common configuration tasks for Pods and containers.

Set up monitoring and logging to troubleshoot a cluster, or debug a containerized application.

Declarative and imperative paradigms for interacting with the Kubernetes API.

Managing confidential settings data using Secrets.

Specify configuration and other data for the Pods that run your workload.

Run and manage both stateless and stateful applications.

Run Jobs using parallel processing.

Configure load balancing, port forwarding, or setup firewall or DNS configurations to access applications in a cluster.

Understand advanced ways to adapt your Kubernetes cluster to the needs of your work environment.

Understand how to protect traffic within your cluster using Transport Layer Security (TLS).

Perform common tasks for managing a DaemonSet, such as performing a rolling update.

Learn how to configure networking for your cluster.

Extend kubectl by creating and installing kubectl plugins.

Configure and manage huge pages as a schedulable resource in a cluster.

Configure and schedule GPUs for use as a resource by nodes in a cluster.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Resize CPU and Memory Resources assigned to Containers

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/

**Contents:**
- Resize CPU and Memory Resources assigned to Containers
- Before you begin
- Pod resize status
  - How kubelet retries Deferred resizes
  - Leveraging observedGeneration Fields
- Container resize policies
    - Note:
- Limitations
- Example 1: Resizing CPU without restart
    - Note:

This page explains how to change the CPU and memory resource requests and limits assigned to a container without recreating the Pod.

Traditionally, changing a Pod's resource requirements necessitated deleting the existing Pod and creating a replacement, often managed by a workload controller. In-place Pod Resize allows changing the CPU/memory allocation of container(s) within a running Pod while potentially avoiding application disruption.

If a node has pods with a pending or incomplete resize (see Pod Resize Status below), the scheduler uses the maximum of a container's desired requests, allocated requests, and actual requests from the status when making scheduling decisions.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.33.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The InPlacePodVerticalScaling feature gate must be enabled for your control plane and for all nodes in your cluster.

The kubectl client version must be at least v1.32 to use the --subresource=resize flag.

The Kubelet updates the Pod's status conditions to indicate the state of a resize request:

If the requested resize is Deferred, the kubelet will periodically re-attempt the resize, for example when another pod is removed or scaled down. If there are multiple deferred resizes, they are retried according to the following priority:

A higher priority resize being marked as pending will not block the remaining pending resizes from being attempted; all remaining pending resizes will still be retried even if a higher-priority resize gets deferred again.

You can control whether a container should be restarted when resizing by setting resizePolicy in t

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired
    - resourceName: memory
      restartPolicy: RestartContainer
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resize-demo
spec:
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.8
    resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired # Default, but explicit here
    - resourceName: memory
      restartPolicy: RestartContainer
    resources:
      limits:
        memory: "200Mi"
        cpu: "700m"
      requests:
        memory: "200Mi"
        cpu: "700m"
```

Example 3 (shell):
```shell
kubectl create -f pod-resize.yaml
```

Example 4 (shell):
```shell
# Wait a moment for the pod to be running
kubectl get pod resize-demo --output=yaml
```

---

## Schedule GPUs

**URL:** https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/

**Contents:**
- Schedule GPUs
- Using device plugins
- Manage clusters with different types of GPUs
- Automatic node labelling
    - GPU vendor implementations
- Feedback

Kubernetes includes stable support for managing AMD and NVIDIA GPUs (graphical processing units) across different nodes in your cluster, using device plugins.

This page describes how users can consume GPUs, and outlines some of the limitations in the implementation.

Kubernetes implements device plugins to let Pods access specialized hardware features such as GPUs.

As an administrator, you have to install GPU drivers from the corresponding hardware vendor on the nodes and run the corresponding device plugin from the GPU vendor. Here are some links to vendors' instructions:

Once you have installed the plugin, your cluster exposes a custom schedulable resource such as amd.com/gpu or nvidia.com/gpu.

You can consume these GPUs from your containers by requesting the custom GPU resource, the same way you request cpu or memory. However, there are some limitations in how you specify the resource requirements for custom devices.

GPUs are only supposed to be specified in the limits section, which means:

Here's an example manifest for a Pod that requests a GPU:

If different nodes in your cluster have different types of GPUs, then you can use Node Labels and Node Selectors to schedule pods to appropriate nodes.

That label key accelerator is just an example; you can use a different label key if you prefer.

As an administrator, you can automatically discover and label all your GPU enabled nodes by deploying Kubernetes Node Feature Discovery (NFD). NFD detects the hardware features that are available on each node in a Kubernetes cluster. Typically, NFD is configured to advertise those features as node labels, but NFD can also add extended resources, annotations, and node taints. NFD is compatible with all supported versions of Kubernetes. By default NFD create the feature labels for the detected features. Administrators can leverage NFD to also taint nodes with specific features, so that only pods that request those features can be scheduled on those nodes.

You also need a plugin for NFD that adds appropriate labels to your nodes; these might be generic labels or they could be vendor specific. Your GPU vendor may provide a third party plugin for NFD; check their documentation for more details.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should rea

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-vector-add
spec:
  restartPolicy: OnFailure
  containers:
    - name: example-vector-add
      image: "registry.example/example-vector-add:v42"
      resources:
        limits:
          gpu-vendor.example/example-gpu: 1 # requesting 1 GPU
```

Example 2 (shell):
```shell
# Label your nodes with the accelerator type they have.
kubectl label nodes node1 accelerator=example-gpu-x100
kubectl label nodes node2 accelerator=other-gpu-k915
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-vector-add
spec:
  restartPolicy: OnFailure
  # You can use Kubernetes node affinity to schedule this Pod onto a node
  # that provides the kind of GPU that its container needs in order to work
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "gpu.gpu-vendor.example/installed-memory"
            operator: Gt # (greater than)
            values: ["40535"]
          - key: "feature.node.kubernetes.io/pci-10.present" # NFD Feature label
    
...
```

---

## Accessing Clusters

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/

**Contents:**
- Accessing Clusters
- Accessing for the first time with kubectl
- Directly accessing the REST API
  - Using kubectl proxy
  - Without kubectl proxy
- Programmatic access to the API
  - Go client
  - Python client
  - Other languages
- Accessing the API from a Pod

This topic discusses multiple ways to interact with clusters.

When accessing the Kubernetes API for the first time, we suggest using the Kubernetes CLI, kubectl.

To access a cluster, you need to know the location of the cluster and have credentials to access it. Typically, this is automatically set-up when you work through a Getting started guide, or someone else set up the cluster and provided you with credentials and a location.

Check the location and credentials that kubectl knows about with this command:

Many of the examples provide an introduction to using kubectl, and complete documentation is found in the kubectl reference.

Kubectl handles locating and authenticating to the apiserver. If you want to directly access the REST API with an http client like curl or wget, or a browser, there are several ways to locate and authenticate:

The following command runs kubectl in a mode where it acts as a reverse proxy. It handles locating the apiserver and authenticating. Run it like this:

See kubectl proxy for more details.

Then you can explore the API with curl, wget, or a browser, replacing localhost with [::1] for IPv6, like so:

The output is similar to this:

Use kubectl apply and kubectl describe secret... to create a token for the default service account with grep/cut:

First, create the Secret, requesting a token for the default ServiceAccount:

Next, wait for the token controller to populate the Secret with a token:

Capture and use the generated token:

The output is similar to this:

The output is similar to this:

The above examples use the --insecure flag. This leaves it subject to MITM attacks. When kubectl accesses the cluster it uses a stored root certificate and client certificates to access the server. (These are installed in the ~/.kube directory). Since cluster certificates are typically self-signed, it may take special configuration to get your http client to use root certificate.

On some clusters, the apiserver does not require authentication; it may serve on localhost, or be protected by a firewall. There is not a standard for this. Controlling Access to the API describes how a cluster admin can configure this.

Kubernetes officially supports Go and Python client libraries.

The Go client can use the same kubeconfig file as the kubectl CLI does to locate and authenticate to the apiserver. See this example.

If the application is deployed as a Pod in the cluster, please refer to the next section.

To use Python client, run the fo

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl config view
```

Example 2 (shell):
```shell
kubectl proxy --port=8080
```

Example 3 (shell):
```shell
curl http://localhost:8080/api/
```

Example 4 (json):
```json
{
  "kind": "APIVersions",
  "versions": [
    "v1"
  ],
  "serverAddressByClientCIDRs": [
    {
      "clientCIDR": "0.0.0.0/0",
      "serverAddress": "10.0.1.149:443"
    }
  ]
}
```

---

## Manual Rotation of CA Certificates

**URL:** https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/

**Contents:**
- Manual Rotation of CA Certificates
- Before you begin
- Rotate the CA certificates manually
    - Caution:
    - Note:
    - Note:
    - Note:
    - Note:
- Feedback

This page shows how to manually rotate the certificate authority (CA) certificates.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Make sure to back up your certificate directory along with configuration files and any other necessary files.

This approach assumes operation of the Kubernetes control plane in a HA configuration with multiple API servers. Graceful termination of the API server is also assumed so clients can cleanly disconnect from one API server and reconnect to another.

Configurations with a single API server will experience unavailability while the API server is being restarted.

Distribute the new CA certificates and private keys (for example: ca.crt, ca.key, front-proxy-ca.crt, and front-proxy-ca.key) to all your control plane nodes in the Kubernetes certificates directory.

Update the --root-ca-file flag for the kube-controller-manager to include both old and new CA, then restart the kube-controller-manager.

Any ServiceAccount created after this point will get Secrets that include both old and new CAs.

The files specified by the kube-controller-manager flags --client-ca-file and --cluster-signing-cert-file cannot be CA bundles. If these flags and --root-ca-file point to the same ca.crt file which is now a bundle (includes both old and new CA) you will face an error. To workaround this problem you can copy the new CA to a separate file and make the flags --client-ca-file and --cluster-signing-cert-file point to the copy. Once ca.crt is no longer a bundle you can restore the problem flags to point to ca.crt and delete the copy.

Issue 1350 for kubeadm tracks an bug with the kube-controller-manager being unable to accept a CA bundle.

Wait for the controller manager to update ca.crt in the service account Secrets to include both old and new CA certificates.

If any Pods are started before new CA is used by API servers, the new Pods get this update and will trust both old and new CAs.

Restart all pods using in-cluster configurations (for example: kube-proxy, CoreDNS, etc) so they can use the updated certificate authority data from Secrets that link to ServiceAccounts.

Append the both old and new CA to the file agai

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
To generate certificates and private keys for your cluster using the `openssl` command line tool,
  see [Certificates (`openssl`)](/docs/tasks/administer-cluster/certificates/#openssl).
  You can also use [`cfssl`](/docs/tasks/administer-cluster/certificates/#cfssl).
```

Example 2 (shell):
```shell
for namespace in $(kubectl get namespace -o jsonpath='{.items[*].metadata.name}'); do
    for name in $(kubectl get deployments -n $namespace -o jsonpath='{.items[*].metadata.name}'); do
        kubectl patch deployment -n ${namespace} ${name} -p '{"spec":{"template":{"metadata":{"annotations":{"ca-rotation": "1"}}}}}';
    done
    for name in $(kubectl get daemonset -n $namespace -o jsonpath='{.items[*].metadata.name}'); do
        kubectl patch daemonset -n ${namespace} ${name} -p '{"spec":{"template":{"metadata":{"annotations":{"ca-rotation": "1"}}}}}';
    done
done
```

Example 3 (unknown):
```unknown
To limit the number of concurrent disruptions that your application experiences,
  see [configure pod disruption budget](/docs/tasks/run-application/configure-pdb/).
```

Example 4 (unknown):
```unknown
Depending on how you use StatefulSets you may also need to perform similar rolling replacement.
```

---

## Define Environment Variables for a Container

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/

**Contents:**
- Define Environment Variables for a Container
- Before you begin
- Define an environment variable for a container
    - Note:
    - Note:
- Using environment variables inside of your config
- What's next
- Feedback

This page shows how to define environment variables for a container in a Kubernetes Pod.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

When you create a Pod, you can set environment variables for the containers that run in the Pod. To set environment variables, include the env or envFrom field in the configuration file.

The env and envFrom fields have different effects.

You can read more about ConfigMap and Secret.

This page explains how to use env.

In this exercise, you create a Pod that runs one container. The configuration file for the Pod defines an environment variable with name DEMO_GREETING and value "Hello from the environment". Here is the configuration manifest for the Pod:

Create a Pod based on that manifest:

List the running Pods:

The output is similar to:

List the Pod's container environment variables:

The output is similar to this:

Environment variables that you define in a Pod's configuration under .spec.containers[*].env[*] can be used elsewhere in the configuration, for example in commands and arguments that you set for the Pod's containers. In the example configuration below, the GREETING, HONORIFIC, and NAME environment variables are set to Warm greetings to, The Most Honorable, and Kubernetes, respectively. The environment variable MESSAGE combines the set of all these environment variables and then uses it as a CLI argument passed to the env-print-demo container.

Environment variable names may consist of any printable ASCII characters except '='.

Upon creation, the command echo Warm greetings to The Most Honorable Kubernetes is run on the container.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: envar-demo
  labels:
    purpose: demonstrate-envars
spec:
  containers:
  - name: envar-demo-container
    image: gcr.io/google-samples/hello-app:2.0
    env:
    - name: DEMO_GREETING
      value: "Hello from the environment"
    - name: DEMO_FAREWELL
      value: "Such a sweet sorrow"
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/envars.yaml
```

Example 3 (shell):
```shell
kubectl get pods -l purpose=demonstrate-envars
```

Example 4 (unknown):
```unknown
NAME            READY     STATUS    RESTARTS   AGE
envar-demo      1/1       Running   0          9s
```

---

## Operating etcd clusters for Kubernetes

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/

**Contents:**
- Operating etcd clusters for Kubernetes
- Before you begin
  - Resource requirements for etcd
  - Tools
- Understanding etcdctl and etcdutl
- Starting etcd clusters
  - Single-node etcd cluster
  - Multi-node etcd cluster
  - Multi-node etcd cluster with load balancer
- Securing etcd clusters

etcd is a consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

etcd is a consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth information about etcd in the official documentation.

Before you follow steps in this page to deploy, manage, back up or restore etcd, you need to understand the typical expectations for operating an etcd cluster. Refer to the etcd documentation for more context.

The minimum recommended etcd versions to run in production are 3.4.22+ and 3.5.6+.

etcd is a leader-based distributed system. Ensure that the leader periodically send heartbeats on time to all followers to keep the cluster stable.

You should run etcd as a cluster with an odd number of members.

Aim to ensure that no resource starvation occurs.

Performance and stability of the cluster is sensitive to network and disk I/O. Any resource starvation can lead to heartbeat timeout, causing instability of the cluster. An unstable etcd indicates that no leader is elected. Under such circumstances, a cluster cannot make any changes to its current state, which implies no new pods can be scheduled.

Operating etcd with limited resources is suitable only for testing purposes. For deploying in production, advanced hardware configuration is required. Before deploying etcd in production, see resource requirement reference.

Keeping etcd clusters stable is critical to the stability of Kubernetes clusters. Therefore, run etcd clusters on dedicated machines or isolated environments for guaranteed resource requirements.

Depending on which specific outcome you're working on, you will need the etcdctl tool or the etcdutl tool (you may need both).

etcdctl and etcdutl are command-line tools used to interact with etcd clusters, but they serve different purposes:

etcdctl: This is the primary command-line client for interacting with etcd over a network. It is used for day-to-day operations such as managing keys and values, administering the cluster, checking health, and more.

etcdutl: This is an administration utility designed to operate directly on etcd data files, including migrating data between etcd versions, defragmenting the database, restoring snapshots, and validating data consistency. For network operations, etcdctl should be used.

For more information

*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
etcd --listen-client-urls=http://$PRIVATE_IP:2379 \
   --advertise-client-urls=http://$PRIVATE_IP:2379
```

Example 2 (shell):
```shell
etcd --listen-client-urls=http://$IP1:2379,http://$IP2:2379,http://$IP3:2379,http://$IP4:2379,http://$IP5:2379 --advertise-client-urls=http://$IP1:2379,http://$IP2:2379,http://$IP3:2379,http://$IP4:2379,http://$IP5:2379
```

Example 3 (unknown):
```unknown
ETCDCTL_API=3 etcdctl --endpoints 10.2.0.9:2379 \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member list
```

Example 4 (shell):
```shell
etcdctl --endpoints=http://10.0.0.2,http://10.0.0.3 member list
```

---

## Configure DNS for a Cluster

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/configure-dns-cluster/

**Contents:**
- Configure DNS for a Cluster
- Feedback

Kubernetes offers a DNS cluster addon, which most of the supported environments enable by default. In Kubernetes version 1.11 and later, CoreDNS is recommended and is installed by default with kubeadm.

For more information on how to configure CoreDNS for a Kubernetes cluster, see the Customizing DNS Service. An example demonstrating how to use Kubernetes DNS with kube-dns, see the Kubernetes DNS sample plugin.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Configure Liveness, Readiness and Startup Probes

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

**Contents:**
- Configure Liveness, Readiness and Startup Probes
    - Caution:
    - Note:
- Before you begin
- Define a liveness command
- Define a liveness HTTP request
- Define a TCP liveness probe
- Define a gRPC liveness probe
    - Note:
- Use a named port

This page shows how to configure liveness, readiness and startup probes for containers.

For more information about probes, see Liveness, Readiness and Startup Probes

The kubelet uses liveness probes to know when to restart a container. For example, liveness probes could catch a deadlock, where an application is running, but unable to make progress. Restarting a container in such a state can help to make the application more available despite bugs.

A common pattern for liveness probes is to use the same low-cost HTTP endpoint as for readiness probes, but with a higher failureThreshold. This ensures that the pod is observed as not-ready for some period of time before it is hard killed.

The kubelet uses readiness probes to know when a container is ready to start accepting traffic. One use of this signal is to control which Pods are used as backends for Services. A Pod is considered ready when its Ready condition is true. When a Pod is not ready, it is removed from Service load balancers. A Pod's Ready condition is false when its Node's Ready condition is not true, when one of the Pod's readinessGates is false, or when at least one of its containers is not ready.

The kubelet uses startup probes to know when a container application has started. If such a probe is configured, liveness and readiness probes do not start until it succeeds, making sure those probes don't interfere with the application startup. This can be used to adopt liveness checks on slow starting containers, avoiding them getting killed by the kubelet before they are up and running.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Many applications running for long periods of time eventually transition to broken states, and cannot recover except by being restarted. Kubernetes provides liveness probes to detect and remedy such situations.

In this exercise, you create a Pod that runs a container based on the registry.k8s.io/busybox:1.27.2 image. Here is the configuration file for the Pod:

In the configuration file, you can see that the Pod has a single Container. The periodSeconds field specifies that the kubelet should perform a liveness probe every 5 seconds. The init

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness
  name: liveness-exec
spec:
  containers:
  - name: liveness
    image: registry.k8s.io/busybox:1.27.2
    args:
    - /bin/sh
    - -c
    - touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
```

Example 2 (shell):
```shell
/bin/sh -c "touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/probe/exec-liveness.yaml
```

Example 4 (shell):
```shell
kubectl describe pod liveness-exec
```

---

## Upgrading kubeadm clusters

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/

**Contents:**
- Upgrading kubeadm clusters
- Before you begin
  - Additional information
  - Considerations when upgrading etcd
- Changing the package repository
- Determine which version to upgrade to
- Upgrading control plane nodes
  - Call "kubeadm upgrade"
    - Note:
    - Note:

This page explains how to upgrade a Kubernetes cluster created with kubeadm from version 1.33.x to version 1.34.x, and from version 1.34.x to 1.34.y (where y > x). Skipping MINOR versions when upgrading is unsupported. For more details, please visit Version Skew Policy.

To see information about upgrading clusters created using older versions of kubeadm, please refer to following pages instead:

The Kubernetes project recommends upgrading to the latest patch releases promptly, and to ensure that you are running a supported minor release of Kubernetes. Following this recommendation helps you to stay secure.

The upgrade workflow at high level is the following:

Because the kube-apiserver static pod is running at all times (even if you have drained the node), when you perform a kubeadm upgrade which includes an etcd upgrade, in-flight requests to the server will stall while the new etcd static pod is restarting. As a workaround, it is possible to actively stop the kube-apiserver process a few seconds before starting the kubeadm upgrade apply command. This permits to complete in-flight requests and close existing connections, and minimizes the consequence of the etcd downtime. This can be done as follows on control plane nodes:

If you're using the community-owned package repositories (pkgs.k8s.io), you need to enable the package repository for the desired Kubernetes minor release. This is explained in Changing the Kubernetes package repository document.

Find the latest patch release for Kubernetes 1.34 using the OS package manager:

# Find the latest 1.34 version in the list. # It should look like 1.34.x-*, where x is the latest patch. sudo apt update sudo apt-cache madison kubeadm

For systems with DNF:# Find the latest 1.34 version in the list. # It should look like 1.34.x-*, where x is the latest patch. sudo yum list --showduplicates kubeadm --disableexcludes=kubernetes For systems with DNF5:# Find the latest 1.34 version in the list. # It should look like 1.34.x-*, where x is the latest patch. sudo yum list --showduplicates kubeadm --setopt=disable_excludes=kubernetes

For systems with DNF:

For systems with DNF5:

If you don't see the version you expect to upgrade to, verify if the Kubernetes package repositories are used.

The upgrade procedure on control plane nodes should be executed one node at a time. Pick a control plane node that you wish to upgrade first. It must have the /etc/kubernetes/admin.conf file.

For the first control plane node

# rep

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
killall -s SIGTERM kube-apiserver # trigger a graceful kube-apiserver shutdown
sleep 20 # wait a little bit to permit completing in-flight requests
kubeadm upgrade ... # execute a kubeadm upgrade command
```

Example 2 (shell):
```shell
# Find the latest 1.34 version in the list.
# It should look like 1.34.x-*, where x is the latest patch.
sudo apt update
sudo apt-cache madison kubeadm
```

Example 3 (shell):
```shell
# Find the latest 1.34 version in the list.
# It should look like 1.34.x-*, where x is the latest patch.
sudo yum list --showduplicates kubeadm --disableexcludes=kubernetes
```

Example 4 (shell):
```shell
# Find the latest 1.34 version in the list.
# It should look like 1.34.x-*, where x is the latest patch.
sudo yum list --showduplicates kubeadm --setopt=disable_excludes=kubernetes
```

---

## Inject Data Into Applications

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/

**Contents:**
- Inject Data Into Applications
      - Define a Command and Arguments for a Container
      - Define Dependent Environment Variables
      - Define Environment Variables for a Container
      - Define Environment Variable Values Using An Init Container
      - Expose Pod Information to Containers Through Environment Variables
      - Expose Pod Information to Containers Through Files
      - Distribute Credentials Securely Using Secrets
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Run Jobs

**URL:** https://kubernetes.io/docs/tasks/job/

**Contents:**
- Run Jobs
      - Running Automated Tasks with a CronJob
      - Coarse Parallel Processing Using a Work Queue
      - Fine Parallel Processing Using a Work Queue
      - Indexed Job for Parallel Processing with Static Work Assignment
      - Job with Pod-to-Pod Communication
      - Parallel Processing using Expansions
      - Handling retriable and non-retriable pod failures with Pod failure policy
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Extend kubectl with plugins

**URL:** https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/#using-the-command-line-runtime-package

**Contents:**
- Extend kubectl with plugins
- Before you begin
- Installing kubectl plugins
    - Caution:
  - Discovering plugins
    - Create plugins
    - Limitations
- Writing kubectl plugins
  - Example plugin
  - Using a plugin

This guide demonstrates how to install and write extensions for kubectl. By thinking of core kubectl commands as essential building blocks for interacting with a Kubernetes cluster, a cluster administrator can think of plugins as a means of utilizing these building blocks to create more complex behavior. Plugins extend kubectl with new sub-commands, allowing for new and custom features not included in the main distribution of kubectl.

You need to have a working kubectl binary installed.

A plugin is a standalone executable file, whose name begins with kubectl-. To install a plugin, move its executable file to anywhere on your PATH.

You can also discover and install kubectl plugins available in the open source using Krew. Krew is a plugin manager maintained by the Kubernetes SIG CLI community.

kubectl provides a command kubectl plugin list that searches your PATH for valid plugin executables. Executing this command causes a traversal of all files in your PATH. Any files that are executable, and begin with kubectl- will show up in the order in which they are present in your PATH in this command's output. A warning will be included for any files beginning with kubectl- that are not executable. A warning will also be included for any valid plugin files that overlap each other's name.

You can use Krew to discover and install kubectl plugins from a community-curated plugin index.

kubectl allows plugins to add custom create commands of the shape kubectl create something by providing a kubectl-create-something binary in the PATH.

It is currently not possible to create plugins that overwrite existing kubectl commands or extend commands other than create. For example, creating a plugin kubectl-version will cause that plugin to never be executed, as the existing kubectl version command will always take precedence over it. Due to this limitation, it is also not possible to use plugins to add new subcommands to existing kubectl commands. For example, adding a subcommand kubectl attach vm by naming your plugin kubectl-attach-vm will cause that plugin to be ignored.

kubectl plugin list shows warnings for any valid plugins that attempt to do this.

You can write a plugin in any programming language or script that allows you to write command-line commands.

There is no plugin installation or pre-loading required. Plugin executables receive the inherited environment from the kubectl binary. A plugin determines which command path it wishes to implement based on its na

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
#!/bin/bash

# optional argument handling
if [[ "$1" == "version" ]]
then
    echo "1.0.0"
    exit 0
fi

# optional argument handling
if [[ "$1" == "config" ]]
then
    echo "$KUBECONFIG"
    exit 0
fi

echo "I am a plugin named kubectl-foo"
```

Example 2 (shell):
```shell
sudo chmod +x ./kubectl-foo
```

Example 3 (shell):
```shell
sudo mv ./kubectl-foo /usr/local/bin
```

Example 4 (shell):
```shell
kubectl foo
```

---

## Define Environment Variable Values Using An Init Container

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-via-file/

**Contents:**
- Define Environment Variable Values Using An Init Container
- Before you begin
- How the design works
    - Note:
- Env File Syntax
- What's next
- Feedback

This page show how to configure environment variables for containers in a Pod via file.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Your Kubernetes server must be version v1.34.

To check the version, enter kubectl version.

In this exercise, you will create a Pod that sources environment variables from files, projecting these values into the running container.

In this manifest, you can see the initContainer mounts an emptyDir volume and writes environment variables to a file within it, and the regular containers reference both the file and the environment variable key through the fileKeyRef field without needing to mount the volume. When optional field is set to false, the specified key in fileKeyRef must exist in the environment variables file.

The volume will only be mounted to the container that writes to the file (initContainer), while the consumer container that consumes the environment variable will not have the volume mounted.

The env file format adheres to the kubernetes env file standard.

During container initialization, the kubelet retrieves environment variables from specified files in the emptyDir volume and exposes them to the container.

All container types (initContainers, regular containers, sidecars containers, and ephemeral containers) support environment variable loading from files.

While these environment variables can store sensitive information, emptyDir volumes don't provide the same protection mechanisms as dedicated Secret objects. Therefore, exposing confidential environment variables to containers through this feature is not considered a security best practice.

Verify that the container in the Pod is running:

Check container logs for environment variables:

The output shows the values of selected environment variables:

The format of Kubernetes env files originates from .env files.

In a shell environment, .env files are typically loaded using the source .env command.

For Kubernetes, the defined env file format adheres to stricter syntax rules:

Blank Lines: Blank lines are ignored.

Leading Spaces: Leading spaces on all lines are ignored.

Variable Declaration: Variables must be declared as VAR=

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: envfile-test-pod
spec:
  initContainers:
    - name: setup-envfile
      image:  nginx
      command: ['sh', '-c', 'echo "DB_ADDRESS=address\nREST_ENDPOINT=endpoint" > /data/config.env']
      volumeMounts:
        - name: config
          mountPath: /data
  containers:
    - name: use-envfile
      image: nginx
      command: [ "/bin/sh", "-c", "env" ]
      env:
        - name: DB_ADDRESS
          valueFrom:
            fileKeyRef:
              path: config.env
              volumeName: config
              key: DB_ADDRESS
              optional: 
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/envars-file-container.yaml
```

Example 3 (shell):
```shell
# If the new Pod isn't yet healthy, rerun this command a few times.
kubectl get pods
```

Example 4 (shell):
```shell
kubectl logs dapi-test-pod -c use-envfile | grep DB_ADDRESS
```

---

## Define a Command and Arguments for a Container

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/

**Contents:**
- Define a Command and Arguments for a Container
- Before you begin
- Define a command and arguments when you create a Pod
    - Note:
- Use environment variables to define arguments
    - Note:
- Run a command in a shell
- What's next
- Feedback

This page shows how to define commands and arguments when you run a container in a Pod.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

When you create a Pod, you can define a command and arguments for the containers that run in the Pod. To define a command, include the command field in the configuration file. To define arguments for the command, include the args field in the configuration file. The command and arguments that you define cannot be changed after the Pod is created.

The command and arguments that you define in the configuration file override the default command and arguments provided by the container image. If you define args, but do not define a command, the default command is used with your new arguments.

In this exercise, you create a Pod that runs one container. The configuration file for the Pod defines a command and two arguments:

Create a Pod based on the YAML configuration file:

List the running Pods:

The output shows that the container that ran in the command-demo Pod has completed.

To see the output of the command that ran in the container, view the logs from the Pod:

The output shows the values of the HOSTNAME and KUBERNETES_PORT environment variables:

In the preceding example, you defined the arguments directly by providing strings. As an alternative to providing strings directly, you can define arguments by using environment variables:

This means you can define an argument for a Pod using any of the techniques available for defining environment variables, including ConfigMaps and Secrets.

In some cases, you need your command to run in a shell. For example, your command might consist of several 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: command-demo
  labels:
    purpose: demonstrate-command
spec:
  containers:
  - name: command-demo-container
    image: debian
    command: ["printenv"]
    args: ["HOSTNAME", "KUBERNETES_PORT"]
  restartPolicy: OnFailure
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/commands.yaml
```

Example 3 (shell):
```shell
kubectl get pods
```

Example 4 (shell):
```shell
kubectl logs command-demo
```

---

## Managing Kubernetes Objects Using Imperative Commands

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/

**Contents:**
- Managing Kubernetes Objects Using Imperative Commands
- Before you begin
- Trade-offs
- How to create objects
- How to update objects
    - Note:
- How to delete objects
    - Note:
- How to view an object
- Using set commands to modify objects before creation

Kubernetes objects can quickly be created, updated, and deleted directly using imperative commands built into the kubectl command-line tool. This document explains how those commands are organized and how to use them to manage live objects.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The kubectl tool supports three kinds of object management:

See Kubernetes Object Management for a discussion of the advantages and disadvantage of each kind of object management.

The kubectl tool supports verb-driven commands for creating some of the most common object types. The commands are named to be recognizable to users unfamiliar with the Kubernetes object types.

The kubectl tool also supports creation commands driven by object type. These commands support more object types and are more explicit about their intent, but require users to know the type of objects they intend to create.

Some objects types have subtypes that you can specify in the create command. For example, the Service object has several subtypes including ClusterIP, LoadBalancer, and NodePort. Here's an example that creates a Service with subtype NodePort:

In the preceding example, the create service nodeport command is called a subcommand of the create service command.

You can use the -h flag to find the arguments and flags supported by a subcommand:

The kubectl command supports verb-driven commands for some common update operations. These commands are named to enable users unfamiliar with Kubernetes objects to perform updates without knowing the specific fields that must be set:

The kubectl command also supports update commands driven by an aspect of the object. Se

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create service nodeport <myservicename>
```

Example 2 (shell):
```shell
kubectl create service nodeport -h
```

Example 3 (shell):
```shell
kubectl delete deployment/nginx
```

Example 4 (sh):
```sh
kubectl create service clusterip my-svc --clusterip="None" -o yaml --dry-run=client | kubectl set selector --local -f - 'environment=qa' -o yaml | kubectl create -f -
```

---

## Developing Cloud Controller Manager

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/developing-cloud-controller-manager/

**Contents:**
- Developing Cloud Controller Manager
- Background
- Developing
  - Out of tree
  - In tree
- Feedback

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

By decoupling the interoperability logic between Kubernetes and the underlying cloud infrastructure, the cloud-controller-manager component enables cloud providers to release features at a different pace compared to the main Kubernetes project.

Since cloud providers develop and release at a different pace compared to the Kubernetes project, abstracting the provider-specific code to the cloud-controller-manager binary allows cloud vendors to evolve independently from the core Kubernetes code.

The Kubernetes project provides skeleton cloud-controller-manager code with Go interfaces to allow you (or your cloud provider) to plug in your own implementations. This means that a cloud provider can implement a cloud-controller-manager by importing packages from Kubernetes core; each cloudprovider will register their own code by calling cloudprovider.RegisterCloudProvider to update a global variable of available cloud providers.

To build an out-of-tree cloud-controller-manager for your cloud:

Many cloud providers publish their controller manager code as open source. If you are creating a new cloud-controller-manager from scratch, you could take an existing out-of-tree cloud controller manager as your starting point.

For in-tree cloud providers, you can run the in-tree cloud controller manager as a DaemonSet in your cluster. See Cloud Controller Manager Administration for more details.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Manage Kubernetes Objects

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/

**Contents:**
- Manage Kubernetes Objects
      - Declarative Management of Kubernetes Objects Using Configuration Files
      - Declarative Management of Kubernetes Objects Using Kustomize
      - Managing Kubernetes Objects Using Imperative Commands
      - Imperative Management of Kubernetes Objects Using Configuration Files
      - Update API Objects in Place Using kubectl patch
      - Migrate Kubernetes Objects Using Storage Version Migration
- Feedback

Use kubectl patch to update Kubernetes API objects in place. Do a strategic merge patch or a JSON merge patch.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Use a User Namespace With a Pod

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/user-namespaces/

**Contents:**
- Use a User Namespace With a Pod
- Before you begin
    - Note:
- Run a Pod that uses a user namespace
- Feedback

This page shows how to configure a user namespace for pods. This allows you to isolate the user running inside the container from the one in the host.

A process running as root in a container can run as a different (non-root) user in the host; in other words, the process has full privileges for operations inside the user namespace, but is unprivileged for operations outside the namespace.

You can use this feature to reduce the damage a compromised container can do to the host or other pods in the same node. There are several security vulnerabilities rated either HIGH or CRITICAL that were not exploitable when user namespaces is active. It is expected user namespace will mitigate some future vulnerabilities too.

Without using a user namespace a container running as root, in the case of a container breakout, has root privileges on the node. And if some capability were granted to the container, the capabilities are valid on the host too. None of this is true when user namespaces are used.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.25.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The cluster that you're using must include at least one node that meets the requirements for using user namespaces with Pods.

If you have a mixture of nodes and only some of the nodes provide user namespace support for Pods, you also need to ensure that the user namespace Pods are scheduled to suitable nodes.

A user namespace for a pod is enabled setting the hostUsers field of .spec to false. For example:

Create the pod on your cluster:

Exec into the pod and run readlink /proc/self/ns/user:

The output is similar to:

The output is si

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: userns
spec:
  hostUsers: false
  containers:
  - name: shell
    command: ["sleep", "infinity"]
    image: debian
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/user-namespaces-stateless.yaml
```

Example 3 (shell):
```shell
kubectl exec -ti userns -- bash
```

Example 4 (shell):
```shell
readlink /proc/self/ns/user
```

---

## Configure the Aggregation Layer

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/

**Contents:**
- Configure the Aggregation Layer
- Before you begin
    - Note:
    - Caution:
- Authentication Flow
  - Kubernetes Apiserver Authentication and Authorization
  - Kubernetes Apiserver Proxies the Request
    - Kubernetes Apiserver Client Authentication
    - Note:
    - Original Request Username and Group

Configuring the aggregation layer allows the Kubernetes apiserver to be extended with additional APIs, which are not part of the core Kubernetes APIs.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Unlike Custom Resource Definitions (CRDs), the Aggregation API involves another server - your Extension apiserver - in addition to the standard Kubernetes apiserver. The Kubernetes apiserver will need to communicate with your extension apiserver, and your extension apiserver will need to communicate with the Kubernetes apiserver. In order for this communication to be secured, the Kubernetes apiserver uses x509 certificates to authenticate itself to the extension apiserver.

This section describes how the authentication and authorization flows work, and how to configure them.

The high-level flow is as follows:

The rest of this section describes these steps in detail.

The flow can be seen in the following diagram.

The source for the above swimlanes can be found in the source of this document.

A request to an API path that is served by an extension apiserver begins the same way as all API requests: communication to the Kubernetes apiserver. This path already has been registered with the Kubernetes apiserver by the extension apiserver.

The user communicates with the Kubernetes apiserver, requesting access to the path. The Kubernetes apiserver uses standard authentication and authorization configured with the Kubernetes apiserver to authenticate the user and authorize access to the specific path.

For an overview of authenticating to a Kubernetes cluster, see "Authenticating to a Cluster". For an overview of authorization of access to

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
--requestheader-client-ca-file=<path to aggregator CA cert>
--requestheader-allowed-names=front-proxy-client
--requestheader-extra-headers-prefix=X-Remote-Extra-
--requestheader-group-headers=X-Remote-Group
--requestheader-username-headers=X-Remote-User
--proxy-client-cert-file=<path to aggregator proxy cert>
--proxy-client-key-file=<path to aggregator proxy key>
```

Example 2 (unknown):
```unknown
--enable-aggregator-routing=true
```

Example 3 (yaml):
```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: <name of the registration object>
spec:
  group: <API group name this extension apiserver hosts>
  version: <API version this extension apiserver hosts>
  groupPriorityMinimum: <priority this APIService for this group, see API documentation>
  versionPriority: <prioritizes ordering of this version within a group, see API documentation>
  service:
    namespace: <namespace of the extension apiserver service>
    name: <name of the extension apiserver service>
  caBundle: <pem encoded ca cert that signs the server cert used
...
```

Example 4 (yaml):
```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
...
spec:
  ...
  service:
    namespace: my-service-namespace
    name: my-service-name
    port: 1234
  caBundle: "Ci0tLS0tQk...<base64-encoded PEM bundle>...tLS0K"
...
```

---

## Translate a Docker Compose File to Kubernetes Resources

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/

**Contents:**
- Translate a Docker Compose File to Kubernetes Resources
- Before you begin
- Install Kompose
- Use Kompose
- User Guide
- kompose convert
  - Kubernetes kompose convert example
  - OpenShift kompose convert example
    - Note:
- Alternative Conversions

What's Kompose? It's a conversion tool for all things compose (namely Docker Compose) to container orchestrators (Kubernetes or OpenShift).

More information can be found on the Kompose website at https://kompose.io/.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

We have multiple ways to install Kompose. Our preferred method is downloading the binary from the latest GitHub release.

Kompose is released via GitHub on a three-week cycle, you can see all current releases on the GitHub release page.# Linux curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-linux-amd64 -o kompose # macOS curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-darwin-amd64 -o kompose # Windows curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-windows-amd64.exe -o kompose.exe chmod +x kompose sudo mv ./kompose /usr/local/bin/kompose Alternatively, you can download the tarball.

Kompose is released via GitHub on a three-week cycle, you can see all current releases on the GitHub release page.

Alternatively, you can download the tarball.

Installing using go get pulls from the master branch with the latest development changes.go get -u github.com/kubernetes/kompose

Installing using go get pulls from the master branch with the latest development changes.

On macOS you can install the latest release via Homebrew:brew install kompose

On macOS you can install the latest release via Homebrew:

In a few steps, we'll take you from Docker Compose to Kubernetes. All you need is an existing docker-compose.yml file.

Go to the directory containing your docker-compose.yml file. If y

*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
# Linux
curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-linux-amd64 -o kompose

# macOS
curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-darwin-amd64 -o kompose

# Windows
curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-windows-amd64.exe -o kompose.exe

chmod +x kompose
sudo mv ./kompose /usr/local/bin/kompose
```

Example 2 (sh):
```sh
go get -u github.com/kubernetes/kompose
```

Example 3 (bash):
```bash
brew install kompose
```

Example 4 (yaml):
```yaml
services:

  redis-leader:
    container_name: redis-leader
    image: redis
    ports:
      - "6379"

  redis-replica:
    container_name: redis-replica
    image: redis
    ports:
      - "6379"
    command: redis-server --replicaof redis-leader 6379 --dir /tmp

  web:
    container_name: web
    image: quay.io/kompose/web
    ports:
      - "8080:8080"
    environment:
      - GET_HOSTS_FROM=dns
    labels:
      kompose.service.type: LoadBalancer
```

---

## Securing a Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/

**Contents:**
- Securing a Cluster
- Before you begin
- Controlling access to the Kubernetes API
  - Use Transport Layer Security (TLS) for all API traffic
  - API Authentication
  - API Authorization
- Controlling access to the Kubelet
- Controlling the capabilities of a workload or user at runtime
  - Limiting resource usage on a cluster
  - Controlling what privileges containers run with

This document covers topics related to protecting a cluster from accidental or malicious access and provides recommendations on overall security.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

As Kubernetes is entirely API-driven, controlling and limiting who can access the cluster and what actions they are allowed to perform is the first line of defense.

Kubernetes expects that all API communication in the cluster is encrypted by default with TLS, and the majority of installation methods will allow the necessary certificates to be created and distributed to the cluster components. Note that some components and installation methods may enable local ports over HTTP and administrators should familiarize themselves with the settings of each component to identify potentially unsecured traffic.

Choose an authentication mechanism for the API servers to use that matches the common access patterns when you install a cluster. For instance, small, single-user clusters may wish to use a simple certificate or static Bearer token approach. Larger clusters may wish to integrate an existing OIDC or LDAP server that allow users to be subdivided into groups.

All API clients must be authenticated, even those that are part of the infrastructure like nodes, proxies, the scheduler, and volume plugins. These clients are typically service accounts or use x509 client certificates, and they are created automatically at cluster startup or are setup as part of the cluster installation.

Consult the authentication reference document for more information.

Once authenticated, every API call is also expected to pass an authorization check. Kubernetes ships an integrated Role-Based Access Control (RBAC) component that matches an incoming user or group to a set of permissions bundled into roles. These permissions combine verbs (get, create, delete) with resources (pods, services, nodes) and can be namespace-scoped or cluster-scoped. A set of out-of-the-box roles are provided that offer reasonable default separation of responsibility depending on what actions a client might want to perform. It is recommended that you u

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
# DCCP is unlikely to be needed, has had multiple serious
# vulnerabilities, and is not well-maintained.
blacklist dccp

# SCTP is not used in most Kubernetes clusters, and has also had
# vulnerabilities in the past.
blacklist sctp
```

---

## Manage TLS Certificates in a Cluster

**URL:** https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/

**Contents:**
- Manage TLS Certificates in a Cluster
    - Note:
- Before you begin
- Trusting TLS in a cluster
    - Note:
- Requesting a certificate
    - Note:
- Create a certificate signing request
- Create a CertificateSigningRequest object to send to the Kubernetes API
- Get the CertificateSigningRequest approved

Kubernetes provides a certificates.k8s.io API, which lets you provision TLS certificates signed by a Certificate Authority (CA) that you control. These CA and certificates can be used by your workloads to establish trust.

certificates.k8s.io API uses a protocol that is similar to the ACME draft.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need the cfssl tool. You can download cfssl from https://github.com/cloudflare/cfssl/releases.

Some steps in this page use the jq tool. If you don't have jq, you can install it via your operating system's software sources, or fetch it from https://jqlang.github.io/jq/.

Trusting the custom CA from an application running as a pod usually requires some extra application configuration. You will need to add the CA certificate bundle to the list of CA certificates that the TLS client or server trusts. For example, you would do this with a golang TLS config by parsing the certificate chain and adding the parsed certificates to the RootCAs field in the tls.Config struct.

Even though the custom CA certificate may be included in the filesystem (in the ConfigMap kube-root-ca.crt), you should not use that certificate authority for any purpose other than to verify internal Kubernetes endpoints. An example of an internal Kubernetes endpoint is the Service named kubernetes in the default namespace.

If you want to use a custom certificate authority for your workloads, you should generate that CA separately, and distribute its CA certificate using a ConfigMap that your pods have access to read.

The following section demonstrates how to create a TLS certificate for a Kubernetes service accessed through DNS.

Generate a private key and certificate signing request (or CSR) by running the following command:

Where 192.0.2.24 is the service's cluster IP, my-svc.my-namespace.svc.cluster.local is the service's DNS name, 10.0.34.2 is the pod's IP and my-pod.my-namespace.pod.cluster.local is the pod's DNS name. You should see the output similar to:

This command generates two files; it generates server.csr containing the PEM encoded PKCS#10 certification request, and server-key.pem containing the PEM encoded key 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
cat <<EOF | cfssl genkey - | cfssljson -bare server
{
  "hosts": [
    "my-svc.my-namespace.svc.cluster.local",
    "my-pod.my-namespace.pod.cluster.local",
    "192.0.2.24",
    "10.0.34.2"
  ],
  "CN": "my-pod.my-namespace.pod.cluster.local",
  "key": {
    "algo": "ecdsa",
    "size": 256
  }
}
EOF
```

Example 2 (unknown):
```unknown
2022/02/01 11:45:32 [INFO] generate received request
2022/02/01 11:45:32 [INFO] received CSR
2022/02/01 11:45:32 [INFO] generating key: ecdsa-256
2022/02/01 11:45:32 [INFO] encoded CSR
```

Example 3 (shell):
```shell
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: my-svc.my-namespace
spec:
  request: $(cat server.csr | base64 | tr -d '\n')
  signerName: example.com/serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF
```

Example 4 (shell):
```shell
kubectl describe csr my-svc.my-namespace
```

---

## Install and Set Up kubectl on macOS

**URL:** https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/

**Contents:**
- Install and Set Up kubectl on macOS
- Before you begin
- Install kubectl on macOS
  - Install kubectl binary with curl on macOS
    - Note:
    - Note:
    - Note:
  - Install with Homebrew on macOS
  - Install with Macports on macOS
- Verify kubectl configuration

You must use a kubectl version that is within one minor version difference of your cluster. For example, a v1.34 client can communicate with v1.33, v1.34, and v1.35 control planes. Using the latest compatible version of kubectl helps avoid unforeseen issues.

The following methods exist for installing kubectl on macOS:

Download the latest release:

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"

To download a specific version, replace the $(curl -L -s https://dl.k8s.io/release/stable.txt) portion of the command with the specific version.

For example, to download version 1.34.0 on Intel macOS, type:

And for macOS on Apple Silicon, type:

Validate the binary (optional)

Download the kubectl checksum file:

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl.sha256"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl.sha256"

Validate the kubectl binary against the checksum file:

If valid, the output is:

If the check fails, shasum exits with nonzero status and prints output similar to:

Make the kubectl binary executable.

Move the kubectl binary to a file location on your system PATH.

Test to ensure the version you installed is up-to-date:

Or use this for detailed view of version:

After installing and validating kubectl, delete the checksum file:

If you are on macOS and using Homebrew package manager, you can install kubectl with Homebrew.

Run the installation command:

Test to ensure the version you installed is up-to-date:

If you are on macOS and using Macports package manager, you can install kubectl with Macports.

Run the installation command:

Test to ensure the version you installed is up-to-date:

In order for kubectl to find and access a Kubernetes cluster, it needs a kubeconfig file, which is created automatically when you create a cluster using kube-up.sh or successfully deploy a Minikube cluster. By default, kubectl configuration is located at ~/.kube/config.

Check that kubectl is properly configured by getting the cluster state:

If you see a URL response, kubectl is correctly configured to access your cluster.

If you see a message similar to the following, kubectl is not configured correctly or is not able to connect to a Kubernetes clu

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
```

Example 2 (bash):
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
```

Example 3 (bash):
```bash
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/darwin/amd64/kubectl"
```

Example 4 (bash):
```bash
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/darwin/arm64/kubectl"
```

---

## Validate IPv4/IPv6 dual-stack

**URL:** https://kubernetes.io/docs/tasks/network/validate-dual-stack/

**Contents:**
- Validate IPv4/IPv6 dual-stack
- Before you begin
    - Note:
- Validate addressing
  - Validate node addressing
  - Validate Pod addressing
- Validate Services
    - Note:
  - Create a dual-stack load balanced Service
- Feedback

This document shares how to validate IPv4/IPv6 dual-stack enabled Kubernetes clusters.

To check the version, enter kubectl version.

Each dual-stack Node should have a single IPv4 block and a single IPv6 block allocated. Validate that IPv4/IPv6 Pod address ranges are configured by running the following command. Replace the sample node name with a valid dual-stack Node from your cluster. In this example, the Node's name is k8s-linuxpool1-34450317-0:

There should be one IPv4 block and one IPv6 block allocated.

Validate that the node has an IPv4 and IPv6 interface detected. Replace node name with a valid node from the cluster. In this example the node name is k8s-linuxpool1-34450317-0:

Validate that a Pod has an IPv4 and IPv6 address assigned. Replace the Pod name with a valid Pod in your cluster. In this example the Pod name is pod01:

You can also validate Pod IPs using the Downward API via the status.podIPs fieldPath. The following snippet demonstrates how you can expose the Pod IPs via an environment variable called MY_POD_IPS within a container.

The following command prints the value of the MY_POD_IPS environment variable from within a container. The value is a comma separated list that corresponds to the Pod's IPv4 and IPv6 addresses.

The Pod's IP addresses will also be written to /etc/hosts within a container. The following command executes a cat on /etc/hosts on a dual stack Pod. From the output you can verify both the IPv4 and IPv6 IP address for the Pod.

Create the following Service that does not explicitly define .spec.ipFamilyPolicy. Kubernetes will assign a cluster IP for the Service from the first configured service-cluster-ip-range and set the .spec.ipFamilyPolicy to SingleStack.

Use kubectl to view the YAML for the Service.

The Service has .spec.ipFamilyPolicy set to SingleStack and .spec.clusterIP set to an IPv4 address from the first configured range set via --service-cluster-ip-range flag on kube-controller-manager.

Create the following Service that explicitly defines IPv6 as the first array element in .spec.ipFamilies. Kubernetes will assign a cluster IP for the Service from the IPv6 range configured service-cluster-ip-range and set the .spec.ipFamilyPolicy to SingleStack.

Use kubectl to view the YAML for the Service.

The Service has .spec.ipFamilyPolicy set to SingleStack and .spec.clusterIP set to an IPv6 address from the IPv6 range set via --service-cluster-ip-range flag on kube-controller-manager.

Create the following Serv

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes k8s-linuxpool1-34450317-0 -o go-template --template='{{range .spec.podCIDRs}}{{printf "%s\n" .}}{{end}}'
```

Example 2 (unknown):
```unknown
10.244.1.0/24
2001:db8::/64
```

Example 3 (shell):
```shell
kubectl get nodes k8s-linuxpool1-34450317-0 -o go-template --template='{{range .status.addresses}}{{printf "%s: %s\n" .type .address}}{{end}}'
```

Example 4 (unknown):
```unknown
Hostname: k8s-linuxpool1-34450317-0
InternalIP: 10.0.0.5
InternalIP: 2001:db8:10::5
```

---

## Assign Pod-level CPU and memory resources

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-pod-level-resources/

**Contents:**
- Assign Pod-level CPU and memory resources
- Before you begin
- Limitations
- Create a namespace
- Create a pod with memory requests and limits at pod-level
- Create a pod with CPU requests and limits at pod-level
- Create a pod with resource requests and limits at both pod-level and container-level
- Clean up
- What's next
  - For application developers

This page shows how to specify CPU and memory resources for a Pod at pod-level in addition to container-level resource specifications. A Kubernetes node allocates resources to a pod based on the pod's resource requests. These requests can be defined at the pod level or individually for containers within the pod. When both are present, the pod-level requests take precedence.

Similarly, a pod's resource usage is restricted by limits, which can also be set at the pod-level or individually for containers within the pod. Again, pod-level limits are prioritized when both are present. This allows for flexible resource management, enabling you to control resource allocation at both the pod and container levels.

In order to specify the resources at pod-level, it is required to enable PodLevelResources feature gate.

For Pod Level Resources:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.34.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The PodLevelResources feature gate must be enabled for your control plane and for all nodes in your cluster.

For Kubernetes 1.34, resizing pod-level resources has the following limitations:

Create a namespace so that the resources you create in this exercise are isolated from the rest of your cluster.

To specify memory requests for a Pod at pod-level, include the resources.requests.memory field in the Pod spec manifest. To specify a memory limit, include resources.limits.memory.

In this exercise, you create a Pod that has one Container. The Pod has a memory request of 100 MiB and a memory limit of 200 MiB. Here's the configuration file for the Pod:

The args section in the manifest provides

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create namespace pod-resources-example
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-demo
  namespace: pod-resources-example
spec:
  resources:
    requests:
      memory: "100Mi"
    limits:
      memory: "200Mi"
  containers:
  - name: memory-demo-ctr
    image: nginx
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/resource/pod-level-memory-request-limit.yaml --namespace=pod-resources-example
```

Example 4 (shell):
```shell
kubectl get pod memory-demo --namespace=pod-resources-example
```

---

## Switching from Polling to CRI Event-based Updates to Container Status

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/switch-to-evented-pleg/

**Contents:**
- Switching from Polling to CRI Event-based Updates to Container Status
- Before you begin
- Why switch to Evented PLEG?
- Switching to Evented PLEG
- What's next
- Feedback

This page shows how to migrate nodes to use event based updates for container status. The event-based implementation reduces node resource consumption by the kubelet, compared to the legacy approach that relies on polling. You may know this feature as evented Pod lifecycle event generator (PLEG). That's the name used internally within the Kubernetes project for a key implementation detail.

The polling based approach is referred to as generic PLEG.

To check the version, enter kubectl version.

Start the Kubelet with the feature gate EventedPLEG enabled. You can manage the kubelet feature gates editing the kubelet config file and restarting the kubelet service. You need to do this on each node where you are using this feature.

Make sure the node is drained before proceeding.

Start the container runtime with the container event generation enabled.

Version 1.26+Check if the CRI-O is already configured to emit CRI events by verifying the configuration,crio config | grep enable_pod_events If it is enabled, the output should be similar to the following:enable_pod_events = true To enable it, start the CRI-O daemon with the flag --enable-pod-events=true or use a dropin config with the following lines:[crio.runtime] enable_pod_events: true

Check if the CRI-O is already configured to emit CRI events by verifying the configuration,

If it is enabled, the output should be similar to the following:

To enable it, start the CRI-O daemon with the flag --enable-pod-events=true or use a dropin config with the following lines:

To check the version, enter kubectl version.

Verify that the kubelet is using event-based container stage change monitoring. To check, look for the term EventedPLEG in the kubelet logs.

The output should be similar to this:

If you have set --v to 4 and above, you might see more entries that indicate that the kubelet is using event-based container state monitoring.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
crio config | grep enable_pod_events
```

Example 2 (none):
```none
enable_pod_events = true
```

Example 3 (toml):
```toml
[crio.runtime]
enable_pod_events: true
```

Example 4 (console):
```console
I0314 11:10:13.909915 1105457 feature_gate.go:249] feature gates: &{map[EventedPLEG:true]}
```

---

## Communicate Between Containers in the Same Pod Using a Shared Volume

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/

**Contents:**
- Communicate Between Containers in the Same Pod Using a Shared Volume
- Before you begin
- Creating a Pod that runs two Containers
- Discussion
- What's next
- Feedback

This page shows how to use a Volume to communicate between two Containers running in the same Pod. See also how to allow processes to communicate by sharing process namespace between containers.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise, you create a Pod that runs two Containers. The two containers share a Volume that they can use to communicate. Here is the configuration file for the Pod:

In the configuration file, you can see that the Pod has a Volume named shared-data.

The first container listed in the configuration file runs an nginx server. The mount path for the shared Volume is /usr/share/nginx/html. The second container is based on the debian image, and has a mount path of /pod-data. The second container runs the following command and then terminates.

Notice that the second container writes the index.html file in the root directory of the nginx server.

Create the Pod and the two Containers:

View information about the Pod and the Containers:

Here is a portion of the output:

You can see that the debian Container has terminated, and the nginx Container is still running.

Get a shell to nginx Container:

In your shell, verify that nginx is running:

The output is similar to this:

Recall that the debian Container created the index.html file in the nginx root directory. Use curl to send a GET request to the nginx server:

The output shows that nginx serves a web page written by the debian container:

The primary reason that Pods can have multiple containers is to support helper applications that assist a primary application. Typical examples of helper applications are data pullers, data pushers, an

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: two-containers
spec:

  restartPolicy: Never

  volumes:
  - name: shared-data
    emptyDir: {}

  containers:

  - name: nginx-container
    image: nginx
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html

  - name: debian-container
    image: debian
    volumeMounts:
    - name: shared-data
      mountPath: /pod-data
    command: ["/bin/sh"]
    args: ["-c", "echo Hello from the debian container > /pod-data/index.html"]
```

Example 2 (unknown):
```unknown
echo Hello from the debian container > /pod-data/index.html
```

Example 3 (unknown):
```unknown
kubectl apply -f https://k8s.io/examples/pods/two-container-pod.yaml
```

Example 4 (unknown):
```unknown
kubectl get pod two-containers --output=yaml
```

---

## List All Container Images Running in a Cluster

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/list-all-running-container-images/

**Contents:**
- List All Container Images Running in a Cluster
- Before you begin
- List all Container images in all namespaces
    - Note:
- List Container images by Pod
- List Container images filtering by Pod label
- List Container images filtering by Pod namespace
- List Container images using a go-template instead of jsonpath
- What's next
  - Reference

This page shows how to use kubectl to list all of the Container images for Pods running in a cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise you will use kubectl to fetch all of the Pods running in a cluster, and format the output to pull out the list of Containers for each.

The jsonpath is interpreted as follows:

The formatting can be controlled further by using the range operation to iterate over elements individually.

To target only Pods matching a specific label, use the -l flag. The following matches only Pods with labels matching app=nginx.

To target only pods in a specific namespace, use the namespace flag. The following matches only Pods in the kube-system namespace.

As an alternative to jsonpath, Kubectl supports using go-templates for formatting the output:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec['initContainers', 'containers'][*].image}" |\
tr -s '[[:space:]]' '\n' |\
sort |\
uniq -c
```

Example 2 (shell):
```shell
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' |\
sort
```

Example 3 (shell):
```shell
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" -l app=nginx
```

Example 4 (shell):
```shell
kubectl get pods --namespace kube-system -o jsonpath="{.items[*].spec.containers[*].image}"
```

---

## Pull an Image from a Private Registry

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/

**Contents:**
- Pull an Image from a Private Registry
- Before you begin
- Log in to Docker Hub
    - Note:
- Create a Secret based on existing credentials
- Create a Secret by providing credentials on the command line
    - Note:
- Inspecting the Secret regcred
- Create a Pod that uses your Secret
    - Note:

This page shows how to create a Pod that uses a Secret to pull an image from a private container image registry or repository. There are many private registries in use. This task uses Docker Hub as an example registry.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To do this exercise, you need the docker command line tool, and a Docker ID for which you know the password.

If you are using a different private container registry, you need the command line tool for that registry and any login information for the registry.

On your laptop, you must authenticate with a registry in order to pull a private image.

Use the docker tool to log in to Docker Hub. See the log in section of Docker ID accounts for more information.

When prompted, enter your Docker ID, and then the credential you want to use (access token, or the password for your Docker ID).

The login process creates or updates a config.json file that holds an authorization token. Review how Kubernetes interprets this file.

View the config.json file:

The output contains a section similar to this:

A Kubernetes cluster uses the Secret of kubernetes.io/dockerconfigjson type to authenticate with a container registry to pull a private image.

If you already ran docker login, you can copy that credential into Kubernetes:

If you need more control (for example, to set a namespace or a label on the new secret) then you can customise the Secret before storing it. Be sure to:

If you get the error message error: no objects passed to create, it may mean the base64 encoded string is invalid. If you get an error message like Secret "myregistrykey" is invalid: data[.dockerconfigjson]: invalid value ..., it means the base64 encoded string in the data was successfully decoded, but could not be parsed as a .docker/config.json file.

Create this Secret, naming it regcred:

You have successfully set your Docker credentials in the cluster as a Secret called regcred.

To understand the contents of the regcred Secret you created, start by viewing the Secret in YAML format:

The output is similar to this:

The value of the .dockerconfigjson field is a base64 representation of your Docker credentials

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
docker login
```

Example 2 (shell):
```shell
cat ~/.docker/config.json
```

Example 3 (json):
```json
{
    "auths": {
        "https://index.docker.io/v1/": {
            "auth": "c3R...zE2"
        }
    }
}
```

Example 4 (shell):
```shell
kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=<path/to/.docker/config.json> \
    --type=kubernetes.io/dockerconfigjson
```

---

## Reserve Compute Resources for System Daemons

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/

**Contents:**
- Reserve Compute Resources for System Daemons
- Before you begin
- Node Allocatable
  - Enabling QoS and Pod level cgroups
  - Configuring a cgroup driver
  - Kube Reserved
  - System Reserved
  - Explicitly Reserved CPU List
  - Eviction Thresholds
  - Enforcing Node Allocatable

Kubernetes nodes can be scheduled to Capacity. Pods can consume all the available capacity on a node by default. This is an issue because nodes typically run quite a few system daemons that power the OS and Kubernetes itself. Unless resources are set aside for these system daemons, pods and system daemons compete for resources and lead to resource starvation issues on the node.

The kubelet exposes a feature named 'Node Allocatable' that helps to reserve compute resources for system daemons. Kubernetes recommends cluster administrators to configure 'Node Allocatable' based on their workload density on each node.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You can configure below kubelet configuration settings using the kubelet configuration file.

'Allocatable' on a Kubernetes node is defined as the amount of compute resources that are available for pods. The scheduler does not over-subscribe 'Allocatable'. 'CPU', 'memory' and 'ephemeral-storage' are supported as of now.

Node Allocatable is exposed as part of v1.Node object in the API and as part of kubectl describe node in the CLI.

Resources can be reserved for two categories of system daemons in the kubelet.

To properly enforce node allocatable constraints on the node, you must enable the new cgroup hierarchy via the cgroupsPerQOS setting. This setting is enabled by default. When enabled, the kubelet will parent all end-user pods under a cgroup hierarchy managed by the kubelet.

The kubelet supports manipulation of the cgroup hierarchy on the host using a cgroup driver. The driver is configured via the cgroupDriver setting.

The supported values are the following:

Depending on the configuration of the associated container runtime, operators may have to choose a particular cgroup driver to ensure proper system behavior. For example, if operators use the systemd cgroup driver provided by the containerd runtime, the kubelet must be configured to use the systemd cgroup driver.

kubeReserved is meant to capture resource reservation for kubernetes system daemons like the kubelet, container runtime, etc. It is not meant to reserve resources for system daemons that are run as pods. k

*[Content truncated]*

---

## Extend kubectl with plugins

**URL:** https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/

**Contents:**
- Extend kubectl with plugins
- Before you begin
- Installing kubectl plugins
    - Caution:
  - Discovering plugins
    - Create plugins
    - Limitations
- Writing kubectl plugins
  - Example plugin
  - Using a plugin

This guide demonstrates how to install and write extensions for kubectl. By thinking of core kubectl commands as essential building blocks for interacting with a Kubernetes cluster, a cluster administrator can think of plugins as a means of utilizing these building blocks to create more complex behavior. Plugins extend kubectl with new sub-commands, allowing for new and custom features not included in the main distribution of kubectl.

You need to have a working kubectl binary installed.

A plugin is a standalone executable file, whose name begins with kubectl-. To install a plugin, move its executable file to anywhere on your PATH.

You can also discover and install kubectl plugins available in the open source using Krew. Krew is a plugin manager maintained by the Kubernetes SIG CLI community.

kubectl provides a command kubectl plugin list that searches your PATH for valid plugin executables. Executing this command causes a traversal of all files in your PATH. Any files that are executable, and begin with kubectl- will show up in the order in which they are present in your PATH in this command's output. A warning will be included for any files beginning with kubectl- that are not executable. A warning will also be included for any valid plugin files that overlap each other's name.

You can use Krew to discover and install kubectl plugins from a community-curated plugin index.

kubectl allows plugins to add custom create commands of the shape kubectl create something by providing a kubectl-create-something binary in the PATH.

It is currently not possible to create plugins that overwrite existing kubectl commands or extend commands other than create. For example, creating a plugin kubectl-version will cause that plugin to never be executed, as the existing kubectl version command will always take precedence over it. Due to this limitation, it is also not possible to use plugins to add new subcommands to existing kubectl commands. For example, adding a subcommand kubectl attach vm by naming your plugin kubectl-attach-vm will cause that plugin to be ignored.

kubectl plugin list shows warnings for any valid plugins that attempt to do this.

You can write a plugin in any programming language or script that allows you to write command-line commands.

There is no plugin installation or pre-loading required. Plugin executables receive the inherited environment from the kubectl binary. A plugin determines which command path it wishes to implement based on its na

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
#!/bin/bash

# optional argument handling
if [[ "$1" == "version" ]]
then
    echo "1.0.0"
    exit 0
fi

# optional argument handling
if [[ "$1" == "config" ]]
then
    echo "$KUBECONFIG"
    exit 0
fi

echo "I am a plugin named kubectl-foo"
```

Example 2 (shell):
```shell
sudo chmod +x ./kubectl-foo
```

Example 3 (shell):
```shell
sudo mv ./kubectl-foo /usr/local/bin
```

Example 4 (shell):
```shell
kubectl foo
```

---

## Fine Parallel Processing Using a Work Queue

**URL:** https://kubernetes.io/docs/tasks/job/fine-parallel-processing-work-queue/

**Contents:**
- Fine Parallel Processing Using a Work Queue
- Before you begin
- Starting Redis
- Filling the queue with tasks
- Create a container image
  - Push the image
- Defining a Job
    - Note:
- Running the Job
- Alternatives

In this example, you will run a Kubernetes Job that runs multiple parallel tasks as worker processes, each running as a separate Pod.

In this example, as each pod is created, it picks up one unit of work from a task queue, processes it, and repeats until the end of the queue is reached.

Here is an overview of the steps in this example:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You will need a container image registry where you can upload images to run in your cluster. The example uses Docker Hub, but you could adapt it to a different container image registry.

This task example also assumes that you have Docker installed locally. You use Docker to build container images.

Be familiar with the basic, non-parallel, use of Job.

For this example, for simplicity, you will start a single instance of Redis. See the Redis Example for an example of deploying Redis scalably and redundantly.

You could also download the following files directly:

To start a single instance of Redis, you need to create the redis pod and redis service:

Now let's fill the queue with some "tasks". In this example, the tasks are strings to be printed.

Start a temporary interactive pod for running the Redis CLI.

Now hit enter, start the Redis CLI, and create a list with some work items in it.

So, the list with key job2 will be the work queue.

Note: if you do not have Kube DNS setup correctly, you may need to change the first step of the above block to redis-cli -h $REDIS_SERVICE_HOST.

Now you are ready to create an image that will process the work in that queue.

You're going to use a Python worker program with a Redis client to read the messages from the message queue.

A simple Redis work queue client library is provided, called rediswq.py (Download).

The "worker" program in each Pod of the Job uses the work queue client library to get work. Here it is:

You could also download worker.py, rediswq.py, and Dockerfile files, then build the container image. Here's an example using Docker to do the image build:

For the Docker Hub, tag your app image with your username and push to the Hub with the below commands. Replace <username> with your Hub username.


*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/job/redis/redis-pod.yaml
kubectl apply -f https://k8s.io/examples/application/job/redis/redis-service.yaml
```

Example 2 (shell):
```shell
kubectl run -i --tty temp --image redis --command "/bin/sh"
```

Example 3 (unknown):
```unknown
Waiting for pod default/redis2-c7h78 to be running, status is Pending, pod ready: false
Hit enter for command prompt
```

Example 4 (shell):
```shell
redis-cli -h redis
```

---

## Parallel Processing using Expansions

**URL:** https://kubernetes.io/docs/tasks/job/parallel-processing-expansion/

**Contents:**
- Parallel Processing using Expansions
- Before you begin
- Create Jobs based on a template
  - Create manifests from the template
  - Create Jobs from the manifests
  - Clean up
- Use advanced template parameters
  - Clean up
- Using Jobs in real workloads
- Labels on Jobs and Pods

This task demonstrates running multiple Jobs based on a common template. You can use this approach to process batches of work in parallel.

For this example there are only three items: apple, banana, and cherry. The sample Jobs process each item by printing a string then pausing.

See using Jobs in real workloads to learn about how this pattern fits more realistic use cases.

You should be familiar with the basic, non-parallel, use of Job.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

For basic templating you need the command-line utility sed.

To follow the advanced templating example, you need a working installation of Python, and the Jinja2 template library for Python.

Once you have Python set up, you can install Jinja2 by running:

First, download the following template of a Job to a file called job-tmpl.yaml. Here's what you'll download:

The file you downloaded is not yet a valid Kubernetes manifest. Instead that template is a YAML representation of a Job object with some placeholders that need to be filled in before it can be used. The $ITEM syntax is not meaningful to Kubernetes.

The following shell snippet uses sed to replace the string $ITEM with the loop variable, writing into a temporary directory named jobs. Run this now:

The output is similar to this:

You could use any type of template language (for example: Jinja2; ERB), or write a program to generate the Job manifests.

Next, create all the Jobs with one kubectl command:

The output is similar to this:

Now, check on the jobs:

The output is similar to this:

Using the -l option to kubectl selects only the Jobs that are part of this group of jobs (there might be other unrelated jobs in the system).

You can check on the Pods as well using the same label selector:

The output is similar to:

We can use this single command to check on the output of all jobs at once:

The output should be:

In the first example, each instance of the template had one parameter, and that parameter was also used in the Job's name. However, names are restricted to contain only certain characters.

This slightly more complex example uses the Jinja template language to generate manifests a

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
pip install --user jinja2
```

Example 2 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: process-item-$ITEM
  labels:
    jobgroup: jobexample
spec:
  template:
    metadata:
      name: jobexample
      labels:
        jobgroup: jobexample
    spec:
      containers:
      - name: c
        image: busybox:1.28
        command: ["sh", "-c", "echo Processing item $ITEM && sleep 5"]
      restartPolicy: Never
```

Example 3 (shell):
```shell
# Use curl to download job-tmpl.yaml
curl -L -s -O https://k8s.io/examples/application/job/job-tmpl.yaml
```

Example 4 (shell):
```shell
# Expand the template into multiple files, one for each item to be processed.
mkdir ./jobs
for i in apple banana cherry
do
  cat job-tmpl.yaml | sed "s/\$ITEM/$i/" > ./jobs/job-$i.yaml
done
```

---

## Utilizing the NUMA-aware Memory Manager

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/memory-manager/

**Contents:**
- Utilizing the NUMA-aware Memory Manager
- Before you begin
- How does the Memory Manager Operate?
  - Startup
  - Runtime
  - Windows Support
- Memory Manager configuration
  - Policies
    - None policy
    - Static policy

The Kubernetes Memory Manager enables the feature of guaranteed memory (and hugepages) allocation for pods in the Guaranteed QoS class.

The Memory Manager employs hint generation protocol to yield the most suitable NUMA affinity for a pod. The Memory Manager feeds the central manager (Topology Manager) with these affinity hints. Based on both the hints and Topology Manager policy, the pod is rejected or admitted to the node.

Moreover, the Memory Manager ensures that the memory which a pod requests is allocated from a minimum number of NUMA nodes.

The Memory Manager is only pertinent to Linux based hosts.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.32.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To align memory resources with other requested resources in a Pod spec:

Starting from v1.22, the Memory Manager is enabled by default through MemoryManager feature gate.

Preceding v1.22, the kubelet must be started with the following flag:

--feature-gates=MemoryManager=true

in order to enable the Memory Manager feature.

The Memory Manager currently offers the guaranteed memory (and hugepages) allocation for Pods in Guaranteed QoS class. To immediately put the Memory Manager into operation follow the guidelines in the section Memory Manager configuration, and subsequently, prepare and deploy a Guaranteed pod as illustrated in the section Placing a Pod in the Guaranteed QoS class.

The Memory Manager is a Hint Provider, and it provides topology hints for the Topology Manager which then aligns the requested resources according to these topology hints. On Linux, it also enforces cgroups (i.e. cpuset.mems) for pods. The

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
--kube-reserved=cpu=4,memory=4Gi
--system-reserved=cpu=1,memory=1Gi
--memory-manager-policy=Static
--reserved-memory '0:memory=3Gi;1:memory=2148Mi'
```

Example 2 (shell):
```shell
--feature-gates=MemoryManager=true
```

Example 3 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      limits:
        memory: "200Mi"
        cpu: "2"
        example.com/device: "1"
      requests:
        memory: "200Mi"
        cpu: "2"
        example.com/device: "1"
```

Example 4 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      limits:
        memory: "200Mi"
        cpu: "300m"
        example.com/device: "1"
      requests:
        memory: "200Mi"
        cpu: "300m"
        example.com/device: "1"
```

---

## Running Automated Tasks with a CronJob

**URL:** https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/

**Contents:**
- Running Automated Tasks with a CronJob
- Before you begin
- Creating a CronJob
    - Note:
- Deleting a CronJob
- Feedback

This page shows how to run automated tasks using Kubernetes CronJob object.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Cron jobs require a config file. Here is a manifest for a CronJob that runs a simple demonstration task every minute:

Run the example CronJob by using this command:

The output is similar to this:

After creating the cron job, get its status using this command:

The output is similar to this:

As you can see from the results of the command, the cron job has not scheduled or run any jobs yet. Watch for the job to be created in around one minute:

The output is similar to this:

Now you've seen one running job scheduled by the "hello" cron job. You can stop watching the job and view the cron job again to see that it scheduled the job:

The output is similar to this:

You should see that the cron job hello successfully scheduled a job at the time specified in LAST SCHEDULE. There are currently 0 active jobs, meaning that the job has completed or failed.

Now, find the pods that the last scheduled job created and view the standard output of one of the pods.

The output is similar to this:

When you don't need a cron job any more, delete it with kubectl delete cronjob <cronjob name>:

Deleting the cron job removes all the jobs and pods it created and stops it from creating additional jobs. You can read more about removing jobs in garbage collection.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
spec:
  schedule: "* * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: hello
            image: busybox:1.28
            imagePullPolicy: IfNotPresent
            command:
            - /bin/sh
            - -c
            - date; echo Hello from the Kubernetes cluster
          restartPolicy: OnFailure
```

Example 2 (shell):
```shell
kubectl create -f https://k8s.io/examples/application/job/cronjob.yaml
```

Example 3 (unknown):
```unknown
cronjob.batch/hello created
```

Example 4 (shell):
```shell
kubectl get cronjob hello
```

---

## Configure Certificate Rotation for the Kubelet

**URL:** https://kubernetes.io/docs/tasks/tls/certificate-rotation/

**Contents:**
- Configure Certificate Rotation for the Kubelet
- Before you begin
- Overview
- Enabling client certificate rotation
- Understanding the certificate rotation configuration
- Feedback

This page shows how to enable and configure certificate rotation for the kubelet.

The kubelet uses certificates for authenticating to the Kubernetes API. By default, these certificates are issued with one year expiration so that they do not need to be renewed too frequently.

Kubernetes contains kubelet certificate rotation, that will automatically generate a new key and request a new certificate from the Kubernetes API as the current certificate approaches expiration. Once the new certificate is available, it will be used for authenticating connections to the Kubernetes API.

The kubelet process accepts an argument --rotate-certificates that controls if the kubelet will automatically request a new certificate as the expiration of the certificate currently in use approaches.

The kube-controller-manager process accepts an argument --cluster-signing-duration (--experimental-cluster-signing-duration prior to 1.19) that controls how long certificates will be issued for.

When a kubelet starts up, if it is configured to bootstrap (using the --bootstrap-kubeconfig flag), it will use its initial certificate to connect to the Kubernetes API and issue a certificate signing request. You can view the status of certificate signing requests using:

Initially a certificate signing request from the kubelet on a node will have a status of Pending. If the certificate signing requests meets specific criteria, it will be auto approved by the controller manager, then it will have a status of Approved. Next, the controller manager will sign a certificate, issued for the duration specified by the --cluster-signing-duration parameter, and the signed certificate will be attached to the certificate signing request.

The kubelet will retrieve the signed certificate from the Kubernetes API and write that to disk, in the location specified by --cert-dir. Then the kubelet will use the new certificate to connect to the Kubernetes API.

As the expiration of the signed certificate approaches, the kubelet will automatically issue a new certificate signing request, using the Kubernetes API. This can happen at any point between 30% and 10% of the time remaining on the certificate. Again, the controller manager will automatically approve the certificate request and attach a signed certificate to the certificate signing request. The kubelet will retrieve the new signed certificate from the Kubernetes API and write that to disk. Then it will update the connections it has to the Kubernetes AP

*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
kubectl get csr
```

---

## Install a Network Policy Provider

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/

**Contents:**
- Install a Network Policy Provider
      - Use Antrea for NetworkPolicy
      - Use Calico for NetworkPolicy
      - Use Cilium for NetworkPolicy
      - Use Kube-router for NetworkPolicy
      - Romana for NetworkPolicy
      - Weave Net for NetworkPolicy
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Administer a Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/

**Contents:**
- Administer a Cluster
      - Administration with kubeadm
      - Overprovision Node Capacity For A Cluster
      - Migrating from dockershim
      - Generate Certificates Manually
      - Manage Memory, CPU, and API Resources
      - Install a Network Policy Provider
      - Access Clusters Using the Kubernetes API
      - Advertise Extended Resources for a Node
      - Autoscale the DNS Service in a Cluster

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Handling retriable and non-retriable pod failures with Pod failure policy

**URL:** https://kubernetes.io/docs/tasks/job/pod-failure-policy/

**Contents:**
- Handling retriable and non-retriable pod failures with Pod failure policy
- Before you begin
- Usage scenarios
  - Using Pod failure policy to avoid unnecessary Pod retries
    - Clean up
  - Using Pod failure policy to ignore Pod disruptions
    - Caution:
    - Cleaning up
  - Using Pod failure policy to avoid unnecessary Pod retries based on custom Pod Conditions
    - Note:

This document shows you how to use the Pod failure policy, in combination with the default Pod backoff failure policy, to improve the control over the handling of container- or Pod-level failure within a Job.

The definition of Pod failure policy may help you to:

You should already be familiar with the basic use of Job.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.25.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Consider the following usage scenarios for Jobs that define a Pod failure policy :

With the following example, you can learn how to use Pod failure policy to avoid unnecessary Pod restarts when a Pod failure indicates a non-retriable software bug.

Examine the following manifest:

After around 30 seconds the entire Job should be terminated. Inspect the status of the Job by running:

In the Job status, the following conditions display:

For comparison, if the Pod failure policy was disabled it would take 6 retries of the Pod, taking at least 2 minutes.

Delete the Job you created:

The cluster automatically cleans up the Pods.

With the following example, you can learn how to use Pod failure policy to ignore Pod disruptions from incrementing the Pod retry counter towards the .spec.backoffLimit limit.

Examine the following manifest:

Run this command to check the nodeName the Pod is scheduled to:

Drain the node to evict the Pod before it completes (within 90s):

Inspect the .status.failed to check the counter for the Job is not incremented:

The Job resumes and succeeds.

For comparison, if the Pod failure policy was disabled the Pod disruption would result in terminating the entire Job (as the .spec.back

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-pod-failure-policy-failjob
spec:
  completions: 8
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: main
        image: docker.io/library/bash:5
        command: ["bash"]
        args:
        - -c
        - echo "Hello world! I'm going to exit with 42 to simulate a software bug." && sleep 30 && exit 42
  backoffLimit: 6
  podFailurePolicy:
    rules:
    - action: FailJob
      onExitCodes:
        containerName: main
        operator: In
        values: [42]
```

Example 2 (sh):
```sh
kubectl create -f https://k8s.io/examples/controllers/job-pod-failure-policy-failjob.yaml
```

Example 3 (sh):
```sh
kubectl get jobs -l job-name=job-pod-failure-policy-failjob -o yaml
```

Example 4 (sh):
```sh
kubectl delete jobs/job-pod-failure-policy-failjob
```

---

## Access Applications in a Cluster

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/

**Contents:**
- Access Applications in a Cluster
      - Deploy and Access the Kubernetes Dashboard
      - Accessing Clusters
      - Configure Access to Multiple Clusters
      - Use Port Forwarding to Access Applications in a Cluster
      - Use a Service to Access an Application in a Cluster
      - Connect a Frontend to a Backend Using Services
      - Create an External Load Balancer
      - List All Container Images Running in a Cluster
      - Set up Ingress on Minikube with the NGINX Ingress Controller

Deploy the web UI (Kubernetes Dashboard) and access it.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Define Dependent Environment Variables

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/define-interdependent-environment-variables/

**Contents:**
- Define Dependent Environment Variables
- Before you begin
- Define an environment dependent variable for a container
- What's next
- Feedback

This page shows how to define dependent environment variables for a container in a Kubernetes Pod.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

When you create a Pod, you can set dependent environment variables for the containers that run in the Pod. To set dependent environment variables, you can use $(VAR_NAME) in the value of env in the configuration file.

In this exercise, you create a Pod that runs one container. The configuration file for the Pod defines a dependent environment variable with common usage defined. Here is the configuration manifest for the Pod:

Create a Pod based on that manifest:

List the running Pods:

Check the logs for the container running in your Pod:

As shown above, you have defined the correct dependency reference of SERVICE_ADDRESS, bad dependency reference of UNCHANGED_REFERENCE and skip dependent references of ESCAPED_REFERENCE.

When an environment variable is already defined when being referenced, the reference can be correctly resolved, such as in the SERVICE_ADDRESS case.

Note that order matters in the env list. An environment variable is not considered "defined" if it is specified further down the list. That is why UNCHANGED_REFERENCE fails to resolve $(PROTOCOL) in the example above.

When the environment variable is undefined or only includes some variables, the undefined environment variable is treated as a normal string, such as UNCHANGED_REFERENCE. Note that incorrectly parsed environment variables, in general, will not block the container from starting.

The $(VAR_NAME) syntax can be escaped with a double $, ie: $$(VAR_NAME). Escaped references are never expanded, regardless of whether the referenced variable is defined or not. This can be seen from the ESCAPED_REFERENCE case above.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dependent-envars-demo
spec:
  containers:
    - name: dependent-envars-demo
      args:
        - while true; do echo -en '\n'; printf UNCHANGED_REFERENCE=$UNCHANGED_REFERENCE'\n'; printf SERVICE_ADDRESS=$SERVICE_ADDRESS'\n';printf ESCAPED_REFERENCE=$ESCAPED_REFERENCE'\n'; sleep 30; done;
      command:
        - sh
        - -c
      image: busybox:1.28
      env:
        - name: SERVICE_PORT
          value: "80"
        - name: SERVICE_IP
          value: "172.17.0.1"
        - name: UNCHANGED_REFERENCE
          value: "$(PROTOCOL)://$(SERVICE_IP)
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/dependent-envars.yaml
```

Example 3 (unknown):
```unknown
pod/dependent-envars-demo created
```

Example 4 (shell):
```shell
kubectl get pods dependent-envars-demo
```

---

## Specifying a Disruption Budget for your Application

**URL:** https://kubernetes.io/docs/tasks/run-application/configure-pdb/

**Contents:**
- Specifying a Disruption Budget for your Application
- Before you begin
- Protecting an Application with a PodDisruptionBudget
- Identify an Application to Protect
- Think about how your application reacts to disruptions
  - Rounding logic when specifying percentages
- Specifying a PodDisruptionBudget
    - Note:
    - Note:
- Create the PDB object

This page shows how to limit the number of concurrent disruptions that your application experiences, allowing for higher availability while permitting the cluster administrator to manage the clusters nodes.

To check the version, enter kubectl version.

The most common use case when you want to protect an application specified by one of the built-in Kubernetes controllers:

In this case, make a note of the controller's .spec.selector; the same selector goes into the PDBs .spec.selector.

From version 1.15 PDBs support custom controllers where the scale subresource is enabled.

You can also use PDBs with pods which are not controlled by one of the above controllers, or arbitrary groups of pods, but there are some restrictions, described in Arbitrary workloads and arbitrary selectors.

Decide how many instances can be down at the same time for a short period due to a voluntary disruption.

Values for minAvailable or maxUnavailable can be expressed as integers or as a percentage.

When you specify the value as a percentage, it may not map to an exact number of Pods. For example, if you have 7 Pods and you set minAvailable to "50%", it's not immediately obvious whether that means 3 Pods or 4 Pods must be available. Kubernetes rounds up to the nearest integer, so in this case, 4 Pods must be available. When you specify the value maxUnavailable as a percentage, Kubernetes rounds up the number of Pods that may be disrupted. Thereby a disruption can exceed your defined maxUnavailable percentage. You can examine the code that controls this behavior.

A PodDisruptionBudget has three fields:

You can specify only one of maxUnavailable and minAvailable in a single PodDisruptionBudget. maxUnavailable can only be used to control the eviction of pods that all have the same associated controller managing them. In the examples below, "desired replicas" is the scale of the controller managing the pods being selected by the PodDisruptionBudget.

Example 1: With a minAvailable of 5, evictions are allowed as long as they leave behind 5 or more healthy pods among those selected by the PodDisruptionBudget's selector.

Example 2: With a minAvailable of 30%, evictions are allowed as long as at least 30% of the number of desired replicas are healthy.

Example 3: With a maxUnavailable of 5, evictions are allowed as long as there are at most 5 unhealthy replicas among the total number of desired replicas.

Example 4: With a maxUnavailable of 30%, evictions are allowed as long as the 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zk-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: zookeeper
```

Example 2 (yaml):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zk-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: zookeeper
```

Example 3 (shell):
```shell
kubectl apply -f mypdb.yaml
```

Example 4 (shell):
```shell
kubectl get poddisruptionbudgets
```

---

## Install and Set Up kubectl on Windows

**URL:** https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/

**Contents:**
- Install and Set Up kubectl on Windows
- Before you begin
- Install kubectl on Windows
  - Install kubectl binary on Windows (via direct download or curl)
    - Note:
    - Note:
  - Install on Windows using Chocolatey, Scoop, or winget
    - Note:
- Verify kubectl configuration
  - Troubleshooting the 'No Auth Provider Found' error message

You must use a kubectl version that is within one minor version difference of your cluster. For example, a v1.34 client can communicate with v1.33, v1.34, and v1.35 control planes. Using the latest compatible version of kubectl helps avoid unforeseen issues.

The following methods exist for installing kubectl on Windows:

You have two options for installing kubectl on your Windows device

Download the latest 1.34 patch release binary directly for your specific architecture by visiting the Kubernetes release page. Be sure to select the correct binary for your architecture (e.g., amd64, arm64, etc.).

If you have curl installed, use this command:

Validate the binary (optional)

Download the kubectl checksum file:

Validate the kubectl binary against the checksum file:

Using Command Prompt to manually compare CertUtil's output to the checksum file downloaded:

Using PowerShell to automate the verification using the -eq operator to get a True or False result:

Append or prepend the kubectl binary folder to your PATH environment variable.

Test to ensure the version of kubectl is the same as downloaded:

Or use this for detailed view of version:

To install kubectl on Windows you can use either Chocolatey package manager, Scoop command-line installer, or winget package manager.

choco install kubernetes-cli

scoop install kubectl

winget install -e --id Kubernetes.kubectl

Test to ensure the version you installed is up-to-date:

Navigate to your home directory:

Create the .kube directory:

Change to the .kube directory you just created:

Configure kubectl to use a remote Kubernetes cluster:

In order for kubectl to find and access a Kubernetes cluster, it needs a kubeconfig file, which is created automatically when you create a cluster using kube-up.sh or successfully deploy a Minikube cluster. By default, kubectl configuration is located at ~/.kube/config.

Check that kubectl is properly configured by getting the cluster state:

If you see a URL response, kubectl is correctly configured to access your cluster.

If you see a message similar to the following, kubectl is not configured correctly or is not able to connect to a Kubernetes cluster.

For example, if you are intending to run a Kubernetes cluster on your laptop (locally), you will need a tool like Minikube to be installed first and then re-run the commands stated above.

If kubectl cluster-info returns the url response but you can't access your cluster, to check whether it is configured properly, us

*[Content truncated]*

**Examples:**

Example 1 (powershell):
```powershell
curl.exe -LO "https://dl.k8s.io/release/v1.34.0/bin/windows/amd64/kubectl.exe"
```

Example 2 (powershell):
```powershell
curl.exe -LO "https://dl.k8s.io/v1.34.0/bin/windows/amd64/kubectl.exe.sha256"
```

Example 3 (cmd):
```cmd
CertUtil -hashfile kubectl.exe SHA256
type kubectl.exe.sha256
```

Example 4 (powershell):
```powershell
$(Get-FileHash -Algorithm SHA256 .\kubectl.exe).Hash -eq $(Get-Content .\kubectl.exe.sha256)
```

---

## Administration with kubeadm

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/

**Contents:**
- Administration with kubeadm
- Feedback

If you don't yet have a cluster, visit bootstrapping clusters with kubeadm.

The tasks in this section are aimed at people administering an existing cluster:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Assign Extended Resources to a Container

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/extended-resource/

**Contents:**
- Assign Extended Resources to a Container
- Before you begin
- Assign an extended resource to a Pod
- Attempt to create a second Pod
- Clean up
- What's next
  - For application developers
  - For cluster administrators
- Feedback

This page shows how to assign extended resources to a Container.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Before you do this exercise, do the exercise in Advertise Extended Resources for a Node. That will configure one of your Nodes to advertise a dongle resource.

To request an extended resource, include the resources:requests field in your Container manifest. Extended resources are fully qualified with any domain outside of *.kubernetes.io/. Valid extended resource names have the form example.com/foo where example.com is replaced with your organization's domain and foo is a descriptive resource name.

Here is the configuration file for a Pod that has one Container:

In the configuration file, you can see that the Container requests 3 dongles.

Verify that the Pod is running:

The output shows dongle requests:

Here is the configuration file for a Pod that has one Container. The Container requests two dongles.

Kubernetes will not be able to satisfy the request for two dongles, because the first Pod used three of the four available dongles.

Attempt to create a Pod:

The output shows that the Pod cannot be scheduled, because there is no Node that has 2 dongles available:

The output shows that the Pod was created, but not scheduled to run on a Node. It has a status of Pending:

Delete the Pods that you created for this exercise:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: extended-resource-demo
spec:
  containers:
  - name: extended-resource-demo-ctr
    image: nginx
    resources:
      requests:
        example.com/dongle: 3
      limits:
        example.com/dongle: 3
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/resource/extended-resource-pod.yaml
```

Example 3 (shell):
```shell
kubectl get pod extended-resource-demo
```

Example 4 (shell):
```shell
kubectl describe pod extended-resource-demo
```

---

## Using a KMS provider for data encryption

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/

**Contents:**
- Using a KMS provider for data encryption
    - Caution:
- Before you begin
  - KMS v1
  - KMS v2
- KMS encryption and per-object encryption keys
- Configuring the KMS provider
  - KMS v1
  - KMS v2
- Implementing a KMS plugin

This page shows how to configure a Key Management Service (KMS) provider and plugin to enable secret data encryption. In Kubernetes 1.34 there are two versions of KMS at-rest encryption. You should use KMS v2 if feasible because KMS v1 is deprecated (since Kubernetes v1.28) and disabled by default (since Kubernetes v1.29). KMS v2 offers significantly better performance characteristics than KMS v1.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

The version of Kubernetes that you need depends on which KMS API version you have selected. Kubernetes recommends using KMS v2.

To check the version, enter kubectl version.

Kubernetes version 1.10.0 or later is required

For version 1.29 and later, the v1 implementation of KMS is disabled by default. To enable the feature, set --feature-gates=KMSv1=true to configure a KMS v1 provider.

Your cluster must use etcd v3 or later

The KMS encryption provider uses an envelope encryption scheme to encrypt data in etcd. The data is encrypted using a data encryption key (DEK). The DEKs are encrypted with a key encryption key (KEK) that is stored and managed in a remote KMS.

If you use the (deprecated) v1 implementation of KMS, a new DEK is generated for each encryption.

With KMS v2, a new DEK is generated per encryption: the API server uses a key derivation function to generate single use data encryption keys from a secret seed combined with some random data. The seed is rotated whenever the KEK is rotated (see the Understanding key_id and Key Rotation section below for more details).

The KMS provider uses gRPC to communicate with a specific KMS plugin over a UNIX domain socket. The KMS plugin, which is implemented as a gRPC server and deployed on the same host(s) as the Kubernetes control plane, is responsible for all communication with the remote KMS.

To configure a KMS provider on the API server, include a provider of type kms in the providers array in the encryption configuration file and set the following properties:

KMS v2 does not support the cachesize property. All data encryption keys (DEKs) will be cached in the clear once the server has unwrapped them via a call to the KMS. Once cached, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps
      - pandas.awesome.bears.example
    providers:
      - kms:
          name: myKmsPluginFoo
          endpoint: unix:///tmp/socketfile-foo.sock
          cachesize: 100
          timeout: 3s
      - kms:
          name: myKmsPluginBar
          endpoint: unix:///tmp/socketfile-bar.sock
          cachesize: 100
          timeout: 3s
```

Example 2 (yaml):
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps
      - pandas.awesome.bears.example
    providers:
      - kms:
          apiVersion: v2
          name: myKmsPluginFoo
          endpoint: unix:///tmp/socketfile-foo.sock
          timeout: 3s
      - kms:
          apiVersion: v2
          name: myKmsPluginBar
          endpoint: unix:///tmp/socketfile-bar.sock
          timeout: 3s
```

Example 3 (shell):
```shell
kubectl create secret generic secret1 -n default --from-literal=mykey=mydata
```

Example 4 (shell):
```shell
ETCDCTL_API=3 etcdctl get /kubernetes.io/secrets/default/secret1 [...] | hexdump -C
```

---

## Extend Kubernetes

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/

**Contents:**
- Extend Kubernetes
      - Configure the Aggregation Layer
      - Use Custom Resources
      - Set up an Extension API Server
      - Configure Multiple Schedulers
      - Use an HTTP Proxy to Access the Kubernetes API
      - Use a SOCKS5 Proxy to Access the Kubernetes API
      - Set up Konnectivity service
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Get a Shell to a Running Container

**URL:** https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/

**Contents:**
- Get a Shell to a Running Container
- Before you begin
- Getting a shell to a container
    - Note:
- Writing the root page for nginx
- Running individual commands in a container
- Opening a shell when a Pod has more than one container
    - Note:
- What's next
- Feedback

This page shows how to use kubectl exec to get a shell to a running container.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

In this exercise, you create a Pod that has one container. The container runs the nginx image. Here is the configuration file for the Pod:

Verify that the container is running:

Get a shell to the running container:

In your shell, list the root directory:

In your shell, experiment with other commands. Here are some examples:

Look again at the configuration file for your Pod. The Pod has an emptyDir volume, and the container mounts the volume at /usr/share/nginx/html.

In your shell, create an index.html file in the /usr/share/nginx/html directory:

In your shell, send a GET request to the nginx server:

The output shows the text that you wrote to the index.html file:

When you are finished with your shell, enter exit.

In an ordinary command window, not your shell, list the environment variables in the running container:

Experiment with running other commands. Here are some examples:

If a Pod has more than one container, use --container or -c to specify a container in the kubectl exec command. For example, suppose you have a Pod named my-pod, and the Pod has two containers named main-app and helper-app. The following command would open a shell to the main-app container.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shell-demo
spec:
  volumes:
  - name: shared-data
    emptyDir: {}
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
  hostNetwork: true
  dnsPolicy: Default
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/shell-demo.yaml
```

Example 3 (shell):
```shell
kubectl get pod shell-demo
```

Example 4 (shell):
```shell
kubectl exec --stdin --tty shell-demo -- /bin/bash
```

---

## Configuring a cgroup driver

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/configure-cgroup-driver/

**Contents:**
- Configuring a cgroup driver
- Before you begin
- Configuring the container runtime cgroup driver
- Configuring the kubelet cgroup driver
    - Note:
    - Note:
- Using the cgroupfs driver
- Migrating to the systemd driver
    - Note:
  - Modify the kubelet ConfigMap

This page explains how to configure the kubelet's cgroup driver to match the container runtime cgroup driver for kubeadm clusters.

You should be familiar with the Kubernetes container runtime requirements.

The Container runtimes page explains that the systemd driver is recommended for kubeadm based setups instead of the kubelet's default cgroupfs driver, because kubeadm manages the kubelet as a systemd service.

The page also provides details on how to set up a number of different container runtimes with the systemd driver by default.

kubeadm allows you to pass a KubeletConfiguration structure during kubeadm init. This KubeletConfiguration can include the cgroupDriver field which controls the cgroup driver of the kubelet.

In v1.22 and later, if the user does not set the cgroupDriver field under KubeletConfiguration, kubeadm defaults it to systemd.

In Kubernetes v1.28, you can enable automatic detection of the cgroup driver as an alpha feature. See systemd cgroup driver for more details.

A minimal example of configuring the field explicitly:

Such a configuration file can then be passed to the kubeadm command:

Kubeadm uses the same KubeletConfiguration for all nodes in the cluster. The KubeletConfiguration is stored in a ConfigMap object under the kube-system namespace.

Executing the sub commands init, join and upgrade would result in kubeadm writing the KubeletConfiguration as a file under /var/lib/kubelet/config.yaml and passing it to the local node kubelet.

On each node, kubeadm detects the CRI socket and stores its details into the /var/lib/kubelet/instance-config.yaml file. When executing the init, join, or upgrade subcommands, kubeadm patches the containerRuntimeEndpoint value from this instance configuration into /var/lib/kubelet/config.yaml.

To use cgroupfs and to prevent kubeadm upgrade from modifying the KubeletConfiguration cgroup driver on existing setups, you must be explicit about its value. This applies to a case where you do not wish future versions of kubeadm to apply the systemd driver by default.

See the below section on "Modify the kubelet ConfigMap" for details on how to be explicit about the value.

If you wish to configure a container runtime to use the cgroupfs driver, you must refer to the documentation of the container runtime of your choice.

To change the cgroup driver of an existing kubeadm cluster from cgroupfs to systemd in-place, a similar procedure to a kubelet upgrade is required. This must include both steps out

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta4
kubernetesVersion: v1.21.0
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
```

Example 2 (shell):
```shell
kubeadm init --config kubeadm-config.yaml
```

Example 3 (yaml):
```yaml
cgroupDriver: systemd
```

---

## Configure a kubelet image credential provider

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubelet-credential-provider/

**Contents:**
- Configure a kubelet image credential provider
- Service Account Token for Image Pulls
- Before you begin
- Installing Plugins on Nodes
- Configuring the Kubelet
  - Configure a kubelet credential provider
    - Configure image matching
- What's next
- Feedback

Starting from Kubernetes v1.20, the kubelet can dynamically retrieve credentials for a container image registry using exec plugins. The kubelet and the exec plugin communicate through stdio (stdin, stdout, and stderr) using Kubernetes versioned APIs. These plugins allow the kubelet to request credentials for a container registry dynamically as opposed to storing static credentials on disk. For example, the plugin may talk to a local metadata server to retrieve short-lived credentials for an image that is being pulled by the kubelet.

You may be interested in using this capability if any of the below are true:

This guide demonstrates how to configure the kubelet's image credential provider plugin mechanism.

Starting from Kubernetes v1.33, the kubelet can be configured to send a service account token bound to the pod for which the image pull is being performed to the credential provider plugin.

This allows the plugin to exchange the token for credentials to access the image registry.

To enable this feature, the KubeletServiceAccountTokenForCredentialProviders feature gate must be enabled on the kubelet, and the tokenAttributes field must be set in the CredentialProviderConfig file for the plugin.

The tokenAttributes field contains information about the service account token that will be passed to the plugin, including the intended audience for the token and whether the plugin requires the pod to have a service account.

Using service account token credentials can enable the following use-cases:

To check the version, enter kubectl version.

A credential provider plugin is an executable binary that will be run by the kubelet. Ensure that the plugin binary exists on every node in your cluster and stored in a known directory. The directory will be required later when configuring kubelet flags.

In order to use this feature, the kubelet expects two flags to be set:

The configuration file passed into --image-credential-provider-config is read by the kubelet to determine which exec plugins should be invoked for which container images. Here's an example configuration file you may end up using if you are using the ECR-based plugin:

The providers field is a list of enabled plugins used by the kubelet. Each entry has a few required fields:

Each credential provider can also be given optional args and environment variables as well. Consult the plugin implementors to determine what set of arguments and environment variables are required for a given plugin.

If yo

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
# providers is a list of credential provider helper plugins that will be enabled by the kubelet.
# Multiple providers may match against a single image, in which case credentials
# from all providers will be returned to the kubelet. If multiple providers are called
# for a single image, the results are combined. If providers return overlapping
# auth keys, the value from the provider earlier in this list is used.
providers:
  # name is the required name of the credential provider. It must match the name of the
  # provider exec
...
```

---

## Configure Access to Multiple Clusters

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/

**Contents:**
- Configure Access to Multiple Clusters
    - Note:
    - Warning:
- Before you begin
- Define clusters, users, and contexts
    - Caution:
    - Note:
- Create a second configuration file
- Set the KUBECONFIG environment variable
  - Linux

This page shows how to configure access to multiple clusters by using configuration files. After your clusters, users, and contexts are defined in one or more configuration files, you can quickly switch between clusters by using the kubectl config use-context command.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check that kubectl is installed, run kubectl version --client. The kubectl version should be within one minor version of your cluster's API server.

Suppose you have two clusters, one for development work and one for test work. In the development cluster, your frontend developers work in a namespace called frontend, and your storage developers work in a namespace called storage. In your test cluster, developers work in the default namespace, or they create auxiliary namespaces as they see fit. Access to the development cluster requires authentication by certificate. Access to the test cluster requires authentication by username and password.

Create a directory named config-exercise. In your config-exercise directory, create a file named config-demo with this content:

A configuration file describes clusters, users, and contexts. Your config-demo file has the framework to describe two clusters, two users, and three contexts.

Go to your config-exercise directory. Enter these commands to add cluster details to your configuration file:

Add user details to your configuration file:

Add context details to your configuration file:

Open your config-demo file to see the added details. As an alternative to opening the config-demo file, you can use the config view command.

The output shows the two clusters, two users, and three contexts:

The fake-ca-file, fake-cert-file and fake-key-file above are the placeholders for the pathnames of the certificate files. You need to change these to the actual pathnames of certificate files in your environment.

Sometimes you may want to use Base64-encoded data embedded here instead of separate certificate files; in that case you need to add the suffix -data to the keys, for example, certificate-authority-data, client-certificate-data, client-key-data.

Each context is a triple (cluster, use

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Config
preferences: {}

clusters:
- cluster:
  name: development
- cluster:
  name: test

users:
- name: developer
- name: experimenter

contexts:
- context:
  name: dev-frontend
- context:
  name: dev-storage
- context:
  name: exp-test
```

Example 2 (shell):
```shell
kubectl config --kubeconfig=config-demo set-cluster development --server=https://1.2.3.4 --certificate-authority=fake-ca-file
kubectl config --kubeconfig=config-demo set-cluster test --server=https://5.6.7.8 --insecure-skip-tls-verify
```

Example 3 (shell):
```shell
kubectl config --kubeconfig=config-demo set-credentials developer --client-certificate=fake-cert-file --client-key=fake-key-seefile
kubectl config --kubeconfig=config-demo set-credentials experimenter --username=exp --password=some-password
```

Example 4 (shell):
```shell
kubectl config --kubeconfig=config-demo set-context dev-frontend --cluster=development --namespace=frontend --user=developer
kubectl config --kubeconfig=config-demo set-context dev-storage --cluster=development --namespace=storage --user=developer
kubectl config --kubeconfig=config-demo set-context exp-test --cluster=test --namespace=default --user=experimenter
```

---

## Coarse Parallel Processing Using a Work Queue

**URL:** https://kubernetes.io/docs/tasks/job/coarse-parallel-processing-work-queue/

**Contents:**
- Coarse Parallel Processing Using a Work Queue
- Before you begin
- Starting a message queue service
- Testing the message queue service
- Fill the queue with tasks
- Create a container image
- Defining a Job
- Running the Job
- Alternatives
- Caveats

In this example, you will run a Kubernetes Job with multiple parallel worker processes.

In this example, as each pod is created, it picks up one unit of work from a task queue, completes it, deletes it from the queue, and exits.

Here is an overview of the steps in this example:

You should already be familiar with the basic, non-parallel, use of Job.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You will need a container image registry where you can upload images to run in your cluster.

This task example also assumes that you have Docker installed locally.

This example uses RabbitMQ, however, you can adapt the example to use another AMQP-type message service.

In practice you could set up a message queue service once in a cluster and reuse it for many jobs, as well as for long-running services.

Start RabbitMQ as follows:

Now, we can experiment with accessing the message queue. We will create a temporary interactive pod, install some tools on it, and experiment with queues.

First create a temporary interactive Pod.

Note that your pod name and command prompt will be different.

Next install the amqp-tools so you can work with message queues. The next commands show what you need to run inside the interactive shell in that Pod:

Later, you will make a container image that includes these packages.

Next, you will check that you can discover the Service for RabbitMQ:

(the IP addresses will vary)

If the kube-dns addon is not set up correctly, the previous step may not work for you. You can also find the IP address for that Service in an environment variable:

(the IP address will vary)

Next you will verify that you can create a queue, and publish and consume messages.

Publish one message to the queue:

In the last command, the amqp-consume tool took one message (-c 1) from the queue, and passes that message to the standard input of an arbitrary command. In this case, the program cat prints out the characters read from standard input, and the echo adds a carriage return so the example is readable.

Now, fill the queue with some simulated tasks. In this example, the tasks are strings to be printed.

In a practice, the content of t

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
# make a Service for the StatefulSet to use
kubectl create -f https://kubernetes.io/examples/application/job/rabbitmq/rabbitmq-service.yaml
```

Example 2 (unknown):
```unknown
service "rabbitmq-service" created
```

Example 3 (shell):
```shell
kubectl create -f https://kubernetes.io/examples/application/job/rabbitmq/rabbitmq-statefulset.yaml
```

Example 4 (unknown):
```unknown
statefulset "rabbitmq" created
```

---

## Configure Liveness, Readiness and Startup Probes

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#configure-probes

**Contents:**
- Configure Liveness, Readiness and Startup Probes
    - Caution:
    - Note:
- Before you begin
- Define a liveness command
- Define a liveness HTTP request
- Define a TCP liveness probe
- Define a gRPC liveness probe
    - Note:
- Use a named port

This page shows how to configure liveness, readiness and startup probes for containers.

For more information about probes, see Liveness, Readiness and Startup Probes

The kubelet uses liveness probes to know when to restart a container. For example, liveness probes could catch a deadlock, where an application is running, but unable to make progress. Restarting a container in such a state can help to make the application more available despite bugs.

A common pattern for liveness probes is to use the same low-cost HTTP endpoint as for readiness probes, but with a higher failureThreshold. This ensures that the pod is observed as not-ready for some period of time before it is hard killed.

The kubelet uses readiness probes to know when a container is ready to start accepting traffic. One use of this signal is to control which Pods are used as backends for Services. A Pod is considered ready when its Ready condition is true. When a Pod is not ready, it is removed from Service load balancers. A Pod's Ready condition is false when its Node's Ready condition is not true, when one of the Pod's readinessGates is false, or when at least one of its containers is not ready.

The kubelet uses startup probes to know when a container application has started. If such a probe is configured, liveness and readiness probes do not start until it succeeds, making sure those probes don't interfere with the application startup. This can be used to adopt liveness checks on slow starting containers, avoiding them getting killed by the kubelet before they are up and running.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Many applications running for long periods of time eventually transition to broken states, and cannot recover except by being restarted. Kubernetes provides liveness probes to detect and remedy such situations.

In this exercise, you create a Pod that runs a container based on the registry.k8s.io/busybox:1.27.2 image. Here is the configuration file for the Pod:

In the configuration file, you can see that the Pod has a single Container. The periodSeconds field specifies that the kubelet should perform a liveness probe every 5 seconds. The init

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness
  name: liveness-exec
spec:
  containers:
  - name: liveness
    image: registry.k8s.io/busybox:1.27.2
    args:
    - /bin/sh
    - -c
    - touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
```

Example 2 (shell):
```shell
/bin/sh -c "touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/probe/exec-liveness.yaml
```

Example 4 (shell):
```shell
kubectl describe pod liveness-exec
```

---

## Running Kubernetes Node Components as a Non-root User

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubelet-in-userns/

**Contents:**
- Running Kubernetes Node Components as a Non-root User
    - Note:
- Before you begin
- Running Kubernetes inside Rootless Docker/Podman
  - kind
  - minikube
- Running Kubernetes inside Unprivileged Containers
  - sysbox
- Running Rootless Kubernetes directly on a host
  - K3s

This document describes how to run Kubernetes Node components such as kubelet, CRI, OCI, and CNI without root privileges, by using a user namespace.

This technique is also known as rootless mode.

This document describes how to run Kubernetes Node components (and hence pods) as a non-root user.

If you are just looking for how to run a pod as a non-root user, see SecurityContext.

Your Kubernetes server must be at or later than version 1.22.

To check the version, enter kubectl version.

kind supports running Kubernetes inside Rootless Docker or Rootless Podman.

See Running kind with Rootless Docker.

minikube also supports running Kubernetes inside Rootless Docker or Rootless Podman.

See the Minikube documentation:

Sysbox is an open-source container runtime (similar to "runc") that supports running system-level workloads such as Docker and Kubernetes inside unprivileged containers isolated with the Linux user namespace.

See Sysbox Quick Start Guide: Kubernetes-in-Docker for more info.

Sysbox supports running Kubernetes inside unprivileged containers without requiring Cgroup v2 and without the KubeletInUserNamespace feature gate. It does this by exposing specially crafted /proc and /sys filesystems inside the container plus several other advanced OS virtualization techniques.

K3s experimentally supports rootless mode.

See Running K3s with Rootless mode for the usage.

Usernetes is a reference distribution of Kubernetes that can be installed under $HOME directory without the root privilege.

Usernetes supports both containerd and CRI-O as CRI runtimes. Usernetes supports multi-node clusters using Flannel (VXLAN).

See the Usernetes repo for the usage.

This section provides hints for running Kubernetes in a user namespace manually.

The first step is to create a user namespace.

If you are trying to run Kubernetes in a user-namespaced container such as Rootless Docker/Podman or LXC/LXD, you are all set, and you can go to the next subsection.

Otherwise you have to create a user namespace by yourself, by calling unshare(2) with CLONE_NEWUSER.

A user namespace can be also unshared by using command line tools such as:

After unsharing the user namespace, you will also have to unshare other namespaces such as mount namespace.

You do not need to call chroot() nor pivot_root() after unsharing the mount namespace, however, you have to mount writable filesystems on several directories in the namespace.

At least, the following directories need to be writa

*[Content truncated]*

**Examples:**

Example 1 (toml):
```toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
# Disable AppArmor
  disable_apparmor = true
# Ignore an error during setting oom_score_adj
  restrict_oom_score_adj = true
# Disable hugetlb cgroup v2 controller (because systemd does not support delegating hugetlb controller)
  disable_hugetlb_controller = true

[plugins."io.containerd.grpc.v1.cri".containerd]
# Using non-fuse overlayfs is also possible for kernel >= 5.11, but requires SELinux to be disabled
  snapshotter = "fuse-overlayfs"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
# We use cgroupfs that is dele
...
```

Example 2 (toml):
```toml
[crio]
  storage_driver = "overlay"
# Using non-fuse overlayfs is also possible for kernel >= 5.11, but requires SELinux to be disabled
  storage_option = ["overlay.mount_program=/usr/local/bin/fuse-overlayfs"]

[crio.runtime]
# We use cgroupfs that is delegated by systemd, so we do not use "systemd" driver
# (unless you run another systemd in the namespace)
  cgroup_manager = "cgroupfs"
```

Example 3 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
featureGates:
  KubeletInUserNamespace: true
# We use cgroupfs that is delegated by systemd, so we do not use "systemd" driver
# (unless you run another systemd in the namespace)
cgroupDriver: "cgroupfs"
```

Example 4 (yaml):
```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables" # or "userspace"
conntrack:
# Skip setting sysctl value "net.netfilter.nf_conntrack_max"
  maxPerCore: 0
# Skip setting "net.netfilter.nf_conntrack_tcp_timeout_established"
  tcpEstablishedTimeout: 0s
# Skip setting "net.netfilter.nf_conntrack_tcp_timeout_close"
  tcpCloseWaitTimeout: 0s
```

---

## Use Cascading Deletion in a Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/use-cascading-deletion/

**Contents:**
- Use Cascading Deletion in a Cluster
- Before you begin
- Check owner references on your pods
- Use foreground cascading deletion
- Use background cascading deletion
- Delete owner objects and orphan dependents
- What's next
- Feedback

This page shows you how to specify the type of cascading deletion to use in your cluster during garbage collection.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You also need to create a sample Deployment to experiment with the different types of cascading deletion. You will need to recreate the Deployment for each type.

Check that the ownerReferences field is present on your pods:

The output has an ownerReferences field similar to this:

By default, Kubernetes uses background cascading deletion to delete dependents of an object. You can switch to foreground cascading deletion using either kubectl or the Kubernetes API, depending on the Kubernetes version your cluster runs.To check the version, enter kubectl version.

To check the version, enter kubectl version.

You can delete objects using foreground cascading deletion using kubectl or the Kubernetes API.

Run the following command:

Using the Kubernetes API

Start a local proxy session:

Use curl to trigger deletion:

The output contains a foregroundDeletion finalizer like this:

To check the version, enter kubectl version.

You can delete objects using background cascading deletion using kubectl or the Kubernetes API.

Kubernetes uses background cascading deletion by default, and does so even if you run the following commands without the --cascade flag or the propagationPolicy argument.

Run the following command:

Using the Kubernetes API

Start a local proxy session:

Use curl to trigger deletion:

The output is similar to this:

By default, when you tell Kubernetes to delete an object, the controller also deletes dependent objects. You can make Kubernetes orphan these dependents using kubectl or the Kubernetes API, depending on the Kubernetes version your cluster runs.To check the version, enter kubectl version.

To check the version, enter kubectl version.

Run the following command:

Using the Kubernetes API

Start a local proxy session:

Use curl to trigger deletion:

The output contains orphan in the finalizers field, similar to this:

You can check that the Pods managed by the Deployment are still running:

Was this page helpful?

Thanks for the feedback. If you have a

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pods -l app=nginx --output=yaml
```

Example 2 (yaml):
```yaml
apiVersion: v1
    ...
    ownerReferences:
    - apiVersion: apps/v1
      blockOwnerDeletion: true
      controller: true
      kind: ReplicaSet
      name: nginx-deployment-6b474476c4
      uid: 4fdcd81c-bd5d-41f7-97af-3a3b759af9a7
    ...
```

Example 3 (shell):
```shell
kubectl delete deployment nginx-deployment --cascade=foreground
```

Example 4 (shell):
```shell
kubectl proxy --port=8080
```

---

## Indexed Job for Parallel Processing with Static Work Assignment

**URL:** https://kubernetes.io/docs/tasks/job/indexed-parallel-processing-static/

**Contents:**
- Indexed Job for Parallel Processing with Static Work Assignment
- Before you begin
- Choose an approach
- Define an Indexed Job
- Running the Job
- Feedback

In this example, you will run a Kubernetes Job that uses multiple parallel worker processes. Each worker is a different container running in its own Pod. The Pods have an index number that the control plane sets automatically, which allows each Pod to identify which part of the overall task to work on.

The pod index is available in the annotation batch.kubernetes.io/job-completion-index as a string representing its decimal value. In order for the containerized task process to obtain this index, you can publish the value of the annotation using the downward API mechanism. For convenience, the control plane automatically sets the downward API to expose the index in the JOB_COMPLETION_INDEX environment variable.

Here is an overview of the steps in this example:

You should already be familiar with the basic, non-parallel, use of Job.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.21.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To access the work item from the worker program, you have a few options:

For this example, imagine that you chose option 3 and you want to run the rev utility. This program accepts a file as an argument and prints its content reversed.

You'll use the rev tool from the busybox container image.

As this is only an example, each Pod only does a tiny piece of work (reversing a short string). In a real workload you might, for example, create a Job that represents the task of producing 60 seconds of video based on scene data. Each work item in the video rendering Job would be to render a particular frame of that video clip. Indexed completion would mean that each Pod in the Job knows which frame to

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
rev data.txt
```

Example 2 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: 'indexed-job'
spec:
  completions: 5
  parallelism: 3
  completionMode: Indexed
  template:
    spec:
      restartPolicy: Never
      initContainers:
      - name: 'input'
        image: 'docker.io/library/bash'
        command:
        - "bash"
        - "-c"
        - |
          items=(foo bar baz qux xyz)
          echo ${items[$JOB_COMPLETION_INDEX]} > /input/data.txt          
        volumeMounts:
        - mountPath: /input
          name: input
      containers:
      - name: 'worker'
        image: 'docker.io/library/busybox'
        
...
```

Example 3 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: 'indexed-job'
spec:
  completions: 5
  parallelism: 3
  completionMode: Indexed
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: 'worker'
        image: 'docker.io/library/busybox'
        command:
        - "rev"
        - "/input/data.txt"
        volumeMounts:
        - mountPath: /input
          name: input
      volumes:
      - name: input
        downwardAPI:
          items:
          - path: "data.txt"
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion
...
```

Example 4 (shell):
```shell
# This uses the first approach (relying on $JOB_COMPLETION_INDEX)
kubectl apply -f https://kubernetes.io/examples/application/job/indexed-job.yaml
```

---

## Use Port Forwarding to Access Applications in a Cluster

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/

**Contents:**
- Use Port Forwarding to Access Applications in a Cluster
- Before you begin
- Creating MongoDB deployment and service
- Forward a local port to a port on the Pod
    - Note:
  - Optionally let kubectl choose the local port
- Discussion
    - Note:
- What's next
- Feedback

This page shows how to use kubectl port-forward to connect to a MongoDB server running in a Kubernetes cluster. This type of connection can be useful for database debugging.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Create a Deployment that runs MongoDB:

The output of a successful command verifies that the deployment was created:

View the pod status to check that it is ready:

The output displays the pod created:

View the Deployment's status:

The output displays that the Deployment was created:

The Deployment automatically manages a ReplicaSet. View the ReplicaSet status using:

The output displays that the ReplicaSet was created:

Create a Service to expose MongoDB on the network:

The output of a successful command verifies that the Service was created:

Check the Service created:

The output displays the service created:

Verify that the MongoDB server is running in the Pod, and listening on port 27017:

The output displays the port for MongoDB in that Pod:

27017 is the official TCP port for MongoDB.

kubectl port-forward allows using resource name, such as a pod name, to select a matching pod to port forward to.

Any of the above commands works. The output is similar to this:

Start the MongoDB command line interface:

At the MongoDB command line prompt, enter the ping command:

A successful ping request returns:

If you don't need a specific local port, you can let kubectl choose and allocate the local port and thus relieve you from having to manage local port conflicts, with the slightly simpler syntax:

The kubectl tool finds a local port number that is not in use (avoiding low ports numbers, because these might be used by other applications). The output is similar to:

Connections made to local port 28015 are forwarded to port 27017 of the Pod that is running the MongoDB server. With this connection in place, you can use your local workstation to debug the database that is running in the Pod.

Learn more about kubectl port-forward.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Ov

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/mongodb/mongo-deployment.yaml
```

Example 2 (unknown):
```unknown
deployment.apps/mongo created
```

Example 3 (shell):
```shell
kubectl get pods
```

Example 4 (unknown):
```unknown
NAME                     READY   STATUS    RESTARTS   AGE
mongo-75f59d57f4-4nd6q   1/1     Running   0          2m4s
```

---

## Configure Multiple Schedulers

**URL:** https://kubernetes.io/docs/tasks/extend-kubernetes/configure-multiple-schedulers/

**Contents:**
- Configure Multiple Schedulers
- Before you begin
- Package the scheduler
- Define a Kubernetes Deployment for the scheduler
    - Note:
- Run the second scheduler in the cluster
  - Enable leader election
    - Note:
- Specify schedulers for pods
  - Verifying that the pods were scheduled using the desired schedulers

Kubernetes ships with a default scheduler that is described here. If the default scheduler does not suit your needs you can implement your own scheduler. Moreover, you can even run multiple schedulers simultaneously alongside the default scheduler and instruct Kubernetes what scheduler to use for each of your pods. Let's learn how to run multiple schedulers in Kubernetes with an example.

A detailed description of how to implement a scheduler is outside the scope of this document. Please refer to the kube-scheduler implementation in pkg/scheduler in the Kubernetes source directory for a canonical example.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Package your scheduler binary into a container image. For the purposes of this example, you can use the default scheduler (kube-scheduler) as your second scheduler. Clone the Kubernetes source code from GitHub and build the source.

Create a container image containing the kube-scheduler binary. Here is the Dockerfile to build the image:

Save the file as Dockerfile, build the image and push it to a registry. This example pushes the image to Google Container Registry (GCR). For more details, please read the GCR documentation. Alternatively you can also use the docker hub. For more details refer to the docker hub documentation.

Now that you have your scheduler in a container image, create a pod configuration for it and run it in your Kubernetes cluster. But instead of creating a pod directly in the cluster, you can use a Deployment for this example. A Deployment manages a Replica Set which in turn manages the pods, thereby making the scheduler resilient to failures. Here is the deplo

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
make
```

Example 2 (docker):
```docker
FROM busybox
ADD ./_output/local/bin/linux/amd64/kube-scheduler /usr/local/bin/kube-scheduler
```

Example 3 (shell):
```shell
docker build -t gcr.io/my-gcp-project/my-kube-scheduler:1.0 .     # The image name and the repository
gcloud docker -- push gcr.io/my-gcp-project/my-kube-scheduler:1.0 # used in here is just an example
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-scheduler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: my-scheduler-as-kube-scheduler
subjects:
- kind: ServiceAccount
  name: my-scheduler
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:kube-scheduler
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: my-scheduler-as-volume-scheduler
subjects:
- kind: ServiceAccount
  name: my-scheduler
  namespace: kube-system
roleRef:
  ki
...
```

---

## Upgrade A Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/

**Contents:**
- Upgrade A Cluster
- Before you begin
- Upgrade approaches
  - kubeadm
  - Manual deployments
    - Caution:
    - Caution:
  - Other deployments
- Post-upgrade tasks
  - Switch your cluster's storage API version

This page provides an overview of the steps you should follow to upgrade a Kubernetes cluster.

The Kubernetes project recommends upgrading to the latest patch releases promptly, and to ensure that you are running a supported minor release of Kubernetes. Following this recommendation helps you to stay secure.

The way that you upgrade a cluster depends on how you initially deployed it and on any subsequent changes.

At a high level, the steps you perform are:

You must have an existing cluster. This page is about upgrading from Kubernetes 1.33 to Kubernetes 1.34. If your cluster is not currently running Kubernetes 1.33 then please check the documentation for the version of Kubernetes that you plan to upgrade to.

If your cluster was deployed using the kubeadm tool, refer to Upgrading kubeadm clusters for detailed information on how to upgrade the cluster.

Once you have upgraded the cluster, remember to install the latest version of kubectl.

You should manually update the control plane following this sequence:

At this point you should install the latest version of kubectl.

For each node in your cluster, drain that node and then either replace it with a new node that uses the 1.34 kubelet, or upgrade the kubelet on that node and bring the node back into service.

Refer to the documentation for your cluster deployment tool to learn the recommended set up steps for maintenance.

The objects that are serialized into etcd for a cluster's internal representation of the Kubernetes resources active in the cluster are written using a particular version of the API.

When the supported API changes, these objects may need to be rewritten in the newer API. Failure to do this will eventually result in resources that are no longer decodable or usable by the Kubernetes API server.

For each affected object, fetch it using the latest supported API and then write it back also using the latest supported API.

Upgrading to a new Kubernetes version can provide new APIs.

You can use kubectl convert command to convert manifests between different API versions. For example:

The kubectl tool replaces the contents of pod.yaml with a manifest that sets kind to Pod (unchanged), but with a revised apiVersion.

If your cluster is running device plugins and the node needs to be upgraded to a Kubernetes release with a newer device plugin API version, device plugins must be upgraded to support both version before the node is upgraded in order to guarantee that device allocations conti

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl convert -f pod.yaml --output-version v1
```

---
