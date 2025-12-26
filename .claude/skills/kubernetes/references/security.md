# Kubernetes - Security

**Pages:** 6

---

## Enforce Pod Security Standards with Namespace Labels

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/

**Contents:**
- Enforce Pod Security Standards with Namespace Labels
- Before you begin
- Requiring the baseline Pod Security Standard with namespace labels
- Add labels to existing namespaces with kubectl label
    - Note:
  - Applying to all namespaces
  - Applying to a single namespace
- Feedback

Namespaces can be labeled to enforce the Pod Security Standards. The three policies privileged, baseline and restricted broadly cover the security spectrum and are implemented by the Pod Security admission controller.

Pod Security Admission was available by default in Kubernetes v1.23, as a beta. From version 1.25 onwards, Pod Security Admission is generally available.

To check the version, enter kubectl version.

This manifest defines a Namespace my-baseline-namespace that:

It is helpful to apply the --dry-run flag when initially evaluating security profile changes for namespaces. The Pod Security Standard checks will still be run in dry run mode, giving you information about how the new policy would treat existing pods, without actually updating a policy.

If you're just getting started with the Pod Security Standards, a suitable first step would be to configure all namespaces with audit annotations for a stricter level such as baseline:

Note that this is not setting an enforce level, so that namespaces that haven't been explicitly evaluated can be distinguished. You can list namespaces without an explicitly set enforce level using this command:

You can update a specific namespace as well. This command adds the enforce=restricted policy to my-existing-namespace, pinning the restricted policy version to v1.34.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-baseline-namespace
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: v1.34

    # We are setting these to our _desired_ `enforce` level.
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.34
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.34
```

Example 2 (shell):
```shell
kubectl label --dry-run=server --overwrite ns --all \
    pod-security.kubernetes.io/enforce=baseline
```

Example 3 (shell):
```shell
kubectl label --overwrite ns --all \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline
```

Example 4 (shell):
```shell
kubectl get namespaces --selector='!pod-security.kubernetes.io/enforce'
```

---

## Apply Pod Security Standards at the Cluster Level

**URL:** https://kubernetes.io/docs/tutorials/security/cluster-level-pss/

**Contents:**
- Apply Pod Security Standards at the Cluster Level
    - Note
- Before you begin
- Choose the right Pod Security Standard to apply
- Set modes, versions and standards
    - Note:
    - Note:
- Clean up
- What's next
- Feedback

Pod Security is an admission controller that carries out checks against the Kubernetes Pod Security Standards when new pods are created. It is a feature GA'ed in v1.25. This tutorial shows you how to enforce the baseline Pod Security Standard at the cluster level which applies a standard configuration to all namespaces in a cluster.

To apply Pod Security Standards to specific namespaces, refer to Apply Pod Security Standards at the namespace level.

If you are running a version of Kubernetes other than v1.34, check the documentation for that version.

Install the following on your workstation:

This tutorial demonstrates what you can configure for a Kubernetes cluster that you fully control. If you are learning how to configure Pod Security Admission for a managed cluster where you are not able to configure the control plane, read Apply Pod Security Standards at the namespace level.

Pod Security Admission lets you apply built-in Pod Security Standards with the following modes: enforce, audit, and warn.

To gather information that helps you to choose the Pod Security Standards that are most appropriate for your configuration, do the following:

Create a cluster with no Pod Security Standards applied:

The output is similar to:

Set the kubectl context to the new cluster:

The output is similar to this:

Get a list of namespaces in the cluster:

The output is similar to this:

Use --dry-run=server to understand what happens when different Pod Security Standards are applied:

The output is similar to:

The output is similar to:

The output is similar to:

From the previous output, you'll notice that applying the privileged Pod Security Standard shows no warnings for any namespaces. However, baseline and restricted standards both have warnings, specifically in the kube-system namespace.

In this section, you apply the following Pod Security Standards to the latest version:

The baseline Pod Security Standard provides a convenient middle ground that allows keeping the exemption list short and prevents known privilege escalations.

Additionally, to prevent pods from failing in kube-system, you'll exempt the namespace from having Pod Security Standards applied.

When you implement Pod Security Admission in your own environment, consider the following:

Based on the risk posture applied to a cluster, a stricter Pod Security Standard like restricted might be a better choice.

Exempting the kube-system namespace allows pods to run as privileged in this namespace. 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kind create cluster --name psa-wo-cluster-pss
```

Example 2 (unknown):
```unknown
Creating cluster "psa-wo-cluster-pss" ...
✓ Ensuring node image (kindest/node:v1.34.0) 🖼
✓ Preparing nodes 📦
✓ Writing configuration 📜
✓ Starting control-plane 🕹️
✓ Installing CNI 🔌
✓ Installing StorageClass 💾
Set kubectl context to "kind-psa-wo-cluster-pss"
You can now use your cluster with:

kubectl cluster-info --context kind-psa-wo-cluster-pss

Thanks for using kind! 😊
```

Example 3 (shell):
```shell
kubectl cluster-info --context kind-psa-wo-cluster-pss
```

Example 4 (unknown):
```unknown
Kubernetes control plane is running at https://127.0.0.1:61350

CoreDNS is running at https://127.0.0.1:61350/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

---

## Enforce Pod Security Standards by Configuring the Built-in Admission Controller

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/

**Contents:**
- Enforce Pod Security Standards by Configuring the Built-in Admission Controller
- Before you begin
- Configure the Admission Controller
    - Note:
    - Note:
- Feedback

Kubernetes provides a built-in admission controller to enforce the Pod Security Standards. You can configure this admission controller to set cluster-wide defaults and exemptions.

Following an alpha release in Kubernetes v1.22, Pod Security Admission became available by default in Kubernetes v1.23, as a beta. From version 1.25 onwards, Pod Security Admission is generally available.

To check the version, enter kubectl version.

If you are not running Kubernetes 1.34, you can switch to viewing this page in the documentation for the Kubernetes version that you are running.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1 # see compatibility note
    kind: PodSecurityConfiguration
    # Defaults applied when a mode label is not set.
    #
    # Level label values must be one of:
    # - "privileged" (default)
    # - "baseline"
    # - "restricted"
    #
    # Version label values must be one of:
    # - "latest" (default) 
    # - specific version like "v1.34"
    defaults:
      enforce: "privileged"
      enforce-version: "latest"
      audi
...
```

---

## Configure a Security Context for a Pod or Container

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

**Contents:**
- Configure a Security Context for a Pod or Container
- Before you begin
- Set the security context for a Pod
  - Implicit group memberships defined in /etc/group in the container image
    - Note:
- Configure fine-grained SupplementalGroups control for a Pod
    - Note:
  - Implementations
    - Note:
- Configure volume permission and ownership change policy for Pods

A security context defines privilege and access control settings for a Pod or Container. Security context settings include, but are not limited to:

Discretionary Access Control: Permission to access an object, like a file, is based on user ID (UID) and group ID (GID).

Security Enhanced Linux (SELinux): Objects are assigned security labels.

Running as privileged or unprivileged.

Linux Capabilities: Give a process some privileges, but not all the privileges of the root user.

AppArmor: Use program profiles to restrict the capabilities of individual programs.

Seccomp: Filter a process's system calls.

allowPrivilegeEscalation: Controls whether a process can gain more privileges than its parent process. This bool directly controls whether the no_new_privs flag gets set on the container process. allowPrivilegeEscalation is always true when the container:

readOnlyRootFilesystem: Mounts the container's root filesystem as read-only.

The above bullets are not a complete set of security context settings -- please see SecurityContext for a comprehensive list.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To specify security settings for a Pod, include the securityContext field in the Pod specification. The securityContext field is a PodSecurityContext object. The security settings that you specify for a Pod apply to all Containers in the Pod. Here is a configuration file for a Pod that has a securityContext and an emptyDir volume:

In the configuration file, the runAsUser field specifies that for any Containers in the Pod, all processes run with user ID 1000. The runAsGroup field specifies the primary group ID of 3000 for all proces

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: security-context-demo
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    supplementalGroups: [4000]
  volumes:
  - name: sec-ctx-vol
    emptyDir: {}
  containers:
  - name: sec-ctx-demo
    image: busybox:1.28
    command: [ "sh", "-c", "sleep 1h" ]
    volumeMounts:
    - name: sec-ctx-vol
      mountPath: /data/demo
    securityContext:
      allowPrivilegeEscalation: false
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/security/security-context.yaml
```

Example 3 (shell):
```shell
kubectl get pod security-context-demo
```

Example 4 (shell):
```shell
kubectl exec -it security-context-demo -- sh
```

---

## Apply Pod Security Standards at the Namespace Level

**URL:** https://kubernetes.io/docs/tutorials/security/ns-level-pss/

**Contents:**
- Apply Pod Security Standards at the Namespace Level
    - Note
- Before you begin
- Create cluster
- Create a namespace
- Enable Pod Security Standards checking for that namespace
- Verify the Pod Security Standard enforcement
- Clean up
- What's next
- Feedback

Pod Security Admission is an admission controller that applies Pod Security Standards when pods are created. It is a feature GA'ed in v1.25. In this tutorial, you will enforce the baseline Pod Security Standard, one namespace at a time.

You can also apply Pod Security Standards to multiple namespaces at once at the cluster level. For instructions, refer to Apply Pod Security Standards at the cluster level.

Install the following on your workstation:

Create a kind cluster as follows:

The output is similar to this:

Set the kubectl context to the new cluster:

The output is similar to this:

Create a new namespace called example:

The output is similar to this:

Enable Pod Security Standards on this namespace using labels supported by built-in Pod Security Admission. In this step you will configure a check to warn on Pods that don't meet the latest version of the baseline pod security standard.

You can configure multiple pod security standard checks on any namespace, using labels. The following command will enforce the baseline Pod Security Standard, but warn and audit for restricted Pod Security Standards as per the latest version (default value)

Create a baseline Pod in the example namespace:

The Pod does start OK; the output includes a warning. For example:

Create a baseline Pod in the default namespace:

Output is similar to this:

The Pod Security Standards enforcement and warning settings were applied only to the example namespace. You could create the same Pod in the default namespace with no warnings.

Now delete the cluster which you created above by running the following command:

Run a shell script to perform all the preceding steps all at once.

Pod Security Admission

Pod Security Standards

Apply Pod Security Standards at the cluster level

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kind create cluster --name psa-ns-level
```

Example 2 (unknown):
```unknown
Creating cluster "psa-ns-level" ...
 ✓ Ensuring node image (kindest/node:v1.34.0) 🖼 
 ✓ Preparing nodes 📦  
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹️ 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
Set kubectl context to "kind-psa-ns-level"
You can now use your cluster with:

kubectl cluster-info --context kind-psa-ns-level

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```

Example 3 (shell):
```shell
kubectl cluster-info --context kind-psa-ns-level
```

Example 4 (unknown):
```unknown
Kubernetes control plane is running at https://127.0.0.1:50996
CoreDNS is running at https://127.0.0.1:50996/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

---

## Restrict a Container's Access to Resources with AppArmor

**URL:** https://kubernetes.io/docs/tutorials/security/apparmor/

**Contents:**
- Restrict a Container's Access to Resources with AppArmor
- Objectives
- Before you begin
- Securing a Pod
    - Note:
- Example
- Administration
  - Setting up Nodes with profiles
- Authoring Profiles
- Specifying AppArmor confinement

This page shows you how to load AppArmor profiles on your nodes and enforce those profiles in Pods. To learn more about how Kubernetes can confine Pods using AppArmor, see Linux kernel security constraints for Pods and containers.

AppArmor is an optional kernel module and Kubernetes feature, so verify it is supported on your Nodes before proceeding:

AppArmor kernel module is enabled -- For the Linux kernel to enforce an AppArmor profile, the AppArmor kernel module must be installed and enabled. Several distributions enable the module by default, such as Ubuntu and SUSE, and many others provide optional support. To check whether the module is enabled, check the /sys/module/apparmor/parameters/enabled file:

The kubelet verifies that AppArmor is enabled on the host before admitting a pod with AppArmor explicitly configured.

Container runtime supports AppArmor -- All common Kubernetes-supported container runtimes should support AppArmor, including containerd and CRI-O. Please refer to the corresponding runtime documentation and verify that the cluster fulfills the requirements to use AppArmor.

Profile is loaded -- AppArmor is applied to a Pod by specifying an AppArmor profile that each container should be run with. If any of the specified profiles are not loaded in the kernel, the kubelet will reject the Pod. You can view which profiles are loaded on a node by checking the /sys/kernel/security/apparmor/profiles file. For example:

For more details on loading profiles on nodes, see Setting up nodes with profiles.

AppArmor profiles can be specified at the pod level or container level. The container AppArmor profile takes precedence over the pod profile.

Where <profile_type> is one of:

See Specifying AppArmor Confinement for full details on the AppArmor profile API.

To verify that the profile was applied, you can check that the container's root process is running with the correct profile by examining its proc attr:

The output should look something like this:

This example assumes you have already set up a cluster with AppArmor support.

First, load the profile you want to use onto your Nodes. This profile blocks all file write operations:

The profile needs to be loaded onto all nodes, since you don't know where the pod will be scheduled. For this example you can use SSH to install the profiles, but other approaches are discussed in Setting up nodes with profiles.

Next, run a simple "Hello AppArmor" Pod with the deny-write profile:

You can verify that

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
cat /sys/module/apparmor/parameters/enabled
Y
```

Example 2 (shell):
```shell
ssh gke-test-default-pool-239f5d02-gyn2 "sudo cat /sys/kernel/security/apparmor/profiles | sort"
```

Example 3 (unknown):
```unknown
apparmor-test-deny-write (enforce)
apparmor-test-audit-write (enforce)
docker-default (enforce)
k8s-nginx (enforce)
```

Example 4 (yaml):
```yaml
securityContext:
  appArmorProfile:
    type: <profile_type>
```

---
