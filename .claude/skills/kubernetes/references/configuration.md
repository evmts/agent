# Kubernetes - Configuration

**Pages:** 20

---

## Encrypting Confidential Data at Rest

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#ensure-all-secrets-are-encrypted

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

## Configure a Pod to Use a ConfigMap

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#create-configmaps-from-files

**Contents:**
- Configure a Pod to Use a ConfigMap
- Before you begin
- Create a ConfigMap
  - Create a ConfigMap using kubectl create configmap
    - Create a ConfigMap from a directory
    - Note:
    - Create ConfigMaps from files
    - Define the key to use when creating a ConfigMap from a file
    - Create ConfigMaps from literal values
  - Create a ConfigMap from generator

Many applications rely on configuration which is used during either application initialization or runtime. Most times, there is a requirement to adjust values assigned to configuration parameters. ConfigMaps are a Kubernetes mechanism that let you inject configuration data into application pods.

The ConfigMap concept allow you to decouple configuration artifacts from image content to keep containerized applications portable. For example, you can download and run the same container image to spin up containers for the purposes of local development, system test, or running a live end-user workload.

This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the wget tool installed. If you have a different tool such as curl, and you do not have wget, you will need to adapt the step that downloads example data.

You can use either kubectl create configmap or a ConfigMap generator in kustomization.yaml to create a ConfigMap.

Use the kubectl create configmap command to create ConfigMaps from directories, files, or literal values:

where <map-name> is the name you want to assign to the ConfigMap and <data-source> is the directory, file, or literal value to draw the data from. The name of a ConfigMap object must be a valid DNS subdomain name.

When you are creating a ConfigMap based on a file, the key in the <data-source> defaults to the basename of the file, and the value defaults to the file content.

You can use kubectl describe or kubectl get to retrieve information about a ConfigMap.

You can use kubectl create configmap to create a ConfigMap from multiple files in the same directory. When you are creating a ConfigMap based on a directory, kubectl identifies files whose filename is a valid key in the directory and packages each of those files into the new ConfigMap. Any directory entries except regular files are ignored (for example: subdirectories, symlinks, devices, pipes, and more).

Each filename being used for ConfigMap creation must consist of only acceptable characters, which are: letters (

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap <map-name> <data-source>
```

Example 2 (shell):
```shell
mkdir -p configure-pod-container/configmap/
```

Example 3 (shell):
```shell
# Download the sample files into `configure-pod-container/configmap/` directory
wget https://kubernetes.io/examples/configmap/game.properties -O configure-pod-container/configmap/game.properties
wget https://kubernetes.io/examples/configmap/ui.properties -O configure-pod-container/configmap/ui.properties

# Create the ConfigMap
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
```

Example 4 (shell):
```shell
kubectl describe configmaps game-config
```

---

## Configure a Pod to Use a ConfigMap

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#create-configmaps-from-directories

**Contents:**
- Configure a Pod to Use a ConfigMap
- Before you begin
- Create a ConfigMap
  - Create a ConfigMap using kubectl create configmap
    - Create a ConfigMap from a directory
    - Note:
    - Create ConfigMaps from files
    - Define the key to use when creating a ConfigMap from a file
    - Create ConfigMaps from literal values
  - Create a ConfigMap from generator

Many applications rely on configuration which is used during either application initialization or runtime. Most times, there is a requirement to adjust values assigned to configuration parameters. ConfigMaps are a Kubernetes mechanism that let you inject configuration data into application pods.

The ConfigMap concept allow you to decouple configuration artifacts from image content to keep containerized applications portable. For example, you can download and run the same container image to spin up containers for the purposes of local development, system test, or running a live end-user workload.

This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the wget tool installed. If you have a different tool such as curl, and you do not have wget, you will need to adapt the step that downloads example data.

You can use either kubectl create configmap or a ConfigMap generator in kustomization.yaml to create a ConfigMap.

Use the kubectl create configmap command to create ConfigMaps from directories, files, or literal values:

where <map-name> is the name you want to assign to the ConfigMap and <data-source> is the directory, file, or literal value to draw the data from. The name of a ConfigMap object must be a valid DNS subdomain name.

When you are creating a ConfigMap based on a file, the key in the <data-source> defaults to the basename of the file, and the value defaults to the file content.

You can use kubectl describe or kubectl get to retrieve information about a ConfigMap.

You can use kubectl create configmap to create a ConfigMap from multiple files in the same directory. When you are creating a ConfigMap based on a directory, kubectl identifies files whose filename is a valid key in the directory and packages each of those files into the new ConfigMap. Any directory entries except regular files are ignored (for example: subdirectories, symlinks, devices, pipes, and more).

Each filename being used for ConfigMap creation must consist of only acceptable characters, which are: letters (

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap <map-name> <data-source>
```

Example 2 (shell):
```shell
mkdir -p configure-pod-container/configmap/
```

Example 3 (shell):
```shell
# Download the sample files into `configure-pod-container/configmap/` directory
wget https://kubernetes.io/examples/configmap/game.properties -O configure-pod-container/configmap/game.properties
wget https://kubernetes.io/examples/configmap/ui.properties -O configure-pod-container/configmap/ui.properties

# Create the ConfigMap
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
```

Example 4 (shell):
```shell
kubectl describe configmaps game-config
```

---

## Set Kubelet Parameters Via A Configuration File

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/

**Contents:**
- Set Kubelet Parameters Via A Configuration File
- Before you begin
- Create the config file
    - Note:
- Start a kubelet process configured via the config file
    - Note:
- Drop-in directory for kubelet configuration files
    - Note:
  - Kubelet configuration merging order
    - Note:

Some steps in this page use the jq tool. If you don't have jq, you can install it via your operating system's software sources, or fetch it from https://jqlang.github.io/jq/.

Some steps also involve installing curl, which can be installed via your operating system's software sources.

A subset of the kubelet's configuration parameters may be set via an on-disk config file, as a substitute for command-line flags.

Providing parameters via a config file is the recommended approach because it simplifies node deployment and configuration management.

The subset of the kubelet's configuration that can be configured via a file is defined by the KubeletConfiguration struct.

The configuration file must be a JSON or YAML representation of the parameters in this struct. Make sure the kubelet has read permissions on the file.

Here is an example of what this file might look like:

In this example, the kubelet is configured with the following settings:

address: The kubelet will serve on IP address 192.168.0.8.

port: The kubelet will serve on port 20250.

serializeImagePulls: Image pulls will be done in parallel.

evictionHard: The kubelet will evict Pods under one of the following conditions:

The imagefs is an optional filesystem that container runtimes use to store container images and container writable layers.

Start the kubelet with the --config flag set to the path of the kubelet's config file. The kubelet will then load its config from this file.

Note that command line flags which target the same value as a config file will override that value. This helps ensure backwards compatibility with the command-line API.

Note that relative file paths in the kubelet config file are resolved relative to the location of the kubelet config file, whereas relative paths in command line flags are resolved relative to the kubelet's current working directory.

Note that some default values differ between command-line flags and the kubelet config file. If --config is provided and the values are not specified via the command line, the defaults for the KubeletConfiguration version apply. In the above example, this version is kubelet.config.k8s.io/v1beta1.

You can specify a drop-in configuration directory for the kubelet. By default, the kubelet does not look for drop-in configuration files anywhere - you must specify a path. For example: --config-dir=/etc/kubernetes/kubelet.conf.d

For Kubernetes v1.28 to v1.29, you can only specify --config-dir if you also set the environme

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: "192.168.0.8"
port: 20250
serializeImagePulls: false
evictionHard:
    memory.available:  "100Mi"
    nodefs.available:  "10%"
    nodefs.inodesFree: "5%"
    imagefs.available: "15%"
    imagefs.inodesFree: "5%"
```

Example 2 (bash):
```bash
kubectl proxy
```

Example 3 (none):
```none
Starting to serve on 127.0.0.1:8001
```

Example 4 (bash):
```bash
curl -X GET http://127.0.0.1:8001/api/v1/nodes/<node-name>/proxy/configz | jq .
```

---

## Managing Secrets using Configuration File

**URL:** https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-config-file/

**Contents:**
- Managing Secrets using Configuration File
- Before you begin
- Create the Secret
    - Note:
  - Specify unencoded data when creating a Secret
    - Note:
  - Specify both data and stringData
    - Note:
- Edit a Secret
- Clean up

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You can define the Secret object in a manifest first, in JSON or YAML format, and then create that object. The Secret resource contains two maps: data and stringData. The data field is used to store arbitrary data, encoded using base64. The stringData field is provided for convenience, and it allows you to provide the same data as unencoded strings. The keys of data and stringData must consist of alphanumeric characters, -, _ or ..

The following example stores two strings in a Secret using the data field.

Convert the strings to base64:

The output is similar to:

Note that the name of a Secret object must be a valid DNS subdomain name.

Create the Secret using kubectl apply:

The output is similar to:

To verify that the Secret was created and to decode the Secret data, refer to Managing Secrets using kubectl.

For certain scenarios, you may wish to use the stringData field instead. This field allows you to put a non-base64 encoded string directly into the Secret, and the string will be encoded for you when the Secret is created or updated.

A practical example of this might be where you are deploying an application that uses a Secret to store a configuration file, and you want to populate parts of that configuration file during your deployment process.

For example, if your application uses the following configuration file:

You could store this in a Secret using the following definition:

When you retrieve the Secret data, the command returns the encoded values, and not the plaintext values you provided in stringData.

For example, if you run the following command:

The output is similar to:

If you specify a field in both data and stringData, the value from stringData is used.

For example, if you define the following Secret:

The Secret object is created as follows:

YWRtaW5pc3RyYXRvcg== decodes to administrator.

To edit the data in the Secret you created using a manifest, modify the data or stringData field in your manifest and apply the file to your cluster. You can edit an existing Secret object unless it is immutable.

For example, if you want to change the password from the pre

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
echo -n 'admin' | base64
echo -n '1f2d1e2e67df' | base64
```

Example 2 (unknown):
```unknown
YWRtaW4=
MWYyZDFlMmU2N2Rm
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
type: Opaque
data:
  username: YWRtaW4=
  password: MWYyZDFlMmU2N2Rm
```

Example 4 (shell):
```shell
kubectl apply -f ./secret.yaml
```

---

## Declarative Management of Kubernetes Objects Using Configuration Files

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#alternative-kubectl-apply-f-directory-prune

**Contents:**
- Declarative Management of Kubernetes Objects Using Configuration Files
- Before you begin
- Trade-offs
- Overview
- How to create objects
    - Note:
    - Note:
- How to update objects
    - Note:
    - Note:

Kubernetes objects can be created, updated, and deleted by storing multiple object configuration files in a directory and using kubectl apply to recursively create and update those objects as needed. This method retains writes made to live objects without merging the changes back into the object configuration files. kubectl diff also gives you a preview of what changes apply will make.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The kubectl tool supports three kinds of object management:

See Kubernetes Object Management for a discussion of the advantages and disadvantage of each kind of object management.

Declarative object configuration requires a firm understanding of the Kubernetes object definitions and configuration. Read and complete the following documents if you have not already:

Following are definitions for terms used in this document:

Use kubectl apply to create all objects, except those that already exist, defined by configuration files in a specified directory:

This sets the kubectl.kubernetes.io/last-applied-configuration: '{...}' annotation on each object. The annotation contains the contents of the object configuration file that was used to create the object.

Here's an example of an object configuration file:

Run kubectl diff to print the object that will be created:

diff uses server-side dry-run, which needs to be enabled on kube-apiserver.

Since diff performs a server-side apply request in dry-run mode, it requires granting PATCH, CREATE, and UPDATE permissions. See Dry-Run Authorization for details.

Create the object using kubectl apply:

Print the live configuration using kubectl get:

The output 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl apply -f <directory>
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  minReadySeconds: 5
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

Example 3 (shell):
```shell
kubectl diff -f https://k8s.io/examples/application/simple_deployment.yaml
```

Example 4 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/simple_deployment.yaml
```

---

## Managing Secrets

**URL:** https://kubernetes.io/docs/tasks/configmap-secret/

**Contents:**
- Managing Secrets
      - Managing Secrets using kubectl
      - Managing Secrets using Configuration File
      - Managing Secrets using Kustomize
- Feedback

Creating Secret objects using kubectl command line.

Creating Secret objects using resource configuration file.

Creating Secret objects using kustomization.yaml file.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Configure a Pod to Use a ConfigMap

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#create-configmaps-from-literal-values

**Contents:**
- Configure a Pod to Use a ConfigMap
- Before you begin
- Create a ConfigMap
  - Create a ConfigMap using kubectl create configmap
    - Create a ConfigMap from a directory
    - Note:
    - Create ConfigMaps from files
    - Define the key to use when creating a ConfigMap from a file
    - Create ConfigMaps from literal values
  - Create a ConfigMap from generator

Many applications rely on configuration which is used during either application initialization or runtime. Most times, there is a requirement to adjust values assigned to configuration parameters. ConfigMaps are a Kubernetes mechanism that let you inject configuration data into application pods.

The ConfigMap concept allow you to decouple configuration artifacts from image content to keep containerized applications portable. For example, you can download and run the same container image to spin up containers for the purposes of local development, system test, or running a live end-user workload.

This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the wget tool installed. If you have a different tool such as curl, and you do not have wget, you will need to adapt the step that downloads example data.

You can use either kubectl create configmap or a ConfigMap generator in kustomization.yaml to create a ConfigMap.

Use the kubectl create configmap command to create ConfigMaps from directories, files, or literal values:

where <map-name> is the name you want to assign to the ConfigMap and <data-source> is the directory, file, or literal value to draw the data from. The name of a ConfigMap object must be a valid DNS subdomain name.

When you are creating a ConfigMap based on a file, the key in the <data-source> defaults to the basename of the file, and the value defaults to the file content.

You can use kubectl describe or kubectl get to retrieve information about a ConfigMap.

You can use kubectl create configmap to create a ConfigMap from multiple files in the same directory. When you are creating a ConfigMap based on a directory, kubectl identifies files whose filename is a valid key in the directory and packages each of those files into the new ConfigMap. Any directory entries except regular files are ignored (for example: subdirectories, symlinks, devices, pipes, and more).

Each filename being used for ConfigMap creation must consist of only acceptable characters, which are: letters (

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap <map-name> <data-source>
```

Example 2 (shell):
```shell
mkdir -p configure-pod-container/configmap/
```

Example 3 (shell):
```shell
# Download the sample files into `configure-pod-container/configmap/` directory
wget https://kubernetes.io/examples/configmap/game.properties -O configure-pod-container/configmap/game.properties
wget https://kubernetes.io/examples/configmap/ui.properties -O configure-pod-container/configmap/ui.properties

# Create the ConfigMap
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
```

Example 4 (shell):
```shell
kubectl describe configmaps game-config
```

---

## Distribute Credentials Securely Using Secrets

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/#project-secret-keys-to-specific-file-paths

**Contents:**
- Distribute Credentials Securely Using Secrets
- Before you begin
  - Convert your secret data to a base-64 representation
    - Caution:
- Create a Secret
  - Create a Secret directly with kubectl
- Create a Pod that has access to the secret data through a Volume
  - Project Secret keys to specific file paths
  - Set POSIX permissions for Secret keys
    - Note:

This page shows how to securely inject sensitive data, such as passwords and encryption keys, into Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Suppose you want to have two pieces of secret data: a username my-app and a password 39528$vdg7Jb. First, use a base64 encoding tool to convert your username and password to a base64 representation. Here's an example using the commonly available base64 program:

The output shows that the base-64 representation of your username is bXktYXBw, and the base-64 representation of your password is Mzk1MjgkdmRnN0pi.

Here is a configuration file you can use to create a Secret that holds your username and password:

View information about the Secret:

View more detailed information about the Secret:

If you want to skip the Base64 encoding step, you can create the same Secret using the kubectl create secret command. For example:

This is more convenient. The detailed approach shown earlier runs through each step explicitly to demonstrate what is happening.

Here is a configuration file you can use to create a Pod:

Verify that your Pod is running:

Get a shell into the Container that is running in your Pod:

The secret data is exposed to the Container through a Volume mounted under /etc/secret-volume.

In your shell, list the files in the /etc/secret-volume directory:

The output shows two files, one for each piece of secret data:

In your shell, display the contents of the username and password files:

The output is your username and password:

Modify your image or command line so that the program looks for files in the mountPath directory. Each key in the Secret data map becomes a file name in this directory.

You can also control the paths within the volume where Secret keys are projected. Use the .spec.volumes[].secret.items field to change the target path of each key:

When you deploy this Pod, the following happens:

If you list keys explicitly using .spec.volumes[].secret.items, consider the following:

You can set the POSIX file access permission bits for a single Secret key. If you don't specify any permissions, 0644 is used by default. You can also set a default POSIX file mode for the

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
echo -n 'my-app' | base64
echo -n '39528$vdg7Jb' | base64
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
data:
  username: bXktYXBw
  password: Mzk1MjgkdmRnN0pi
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/secret.yaml
```

Example 4 (shell):
```shell
kubectl get secret test-secret
```

---

## Configure a Pod to Use a ConfigMap

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/

**Contents:**
- Configure a Pod to Use a ConfigMap
- Before you begin
- Create a ConfigMap
  - Create a ConfigMap using kubectl create configmap
    - Create a ConfigMap from a directory
    - Note:
    - Create ConfigMaps from files
    - Define the key to use when creating a ConfigMap from a file
    - Create ConfigMaps from literal values
  - Create a ConfigMap from generator

Many applications rely on configuration which is used during either application initialization or runtime. Most times, there is a requirement to adjust values assigned to configuration parameters. ConfigMaps are a Kubernetes mechanism that let you inject configuration data into application pods.

The ConfigMap concept allow you to decouple configuration artifacts from image content to keep containerized applications portable. For example, you can download and run the same container image to spin up containers for the purposes of local development, system test, or running a live end-user workload.

This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the wget tool installed. If you have a different tool such as curl, and you do not have wget, you will need to adapt the step that downloads example data.

You can use either kubectl create configmap or a ConfigMap generator in kustomization.yaml to create a ConfigMap.

Use the kubectl create configmap command to create ConfigMaps from directories, files, or literal values:

where <map-name> is the name you want to assign to the ConfigMap and <data-source> is the directory, file, or literal value to draw the data from. The name of a ConfigMap object must be a valid DNS subdomain name.

When you are creating a ConfigMap based on a file, the key in the <data-source> defaults to the basename of the file, and the value defaults to the file content.

You can use kubectl describe or kubectl get to retrieve information about a ConfigMap.

You can use kubectl create configmap to create a ConfigMap from multiple files in the same directory. When you are creating a ConfigMap based on a directory, kubectl identifies files whose filename is a valid key in the directory and packages each of those files into the new ConfigMap. Any directory entries except regular files are ignored (for example: subdirectories, symlinks, devices, pipes, and more).

Each filename being used for ConfigMap creation must consist of only acceptable characters, which are: letters (

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap <map-name> <data-source>
```

Example 2 (shell):
```shell
mkdir -p configure-pod-container/configmap/
```

Example 3 (shell):
```shell
# Download the sample files into `configure-pod-container/configmap/` directory
wget https://kubernetes.io/examples/configmap/game.properties -O configure-pod-container/configmap/game.properties
wget https://kubernetes.io/examples/configmap/ui.properties -O configure-pod-container/configmap/ui.properties

# Create the ConfigMap
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
```

Example 4 (shell):
```shell
kubectl describe configmaps game-config
```

---

## Adopting Sidecar Containers

**URL:** https://kubernetes.io/docs/tutorials/configuration/pod-sidecar-containers/

**Contents:**
- Adopting Sidecar Containers
- Objectives
- Before you begin
- Sidecar containers overview
- Benefits of a built-in sidecar container
- Adopting built-in sidecar containers
  - Ensure the feature gate is enabled
    - Note
  - Check for 3rd party tooling and mutating webhooks
    - Note

This section is relevant for people adopting a new built-in sidecar containers feature for their workloads.

Sidecar container is not a new concept as posted in the blog post. Kubernetes allows running multiple containers in a Pod to implement this concept. However, running a sidecar container as a regular container has a lot of limitations being fixed with the new built-in sidecar containers support.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.29.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Sidecar containers are secondary containers that run along with the main application container within the same Pod. These containers are used to enhance or to extend the functionality of the primary app container by providing additional services, or functionalities such as logging, monitoring, security, or data synchronization, without directly altering the primary application code. You can read more in the Sidecar containers concept page.

The concept of sidecar containers is not new and there are multiple implementations of this concept. As well as sidecar containers that you, the person defining the Pod, want to run, you can also find that some addons modify Pods - before the Pods start running - so that there are extra sidecar containers. The mechanisms to inject those extra sidecars are often mutating webhooks. For example, a service mesh addon might inject a sidecar that configures mutual TLS and encryption in transit between different Pods.

While the concept of sidecar containers is not new, the native implementation of this feature in Kubernetes, however, is new. And as with every new feature, adopting this feature ma

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get --raw /metrics | grep kubernetes_feature_enabled | grep SidecarContainers
```

Example 2 (shell):
```shell
kubectl get --raw /api/v1/nodes/<node-name>/proxy/metrics | grep kubernetes_feature_enabled | grep SidecarContainers
```

Example 3 (unknown):
```unknown
kubernetes_feature_enabled{name="SidecarContainers",stage="BETA"} 1
```

---

## Declarative Management of Kubernetes Objects Using Configuration Files

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/

**Contents:**
- Declarative Management of Kubernetes Objects Using Configuration Files
- Before you begin
- Trade-offs
- Overview
- How to create objects
    - Note:
    - Note:
- How to update objects
    - Note:
    - Note:

Kubernetes objects can be created, updated, and deleted by storing multiple object configuration files in a directory and using kubectl apply to recursively create and update those objects as needed. This method retains writes made to live objects without merging the changes back into the object configuration files. kubectl diff also gives you a preview of what changes apply will make.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The kubectl tool supports three kinds of object management:

See Kubernetes Object Management for a discussion of the advantages and disadvantage of each kind of object management.

Declarative object configuration requires a firm understanding of the Kubernetes object definitions and configuration. Read and complete the following documents if you have not already:

Following are definitions for terms used in this document:

Use kubectl apply to create all objects, except those that already exist, defined by configuration files in a specified directory:

This sets the kubectl.kubernetes.io/last-applied-configuration: '{...}' annotation on each object. The annotation contains the contents of the object configuration file that was used to create the object.

Here's an example of an object configuration file:

Run kubectl diff to print the object that will be created:

diff uses server-side dry-run, which needs to be enabled on kube-apiserver.

Since diff performs a server-side apply request in dry-run mode, it requires granting PATCH, CREATE, and UPDATE permissions. See Dry-Run Authorization for details.

Create the object using kubectl apply:

Print the live configuration using kubectl get:

The output 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl apply -f <directory>
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  minReadySeconds: 5
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

Example 3 (shell):
```shell
kubectl diff -f https://k8s.io/examples/application/simple_deployment.yaml
```

Example 4 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/simple_deployment.yaml
```

---

## Managing Secrets using kubectl

**URL:** https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/

**Contents:**
- Managing Secrets using kubectl
- Before you begin
- Create a Secret
  - Use raw data
    - Note:
  - Use source files
  - Verify the Secret
  - Decode the Secret
    - Caution:
- Edit a Secret

This page shows you how to create, edit, manage, and delete Kubernetes Secrets using the kubectl command-line tool.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

A Secret object stores sensitive data such as credentials used by Pods to access services. For example, you might need a Secret to store the username and password needed to access a database.

You can create the Secret by passing the raw data in the command, or by storing the credentials in files that you pass in the command. The following commands create a Secret that stores the username admin and the password S!B\*d$zDsb=.

Run the following command:

You must use single quotes '' to escape special characters such as $, \, *, =, and ! in your strings. If you don't, your shell will interpret these characters.

Store the credentials in files:

The -n flag ensures that the generated files do not have an extra newline character at the end of the text. This is important because when kubectl reads a file and encodes the content into a base64 string, the extra newline character gets encoded too. You do not need to escape special characters in strings that you include in a file.

Pass the file paths in the kubectl command:

The default key name is the file name. You can optionally set the key name using --from-file=[key=]source. For example:

With either method, the output is similar to:

Check that the Secret was created:

The output is similar to:

View the details of the Secret:

The output is similar to:

The commands kubectl get and kubectl describe avoid showing the contents of a Secret by default. This is to protect the Secret from being exposed accidentally, or from being stored in a terminal log.

View the contents of the Secret you created:

The output is similar to:

Decode the password data:

The output is similar to:

You can edit an existing Secret object unless it is immutable. To edit a Secret, run the following command:

This opens your default editor and allows you to update the base64 encoded Secret values in the data field, such as in the following example:

To delete a Secret, run the following command:

Was this page helpful?

Thanks for the feedback. If you 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create secret generic db-user-pass \
    --from-literal=username=admin \
    --from-literal=password='S!B\*d$zDsb='
```

Example 2 (shell):
```shell
echo -n 'admin' > ./username.txt
echo -n 'S!B\*d$zDsb=' > ./password.txt
```

Example 3 (shell):
```shell
kubectl create secret generic db-user-pass \
    --from-file=./username.txt \
    --from-file=./password.txt
```

Example 4 (shell):
```shell
kubectl create secret generic db-user-pass \
    --from-file=username=./username.txt \
    --from-file=password=./password.txt
```

---

## Updating Configuration via a ConfigMap

**URL:** https://kubernetes.io/docs/tutorials/configuration/updating-configuration-via-a-configmap/

**Contents:**
- Updating Configuration via a ConfigMap
- Before you begin
- Objectives
- Update configuration via a ConfigMap mounted as a Volume
    - Note:
- Update environment variables of a Pod via a ConfigMap
    - Note:
    - Note:
- Update configuration via a ConfigMap in a multi-container Pod
- Update configuration via a ConfigMap in a Pod possessing a sidecar container

This page provides a step-by-step example of updating configuration within a Pod via a ConfigMap and builds upon the Configure a Pod to Use a ConfigMap task.At the end of this tutorial, you will understand how to change the configuration for a running application.This tutorial uses the alpine and nginx images as examples.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the curl command-line tool for making HTTP requests from the terminal or command prompt. If you do not have curl available, you can install it. Check the documentation for your local operating system.

Use the kubectl create configmap command to create a ConfigMap from literal values:

Below is an example of a Deployment manifest with the ConfigMap sport mounted as a volume into the Pod's only container.

Create the Deployment:

Check the pods for this Deployment to ensure they are ready (matching by selector):

You should see an output similar to:

On each node where one of these Pods is running, the kubelet fetches the data for that ConfigMap and translates it to files in a local volume. The kubelet then mounts that volume into the container, as specified in the Pod template. The code running in that container loads the information from the file and uses it to print a report to stdout. You can check this report by viewing the logs for one of the Pods in that Deployment:

You should see an output similar to:

In the editor that appears, change the value of key sport from football to cricket. Save your changes. The kubectl tool updates the ConfigMap accordingly (if you see an error, try again).

Here's an example of how that manifest could look after you edit it:

You should see the following output:

Tail (follow the latest entries in) the logs of one of the pods that belongs to this Deployment:

After few seconds, you should see the log output change as follows:

When you have a ConfigMap that is mapped into a running Pod using either a configMap volume or a projected volume, and you update that ConfigMap, the running Pod sees the update almost immediately.However, your application only sees the change if it is written to either poll for changes, or wa

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap sport --from-literal=sport=football
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: configmap-volume
  labels:
    app.kubernetes.io/name: configmap-volume
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: configmap-volume
  template:
    metadata:
      labels:
        app.kubernetes.io/name: configmap-volume
    spec:
      containers:
        - name: alpine
          image: alpine:3
          command:
            - /bin/sh
            - -c
            - while true; do echo "$(date) My preferred sport is $(cat /etc/config/sport)";
              sleep 10; done;
          ports:
            - 
...
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/deployments/deployment-with-configmap-as-volume.yaml
```

Example 4 (shell):
```shell
kubectl get pods --selector=app.kubernetes.io/name=configmap-volume
```

---

## Distribute Credentials Securely Using Secrets

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/

**Contents:**
- Distribute Credentials Securely Using Secrets
- Before you begin
  - Convert your secret data to a base-64 representation
    - Caution:
- Create a Secret
  - Create a Secret directly with kubectl
- Create a Pod that has access to the secret data through a Volume
  - Project Secret keys to specific file paths
  - Set POSIX permissions for Secret keys
    - Note:

This page shows how to securely inject sensitive data, such as passwords and encryption keys, into Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Suppose you want to have two pieces of secret data: a username my-app and a password 39528$vdg7Jb. First, use a base64 encoding tool to convert your username and password to a base64 representation. Here's an example using the commonly available base64 program:

The output shows that the base-64 representation of your username is bXktYXBw, and the base-64 representation of your password is Mzk1MjgkdmRnN0pi.

Here is a configuration file you can use to create a Secret that holds your username and password:

View information about the Secret:

View more detailed information about the Secret:

If you want to skip the Base64 encoding step, you can create the same Secret using the kubectl create secret command. For example:

This is more convenient. The detailed approach shown earlier runs through each step explicitly to demonstrate what is happening.

Here is a configuration file you can use to create a Pod:

Verify that your Pod is running:

Get a shell into the Container that is running in your Pod:

The secret data is exposed to the Container through a Volume mounted under /etc/secret-volume.

In your shell, list the files in the /etc/secret-volume directory:

The output shows two files, one for each piece of secret data:

In your shell, display the contents of the username and password files:

The output is your username and password:

Modify your image or command line so that the program looks for files in the mountPath directory. Each key in the Secret data map becomes a file name in this directory.

You can also control the paths within the volume where Secret keys are projected. Use the .spec.volumes[].secret.items field to change the target path of each key:

When you deploy this Pod, the following happens:

If you list keys explicitly using .spec.volumes[].secret.items, consider the following:

You can set the POSIX file access permission bits for a single Secret key. If you don't specify any permissions, 0644 is used by default. You can also set a default POSIX file mode for the

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
echo -n 'my-app' | base64
echo -n '39528$vdg7Jb' | base64
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
data:
  username: bXktYXBw
  password: Mzk1MjgkdmRnN0pi
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/secret.yaml
```

Example 4 (shell):
```shell
kubectl get secret test-secret
```

---

## Configure a Pod to Use a ConfigMap

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#optional-configmaps

**Contents:**
- Configure a Pod to Use a ConfigMap
- Before you begin
- Create a ConfigMap
  - Create a ConfigMap using kubectl create configmap
    - Create a ConfigMap from a directory
    - Note:
    - Create ConfigMaps from files
    - Define the key to use when creating a ConfigMap from a file
    - Create ConfigMaps from literal values
  - Create a ConfigMap from generator

Many applications rely on configuration which is used during either application initialization or runtime. Most times, there is a requirement to adjust values assigned to configuration parameters. ConfigMaps are a Kubernetes mechanism that let you inject configuration data into application pods.

The ConfigMap concept allow you to decouple configuration artifacts from image content to keep containerized applications portable. For example, you can download and run the same container image to spin up containers for the purposes of local development, system test, or running a live end-user workload.

This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You need to have the wget tool installed. If you have a different tool such as curl, and you do not have wget, you will need to adapt the step that downloads example data.

You can use either kubectl create configmap or a ConfigMap generator in kustomization.yaml to create a ConfigMap.

Use the kubectl create configmap command to create ConfigMaps from directories, files, or literal values:

where <map-name> is the name you want to assign to the ConfigMap and <data-source> is the directory, file, or literal value to draw the data from. The name of a ConfigMap object must be a valid DNS subdomain name.

When you are creating a ConfigMap based on a file, the key in the <data-source> defaults to the basename of the file, and the value defaults to the file content.

You can use kubectl describe or kubectl get to retrieve information about a ConfigMap.

You can use kubectl create configmap to create a ConfigMap from multiple files in the same directory. When you are creating a ConfigMap based on a directory, kubectl identifies files whose filename is a valid key in the directory and packages each of those files into the new ConfigMap. Any directory entries except regular files are ignored (for example: subdirectories, symlinks, devices, pipes, and more).

Each filename being used for ConfigMap creation must consist of only acceptable characters, which are: letters (

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create configmap <map-name> <data-source>
```

Example 2 (shell):
```shell
mkdir -p configure-pod-container/configmap/
```

Example 3 (shell):
```shell
# Download the sample files into `configure-pod-container/configmap/` directory
wget https://kubernetes.io/examples/configmap/game.properties -O configure-pod-container/configmap/game.properties
wget https://kubernetes.io/examples/configmap/ui.properties -O configure-pod-container/configmap/ui.properties

# Create the ConfigMap
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
```

Example 4 (shell):
```shell
kubectl describe configmaps game-config
```

---

## Managing Secrets using Kustomize

**URL:** https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kustomize/

**Contents:**
- Managing Secrets using Kustomize
- Before you begin
- Create a Secret
    - Note:
  - Create the kustomization file
  - Apply the kustomization file
- Edit a Secret
- Clean up
- What's next
- Feedback

kubectl supports using the Kustomize object management tool to manage Secrets and ConfigMaps. You create a resource generator using Kustomize, which generates a Secret that you can apply to the API server using kubectl.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You can generate a Secret by defining a secretGenerator in a kustomization.yaml file that references other existing files, .env files, or literal values. For example, the following instructions create a kustomization file for the username admin and the password 1f2d1e2e67df.

secretGenerator: - name: database-creds literals: - username=admin - password=1f2d1e2e67df

Store the credentials in files. The filenames are the keys of the secret:echo -n 'admin' > ./username.txt echo -n '1f2d1e2e67df' > ./password.txt The -n flag ensures that there's no newline character at the end of your files.Create the kustomization.yaml file:secretGenerator: - name: database-creds files: - username.txt - password.txt

Store the credentials in files. The filenames are the keys of the secret:

The -n flag ensures that there's no newline character at the end of your files.

Create the kustomization.yaml file:

You can also define the secretGenerator in the kustomization.yaml file by providing .env files. For example, the following kustomization.yaml file pulls in data from an .env.secret file:secretGenerator: - name: db-user-pass envs: - .env.secret

You can also define the secretGenerator in the kustomization.yaml file by providing .env files. For example, the following kustomization.yaml file pulls in data from an .env.secret file:

In all cases, you don't need to encode the values in base64. The name of the YAML file must be kustomization.yaml or kustomization.yml.

To create the Secret, apply the directory that contains the kustomization file:

The output is similar to:

When a Secret is generated, the Secret name is created by hashing the Secret data and appending the hash value to the name. This ensures that a new Secret is generated each time the data is modified.

To verify that the Secret was created and to decode the Secret data,

The output is similar to:

The output is similar to:

Fo

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
secretGenerator:
- name: database-creds
  literals:
  - username=admin
  - password=1f2d1e2e67df
```

Example 2 (shell):
```shell
echo -n 'admin' > ./username.txt
echo -n '1f2d1e2e67df' > ./password.txt
```

Example 3 (yaml):
```yaml
secretGenerator:
- name: database-creds
  files:
  - username.txt
  - password.txt
```

Example 4 (yaml):
```yaml
secretGenerator:
- name: db-user-pass
  envs:
  - .env.secret
```

---

## Distribute Credentials Securely Using Secrets

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/#set-posix-permissions-for-secret-keys

**Contents:**
- Distribute Credentials Securely Using Secrets
- Before you begin
  - Convert your secret data to a base-64 representation
    - Caution:
- Create a Secret
  - Create a Secret directly with kubectl
- Create a Pod that has access to the secret data through a Volume
  - Project Secret keys to specific file paths
  - Set POSIX permissions for Secret keys
    - Note:

This page shows how to securely inject sensitive data, such as passwords and encryption keys, into Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Suppose you want to have two pieces of secret data: a username my-app and a password 39528$vdg7Jb. First, use a base64 encoding tool to convert your username and password to a base64 representation. Here's an example using the commonly available base64 program:

The output shows that the base-64 representation of your username is bXktYXBw, and the base-64 representation of your password is Mzk1MjgkdmRnN0pi.

Here is a configuration file you can use to create a Secret that holds your username and password:

View information about the Secret:

View more detailed information about the Secret:

If you want to skip the Base64 encoding step, you can create the same Secret using the kubectl create secret command. For example:

This is more convenient. The detailed approach shown earlier runs through each step explicitly to demonstrate what is happening.

Here is a configuration file you can use to create a Pod:

Verify that your Pod is running:

Get a shell into the Container that is running in your Pod:

The secret data is exposed to the Container through a Volume mounted under /etc/secret-volume.

In your shell, list the files in the /etc/secret-volume directory:

The output shows two files, one for each piece of secret data:

In your shell, display the contents of the username and password files:

The output is your username and password:

Modify your image or command line so that the program looks for files in the mountPath directory. Each key in the Secret data map becomes a file name in this directory.

You can also control the paths within the volume where Secret keys are projected. Use the .spec.volumes[].secret.items field to change the target path of each key:

When you deploy this Pod, the following happens:

If you list keys explicitly using .spec.volumes[].secret.items, consider the following:

You can set the POSIX file access permission bits for a single Secret key. If you don't specify any permissions, 0644 is used by default. You can also set a default POSIX file mode for the

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
echo -n 'my-app' | base64
echo -n '39528$vdg7Jb' | base64
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
data:
  username: bXktYXBw
  password: Mzk1MjgkdmRnN0pi
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/secret.yaml
```

Example 4 (shell):
```shell
kubectl get secret test-secret
```

---

## Configuring Redis using a ConfigMap

**URL:** https://kubernetes.io/docs/tutorials/configuration/configure-redis-using-configmap/

**Contents:**
- Configuring Redis using a ConfigMap
- Objectives
- Before you begin
- Real World Example: Configuring Redis using a ConfigMap
- What's next
- Feedback

This page provides a real world example of how to configure Redis using a ConfigMap and builds upon the Configure a Pod to Use a ConfigMap task.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Follow the steps below to configure a Redis cache using data stored in a ConfigMap.

First create a ConfigMap with an empty configuration block:

Apply the ConfigMap created above, along with a Redis pod manifest:

Examine the contents of the Redis pod manifest and note the following:

This has the net effect of exposing the data in data.redis-config from the example-redis-config ConfigMap above as /redis-master/redis.conf inside the Pod.

Examine the created objects:

You should see the following output:

Recall that we left redis-config key in the example-redis-config ConfigMap blank:

You should see an empty redis-config key:

Use kubectl exec to enter the pod and run the redis-cli tool to check the current configuration:

It should show the default value of 0:

Similarly, check maxmemory-policy:

Which should also yield its default value of noeviction:

Now let's add some configuration values to the example-redis-config ConfigMap:

Apply the updated ConfigMap:

Confirm that the ConfigMap was updated:

You should see the configuration values we just added:

Check the Redis Pod again using redis-cli via kubectl exec to see if the configuration was applied:

It remains at the default value of 0:

Similarly, maxmemory-policy remains at the noeviction default setting:

The configuration values have not changed because the Pod needs to be restarted to grab updated values from associated ConfigMaps. Let's delete and recreate the Pod:

Now re-ch

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
cat <<EOF >./example-redis-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-redis-config
data:
  redis-config: ""
EOF
```

Example 2 (shell):
```shell
kubectl apply -f example-redis-config.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/pods/config/redis-pod.yaml
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: redis
spec:
  containers:
  - name: redis
    image: redis:8.0.2
    command:
      - redis-server
      - "/redis-master/redis.conf"
    env:
    - name: MASTER
      value: "true"
    ports:
    - containerPort: 6379
    resources:
      limits:
        cpu: "0.1"
    volumeMounts:
    - mountPath: /redis-master-data
      name: data
    - mountPath: /redis-master
      name: config
  volumes:
    - name: data
      emptyDir: {}
    - name: config
      configMap:
        name: example-redis-config
        items:
        - key: redis-config
        
...
```

Example 4 (shell):
```shell
kubectl get pod/redis configmap/example-redis-config
```

---

## Imperative Management of Kubernetes Objects Using Configuration Files

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-config/

**Contents:**
- Imperative Management of Kubernetes Objects Using Configuration Files
- Before you begin
- Trade-offs
- How to create objects
- How to update objects
    - Warning:
- How to delete objects
    - Note:
- How to view an object
- Limitations

Kubernetes objects can be created, updated, and deleted by using the kubectl command-line tool along with an object configuration file written in YAML or JSON. This document explains how to define and manage objects using configuration files.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The kubectl tool supports three kinds of object management:

See Kubernetes Object Management for a discussion of the advantages and disadvantage of each kind of object management.

You can use kubectl create -f to create an object from a configuration file. Refer to the kubernetes API reference for details.

You can use kubectl replace -f to update a live object according to a configuration file.

You can use kubectl delete -f to delete an object that is described in a configuration file.

If configuration file has specified the generateName field in the metadata section instead of the name field, you cannot delete the object using kubectl delete -f <filename|url>. You will have to use other flags for deleting the object. For example:

You can use kubectl get -f to view information about an object that is described in a configuration file.

The -o yaml flag specifies that the full object configuration is printed. Use kubectl get -h to see a list of options.

The create, replace, and delete commands work well when each object's configuration is fully defined and recorded in its configuration file. However when a live object is updated, and the updates are not merged into its configuration file, the updates will be lost the next time a replace is executed. This can happen if a controller, such as a HorizontalPodAutoscaler, makes updates directly 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl delete <type> <name>
kubectl delete <type> -l <label>
```

Example 2 (shell):
```shell
kubectl create -f <url> --edit
```

Example 3 (shell):
```shell
kubectl get <kind>/<name> -o yaml > <kind>_<name>.yaml
```

Example 4 (shell):
```shell
kubectl replace -f <kind>_<name>.yaml
```

---
