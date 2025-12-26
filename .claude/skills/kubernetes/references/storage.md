# Kubernetes - Storage

**Pages:** 11

---

## Example: Deploying WordPress and MySQL with Persistent Volumes

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/#visit-your-new-wordpress-blog

**Contents:**
- Example: Deploying WordPress and MySQL with Persistent Volumes
    - Warning:
    - Note:
- Objectives
- Before you begin
- Create PersistentVolumeClaims and PersistentVolumes
    - Warning:
    - Note:
    - Note:
- Create a kustomization.yaml

This tutorial shows you how to deploy a WordPress site and a MySQL database using Minikube. Both applications use PersistentVolumes and PersistentVolumeClaims to store data.

A PersistentVolume (PV) is a piece of storage in the cluster that has been manually provisioned by an administrator, or dynamically provisioned by Kubernetes using a StorageClass. A PersistentVolumeClaim (PVC) is a request for storage by a user that can be fulfilled by a PV. PersistentVolumes and PersistentVolumeClaims are independent from Pod lifecycles and preserve data through restarting, rescheduling, and even deleting Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The example shown on this page works with kubectl 1.27 and above.

Download the following configuration files:

mysql-deployment.yaml

wordpress-deployment.yaml

MySQL and Wordpress each require a PersistentVolume to store data. Their PersistentVolumeClaims will be created at the deployment step.

Many cluster environments have a default StorageClass installed. When a StorageClass is not specified in the PersistentVolumeClaim, the cluster's default StorageClass is used instead.

When a PersistentVolumeClaim is created, a PersistentVolume is dynamically provisioned based on the StorageClass configuration.

A Secret is an object that stores a piece of sensitive data like a password or key. Since 1.14, kubectl supports the management of Kubernetes objects using a kustomization file. You can create a Secret by generators in kustomization.yaml.

Add a Secret generator in kustomization.yaml from the following command. You will need to replace YOUR_PASSWORD with the password you want to use.

T

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
cat <<EOF >./kustomization.yaml
secretGenerator:
- name: mysql-pass
  literals:
  - password=YOUR_PASSWORD
EOF
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  ports:
    - port: 3306
  selector:
    app: wordpress
    tier: mysql
  clusterIP: None
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  tem
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: frontend
  type: LoadBalancer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wp-pv-claim
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
 
...
```

Example 4 (shell):
```shell
curl -LO https://k8s.io/examples/application/wordpress/mysql-deployment.yaml
```

---

## Change the Reclaim Policy of a PersistentVolume

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/

**Contents:**
- Change the Reclaim Policy of a PersistentVolume
- Before you begin
- Why change reclaim policy of a PersistentVolume
- Changing the reclaim policy of a PersistentVolume
    - Note:
- What's next
  - References
- Feedback

This page shows how to change the reclaim policy of a Kubernetes PersistentVolume.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

PersistentVolumes can have various reclaim policies, including "Retain", "Recycle", and "Delete". For dynamically provisioned PersistentVolumes, the default reclaim policy is "Delete". This means that a dynamically provisioned volume is automatically deleted when a user deletes the corresponding PersistentVolumeClaim. This automatic behavior might be inappropriate if the volume contains precious data. In that case, it is more appropriate to use the "Retain" policy. With the "Retain" policy, if a user deletes a PersistentVolumeClaim, the corresponding PersistentVolume will not be deleted. Instead, it is moved to the Released phase, where all of its data can be manually recovered.

List the PersistentVolumes in your cluster:

The output is similar to this:

This list also includes the name of the claims that are bound to each volume for easier identification of dynamically provisioned volumes.

Choose one of your PersistentVolumes and change its reclaim policy:

where <your-pv-name> is the name of your chosen PersistentVolume.

On Windows, you must double quote any JSONPath template that contains spaces (not single quote as shown above for bash). This in turn means that you must use a single quote or escaped double quote around any literals in the template. For example:

Verify that your chosen PersistentVolume has the right policy:

The output is similar to this:

In the preceding output, you can see that the volume bound to claim default/claim3 has reclaim policy Retain. It will not be automatically de

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pv
```

Example 2 (none):
```none
NAME                                       CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS    CLAIM             STORAGECLASS     REASON    AGE
pvc-b6efd8da-b7b5-11e6-9d58-0ed433a7dd94   4Gi        RWO           Delete          Bound     default/claim1    manual                     10s
pvc-b95650f8-b7b5-11e6-9d58-0ed433a7dd94   4Gi        RWO           Delete          Bound     default/claim2    manual                     6s
pvc-bb3ca71d-b7b5-11e6-9d58-0ed433a7dd94   4Gi        RWO           Delete          Bound     default/claim3    manual                     3s
```

Example 3 (shell):
```shell
kubectl patch pv <your-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Example 4 (cmd):
```cmd
kubectl patch pv <your-pv-name> -p "{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}"
```

---

## Example: Deploying WordPress and MySQL with Persistent Volumes

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/

**Contents:**
- Example: Deploying WordPress and MySQL with Persistent Volumes
    - Warning:
    - Note:
- Objectives
- Before you begin
- Create PersistentVolumeClaims and PersistentVolumes
    - Warning:
    - Note:
    - Note:
- Create a kustomization.yaml

This tutorial shows you how to deploy a WordPress site and a MySQL database using Minikube. Both applications use PersistentVolumes and PersistentVolumeClaims to store data.

A PersistentVolume (PV) is a piece of storage in the cluster that has been manually provisioned by an administrator, or dynamically provisioned by Kubernetes using a StorageClass. A PersistentVolumeClaim (PVC) is a request for storage by a user that can be fulfilled by a PV. PersistentVolumes and PersistentVolumeClaims are independent from Pod lifecycles and preserve data through restarting, rescheduling, and even deleting Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The example shown on this page works with kubectl 1.27 and above.

Download the following configuration files:

mysql-deployment.yaml

wordpress-deployment.yaml

MySQL and Wordpress each require a PersistentVolume to store data. Their PersistentVolumeClaims will be created at the deployment step.

Many cluster environments have a default StorageClass installed. When a StorageClass is not specified in the PersistentVolumeClaim, the cluster's default StorageClass is used instead.

When a PersistentVolumeClaim is created, a PersistentVolume is dynamically provisioned based on the StorageClass configuration.

A Secret is an object that stores a piece of sensitive data like a password or key. Since 1.14, kubectl supports the management of Kubernetes objects using a kustomization file. You can create a Secret by generators in kustomization.yaml.

Add a Secret generator in kustomization.yaml from the following command. You will need to replace YOUR_PASSWORD with the password you want to use.

T

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
cat <<EOF >./kustomization.yaml
secretGenerator:
- name: mysql-pass
  literals:
  - password=YOUR_PASSWORD
EOF
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  ports:
    - port: 3306
  selector:
    app: wordpress
    tier: mysql
  clusterIP: None
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  tem
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: frontend
  type: LoadBalancer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wp-pv-claim
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
 
...
```

Example 4 (shell):
```shell
curl -LO https://k8s.io/examples/application/wordpress/mysql-deployment.yaml
```

---

## Limit Storage Consumption

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/limit-storage-consumption/

**Contents:**
- Limit Storage Consumption
- Before you begin
- Scenario: Limiting Storage Consumption
- LimitRange to limit requests for storage
- ResourceQuota to limit PVC count and cumulative storage capacity
- Summary
- Feedback

This example demonstrates how to limit the amount of storage consumed in a namespace.

The following resources are used in the demonstration: ResourceQuota, LimitRange, and PersistentVolumeClaim.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The cluster-admin is operating a cluster on behalf of a user population and the admin wants to control how much storage a single namespace can consume in order to control cost.

The admin would like to limit:

Adding a LimitRange to a namespace enforces storage request sizes to a minimum and maximum. Storage is requested via PersistentVolumeClaim. The admission controller that enforces limit ranges will reject any PVC that is above or below the values set by the admin.

In this example, a PVC requesting 10Gi of storage would be rejected because it exceeds the 2Gi max.

Minimum storage requests are used when the underlying storage provider requires certain minimums. For example, AWS EBS volumes have a 1Gi minimum requirement.

Admins can limit the number of PVCs in a namespace as well as the cumulative capacity of those PVCs. New PVCs that exceed either maximum value will be rejected.

In this example, a 6th PVC in the namespace would be rejected because it exceeds the maximum count of 5. Alternatively, a 5Gi maximum quota when combined with the 2Gi max limit above, cannot have 3 PVCs where each has 2Gi. That would be 6Gi requested for a namespace capped at 5Gi.

A limit range can put a ceiling on how much storage is requested while a resource quota can effectively cap the storage consumed by a namespace through claim counts and cumulative storage capacity. The allows a cluster-admin to plan their cluster's storage budget without risk of any one project going over their allotment.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: storagelimits
spec:
  limits:
  - type: PersistentVolumeClaim
    max:
      storage: 2Gi
    min:
      storage: 1Gi
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storagequota
spec:
  hard:
    persistentvolumeclaims: "5"
    requests.storage: "5Gi"
```

---

## Migrate Kubernetes Objects Using Storage Version Migration

**URL:** https://kubernetes.io/docs/tasks/manage-kubernetes-objects/storage-version-migration/

**Contents:**
- Migrate Kubernetes Objects Using Storage Version Migration
- Before you begin
- Re-encrypt Kubernetes secrets using storage version migration
- Update the preferred storage schema of a CRD
- Feedback

Kubernetes relies on API data being actively re-written, to support some maintenance activities related to at rest storage. Two prominent examples are the versioned schema of stored resources (that is, the preferred storage schema changing from v1 to v2 for a given resource) and encryption at rest (that is, rewriting stale data based on a change in how the data should be encrypted).

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.30.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Ensure that your cluster has the StorageVersionMigrator and InformerResourceVersion feature gates enabled. You will need control plane administrator access to make that change.

Enable storage version migration REST api by setting runtime config storagemigration.k8s.io/v1alpha1 to true for the API server. For more information on how to do that, read enable or disable a Kubernetes API.

To begin with, configure KMS provider to encrypt data at rest in etcd using following encryption configuration.

Make sure to enable automatic reload of encryption configuration file by setting --encryption-provider-config-automatic-reload to true.

Create a Secret using kubectl.

Verify the serialized data for that Secret object is prefixed with k8s:enc:aescbc:v1:key1.

Update the encryption configuration file as follows to rotate the encryption key.

To ensure that previously created secret my-secret is re-encrypted with new key key2, you will use Storage Version Migration.

Create a StorageVersionMigration manifest named migrate-secret.yaml as follows:

Create the object using kubectl as follows:

Monitor migration of Secrets by checking the .status of the Sto

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: c2VjcmV0IGlzIHNlY3VyZQ==
```

Example 2 (shell):
```shell
kubectl create secret generic my-secret --from-literal=key1=supersecret
```

Example 3 (yaml):
```yaml
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key2
        secret: c2VjcmV0IGlzIHNlY3VyZSwgaXMgaXQ/
  - aescbc:
      keys:
      - name: key1
        secret: c2VjcmV0IGlzIHNlY3VyZQ==
```

Example 4 (yaml):
```yaml
kind: StorageVersionMigration
apiVersion: storagemigration.k8s.io/v1alpha1
metadata:
  name: secrets-migration
spec:
  resource:
    group: ""
    version: v1
    resource: secrets
```

---

## Configure a Pod to Use a Projected Volume for Storage

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-projected-volume-storage/

**Contents:**
- Configure a Pod to Use a Projected Volume for Storage
    - Note:
- Before you begin
- Configure a projected volume for a pod
- Clean up
- What's next
- Feedback

This page shows how to use a projected Volume to mount several existing volume sources into the same directory. Currently, secret, configMap, downwardAPI, and serviceAccountToken volumes can be projected.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise, you create username and password Secrets from local files. You then create a Pod that runs one container, using a projected Volume to mount the Secrets into the same shared directory.

Here is the configuration file for the Pod:

Verify that the Pod's container is running, and then watch for changes to the Pod:

The output looks like this:

In another terminal, get a shell to the running container:

In your shell, verify that the projected-volume directory contains your projected sources:

Delete the Pod and the Secrets:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-projected-volume
spec:
  containers:
  - name: test-projected-volume
    image: busybox:1.28
    args:
    - sleep
    - "86400"
    volumeMounts:
    - name: all-in-one
      mountPath: "/projected-volume"
      readOnly: true
  volumes:
  - name: all-in-one
    projected:
      sources:
      - secret:
          name: user
      - secret:
          name: pass
```

Example 2 (shell):
```shell
# Create files containing the username and password:
echo -n "admin" > ./username.txt
echo -n "1f2d1e2e67df" > ./password.txt

# Package these files into secrets:
kubectl create secret generic user --from-file=./username.txt
kubectl create secret generic pass --from-file=./password.txt
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/storage/projected.yaml
```

Example 4 (shell):
```shell
kubectl get --watch pod test-projected-volume
```

---

## Configure a Pod to Use a PersistentVolume for Storage

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/

**Contents:**
- Configure a Pod to Use a PersistentVolume for Storage
- Before you begin
- Create an index.html file on your Node
    - Note:
- Create a PersistentVolume
    - Note:
- Create a PersistentVolumeClaim
- Create a Pod
- Clean up
- Mounting the same PersistentVolume in two places

This page shows you how to configure a Pod to use a PersistentVolumeClaim for storage. Here is a summary of the process:

You, as cluster administrator, create a PersistentVolume backed by physical storage. You do not associate the volume with any Pod.

You, now taking the role of a developer / cluster user, create a PersistentVolumeClaim that is automatically bound to a suitable PersistentVolume.

You create a Pod that uses the above PersistentVolumeClaim for storage.

You need to have a Kubernetes cluster that has only one Node, and the kubectl command-line tool must be configured to communicate with your cluster. If you do not already have a single-node cluster, you can create one by using Minikube.

Familiarize yourself with the material in Persistent Volumes.

Open a shell to the single Node in your cluster. How you open a shell depends on how you set up your cluster. For example, if you are using Minikube, you can open a shell to your Node by entering minikube ssh.

In your shell on that Node, create a /mnt/data directory:

In the /mnt/data directory, create an index.html file:

Test that the index.html file exists:

The output should be:

You can now close the shell to your Node.

In this exercise, you create a hostPath PersistentVolume. Kubernetes supports hostPath for development and testing on a single-node cluster. A hostPath PersistentVolume uses a file or directory on the Node to emulate network-attached storage.

In a production cluster, you would not use hostPath. Instead a cluster administrator would provision a network resource like a Google Compute Engine persistent disk, an NFS share, or an Amazon Elastic Block Store volume. Cluster administrators can also use StorageClasses to set up dynamic provisioning.

Here is the configuration file for the hostPath PersistentVolume:

The configuration file specifies that the volume is at /mnt/data on the cluster's Node. The configuration also specifies a size of 10 gibibytes and an access mode of ReadWriteOnce, which means the volume can be mounted as read-write by a single Node. It defines the StorageClass name manual for the PersistentVolume, which will be used to bind PersistentVolumeClaim requests to this PersistentVolume.

Create the PersistentVolume:

View information about the PersistentVolume:

The output shows that the PersistentVolume has a STATUS of Available. This means it has not yet been bound to a PersistentVolumeClaim.

The next step is to create a PersistentVolumeClaim. Pods use Pe

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
# This assumes that your Node uses "sudo" to run commands
# as the superuser
sudo mkdir /mnt/data
```

Example 2 (shell):
```shell
# This again assumes that your Node uses "sudo" to run commands
# as the superuser
sudo sh -c "echo 'Hello from Kubernetes storage' > /mnt/data/index.html"
```

Example 3 (shell):
```shell
cat /mnt/data/index.html
```

Example 4 (unknown):
```unknown
Hello from Kubernetes storage
```

---

## Use an Image Volume With a Pod

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/

**Contents:**
- Use an Image Volume With a Pod
- Before you begin
- Run a Pod that uses an image volume
- Use subPath (or subPathExpr)
- Further reading
- Feedback

This page shows how to configure a pod using image volumes. This allows you to mount content from OCI registries inside containers.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.31.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

An image volume for a pod is enabled by setting the volumes.[*].image field of .spec to a valid reference and consuming it in the volumeMounts of the container. For example:

Create the pod on your cluster:

Attach to the container:

Check the content of a file in the volume:

The output is similar to:

You can also check another file in a different path:

The output is similar to:

It is possible to utilize subPath or subPathExpr from Kubernetes v1.33 when using the image volume feature.

Create the pod on your cluster:

Attach to the container:

Check the content of the file from the dir sub path in the volume:

The output is similar to:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: image-volume
spec:
  containers:
  - name: shell
    command: ["sleep", "infinity"]
    image: debian
    volumeMounts:
    - name: volume
      mountPath: /volume
  volumes:
  - name: volume
    image:
      reference: quay.io/crio/artifact:v2
      pullPolicy: IfNotPresent
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/image-volumes.yaml
```

Example 3 (shell):
```shell
kubectl attach -it image-volume bash
```

Example 4 (shell):
```shell
cat /volume/dir/file
```

---

## Configure a Pod to Use a Volume for Storage

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/

**Contents:**
- Configure a Pod to Use a Volume for Storage
- Before you begin
- Configure a volume for a Pod
- What's next
- Feedback

This page shows how to configure a Pod to use a Volume for storage.

A Container's file system lives only as long as the Container does. So when a Container terminates and restarts, filesystem changes are lost. For more consistent storage that is independent of the Container, you can use a Volume. This is especially important for stateful applications, such as key-value stores (such as Redis) and databases.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In this exercise, you create a Pod that runs one Container. This Pod has a Volume of type emptyDir that lasts for the life of the Pod, even if the Container terminates and restarts. Here is the configuration file for the Pod:

Verify that the Pod's Container is running, and then watch for changes to the Pod:

The output looks like this:

In another terminal, get a shell to the running Container:

In your shell, go to /data/redis, and then create a file:

In your shell, list the running processes:

The output is similar to this:

In your shell, kill the Redis process:

where <pid> is the Redis process ID (PID).

In your original terminal, watch for changes to the Redis Pod. Eventually, you will see something like this:

At this point, the Container has terminated and restarted. This is because the Redis Pod has a restartPolicy of Always.

Get a shell into the restarted Container:

In your shell, go to /data/redis, and verify that test-file is still there.

Delete the Pod that you created for this exercise:

In addition to the local disk storage provided by emptyDir, Kubernetes supports many different network-attached storage solutions, including PD on GCE and EBS on EC2, which are 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: redis
spec:
  containers:
  - name: redis
    image: redis
    volumeMounts:
    - name: redis-storage
      mountPath: /data/redis
  volumes:
  - name: redis-storage
    emptyDir: {}
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/storage/redis.yaml
```

Example 3 (shell):
```shell
kubectl get pod redis --watch
```

Example 4 (console):
```console
NAME      READY     STATUS    RESTARTS   AGE
redis     1/1       Running   0          13s
```

---

## Change the Access Mode of a PersistentVolume to ReadWriteOncePod

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/change-pv-access-mode-readwriteoncepod/

**Contents:**
- Change the Access Mode of a PersistentVolume to ReadWriteOncePod
- Before you begin
    - Note:
    - Note:
- Why should I use ReadWriteOncePod?
- Migrating existing PersistentVolumes
    - Note:
    - Note:
- What's next
- Feedback

This page shows how to change the access mode on an existing PersistentVolume to use ReadWriteOncePod.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.22.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The ReadWriteOncePod access mode is only supported for CSI volumes. To use this volume access mode you will need to update the following CSI sidecars to these versions or greater:

Prior to Kubernetes v1.22, the ReadWriteOnce access mode was commonly used to restrict PersistentVolume access for workloads that required single-writer access to storage. However, this access mode had a limitation: it restricted volume access to a single node, allowing multiple pods on the same node to read from and write to the same volume simultaneously. This could pose a risk for applications that demand strict single-writer access for data safety.

If ensuring single-writer access is critical for your workloads, consider migrating your volumes to ReadWriteOncePod.

If you have existing PersistentVolumes, they can be migrated to use ReadWriteOncePod. Only migrations from ReadWriteOnce to ReadWriteOncePod are supported.

In this example, there is already a ReadWriteOnce "cat-pictures-pvc" PersistentVolumeClaim that is bound to a "cat-pictures-pv" PersistentVolume, and a "cat-pictures-writer" Deployment that uses this PersistentVolumeClaim.

If your storage plugin supports Dynamic provisioning, the "cat-picutres-pv" will be created for you, but its name may differ. To get your PersistentVolume's name run:

And you can view the PVC before you make changes. Either view the manifest locally, or run kubectl get pvc <name-of-pvc> -o yaml. The outp

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pvc cat-pictures-pvc -o jsonpath='{.spec.volumeName}'
```

Example 2 (yaml):
```yaml
# cat-pictures-pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: cat-pictures-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Example 3 (yaml):
```yaml
# cat-pictures-writer-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cat-pictures-writer
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cat-pictures-writer
  template:
    metadata:
      labels:
        app: cat-pictures-writer
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: cat-pictures
          mountPath: /mnt
      volumes:
      - name: cat-pictures
        persistentVolumeClaim:
          claimName: cat-pictures-pvc
          readOnly: false
```

Example 4 (shell):
```shell
kubectl patch pv cat-pictures-pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

---

## Change the default StorageClass

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/

**Contents:**
- Change the default StorageClass
- Before you begin
- Why change the default storage class?
- Changing the default StorageClass
- What's next
- Feedback

This page shows how to change the default Storage Class that is used to provision volumes for PersistentVolumeClaims that have no special requirements.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Depending on the installation method, your Kubernetes cluster may be deployed with an existing StorageClass that is marked as default. This default StorageClass is then used to dynamically provision storage for PersistentVolumeClaims that do not require any specific storage class. See PersistentVolumeClaim documentation for details.

The pre-installed default StorageClass may not fit well with your expected workload; for example, it might provision storage that is too expensive. If this is the case, you can either change the default StorageClass or disable it completely to avoid dynamic provisioning of storage.

Deleting the default StorageClass may not work, as it may be re-created automatically by the addon manager running in your cluster. Please consult the docs for your installation for details about addon manager and how to disable individual addons.

List the StorageClasses in your cluster:

The output is similar to this:

The default StorageClass is marked by (default).

Mark the default StorageClass as non-default:

The default StorageClass has an annotation storageclass.kubernetes.io/is-default-class set to true. Any other value or absence of the annotation is interpreted as false.

To mark a StorageClass as non-default, you need to change its value to false:

where standard is the name of your chosen StorageClass.

Mark a StorageClass as default:

Similar to the previous step, you need to add/set the annotation storageclass.

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
kubectl get storageclass
```

Example 2 (bash):
```bash
NAME                 PROVISIONER               AGE
standard (default)   kubernetes.io/gce-pd      1d
gold                 kubernetes.io/gce-pd      1d
```

Example 3 (bash):
```bash
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

Example 4 (bash):
```bash
kubectl patch storageclass gold -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---
