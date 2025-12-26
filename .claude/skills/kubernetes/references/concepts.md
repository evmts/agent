# Kubernetes - Concepts

**Pages:** 271

---

## DNS for Services and Pods

**URL:** https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/

**Contents:**
- DNS for Services and Pods
  - Namespaces of Services
  - DNS Records
- Services
  - A/AAAA records
  - SRV records
- Pods
  - A/AAAA records
  - Pod's hostname and subdomain fields
    - Note:

Kubernetes creates DNS records for Services and Pods. You can contact Services with consistent DNS names instead of IP addresses.

Kubernetes publishes information about Pods and Services which is used to program DNS. kubelet configures Pods' DNS so that running containers can look up Services by name rather than IP.

Services defined in the cluster are assigned DNS names. By default, a client Pod's DNS search list includes the Pod's own namespace and the cluster's default domain.

A DNS query may return different results based on the namespace of the Pod making it. DNS queries that don't specify a namespace are limited to the Pod's namespace. Access Services in other namespaces by specifying it in the DNS query.

For example, consider a Pod in a test namespace. A data Service is in the prod namespace.

A query for data returns no results, because it uses the Pod's test namespace.

A query for data.prod returns the intended result, because it specifies the namespace.

DNS queries may be expanded using the Pod's /etc/resolv.conf. kubelet configures this file for each Pod. For example, a query for just data may be expanded to data.test.svc.cluster.local. The values of the search option are used to expand queries. To learn more about DNS queries, see the resolv.conf manual page.

In summary, a Pod in the test namespace can successfully resolve either data.prod or data.prod.svc.cluster.local.

What objects get DNS records?

The following sections detail the supported DNS record types and layout that is supported. Any other layout or names or queries that happen to work are considered implementation details and are subject to change without warning. For more up-to-date specification, see Kubernetes DNS-Based Service Discovery.

"Normal" (not headless) Services are assigned DNS A and/or AAAA records, depending on the IP family or families of the Service, with a name of the form my-svc.my-namespace.svc.cluster-domain.example. This resolves to the cluster IP of the Service.

Headless Services (without a cluster IP) are also assigned DNS A and/or AAAA records, with a name of the form my-svc.my-namespace.svc.cluster-domain.example. Unlike normal Services, this resolves to the set of IPs of all of the Pods selected by the Service. Clients are expected to consume the set or else use standard round-robin selection from the set.

SRV Records are created for named ports that are part of normal or headless services.

Kube-DNS versions, prior to the implementation of the D

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
nameserver 10.32.0.10
search <namespace>.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

Example 2 (unknown):
```unknown
<pod-IPv4-address>.<namespace>.pod.<cluster-domain>
```

Example 3 (unknown):
```unknown
172-17-0-3.default.pod.cluster.local
```

Example 4 (unknown):
```unknown
<pod-ipv4-address>.<service-name>.<my-namespace>.svc.<cluster-domain.example>
```

---

## Services, Load Balancing, and Networking

**URL:** https://kubernetes.io/docs/concepts/services-networking/

**Contents:**
- Services, Load Balancing, and Networking
- The Kubernetes network model
- What's next
      - Service
      - Ingress
      - Ingress Controllers
      - Gateway API
      - EndpointSlices
      - Network Policies
      - DNS for Services and Pods

The Kubernetes network model is built out of several pieces:

Each pod in a cluster gets its own unique cluster-wide IP address.

The pod network (also called a cluster network) handles communication between pods. It ensures that (barring intentional network segmentation):

All pods can communicate with all other pods, whether they are on the same node or on different nodes. Pods can communicate with each other directly, without the use of proxies or address translation (NAT).

On Windows, this rule does not apply to host-network pods.

Agents on a node (such as system daemons, or kubelet) can communicate with all pods on that node.

The Service API lets you provide a stable (long lived) IP address or hostname for a service implemented by one or more backend pods, where the individual pods making up the service can change over time.

Kubernetes automatically manages EndpointSlice objects to provide information about the pods currently backing a Service.

A service proxy implementation monitors the set of Service and EndpointSlice objects, and programs the data plane to route service traffic to its backends, by using operating system or cloud provider APIs to intercept or rewrite packets.

The Gateway API (or its predecessor, Ingress) allows you to make Services accessible to clients that are outside the cluster.

NetworkPolicy is a built-in Kubernetes API that allows you to control traffic between pods, or between pods and the outside world.

In older container systems, there was no automatic connectivity between containers on different hosts, and so it was often necessary to explicitly create links between containers, or to map container ports to host ports to make them reachable by containers on other hosts. This is not needed in Kubernetes; Kubernetes's model is that pods can be treated much like VMs or physical hosts from the perspectives of port allocation, naming, service discovery, load balancing, application configuration, and migration.

Only a few parts of this model are implemented by Kubernetes itself. For the other parts, Kubernetes defines the APIs, but the corresponding functionality is provided by external components, some of which are optional:

Pod network namespace setup is handled by system-level software implementing the Container Runtime Interface.

The pod network itself is managed by a pod network implementation. On Linux, most container runtimes use the Container Networking Interface (CNI) to interact with the pod network implement

*[Content truncated]*

---

## Volume Snapshots

**URL:** https://kubernetes.io/docs/concepts/storage/volume-snapshots/#convert-volume-mode

**Contents:**
- Volume Snapshots
- Introduction
- Lifecycle of a volume snapshot and volume snapshot content
  - Provisioning Volume Snapshot
    - Pre-provisioned
    - Dynamic
  - Binding
  - Persistent Volume Claim as Snapshot Source Protection
  - Delete
- VolumeSnapshots

In Kubernetes, a VolumeSnapshot represents a snapshot of a volume on a storage system. This document assumes that you are already familiar with Kubernetes persistent volumes.

Similar to how API resources PersistentVolume and PersistentVolumeClaim are used to provision volumes for users and administrators, VolumeSnapshotContent and VolumeSnapshot API resources are provided to create volume snapshots for users and administrators.

A VolumeSnapshotContent is a snapshot taken from a volume in the cluster that has been provisioned by an administrator. It is a resource in the cluster just like a PersistentVolume is a cluster resource.

A VolumeSnapshot is a request for snapshot of a volume by a user. It is similar to a PersistentVolumeClaim.

VolumeSnapshotClass allows you to specify different attributes belonging to a VolumeSnapshot. These attributes may differ among snapshots taken from the same volume on the storage system and therefore cannot be expressed by using the same StorageClass of a PersistentVolumeClaim.

Volume snapshots provide Kubernetes users with a standardized way to copy a volume's contents at a particular point in time without creating an entirely new volume. This functionality enables, for example, database administrators to backup databases before performing edit or delete modifications.

Users need to be aware of the following when using this feature:

For advanced use cases, such as creating group snapshots of multiple volumes, see the external CSI Volume Group Snapshot documentation.

VolumeSnapshotContents are resources in the cluster. VolumeSnapshots are requests for those resources. The interaction between VolumeSnapshotContents and VolumeSnapshots follow this lifecycle:

There are two ways snapshots may be provisioned: pre-provisioned or dynamically provisioned.

A cluster administrator creates a number of VolumeSnapshotContents. They carry the details of the real volume snapshot on the storage system which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

Instead of using a pre-existing snapshot, you can request that a snapshot to be dynamically taken from a PersistentVolumeClaim. The VolumeSnapshotClass specifies storage provider-specific parameters to use when taking a snapshot.

The snapshot controller handles the binding of a VolumeSnapshot object with an appropriate VolumeSnapshotContent object, in both pre-provisioned and dynamically provisioned scenarios. The binding

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: new-snapshot-test
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: pvc-test
```

Example 2 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  source:
    volumeSnapshotContentName: test-content
```

Example 3 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: snapcontent-72d9a349-aacd-42d2-a240-d775650d2455
spec:
  deletionPolicy: Delete
  driver: hostpath.csi.k8s.io
  source:
    volumeHandle: ee0cfb94-f8d4-11e9-b2d8-0242ac110002
  sourceVolumeMode: Filesystem
  volumeSnapshotClassName: csi-hostpath-snapclass
  volumeSnapshotRef:
    name: new-snapshot-test
    namespace: default
    uid: 72d9a349-aacd-42d2-a240-d775650d2455
```

Example 4 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: new-snapshot-content-test
spec:
  deletionPolicy: Delete
  driver: hostpath.csi.k8s.io
  source:
    snapshotHandle: 7bdd0de3-aaeb-11e8-9aae-0242ac110002
  sourceVolumeMode: Filesystem
  volumeSnapshotRef:
    name: new-snapshot-test
    namespace: default
```

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names/

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Node-pressure Eviction

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

**Contents:**
- Node-pressure Eviction
- Self healing behavior
  - Self healing for static pods
- Eviction signals and thresholds
  - Eviction signals
    - Memory signals
    - Filesystem signals
    - Note:
  - Deprecated kubelet garbage collection features
  - Eviction thresholds

Node-pressure eviction is the process by which the kubelet proactively terminates pods to reclaim resource on nodes.

The kubelet monitors resources like memory, disk space, and filesystem inodes on your cluster's nodes. When one or more of these resources reach specific consumption levels, the kubelet can proactively fail one or more pods on the node to reclaim resources and prevent starvation.

During a node-pressure eviction, the kubelet sets the phase for the selected pods to Failed, and terminates the Pod.

Node-pressure eviction is not the same as API-initiated eviction.

The kubelet does not respect your configured PodDisruptionBudget or the pod's terminationGracePeriodSeconds. If you use soft eviction thresholds, the kubelet respects your configured eviction-max-pod-grace-period. If you use hard eviction thresholds, the kubelet uses a 0s grace period (immediate shutdown) for termination.

The kubelet attempts to reclaim node-level resources before it terminates end-user pods. For example, it removes unused container images when disk resources are starved.

If the pods are managed by a workload management object (such as StatefulSet or Deployment) that replaces failed pods, the control plane (kube-controller-manager) creates new pods in place of the evicted pods.

If you are running a static pod on a node that is under resource pressure, the kubelet may evict that static Pod. The kubelet then tries to create a replacement, because static Pods always represent an intent to run a Pod on that node.

The kubelet takes the priority of the static pod into account when creating a replacement. If the static pod manifest specifies a low priority, and there are higher-priority Pods defined within the cluster's control plane, and the node is under resource pressure, the kubelet may not be able to make room for that static pod. The kubelet continues to attempt to run all static pods even when there is resource pressure on a node.

The kubelet uses various parameters to make eviction decisions, like the following:

Eviction signals are the current state of a particular resource at a specific point in time. The kubelet uses eviction signals to make eviction decisions by comparing the signals to eviction thresholds, which are the minimum amount of the resource that should be available on the node.

The kubelet uses the following eviction signals:

In this table, the Description column shows how kubelet gets the value of the signal. Each signal supports either a pe

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
evictionHard:
  memory.available: "500Mi"
  nodefs.available: "1Gi"
  imagefs.available: "100Gi"
evictionMinimumReclaim:
  memory.available: "0Mi"
  nodefs.available: "500Mi"
  imagefs.available: "2Gi"
```

Example 2 (none):
```none
--eviction-hard=memory.available<500Mi
--system-reserved=memory=1.5Gi
```

---

## Labels and Selectors

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#syntax-and-character-set

**Contents:**
- Labels and Selectors
- Motivation
- Syntax and character set
- Label selectors
    - Note:
    - Caution:
  - Equality-based requirement
  - Set-based requirement
- API
  - LIST and WATCH filtering

Labels are key/value pairs that are attached to objects such as Pods. Labels are intended to be used to specify identifying attributes of objects that are meaningful and relevant to users, but do not directly imply semantics to the core system. Labels can be used to organize and to select subsets of objects. Labels can be attached to objects at creation time and subsequently added and modified at any time. Each object can have a set of key/value labels defined. Each Key must be unique for a given object.

Labels allow for efficient queries and watches and are ideal for use in UIs and CLIs. Non-identifying information should be recorded using annotations.

Labels enable users to map their own organizational structures onto system objects in a loosely coupled fashion, without requiring clients to store these mappings.

Service deployments and batch processing pipelines are often multi-dimensional entities (e.g., multiple partitions or deployments, multiple release tracks, multiple tiers, multiple micro-services per tier). Management often requires cross-cutting operations, which breaks encapsulation of strictly hierarchical representations, especially rigid hierarchies determined by the infrastructure rather than by users.

These are examples of commonly used labels; you are free to develop your own conventions. Keep in mind that label Key must be unique for a given object.

Labels are key/value pairs. Valid label keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, followed by a slash (/).

If the prefix is omitted, the label Key is presumed to be private to the user. Automated system components (e.g. kube-scheduler, kube-controller-manager, kube-apiserver, kubectl, or other third-party automation) which add labels to end-user objects must specify a prefix.

The kubernetes.io/ and k8s.io/ prefixes are reserved for Kubernetes core components.

For example, here's a manifest for a Pod that has two labels environment: production and app: nginx:

Unlike names and UIDs, labels do not provide uniqueness. In general, we expect many objects to carry the same label(s).

Via a label sel

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "labels": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: label-demo
  labels:
    environment: production
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 3 (unknown):
```unknown
environment = production
tier != frontend
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  containers:
    - name: cuda-test
      image: "registry.k8s.io/cuda-vector-add:v0.1"
      resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia-tesla-p100
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#kube-scheduler

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Hardening Guide - Authentication Mechanisms

**URL:** https://kubernetes.io/docs/concepts/security/hardening-guide/authentication-mechanisms/

**Contents:**
- Hardening Guide - Authentication Mechanisms
- X.509 client certificate authentication
- Static token file
- Bootstrap tokens
- ServiceAccount secret tokens
- TokenRequest API tokens
- OpenID Connect token authentication
- Webhook token authentication
- Authenticating proxy
- What's next

Selecting the appropriate authentication mechanism(s) is a crucial aspect of securing your cluster. Kubernetes provides several built-in mechanisms, each with its own strengths and weaknesses that should be carefully considered when choosing the best authentication mechanism for your cluster.

In general, it is recommended to enable as few authentication mechanisms as possible to simplify user management and prevent cases where users retain access to a cluster that is no longer required.

It is important to note that Kubernetes does not have an in-built user database within the cluster. Instead, it takes user information from the configured authentication system and uses that to make authorization decisions. Therefore, to audit user access, you need to review credentials from every configured authentication source.

For production clusters with multiple users directly accessing the Kubernetes API, it is recommended to use external authentication sources such as OIDC. The internal authentication mechanisms, such as client certificates and service account tokens, described below, are not suitable for this use case.

Kubernetes leverages X.509 client certificate authentication for system components, such as when the kubelet authenticates to the API Server. While this mechanism can also be used for user authentication, it might not be suitable for production use due to several restrictions:

Although Kubernetes allows you to load credentials from a static token file located on the control plane node disks, this approach is not recommended for production servers due to several reasons:

Bootstrap tokens are used for joining nodes to clusters and are not recommended for user authentication due to several reasons:

Service account secrets are available as an option to allow workloads running in the cluster to authenticate to the API server. In Kubernetes < 1.23, these were the default option, however, they are being replaced with TokenRequest API tokens. While these secrets could be used for user authentication, they are generally unsuitable for a number of reasons:

The TokenRequest API is a useful tool for generating short-lived credentials for service authentication to the API server or third-party systems. However, it is not generally recommended for user authentication as there is no revocation method available, and distributing credentials to users in a secure manner can be challenging.

When using TokenRequest tokens for service authentication, it is recom

*[Content truncated]*

---

## Windows in Kubernetes

**URL:** https://kubernetes.io/docs/concepts/windows/

**Contents:**
- Windows in Kubernetes
- Feedback

Kubernetes supports worker nodes running either Linux or Microsoft Windows.

The CNCF and its parent the Linux Foundation take a vendor-neutral approach towards compatibility. It is possible to join your Windows server as a worker node to a Kubernetes cluster.

You can install and set up kubectl on Windows no matter what operating system you use within your cluster.

If you are using Windows nodes, you can read:

or, for an overview, read:

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Pods

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/

**Contents:**
- Pods
- What is a Pod?
    - Note:
- Using Pods
  - Workload resources for managing pods
- Working with Pods
    - Note:
  - Pod OS
  - Pods and controllers
  - Pod templates

Pods are the smallest deployable units of computing that you can create and manage in Kubernetes.

A Pod (as in a pod of whales or pea pod) is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers. A Pod's contents are always co-located and co-scheduled, and run in a shared context. A Pod models an application-specific "logical host": it contains one or more application containers which are relatively tightly coupled. In non-cloud contexts, applications executed on the same physical or virtual machine are analogous to cloud applications executed on the same logical host.

As well as application containers, a Pod can contain init containers that run during Pod startup. You can also inject ephemeral containers for debugging a running Pod.

The shared context of a Pod is a set of Linux namespaces, cgroups, and potentially other facets of isolation - the same things that isolate a container. Within a Pod's context, the individual applications may have further sub-isolations applied.

A Pod is similar to a set of containers with shared namespaces and shared filesystem volumes.

Pods in a Kubernetes cluster are used in two main ways:

Pods that run a single container. The "one-container-per-Pod" model is the most common Kubernetes use case; in this case, you can think of a Pod as a wrapper around a single container; Kubernetes manages Pods rather than managing the containers directly.

Pods that run multiple containers that need to work together. A Pod can encapsulate an application composed of multiple co-located containers that are tightly coupled and need to share resources. These co-located containers form a single cohesive unit.

Grouping multiple co-located and co-managed containers in a single Pod is a relatively advanced use case. You should use this pattern only in specific instances in which your containers are tightly coupled.

You don't need to run multiple containers to provide replication (for resilience or capacity); if you need multiple replicas, see Workload management.

The following is an example of a Pod which consists of a container running the image nginx:1.14.2.

To create the Pod shown above, run the following command:

Pods are generally not created directly and are created using workload resources. See Working with Pods for more information on how Pods are used with workload resources.

Usually you don't need to create Pods directly, even singleton Pods. Instead, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml
```

Example 3 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    # This is the pod template
    spec:
      containers:
      - name: hello
        image: busybox:1.28
        command: ['sh', '-c', 'echo "Hello, Kubernetes!" && sleep 3600']
      restartPolicy: OnFailure
    # The pod template ends here
```

---

## Field Selectors

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/

**Contents:**
- Field Selectors
    - Note:
- Supported fields
  - List of supported fields
  - Custom resources fields
- Supported operators
    - Note:
- Chained selectors
- Multiple resource types
- Feedback

Field selectors let you select Kubernetes objects based on the value of one or more resource fields. Here are some examples of field selector queries:

This kubectl command selects all Pods for which the value of the status.phase field is Running:

Supported field selectors vary by Kubernetes resource type. All resource types support the metadata.name and metadata.namespace fields. Using unsupported field selectors produces an error. For example:

All custom resource types support the metadata.name and metadata.namespace fields.

Additionally, the spec.versions[*].selectableFields field of a CustomResourceDefinition declares which other fields in a custom resource may be used in field selectors. See selectable fields for custom resources for more information about how to use field selectors with CustomResourceDefinitions.

You can use the =, ==, and != operators with field selectors (= and == mean the same thing). This kubectl command, for example, selects all Kubernetes Services that aren't in the default namespace:

As with label and other selectors, field selectors can be chained together as a comma-separated list. This kubectl command selects all Pods for which the status.phase does not equal Running and the spec.restartPolicy field equals Always:

You can use field selectors across multiple resource types. This kubectl command selects all Statefulsets and Services that are not in the default namespace:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get pods --field-selector status.phase=Running
```

Example 2 (shell):
```shell
kubectl get ingress --field-selector foo.bar=baz
```

Example 3 (unknown):
```unknown
Error from server (BadRequest): Unable to find "ingresses" that match label selector "", field selector "foo.bar=baz": "foo.bar" is not a known field selector: only "metadata.name", "metadata.namespace"
```

Example 4 (shell):
```shell
kubectl get services  --all-namespaces --field-selector metadata.namespace!=default
```

---

## Scheduling Framework

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/#extension-points

**Contents:**
- Scheduling Framework
- Framework workflow
  - Scheduling cycle & binding cycle
- Interfaces
    - Scheduling framework extension points
  - PreEnqueue
  - EnqueueExtension
  - QueueingHint
  - QueueSort
  - PreFilter

The scheduling framework is a pluggable architecture for the Kubernetes scheduler. It consists of a set of "plugin" APIs that are compiled directly into the scheduler. These APIs allow most scheduling features to be implemented as plugins, while keeping the scheduling "core" lightweight and maintainable. Refer to the design proposal of the scheduling framework for more technical information on the design of the framework.

The Scheduling Framework defines a few extension points. Scheduler plugins register to be invoked at one or more extension points. Some of these plugins can change the scheduling decisions and some are informational only.

Each attempt to schedule one Pod is split into two phases, the scheduling cycle and the binding cycle.

The scheduling cycle selects a node for the Pod, and the binding cycle applies that decision to the cluster. Together, a scheduling cycle and binding cycle are referred to as a "scheduling context".

Scheduling cycles are run serially, while binding cycles may run concurrently.

A scheduling or binding cycle can be aborted if the Pod is determined to be unschedulable or if there is an internal error. The Pod will be returned to the queue and retried.

The following picture shows the scheduling context of a Pod and the interfaces that the scheduling framework exposes.

One plugin may implement multiple interfaces to perform more complex or stateful tasks.

Some interfaces match the scheduler extension points which can be configured through Scheduler Configuration.

These plugins are called prior to adding Pods to the internal active queue, where Pods are marked as ready for scheduling.

Only when all PreEnqueue plugins return Success, the Pod is allowed to enter the active queue. Otherwise, it's placed in the internal unschedulable Pods list, and doesn't get an Unschedulable condition.

For more details about how internal scheduler queues work, read Scheduling queue in kube-scheduler.

EnqueueExtension is the interface where the plugin can control whether to retry scheduling of Pods rejected by this plugin, based on changes in the cluster. Plugins that implement PreEnqueue, PreFilter, Filter, Reserve or Permit should implement this interface.

QueueingHint is a callback function for deciding whether a Pod can be requeued to the active queue or backoff queue. It's executed every time a certain kind of event or change happens in the cluster. When the QueueingHint finds that the event might make the Pod schedulable, the 

*[Content truncated]*

**Examples:**

Example 1 (go):
```go
func ScoreNode(_ *v1.pod, n *v1.Node) (int, error) {
    return getBlinkingLightCount(n)
}
```

Example 2 (go):
```go
func NormalizeScores(scores map[string]int) {
    highest := 0
    for _, score := range scores {
        highest = max(highest, score)
    }
    for node, score := range scores {
        scores[node] = score*NodeScoreMax/highest
    }
}
```

Example 3 (go):
```go
type Plugin interface {
    Name() string
}

type QueueSortPlugin interface {
    Plugin
    Less(*v1.pod, *v1.pod) bool
}

type PreFilterPlugin interface {
    Plugin
    PreFilter(context.Context, *framework.CycleState, *v1.pod) error
}

// ...
```

---

## Role Based Access Control Good Practices

**URL:** https://kubernetes.io/docs/concepts/security/rbac-good-practices/

**Contents:**
- Role Based Access Control Good Practices
- General good practice
  - Least privilege
  - Minimize distribution of privileged tokens
  - Hardening
  - Periodic review
- Kubernetes RBAC - privilege escalation risks
  - Listing secrets
  - Workload creation
  - Persistent volume creation

Kubernetes RBAC is a key security control to ensure that cluster users and workloads have only the access to resources required to execute their roles. It is important to ensure that, when designing permissions for cluster users, the cluster administrator understands the areas where privilege escalation could occur, to reduce the risk of excessive access leading to security incidents.

The good practices laid out here should be read in conjunction with the general RBAC documentation.

Ideally, minimal RBAC rights should be assigned to users and service accounts. Only permissions explicitly required for their operation should be used. While each cluster will be different, some general rules that can be applied are :

Ideally, pods shouldn't be assigned service accounts that have been granted powerful permissions (for example, any of the rights listed under privilege escalation risks). In cases where a workload requires powerful permissions, consider the following practices:

Kubernetes defaults to providing access which may not be required in every cluster. Reviewing the RBAC rights provided by default can provide opportunities for security hardening. In general, changes should not be made to rights provided to system: accounts some options to harden cluster rights exist:

It is vital to periodically review the Kubernetes RBAC settings for redundant entries and possible privilege escalations. If an attacker is able to create a user account with the same name as a deleted user, they can automatically inherit all the rights of the deleted user, especially the rights assigned to that user.

Within Kubernetes RBAC there are a number of privileges which, if granted, can allow a user or a service account to escalate their privileges in the cluster or affect systems outside the cluster.

This section is intended to provide visibility of the areas where cluster operators should take care, to ensure that they do not inadvertently allow for more access to clusters than intended.

It is generally clear that allowing get access on Secrets will allow a user to read their contents. It is also important to note that list and watch access also effectively allow for users to reveal the Secret contents. For example, when a List response is returned (for example, via kubectl get secrets -A -o yaml), the response includes the contents of all Secrets.

Permission to create workloads (either Pods, or workload resources that manage Pods) in a namespace implicitly grants access to

*[Content truncated]*

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/#load-balancer-ip-mode

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#create-eviction-pod-v1-core

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#podstatus-v1-core

---

## Resource Management for Pods and Containers

**URL:** https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

**Contents:**
- Resource Management for Pods and Containers
- Requests and limits
    - Note:
    - Note:
- Resource types
    - Note:
- Resource requests and limits of Pod and container
- Pod-level resource specification
- Resource units in Kubernetes
  - CPU resource units

When you specify a Pod, you can optionally specify how much of each resource a container needs. The most common resources to specify are CPU and memory (RAM); there are others.

When you specify the resource request for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a resource limit for a container, the kubelet enforces those limits so that the running container is not allowed to use more of that resource than the limit you set. The kubelet also reserves at least the request amount of that system resource specifically for that container to use.

If the node where a Pod is running has enough of a resource available, it's possible (and allowed) for a container to use more resource than its request for that resource specifies.

For example, if you set a memory request of 256 MiB for a container, and that container is in a Pod scheduled to a Node with 8GiB of memory and no other Pods, then the container can try to use more RAM.

Limits are a different story. Both cpu and memory limits are applied by the kubelet (and container runtime), and are ultimately enforced by the kernel. On Linux nodes, the Linux kernel enforces limits with cgroups. The behavior of cpu and memory limit enforcement is slightly different.

cpu limits are enforced by CPU throttling. When a container approaches its cpu limit, the kernel will restrict access to the CPU corresponding to the container's limit. Thus, a cpu limit is a hard limit the kernel enforces. Containers may not use more CPU than is specified in their cpu limit.

memory limits are enforced by the kernel with out of memory (OOM) kills. When a container uses more than its memory limit, the kernel may terminate it. However, terminations only happen when the kernel detects memory pressure. Thus, a container that over allocates memory may not be immediately killed. This means memory limits are enforced reactively. A container may use more memory than its memory limit, but if it does, it may get killed.

CPU and memory are each a resource type. A resource type has a base unit. CPU represents compute processing and is specified in units of Kubernetes CPUs. Memory is specified in units of bytes. For Linux workloads, you can specify huge page resources. Huge pages are a Linux-specific feature where the node kernel allocates blocks of memory that are much larger than the default page size.

For example, on a system where the default page size is 4KiB, you coul

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
128974848, 129e6, 129M,  128974848000m, 123Mi
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-resources-demo
  namespace: pod-resources-example
spec:
  resources:
    limits:
      cpu: "1"
      memory: "200Mi"
    requests:
      cpu: "1"
      memory: "100Mi"
  containers:
  - name: pod-resources-demo-ctr-1
    image: nginx
    resources:
      limits:
        cpu: "0.5"
        memory: "100Mi"
      requests:
        cpu: "0.5"
        memory: "50Mi"
  - name: pod-resources-demo-ctr-2
    image: fedora
    command:
    - sleep
    - inf
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  volumes:
    - name: ephemeral
      e
...
```

---

## Device Plugins

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/#device-plugin-and-unhealthy-devices

**Contents:**
- Device Plugins
- Device plugin registration
  - Example
- Device plugin implementation
    - Note:
    - Note:
    - Note:
  - Handling kubelet restarts
  - Device plugin and unhealthy devices
- Device plugin deployment

Kubernetes provides a device plugin framework that you can use to advertise system hardware resources to the Kubelet.

Instead of customizing the code for Kubernetes itself, vendors can implement a device plugin that you deploy either manually or as a DaemonSet. The targeted devices include GPUs, high-performance NICs, FPGAs, InfiniBand adapters, and other similar computing resources that may require vendor specific initialization and setup.

The kubelet exports a Registration gRPC service:

A device plugin can register itself with the kubelet through this gRPC service. During the registration, the device plugin needs to send:

Following a successful registration, the device plugin sends the kubelet the list of devices it manages, and the kubelet is then in charge of advertising those resources to the API server as part of the kubelet node status update. For example, after a device plugin registers hardware-vendor.example/foo with the kubelet and reports two healthy devices on a node, the node status is updated to advertise that the node has 2 "Foo" devices installed and available.

Then, users can request devices as part of a Pod specification (see container). Requesting extended resources is similar to how you manage requests and limits for other resources, with the following differences:

Suppose a Kubernetes cluster is running a device plugin that advertises resource hardware-vendor.example/foo on certain nodes. Here is an example of a pod requesting this resource to run a demo workload:

The general workflow of a device plugin includes the following steps:

Initialization. During this phase, the device plugin performs vendor-specific initialization and setup to make sure the devices are in a ready state.

The plugin starts a gRPC service, with a Unix socket under the host path /var/lib/kubelet/device-plugins/, that implements the following interfaces:

The plugin registers itself with the kubelet through the Unix socket at host path /var/lib/kubelet/device-plugins/kubelet.sock.

After successfully registering itself, the device plugin runs in serving mode, during which it keeps monitoring device health and reports back to the kubelet upon any device state changes. It is also responsible for serving Allocate gRPC requests. During Allocate, the device plugin may do device-specific preparation; for example, GPU cleanup or QRNG initialization. If the operations succeed, the device plugin returns an AllocateResponse that contains container runtime configur

*[Content truncated]*

**Examples:**

Example 1 (gRPC):
```gRPC
service Registration {
	rpc Register(RegisterRequest) returns (Empty) {}
}
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: demo-pod
spec:
  containers:
    - name: demo-container-1
      image: registry.k8s.io/pause:3.8
      resources:
        limits:
          hardware-vendor.example/foo: 2
#
# This Pod needs 2 of the hardware-vendor.example/foo devices
# and can only schedule onto a Node that's able to satisfy
# that need.
#
# If the Node has more than 2 of those devices available, the
# remainder would be available for other Pods to use.
```

Example 3 (gRPC):
```gRPC
service DevicePlugin {
      // GetDevicePluginOptions returns options to be communicated with Device Manager.
      rpc GetDevicePluginOptions(Empty) returns (DevicePluginOptions) {}

      // ListAndWatch returns a stream of List of Devices
      // Whenever a Device state change or a Device disappears, ListAndWatch
      // returns the new list
      rpc ListAndWatch(Empty) returns (stream ListAndWatchResponse) {}

      // Allocate is called during container creation so that the Device
      // Plugin can run device specific operations and instruct Kubelet
      // of the steps to make the
...
```

Example 4 (gRPC):
```gRPC
// PodResourcesLister is a service provided by the kubelet that provides information about the
// node resources consumed by pods and containers on the node
service PodResourcesLister {
    rpc List(ListPodResourcesRequest) returns (ListPodResourcesResponse) {}
    rpc GetAllocatableResources(AllocatableResourcesRequest) returns (AllocatableResourcesResponse) {}
    rpc Get(GetPodResourcesRequest) returns (GetPodResourcesResponse) {}
}
```

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## Topology Aware Routing

**URL:** https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/#implementation-control-plane

**Contents:**
- Topology Aware Routing
    - Note:
- Motivation
- Enabling Topology Aware Routing
    - Note:
- When it works best
  - 1. Incoming traffic is evenly distributed
  - 2. The Service has 3 or more endpoints per zone
- How It Works
  - EndpointSlice controller

Topology Aware Routing adjusts routing behavior to prefer keeping traffic in the zone it originated from. In some cases this can help reduce costs or improve network performance.

Kubernetes clusters are increasingly deployed in multi-zone environments. Topology Aware Routing provides a mechanism to help keep traffic within the zone it originated from. When calculating the endpoints for a Service, the EndpointSlice controller considers the topology (region and zone) of each endpoint and populates the hints field to allocate it to a zone. Cluster components such as kube-proxy can then consume those hints, and use them to influence how the traffic is routed (favoring topologically closer endpoints).

You can enable Topology Aware Routing for a Service by setting the service.kubernetes.io/topology-mode annotation to Auto. When there are enough endpoints available in each zone, Topology Hints will be populated on EndpointSlices to allocate individual endpoints to specific zones, resulting in traffic being routed closer to where it originated from.

This feature works best when:

If a large proportion of traffic is originating from a single zone, that traffic could overload the subset of endpoints that have been allocated to that zone. This feature is not recommended when incoming traffic is expected to originate from a single zone.

In a three zone cluster, this means 9 or more endpoints. If there are fewer than 3 endpoints per zone, there is a high (≈50%) probability that the EndpointSlice controller will not be able to allocate endpoints evenly and instead will fall back to the default cluster-wide routing approach.

The "Auto" heuristic attempts to proportionally allocate a number of endpoints to each zone. Note that this heuristic works best for Services that have a significant number of endpoints.

The EndpointSlice controller is responsible for setting hints on EndpointSlices when this heuristic is enabled. The controller allocates a proportional amount of endpoints to each zone. This proportion is based on the allocatable CPU cores for nodes running in that zone. For example, if one zone had 2 CPU cores and another zone only had 1 CPU core, the controller would allocate twice as many endpoints to the zone with 2 CPU cores.

The following example shows what an EndpointSlice looks like when hints have been populated:

The kube-proxy component filters the endpoints it routes to based on the hints set by the EndpointSlice controller. In most cases, this mea

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: example-hints
  labels:
    kubernetes.io/service-name: example-svc
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 80
endpoints:
  - addresses:
      - "10.1.2.3"
    conditions:
      ready: true
    hostname: pod-1
    zone: zone-a
    hints:
      forZones:
        - name: "zone-a"
```

---

## Nodes

**URL:** https://kubernetes.io/docs/concepts/architecture/nodes/#condition

**Contents:**
- Nodes
- Management
    - Note:
  - Node name uniqueness
  - Self-registration of Nodes
    - Note:
  - Manual Node administration
    - Note:
- Node status
- Node heartbeats

Kubernetes runs your workload by placing containers into Pods to run on Nodes. A node may be a virtual or physical machine, depending on the cluster. Each node is managed by the control plane and contains the services necessary to run Pods.

Typically you have several nodes in a cluster; in a learning or resource-limited environment, you might have only one node.

The components on a node include the kubelet, a container runtime, and the kube-proxy.

There are two main ways to have Nodes added to the API server:

After you create a Node object, or the kubelet on a node self-registers, the control plane checks whether the new Node object is valid. For example, if you try to create a Node from the following JSON manifest:

Kubernetes creates a Node object internally (the representation). Kubernetes checks that a kubelet has registered to the API server that matches the metadata.name field of the Node. If the node is healthy (i.e. all necessary services are running), then it is eligible to run a Pod. Otherwise, that node is ignored for any cluster activity until it becomes healthy.

Kubernetes keeps the object for the invalid Node and continues checking to see whether it becomes healthy.

You, or a controller, must explicitly delete the Node object to stop that health checking.

The name of a Node object must be a valid DNS subdomain name.

The name identifies a Node. Two Nodes cannot have the same name at the same time. Kubernetes also assumes that a resource with the same name is the same object. In case of a Node, it is implicitly assumed that an instance using the same name will have the same state (e.g. network settings, root disk contents) and attributes like node labels. This may lead to inconsistencies if an instance was modified without changing its name. If the Node needs to be replaced or updated significantly, the existing Node object needs to be removed from API server first and re-added after the update.

When the kubelet flag --register-node is true (the default), the kubelet will attempt to register itself with the API server. This is the preferred pattern, used by most distros.

For self-registration, the kubelet is started with the following options:

--kubeconfig - Path to credentials to authenticate itself to the API server.

--cloud-provider - How to talk to a cloud provider to read metadata about itself.

--register-node - Automatically register with the API server.

--register-with-taints - Register the node with the given list of taint

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
  "kind": "Node",
  "apiVersion": "v1",
  "metadata": {
    "name": "10.240.79.157",
    "labels": {
      "name": "my-first-k8s-node"
    }
  }
}
```

Example 2 (shell):
```shell
kubectl cordon $NODENAME
```

Example 3 (shell):
```shell
kubectl describe node <insert-node-name-here>
```

---

## Resource Bin Packing

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/

**Contents:**
- Resource Bin Packing
- Enabling bin packing using MostAllocated strategy
- Enabling bin packing using RequestedToCapacityRatio
  - Tuning the score function
  - Node scoring for capacity allocation
- What's next
- Feedback

In the scheduling-plugin NodeResourcesFit of kube-scheduler, there are two scoring strategies that support the bin packing of resources: MostAllocated and RequestedToCapacityRatio.

The MostAllocated strategy scores the nodes based on the utilization of resources, favoring the ones with higher allocation. For each resource type, you can set a weight to modify its influence in the node score.

To set the MostAllocated strategy for the NodeResourcesFit plugin, use a scheduler configuration similar to the following:

To learn more about other parameters and their default configuration, see the API documentation for NodeResourcesFitArgs.

The RequestedToCapacityRatio strategy allows the users to specify the resources along with weights for each resource to score nodes based on the request to capacity ratio. This allows users to bin pack extended resources by using appropriate parameters to improve the utilization of scarce resources in large clusters. It favors nodes according to a configured function of the allocated resources. The behavior of the RequestedToCapacityRatio in the NodeResourcesFit score function can be controlled by the scoringStrategy field. Within the scoringStrategy field, you can configure two parameters: requestedToCapacityRatio and resources. The shape in the requestedToCapacityRatio parameter allows the user to tune the function as least requested or most requested based on utilization and score values. The resources parameter comprises both the name of the resource to be considered during scoring and its corresponding weight, which specifies the weight of each resource.

Below is an example configuration that sets the bin packing behavior for extended resources intel.com/foo and intel.com/bar using the requestedToCapacityRatio field.

Referencing the KubeSchedulerConfiguration file with the kube-scheduler flag --config=/path/to/config/file will pass the configuration to the scheduler.

To learn more about other parameters and their default configuration, see the API documentation for NodeResourcesFitArgs.

shape is used to specify the behavior of the RequestedToCapacityRatio function.

The above arguments give the node a score of 0 if utilization is 0% and 10 for utilization 100%, thus enabling bin packing behavior. To enable least requested the score value must be reversed as follows.

resources is an optional parameter which defaults to:

It can be used to add extended resources as follows:

The weight parameter is optional and is set

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
        - name: intel.com/foo
          weight: 3
        - name: intel.com/bar
          weight: 3
        type: MostAllocated
    name: NodeResourcesFit
```

Example 2 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- pluginConfig:
  - args:
      scoringStrategy:
        resources:
        - name: intel.com/foo
          weight: 3
        - name: intel.com/bar
          weight: 3
        requestedToCapacityRatio:
          shape:
          - utilization: 0
            score: 0
          - utilization: 100
            score: 10
        type: RequestedToCapacityRatio
    name: NodeResourcesFit
```

Example 3 (yaml):
```yaml
shape:
  - utilization: 0
    score: 0
  - utilization: 100
    score: 10
```

Example 4 (yaml):
```yaml
shape:
  - utilization: 0
    score: 10
  - utilization: 100
    score: 0
```

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Security

**URL:** https://kubernetes.io/docs/concepts/security/#policies

**Contents:**
- Security
- Kubernetes security mechanisms
  - Control plane protection
  - Secrets
  - Workload protection
  - Admission control
  - Auditing
- Cloud provider security
- Policies
- What's next

This section of the Kubernetes documentation aims to help you learn to run workloads more securely, and about the essential aspects of keeping a Kubernetes cluster secure.

Kubernetes is based on a cloud-native architecture, and draws on advice from the CNCF about good practice for cloud native information security.

Read Cloud Native Security and Kubernetes for the broader context about how to secure your cluster and the applications that you're running on it.

Kubernetes includes several APIs and security controls, as well as ways to define policies that can form part of how you manage information security.

A key security mechanism for any Kubernetes cluster is to control access to the Kubernetes API.

Kubernetes expects you to configure and use TLS to provide data encryption in transit within the control plane, and between the control plane and its clients. You can also enable encryption at rest for the data stored within Kubernetes control plane; this is separate from using encryption at rest for your own workloads' data, which might also be a good idea.

The Secret API provides basic protection for configuration values that require confidentiality.

Enforce Pod security standards to ensure that Pods and their containers are isolated appropriately. You can also use RuntimeClasses to define custom isolation if you need it.

Network policies let you control network traffic between Pods, or between Pods and the network outside your cluster.

You can deploy security controls from the wider ecosystem to implement preventative or detective controls around Pods, their containers, and the images that run in them.

Admission controllers are plugins that intercept Kubernetes API requests and can validate or mutate the requests based on specific fields in the request. Thoughtfully designing these controllers helps to avoid unintended disruptions as Kubernetes APIs change across version updates. For design considerations, see Admission Webhook Good Practices.

Kubernetes audit logging provides a security-relevant, chronological set of records documenting the sequence of actions in a cluster. The cluster audits the activities generated by users, by applications that use the Kubernetes API, and by the control plane itself.

If you are running a Kubernetes cluster on your own hardware or a different cloud provider, consult your documentation for security best practices. Here are links to some of the popular cloud providers' security documentation:

You can define se

*[Content truncated]*

---

## Gateway API

**URL:** https://kubernetes.io/docs/concepts/services-networking/gateway/

**Contents:**
- Gateway API
- Design principles
- Resource model
  - GatewayClass
  - Gateway
  - HTTPRoute
  - GRPCRoute
- Request flow
- Conformance
- Migrating from Ingress

Make network services available by using an extensible, role-oriented, protocol-aware configuration mechanism. Gateway API is an add-on containing API kinds that provide dynamic infrastructure provisioning and advanced traffic routing.

The following principles shaped the design and architecture of Gateway API:

Gateway API has four stable API kinds:

GatewayClass: Defines a set of gateways with common configuration and managed by a controller that implements the class.

Gateway: Defines an instance of traffic handling infrastructure, such as cloud load balancer.

HTTPRoute: Defines HTTP-specific rules for mapping traffic from a Gateway listener to a representation of backend network endpoints. These endpoints are often represented as a Service.

GRPCRoute: Defines gRPC-specific rules for mapping traffic from a Gateway listener to a representation of backend network endpoints. These endpoints are often represented as a Service.

Gateway API is organized into different API kinds that have interdependent relationships to support the role-oriented nature of organizations. A Gateway object is associated with exactly one GatewayClass; the GatewayClass describes the gateway controller responsible for managing Gateways of this class. One or more route kinds such as HTTPRoute, are then associated to Gateways. A Gateway can filter the routes that may be attached to its listeners, forming a bidirectional trust model with routes.

The following figure illustrates the relationships of the three stable Gateway API kinds:

Gateways can be implemented by different controllers, often with different configurations. A Gateway must reference a GatewayClass that contains the name of the controller that implements the class.

A minimal GatewayClass example:

In this example, a controller that has implemented Gateway API is configured to manage GatewayClasses with the controller name example.com/gateway-controller. Gateways of this class will be managed by the implementation's controller.

See the GatewayClass reference for a full definition of this API kind.

A Gateway describes an instance of traffic handling infrastructure. It defines a network endpoint that can be used for processing traffic, i.e. filtering, balancing, splitting, etc. for backends such as a Service. For example, a Gateway may represent a cloud load balancer or an in-cluster proxy server that is configured to accept HTTP traffic.

A minimal Gateway resource example:

In this example, an instance of traffic h

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: example-class
spec:
  controllerName: example.com/gateway-controller
```

Example 2 (yaml):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: example-gateway
spec:
  gatewayClassName: example-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
```

Example 3 (yaml):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-httproute
spec:
  parentRefs:
  - name: example-gateway
  hostnames:
  - "www.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /login
    backendRefs:
    - name: example-svc
      port: 8080
```

Example 4 (yaml):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: example-grpcroute
spec:
  parentRefs:
  - name: example-gateway
  hostnames:
  - "svc.example.com"
  rules:
  - backendRefs:
    - name: example-svc
      port: 50051
```

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Overview

**URL:** https://kubernetes.io/docs/concepts/overview/

**Contents:**
- Overview
- Why you need Kubernetes and what it can do
- What Kubernetes is not
- Historical context for Kubernetes
- What's next
- Feedback

This page is an overview of Kubernetes.

The name Kubernetes originates from Greek, meaning helmsman or pilot. K8s as an abbreviation results from counting the eight letters between the "K" and the "s". Google open-sourced the Kubernetes project in 2014. Kubernetes combines over 15 years of Google's experience running production workloads at scale with best-of-breed ideas and practices from the community.

Containers are a good way to bundle and run your applications. In a production environment, you need to manage the containers that run the applications and ensure that there is no downtime. For example, if a container goes down, another container needs to start. Wouldn't it be easier if this behavior was handled by a system?

That's how Kubernetes comes to the rescue! Kubernetes provides you with a framework to run distributed systems resiliently. It takes care of scaling and failover for your application, provides deployment patterns, and more. For example: Kubernetes can easily manage a canary deployment for your system.

Kubernetes provides you with:

Kubernetes is not a traditional, all-inclusive PaaS (Platform as a Service) system. Since Kubernetes operates at the container level rather than at the hardware level, it provides some generally applicable features common to PaaS offerings, such as deployment, scaling, load balancing, and lets users integrate their logging, monitoring, and alerting solutions. However, Kubernetes is not monolithic, and these default solutions are optional and pluggable. Kubernetes provides the building blocks for building developer platforms, but preserves user choice and flexibility where it is important.

Let's take a look at why Kubernetes is so useful by going back in time.

Traditional deployment era:

Early on, organizations ran applications on physical servers. There was no way to define resource boundaries for applications in a physical server, and this caused resource allocation issues. For example, if multiple applications run on a physical server, there can be instances where one application would take up most of the resources, and as a result, the other applications would underperform. A solution for this would be to run each application on a different physical server. But this did not scale as resources were underutilized, and it was expensive for organizations to maintain many physical servers.

Virtualized deployment era:

As a solution, virtualization was introduced. It allows you to run multiple Virtual M

*[Content truncated]*

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/using-api/#api-versioning

**Contents:**
- API Overview
- API versioning
    - Note:
- API groups
- Enabling or disabling API groups
    - Note:
- Persistence
- What's next
- Feedback

This section provides reference information for the Kubernetes API.

The REST API is the fundamental fabric of Kubernetes. All operations and communications between components, and external user commands are REST API calls that the API Server handles. Consequently, everything in the Kubernetes platform is treated as an API object and has a corresponding entry in the API.

The Kubernetes API reference lists the API for Kubernetes version v1.34.

For general background information, read The Kubernetes API. Controlling Access to the Kubernetes API describes how clients can authenticate to the Kubernetes API server, and how their requests are authorized.

The JSON and Protobuf serialization schemas follow the same guidelines for schema changes. The following descriptions cover both formats.

The API versioning and software versioning are indirectly related. The API and release versioning proposal describes the relationship between API versioning and software versioning.

Different API versions indicate different levels of stability and support. You can find more information about the criteria for each level in the API Changes documentation.

Here's a summary of each level:

The version names contain beta (for example, v2beta3).

Built-in beta API versions are disabled by default and must be explicitly enabled in the kube-apiserver configuration to be used (except for beta versions of APIs introduced prior to Kubernetes 1.22, which were enabled by default).

Built-in beta API versions have a maximum lifetime of 9 months or 3 minor releases (whichever is longer) from introduction to deprecation, and 9 months or 3 minor releases (whichever is longer) from deprecation to removal.

The software is well tested. Enabling a feature is considered safe.

The support for a feature will not be dropped, though the details may change.

The schema and/or semantics of objects may change in incompatible ways in a subsequent beta or stable API version. When this happens, migration instructions are provided. Adapting to a subsequent beta or stable API version may require editing or re-creating API objects, and may not be straightforward. The migration may require downtime for applications that rely on the feature.

The software is not recommended for production uses. Subsequent releases may introduce incompatible changes. Use of beta API versions is required to transition to subsequent beta or stable API versions once the beta API version is deprecated and no longer served.

API

*[Content truncated]*

---

## Linux kernel security constraints for Pods and containers

**URL:** https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/

**Contents:**
- Linux kernel security constraints for Pods and containers
- Run workloads without root privileges
    - Caution:
- Security features in the Linux kernel
  - seccomp
    - Note:
    - Considerations for seccomp
  - AppArmor and SELinux: policy-based mandatory access control
    - AppArmor
    - SELinux

This page describes some of the security features that are built into the Linux kernel that you can use in your Kubernetes workloads. To learn how to apply these features to your Pods and containers, refer to Configure a SecurityContext for a Pod or Container. You should already be familiar with Linux and with the basics of Kubernetes workloads.

When you deploy a workload in Kubernetes, use the Pod specification to restrict that workload from running as the root user on the node. You can use the Pod securityContext to define the specific Linux user and group for the processes in the Pod, and explicitly restrict containers from running as root users. Setting these values in the Pod manifest takes precedence over similar values in the container image, which is especially useful if you're running images that you don't own.

Configuring the kernel security features on this page provides fine-grained control over the actions that processes in your cluster can take, but managing these configurations can be challenging at scale. Running containers as non-root, or in user namespaces if you need root privileges, helps to reduce the chance that you'll need to enforce your configured kernel security capabilities.

Kubernetes lets you configure and use Linux kernel features to improve isolation and harden your containerized workloads. Common features include the following:

To configure settings for one of these features, the operating system that you choose for your nodes must enable the feature in the kernel. For example, Ubuntu 7.10 and later enable AppArmor by default. To learn whether your OS enables a specific feature, consult the OS documentation.

You use the securityContext field in your Pod specification to define the constraints that apply to those processes. The securityContext field also supports other security settings, such as specific Linux capabilities or file access permissions using UIDs and GIDs. To learn more, refer to Configure a SecurityContext for a Pod or Container.

Some of your workloads might need privileges to perform specific actions as the root user on your node's host machine. Linux uses capabilities to divide the available privileges into categories, so that processes can get the privileges required to perform specific actions without being granted all privileges. Each capability has a set of system calls (syscalls) that a process can make. seccomp lets you restrict these individual syscalls. It can be used to sandbox the privileges o

*[Content truncated]*

---

## Logging Architecture

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/logging/

**Contents:**
- Logging Architecture
- Pod and container logs
  - Container log streams
  - How nodes handle container logs
  - Log rotation
    - Note:
- System component logs
  - Log locations
    - Caution:
    - Note:

Application logs can help you understand what is happening inside your application. The logs are particularly useful for debugging problems and monitoring cluster activity. Most modern applications have some kind of logging mechanism. Likewise, container engines are designed to support logging. The easiest and most adopted logging method for containerized applications is writing to standard output and standard error streams.

However, the native functionality provided by a container engine or runtime is usually not enough for a complete logging solution.

For example, you may want to access your application's logs if a container crashes, a pod gets evicted, or a node dies.

In a cluster, logs should have a separate storage and lifecycle independent of nodes, pods, or containers. This concept is called cluster-level logging.

Cluster-level logging architectures require a separate backend to store, analyze, and query logs. Kubernetes does not provide a native storage solution for log data. Instead, there are many logging solutions that integrate with Kubernetes. The following sections describe how to handle and store logs on nodes.

Kubernetes captures logs from each container in a running Pod.

This example uses a manifest for a Pod with a container that writes text to the standard output stream, once per second.

To run this pod, use the following command:

To fetch the logs, use the kubectl logs command, as follows:

The output is similar to:

You can use kubectl logs --previous to retrieve logs from a previous instantiation of a container. If your pod has multiple containers, specify which container's logs you want to access by appending a container name to the command, with a -c flag, like so:

As an alpha feature, the kubelet can split out the logs from the two standard streams produced by a container: standard output and standard error. To use this behavior, you must enable the PodLogsQuerySplitStreams feature gate. With that feature gate enabled, Kubernetes 1.34 allows access to these log streams directly via the Pod API. You can fetch a specific stream by specifying the stream name (either Stdout or Stderr), using the stream query string. You must have access to read the log subresource of that Pod.

To demonstrate this feature, you can create a Pod that periodically writes text to both the standard output and error stream.

To run this pod, use the following command:

To fetch only the stderr log stream, you can run:

See the kubectl logs documenta

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: counter
spec:
  containers:
  - name: count
    image: busybox:1.28
    args: [/bin/sh, -c,
            'i=0; while true; do echo "$i: $(date)"; i=$((i+1)); sleep 1; done']
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/debug/counter-pod.yaml
```

Example 3 (console):
```console
pod/counter created
```

Example 4 (shell):
```shell
kubectl logs counter
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/using-api/

**Contents:**
- API Overview
- API versioning
    - Note:
- API groups
- Enabling or disabling API groups
    - Note:
- Persistence
- What's next
- Feedback

This section provides reference information for the Kubernetes API.

The REST API is the fundamental fabric of Kubernetes. All operations and communications between components, and external user commands are REST API calls that the API Server handles. Consequently, everything in the Kubernetes platform is treated as an API object and has a corresponding entry in the API.

The Kubernetes API reference lists the API for Kubernetes version v1.34.

For general background information, read The Kubernetes API. Controlling Access to the Kubernetes API describes how clients can authenticate to the Kubernetes API server, and how their requests are authorized.

The JSON and Protobuf serialization schemas follow the same guidelines for schema changes. The following descriptions cover both formats.

The API versioning and software versioning are indirectly related. The API and release versioning proposal describes the relationship between API versioning and software versioning.

Different API versions indicate different levels of stability and support. You can find more information about the criteria for each level in the API Changes documentation.

Here's a summary of each level:

The version names contain beta (for example, v2beta3).

Built-in beta API versions are disabled by default and must be explicitly enabled in the kube-apiserver configuration to be used (except for beta versions of APIs introduced prior to Kubernetes 1.22, which were enabled by default).

Built-in beta API versions have a maximum lifetime of 9 months or 3 minor releases (whichever is longer) from introduction to deprecation, and 9 months or 3 minor releases (whichever is longer) from deprecation to removal.

The software is well tested. Enabling a feature is considered safe.

The support for a feature will not be dropped, though the details may change.

The schema and/or semantics of objects may change in incompatible ways in a subsequent beta or stable API version. When this happens, migration instructions are provided. Adapting to a subsequent beta or stable API version may require editing or re-creating API objects, and may not be straightforward. The migration may require downtime for applications that rely on the feature.

The software is not recommended for production uses. Subsequent releases may introduce incompatible changes. Use of beta API versions is required to transition to subsequent beta or stable API versions once the beta API version is deprecated and no longer served.

API

*[Content truncated]*

---

## ReplicaSet

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/

**Contents:**
- ReplicaSet
- How a ReplicaSet works
- When to use a ReplicaSet
- Example
- Non-Template Pod acquisitions
- Writing a ReplicaSet manifest
  - Pod Template
  - Pod Selector
    - Note:
  - Replicas

A ReplicaSet's purpose is to maintain a stable set of replica Pods running at any given time. As such, it is often used to guarantee the availability of a specified number of identical Pods.

A ReplicaSet is defined with fields, including a selector that specifies how to identify Pods it can acquire, a number of replicas indicating how many Pods it should be maintaining, and a pod template specifying the data of new Pods it should create to meet the number of replicas criteria. A ReplicaSet then fulfills its purpose by creating and deleting Pods as needed to reach the desired number. When a ReplicaSet needs to create new Pods, it uses its Pod template.

A ReplicaSet is linked to its Pods via the Pods' metadata.ownerReferences field, which specifies what resource the current object is owned by. All Pods acquired by a ReplicaSet have their owning ReplicaSet's identifying information within their ownerReferences field. It's through this link that the ReplicaSet knows of the state of the Pods it is maintaining and plans accordingly.

A ReplicaSet identifies new Pods to acquire by using its selector. If there is a Pod that has no OwnerReference or the OwnerReference is not a Controller and it matches a ReplicaSet's selector, it will be immediately acquired by said ReplicaSet.

A ReplicaSet ensures that a specified number of pod replicas are running at any given time. However, a Deployment is a higher-level concept that manages ReplicaSets and provides declarative updates to Pods along with a lot of other useful features. Therefore, we recommend using Deployments instead of directly using ReplicaSets, unless you require custom update orchestration or don't require updates at all.

This actually means that you may never need to manipulate ReplicaSet objects: use a Deployment instead, and define your application in the spec section.

Saving this manifest into frontend.yaml and submitting it to a Kubernetes cluster will create the defined ReplicaSet and the Pods that it manages.

You can then get the current ReplicaSets deployed:

And see the frontend one you created:

You can also check on the state of the ReplicaSet:

And you will see output similar to:

And lastly you can check for the Pods brought up:

You should see Pod information similar to:

You can also verify that the owner reference of these pods is set to the frontend ReplicaSet. To do this, get the yaml of one of the Pods running:

The output will look similar to this, with the frontend ReplicaSet's in

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  labels:
    app: guestbook
    tier: frontend
spec:
  # modify replicas according to your case
  replicas: 3
  selector:
    matchLabels:
      tier: frontend
  template:
    metadata:
      labels:
        tier: frontend
    spec:
      containers:
      - name: php-redis
        image: us-docker.pkg.dev/google-samples/containers/gke/gb-frontend:v5
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/frontend.yaml
```

Example 3 (shell):
```shell
kubectl get rs
```

Example 4 (unknown):
```unknown
NAME       DESIRED   CURRENT   READY   AGE
frontend   3         3         3       6s
```

---

## Service Internal Traffic Policy

**URL:** https://kubernetes.io/docs/concepts/services-networking/service-traffic-policy/

**Contents:**
- Service Internal Traffic Policy
- Using Service Internal Traffic Policy
    - Note:
- How it works
- What's next
- Feedback

Service Internal Traffic Policy enables internal traffic restrictions to only route internal traffic to endpoints within the node the traffic originated from. The "internal" traffic here refers to traffic originated from Pods in the current cluster. This can help to reduce costs and improve performance.

You can enable the internal-only traffic policy for a Service, by setting its .spec.internalTrafficPolicy to Local. This tells kube-proxy to only use node local endpoints for cluster internal traffic.

The following example shows what a Service looks like when you set .spec.internalTrafficPolicy to Local:

The kube-proxy filters the endpoints it routes to based on the spec.internalTrafficPolicy setting. When it's set to Local, only node local endpoints are considered. When it's Cluster (the default), or is not set, Kubernetes considers all endpoints.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
  internalTrafficPolicy: Local
```

---

## Security For Windows Nodes

**URL:** https://kubernetes.io/docs/concepts/security/windows-security/

**Contents:**
- Security For Windows Nodes
- Protection for Secret data on nodes
- Container users
    - Note:
- Pod-level security isolation
- Feedback

This page describes security considerations and best practices specific to the Windows operating system.

On Windows, data from Secrets are written out in clear text onto the node's local storage (as compared to using tmpfs / in-memory filesystems on Linux). As a cluster operator, you should take both of the following additional measures:

RunAsUsername can be specified for Windows Pods or containers to execute the container processes as specific user. This is roughly equivalent to RunAsUser.

Windows containers offer two default user accounts, ContainerUser and ContainerAdministrator. The differences between these two user accounts are covered in When to use ContainerAdmin and ContainerUser user accounts within Microsoft's Secure Windows containers documentation.

Local users can be added to container images during the container build process.

Windows containers can also run as Active Directory identities by utilizing Group Managed Service Accounts

Linux-specific pod security context mechanisms (such as SELinux, AppArmor, Seccomp, or custom POSIX capabilities) are not supported on Windows nodes.

Privileged containers are not supported on Windows. Instead HostProcess containers can be used on Windows to perform many of the tasks performed by privileged containers on Linux.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Nodes

**URL:** https://kubernetes.io/docs/concepts/architecture/nodes/#graceful-node-shutdown

**Contents:**
- Nodes
- Management
    - Note:
  - Node name uniqueness
  - Self-registration of Nodes
    - Note:
  - Manual Node administration
    - Note:
- Node status
- Node heartbeats

Kubernetes runs your workload by placing containers into Pods to run on Nodes. A node may be a virtual or physical machine, depending on the cluster. Each node is managed by the control plane and contains the services necessary to run Pods.

Typically you have several nodes in a cluster; in a learning or resource-limited environment, you might have only one node.

The components on a node include the kubelet, a container runtime, and the kube-proxy.

There are two main ways to have Nodes added to the API server:

After you create a Node object, or the kubelet on a node self-registers, the control plane checks whether the new Node object is valid. For example, if you try to create a Node from the following JSON manifest:

Kubernetes creates a Node object internally (the representation). Kubernetes checks that a kubelet has registered to the API server that matches the metadata.name field of the Node. If the node is healthy (i.e. all necessary services are running), then it is eligible to run a Pod. Otherwise, that node is ignored for any cluster activity until it becomes healthy.

Kubernetes keeps the object for the invalid Node and continues checking to see whether it becomes healthy.

You, or a controller, must explicitly delete the Node object to stop that health checking.

The name of a Node object must be a valid DNS subdomain name.

The name identifies a Node. Two Nodes cannot have the same name at the same time. Kubernetes also assumes that a resource with the same name is the same object. In case of a Node, it is implicitly assumed that an instance using the same name will have the same state (e.g. network settings, root disk contents) and attributes like node labels. This may lead to inconsistencies if an instance was modified without changing its name. If the Node needs to be replaced or updated significantly, the existing Node object needs to be removed from API server first and re-added after the update.

When the kubelet flag --register-node is true (the default), the kubelet will attempt to register itself with the API server. This is the preferred pattern, used by most distros.

For self-registration, the kubelet is started with the following options:

--kubeconfig - Path to credentials to authenticate itself to the API server.

--cloud-provider - How to talk to a cloud provider to read metadata about itself.

--register-node - Automatically register with the API server.

--register-with-taints - Register the node with the given list of taint

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
  "kind": "Node",
  "apiVersion": "v1",
  "metadata": {
    "name": "10.240.79.157",
    "labels": {
      "name": "my-first-k8s-node"
    }
  }
}
```

Example 2 (shell):
```shell
kubectl cordon $NODENAME
```

Example 3 (shell):
```shell
kubectl describe node <insert-node-name-here>
```

---

## Garbage Collection

**URL:** https://kubernetes.io/docs/concepts/architecture/garbage-collection/#containers-images

**Contents:**
- Garbage Collection
- Owners and dependents
    - Note:
- Cascading deletion
  - Foreground cascading deletion
  - Background cascading deletion
  - Orphaned dependents
- Garbage collection of unused containers and images
  - Container image lifecycle
    - Garbage collection for unused container images

Garbage collection is a collective term for the various mechanisms Kubernetes uses to clean up cluster resources. This allows the clean up of resources like the following:

Many objects in Kubernetes link to each other through owner references. Owner references tell the control plane which objects are dependent on others. Kubernetes uses owner references to give the control plane, and other API clients, the opportunity to clean up related resources before deleting an object. In most cases, Kubernetes manages owner references automatically.

Ownership is different from the labels and selectors mechanism that some resources also use. For example, consider a Service that creates EndpointSlice objects. The Service uses labels to allow the control plane to determine which EndpointSlice objects are used for that Service. In addition to the labels, each EndpointSlice that is managed on behalf of a Service has an owner reference. Owner references help different parts of Kubernetes avoid interfering with objects they don’t control.

Cross-namespace owner references are disallowed by design. Namespaced dependents can specify cluster-scoped or namespaced owners. A namespaced owner must exist in the same namespace as the dependent. If it does not, the owner reference is treated as absent, and the dependent is subject to deletion once all owners are verified absent.

Cluster-scoped dependents can only specify cluster-scoped owners. In v1.20+, if a cluster-scoped dependent specifies a namespaced kind as an owner, it is treated as having an unresolvable owner reference, and is not able to be garbage collected.

In v1.20+, if the garbage collector detects an invalid cross-namespace ownerReference, or a cluster-scoped dependent with an ownerReference referencing a namespaced kind, a warning Event with a reason of OwnerRefInvalidNamespace and an involvedObject of the invalid dependent is reported. You can check for that kind of Event by running kubectl get events -A --field-selector=reason=OwnerRefInvalidNamespace.

Kubernetes checks for and deletes objects that no longer have owner references, like the pods left behind when you delete a ReplicaSet. When you delete an object, you can control whether Kubernetes deletes the object's dependents automatically, in a process called cascading deletion. There are two types of cascading deletion, as follows:

You can also control how and when garbage collection deletes resources that have owner references using Kubernetes finalizers

*[Content truncated]*

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/

---

## Taints and Tolerations

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/#taint-based-evictions

**Contents:**
- Taints and Tolerations
- Concepts
    - Note:
- Example Use Cases
- Taint based Evictions
    - Note:
    - Note:
    - Note:
- Taint Nodes by Condition
- Device taints and tolerations

Node affinity is a property of Pods that attracts them to a set of nodes (either as a preference or a hard requirement). Taints are the opposite -- they allow a node to repel a set of pods.

Tolerations are applied to pods. Tolerations allow the scheduler to schedule pods with matching taints. Tolerations allow scheduling but don't guarantee scheduling: the scheduler also evaluates other parameters as part of its function.

Taints and tolerations work together to ensure that pods are not scheduled onto inappropriate nodes. One or more taints are applied to a node; this marks that the node should not accept any pods that do not tolerate the taints.

You add a taint to a node using kubectl taint. For example,

places a taint on node node1. The taint has key key1, value value1, and taint effect NoSchedule. This means that no pod will be able to schedule onto node1 unless it has a matching toleration.

To remove the taint added by the command above, you can run:

You specify a toleration for a pod in the PodSpec. Both of the following tolerations "match" the taint created by the kubectl taint line above, and thus a pod with either toleration would be able to schedule onto node1:

The default Kubernetes scheduler takes taints and tolerations into account when selecting a node to run a particular Pod. However, if you manually specify the .spec.nodeName for a Pod, that action bypasses the scheduler; the Pod is then bound onto the node where you assigned it, even if there are NoSchedule taints on that node that you selected. If this happens and the node also has a NoExecute taint set, the kubelet will eject the Pod unless there is an appropriate tolerance set.

Here's an example of a pod that has some tolerations defined:

The default value for operator is Equal.

A toleration "matches" a taint if the keys are the same and the effects are the same, and:

There are two special cases:

If the key is empty, then the operator must be Exists, which matches all keys and values. Note that the effect still needs to be matched at the same time.

An empty effect matches all effects with key key1.

The above example used the effect of NoSchedule. Alternatively, you can use the effect of PreferNoSchedule.

The allowed values for the effect field are:

You can put multiple taints on the same node and multiple tolerations on the same pod. The way Kubernetes processes multiple taints and tolerations is like a filter: start with all of a node's taints, then ignore the ones for wh

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl taint nodes node1 key1=value1:NoSchedule
```

Example 2 (shell):
```shell
kubectl taint nodes node1 key1=value1:NoSchedule-
```

Example 3 (yaml):
```yaml
tolerations:
- key: "key1"
  operator: "Equal"
  value: "value1"
  effect: "NoSchedule"
```

Example 4 (yaml):
```yaml
tolerations:
- key: "key1"
  operator: "Exists"
  effect: "NoSchedule"
```

---

## Resource Management for Pods and Containers

**URL:** https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#extended-resources-allocation-by-dra

**Contents:**
- Resource Management for Pods and Containers
- Requests and limits
    - Note:
    - Note:
- Resource types
    - Note:
- Resource requests and limits of Pod and container
- Pod-level resource specification
- Resource units in Kubernetes
  - CPU resource units

When you specify a Pod, you can optionally specify how much of each resource a container needs. The most common resources to specify are CPU and memory (RAM); there are others.

When you specify the resource request for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a resource limit for a container, the kubelet enforces those limits so that the running container is not allowed to use more of that resource than the limit you set. The kubelet also reserves at least the request amount of that system resource specifically for that container to use.

If the node where a Pod is running has enough of a resource available, it's possible (and allowed) for a container to use more resource than its request for that resource specifies.

For example, if you set a memory request of 256 MiB for a container, and that container is in a Pod scheduled to a Node with 8GiB of memory and no other Pods, then the container can try to use more RAM.

Limits are a different story. Both cpu and memory limits are applied by the kubelet (and container runtime), and are ultimately enforced by the kernel. On Linux nodes, the Linux kernel enforces limits with cgroups. The behavior of cpu and memory limit enforcement is slightly different.

cpu limits are enforced by CPU throttling. When a container approaches its cpu limit, the kernel will restrict access to the CPU corresponding to the container's limit. Thus, a cpu limit is a hard limit the kernel enforces. Containers may not use more CPU than is specified in their cpu limit.

memory limits are enforced by the kernel with out of memory (OOM) kills. When a container uses more than its memory limit, the kernel may terminate it. However, terminations only happen when the kernel detects memory pressure. Thus, a container that over allocates memory may not be immediately killed. This means memory limits are enforced reactively. A container may use more memory than its memory limit, but if it does, it may get killed.

CPU and memory are each a resource type. A resource type has a base unit. CPU represents compute processing and is specified in units of Kubernetes CPUs. Memory is specified in units of bytes. For Linux workloads, you can specify huge page resources. Huge pages are a Linux-specific feature where the node kernel allocates blocks of memory that are much larger than the default page size.

For example, on a system where the default page size is 4KiB, you coul

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
128974848, 129e6, 129M,  128974848000m, 123Mi
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-resources-demo
  namespace: pod-resources-example
spec:
  resources:
    limits:
      cpu: "1"
      memory: "200Mi"
    requests:
      cpu: "1"
      memory: "100Mi"
  containers:
  - name: pod-resources-demo-ctr-1
    image: nginx
    resources:
      limits:
        cpu: "0.5"
        memory: "100Mi"
      requests:
        cpu: "0.5"
        memory: "50Mi"
  - name: pod-resources-demo-ctr-2
    image: fedora
    command:
    - sleep
    - inf
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  volumes:
    - name: ephemeral
      e
...
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/#recovering-from-failure-when-expanding-volumes

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## The Kubernetes API

**URL:** https://kubernetes.io/docs/concepts/overview/kubernetes-api/#discovery-api

**Contents:**
- The Kubernetes API
- Discovery API
  - Aggregated discovery
  - Unaggregated discovery
- OpenAPI interface definition
  - OpenAPI V2
    - Warning:
  - OpenAPI V3
  - Protobuf serialization
- Persistence

The core of Kubernetes' control plane is the API server. The API server exposes an HTTP API that lets end users, different parts of your cluster, and external components communicate with one another.

The Kubernetes API lets you query and manipulate the state of API objects in Kubernetes (for example: Pods, Namespaces, ConfigMaps, and Events).

Most operations can be performed through the kubectl command-line interface or other command-line tools, such as kubeadm, which in turn use the API. However, you can also access the API directly using REST calls. Kubernetes provides a set of client libraries for those looking to write applications using the Kubernetes API.

Each Kubernetes cluster publishes the specification of the APIs that the cluster serves. There are two mechanisms that Kubernetes uses to publish these API specifications; both are useful to enable automatic interoperability. For example, the kubectl tool fetches and caches the API specification for enabling command-line completion and other features. The two supported mechanisms are as follows:

The Discovery API provides information about the Kubernetes APIs: API names, resources, versions, and supported operations. This is a Kubernetes specific term as it is a separate API from the Kubernetes OpenAPI. It is intended to be a brief summary of the available resources and it does not detail specific schema for the resources. For reference about resource schemas, please refer to the OpenAPI document.

The Kubernetes OpenAPI Document provides (full) OpenAPI v2.0 and 3.0 schemas for all Kubernetes API endpoints. The OpenAPI v3 is the preferred method for accessing OpenAPI as it provides a more comprehensive and accurate view of the API. It includes all the available API paths, as well as all resources consumed and produced for every operations on every endpoints. It also includes any extensibility components that a cluster supports. The data is a complete specification and is significantly larger than that from the Discovery API.

Kubernetes publishes a list of all group versions and resources supported via the Discovery API. This includes the following for each resource:

The API is available in both aggregated and unaggregated form. The aggregated discovery serves two endpoints, while the unaggregated discovery serves a separate endpoint for each group version.

Kubernetes offers stable support for aggregated discovery, publishing all resources supported by a cluster through two endpoints (/api and

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
{
  "kind": "APIGroupList",
  "apiVersion": "v1",
  "groups": [
    {
      "name": "apiregistration.k8s.io",
      "versions": [
        {
          "groupVersion": "apiregistration.k8s.io/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apiregistration.k8s.io/v1",
        "version": "v1"
      }
    },
    {
      "name": "apps",
      "versions": [
        {
          "groupVersion": "apps/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apps/v1",
        "version": "v1"
      }
    }
...
```

Example 2 (yaml):
```yaml
{
    "paths": {
        ...,
        "api/v1": {
            "serverRelativeURL": "/openapi/v3/api/v1?hash=CC0E9BFD992D8C59AEC98A1E2336F899E8318D3CF4C68944C3DEC640AF5AB52D864AC50DAA8D145B3494F75FA3CFF939FCBDDA431DAD3CA79738B297795818CF"
        },
        "apis/admissionregistration.k8s.io/v1": {
            "serverRelativeURL": "/openapi/v3/apis/admissionregistration.k8s.io/v1?hash=E19CC93A116982CE5422FC42B590A8AFAD92CDE9AE4D59B5CAAD568F083AD07946E6CB5817531680BCE6E215C16973CD39003B0425F3477CFD854E89A9DB6597"
        },
        ....
    }
}
```

---

## Pod Priority and Preemption

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/

**Contents:**
- Pod Priority and Preemption
    - Warning:
- How to use priority and preemption
    - Note:
- PriorityClass
  - Notes about PodPriority and existing clusters
  - Example PriorityClass
- Non-preempting PriorityClass
  - Example Non-preempting PriorityClass
- Pod priority

Pods can have priority. Priority indicates the importance of a Pod relative to other Pods. If a Pod cannot be scheduled, the scheduler tries to preempt (evict) lower priority Pods to make scheduling of the pending Pod possible.

In a cluster where not all users are trusted, a malicious user could create Pods at the highest possible priorities, causing other Pods to be evicted/not get scheduled. An administrator can use ResourceQuota to prevent users from creating pods at high priorities.

See limit Priority Class consumption by default for details.

To use priority and preemption:

Add one or more PriorityClasses.

Create Pods withpriorityClassName set to one of the added PriorityClasses. Of course you do not need to create the Pods directly; normally you would add priorityClassName to the Pod template of a collection object like a Deployment.

Keep reading for more information about these steps.

A PriorityClass is a non-namespaced object that defines a mapping from a priority class name to the integer value of the priority. The name is specified in the name field of the PriorityClass object's metadata. The value is specified in the required value field. The higher the value, the higher the priority. The name of a PriorityClass object must be a valid DNS subdomain name, and it cannot be prefixed with system-.

A PriorityClass object can have any 32-bit integer value smaller than or equal to 1 billion. This means that the range of values for a PriorityClass object is from -2147483648 to 1000000000 inclusive. Larger numbers are reserved for built-in PriorityClasses that represent critical system Pods. A cluster admin should create one PriorityClass object for each such mapping that they want.

PriorityClass also has two optional fields: globalDefault and description. The globalDefault field indicates that the value of this PriorityClass should be used for Pods without a priorityClassName. Only one PriorityClass with globalDefault set to true can exist in the system. If there is no PriorityClass with globalDefault set, the priority of Pods with no priorityClassName is zero.

The description field is an arbitrary string. It is meant to tell users of the cluster when they should use this PriorityClass.

If you upgrade an existing cluster without this feature, the priority of your existing Pods is effectively zero.

Addition of a PriorityClass with globalDefault set to true does not change the priorities of existing Pods. The value of such a PriorityClass is us

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "This priority class should be used for XYZ service pods only."
```

Example 2 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-nonpreempting
value: 1000000
preemptionPolicy: Never
globalDefault: false
description: "This priority class will not cause other pods to be preempted."
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  priorityClassName: high-priority
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/using-api/#api-groups

**Contents:**
- API Overview
- API versioning
    - Note:
- API groups
- Enabling or disabling API groups
    - Note:
- Persistence
- What's next
- Feedback

This section provides reference information for the Kubernetes API.

The REST API is the fundamental fabric of Kubernetes. All operations and communications between components, and external user commands are REST API calls that the API Server handles. Consequently, everything in the Kubernetes platform is treated as an API object and has a corresponding entry in the API.

The Kubernetes API reference lists the API for Kubernetes version v1.34.

For general background information, read The Kubernetes API. Controlling Access to the Kubernetes API describes how clients can authenticate to the Kubernetes API server, and how their requests are authorized.

The JSON and Protobuf serialization schemas follow the same guidelines for schema changes. The following descriptions cover both formats.

The API versioning and software versioning are indirectly related. The API and release versioning proposal describes the relationship between API versioning and software versioning.

Different API versions indicate different levels of stability and support. You can find more information about the criteria for each level in the API Changes documentation.

Here's a summary of each level:

The version names contain beta (for example, v2beta3).

Built-in beta API versions are disabled by default and must be explicitly enabled in the kube-apiserver configuration to be used (except for beta versions of APIs introduced prior to Kubernetes 1.22, which were enabled by default).

Built-in beta API versions have a maximum lifetime of 9 months or 3 minor releases (whichever is longer) from introduction to deprecation, and 9 months or 3 minor releases (whichever is longer) from deprecation to removal.

The software is well tested. Enabling a feature is considered safe.

The support for a feature will not be dropped, though the details may change.

The schema and/or semantics of objects may change in incompatible ways in a subsequent beta or stable API version. When this happens, migration instructions are provided. Adapting to a subsequent beta or stable API version may require editing or re-creating API objects, and may not be straightforward. The migration may require downtime for applications that rely on the feature.

The software is not recommended for production uses. Subsequent releases may introduce incompatible changes. Use of beta API versions is required to transition to subsequent beta or stable API versions once the beta API version is deprecated and no longer served.

API

*[Content truncated]*

---

## Service Accounts

**URL:** https://kubernetes.io/docs/concepts/security/service-accounts/

**Contents:**
- Service Accounts
- What are service accounts?
  - Default service accounts
- Use cases for Kubernetes service accounts
- How to use service accounts
  - Grant permissions to a ServiceAccount
    - Cross-namespace access using a ServiceAccount
  - Assign a ServiceAccount to a Pod
    - Manually retrieve ServiceAccount credentials
    - Note:

This page introduces the ServiceAccount object in Kubernetes, providing information about how service accounts work, use cases, limitations, alternatives, and links to resources for additional guidance.

A service account is a type of non-human account that, in Kubernetes, provides a distinct identity in a Kubernetes cluster. Application Pods, system components, and entities inside and outside the cluster can use a specific ServiceAccount's credentials to identify as that ServiceAccount. This identity is useful in various situations, including authenticating to the API server or implementing identity-based security policies.

Service accounts exist as ServiceAccount objects in the API server. Service accounts have the following properties:

Namespaced: Each service account is bound to a Kubernetes namespace. Every namespace gets a default ServiceAccount upon creation.

Lightweight: Service accounts exist in the cluster and are defined in the Kubernetes API. You can quickly create service accounts to enable specific tasks.

Portable: A configuration bundle for a complex containerized workload might include service account definitions for the system's components. The lightweight nature of service accounts and the namespaced identities make the configurations portable.

Service accounts are different from user accounts, which are authenticated human users in the cluster. By default, user accounts don't exist in the Kubernetes API server; instead, the API server treats user identities as opaque data. You can authenticate as a user account using multiple methods. Some Kubernetes distributions might add custom extension APIs to represent user accounts in the API server.

When you create a cluster, Kubernetes automatically creates a ServiceAccount object named default for every namespace in your cluster. The default service accounts in each namespace get no permissions by default other than the default API discovery permissions that Kubernetes grants to all authenticated principals if role-based access control (RBAC) is enabled. If you delete the default ServiceAccount object in a namespace, the control plane replaces it with a new one.

If you deploy a Pod in a namespace, and you don't manually assign a ServiceAccount to the Pod, Kubernetes assigns the default ServiceAccount for that namespace to the Pod.

As a general guideline, you can use service accounts to provide identities in the following scenarios:

To use a Kubernetes service account, you do the follow

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    kubernetes.io/enforce-mountable-secrets: "true"
  name: my-serviceaccount
  namespace: my-namespace
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## Automatic Cleanup for Finished Jobs

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/ttlafterfinished/

**Contents:**
- Automatic Cleanup for Finished Jobs
- Cleanup for finished Jobs
- Caveats
  - Updating TTL for finished Jobs
  - Time skew
- What's next
- Feedback

When your Job has finished, it's useful to keep that Job in the API (and not immediately delete the Job) so that you can tell whether the Job succeeded or failed.

Kubernetes' TTL-after-finished controller provides a TTL (time to live) mechanism to limit the lifetime of Job objects that have finished execution.

The TTL-after-finished controller is only supported for Jobs. You can use this mechanism to clean up finished Jobs (either Complete or Failed) automatically by specifying the .spec.ttlSecondsAfterFinished field of a Job, as in this example.

The TTL-after-finished controller assumes that a Job is eligible to be cleaned up TTL seconds after the Job has finished. The timer starts once the status condition of the Job changes to show that the Job is either Complete or Failed; once the TTL has expired, that Job becomes eligible for cascading removal. When the TTL-after-finished controller cleans up a job, it will delete it cascadingly, that is to say it will delete its dependent objects together with it.

Kubernetes honors object lifecycle guarantees on the Job, such as waiting for finalizers.

You can set the TTL seconds at any time. Here are some examples for setting the .spec.ttlSecondsAfterFinished field of a Job:

You can modify the TTL period, e.g. .spec.ttlSecondsAfterFinished field of Jobs, after the job is created or has finished. If you extend the TTL period after the existing ttlSecondsAfterFinished period has expired, Kubernetes doesn't guarantee to retain that Job, even if an update to extend the TTL returns a successful API response.

Because the TTL-after-finished controller uses timestamps stored in the Kubernetes jobs to determine whether the TTL has expired or not, this feature is sensitive to time skew in your cluster, which may cause the control plane to clean up Job objects at the wrong time.

Clocks aren't always correct, but the difference should be very small. Please be aware of this risk when setting a non-zero TTL.

Read Clean up Jobs automatically

Refer to the Kubernetes Enhancement Proposal (KEP) for adding this mechanism.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Taints and Tolerations

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/

**Contents:**
- Taints and Tolerations
- Concepts
    - Note:
- Example Use Cases
- Taint based Evictions
    - Note:
    - Note:
    - Note:
- Taint Nodes by Condition
- Device taints and tolerations

Node affinity is a property of Pods that attracts them to a set of nodes (either as a preference or a hard requirement). Taints are the opposite -- they allow a node to repel a set of pods.

Tolerations are applied to pods. Tolerations allow the scheduler to schedule pods with matching taints. Tolerations allow scheduling but don't guarantee scheduling: the scheduler also evaluates other parameters as part of its function.

Taints and tolerations work together to ensure that pods are not scheduled onto inappropriate nodes. One or more taints are applied to a node; this marks that the node should not accept any pods that do not tolerate the taints.

You add a taint to a node using kubectl taint. For example,

places a taint on node node1. The taint has key key1, value value1, and taint effect NoSchedule. This means that no pod will be able to schedule onto node1 unless it has a matching toleration.

To remove the taint added by the command above, you can run:

You specify a toleration for a pod in the PodSpec. Both of the following tolerations "match" the taint created by the kubectl taint line above, and thus a pod with either toleration would be able to schedule onto node1:

The default Kubernetes scheduler takes taints and tolerations into account when selecting a node to run a particular Pod. However, if you manually specify the .spec.nodeName for a Pod, that action bypasses the scheduler; the Pod is then bound onto the node where you assigned it, even if there are NoSchedule taints on that node that you selected. If this happens and the node also has a NoExecute taint set, the kubelet will eject the Pod unless there is an appropriate tolerance set.

Here's an example of a pod that has some tolerations defined:

The default value for operator is Equal.

A toleration "matches" a taint if the keys are the same and the effects are the same, and:

There are two special cases:

If the key is empty, then the operator must be Exists, which matches all keys and values. Note that the effect still needs to be matched at the same time.

An empty effect matches all effects with key key1.

The above example used the effect of NoSchedule. Alternatively, you can use the effect of PreferNoSchedule.

The allowed values for the effect field are:

You can put multiple taints on the same node and multiple tolerations on the same pod. The way Kubernetes processes multiple taints and tolerations is like a filter: start with all of a node's taints, then ignore the ones for wh

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl taint nodes node1 key1=value1:NoSchedule
```

Example 2 (shell):
```shell
kubectl taint nodes node1 key1=value1:NoSchedule-
```

Example 3 (yaml):
```yaml
tolerations:
- key: "key1"
  operator: "Equal"
  value: "value1"
  effect: "NoSchedule"
```

Example 4 (yaml):
```yaml
tolerations:
- key: "key1"
  operator: "Exists"
  effect: "NoSchedule"
```

---

## Container Lifecycle Hooks

**URL:** https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/

**Contents:**
- Container Lifecycle Hooks
- Overview
- Container hooks
  - Hook handler implementations
  - Hook handler execution
  - Hook delivery guarantees
  - Debugging Hook handlers
- What's next
- Feedback

This page describes how kubelet managed Containers can use the Container lifecycle hook framework to run code triggered by events during their management lifecycle.

Analogous to many programming language frameworks that have component lifecycle hooks, such as Angular, Kubernetes provides Containers with lifecycle hooks. The hooks enable Containers to be aware of events in their management lifecycle and run code implemented in a handler when the corresponding lifecycle hook is executed.

There are two hooks that are exposed to Containers:

This hook is executed immediately after a container is created. However, there is no guarantee that the hook will execute before the container ENTRYPOINT. No parameters are passed to the handler.

This hook is called immediately before a container is terminated due to an API request or management event such as a liveness/startup probe failure, preemption, resource contention and others. A call to the PreStop hook fails if the container is already in a terminated or completed state and the hook must complete before the TERM signal to stop the container can be sent. The Pod's termination grace period countdown begins before the PreStop hook is executed, so regardless of the outcome of the handler, the container will eventually terminate within the Pod's termination grace period. No parameters are passed to the handler.

A more detailed description of the termination behavior can be found in Termination of Pods.

The StopSignal lifecycle can be used to define a stop signal which would be sent to the container when it is stopped. If you set this, it overrides any STOPSIGNAL instruction defined within the container image.

A more detailed description of termination behaviour with custom stop signals can be found in Stop Signals.

Containers can access a hook by implementing and registering a handler for that hook. There are three types of hook handlers that can be implemented for Containers:

When a Container lifecycle management hook is called, the Kubernetes management system executes the handler according to the hook action, httpGet, tcpSocket (deprecated) and sleep are executed by the kubelet process, and exec is executed in the container.

The PostStart hook handler call is initiated when a container is created, meaning the container ENTRYPOINT and the PostStart hook are triggered simultaneously. However, if the PostStart hook takes too long to execute or if it hangs, it can prevent the container from transitioning to a 

*[Content truncated]*

**Examples:**

Example 1 (javascript):
```javascript
Events:
  Type     Reason               Age              From               Message
  ----     ------               ----             ----               -------
  Normal   Scheduled            7s               default-scheduler  Successfully assigned default/lifecycle-demo to ip-XXX-XXX-XX-XX.us-east-2...
  Normal   Pulled               6s               kubelet            Successfully pulled image "nginx" in 229.604315ms
  Normal   Pulling              4s (x2 over 6s)  kubelet            Pulling image "nginx"
  Normal   Created              4s (x2 over 5s)  kubelet            Created container 
...
```

---

## Annotations

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/

**Contents:**
- Annotations
- Attaching metadata to objects
    - Note:
- Syntax and character set
- What's next
- Feedback

You can use Kubernetes annotations to attach arbitrary non-identifying metadata to objects. Clients such as tools and libraries can retrieve this metadata.

You can use either labels or annotations to attach metadata to Kubernetes objects. Labels can be used to select objects and to find collections of objects that satisfy certain conditions. In contrast, annotations are not used to identify and select objects. The metadata in an annotation can be small or large, structured or unstructured, and can include characters not permitted by labels. It is possible to use labels as well as annotations in the metadata of the same object.

Annotations, like labels, are key/value maps:

Here are some examples of information that could be recorded in annotations:

Fields managed by a declarative configuration layer. Attaching these fields as annotations distinguishes them from default values set by clients or servers, and from auto-generated fields and fields set by auto-sizing or auto-scaling systems.

Build, release, or image information like timestamps, release IDs, git branch, PR numbers, image hashes, and registry address.

Pointers to logging, monitoring, analytics, or audit repositories.

Client library or tool information that can be used for debugging purposes: for example, name, version, and build information.

User or tool/system provenance information, such as URLs of related objects from other ecosystem components.

Lightweight rollout tool metadata: for example, config or checkpoints.

Phone or pager numbers of persons responsible, or directory entries that specify where that information can be found, such as a team web site.

Directives from the end-user to the implementations to modify behavior or engage non-standard features.

Instead of using annotations, you could store this type of information in an external database or directory, but that would make it much harder to produce shared client libraries and tools for deployment, management, introspection, and the like.

Annotations are key/value pairs. Valid annotation keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, f

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "annotations": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: annotations-demo
  annotations:
    imageregistry: "https://hub.docker.com/"
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Ingress Controllers

**URL:** https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/

**Contents:**
- Ingress Controllers
- Additional controllers
- Using multiple Ingress controllers
    - Note:
- What's next
- Feedback

In order for the Ingress resource to work, the cluster must have an ingress controller running.

Unlike other types of controllers which run as part of the kube-controller-manager binary, Ingress controllers are not started automatically with a cluster. Use this page to choose the ingress controller implementation that best fits your cluster.

Kubernetes as a project supports and maintains AWS, GCE, and nginx ingress controllers.

You may deploy any number of ingress controllers using ingress class within a cluster. Note the .metadata.name of your ingress class resource. When you create an ingress you would need that name to specify the ingressClassName field on your Ingress object (refer to IngressSpec v1 reference). ingressClassName is a replacement of the older annotation method.

If you do not specify an IngressClass for an Ingress, and your cluster has exactly one IngressClass marked as default, then Kubernetes applies the cluster's default IngressClass to the Ingress. You mark an IngressClass as default by setting the ingressclass.kubernetes.io/is-default-class annotation on that IngressClass, with the string value "true".

Ideally, all ingress controllers should fulfill this specification, but the various ingress controllers operate slightly differently.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Deployments

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

**Contents:**
- Deployments
    - Note:
- Use Case
- Creating a Deployment
    - Note:
    - Note:
  - Pod-template-hash label
    - Caution:
- Updating a Deployment
    - Note:

A Deployment provides declarative updates for Pods and ReplicaSets.

You describe a desired state in a Deployment, and the Deployment Controller changes the actual state to the desired state at a controlled rate. You can define Deployments to create new ReplicaSets, or to remove existing Deployments and adopt all their resources with new Deployments.

The following are typical use cases for Deployments:

The following is an example of a Deployment. It creates a ReplicaSet to bring up three nginx Pods:

A Deployment named nginx-deployment is created, indicated by the .metadata.name field. This name will become the basis for the ReplicaSets and Pods which are created later. See Writing a Deployment Spec for more details.

The Deployment creates a ReplicaSet that creates three replicated Pods, indicated by the .spec.replicas field.

The .spec.selector field defines how the created ReplicaSet finds which Pods to manage. In this case, you select a label that is defined in the Pod template (app: nginx). However, more sophisticated selection rules are possible, as long as the Pod template itself satisfies the rule.

The .spec.template field contains the following sub-fields:

Before you begin, make sure your Kubernetes cluster is up and running. Follow the steps given below to create the above Deployment:

Create the Deployment by running the following command:

Run kubectl get deployments to check if the Deployment was created.

If the Deployment is still being created, the output is similar to the following:

When you inspect the Deployments in your cluster, the following fields are displayed:

Notice how the number of desired replicas is 3 according to .spec.replicas field.

To see the Deployment rollout status, run kubectl rollout status deployment/nginx-deployment.

The output is similar to:

Run the kubectl get deployments again a few seconds later. The output is similar to this:

Notice that the Deployment has created all three replicas, and all replicas are up-to-date (they contain the latest Pod template) and available.

To see the ReplicaSet (rs) created by the Deployment, run kubectl get rs. The output is similar to this:

ReplicaSet output shows the following fields:

Notice that the name of the ReplicaSet is always formatted as [DEPLOYMENT-NAME]-[HASH]. This name will become the basis for the Pods which are created.

The HASH string is the same as the pod-template-hash label on the ReplicaSet.

To see the labels automatically generated for each Pod, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
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
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml
```

Example 3 (unknown):
```unknown
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   0/3     0            0           1s
```

Example 4 (unknown):
```unknown
Waiting for rollout to finish: 2 out of 3 new replicas have been updated...
deployment "nginx-deployment" successfully rolled out
```

---

## Security Checklist

**URL:** https://kubernetes.io/docs/concepts/security/security-checklist/

**Contents:**
- Security Checklist
    - Caution:
- Authentication & Authorization
- Network security
- Pod security
    - Caution:
  - Enabling Seccomp
    - Note:
  - Enabling AppArmor or SELinux
    - AppArmor

This checklist aims at providing a basic list of guidance with links to more comprehensive documentation on each topic. It does not claim to be exhaustive and is meant to evolve.

On how to read and use this document:

After bootstrapping, neither users nor components should authenticate to the Kubernetes API as system:masters. Similarly, running all of kube-controller-manager as system:masters should be avoided. In fact, system:masters should only be used as a break-glass mechanism, as opposed to an admin user.

A number of Container Network Interface (CNI) plugins plugins provide the functionality to restrict network resources that pods may communicate with. This is most commonly done through Network Policies which provide a namespaced resource to define rules. Default network policies that block all egress and ingress, in each namespace, selecting all pods, can be useful to adopt an allow list approach to ensure that no workloads are missed.

Not all CNI plugins provide encryption in transit. If the chosen plugin lacks this feature, an alternative solution could be to use a service mesh to provide that functionality.

The etcd datastore of the control plane should have controls to limit access and not be publicly exposed on the Internet. Furthermore, mutual TLS (mTLS) should be used to communicate securely with it. The certificate authority for this should be unique to etcd.

External Internet access to the Kubernetes API server should be restricted to not expose the API publicly. Be careful, as many managed Kubernetes distributions are publicly exposing the API server by default. You can then use a bastion host to access the server.

The kubelet API access should be restricted and not exposed publicly, the default authentication and authorization settings, when no configuration file specified with the --config flag, are overly permissive.

If a cloud provider is used for hosting Kubernetes, the access from pods to the cloud metadata API 169.254.169.254 should also be restricted or blocked if not needed because it may leak information.

For restricted LoadBalancer and ExternalIPs use, see CVE-2020-8554: Man in the middle using LoadBalancer or ExternalIPs and the DenyServiceExternalIPs admission controller for further information.

RBAC authorization is crucial but cannot be granular enough to have authorization on the Pods' resources (or on any resource that manages Pods). The only granularity is the API verbs on the resource itself, for example, create

*[Content truncated]*

---

## Traces For Kubernetes System Components

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/system-traces/

**Contents:**
- Traces For Kubernetes System Components
- Trace Collection
- Component traces
  - kube-apiserver traces
    - Enabling tracing in the kube-apiserver
  - kubelet traces
    - Enabling tracing in the kubelet
- Stability
- What's next
- Feedback

System component traces record the latency of and relationships between operations in the cluster.

Kubernetes components emit traces using the OpenTelemetry Protocol with the gRPC exporter and can be collected and routed to tracing backends using an OpenTelemetry Collector.

Kubernetes components have built-in gRPC exporters for OTLP to export traces, either with an OpenTelemetry Collector, or without an OpenTelemetry Collector.

For a complete guide to collecting traces and using the collector, see Getting Started with the OpenTelemetry Collector. However, there are a few things to note that are specific to Kubernetes components.

By default, Kubernetes components export traces using the grpc exporter for OTLP on the IANA OpenTelemetry port, 4317. As an example, if the collector is running as a sidecar to a Kubernetes component, the following receiver configuration will collect spans and log them to standard output:

To directly emit traces to a backend without utilizing a collector, specify the endpoint field in the Kubernetes tracing configuration file with the desired trace backend address. This method negates the need for a collector and simplifies the overall structure.

For trace backend header configuration, including authentication details, environment variables can be used with OTEL_EXPORTER_OTLP_HEADERS, see OTLP Exporter Configuration.

Additionally, for trace resource attribute configuration such as Kubernetes cluster name, namespace, Pod name, etc., environment variables can also be used with OTEL_RESOURCE_ATTRIBUTES, see OTLP Kubernetes Resource.

The kube-apiserver generates spans for incoming HTTP requests, and for outgoing requests to webhooks, etcd, and re-entrant requests. It propagates the W3C Trace Context with outgoing requests but does not make use of the trace context attached to incoming requests, as the kube-apiserver is often a public endpoint.

To enable tracing, provide the kube-apiserver with a tracing configuration file with --tracing-config-file=<path-to-config>. This is an example config that records spans for 1 in 10000 requests, and uses the default OpenTelemetry endpoint:

For more information about the TracingConfiguration struct, see API server config API (v1).

The kubelet CRI interface and authenticated http servers are instrumented to generate trace spans. As with the apiserver, the endpoint and sampling rate are configurable. Trace context propagation is also configured. A parent span's sampling decision is alway

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
receivers:
  otlp:
    protocols:
      grpc:
exporters:
  # Replace this exporter with the exporter for your backend
  exporters:
    debug:
      verbosity: detailed
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
```

Example 2 (yaml):
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: TracingConfiguration
# default value
#endpoint: localhost:4317
samplingRatePerMillion: 100
```

Example 3 (yaml):
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
tracing:
  # default value
  #endpoint: localhost:4317
  samplingRatePerMillion: 100
```

---

## Scheduling Framework

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/#queueinghint

**Contents:**
- Scheduling Framework
- Framework workflow
  - Scheduling cycle & binding cycle
- Interfaces
    - Scheduling framework extension points
  - PreEnqueue
  - EnqueueExtension
  - QueueingHint
  - QueueSort
  - PreFilter

The scheduling framework is a pluggable architecture for the Kubernetes scheduler. It consists of a set of "plugin" APIs that are compiled directly into the scheduler. These APIs allow most scheduling features to be implemented as plugins, while keeping the scheduling "core" lightweight and maintainable. Refer to the design proposal of the scheduling framework for more technical information on the design of the framework.

The Scheduling Framework defines a few extension points. Scheduler plugins register to be invoked at one or more extension points. Some of these plugins can change the scheduling decisions and some are informational only.

Each attempt to schedule one Pod is split into two phases, the scheduling cycle and the binding cycle.

The scheduling cycle selects a node for the Pod, and the binding cycle applies that decision to the cluster. Together, a scheduling cycle and binding cycle are referred to as a "scheduling context".

Scheduling cycles are run serially, while binding cycles may run concurrently.

A scheduling or binding cycle can be aborted if the Pod is determined to be unschedulable or if there is an internal error. The Pod will be returned to the queue and retried.

The following picture shows the scheduling context of a Pod and the interfaces that the scheduling framework exposes.

One plugin may implement multiple interfaces to perform more complex or stateful tasks.

Some interfaces match the scheduler extension points which can be configured through Scheduler Configuration.

These plugins are called prior to adding Pods to the internal active queue, where Pods are marked as ready for scheduling.

Only when all PreEnqueue plugins return Success, the Pod is allowed to enter the active queue. Otherwise, it's placed in the internal unschedulable Pods list, and doesn't get an Unschedulable condition.

For more details about how internal scheduler queues work, read Scheduling queue in kube-scheduler.

EnqueueExtension is the interface where the plugin can control whether to retry scheduling of Pods rejected by this plugin, based on changes in the cluster. Plugins that implement PreEnqueue, PreFilter, Filter, Reserve or Permit should implement this interface.

QueueingHint is a callback function for deciding whether a Pod can be requeued to the active queue or backoff queue. It's executed every time a certain kind of event or change happens in the cluster. When the QueueingHint finds that the event might make the Pod schedulable, the 

*[Content truncated]*

**Examples:**

Example 1 (go):
```go
func ScoreNode(_ *v1.pod, n *v1.Node) (int, error) {
    return getBlinkingLightCount(n)
}
```

Example 2 (go):
```go
func NormalizeScores(scores map[string]int) {
    highest := 0
    for _, score := range scores {
        highest = max(highest, score)
    }
    for node, score := range scores {
        scores[node] = score*NodeScoreMax/highest
    }
}
```

Example 3 (go):
```go
type Plugin interface {
    Name() string
}

type QueueSortPlugin interface {
    Plugin
    Less(*v1.pod, *v1.pod) bool
}

type PreFilterPlugin interface {
    Plugin
    PreFilter(context.Context, *framework.CycleState, *v1.pod) error
}

// ...
```

---

## The Kubernetes API

**URL:** https://kubernetes.io/docs/concepts/overview/kubernetes-api/#api-groups-and-versioning

**Contents:**
- The Kubernetes API
- Discovery API
  - Aggregated discovery
  - Unaggregated discovery
- OpenAPI interface definition
  - OpenAPI V2
    - Warning:
  - OpenAPI V3
  - Protobuf serialization
- Persistence

The core of Kubernetes' control plane is the API server. The API server exposes an HTTP API that lets end users, different parts of your cluster, and external components communicate with one another.

The Kubernetes API lets you query and manipulate the state of API objects in Kubernetes (for example: Pods, Namespaces, ConfigMaps, and Events).

Most operations can be performed through the kubectl command-line interface or other command-line tools, such as kubeadm, which in turn use the API. However, you can also access the API directly using REST calls. Kubernetes provides a set of client libraries for those looking to write applications using the Kubernetes API.

Each Kubernetes cluster publishes the specification of the APIs that the cluster serves. There are two mechanisms that Kubernetes uses to publish these API specifications; both are useful to enable automatic interoperability. For example, the kubectl tool fetches and caches the API specification for enabling command-line completion and other features. The two supported mechanisms are as follows:

The Discovery API provides information about the Kubernetes APIs: API names, resources, versions, and supported operations. This is a Kubernetes specific term as it is a separate API from the Kubernetes OpenAPI. It is intended to be a brief summary of the available resources and it does not detail specific schema for the resources. For reference about resource schemas, please refer to the OpenAPI document.

The Kubernetes OpenAPI Document provides (full) OpenAPI v2.0 and 3.0 schemas for all Kubernetes API endpoints. The OpenAPI v3 is the preferred method for accessing OpenAPI as it provides a more comprehensive and accurate view of the API. It includes all the available API paths, as well as all resources consumed and produced for every operations on every endpoints. It also includes any extensibility components that a cluster supports. The data is a complete specification and is significantly larger than that from the Discovery API.

Kubernetes publishes a list of all group versions and resources supported via the Discovery API. This includes the following for each resource:

The API is available in both aggregated and unaggregated form. The aggregated discovery serves two endpoints, while the unaggregated discovery serves a separate endpoint for each group version.

Kubernetes offers stable support for aggregated discovery, publishing all resources supported by a cluster through two endpoints (/api and

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
{
  "kind": "APIGroupList",
  "apiVersion": "v1",
  "groups": [
    {
      "name": "apiregistration.k8s.io",
      "versions": [
        {
          "groupVersion": "apiregistration.k8s.io/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apiregistration.k8s.io/v1",
        "version": "v1"
      }
    },
    {
      "name": "apps",
      "versions": [
        {
          "groupVersion": "apps/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apps/v1",
        "version": "v1"
      }
    }
...
```

Example 2 (yaml):
```yaml
{
    "paths": {
        ...,
        "api/v1": {
            "serverRelativeURL": "/openapi/v3/api/v1?hash=CC0E9BFD992D8C59AEC98A1E2336F899E8318D3CF4C68944C3DEC640AF5AB52D864AC50DAA8D145B3494F75FA3CFF939FCBDDA431DAD3CA79738B297795818CF"
        },
        "apis/admissionregistration.k8s.io/v1": {
            "serverRelativeURL": "/openapi/v3/apis/admissionregistration.k8s.io/v1?hash=E19CC93A116982CE5422FC42B590A8AFAD92CDE9AE4D59B5CAAD568F083AD07946E6CB5817531680BCE6E215C16973CD39003B0425F3477CFD854E89A9DB6597"
        },
        ....
    }
}
```

---

## ReplicaSet

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#pod-deletion-cost

**Contents:**
- ReplicaSet
- How a ReplicaSet works
- When to use a ReplicaSet
- Example
- Non-Template Pod acquisitions
- Writing a ReplicaSet manifest
  - Pod Template
  - Pod Selector
    - Note:
  - Replicas

A ReplicaSet's purpose is to maintain a stable set of replica Pods running at any given time. As such, it is often used to guarantee the availability of a specified number of identical Pods.

A ReplicaSet is defined with fields, including a selector that specifies how to identify Pods it can acquire, a number of replicas indicating how many Pods it should be maintaining, and a pod template specifying the data of new Pods it should create to meet the number of replicas criteria. A ReplicaSet then fulfills its purpose by creating and deleting Pods as needed to reach the desired number. When a ReplicaSet needs to create new Pods, it uses its Pod template.

A ReplicaSet is linked to its Pods via the Pods' metadata.ownerReferences field, which specifies what resource the current object is owned by. All Pods acquired by a ReplicaSet have their owning ReplicaSet's identifying information within their ownerReferences field. It's through this link that the ReplicaSet knows of the state of the Pods it is maintaining and plans accordingly.

A ReplicaSet identifies new Pods to acquire by using its selector. If there is a Pod that has no OwnerReference or the OwnerReference is not a Controller and it matches a ReplicaSet's selector, it will be immediately acquired by said ReplicaSet.

A ReplicaSet ensures that a specified number of pod replicas are running at any given time. However, a Deployment is a higher-level concept that manages ReplicaSets and provides declarative updates to Pods along with a lot of other useful features. Therefore, we recommend using Deployments instead of directly using ReplicaSets, unless you require custom update orchestration or don't require updates at all.

This actually means that you may never need to manipulate ReplicaSet objects: use a Deployment instead, and define your application in the spec section.

Saving this manifest into frontend.yaml and submitting it to a Kubernetes cluster will create the defined ReplicaSet and the Pods that it manages.

You can then get the current ReplicaSets deployed:

And see the frontend one you created:

You can also check on the state of the ReplicaSet:

And you will see output similar to:

And lastly you can check for the Pods brought up:

You should see Pod information similar to:

You can also verify that the owner reference of these pods is set to the frontend ReplicaSet. To do this, get the yaml of one of the Pods running:

The output will look similar to this, with the frontend ReplicaSet's in

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend
  labels:
    app: guestbook
    tier: frontend
spec:
  # modify replicas according to your case
  replicas: 3
  selector:
    matchLabels:
      tier: frontend
  template:
    metadata:
      labels:
        tier: frontend
    spec:
      containers:
      - name: php-redis
        image: us-docker.pkg.dev/google-samples/containers/gke/gb-frontend:v5
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/frontend.yaml
```

Example 3 (shell):
```shell
kubectl get rs
```

Example 4 (unknown):
```unknown
NAME       DESIRED   CURRENT   READY   AGE
frontend   3         3         3       6s
```

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#semantics-for-get-and-list

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Operator pattern

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/operator/

**Contents:**
- Operator pattern
- Motivation
- Operators in Kubernetes
- An example operator
- Deploying operators
- Using an operator
- Writing your own operator
- What's next
- Feedback

Operators are software extensions to Kubernetes that make use of custom resources to manage applications and their components. Operators follow Kubernetes principles, notably the control loop.

The operator pattern aims to capture the key aim of a human operator who is managing a service or set of services. Human operators who look after specific applications and services have deep knowledge of how the system ought to behave, how to deploy it, and how to react if there are problems.

People who run workloads on Kubernetes often like to use automation to take care of repeatable tasks. The operator pattern captures how you can write code to automate a task beyond what Kubernetes itself provides.

Kubernetes is designed for automation. Out of the box, you get lots of built-in automation from the core of Kubernetes. You can use Kubernetes to automate deploying and running workloads, and you can automate how Kubernetes does that.

Kubernetes' operator pattern concept lets you extend the cluster's behaviour without modifying the code of Kubernetes itself by linking controllers to one or more custom resources. Operators are clients of the Kubernetes API that act as controllers for a Custom Resource.

Some of the things that you can use an operator to automate include:

What might an operator look like in more detail? Here's an example:

The most common way to deploy an operator is to add the Custom Resource Definition and its associated Controller to your cluster. The Controller will normally run outside of the control plane, much as you would run any containerized application. For example, you can run the controller in your cluster as a Deployment.

Once you have an operator deployed, you'd use it by adding, modifying or deleting the kind of resource that the operator uses. Following the above example, you would set up a Deployment for the operator itself, and then:

…and that's it! The operator will take care of applying the changes as well as keeping the existing service in good shape.

If there isn't an operator in the ecosystem that implements the behavior you want, you can code your own.

You also implement an operator (that is, a Controller) using any language / runtime that can act as a client for the Kubernetes API.

Following are a few libraries and tools you can use to write your own cloud native operator.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get SampleDB                   # find configured databases

kubectl edit SampleDB/example-database # manually change some settings
```

---

## Secrets

**URL:** https://kubernetes.io/docs/concepts/configuration/secret/

**Contents:**
- Secrets
    - Caution:
- Uses for Secrets
  - Use case: dotfiles in a secret volume
    - Note:
  - Use case: Secret visible to one container in a Pod
  - Alternatives to Secrets
- Types of Secret
  - Opaque Secrets
  - ServiceAccount token Secrets

A Secret is an object that contains a small amount of sensitive data such as a password, a token, or a key. Such information might otherwise be put in a Pod specification or in a container image. Using a Secret means that you don't need to include confidential data in your application code.

Because Secrets can be created independently of the Pods that use them, there is less risk of the Secret (and its data) being exposed during the workflow of creating, viewing, and editing Pods. Kubernetes, and applications that run in your cluster, can also take additional precautions with Secrets, such as avoiding writing sensitive data to nonvolatile storage.

Secrets are similar to ConfigMaps but are specifically intended to hold confidential data.

Kubernetes Secrets are, by default, stored unencrypted in the API server's underlying data store (etcd). Anyone with API access can retrieve or modify a Secret, and so can anyone with access to etcd. Additionally, anyone who is authorized to create a Pod in a namespace can use that access to read any Secret in that namespace; this includes indirect access such as the ability to create a Deployment.

In order to safely use Secrets, take at least the following steps:

For more guidelines to manage and improve the security of your Secrets, refer to Good practices for Kubernetes Secrets.

See Information security for Secrets for more details.

You can use Secrets for purposes such as the following:

The Kubernetes control plane also uses Secrets; for example, bootstrap token Secrets are a mechanism to help automate node registration.

You can make your data "hidden" by defining a key that begins with a dot. This key represents a dotfile or "hidden" file. For example, when the following Secret is mounted into a volume, secret-volume, the volume will contain a single file, called .secret-file, and the dotfile-test-container will have this file present at the path /etc/secret-volume/.secret-file.

Consider a program that needs to handle HTTP requests, do some complex business logic, and then sign some messages with an HMAC. Because it has complex application logic, there might be an unnoticed remote file reading exploit in the server, which could expose the private key to an attacker.

This could be divided into two processes in two containers: a frontend container which handles user interaction and business logic, but which cannot see the private key; and a signer container that can see the private key, and responds to simple 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dotfile-secret
data:
  .secret-file: dmFsdWUtMg0KDQo=
---
apiVersion: v1
kind: Pod
metadata:
  name: secret-dotfiles-pod
spec:
  volumes:
    - name: secret-volume
      secret:
        secretName: dotfile-secret
  containers:
    - name: dotfile-test-container
      image: registry.k8s.io/busybox
      command:
        - ls
        - "-l"
        - "/etc/secret-volume"
      volumeMounts:
        - name: secret-volume
          readOnly: true
          mountPath: "/etc/secret-volume"
```

Example 2 (shell):
```shell
kubectl create secret generic empty-secret
kubectl get secret empty-secret
```

Example 3 (unknown):
```unknown
NAME           TYPE     DATA   AGE
empty-secret   Opaque   0      2m6s
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: secret-sa-sample
  annotations:
    kubernetes.io/service-account.name: "sa-name"
type: kubernetes.io/service-account-token
data:
  extra: YmFyCg==
```

---

## Storage Capacity

**URL:** https://kubernetes.io/docs/concepts/storage/storage-capacity/

**Contents:**
- Storage Capacity
- Before you begin
- API
- Scheduling
- Rescheduling
- Limitations
- What's next
- Feedback

Storage capacity is limited and may vary depending on the node on which a pod runs: network-attached storage might not be accessible by all nodes, or storage is local to a node to begin with.

This page describes how Kubernetes keeps track of storage capacity and how the scheduler uses that information to schedule Pods onto nodes that have access to enough storage capacity for the remaining missing volumes. Without storage capacity tracking, the scheduler may choose a node that doesn't have enough capacity to provision a volume and multiple scheduling retries will be needed.

Kubernetes v1.34 includes cluster-level API support for storage capacity tracking. To use this you must also be using a CSI driver that supports capacity tracking. Consult the documentation for the CSI drivers that you use to find out whether this support is available and, if so, how to use it. If you are not running Kubernetes v1.34, check the documentation for that version of Kubernetes.

There are two API extensions for this feature:

Storage capacity information is used by the Kubernetes scheduler if:

In that case, the scheduler only considers nodes for the Pod which have enough storage available to them. This check is very simplistic and only compares the size of the volume against the capacity listed in CSIStorageCapacity objects with a topology that includes the node.

For volumes with Immediate volume binding mode, the storage driver decides where to create the volume, independently of Pods that will use the volume. The scheduler then schedules Pods onto nodes where the volume is available after the volume has been created.

For CSI ephemeral volumes, scheduling always happens without considering storage capacity. This is based on the assumption that this volume type is only used by special CSI drivers which are local to a node and do not need significant resources there.

When a node has been selected for a Pod with WaitForFirstConsumer volumes, that decision is still tentative. The next step is that the CSI storage driver gets asked to create the volume with a hint that the volume is supposed to be available on the selected node.

Because Kubernetes might have chosen a node based on out-dated capacity information, it is possible that the volume cannot really be created. The node selection is then reset and the Kubernetes scheduler tries again to find a node for the Pod.

Storage capacity tracking increases the chance that scheduling works on the first try, but cannot guaran

*[Content truncated]*

---

## Security For Linux Nodes

**URL:** https://kubernetes.io/docs/concepts/security/linux-security/

**Contents:**
- Security For Linux Nodes
- Protection for Secret data on nodes
- Feedback

This page describes security considerations and best practices specific to the Linux operating system.

On Linux nodes, memory-backed volumes (such as secret volume mounts, or emptyDir with medium: Memory) are implemented with a tmpfs filesystem.

If you have swap configured and use an older Linux kernel (or a current kernel and an unsupported configuration of Kubernetes), memory backed volumes can have data written to persistent storage.

The Linux kernel officially supports the noswap option from version 6.3, therefore it is recommended the used kernel version is 6.3 or later, or supports the noswap option via a backport, if swap is enabled on the node.

Read swap memory management for more info.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Annotations

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations

**Contents:**
- Annotations
- Attaching metadata to objects
    - Note:
- Syntax and character set
- What's next
- Feedback

You can use Kubernetes annotations to attach arbitrary non-identifying metadata to objects. Clients such as tools and libraries can retrieve this metadata.

You can use either labels or annotations to attach metadata to Kubernetes objects. Labels can be used to select objects and to find collections of objects that satisfy certain conditions. In contrast, annotations are not used to identify and select objects. The metadata in an annotation can be small or large, structured or unstructured, and can include characters not permitted by labels. It is possible to use labels as well as annotations in the metadata of the same object.

Annotations, like labels, are key/value maps:

Here are some examples of information that could be recorded in annotations:

Fields managed by a declarative configuration layer. Attaching these fields as annotations distinguishes them from default values set by clients or servers, and from auto-generated fields and fields set by auto-sizing or auto-scaling systems.

Build, release, or image information like timestamps, release IDs, git branch, PR numbers, image hashes, and registry address.

Pointers to logging, monitoring, analytics, or audit repositories.

Client library or tool information that can be used for debugging purposes: for example, name, version, and build information.

User or tool/system provenance information, such as URLs of related objects from other ecosystem components.

Lightweight rollout tool metadata: for example, config or checkpoints.

Phone or pager numbers of persons responsible, or directory entries that specify where that information can be found, such as a team web site.

Directives from the end-user to the implementations to modify behavior or engage non-standard features.

Instead of using annotations, you could store this type of information in an external database or directory, but that would make it much harder to produce shared client libraries and tools for deployment, management, introspection, and the like.

Annotations are key/value pairs. Valid annotation keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, f

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "annotations": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: annotations-demo
  annotations:
    imageregistry: "https://hub.docker.com/"
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/#mount-options

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## Topology Aware Routing

**URL:** https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/

**Contents:**
- Topology Aware Routing
    - Note:
- Motivation
- Enabling Topology Aware Routing
    - Note:
- When it works best
  - 1. Incoming traffic is evenly distributed
  - 2. The Service has 3 or more endpoints per zone
- How It Works
  - EndpointSlice controller

Topology Aware Routing adjusts routing behavior to prefer keeping traffic in the zone it originated from. In some cases this can help reduce costs or improve network performance.

Kubernetes clusters are increasingly deployed in multi-zone environments. Topology Aware Routing provides a mechanism to help keep traffic within the zone it originated from. When calculating the endpoints for a Service, the EndpointSlice controller considers the topology (region and zone) of each endpoint and populates the hints field to allocate it to a zone. Cluster components such as kube-proxy can then consume those hints, and use them to influence how the traffic is routed (favoring topologically closer endpoints).

You can enable Topology Aware Routing for a Service by setting the service.kubernetes.io/topology-mode annotation to Auto. When there are enough endpoints available in each zone, Topology Hints will be populated on EndpointSlices to allocate individual endpoints to specific zones, resulting in traffic being routed closer to where it originated from.

This feature works best when:

If a large proportion of traffic is originating from a single zone, that traffic could overload the subset of endpoints that have been allocated to that zone. This feature is not recommended when incoming traffic is expected to originate from a single zone.

In a three zone cluster, this means 9 or more endpoints. If there are fewer than 3 endpoints per zone, there is a high (≈50%) probability that the EndpointSlice controller will not be able to allocate endpoints evenly and instead will fall back to the default cluster-wide routing approach.

The "Auto" heuristic attempts to proportionally allocate a number of endpoints to each zone. Note that this heuristic works best for Services that have a significant number of endpoints.

The EndpointSlice controller is responsible for setting hints on EndpointSlices when this heuristic is enabled. The controller allocates a proportional amount of endpoints to each zone. This proportion is based on the allocatable CPU cores for nodes running in that zone. For example, if one zone had 2 CPU cores and another zone only had 1 CPU core, the controller would allocate twice as many endpoints to the zone with 2 CPU cores.

The following example shows what an EndpointSlice looks like when hints have been populated:

The kube-proxy component filters the endpoints it routes to based on the hints set by the EndpointSlice controller. In most cases, this mea

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: example-hints
  labels:
    kubernetes.io/service-name: example-svc
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 80
endpoints:
  - addresses:
      - "10.1.2.3"
    conditions:
      ready: true
    hostname: pod-1
    zone: zone-a
    hints:
      forZones:
        - name: "zone-a"
```

---

## Pod Security Policies

**URL:** https://kubernetes.io/docs/concepts/security/pod-security-policy/

**Contents:**
- Pod Security Policies
    - Removed feature
- Feedback

Instead of using PodSecurityPolicy, you can enforce similar restrictions on Pods using either or both:

For a migration guide, see Migrate from PodSecurityPolicy to the Built-In PodSecurity Admission Controller. For more information on the removal of this API, see PodSecurityPolicy Deprecation: Past, Present, and Future.

If you are not running Kubernetes v1.34, check the documentation for your version of Kubernetes.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Recommended Labels

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/

**Contents:**
- Recommended Labels
    - Note:
- Labels
- Applications And Instances Of Applications
- Examples
  - A Simple Stateless Service
  - Web Application With A Database
- Feedback

You can visualize and manage Kubernetes objects with more tools than kubectl and the dashboard. A common set of labels allows tools to work interoperably, describing objects in a common manner that all tools can understand.

In addition to supporting tooling, the recommended labels describe applications in a way that can be queried.

The metadata is organized around the concept of an application. Kubernetes is not a platform as a service (PaaS) and doesn't have or enforce a formal notion of an application. Instead, applications are informal and described with metadata. The definition of what an application contains is loose.

Shared labels and annotations share a common prefix: app.kubernetes.io. Labels without a prefix are private to users. The shared prefix ensures that shared labels do not interfere with custom user labels.

In order to take full advantage of using these labels, they should be applied on every resource object.

To illustrate these labels in action, consider the following StatefulSet object:

An application can be installed one or more times into a Kubernetes cluster and, in some cases, the same namespace. For example, WordPress can be installed more than once where different websites are different installations of WordPress.

The name of an application and the instance name are recorded separately. For example, WordPress has a app.kubernetes.io/name of wordpress while it has an instance name, represented as app.kubernetes.io/instance with a value of wordpress-abcxyz. This enables the application and instance of the application to be identifiable. Every instance of an application must have a unique name.

To illustrate different ways to use these labels the following examples have varying complexity.

Consider the case for a simple stateless service deployed using Deployment and Service objects. The following two snippets represent how the labels could be used in their simplest form.

The Deployment is used to oversee the pods running the application itself.

The Service is used to expose the application.

Consider a slightly more complicated application: a web application (WordPress) using a database (MySQL), installed using Helm. The following snippets illustrate the start of objects used to deploy this application.

The start to the following Deployment is used for WordPress:

The Service is used to expose WordPress:

MySQL is exposed as a StatefulSet with metadata for both it and the larger application it belongs to:

The Service is 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# This is an excerpt
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app.kubernetes.io/name: mysql
    app.kubernetes.io/instance: mysql-abcxyz
    app.kubernetes.io/version: "5.7.21"
    app.kubernetes.io/component: database
    app.kubernetes.io/part-of: wordpress
    app.kubernetes.io/managed-by: Helm
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: myservice
    app.kubernetes.io/instance: myservice-abcxyz
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: myservice
    app.kubernetes.io/instance: myservice-abcxyz
...
```

Example 4 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: wordpress
    app.kubernetes.io/instance: wordpress-abcxyz
    app.kubernetes.io/version: "4.9.4"
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/component: server
    app.kubernetes.io/part-of: wordpress
...
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#etcd

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Storage

**URL:** https://kubernetes.io/docs/concepts/storage/

**Contents:**
- Storage
      - Volumes
      - Persistent Volumes
      - Projected Volumes
      - Ephemeral Volumes
      - Storage Classes
      - Volume Attributes Classes
      - Dynamic Volume Provisioning
      - Volume Snapshots
      - Volume Snapshot Classes

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#web-ui-dashboard

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Windows in Kubernetes

**URL:** https://kubernetes.io/docs/concepts/windows/#third-party-content-disclaimer

**Contents:**
- Windows in Kubernetes
- Feedback

Kubernetes supports worker nodes running either Linux or Microsoft Windows.

The CNCF and its parent the Linux Foundation take a vendor-neutral approach towards compatibility. It is possible to join your Windows server as a worker node to a Kubernetes cluster.

You can install and set up kubectl on Windows no matter what operating system you use within your cluster.

If you are using Windows nodes, you can read:

or, for an overview, read:

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Node Autoscaling

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/

**Contents:**
- Node Autoscaling
- Node provisioning
    - Note:
  - Pod scheduling constraints
  - Node constraints imposed by autoscaler configuration
  - Auto-provisioning
- Node consolidation
    - Note:
    - Note:
    - Note:

In order to run workloads in your cluster, you need Nodes. Nodes in your cluster can be autoscaled - dynamically provisioned, or consolidated to provide needed capacity while optimizing cost. Autoscaling is performed by Node autoscalers.

If there are Pods in a cluster that can't be scheduled on existing Nodes, new Nodes can be automatically added to the cluster—provisioned—to accommodate the Pods. This is especially useful if the number of Pods changes over time, for example as a result of combining horizontal workload with Node autoscaling.

Autoscalers provision the Nodes by creating and deleting cloud provider resources backing them. Most commonly, the resources backing the Nodes are Virtual Machines.

The main goal of provisioning is to make all Pods schedulable. This goal is not always attainable because of various limitations, including reaching configured provisioning limits, provisioning configuration not being compatible with a particular set of pods, or the lack of cloud provider capacity. While provisioning, Node autoscalers often try to achieve additional goals (for example minimizing the cost of the provisioned Nodes or balancing the number of Nodes between failure domains).

There are two main inputs to a Node autoscaler when determining Nodes to provision—Pod scheduling constraints, and Node constraints imposed by autoscaler configuration.

Autoscaler configuration may also include other Node provisioning triggers (for example the number of Nodes falling below a configured minimum limit).

Pods can express scheduling constraints to impose limitations on the kind of Nodes they can be scheduled on. Node autoscalers take these constraints into account to ensure that the pending Pods can be scheduled on the provisioned Nodes.

The most common kind of scheduling constraints are the resource requests specified by Pod containers. Autoscalers will make sure that the provisioned Nodes have enough resources to satisfy the requests. However, they don't directly take into account the real resource usage of the Pods after they start running. In order to autoscale Nodes based on actual workload resource usage, you can combine horizontal workload autoscaling with Node autoscaling.

Other common Pod scheduling constraints include Node affinity, inter-Pod affinity, or a requirement for a particular storage volume.

The specifics of the provisioned Nodes (for example the amount of resources, the presence of a given label) depend on autoscaler configuration. 

*[Content truncated]*

---

## Containers

**URL:** https://kubernetes.io/docs/concepts/containers/

**Contents:**
- Containers
- Container images
- Container runtimes
      - Container Environment
      - Container Lifecycle Hooks
- Feedback

This page will discuss containers and container images, as well as their use in operations and solution development.

The word container is an overloaded term. Whenever you use the word, check whether your audience uses the same definition.

Each container that you run is repeatable; the standardization from having dependencies included means that you get the same behavior wherever you run it.

Containers decouple applications from the underlying host infrastructure. This makes deployment easier in different cloud or OS environments.

Each node in a Kubernetes cluster runs the containers that form the Pods assigned to that node. Containers in a Pod are co-located and co-scheduled to run on the same node.

A container image is a ready-to-run software package containing everything needed to run an application: the code and any runtime it requires, application and system libraries, and default values for any essential settings.

Containers are intended to be stateless and immutable: you should not change the code of a container that is already running. If you have a containerized application and want to make changes, the correct process is to build a new image that includes the change, then recreate the container to start from the updated image.

A fundamental component that empowers Kubernetes to run containers effectively. It is responsible for managing the execution and lifecycle of containers within the Kubernetes environment.

Kubernetes supports container runtimes such as containerd, CRI-O, and any other implementation of the Kubernetes CRI (Container Runtime Interface).

Usually, you can allow your cluster to pick the default container runtime for a Pod. If you need to use more than one container runtime in your cluster, you can specify the RuntimeClass for a Pod to make sure that Kubernetes runs those containers using a particular container runtime.

You can also use RuntimeClass to run different Pods with the same container runtime but with different settings.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Scheduler Performance Tuning

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/scheduler-perf-tuning/

**Contents:**
- Scheduler Performance Tuning
  - Setting the threshold
- Node scoring threshold
  - Default threshold
- Example
- Tuning percentageOfNodesToScore
    - Note:
- How the scheduler iterates over Nodes
- What's next
- Feedback

kube-scheduler is the Kubernetes default scheduler. It is responsible for placement of Pods on Nodes in a cluster.

Nodes in a cluster that meet the scheduling requirements of a Pod are called feasible Nodes for the Pod. The scheduler finds feasible Nodes for a Pod and then runs a set of functions to score the feasible Nodes, picking a Node with the highest score among the feasible ones to run the Pod. The scheduler then notifies the API server about this decision in a process called Binding.

This page explains performance tuning optimizations that are relevant for large Kubernetes clusters.

In large clusters, you can tune the scheduler's behaviour balancing scheduling outcomes between latency (new Pods are placed quickly) and accuracy (the scheduler rarely makes poor placement decisions).

You configure this tuning setting via kube-scheduler setting percentageOfNodesToScore. This KubeSchedulerConfiguration setting determines a threshold for scheduling nodes in your cluster.

The percentageOfNodesToScore option accepts whole numeric values between 0 and 100. The value 0 is a special number which indicates that the kube-scheduler should use its compiled-in default. If you set percentageOfNodesToScore above 100, kube-scheduler acts as if you had set a value of 100.

To change the value, edit the kube-scheduler configuration file and then restart the scheduler. In many cases, the configuration file can be found at /etc/kubernetes/config/kube-scheduler.yaml.

After you have made this change, you can run

to verify that the kube-scheduler component is healthy.

To improve scheduling performance, the kube-scheduler can stop looking for feasible nodes once it has found enough of them. In large clusters, this saves time compared to a naive approach that would consider every node.

You specify a threshold for how many nodes are enough, as a whole number percentage of all the nodes in your cluster. The kube-scheduler converts this into an integer number of nodes. During scheduling, if the kube-scheduler has identified enough feasible nodes to exceed the configured percentage, the kube-scheduler stops searching for more feasible nodes and moves on to the scoring phase.

How the scheduler iterates over Nodes describes the process in detail.

If you don't specify a threshold, Kubernetes calculates a figure using a linear formula that yields 50% for a 100-node cluster and yields 10% for a 5000-node cluster. The lower bound for the automatic value is 5%.

This means th

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
kubectl get pods -n kube-system | grep kube-scheduler
```

Example 2 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
algorithmSource:
  provider: DefaultProvider

...

percentageOfNodesToScore: 50
```

Example 3 (unknown):
```unknown
Zone 1: Node 1, Node 2, Node 3, Node 4
Zone 2: Node 5, Node 6
```

Example 4 (unknown):
```unknown
Node 1, Node 5, Node 2, Node 6, Node 3, Node 4
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Security

**URL:** https://kubernetes.io/docs/concepts/security/#third-party-content-disclaimer

**Contents:**
- Security
- Kubernetes security mechanisms
  - Control plane protection
  - Secrets
  - Workload protection
  - Admission control
  - Auditing
- Cloud provider security
- Policies
- What's next

This section of the Kubernetes documentation aims to help you learn to run workloads more securely, and about the essential aspects of keeping a Kubernetes cluster secure.

Kubernetes is based on a cloud-native architecture, and draws on advice from the CNCF about good practice for cloud native information security.

Read Cloud Native Security and Kubernetes for the broader context about how to secure your cluster and the applications that you're running on it.

Kubernetes includes several APIs and security controls, as well as ways to define policies that can form part of how you manage information security.

A key security mechanism for any Kubernetes cluster is to control access to the Kubernetes API.

Kubernetes expects you to configure and use TLS to provide data encryption in transit within the control plane, and between the control plane and its clients. You can also enable encryption at rest for the data stored within Kubernetes control plane; this is separate from using encryption at rest for your own workloads' data, which might also be a good idea.

The Secret API provides basic protection for configuration values that require confidentiality.

Enforce Pod security standards to ensure that Pods and their containers are isolated appropriately. You can also use RuntimeClasses to define custom isolation if you need it.

Network policies let you control network traffic between Pods, or between Pods and the network outside your cluster.

You can deploy security controls from the wider ecosystem to implement preventative or detective controls around Pods, their containers, and the images that run in them.

Admission controllers are plugins that intercept Kubernetes API requests and can validate or mutate the requests based on specific fields in the request. Thoughtfully designing these controllers helps to avoid unintended disruptions as Kubernetes APIs change across version updates. For design considerations, see Admission Webhook Good Practices.

Kubernetes audit logging provides a security-relevant, chronological set of records documenting the sequence of actions in a cluster. The cluster audits the activities generated by users, by applications that use the Kubernetes API, and by the control plane itself.

If you are running a Kubernetes cluster on your own hardware or a different cloud provider, consult your documentation for security best practices. Here are links to some of the popular cloud providers' security documentation:

You can define se

*[Content truncated]*

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#standard-api-terminology

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Installing Addons

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/addons/#networking-and-network-policy

**Contents:**
- Installing Addons
- Networking and Network Policy
- Service Discovery
- Visualization & Control
- Infrastructure
- Instrumentation
- Legacy Add-ons
- Feedback

Add-ons extend the functionality of Kubernetes.

This page lists some of the available add-ons and links to their respective installation instructions. The list does not try to be exhaustive.

There are several other add-ons documented in the deprecated cluster/addons directory.

Well-maintained ones should be linked to here. PRs welcome!

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Pod Scheduling Readiness

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/

**Contents:**
- Pod Scheduling Readiness
- Configuring Pod schedulingGates
- Usage example
- Observability
- Mutable Pod scheduling directives
- What's next
- Feedback

Pods were considered ready for scheduling once created. Kubernetes scheduler does its due diligence to find nodes to place all pending Pods. However, in a real-world case, some Pods may stay in a "miss-essential-resources" state for a long period. These Pods actually churn the scheduler (and downstream integrators like Cluster AutoScaler) in an unnecessary manner.

By specifying/removing a Pod's .spec.schedulingGates, you can control when a Pod is ready to be considered for scheduling.

The schedulingGates field contains a list of strings, and each string literal is perceived as a criteria that Pod should be satisfied before considered schedulable. This field can be initialized only when a Pod is created (either by the client, or mutated during admission). After creation, each schedulingGate can be removed in arbitrary order, but addition of a new scheduling gate is disallowed.

Figure. Pod SchedulingGates

To mark a Pod not-ready for scheduling, you can create it with one or more scheduling gates like this:

After the Pod's creation, you can check its state using:

The output reveals it's in SchedulingGated state:

You can also check its schedulingGates field by running:

To inform scheduler this Pod is ready for scheduling, you can remove its schedulingGates entirely by reapplying a modified manifest:

You can check if the schedulingGates is cleared by running:

The output is expected to be empty. And you can check its latest status by running:

Given the test-pod doesn't request any CPU/memory resources, it's expected that this Pod's state get transited from previous SchedulingGated to Running:

The metric scheduler_pending_pods comes with a new label "gated" to distinguish whether a Pod has been tried scheduling but claimed as unschedulable, or explicitly marked as not ready for scheduling. You can use scheduler_pending_pods{queue="gated"} to check the metric result.

You can mutate scheduling directives of Pods while they have scheduling gates, with certain constraints. At a high level, you can only tighten the scheduling directives of a Pod. In other words, the updated directives would cause the Pods to only be able to be scheduled on a subset of the nodes that it would previously match. More concretely, the rules for updating a Pod's scheduling directives are as follows:

For .spec.nodeSelector, only additions are allowed. If absent, it will be allowed to be set.

For spec.affinity.nodeAffinity, if nil, then setting anything is allowed.

If NodeSele

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  schedulingGates:
  - name: example.com/foo
  - name: example.com/bar
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.6
```

Example 2 (bash):
```bash
kubectl get pod test-pod
```

Example 3 (none):
```none
NAME       READY   STATUS            RESTARTS   AGE
test-pod   0/1     SchedulingGated   0          7s
```

Example 4 (bash):
```bash
kubectl get pod test-pod -o jsonpath='{.spec.schedulingGates}'
```

---

## Objects In Kubernetes

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/#kubernetes-objects

**Contents:**
- Objects In Kubernetes
- Understanding Kubernetes objects
  - Object spec and status
  - Describing a Kubernetes object
  - Required fields
    - Note:
- Server side field validation
- What's next
- Feedback

This page explains how Kubernetes objects are represented in the Kubernetes API, and how you can express them in .yaml format.

Kubernetes objects are persistent entities in the Kubernetes system. Kubernetes uses these entities to represent the state of your cluster. Specifically, they can describe:

A Kubernetes object is a "record of intent"--once you create the object, the Kubernetes system will constantly work to ensure that the object exists. By creating an object, you're effectively telling the Kubernetes system what you want your cluster's workload to look like; this is your cluster's desired state.

To work with Kubernetes objects—whether to create, modify, or delete them—you'll need to use the Kubernetes API. When you use the kubectl command-line interface, for example, the CLI makes the necessary Kubernetes API calls for you. You can also use the Kubernetes API directly in your own programs using one of the Client Libraries.

Almost every Kubernetes object includes two nested object fields that govern the object's configuration: the object spec and the object status. For objects that have a spec, you have to set this when you create the object, providing a description of the characteristics you want the resource to have: its desired state.

The status describes the current state of the object, supplied and updated by the Kubernetes system and its components. The Kubernetes control plane continually and actively manages every object's actual state to match the desired state you supplied.

For example: in Kubernetes, a Deployment is an object that can represent an application running on your cluster. When you create the Deployment, you might set the Deployment spec to specify that you want three replicas of the application to be running. The Kubernetes system reads the Deployment spec and starts three instances of your desired application--updating the status to match your spec. If any of those instances should fail (a status change), the Kubernetes system responds to the difference between spec and status by making a correction--in this case, starting a replacement instance.

For more information on the object spec, status, and metadata, see the Kubernetes API Conventions.

When you create an object in Kubernetes, you must provide the object spec that describes its desired state, as well as some basic information about the object (such as a name). When you use the Kubernetes API to create the object (either directly or via kubectl), that API reque

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

Example 3 (unknown):
```unknown
deployment.apps/nginx-deployment created
```

---

## Custom Resources

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/

**Contents:**
- Custom Resources
- Custom resources
- Custom controllers
- Should I add a custom resource to my Kubernetes cluster?
  - Declarative APIs
- Should I use a ConfigMap or a custom resource?
    - Note:
- Adding custom resources
    - Note:
- CustomResourceDefinitions

Custom resources are extensions of the Kubernetes API. This page discusses when to add a custom resource to your Kubernetes cluster and when to use a standalone service. It describes the two methods for adding custom resources and how to choose between them.

A resource is an endpoint in the Kubernetes API that stores a collection of API objects of a certain kind; for example, the built-in pods resource contains a collection of Pod objects.

A custom resource is an extension of the Kubernetes API that is not necessarily available in a default Kubernetes installation. It represents a customization of a particular Kubernetes installation. However, many core Kubernetes functions are now built using custom resources, making Kubernetes more modular.

Custom resources can appear and disappear in a running cluster through dynamic registration, and cluster admins can update custom resources independently of the cluster itself. Once a custom resource is installed, users can create and access its objects using kubectl, just as they do for built-in resources like Pods.

On their own, custom resources let you store and retrieve structured data. When you combine a custom resource with a custom controller, custom resources provide a true declarative API.

The Kubernetes declarative API enforces a separation of responsibilities. You declare the desired state of your resource. The Kubernetes controller keeps the current state of Kubernetes objects in sync with your declared desired state. This is in contrast to an imperative API, where you instruct a server what to do.

You can deploy and update a custom controller on a running cluster, independently of the cluster's lifecycle. Custom controllers can work with any kind of resource, but they are especially effective when combined with custom resources. The Operator pattern combines custom resources and custom controllers. You can use custom controllers to encode domain knowledge for specific applications into an extension of the Kubernetes API.

When creating a new API, consider whether to aggregate your API with the Kubernetes cluster APIs or let your API stand alone.

In a Declarative API, typically:

Imperative APIs are not declarative. Signs that your API might not be declarative include:

Use a ConfigMap if any of the following apply:

Use a custom resource (CRD or Aggregated API) if most of the following apply:

Kubernetes provides two ways to add custom resources to your cluster:

Kubernetes provides these two optio

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: shirts.stable.example.com
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: shirts
    singular: shirt
    kind: Shirt
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              color:
                type: string
              size:
                type: string
    selectableFields:
    - jsonPath: .spec.color
    - jsonPath: .spec
...
```

Example 2 (shell):
```shell
kubectl get shirts.stable.example.com --field-selector spec.color=blue
```

Example 3 (unknown):
```unknown
NAME       COLOR  SIZE
example1   blue   S
example2   blue   M
```

---

## Device Plugins

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/#monitoring-device-plugin-resources

**Contents:**
- Device Plugins
- Device plugin registration
  - Example
- Device plugin implementation
    - Note:
    - Note:
    - Note:
  - Handling kubelet restarts
  - Device plugin and unhealthy devices
- Device plugin deployment

Kubernetes provides a device plugin framework that you can use to advertise system hardware resources to the Kubelet.

Instead of customizing the code for Kubernetes itself, vendors can implement a device plugin that you deploy either manually or as a DaemonSet. The targeted devices include GPUs, high-performance NICs, FPGAs, InfiniBand adapters, and other similar computing resources that may require vendor specific initialization and setup.

The kubelet exports a Registration gRPC service:

A device plugin can register itself with the kubelet through this gRPC service. During the registration, the device plugin needs to send:

Following a successful registration, the device plugin sends the kubelet the list of devices it manages, and the kubelet is then in charge of advertising those resources to the API server as part of the kubelet node status update. For example, after a device plugin registers hardware-vendor.example/foo with the kubelet and reports two healthy devices on a node, the node status is updated to advertise that the node has 2 "Foo" devices installed and available.

Then, users can request devices as part of a Pod specification (see container). Requesting extended resources is similar to how you manage requests and limits for other resources, with the following differences:

Suppose a Kubernetes cluster is running a device plugin that advertises resource hardware-vendor.example/foo on certain nodes. Here is an example of a pod requesting this resource to run a demo workload:

The general workflow of a device plugin includes the following steps:

Initialization. During this phase, the device plugin performs vendor-specific initialization and setup to make sure the devices are in a ready state.

The plugin starts a gRPC service, with a Unix socket under the host path /var/lib/kubelet/device-plugins/, that implements the following interfaces:

The plugin registers itself with the kubelet through the Unix socket at host path /var/lib/kubelet/device-plugins/kubelet.sock.

After successfully registering itself, the device plugin runs in serving mode, during which it keeps monitoring device health and reports back to the kubelet upon any device state changes. It is also responsible for serving Allocate gRPC requests. During Allocate, the device plugin may do device-specific preparation; for example, GPU cleanup or QRNG initialization. If the operations succeed, the device plugin returns an AllocateResponse that contains container runtime configur

*[Content truncated]*

**Examples:**

Example 1 (gRPC):
```gRPC
service Registration {
	rpc Register(RegisterRequest) returns (Empty) {}
}
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: demo-pod
spec:
  containers:
    - name: demo-container-1
      image: registry.k8s.io/pause:3.8
      resources:
        limits:
          hardware-vendor.example/foo: 2
#
# This Pod needs 2 of the hardware-vendor.example/foo devices
# and can only schedule onto a Node that's able to satisfy
# that need.
#
# If the Node has more than 2 of those devices available, the
# remainder would be available for other Pods to use.
```

Example 3 (gRPC):
```gRPC
service DevicePlugin {
      // GetDevicePluginOptions returns options to be communicated with Device Manager.
      rpc GetDevicePluginOptions(Empty) returns (DevicePluginOptions) {}

      // ListAndWatch returns a stream of List of Devices
      // Whenever a Device state change or a Device disappears, ListAndWatch
      // returns the new list
      rpc ListAndWatch(Empty) returns (stream ListAndWatchResponse) {}

      // Allocate is called during container creation so that the Device
      // Plugin can run device specific operations and instruct Kubelet
      // of the steps to make the
...
```

Example 4 (gRPC):
```gRPC
// PodResourcesLister is a service provided by the kubelet that provides information about the
// node resources consumed by pods and containers on the node
service PodResourcesLister {
    rpc List(ListPodResourcesRequest) returns (ListPodResourcesResponse) {}
    rpc GetAllocatableResources(AllocatableResourcesRequest) returns (AllocatableResourcesResponse) {}
    rpc Get(GetPodResourcesRequest) returns (GetPodResourcesResponse) {}
}
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/#class

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## About cgroup v2

**URL:** https://kubernetes.io/docs/concepts/architecture/cgroups/

**Contents:**
- About cgroup v2
- What is cgroup v2?
- Using cgroup v2
  - Requirements
  - Linux Distribution cgroup v2 support
  - Migrating to cgroup v2
- Identify the cgroup version on Linux Nodes
- What's next
- Feedback

On Linux, control groups constrain resources that are allocated to processes.

The kubelet and the underlying container runtime need to interface with cgroups to enforce resource management for pods and containers which includes cpu/memory requests and limits for containerized workloads.

There are two versions of cgroups in Linux: cgroup v1 and cgroup v2. cgroup v2 is the new generation of the cgroup API.

cgroup v2 is the next version of the Linux cgroup API. cgroup v2 provides a unified control system with enhanced resource management capabilities.

cgroup v2 offers several improvements over cgroup v1, such as the following:

Some Kubernetes features exclusively use cgroup v2 for enhanced resource management and isolation. For example, the MemoryQoS feature improves memory QoS and relies on cgroup v2 primitives.

The recommended way to use cgroup v2 is to use a Linux distribution that enables and uses cgroup v2 by default.

To check if your distribution uses cgroup v2, refer to Identify cgroup version on Linux nodes.

cgroup v2 has the following requirements:

For a list of Linux distributions that use cgroup v2, refer to the cgroup v2 documentation

To check if your distribution is using cgroup v2, refer to your distribution's documentation or follow the instructions in Identify the cgroup version on Linux nodes.

You can also enable cgroup v2 manually on your Linux distribution by modifying the kernel cmdline boot arguments. If your distribution uses GRUB, systemd.unified_cgroup_hierarchy=1 should be added in GRUB_CMDLINE_LINUX under /etc/default/grub, followed by sudo update-grub. However, the recommended approach is to use a distribution that already enables cgroup v2 by default.

To migrate to cgroup v2, ensure that you meet the requirements, then upgrade to a kernel version that enables cgroup v2 by default.

The kubelet automatically detects that the OS is running on cgroup v2 and performs accordingly with no additional configuration required.

There should not be any noticeable difference in the user experience when switching to cgroup v2, unless users are accessing the cgroup file system directly, either on the node or from within the containers.

cgroup v2 uses a different API than cgroup v1, so if there are any applications that directly access the cgroup file system, they need to be updated to newer versions that support cgroup v2. For example:

The cgroup version depends on the Linux distribution being used and the default cgroup version co

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
stat -fc %T /sys/fs/cgroup/
```

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#field-validation

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Assigning Pods to Nodes

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity

**Contents:**
- Assigning Pods to Nodes
- Node labels
    - Note:
  - Node isolation/restriction
- nodeSelector
- Affinity and anti-affinity
  - Node affinity
    - Note:
    - Note:
    - Node affinity weight

You can constrain a Pod so that it is restricted to run on particular node(s), or to prefer to run on particular nodes. There are several ways to do this and the recommended approaches all use label selectors to facilitate the selection. Often, you do not need to set any such constraints; the scheduler will automatically do a reasonable placement (for example, spreading your Pods across nodes so as not place Pods on a node with insufficient free resources). However, there are some circumstances where you may want to control which node the Pod deploys to, for example, to ensure that a Pod ends up on a node with an SSD attached to it, or to co-locate Pods from two different services that communicate a lot into the same availability zone.

You can use any of the following methods to choose where Kubernetes schedules specific Pods:

Like many other Kubernetes objects, nodes have labels. You can attach labels manually. Kubernetes also populates a standard set of labels on all nodes in a cluster.

Adding labels to nodes allows you to target Pods for scheduling on specific nodes or groups of nodes. You can use this functionality to ensure that specific Pods only run on nodes with certain isolation, security, or regulatory properties.

If you use labels for node isolation, choose label keys that the kubelet cannot modify. This prevents a compromised node from setting those labels on itself so that the scheduler schedules workloads onto the compromised node.

The NodeRestriction admission plugin prevents the kubelet from setting or modifying labels with a node-restriction.kubernetes.io/ prefix.

To make use of that label prefix for node isolation:

nodeSelector is the simplest recommended form of node selection constraint. You can add the nodeSelector field to your Pod specification and specify the node labels you want the target node to have. Kubernetes only schedules the Pod onto nodes that have each of the labels you specify.

See Assign Pods to Nodes for more information.

nodeSelector is the simplest way to constrain Pods to nodes with specific labels. Affinity and anti-affinity expand the types of constraints you can define. Some of the benefits of affinity and anti-affinity include:

The affinity feature consists of two types of affinity:

Node affinity is conceptually similar to nodeSelector, allowing you to constrain which nodes your Pod can be scheduled on based on node labels. There are two types of node affinity:

You can specify node affinities using t

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-node-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - antarctica-east1
            - antarctica-west1
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: another-node-label-key
            operator: In
            values:
            - another-node-label-va
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-affinity-preferred-weight
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: label-1
            operator: In
            values:
            - key-1
      - weight: 50
        preference:
          matchExpressions:
    
...
```

Example 3 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration

profiles:
  - schedulerName: default-scheduler
  - schedulerName: foo-scheduler
    pluginConfig:
      - name: NodeAffinity
        args:
          addedAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: scheduler-profile
                  operator: In
                  values:
                  - foo
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-pod-affinity
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - S1
        topologyKey: topology.kubernetes.io/zone
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: security
              operator: In
              values:
         
...
```

---

## Windows containers in Kubernetes

**URL:** https://kubernetes.io/docs/concepts/windows/intro/

**Contents:**
- Windows containers in Kubernetes
- Windows nodes in Kubernetes
- Compatibility and limitations
  - Comparison with Linux
  - Command line options for the kubelet
  - API compatibility
    - Field compatibility for container specifications
    - Field compatibility for Pod specifications
    - Host network access
    - Field compatibility for Pod security context

Windows applications constitute a large portion of the services and applications that run in many organizations. Windows containers provide a way to encapsulate processes and package dependencies, making it easier to use DevOps practices and follow cloud native patterns for Windows applications.

Organizations with investments in Windows-based applications and Linux-based applications don't have to look for separate orchestrators to manage their workloads, leading to increased operational efficiencies across their deployments, regardless of operating system.

To enable the orchestration of Windows containers in Kubernetes, include Windows nodes in your existing Linux cluster. Scheduling Windows containers in Pods on Kubernetes is similar to scheduling Linux-based containers.

In order to run Windows containers, your Kubernetes cluster must include multiple operating systems. While you can only run the control plane on Linux, you can deploy worker nodes running either Windows or Linux.

Windows nodes are supported provided that the operating system is Windows Server 2019 or Windows Server 2022.

This document uses the term Windows containers to mean Windows containers with process isolation. Kubernetes does not support running Windows containers with Hyper-V isolation.

Some node features are only available if you use a specific container runtime; others are not available on Windows nodes, including:

Not all features of shared namespaces are supported. See API compatibility for more details.

See Windows OS version compatibility for details on the Windows versions that Kubernetes is tested against.

From an API and kubectl perspective, Windows containers behave in much the same way as Linux-based containers. However, there are some notable differences in key functionality which are outlined in this section.

Key Kubernetes elements work the same way in Windows as they do in Linux. This section refers to several key workload abstractions and how they map to Windows.

A Pod is the basic building block of Kubernetes–the smallest and simplest unit in the Kubernetes object model that you create or deploy. You may not deploy Windows and Linux containers in the same Pod. All containers in a Pod are scheduled onto a single Node where each Node represents a specific platform and architecture. The following Pod capabilities, properties and events are supported with Windows containers:

Single or multiple containers per Pod with process isolation and volume sharing



*[Content truncated]*

---

## Kubernetes API Aggregation Layer

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/

**Contents:**
- Kubernetes API Aggregation Layer
- Aggregation layer
  - Response latency
- What's next
- Feedback

The aggregation layer allows Kubernetes to be extended with additional APIs, beyond what is offered by the core Kubernetes APIs. The additional APIs can either be ready-made solutions such as a metrics server, or APIs that you develop yourself.

The aggregation layer is different from Custom Resource Definitions, which are a way to make the kube-apiserver recognise new kinds of object.

The aggregation layer runs in-process with the kube-apiserver. Until an extension resource is registered, the aggregation layer will do nothing. To register an API, you add an APIService object, which "claims" the URL path in the Kubernetes API. At that point, the aggregation layer will proxy anything sent to that API path (e.g. /apis/myextension.mycompany.io/v1/…) to the registered APIService.

The most common way to implement the APIService is to run an extension API server in Pod(s) that run in your cluster. If you're using the extension API server to manage resources in your cluster, the extension API server (also written as "extension-apiserver") is typically paired with one or more controllers. The apiserver-builder library provides a skeleton for both extension API servers and the associated controller(s).

Extension API servers should have low latency networking to and from the kube-apiserver. Discovery requests are required to round-trip from the kube-apiserver in five seconds or less.

If your extension API server cannot achieve that latency requirement, consider making changes that let you meet it.

Alternatively: learn how to extend the Kubernetes API using Custom Resource Definitions.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Kubernetes Components

**URL:** https://kubernetes.io/docs/concepts/overview/components/#third-party-content-disclaimer

**Contents:**
- Kubernetes Components
- Core Components
  - Control Plane Components
  - Node Components
- Addons
- Flexibility in Architecture
- Feedback

This page provides a high-level overview of the essential components that make up a Kubernetes cluster.

The components of a Kubernetes cluster

A Kubernetes cluster consists of a control plane and one or more worker nodes. Here's a brief overview of the main components:

Manage the overall state of the cluster:

Run on every node, maintaining running pods and providing the Kubernetes runtime environment:

Your cluster may require additional software on each node; for example, you might also run systemd on a Linux node to supervise local components.

Addons extend the functionality of Kubernetes. A few important examples include:

Kubernetes allows for flexibility in how these components are deployed and managed. The architecture can be adapted to various needs, from small development environments to large-scale production deployments.

For more detailed information about each component and various ways to configure your cluster architecture, see the Cluster Architecture page.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Configuration

**URL:** https://kubernetes.io/docs/concepts/configuration/

**Contents:**
- Configuration
      - Configuration Best Practices
      - ConfigMaps
      - Secrets
      - Liveness, Readiness, and Startup Probes
      - Resource Management for Pods and Containers
      - Organizing Cluster Access Using kubeconfig Files
      - Resource Management for Windows nodes
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Workloads

**URL:** https://kubernetes.io/docs/concepts/workloads/

**Contents:**
- Workloads
- What's next
- Feedback

A workload is an application running on Kubernetes. Whether your workload is a single component or several that work together, on Kubernetes you run it inside a set of pods. In Kubernetes, a Pod represents a set of running containers on your cluster.

Kubernetes pods have a defined lifecycle. For example, once a pod is running in your cluster then a critical fault on the node where that pod is running means that all the pods on that node fail. Kubernetes treats that level of failure as final: you would need to create a new Pod to recover, even if the node later becomes healthy.

However, to make life considerably easier, you don't need to manage each Pod directly. Instead, you can use workload resources that manage a set of pods on your behalf. These resources configure controllers that make sure the right number of the right kind of pod are running, to match the state you specified.

Kubernetes provides several built-in workload resources:

In the wider Kubernetes ecosystem, you can find third-party workload resources that provide additional behaviors. Using a custom resource definition, you can add in a third-party workload resource if you want a specific behavior that's not part of Kubernetes' core. For example, if you wanted to run a group of Pods for your application but stop work unless all the Pods are available (perhaps for some high-throughput distributed task), then you can implement or install an extension that does provide that feature.

As well as reading about each API kind for workload management, you can read how to do specific tasks:

To learn about Kubernetes' mechanisms for separating code from configuration, visit Configuration.

There are two supporting concepts that provide backgrounds about how Kubernetes manages pods for applications:

Once your application is running, you might want to make it available on the internet as a Service or, for web application only, using an Ingress.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Cluster Networking

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/networking/#how-to-implement-the-kubernetes-network-model

**Contents:**
- Cluster Networking
- Kubernetes IP address ranges
- Cluster networking types
- How to implement the Kubernetes network model
- What's next
- Feedback

Networking is a central part of Kubernetes, but it can be challenging to understand exactly how it is expected to work. There are 4 distinct networking problems to address:

Kubernetes is all about sharing machines among applications. Typically, sharing machines requires ensuring that two applications do not try to use the same ports. Coordinating ports across multiple developers is very difficult to do at scale and exposes users to cluster-level issues outside of their control.

Dynamic port allocation brings a lot of complications to the system - every application has to take ports as flags, the API servers have to know how to insert dynamic port numbers into configuration blocks, services have to know how to find each other, etc. Rather than deal with this, Kubernetes takes a different approach.

To learn about the Kubernetes networking model, see here.

Kubernetes clusters require to allocate non-overlapping IP addresses for Pods, Services and Nodes, from a range of available addresses configured in the following components:

Kubernetes clusters, attending to the IP families configured, can be categorized into:

Kubernetes clusters only consider the IP families present on the Pods, Services and Nodes objects, independently of the existing IPs of the represented objects. Per example, a server or a pod can have multiple IP addresses on its interfaces, but only the IP addresses in node.status.addresses or pod.status.ips are considered for implementing the Kubernetes network model and defining the type of the cluster.

The network model is implemented by the container runtime on each node. The most common container runtimes use Container Network Interface (CNI) plugins to manage their network and security capabilities. Many different CNI plugins exist from many different vendors. Some of these provide only basic features of adding and removing network interfaces, while others provide more sophisticated solutions, such as integration with other container orchestration systems, running multiple CNI plugins, advanced IPAM features etc.

See this page for a non-exhaustive list of networking addons supported by Kubernetes.

The early design of the networking model and its rationale are described in more detail in the networking design document. For future plans and some on-going efforts that aim to improve Kubernetes networking, please refer to the SIG-Network KEPs.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question ab

*[Content truncated]*

---

## Pod Topology Spread Constraints

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

**Contents:**
- Pod Topology Spread Constraints
- Motivation
- topologySpreadConstraints field
  - Spread constraint definition
    - Note:
    - Caution:
    - Note:
    - Note:
    - Note:
  - Node labels

You can use topology spread constraints to control how Pods are spread across your cluster among failure-domains such as regions, zones, nodes, and other user-defined topology domains. This can help to achieve high availability as well as efficient resource utilization.

You can set cluster-level constraints as a default, or configure topology spread constraints for individual workloads.

Imagine that you have a cluster of up to twenty nodes, and you want to run a workload that automatically scales how many replicas it uses. There could be as few as two Pods or as many as fifteen. When there are only two Pods, you'd prefer not to have both of those Pods run on the same node: you would run the risk that a single node failure takes your workload offline.

In addition to this basic usage, there are some advanced usage examples that enable your workloads to benefit on high availability and cluster utilization.

As you scale up and run more Pods, a different concern becomes important. Imagine that you have three nodes running five Pods each. The nodes have enough capacity to run that many replicas; however, the clients that interact with this workload are split across three different datacenters (or infrastructure zones). Now you have less concern about a single node failure, but you notice that latency is higher than you'd like, and you are paying for network costs associated with sending network traffic between the different zones.

You decide that under normal operation you'd prefer to have a similar number of replicas scheduled into each infrastructure zone, and you'd like the cluster to self-heal in the case that there is a problem.

Pod topology spread constraints offer you a declarative way to configure that.

The Pod API includes a field, spec.topologySpreadConstraints. The usage of this field looks like the following:

You can read more about this field by running kubectl explain Pod.spec.topologySpreadConstraints or refer to the scheduling section of the API reference for Pod.

You can define one or multiple topologySpreadConstraints entries to instruct the kube-scheduler how to place each incoming Pod in relation to the existing Pods across your cluster. Those fields are:

maxSkew describes the degree to which Pods may be unevenly distributed. You must specify this field and the number must be greater than zero. Its semantics differ according to the value of whenUnsatisfiable:

minDomains indicates a minimum number of eligible domains. This field is 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  # Configure a topology spread constraint
  topologySpreadConstraints:
    - maxSkew: <integer>
      minDomains: <integer> # optional
      topologyKey: <string>
      whenUnsatisfiable: <string>
      labelSelector: <object>
      matchLabelKeys: <list> # optional; beta since v1.27
      nodeAffinityPolicy: [Honor|Ignore] # optional; beta since v1.26
      nodeTaintsPolicy: [Honor|Ignore] # optional; beta since v1.26
  ### other Pod fields go here
```

Example 2 (yaml):
```yaml
topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: foo
          matchLabelKeys:
            - pod-template-hash
```

Example 3 (yaml):
```yaml
region: us-east-1
  zone: us-east-1a
```

Example 4 (unknown):
```unknown
NAME    STATUS   ROLES    AGE     VERSION   LABELS
node1   Ready    <none>   4m26s   v1.16.0   node=node1,zone=zoneA
node2   Ready    <none>   3m58s   v1.16.0   node=node2,zone=zoneA
node3   Ready    <none>   3m17s   v1.16.0   node=node3,zone=zoneB
node4   Ready    <none>   2m43s   v1.16.0   node=node4,zone=zoneB
```

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-has-network

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#network-plugins

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Device Plugins

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/

**Contents:**
- Device Plugins
- Device plugin registration
  - Example
- Device plugin implementation
    - Note:
    - Note:
    - Note:
  - Handling kubelet restarts
  - Device plugin and unhealthy devices
- Device plugin deployment

Kubernetes provides a device plugin framework that you can use to advertise system hardware resources to the Kubelet.

Instead of customizing the code for Kubernetes itself, vendors can implement a device plugin that you deploy either manually or as a DaemonSet. The targeted devices include GPUs, high-performance NICs, FPGAs, InfiniBand adapters, and other similar computing resources that may require vendor specific initialization and setup.

The kubelet exports a Registration gRPC service:

A device plugin can register itself with the kubelet through this gRPC service. During the registration, the device plugin needs to send:

Following a successful registration, the device plugin sends the kubelet the list of devices it manages, and the kubelet is then in charge of advertising those resources to the API server as part of the kubelet node status update. For example, after a device plugin registers hardware-vendor.example/foo with the kubelet and reports two healthy devices on a node, the node status is updated to advertise that the node has 2 "Foo" devices installed and available.

Then, users can request devices as part of a Pod specification (see container). Requesting extended resources is similar to how you manage requests and limits for other resources, with the following differences:

Suppose a Kubernetes cluster is running a device plugin that advertises resource hardware-vendor.example/foo on certain nodes. Here is an example of a pod requesting this resource to run a demo workload:

The general workflow of a device plugin includes the following steps:

Initialization. During this phase, the device plugin performs vendor-specific initialization and setup to make sure the devices are in a ready state.

The plugin starts a gRPC service, with a Unix socket under the host path /var/lib/kubelet/device-plugins/, that implements the following interfaces:

The plugin registers itself with the kubelet through the Unix socket at host path /var/lib/kubelet/device-plugins/kubelet.sock.

After successfully registering itself, the device plugin runs in serving mode, during which it keeps monitoring device health and reports back to the kubelet upon any device state changes. It is also responsible for serving Allocate gRPC requests. During Allocate, the device plugin may do device-specific preparation; for example, GPU cleanup or QRNG initialization. If the operations succeed, the device plugin returns an AllocateResponse that contains container runtime configur

*[Content truncated]*

**Examples:**

Example 1 (gRPC):
```gRPC
service Registration {
	rpc Register(RegisterRequest) returns (Empty) {}
}
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: demo-pod
spec:
  containers:
    - name: demo-container-1
      image: registry.k8s.io/pause:3.8
      resources:
        limits:
          hardware-vendor.example/foo: 2
#
# This Pod needs 2 of the hardware-vendor.example/foo devices
# and can only schedule onto a Node that's able to satisfy
# that need.
#
# If the Node has more than 2 of those devices available, the
# remainder would be available for other Pods to use.
```

Example 3 (gRPC):
```gRPC
service DevicePlugin {
      // GetDevicePluginOptions returns options to be communicated with Device Manager.
      rpc GetDevicePluginOptions(Empty) returns (DevicePluginOptions) {}

      // ListAndWatch returns a stream of List of Devices
      // Whenever a Device state change or a Device disappears, ListAndWatch
      // returns the new list
      rpc ListAndWatch(Empty) returns (stream ListAndWatchResponse) {}

      // Allocate is called during container creation so that the Device
      // Plugin can run device specific operations and instruct Kubelet
      // of the steps to make the
...
```

Example 4 (gRPC):
```gRPC
// PodResourcesLister is a service provided by the kubelet that provides information about the
// node resources consumed by pods and containers on the node
service PodResourcesLister {
    rpc List(ListPodResourcesRequest) returns (ListPodResourcesResponse) {}
    rpc GetAllocatableResources(AllocatableResourcesRequest) returns (AllocatableResourcesResponse) {}
    rpc Get(GetPodResourcesRequest) returns (GetPodResourcesResponse) {}
}
```

---

## Namespaces

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

**Contents:**
- Namespaces
- When to Use Multiple Namespaces
    - Note:
- Initial namespaces
- Working with Namespaces
    - Note:
  - Viewing namespaces
  - Setting the namespace for a request
  - Setting the namespace preference
- Namespaces and DNS

In Kubernetes, namespaces provide a mechanism for isolating groups of resources within a single cluster. Names of resources need to be unique within a namespace, but not across namespaces. Namespace-based scoping is applicable only for namespaced objects (e.g. Deployments, Services, etc.) and not for cluster-wide objects (e.g. StorageClass, Nodes, PersistentVolumes, etc.).

Namespaces are intended for use in environments with many users spread across multiple teams, or projects. For clusters with a few to tens of users, you should not need to create or think about namespaces at all. Start using namespaces when you need the features they provide.

Namespaces provide a scope for names. Names of resources need to be unique within a namespace, but not across namespaces. Namespaces cannot be nested inside one another and each Kubernetes resource can only be in one namespace.

Namespaces are a way to divide cluster resources between multiple users (via resource quota).

It is not necessary to use multiple namespaces to separate slightly different resources, such as different versions of the same software: use labels to distinguish resources within the same namespace.

Kubernetes starts with four initial namespaces:

Creation and deletion of namespaces are described in the Admin Guide documentation for namespaces.

You can list the current namespaces in a cluster using:

To set the namespace for a current request, use the --namespace flag.

You can permanently save the namespace for all subsequent kubectl commands in that context.

When you create a Service, it creates a corresponding DNS entry. This entry is of the form <service-name>.<namespace-name>.svc.cluster.local, which means that if a container only uses <service-name>, it will resolve to the service which is local to a namespace. This is useful for using the same configuration across multiple namespaces such as Development, Staging and Production. If you want to reach across namespaces, you need to use the fully qualified domain name (FQDN).

As a result, all namespace names must be valid RFC 1123 DNS labels.

By creating namespaces with the same name as public top-level domains, Services in these namespaces can have short DNS names that overlap with public DNS records. Workloads from any namespace performing a DNS lookup without a trailing dot will be redirected to those services, taking precedence over public DNS.

To mitigate this, limit privileges for creating namespaces to trusted users. If required

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get namespace
```

Example 2 (unknown):
```unknown
NAME              STATUS   AGE
default           Active   1d
kube-node-lease   Active   1d
kube-public       Active   1d
kube-system       Active   1d
```

Example 3 (shell):
```shell
kubectl run nginx --image=nginx --namespace=<insert-namespace-name-here>
kubectl get pods --namespace=<insert-namespace-name-here>
```

Example 4 (shell):
```shell
kubectl config set-context --current --namespace=<insert-namespace-name-here>
# Validate it
kubectl config view --minify | grep namespace:
```

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#admin-access

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Configuration Best Practices

**URL:** https://kubernetes.io/docs/concepts/configuration/overview/#general-configuration-tips

**Contents:**
- Configuration Best Practices
- General Configuration Tips
    - Note:
- "Naked" Pods versus ReplicaSets, Deployments, and Jobs
- Services
- Using Labels
- Using kubectl
- Feedback

This document highlights and consolidates configuration best practices that are introduced throughout the user guide, Getting Started documentation, and examples.

This is a living document. If you think of something that is not on this list but might be useful to others, please don't hesitate to file an issue or submit a PR.

When defining configurations, specify the latest stable API version.

Configuration files should be stored in version control before being pushed to the cluster. This allows you to quickly roll back a configuration change if necessary. It also aids cluster re-creation and restoration.

Write your configuration files using YAML rather than JSON. Though these formats can be used interchangeably in almost all scenarios, YAML tends to be more user-friendly.

Group related objects into a single file whenever it makes sense. One file is often easier to manage than several. See the guestbook-all-in-one.yaml file as an example of this syntax.

Note also that many kubectl commands can be called on a directory. For example, you can call kubectl apply on a directory of config files.

Don't specify default values unnecessarily: simple, minimal configuration will make errors less likely.

Put object descriptions in annotations, to allow better introspection.

There is a breaking change introduced in the YAML 1.2 boolean values specification with respect to YAML 1.1. This is a known issue in Kubernetes. YAML 1.2 only recognizes true and false as valid booleans, while YAML 1.1 also accepts yes, no, on, and off as booleans. However, Kubernetes uses YAML parsers that are mostly compatible with YAML 1.1, which means that using yes or no instead of true or false in a YAML manifest may cause unexpected errors or behaviors. To avoid this issue, it is recommended to always use true or false for boolean values in YAML manifests, and to quote any strings that may be confused with booleans, such as "yes" or "no".

Besides booleans, there are additional specifications changes between YAML versions. Please refer to the YAML Specification Changes documentation for a comprehensive list.

Don't use naked Pods (that is, Pods not bound to a ReplicaSet or Deployment) if you can avoid it. Naked Pods will not be rescheduled in the event of a node failure.

A Deployment, which both creates a ReplicaSet to ensure that the desired number of Pods is always available, and specifies a strategy to replace Pods (such as RollingUpdate), is almost always preferable to creating 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
FOO_SERVICE_HOST=<the host the Service is running on>
FOO_SERVICE_PORT=<the port the Service is running on>
```

---

## Jobs

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/job/#elastic-indexed-jobs

**Contents:**
- Jobs
- Running an example Job
- Writing a Job spec
  - Job Labels
  - Pod Template
  - Pod selector
  - Parallel execution for Jobs
    - Controlling parallelism
  - Completion mode
    - Note:

A Job creates one or more Pods and will continue to retry execution of the Pods until a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created. Suspending a Job will delete its active Pods until the Job is resumed again.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.

If you want to run a Job (either a single task, or several in parallel) on a schedule, see CronJob.

Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

You can run the example with this command:

The output is similar to this:

Check on the status of the Job with kubectl:

Name: pi Namespace: default Selector: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi ... Annotations: batch.kubernetes.io/job-tracking: "" Parallelism: 1 Completions: 1 Start Time: Mon, 02 Dec 2019 15:20:11 +0200 Completed At: Mon, 02 Dec 2019 15:21:16 +0200 Duration: 65s Pods Statuses: 0 Running / 1 Succeeded / 0 Failed Pod Template: Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi Containers: pi: Image: perl:5.34.0 Port: <none> Host Port: <none> Command: perl -Mbignum=bpi -wle print bpi(2000) Environment: <none> Mounts: <none> Volumes: <none> Events: Type Reason Age From Message ---- ------ ---- ---- ------- Normal SuccessfulCreate 21s job-controller Created pod: pi-xf9p4 Normal Completed 18s job-controller Job completed

apiVersion: batch/v1 kind: Job metadata: annotations: batch.kubernetes.io/job-tracking: "" ... creationTimestamp: "2022-11-10T17:53:53Z" generation: 1 labels: batch.kubernetes.io/controller-uid: 863452e6-270d-420e-9b94-53a54146c223 batch.kubernetes.io/job-name: pi name: pi namespace: default resourceVersion: "4751" uid: 204fb678-040b-497f-9266-35ffa8716d14 spec: backoffLimit: 4 completionMode: NonIndexed completions: 1 parallelism: 1 selector: matchLabels: batch.kubernetes.io/controller-uid: 863452e6-270d-4

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl:5.34.0
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/job.yaml
```

Example 3 (unknown):
```unknown
job.batch/pi created
```

Example 4 (bash):
```bash
Name:           pi
Namespace:      default
Selector:       batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
Labels:         batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
                batch.kubernetes.io/job-name=pi
                ...
Annotations:    batch.kubernetes.io/job-tracking: ""
Parallelism:    1
Completions:    1
Start Time:     Mon, 02 Dec 2019 15:20:11 +0200
Completed At:   Mon, 02 Dec 2019 15:21:16 +0200
Duration:       65s
Pods Statuses:  0 Running / 1 Succeeded / 0 Failed
Pod Template:
  Labels:  batch.kubernetes.io/controller-u
...
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#device-health-monitoring

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## Garbage Collection

**URL:** https://kubernetes.io/docs/concepts/architecture/garbage-collection/

**Contents:**
- Garbage Collection
- Owners and dependents
    - Note:
- Cascading deletion
  - Foreground cascading deletion
  - Background cascading deletion
  - Orphaned dependents
- Garbage collection of unused containers and images
  - Container image lifecycle
    - Garbage collection for unused container images

Garbage collection is a collective term for the various mechanisms Kubernetes uses to clean up cluster resources. This allows the clean up of resources like the following:

Many objects in Kubernetes link to each other through owner references. Owner references tell the control plane which objects are dependent on others. Kubernetes uses owner references to give the control plane, and other API clients, the opportunity to clean up related resources before deleting an object. In most cases, Kubernetes manages owner references automatically.

Ownership is different from the labels and selectors mechanism that some resources also use. For example, consider a Service that creates EndpointSlice objects. The Service uses labels to allow the control plane to determine which EndpointSlice objects are used for that Service. In addition to the labels, each EndpointSlice that is managed on behalf of a Service has an owner reference. Owner references help different parts of Kubernetes avoid interfering with objects they don’t control.

Cross-namespace owner references are disallowed by design. Namespaced dependents can specify cluster-scoped or namespaced owners. A namespaced owner must exist in the same namespace as the dependent. If it does not, the owner reference is treated as absent, and the dependent is subject to deletion once all owners are verified absent.

Cluster-scoped dependents can only specify cluster-scoped owners. In v1.20+, if a cluster-scoped dependent specifies a namespaced kind as an owner, it is treated as having an unresolvable owner reference, and is not able to be garbage collected.

In v1.20+, if the garbage collector detects an invalid cross-namespace ownerReference, or a cluster-scoped dependent with an ownerReference referencing a namespaced kind, a warning Event with a reason of OwnerRefInvalidNamespace and an involvedObject of the invalid dependent is reported. You can check for that kind of Event by running kubectl get events -A --field-selector=reason=OwnerRefInvalidNamespace.

Kubernetes checks for and deletes objects that no longer have owner references, like the pods left behind when you delete a ReplicaSet. When you delete an object, you can control whether Kubernetes deletes the object's dependents automatically, in a process called cascading deletion. There are two types of cascading deletion, as follows:

You can also control how and when garbage collection deletes resources that have owner references using Kubernetes finalizers

*[Content truncated]*

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#storage-plugins

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#enabling-admin-access

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Cluster Administration

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/

**Contents:**
- Cluster Administration
- Planning a cluster
    - Note:
- Managing a cluster
- Securing a cluster
  - Securing the kubelet
- Optional Cluster Services
- Feedback

The cluster administration overview is for anyone creating or administering a Kubernetes cluster. It assumes some familiarity with core Kubernetes concepts.

See the guides in Setup for examples of how to plan, set up, and configure Kubernetes clusters. The solutions listed in this article are called distros.

Before choosing a guide, here are some considerations:

Learn how to manage nodes.

Learn how to set up and manage the resource quota for shared clusters.

Generate Certificates describes the steps to generate certificates using different tool chains.

Kubernetes Container Environment describes the environment for Kubelet managed containers on a Kubernetes node.

Controlling Access to the Kubernetes API describes how Kubernetes implements access control for its own API.

Authenticating explains authentication in Kubernetes, including the various authentication options.

Authorization is separate from authentication, and controls how HTTP calls are handled.

Using Admission Controllers explains plug-ins which intercepts requests to the Kubernetes API server after authentication and authorization.

Admission Webhook Good Practices provides good practices and considerations when designing mutating admission webhooks and validating admission webhooks.

Using Sysctls in a Kubernetes Cluster describes to an administrator how to use the sysctl command-line tool to set kernel parameters .

Auditing describes how to interact with Kubernetes' audit logs.

DNS Integration describes how to resolve a DNS name directly to a Kubernetes service.

Logging and Monitoring Cluster Activity explains how logging in Kubernetes works and how to implement it.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Windows containers in Kubernetes

**URL:** https://kubernetes.io/docs/concepts/windows/intro/#windows-os-version-support

**Contents:**
- Windows containers in Kubernetes
- Windows nodes in Kubernetes
- Compatibility and limitations
  - Comparison with Linux
  - Command line options for the kubelet
  - API compatibility
    - Field compatibility for container specifications
    - Field compatibility for Pod specifications
    - Host network access
    - Field compatibility for Pod security context

Windows applications constitute a large portion of the services and applications that run in many organizations. Windows containers provide a way to encapsulate processes and package dependencies, making it easier to use DevOps practices and follow cloud native patterns for Windows applications.

Organizations with investments in Windows-based applications and Linux-based applications don't have to look for separate orchestrators to manage their workloads, leading to increased operational efficiencies across their deployments, regardless of operating system.

To enable the orchestration of Windows containers in Kubernetes, include Windows nodes in your existing Linux cluster. Scheduling Windows containers in Pods on Kubernetes is similar to scheduling Linux-based containers.

In order to run Windows containers, your Kubernetes cluster must include multiple operating systems. While you can only run the control plane on Linux, you can deploy worker nodes running either Windows or Linux.

Windows nodes are supported provided that the operating system is Windows Server 2019 or Windows Server 2022.

This document uses the term Windows containers to mean Windows containers with process isolation. Kubernetes does not support running Windows containers with Hyper-V isolation.

Some node features are only available if you use a specific container runtime; others are not available on Windows nodes, including:

Not all features of shared namespaces are supported. See API compatibility for more details.

See Windows OS version compatibility for details on the Windows versions that Kubernetes is tested against.

From an API and kubectl perspective, Windows containers behave in much the same way as Linux-based containers. However, there are some notable differences in key functionality which are outlined in this section.

Key Kubernetes elements work the same way in Windows as they do in Linux. This section refers to several key workload abstractions and how they map to Windows.

A Pod is the basic building block of Kubernetes–the smallest and simplest unit in the Kubernetes object model that you create or deploy. You may not deploy Windows and Linux containers in the same Pod. All containers in a Pod are scheduled onto a single Node where each Node represents a specific platform and architecture. The following Pod capabilities, properties and events are supported with Windows containers:

Single or multiple containers per Pod with process isolation and volume sharing



*[Content truncated]*

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Assigning Pods to Nodes

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity

**Contents:**
- Assigning Pods to Nodes
- Node labels
    - Note:
  - Node isolation/restriction
- nodeSelector
- Affinity and anti-affinity
  - Node affinity
    - Note:
    - Note:
    - Node affinity weight

You can constrain a Pod so that it is restricted to run on particular node(s), or to prefer to run on particular nodes. There are several ways to do this and the recommended approaches all use label selectors to facilitate the selection. Often, you do not need to set any such constraints; the scheduler will automatically do a reasonable placement (for example, spreading your Pods across nodes so as not place Pods on a node with insufficient free resources). However, there are some circumstances where you may want to control which node the Pod deploys to, for example, to ensure that a Pod ends up on a node with an SSD attached to it, or to co-locate Pods from two different services that communicate a lot into the same availability zone.

You can use any of the following methods to choose where Kubernetes schedules specific Pods:

Like many other Kubernetes objects, nodes have labels. You can attach labels manually. Kubernetes also populates a standard set of labels on all nodes in a cluster.

Adding labels to nodes allows you to target Pods for scheduling on specific nodes or groups of nodes. You can use this functionality to ensure that specific Pods only run on nodes with certain isolation, security, or regulatory properties.

If you use labels for node isolation, choose label keys that the kubelet cannot modify. This prevents a compromised node from setting those labels on itself so that the scheduler schedules workloads onto the compromised node.

The NodeRestriction admission plugin prevents the kubelet from setting or modifying labels with a node-restriction.kubernetes.io/ prefix.

To make use of that label prefix for node isolation:

nodeSelector is the simplest recommended form of node selection constraint. You can add the nodeSelector field to your Pod specification and specify the node labels you want the target node to have. Kubernetes only schedules the Pod onto nodes that have each of the labels you specify.

See Assign Pods to Nodes for more information.

nodeSelector is the simplest way to constrain Pods to nodes with specific labels. Affinity and anti-affinity expand the types of constraints you can define. Some of the benefits of affinity and anti-affinity include:

The affinity feature consists of two types of affinity:

Node affinity is conceptually similar to nodeSelector, allowing you to constrain which nodes your Pod can be scheduled on based on node labels. There are two types of node affinity:

You can specify node affinities using t

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-node-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - antarctica-east1
            - antarctica-west1
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: another-node-label-key
            operator: In
            values:
            - another-node-label-va
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-affinity-preferred-weight
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: label-1
            operator: In
            values:
            - key-1
      - weight: 50
        preference:
          matchExpressions:
    
...
```

Example 3 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration

profiles:
  - schedulerName: default-scheduler
  - schedulerName: foo-scheduler
    pluginConfig:
      - name: NodeAffinity
        args:
          addedAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: scheduler-profile
                  operator: In
                  values:
                  - foo
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-pod-affinity
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - S1
        topologyKey: topology.kubernetes.io/zone
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: security
              operator: In
              values:
         
...
```

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#rfc-1035-label-names

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Volume Health Monitoring

**URL:** https://kubernetes.io/docs/concepts/storage/volume-health-monitoring/

**Contents:**
- Volume Health Monitoring
- Volume health monitoring
    - Note:
- What's next
- Feedback

CSI volume health monitoring allows CSI Drivers to detect abnormal volume conditions from the underlying storage systems and report them as events on PVCs or Pods.

Kubernetes volume health monitoring is part of how Kubernetes implements the Container Storage Interface (CSI). Volume health monitoring feature is implemented in two components: an External Health Monitor controller, and the kubelet.

If a CSI Driver supports Volume Health Monitoring feature from the controller side, an event will be reported on the related PersistentVolumeClaim (PVC) when an abnormal volume condition is detected on a CSI volume.

The External Health Monitor controller also watches for node failure events. You can enable node failure monitoring by setting the enable-node-watcher flag to true. When the external health monitor detects a node failure event, the controller reports an Event will be reported on the PVC to indicate that pods using this PVC are on a failed node.

If a CSI Driver supports Volume Health Monitoring feature from the node side, an Event will be reported on every Pod using the PVC when an abnormal volume condition is detected on a CSI volume. In addition, Volume Health information is exposed as Kubelet VolumeStats metrics. A new metric kubelet_volume_stats_health_status_abnormal is added. This metric includes two labels: namespace and persistentvolumeclaim. The count is either 1 or 0. 1 indicates the volume is unhealthy, 0 indicates volume is healthy. For more information, please check KEP.

See the CSI driver documentation to find out which CSI drivers have implemented this feature.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## API Priority and Fairness

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/flow-control/#defaults

**Contents:**
- API Priority and Fairness
    - Caution:
- Enabling/Disabling API Priority and Fairness
- Recursive server scenarios
- Concepts
  - Priority Levels
  - Seats Occupied by a Request
  - Execution time tweaks for watch requests
  - Queuing
  - Exempt requests

Controlling the behavior of the Kubernetes API server in an overload situation is a key task for cluster administrators. The kube-apiserver has some controls available (i.e. the --max-requests-inflight and --max-mutating-requests-inflight command-line flags) to limit the amount of outstanding work that will be accepted, preventing a flood of inbound requests from overloading and potentially crashing the API server, but these flags are not enough to ensure that the most important requests get through in a period of high traffic.

The API Priority and Fairness feature (APF) is an alternative that improves upon aforementioned max-inflight limitations. APF classifies and isolates requests in a more fine-grained way. It also introduces a limited amount of queuing, so that no requests are rejected in cases of very brief bursts. Requests are dispatched from queues using a fair queuing technique so that, for example, a poorly-behaved controller need not starve others (even at the same priority level).

This feature is designed to work well with standard controllers, which use informers and react to failures of API requests with exponential back-off, and other clients that also work this way.

The API Priority and Fairness feature is controlled by a command-line flag and is enabled by default. See Options for a general explanation of the available kube-apiserver command-line options and how to enable and disable them. The name of the command-line option for APF is "--enable-priority-and-fairness". This feature also involves an API Group with: (a) a stable v1 version, introduced in 1.29, and enabled by default (b) a v1beta3 version, enabled by default, and deprecated in v1.29. You can disable the API group beta version v1beta3 by adding the following command-line flags to your kube-apiserver invocation:

The command-line flag --enable-priority-and-fairness=false will disable the API Priority and Fairness feature.

API Priority and Fairness must be used carefully in recursive server scenarios. These are scenarios in which some server A, while serving a request, issues a subsidiary request to some server B. Perhaps server B might even make a further subsidiary call back to server A. In situations where Priority and Fairness control is applied to both the original request and some subsidiary ones(s), no matter how deep in the recursion, there is a danger of priority inversions and/or deadlocks.

One example of recursion is when the kube-apiserver issues an admission we

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kube-apiserver \
--runtime-config=flowcontrol.apiserver.k8s.io/v1beta3=false \
 # …and other flags as usual
```

Example 2 (yaml):
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: health-for-strangers
spec:
  matchingPrecedence: 1000
  priorityLevelConfiguration:
    name: exempt
  rules:
    - nonResourceRules:
      - nonResourceURLs:
          - "/healthz"
          - "/livez"
          - "/readyz"
        verbs:
          - "*"
      subjects:
        - kind: Group
          group:
            name: "system:unauthenticated"
```

Example 3 (yaml):
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: list-events-default-service-account
spec:
  distinguisherMethod:
    type: ByUser
  matchingPrecedence: 8000
  priorityLevelConfiguration:
    name: catch-all
  rules:
    - resourceRules:
      - apiGroups:
          - '*'
        namespaces:
          - default
        resources:
          - events
        verbs:
          - list
      subjects:
        - kind: ServiceAccount
          serviceAccount:
            name: default
            namespace: default
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#-strong-api-groups-strong-

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## Kubernetes API Server Bypass Risks

**URL:** https://kubernetes.io/docs/concepts/security/api-server-bypass-risks/

**Contents:**
- Kubernetes API Server Bypass Risks
- Static Pods
  - Mitigations
- The kubelet API
  - Mitigations
- The etcd API
  - Mitigations
- Container runtime socket
  - Mitigations
- Feedback

The Kubernetes API server is the main point of entry to a cluster for external parties (users and services) interacting with it.

As part of this role, the API server has several key built-in security controls, such as audit logging and admission controllers. However, there are ways to modify the configuration or content of the cluster that bypass these controls.

This page describes the ways in which the security controls built into the Kubernetes API server can be bypassed, so that cluster operators and security architects can ensure that these bypasses are appropriately restricted.

The kubelet on each node loads and directly manages any manifests that are stored in a named directory or fetched from a specific URL as static Pods in your cluster. The API server doesn't manage these static Pods. An attacker with write access to this location could modify the configuration of static pods loaded from that source, or could introduce new static Pods.

Static Pods are restricted from accessing other objects in the Kubernetes API. For example, you can't configure a static Pod to mount a Secret from the cluster. However, these Pods can take other security sensitive actions, such as using hostPath mounts from the underlying node.

By default, the kubelet creates a mirror pod so that the static Pods are visible in the Kubernetes API. However, if the attacker uses an invalid namespace name when creating the Pod, it will not be visible in the Kubernetes API and can only be discovered by tooling that has access to the affected host(s).

If a static Pod fails admission control, the kubelet won't register the Pod with the API server. However, the Pod still runs on the node. For more information, refer to kubeadm issue #1541.

The kubelet provides an HTTP API that is typically exposed on TCP port 10250 on cluster worker nodes. The API might also be exposed on control plane nodes depending on the Kubernetes distribution in use. Direct access to the API allows for disclosure of information about the pods running on a node, the logs from those pods, and execution of commands in every container running on the node.

When Kubernetes cluster users have RBAC access to Node object sub-resources, that access serves as authorization to interact with the kubelet API. The exact access depends on which sub-resource access has been granted, as detailed in kubelet authorization.

Direct access to the kubelet API is not subject to admission control and is not logged by Kubernetes audit

*[Content truncated]*

---

## Node Resource Managers

**URL:** https://kubernetes.io/docs/concepts/policy/node-resource-managers/

**Contents:**
- Node Resource Managers
- Hardware topology alignment policies
- Policies for assigning CPUs to Pods
    - Note:
  - Static policy
    - Note:
    - Static policy options
      - full-pcpus-only
      - distribute-cpus-across-numa
      - align-by-socket

In order to support latency-critical and high-throughput workloads, Kubernetes offers a suite of Resource Managers. The managers aim to co-ordinate and optimise the alignment of node's resources for pods configured with a specific requirement for CPUs, devices, and memory (hugepages) resources.

Topology Manager is a kubelet component that aims to coordinate the set of components that are responsible for these optimizations. The overall resource management process is governed using the policy you specify. To learn more, read Control Topology Management Policies on a Node.

Once a Pod is bound to a Node, the kubelet on that node may need to either multiplex the existing hardware (for example, sharing CPUs across multiple Pods) or allocate hardware by dedicating some resource (for example, assigning one of more CPUs for a Pod's exclusive use).

By default, the kubelet uses CFS quota to enforce pod CPU limits. When the node runs many CPU-bound pods, the workload can move to different CPU cores depending on whether the pod is throttled and which CPU cores are available at scheduling time. Many workloads are not sensitive to this migration and thus work fine without any intervention.

However, in workloads where CPU cache affinity and scheduling latency significantly affect workload performance, the kubelet allows alternative CPU management policies to determine some placement preferences on the node. This is implemented using the CPU Manager and its policy. There are two available policies:

CPU Manager doesn't support offlining and onlining of CPUs at runtime.

The static policy enables finer-grained CPU management and exclusive CPU assignment. This policy manages a shared pool of CPUs that initially contains all CPUs in the node. The amount of exclusively allocatable CPUs is equal to the total number of CPUs in the node minus any CPU reservations set by the kubelet configuration. CPUs reserved by these options are taken, in integer quantity, from the initial shared pool in ascending order by physical core ID. This shared pool is the set of CPUs on which any containers in BestEffort and Burstable pods run. Containers in Guaranteed pods with fractional CPU requests also run on CPUs in the shared pool. Only containers that are part of a Guaranteed pod and have integer CPU requests are assigned exclusive CPUs.

As Guaranteed pods whose containers fit the requirements for being statically assigned are scheduled to the node, CPUs are removed from the shared pool a

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
```

Example 2 (yaml):
```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      limits:
        memory: "200Mi"
      requests:
        memory: "100Mi"
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
      requests:
        memory: "100Mi"
        cpu: "1"
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
        cpu: "2"
      requests:
        memory: "200Mi"
        cpu: "2"
```

---

## Ephemeral Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/

**Contents:**
- Ephemeral Volumes
  - Types of ephemeral volumes
  - CSI ephemeral volumes
    - Note:
  - CSI driver restrictions
  - Generic ephemeral volumes
  - Lifecycle and PersistentVolumeClaim
  - PersistentVolumeClaim naming
    - Caution:
  - Security

This document describes ephemeral volumes in Kubernetes. Familiarity with volumes is suggested, in particular PersistentVolumeClaim and PersistentVolume.

Some applications need additional storage but don't care whether that data is stored persistently across restarts. For example, caching services are often limited by memory size and can move infrequently used data into storage that is slower than memory with little impact on overall performance.

Other applications expect some read-only input data to be present in files, like configuration data or secret keys.

Ephemeral volumes are designed for these use cases. Because volumes follow the Pod's lifetime and get created and deleted along with the Pod, Pods can be stopped and restarted without being limited to where some persistent volume is available.

Ephemeral volumes are specified inline in the Pod spec, which simplifies application deployment and management.

Kubernetes supports several different kinds of ephemeral volumes for different purposes:

emptyDir, configMap, downwardAPI, secret are provided as local ephemeral storage. They are managed by kubelet on each node.

CSI ephemeral volumes must be provided by third-party CSI storage drivers.

Generic ephemeral volumes can be provided by third-party CSI storage drivers, but also by any other storage driver that supports dynamic provisioning. Some CSI drivers are written specifically for CSI ephemeral volumes and do not support dynamic provisioning: those then cannot be used for generic ephemeral volumes.

The advantage of using third-party drivers is that they can offer functionality that Kubernetes itself does not support, for example storage with different performance characteristics than the disk that is managed by kubelet, or injecting different data.

Conceptually, CSI ephemeral volumes are similar to configMap, downwardAPI and secret volume types: the storage is managed locally on each node and is created together with other local resources after a Pod has been scheduled onto a node. Kubernetes has no concept of rescheduling Pods anymore at this stage. Volume creation has to be unlikely to fail, otherwise Pod startup gets stuck. In particular, storage capacity aware Pod scheduling is not supported for these volumes. They are currently also not covered by the storage resource usage limits of a Pod, because that is something that kubelet can only enforce for storage that it manages itself.

Here's an example manifest for a Pod that uses CSI ephem

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
kind: Pod
apiVersion: v1
metadata:
  name: my-csi-app
spec:
  containers:
    - name: my-frontend
      image: busybox:1.28
      volumeMounts:
      - mountPath: "/data"
        name: my-csi-inline-vol
      command: [ "sleep", "1000000" ]
  volumes:
    - name: my-csi-inline-vol
      csi:
        driver: inline.storage.kubernetes.io
        volumeAttributes:
          foo: bar
```

Example 2 (yaml):
```yaml
kind: Pod
apiVersion: v1
metadata:
  name: my-app
spec:
  containers:
    - name: my-frontend
      image: busybox:1.28
      volumeMounts:
      - mountPath: "/scratch"
        name: scratch-volume
      command: [ "sleep", "1000000" ]
  volumes:
    - name: scratch-volume
      ephemeral:
        volumeClaimTemplate:
          metadata:
            labels:
              type: my-frontend-volume
          spec:
            accessModes: [ "ReadWriteOnce" ]
            storageClassName: "scratch-storage-class"
            resources:
              requests:
                storage: 1Gi
```

---

## Jobs

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-tracking-with-finalizers

**Contents:**
- Jobs
- Running an example Job
- Writing a Job spec
  - Job Labels
  - Pod Template
  - Pod selector
  - Parallel execution for Jobs
    - Controlling parallelism
  - Completion mode
    - Note:

A Job creates one or more Pods and will continue to retry execution of the Pods until a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created. Suspending a Job will delete its active Pods until the Job is resumed again.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.

If you want to run a Job (either a single task, or several in parallel) on a schedule, see CronJob.

Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

You can run the example with this command:

The output is similar to this:

Check on the status of the Job with kubectl:

Name: pi Namespace: default Selector: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi ... Annotations: batch.kubernetes.io/job-tracking: "" Parallelism: 1 Completions: 1 Start Time: Mon, 02 Dec 2019 15:20:11 +0200 Completed At: Mon, 02 Dec 2019 15:21:16 +0200 Duration: 65s Pods Statuses: 0 Running / 1 Succeeded / 0 Failed Pod Template: Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi Containers: pi: Image: perl:5.34.0 Port: <none> Host Port: <none> Command: perl -Mbignum=bpi -wle print bpi(2000) Environment: <none> Mounts: <none> Volumes: <none> Events: Type Reason Age From Message ---- ------ ---- ---- ------- Normal SuccessfulCreate 21s job-controller Created pod: pi-xf9p4 Normal Completed 18s job-controller Job completed

apiVersion: batch/v1 kind: Job metadata: annotations: batch.kubernetes.io/job-tracking: "" ... creationTimestamp: "2022-11-10T17:53:53Z" generation: 1 labels: batch.kubernetes.io/controller-uid: 863452e6-270d-420e-9b94-53a54146c223 batch.kubernetes.io/job-name: pi name: pi namespace: default resourceVersion: "4751" uid: 204fb678-040b-497f-9266-35ffa8716d14 spec: backoffLimit: 4 completionMode: NonIndexed completions: 1 parallelism: 1 selector: matchLabels: batch.kubernetes.io/controller-uid: 863452e6-270d-4

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl:5.34.0
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/job.yaml
```

Example 3 (unknown):
```unknown
job.batch/pi created
```

Example 4 (bash):
```bash
Name:           pi
Namespace:      default
Selector:       batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
Labels:         batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
                batch.kubernetes.io/job-name=pi
                ...
Annotations:    batch.kubernetes.io/job-tracking: ""
Parallelism:    1
Completions:    1
Start Time:     Mon, 02 Dec 2019 15:20:11 +0200
Completed At:   Mon, 02 Dec 2019 15:21:16 +0200
Duration:       65s
Pods Statuses:  0 Running / 1 Succeeded / 0 Failed
Pod Template:
  Labels:  batch.kubernetes.io/controller-u
...
```

---

## Resource Management for Windows nodes

**URL:** https://kubernetes.io/docs/concepts/configuration/windows-resource-management/

**Contents:**
- Resource Management for Windows nodes
- Memory management
- CPU management
- Resource reservation
    - Caution:
- Feedback

This page outlines the differences in how resources are managed between Linux and Windows.

On Linux nodes, cgroups are used as a pod boundary for resource control. Containers are created within that boundary for network, process and file system isolation. The Linux cgroup APIs can be used to gather CPU, I/O, and memory use statistics.

In contrast, Windows uses a job object per container with a system namespace filter to contain all processes in a container and provide logical isolation from the host. (Job objects are a Windows process isolation mechanism and are different from what Kubernetes refers to as a Job).

There is no way to run a Windows container without the namespace filtering in place. This means that system privileges cannot be asserted in the context of the host, and thus privileged containers are not available on Windows. Containers cannot assume an identity from the host because the Security Account Manager (SAM) is separate.

Windows does not have an out-of-memory process killer as Linux does. Windows always treats all user-mode memory allocations as virtual, and pagefiles are mandatory.

Windows nodes do not overcommit memory for processes. The net effect is that Windows won't reach out of memory conditions the same way Linux does, and processes page to disk instead of being subject to out of memory (OOM) termination. If memory is over-provisioned and all physical memory is exhausted, then paging can slow down performance.

Windows can limit the amount of CPU time allocated for different processes but cannot guarantee a minimum amount of CPU time.

On Windows, the kubelet supports a command-line flag to set the scheduling priority of the kubelet process: --windows-priorityclass. This flag allows the kubelet process to get more CPU time slices when compared to other processes running on the Windows host. More information on the allowable values and their meaning is available at Windows Priority Classes. To ensure that running Pods do not starve the kubelet of CPU cycles, set this flag to ABOVE_NORMAL_PRIORITY_CLASS or above.

To account for memory and CPU used by the operating system, the container runtime, and by Kubernetes host processes such as the kubelet, you can (and should) reserve memory and CPU resources with the --kube-reserved and/or --system-reserved kubelet flags. On Windows these values are only used to calculate the node's allocatable resources.

As you deploy workloads, set resource memory and CPU limits on containers. Th

*[Content truncated]*

---

## Guide for Running Windows Containers in Kubernetes

**URL:** https://kubernetes.io/docs/concepts/windows/user-guide/

**Contents:**
- Guide for Running Windows Containers in Kubernetes
- Objectives
- Before you begin
- Getting Started: Deploying a Windows workload
    - Note:
    - Note:
- Observability
  - Capturing logs from workloads
- Configuring container user
  - Using configurable Container usernames

This page provides a walkthrough for some steps you can follow to run Windows containers using Kubernetes. The page also highlights some Windows specific functionality within Kubernetes.

It is important to note that creating and deploying services and workloads on Kubernetes behaves in much the same way for Linux and Windows containers. The kubectl commands to interface with the cluster are identical. The examples in this page are provided to jumpstart your experience with Windows containers.

Configure an example deployment to run Windows containers on a Windows node.

You should already have access to a Kubernetes cluster that includes a worker node running Windows Server.

The example YAML file below deploys a simple webserver application running inside a Windows container.

Create a manifest named win-webserver.yaml with the contents below:

Check that all nodes are healthy:

Deploy the service and watch for pod updates:

When the service is deployed correctly both Pods are marked as Ready. To exit the watch command, press Ctrl+C.

Check that the deployment succeeded. To verify:

Logs are an important element of observability; they enable users to gain insights into the operational aspect of workloads and are a key ingredient to troubleshooting issues. Because Windows containers and workloads inside Windows containers behave differently from Linux containers, users had a hard time collecting logs, limiting operational visibility. Windows workloads for example are usually configured to log to ETW (Event Tracing for Windows) or push entries to the application event log. LogMonitor, an open source tool by Microsoft, is the recommended way to monitor configured log sources inside a Windows container. LogMonitor supports monitoring event logs, ETW providers, and custom application logs, piping them to STDOUT for consumption by kubectl logs <pod>.

Follow the instructions in the LogMonitor GitHub page to copy its binaries and configuration files to all your containers and add the necessary entrypoints for LogMonitor to push your logs to STDOUT.

Windows containers can be configured to run their entrypoints and processes with different usernames than the image defaults. Learn more about it here.

Windows container workloads can be configured to use Group Managed Service Accounts (GMSA). Group Managed Service Accounts are a specific type of Active Directory account that provide automatic password management, simplified service principal name (SPN) management,

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: win-webserver
  labels:
    app: win-webserver
spec:
  ports:
    # the port that this service should serve on
    - port: 80
      targetPort: 80
  selector:
    app: win-webserver
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: win-webserver
  name: win-webserver
spec:
  replicas: 2
  selector:
    matchLabels:
      app: win-webserver
  template:
    metadata:
      labels:
        app: win-webserver
      name: win-webserver
    spec:
     containers:
      - name: windowswebserver
        image: mcr.
...
```

Example 2 (bash):
```bash
kubectl get nodes
```

Example 3 (bash):
```bash
kubectl apply -f win-webserver.yaml
kubectl get pods -o wide -w
```

Example 4 (yaml):
```yaml
nodeSelector:
    kubernetes.io/os: windows
    node.kubernetes.io/windows-build: '10.0.17763'
tolerations:
    - key: "os"
      operator: "Equal"
      value: "windows"
      effect: "NoSchedule"
```

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## DaemonSet

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/daemonset

**Contents:**
- DaemonSet
- Writing a DaemonSet Spec
  - Create a DaemonSet
  - Required Fields
  - Pod Template
  - Pod Selector
  - Running Pods on select Nodes
- How Daemon Pods are scheduled
    - Note:
  - Taints and tolerations

A DaemonSet ensures that all (or some) Nodes run a copy of a Pod. As nodes are added to the cluster, Pods are added to them. As nodes are removed from the cluster, those Pods are garbage collected. Deleting a DaemonSet will clean up the Pods it created.

Some typical uses of a DaemonSet are:

In a simple case, one DaemonSet, covering all nodes, would be used for each type of daemon. A more complex setup might use multiple DaemonSets for a single type of daemon, but with different flags and/or different memory and cpu requests for different hardware types.

You can describe a DaemonSet in a YAML file. For example, the daemonset.yaml file below describes a DaemonSet that runs the fluentd-elasticsearch Docker image:

Create a DaemonSet based on the YAML file:

As with all other Kubernetes config, a DaemonSet needs apiVersion, kind, and metadata fields. For general information about working with config files, see running stateless applications and object management using kubectl.

The name of a DaemonSet object must be a valid DNS subdomain name.

A DaemonSet also needs a .spec section.

The .spec.template is one of the required fields in .spec.

The .spec.template is a pod template. It has exactly the same schema as a Pod, except it is nested and does not have an apiVersion or kind.

In addition to required fields for a Pod, a Pod template in a DaemonSet has to specify appropriate labels (see pod selector).

A Pod Template in a DaemonSet must have a RestartPolicy equal to Always, or be unspecified, which defaults to Always.

The .spec.selector field is a pod selector. It works the same as the .spec.selector of a Job.

You must specify a pod selector that matches the labels of the .spec.template. Also, once a DaemonSet is created, its .spec.selector can not be mutated. Mutating the pod selector can lead to the unintentional orphaning of Pods, and it was found to be confusing to users.

The .spec.selector is an object consisting of two fields:

When the two are specified the result is ANDed.

The .spec.selector must match the .spec.template.metadata.labels. Config with these two not matching will be rejected by the API.

If you specify a .spec.template.spec.nodeSelector, then the DaemonSet controller will create Pods on nodes which match that node selector. Likewise if you specify a .spec.template.spec.affinity, then DaemonSet controller will create Pods on nodes which match that node affinity. If you do not specify either, then the DaemonSet controller will cr

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd-elasticsearch
  namespace: kube-system
  labels:
    k8s-app: fluentd-logging
spec:
  selector:
    matchLabels:
      name: fluentd-elasticsearch
  template:
    metadata:
      labels:
        name: fluentd-elasticsearch
    spec:
      tolerations:
      # these tolerations are to have the daemonset runnable on control plane nodes
      # remove them if your control plane nodes should not run pods
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernet
...
```

Example 2 (unknown):
```unknown
kubectl apply -f https://k8s.io/examples/controllers/daemonset.yaml
```

Example 3 (yaml):
```yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchFields:
      - key: metadata.name
        operator: In
        values:
        - target-host-name
```

---

## Pod Security Standards

**URL:** https://kubernetes.io/docs/concepts/security/pod-security-standards/

**Contents:**
- Pod Security Standards
- Profile Details
  - Privileged
  - Baseline
    - Note:
  - Restricted
    - Note:
- Policy Instantiation
  - Alternatives
- Pod OS field

The Pod Security Standards define three different policies to broadly cover the security spectrum. These policies are cumulative and range from highly-permissive to highly-restrictive. This guide outlines the requirements of each policy.

The Privileged policy is purposely-open, and entirely unrestricted. This type of policy is typically aimed at system- and infrastructure-level workloads managed by privileged, trusted users.

The Privileged policy is defined by an absence of restrictions. If you define a Pod where the Privileged security policy applies, the Pod you define is able to bypass typical container isolation mechanisms. For example, you can define a Pod that has access to the node's host network.

The Baseline policy is aimed at ease of adoption for common containerized workloads while preventing known privilege escalations. This policy is targeted at application operators and developers of non-critical applications. The following listed controls should be enforced/disallowed:

Windows Pods offer the ability to run HostProcess containers which enables privileged access to the Windows host machine. Privileged access to the host is disallowed in the Baseline policy.FEATURE STATE: Kubernetes v1.26 [stable]

Sharing the host namespaces must be disallowed.

Privileged Pods disable most security mechanisms and must be disallowed.

Adding additional capabilities beyond those listed below must be disallowed.

HostPath volumes must be forbidden.

HostPorts should be disallowed entirely (recommended) or restricted to a known list

The Host field in probes and lifecycle hooks must be disallowed.

On supported hosts, the RuntimeDefault AppArmor profile is applied by default. The baseline policy should prevent overriding or disabling the default AppArmor profile, or restrict overrides to an allowed set of profiles.

Setting the SELinux type is restricted, and setting a custom SELinux user or role option is forbidden.

The default /proc masks are set up to reduce attack surface, and should be required.

Seccomp profile must not be explicitly set to Unconfined.

Sysctls can disable security mechanisms or affect all containers on a host, and should be disallowed except for an allowed "safe" subset. A sysctl is considered safe if it is namespaced in the container or the Pod, and it is isolated from other Pods or processes on the same Node.

The Restricted policy is aimed at enforcing current Pod hardening best practices, at the expense of some compatibility. It i

*[Content truncated]*

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#dns

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#pod-name-label

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Hardening Guide - Scheduler Configuration

**URL:** https://kubernetes.io/docs/concepts/security/hardening-guide/scheduler/

**Contents:**
- Hardening Guide - Scheduler Configuration
- kube-scheduler configuration
  - Scheduler authentication & authorization command line options
  - Scheduler networking command line options
  - Scheduler TLS command line options
- Scheduling configurations for custom schedulers
  - Key considerations
- Disallow labeling nodes
- Feedback

The Kubernetes scheduler is one of the critical components of the control plane.

This document covers how to improve the security posture of the Scheduler.

A misconfigured scheduler can have security implications. Such a scheduler can target specific nodes and evict the workloads or applications that are sharing the node and its resources. This can aid an attacker with a Yo-Yo attack: an attack on a vulnerable autoscaler.

When setting up authentication configuration, it should be made sure that kube-scheduler's authentication remains consistent with kube-api-server's authentication. If any request has missing authentication headers, the authentication should happen through the kube-api-server allowing all authentication to be consistent in the cluster.

When using custom schedulers based on the Kubernetes scheduling code, cluster administrators need to be careful with plugins that use the queueSort, prefilter, filter, or permit extension points. These extension points control various stages of a scheduling process, and the wrong configuration can impact the kube-scheduler's behavior in your cluster.

When using a plugin that is not one of the default plugins, consider disabling the queueSort, filter and permit extension points as follows:

This creates a scheduler profile my-custom-scheduler. Whenever the .spec of a Pod does not have a value for .spec.schedulerName, the kube-scheduler runs for that Pod, using its main configuration, and default plugins. If you define a Pod with .spec.schedulerName set to my-custom-scheduler, the kube-scheduler runs but with a custom configuration; in that custom configuration, the queueSort, filter and permit extension points are disabled. If you use this KubeSchedulerConfiguration, and don't run any custom scheduler, and you then define a Pod with .spec.schedulerName set to nonexistent-scheduler (or any other scheduler name that doesn't exist in your cluster), no events would be generated for a pod.

A cluster administrator should ensure that cluster users cannot label the nodes. A malicious actor can use nodeSelector to schedule workloads on nodes where those workloads should not be present.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
  - schedulerName: my-scheduler
    plugins:
      # Disable specific plugins for different extension points
      # You can disable all plugins for an extension point using "*"
      queueSort:
        disabled:
        - name: "*"             # Disable all queueSort plugins
      # - name: "PrioritySort"  # Disable specific queueSort plugin
      filter:
        disabled:
        - name: "*"                 # Disable all filter plugins
      # - name: "NodeResourcesFit"  # Disable specific filter plugin
   
...
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#kubelet

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Kubernetes Scheduler

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/

**Contents:**
- Kubernetes Scheduler
- Scheduling overview
- kube-scheduler
  - Node selection in kube-scheduler
- What's next
- Feedback

In Kubernetes, scheduling refers to making sure that Pods are matched to Nodes so that Kubelet can run them.

A scheduler watches for newly created Pods that have no Node assigned. For every Pod that the scheduler discovers, the scheduler becomes responsible for finding the best Node for that Pod to run on. The scheduler reaches this placement decision taking into account the scheduling principles described below.

If you want to understand why Pods are placed onto a particular Node, or if you're planning to implement a custom scheduler yourself, this page will help you learn about scheduling.

kube-scheduler is the default scheduler for Kubernetes and runs as part of the control plane. kube-scheduler is designed so that, if you want and need to, you can write your own scheduling component and use that instead.

Kube-scheduler selects an optimal node to run newly created or not yet scheduled (unscheduled) pods. Since containers in pods - and pods themselves - can have different requirements, the scheduler filters out any nodes that don't meet a Pod's specific scheduling needs. Alternatively, the API lets you specify a node for a Pod when you create it, but this is unusual and is only done in special cases.

In a cluster, Nodes that meet the scheduling requirements for a Pod are called feasible nodes. If none of the nodes are suitable, the pod remains unscheduled until the scheduler is able to place it.

The scheduler finds feasible Nodes for a Pod and then runs a set of functions to score the feasible Nodes and picks a Node with the highest score among the feasible ones to run the Pod. The scheduler then notifies the API server about this decision in a process called binding.

Factors that need to be taken into account for scheduling decisions include individual and collective resource requirements, hardware / software / policy constraints, affinity and anti-affinity specifications, data locality, inter-workload interference, and so on.

kube-scheduler selects a node for the pod in a 2-step operation:

The filtering step finds the set of Nodes where it's feasible to schedule the Pod. For example, the PodFitsResources filter checks whether a candidate Node has enough available resources to meet a Pod's specific resource requests. After this step, the node list contains any suitable Nodes; often, there will be more than one. If the list is empty, that Pod isn't (yet) schedulable.

In the scoring step, the scheduler ranks the remaining nodes to choose the mos

*[Content truncated]*

---

## Admission Webhook Good Practices

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/

**Contents:**
- Admission Webhook Good Practices
- Importance of good webhook design
- Identify whether you use admission webhooks
- Choose an admission control mechanism
  - Use built-in validation and defaulting for CustomResourceDefinitions
- Performance and latency
  - Design admission webhooks for low latency
  - Prevent loops caused by competing controllers
  - Set a small timeout value
  - Use a load balancer to ensure webhook availability

This page provides good practices and considerations when designing admission webhooks in Kubernetes. This information is intended for cluster operators who run admission webhook servers or third-party applications that modify or validate your API requests.

Before reading this page, ensure that you're familiar with the following concepts:

Admission control occurs when any create, update, or delete request is sent to the Kubernetes API. Admission controllers intercept requests that match specific criteria that you define. These requests are then sent to mutating admission webhooks or validating admission webhooks. These webhooks are often written to ensure that specific fields in object specifications exist or have specific allowed values.

Webhooks are a powerful mechanism to extend the Kubernetes API. Badly-designed webhooks often result in workload disruptions because of how much control the webhooks have over objects in the cluster. Like other API extension mechanisms, webhooks are challenging to test at scale for compatibility with all of your workloads, other webhooks, add-ons, and plugins.

Additionally, with every release, Kubernetes adds or modifies the API with new features, feature promotions to beta or stable status, and deprecations. Even stable Kubernetes APIs are likely to change. For example, the Pod API changed in v1.29 to add the Sidecar containers feature. While it's rare for a Kubernetes object to enter a broken state because of a new Kubernetes API, webhooks that worked as expected with earlier versions of an API might not be able to reconcile more recent changes to that API. This can result in unexpected behavior after you upgrade your clusters to newer versions.

This page describes common webhook failure scenarios and how to avoid them by cautiously and thoughtfully designing and implementing your webhooks.

Even if you don't run your own admission webhooks, some third-party applications that you run in your clusters might use mutating or validating admission webhooks.

To check whether your cluster has any mutating admission webhooks, run the following command:

The output lists any mutating admission controllers in the cluster.

To check whether your cluster has any validating admission webhooks, run the following command:

The output lists any validating admission controllers in the cluster.

Kubernetes includes multiple admission control and policy enforcement options. Knowing when to use a specific option can help you to impro

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get mutatingwebhookconfigurations
```

Example 2 (shell):
```shell
kubectl get validatingwebhookconfigurations
```

---

## Kubernetes Object Management

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/

**Contents:**
- Kubernetes Object Management
- Management techniques
    - Warning:
- Imperative commands
  - Examples
  - Trade-offs
- Imperative object configuration
    - Warning:
  - Examples
  - Trade-offs

The kubectl command-line tool supports several different ways to create and manage Kubernetes objects. This document provides an overview of the different approaches. Read the Kubectl book for details of managing objects by Kubectl.

When using imperative commands, a user operates directly on live objects in a cluster. The user provides operations to the kubectl command as arguments or flags.

This is the recommended way to get started or to run a one-off task in a cluster. Because this technique operates directly on live objects, it provides no history of previous configurations.

Run an instance of the nginx container by creating a Deployment object:

Advantages compared to object configuration:

Disadvantages compared to object configuration:

In imperative object configuration, the kubectl command specifies the operation (create, replace, etc.), optional flags and at least one file name. The file specified must contain a full definition of the object in YAML or JSON format.

See the API reference for more details on object definitions.

Create the objects defined in a configuration file:

Delete the objects defined in two configuration files:

Update the objects defined in a configuration file by overwriting the live configuration:

Advantages compared to imperative commands:

Disadvantages compared to imperative commands:

Advantages compared to declarative object configuration:

Disadvantages compared to declarative object configuration:

When using declarative object configuration, a user operates on object configuration files stored locally, however the user does not define the operations to be taken on the files. Create, update, and delete operations are automatically detected per-object by kubectl. This enables working on directories, where different operations might be needed for different objects.

Process all object configuration files in the configs directory, and create or patch the live objects. You can first diff to see what changes are going to be made, and then apply:

Recursively process directories:

Advantages compared to imperative object configuration:

Disadvantages compared to imperative object configuration:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (sh):
```sh
kubectl create deployment nginx --image nginx
```

Example 2 (sh):
```sh
kubectl create -f nginx.yaml
```

Example 3 (sh):
```sh
kubectl delete -f nginx.yaml -f redis.yaml
```

Example 4 (sh):
```sh
kubectl replace -f nginx.yaml
```

---

## Leases

**URL:** https://kubernetes.io/docs/concepts/architecture/leases/

**Contents:**
- Leases
- Node heartbeats
- Leader election
- API server identity
- Workloads
- Feedback

Distributed systems often have a need for leases, which provide a mechanism to lock shared resources and coordinate activity between members of a set. In Kubernetes, the lease concept is represented by Lease objects in the coordination.k8s.io API Group, which are used for system-critical capabilities such as node heartbeats and component-level leader election.

Kubernetes uses the Lease API to communicate kubelet node heartbeats to the Kubernetes API server. For every Node , there is a Lease object with a matching name in the kube-node-lease namespace. Under the hood, every kubelet heartbeat is an update request to this Lease object, updating the spec.renewTime field for the Lease. The Kubernetes control plane uses the time stamp of this field to determine the availability of this Node.

See Node Lease objects for more details.

Kubernetes also uses Leases to ensure only one instance of a component is running at any given time. This is used by control plane components like kube-controller-manager and kube-scheduler in HA configurations, where only one instance of the component should be actively running while the other instances are on stand-by.

Read coordinated leader election to learn about how Kubernetes builds on the Lease API to select which component instance acts as leader.

Starting in Kubernetes v1.26, each kube-apiserver uses the Lease API to publish its identity to the rest of the system. While not particularly useful on its own, this provides a mechanism for clients to discover how many instances of kube-apiserver are operating the Kubernetes control plane. Existence of kube-apiserver leases enables future capabilities that may require coordination between each kube-apiserver.

You can inspect Leases owned by each kube-apiserver by checking for lease objects in the kube-system namespace with the name apiserver-<sha256-hash>. Alternatively you can use the label selector apiserver.kubernetes.io/identity=kube-apiserver:

The SHA256 hash used in the lease name is based on the OS hostname as seen by that API server. Each kube-apiserver should be configured to use a hostname that is unique within the cluster. New instances of kube-apiserver that use the same hostname will take over existing Leases using a new holder identity, as opposed to instantiating new Lease objects. You can check the hostname used by kube-apiserver by checking the value of the kubernetes.io/hostname label:

Expired leases from kube-apiservers that no longer exist are garbage c

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver
```

Example 2 (unknown):
```unknown
NAME                                        HOLDER                                                                           AGE
apiserver-07a5ea9b9b072c4a5f3d1c3702        apiserver-07a5ea9b9b072c4a5f3d1c3702_0c8914f7-0f35-440e-8676-7844977d3a05        5m33s
apiserver-7be9e061c59d368b3ddaf1376e        apiserver-7be9e061c59d368b3ddaf1376e_84f2a85d-37c1-4b14-b6b9-603e62e4896f        4m23s
apiserver-1dfef752bcb36637d2763d1868        apiserver-1dfef752bcb36637d2763d1868_c5ffa286-8a9a-45d4-91e7-61118ed58d2e        4m43s
```

Example 3 (shell):
```shell
kubectl -n kube-system get lease apiserver-07a5ea9b9b072c4a5f3d1c3702 -o yaml
```

Example 4 (yaml):
```yaml
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  creationTimestamp: "2023-07-02T13:16:48Z"
  labels:
    apiserver.kubernetes.io/identity: kube-apiserver
    kubernetes.io/hostname: master-1
  name: apiserver-07a5ea9b9b072c4a5f3d1c3702
  namespace: kube-system
  resourceVersion: "334899"
  uid: 90870ab5-1ba9-4523-b215-e4d4e662acb1
spec:
  holderIdentity: apiserver-07a5ea9b9b072c4a5f3d1c3702_0c8914f7-0f35-440e-8676-7844977d3a05
  leaseDurationSeconds: 3600
  renewTime: "2023-07-04T21:58:48.065888Z"
```

---

## Storage Classes

**URL:** https://kubernetes.io/docs/concepts/storage/storage-classes/

**Contents:**
- Storage Classes
- StorageClass objects
- Default StorageClass
    - Note:
- Provisioner
- Reclaim policy
- Volume expansion
    - Note:
- Mount options
- Volume binding mode

This document describes the concept of a StorageClass in Kubernetes. Familiarity with volumes and persistent volumes is suggested.

A StorageClass provides a way for administrators to describe the classes of storage they offer. Different classes might map to quality-of-service levels, or to backup policies, or to arbitrary policies determined by the cluster administrators. Kubernetes itself is unopinionated about what classes represent.

The Kubernetes concept of a storage class is similar to “profiles” in some other storage system designs.

Each StorageClass contains the fields provisioner, parameters, and reclaimPolicy, which are used when a PersistentVolume belonging to the class needs to be dynamically provisioned to satisfy a PersistentVolumeClaim (PVC).

The name of a StorageClass object is significant, and is how users can request a particular class. Administrators set the name and other parameters of a class when first creating StorageClass objects.

As an administrator, you can specify a default StorageClass that applies to any PVCs that don't request a specific class. For more details, see the PersistentVolumeClaim concept.

Here's an example of a StorageClass:

You can mark a StorageClass as the default for your cluster. For instructions on setting the default StorageClass, see Change the default StorageClass.

When a PVC does not specify a storageClassName, the default StorageClass is used.

If you set the storageclass.kubernetes.io/is-default-class annotation to true on more than one StorageClass in your cluster, and you then create a PersistentVolumeClaim with no storageClassName set, Kubernetes uses the most recently created default StorageClass.

You can create a PersistentVolumeClaim without specifying a storageClassName for the new PVC, and you can do so even when no default StorageClass exists in your cluster. In this case, the new PVC creates as you defined it, and the storageClassName of that PVC remains unset until a default becomes available.

You can have a cluster without any default StorageClass. If you don't mark any StorageClass as default (and one hasn't been set for you by, for example, a cloud provider), then Kubernetes cannot apply that defaulting for PersistentVolumeClaims that need it.

If or when a default StorageClass becomes available, the control plane identifies any existing PVCs without storageClassName. For the PVCs that either have an empty value for storageClassName or do not have this key, the control plane then 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: low-latency
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: csi-driver.example-vendor.example
reclaimPolicy: Retain # default value is Delete
allowVolumeExpansion: true
mountOptions:
  - discard # this might enable UNMAP / TRIM at the block storage layer
volumeBindingMode: WaitForFirstConsumer
parameters:
  guaranteedReadWriteLatency: "true" # provider-specific
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: task-pv-pod
spec:
  nodeSelector:
    kubernetes.io/hostname: kube-01
  volumes:
    - name: task-pv-storage
      persistentVolumeClaim:
        claimName: task-pv-claim
  containers:
    - name: task-pv-container
      image: nginx
      ports:
        - containerPort: 80
          name: "http-server"
      volumeMounts:
        - mountPath: "/usr/share/nginx/html"
          name: task-pv-storage
```

Example 3 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner:  example.com/example
parameters:
  type: pd-standard
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values:
    - us-central-1a
    - us-central-1b
```

Example 4 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  csi.storage.k8s.io/fstype: xfs
  type: io1
  iopsPerGB: "50"
  encrypted: "true"
  tagSpecification_1: "key1=value1"
  tagSpecification_2: "key2=value2"
allowedTopologies:
- matchLabelExpressions:
  - key: topology.ebs.csi.aws.com/zone
    values:
    - us-east-2c
```

---

## Liveness, Readiness, and Startup Probes

**URL:** https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/

**Contents:**
- Liveness, Readiness, and Startup Probes
- Liveness probe
- Readiness probe
- Startup probe
- Feedback

Kubernetes has various types of probes:

Liveness probes determine when to restart a container. For example, liveness probes could catch a deadlock when an application is running but unable to make progress.

If a container fails its liveness probe repeatedly, the kubelet restarts the container.

Liveness probes do not wait for readiness probes to succeed. If you want to wait before executing a liveness probe, you can either define initialDelaySeconds or use a startup probe.

Readiness probes determine when a container is ready to accept traffic. This is useful when waiting for an application to perform time-consuming initial tasks that depend on its backing services; for example: establishing network connections, loading files, and warming caches. Readiness probes can also be useful later in the container’s lifecycle, for example, when recovering from temporary faults or overloads.

If the readiness probe returns a failed state, Kubernetes removes the pod from all matching service endpoints.

Readiness probes run on the container during its whole lifecycle.

A startup probe verifies whether the application within a container is started. This can be used to adopt liveness checks on slow starting containers, avoiding them getting killed by the kubelet before they are up and running.

If such a probe is configured, it disables liveness and readiness checks until it succeeds.

This type of probe is only executed at startup, unlike liveness and readiness probes, which are run periodically.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Ingress

**URL:** https://kubernetes.io/docs/concepts/services-networking/ingress/

**Contents:**
- Ingress
    - Note:
- Terminology
- What is Ingress?
- Prerequisites
    - Note:
- The Ingress resource
  - Ingress rules
  - DefaultBackend
  - Resource backends

FEATURE STATE: Kubernetes v1.19 [stable]An API object that manages external access to the services in a cluster, typically HTTP.Ingress may provide load balancing, SSL termination and name-based virtual hosting.

An API object that manages external access to the services in a cluster, typically HTTP.

Ingress may provide load balancing, SSL termination and name-based virtual hosting.

For clarity, this guide defines the following terms:

Ingress exposes HTTP and HTTPS routes from outside the cluster to services within the cluster. Traffic routing is controlled by rules defined on the Ingress resource.

Here is a simple example where an Ingress sends all its traffic to one Service:

An Ingress may be configured to give Services externally-reachable URLs, load balance traffic, terminate SSL / TLS, and offer name-based virtual hosting. An Ingress controller is responsible for fulfilling the Ingress, usually with a load balancer, though it may also configure your edge router or additional frontends to help handle the traffic.

An Ingress does not expose arbitrary ports or protocols. Exposing services other than HTTP and HTTPS to the internet typically uses a service of type Service.Type=NodePort or Service.Type=LoadBalancer.

You must have an Ingress controller to satisfy an Ingress. Only creating an Ingress resource has no effect.

You may need to deploy an Ingress controller such as ingress-nginx. You can choose from a number of Ingress controllers.

Ideally, all Ingress controllers should fit the reference specification. In reality, the various Ingress controllers operate slightly differently.

A minimal Ingress resource example:

An Ingress needs apiVersion, kind, metadata and spec fields. The name of an Ingress object must be a valid DNS subdomain name. For general information about working with config files, see deploying applications, configuring containers, managing resources. Ingress frequently uses annotations to configure some options depending on the Ingress controller, an example of which is the rewrite-target annotation. Different Ingress controllers support different annotations. Review the documentation for your choice of Ingress controller to learn which annotations are supported.

The Ingress spec has all the information needed to configure a load balancer or proxy server. Most importantly, it contains a list of rules matched against all incoming requests. Ingress resource only supports rules for directing HTTP(S) traffic.

If the ingressClas

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minimal-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx-example
  rules:
  - http:
      paths:
      - path: /testpath
        pathType: Prefix
        backend:
          service:
            name: test
            port:
              number: 80
```

Example 2 (yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-resource-backend
spec:
  defaultBackend:
    resource:
      apiGroup: k8s.example.com
      kind: StorageBucket
      name: static-assets
  rules:
    - http:
        paths:
          - path: /icons
            pathType: ImplementationSpecific
            backend:
              resource:
                apiGroup: k8s.example.com
                kind: StorageBucket
                name: icon-assets
```

Example 3 (bash):
```bash
kubectl describe ingress ingress-resource-backend
```

Example 4 (unknown):
```unknown
Name:             ingress-resource-backend
Namespace:        default
Address:
Default backend:  APIGroup: k8s.example.com, Kind: StorageBucket, Name: static-assets
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /icons   APIGroup: k8s.example.com, Kind: StorageBucket, Name: icon-assets
Annotations:  <none>
Events:       <none>
```

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/#flexvolume

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Images

**URL:** https://kubernetes.io/docs/concepts/containers/images/

**Contents:**
- Images
    - Note:
- Image names
- Updating images
  - Image pull policy
    - Note:
    - Default image pull policy
    - Note:
    - Required image pull
  - ImagePullBackOff

A container image represents binary data that encapsulates an application and all its software dependencies. Container images are executable software bundles that can run standalone and that make very well-defined assumptions about their runtime environment.

You typically create a container image of your application and push it to a registry before referring to it in a Pod.

This page provides an outline of the container image concept.

Container images are usually given a name such as pause, example/mycontainer, or kube-apiserver. Images can also include a registry hostname; for example: fictional.registry.example/imagename, and possibly a port number as well; for example: fictional.registry.example:10443/imagename.

If you don't specify a registry hostname, Kubernetes assumes that you mean the Docker public registry. You can change this behavior by setting a default image registry in the container runtime configuration.

After the image name part you can add a tag or digest (in the same way you would when using with commands like docker or podman). Tags let you identify different versions of the same series of images. Digests are a unique identifier for a specific version of an image. Digests are hashes of the image's content, and are immutable. Tags can be moved to point to different images, but digests are fixed.

Image tags consist of lowercase and uppercase letters, digits, underscores (_), periods (.), and dashes (-). A tag can be up to 128 characters long, and must conform to the following regex pattern: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}. You can read more about it and find the validation regex in the OCI Distribution Specification. If you don't specify a tag, Kubernetes assumes you mean the tag latest.

Image digests consists of a hash algorithm (such as sha256) and a hash value. For example: sha256:1ff6c18fbef2045af6b9c16bf034cc421a29027b800e4f9b68ae9b1cb3e9ae07. You can find more information about the digest format in the OCI Image Specification.

Some image name examples that Kubernetes can use are:

When you first create a Deployment, StatefulSet, Pod, or other object that includes a PodTemplate, and a pull policy was not explicitly specified, then by default the pull policy of all containers in that Pod will be set to IfNotPresent. This policy causes the kubelet to skip pulling an image if it already exists.

The imagePullPolicy for a container and the tag of the image both affect when the kubelet attempts to pull (download) the specified im

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
    "auths": {
        "my-registry.example/images": { "auth": "…" },
        "*.my-registry.example/images": { "auth": "…" }
    }
}
```

Example 2 (json):
```json
{
    "auths": {
        "my-registry.example/images": {
            "auth": "…"
        },
        "my-registry.example/images/subpath": {
            "auth": "…"
        }
    }
}
```

Example 3 (shell):
```shell
kubectl create secret docker-registry <name> \
  --docker-server=<docker-registry-server> \
  --docker-username=<docker-user> \
  --docker-password=<docker-password> \
  --docker-email=<docker-email>
```

Example 4 (shell):
```shell
cat <<EOF > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: foo
  namespace: awesomeapps
spec:
  containers:
    - name: foo
      image: janedoe/awesomeapp:v1
  imagePullSecrets:
    - name: myregistrykey
EOF

cat <<EOF >> ./kustomization.yaml
resources:
- pod.yaml
EOF
```

---

## Volume Attributes Classes

**URL:** https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/

**Contents:**
- Volume Attributes Classes
- The VolumeAttributesClass API
  - Provisioner
  - Resizer
- Parameters
- Feedback

This page assumes that you are familiar with StorageClasses, volumes and PersistentVolumes in Kubernetes.

A VolumeAttributesClass provides a way for administrators to describe the mutable "classes" of storage they offer. Different classes might map to different quality-of-service levels. Kubernetes itself is un-opinionated about what these classes represent.

This feature is generally available (GA) as of version 1.34, and users have the option to disable it.

You can also only use VolumeAttributesClasses with storage backed by Container Storage Interface, and only where the relevant CSI driver implements the ModifyVolume API.

Each VolumeAttributesClass contains the driverName and parameters, which are used when a PersistentVolume (PV) belonging to the class needs to be dynamically provisioned or modified.

The name of a VolumeAttributesClass object is significant and is how users can request a particular class. Administrators set the name and other parameters of a class when first creating VolumeAttributesClass objects. While the name of a VolumeAttributesClass object in a PersistentVolumeClaim is mutable, the parameters in an existing class are immutable.

Each VolumeAttributesClass has a provisioner that determines what volume plugin is used for provisioning PVs. The field driverName must be specified.

The feature support for VolumeAttributesClass is implemented in kubernetes-csi/external-provisioner.

You are not restricted to specifying the kubernetes-csi/external-provisioner. You can also run and specify external provisioners, which are independent programs that follow a specification defined by Kubernetes. Authors of external provisioners have full discretion over where their code lives, how the provisioner is shipped, how it needs to be run, what volume plugin it uses, etc.

To understand how the provisioner works with VolumeAttributesClass, refer to the CSI external-provisioner documentation.

Each VolumeAttributesClass has a resizer that determines what volume plugin is used for modifying PVs. The field driverName must be specified.

The modifying volume feature support for VolumeAttributesClass is implemented in kubernetes-csi/external-resizer.

For example, an existing PersistentVolumeClaim is using a VolumeAttributesClass named silver:

A new VolumeAttributesClass gold is available in the cluster:

The end user can update the PVC with the new VolumeAttributesClass gold and apply:

To understand how the resizer works with VolumeAttributesCla

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: VolumeAttributesClass
metadata:
  name: silver
driverName: pd.csi.storage.gke.io
parameters:
  provisioned-iops: "3000"
  provisioned-throughput: "50"
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pv-claim
spec:
  …
  volumeAttributesClassName: silver
  …
```

Example 3 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: VolumeAttributesClass
metadata:
  name: gold
driverName: pd.csi.storage.gke.io
parameters:
  iops: "4000"
  throughput: "60"
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pv-claim
spec:
  …
  volumeAttributesClassName: gold
  …
```

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#cbor-encoding

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Networking on Windows

**URL:** https://kubernetes.io/docs/concepts/services-networking/windows-networking/

**Contents:**
- Networking on Windows
- Container networking on Windows
- Network modes
- IP address management (IPAM)
- Direct Server Return (DSR)
- Load balancing and Services
- Limitations
- Feedback

Kubernetes supports running nodes on either Linux or Windows. You can mix both kinds of node within a single cluster. This page provides an overview to networking specific to the Windows operating system.

Networking for Windows containers is exposed through CNI plugins. Windows containers function similarly to virtual machines in regards to networking. Each container has a virtual network adapter (vNIC) which is connected to a Hyper-V virtual switch (vSwitch). The Host Networking Service (HNS) and the Host Compute Service (HCS) work together to create containers and attach container vNICs to networks. HCS is responsible for the management of containers whereas HNS is responsible for the management of networking resources such as:

The Windows HNS and vSwitch implement namespacing and can create virtual NICs as needed for a pod or container. However, many configurations such as DNS, routes, and metrics are stored in the Windows registry database rather than as files inside /etc, which is how Linux stores those configurations. The Windows registry for the container is separate from that of the host, so concepts like mapping /etc/resolv.conf from the host into a container don't have the same effect they would on Linux. These must be configured using Windows APIs run in the context of that container. Therefore CNI implementations need to call the HNS instead of relying on file mappings to pass network details into the pod or container.

Windows supports five different networking drivers/modes: L2bridge, L2tunnel, Overlay (Beta), Transparent, and NAT. In a heterogeneous cluster with Windows and Linux worker nodes, you need to select a networking solution that is compatible on both Windows and Linux. The following table lists the out-of-tree plugins are supported on Windows, with recommendations on when to use each CNI:

As outlined above, the Flannel CNI plugin is also supported on Windows via the VXLAN network backend (Beta support ; delegates to win-overlay) and host-gateway network backend (stable support; delegates to win-bridge).

This plugin supports delegating to one of the reference CNI plugins (win-overlay, win-bridge), to work in conjunction with Flannel daemon on Windows (Flanneld) for automatic node subnet lease assignment and HNS network creation. This plugin reads in its own configuration file (cni.conf), and aggregates it with the environment variables from the FlannelD generated subnet.env file. It then delegates to one of the reference CNI plu

*[Content truncated]*

---

## Node-specific Volume Limits

**URL:** https://kubernetes.io/docs/concepts/storage/storage-limits/

**Contents:**
- Node-specific Volume Limits
- Kubernetes default limits
- Dynamic volume limits
  - Mutable CSI Node Allocatable Count
    - Periodic Updates
- Feedback

This page describes the maximum number of volumes that can be attached to a Node for various cloud providers.

Cloud providers like Google, Amazon, and Microsoft typically have a limit on how many volumes can be attached to a Node. It is important for Kubernetes to respect those limits. Otherwise, Pods scheduled on a Node could get stuck waiting for volumes to attach.

The Kubernetes scheduler has default limits on the number of volumes that can be attached to a Node:

Dynamic volume limits are supported for following volume types.

For volumes managed by in-tree volume plugins, Kubernetes automatically determines the Node type and enforces the appropriate maximum number of volumes for the node. For example:

On Google Compute Engine, up to 127 volumes can be attached to a node, depending on the node type.

For Amazon EBS disks on M5,C5,R5,T3 and Z1D instance types, Kubernetes allows only 25 volumes to be attached to a Node. For other instance types on Amazon Elastic Compute Cloud (EC2), Kubernetes allows 39 volumes to be attached to a Node.

On Azure, up to 64 disks can be attached to a node, depending on the node type. For more details, refer to Sizes for virtual machines in Azure.

If a CSI storage driver advertises a maximum number of volumes for a Node (using NodeGetInfo), the kube-scheduler honors that limit. Refer to the CSI specifications for details.

For volumes managed by in-tree plugins that have been migrated to a CSI driver, the maximum number of volumes will be the one reported by the CSI driver.

CSI drivers can dynamically adjust the maximum number of volumes that can be attached to a Node at runtime. This enhances scheduling accuracy and reduces pod scheduling failures due to changes in resource availability.

To use this feature, you must enable the MutableCSINodeAllocatableCount feature gate on the following components:

When enabled, CSI drivers can request periodic updates to their volume limits by setting the nodeAllocatableUpdatePeriodSeconds field in the CSIDriver specification. For example:

Kubelet will periodically call the corresponding CSI driver’s NodeGetInfo endpoint to refresh the maximum number of attachable volumes, using the interval specified in nodeAllocatableUpdatePeriodSeconds. The minimum allowed value for this field is 10 seconds.

If a volume attachment operation fails with a ResourceExhausted error (gRPC code 8), Kubernetes triggers an immediate update to the allocatable volume count for that Node. Additionally, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: hostpath.csi.k8s.io
spec:
  nodeAllocatableUpdatePeriodSeconds: 60
```

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#start-ordinal

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Limit Ranges

**URL:** https://kubernetes.io/docs/concepts/policy/limit-range/

**Contents:**
- Limit Ranges
- Constraints on resource limits and requests
- LimitRange and admission checks for Pods
    - Note:
- Example resource constraints
- What's next
- Feedback

By default, containers run with unbounded compute resources on a Kubernetes cluster. Using Kubernetes resource quotas, administrators (also termed cluster operators) can restrict consumption and creation of cluster resources (such as CPU time, memory, and persistent storage) within a specified namespace. Within a namespace, a Pod can consume as much CPU and memory as is allowed by the ResourceQuotas that apply to that namespace. As a cluster operator, or as a namespace-level administrator, you might also be concerned about making sure that a single object cannot monopolize all available resources within a namespace.

A LimitRange is a policy to constrain the resource allocations (limits and requests) that you can specify for each applicable object kind (such as Pod or PersistentVolumeClaim) in a namespace.

A LimitRange provides constraints that can:

Kubernetes constrains resource allocations to Pods in a particular namespace whenever there is at least one LimitRange object in that namespace.

The name of a LimitRange object must be a valid DNS subdomain name.

A LimitRange does not check the consistency of the default values it applies. This means that a default value for the limit that is set by LimitRange may be less than the request value specified for the container in the spec that a client submits to the API server. If that happens, the final Pod will not be schedulable.

For example, you define a LimitRange with below manifest:Note:The following examples operate within the default namespace of your cluster, as the namespace parameter is undefined and the LimitRange scope is limited to the namespace level. This implies that any references or operations within these examples will interact with elements within the default namespace of your cluster. You can override the operating namespace by configuring namespace in the metadata.namespace field.

along with a Pod that declares a CPU resource request of 700m, but not a limit:

then that Pod will not be scheduled, failing with an error similar to:

If you set both request and limit, then that new Pod will be scheduled successfully even with the same LimitRange in place:

Examples of policies that could be created using LimitRange are:

In the case where the total limits of the namespace is less than the sum of the limits of the Pods/Containers, there may be contention for resources. In this case, the Containers or Pods will not be created.

Neither contention nor changes to a LimitRange will affect alre

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-resource-constraint
spec:
  limits:
  - default: # this section defines default limits
      cpu: 500m
    defaultRequest: # this section defines default requests
      cpu: 500m
    max: # max and min define the limit range
      cpu: "1"
    min:
      cpu: 100m
    type: Container
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-conflict-with-limitrange-cpu
spec:
  containers:
  - name: demo
    image: registry.k8s.io/pause:3.8
    resources:
      requests:
        cpu: 700m
```

Example 3 (unknown):
```unknown
Pod "example-conflict-with-limitrange-cpu" is invalid: spec.containers[0].resources.requests: Invalid value: "700m": must be less than or equal to cpu limit
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-no-conflict-with-limitrange-cpu
spec:
  containers:
  - name: demo
    image: registry.k8s.io/pause:3.8
    resources:
      requests:
        cpu: 700m
      limits:
        cpu: 700m
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/#using-subpath

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Resource Management for Pods and Containers

**URL:** https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#extended-resources

**Contents:**
- Resource Management for Pods and Containers
- Requests and limits
    - Note:
    - Note:
- Resource types
    - Note:
- Resource requests and limits of Pod and container
- Pod-level resource specification
- Resource units in Kubernetes
  - CPU resource units

When you specify a Pod, you can optionally specify how much of each resource a container needs. The most common resources to specify are CPU and memory (RAM); there are others.

When you specify the resource request for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a resource limit for a container, the kubelet enforces those limits so that the running container is not allowed to use more of that resource than the limit you set. The kubelet also reserves at least the request amount of that system resource specifically for that container to use.

If the node where a Pod is running has enough of a resource available, it's possible (and allowed) for a container to use more resource than its request for that resource specifies.

For example, if you set a memory request of 256 MiB for a container, and that container is in a Pod scheduled to a Node with 8GiB of memory and no other Pods, then the container can try to use more RAM.

Limits are a different story. Both cpu and memory limits are applied by the kubelet (and container runtime), and are ultimately enforced by the kernel. On Linux nodes, the Linux kernel enforces limits with cgroups. The behavior of cpu and memory limit enforcement is slightly different.

cpu limits are enforced by CPU throttling. When a container approaches its cpu limit, the kernel will restrict access to the CPU corresponding to the container's limit. Thus, a cpu limit is a hard limit the kernel enforces. Containers may not use more CPU than is specified in their cpu limit.

memory limits are enforced by the kernel with out of memory (OOM) kills. When a container uses more than its memory limit, the kernel may terminate it. However, terminations only happen when the kernel detects memory pressure. Thus, a container that over allocates memory may not be immediately killed. This means memory limits are enforced reactively. A container may use more memory than its memory limit, but if it does, it may get killed.

CPU and memory are each a resource type. A resource type has a base unit. CPU represents compute processing and is specified in units of Kubernetes CPUs. Memory is specified in units of bytes. For Linux workloads, you can specify huge page resources. Huge pages are a Linux-specific feature where the node kernel allocates blocks of memory that are much larger than the default page size.

For example, on a system where the default page size is 4KiB, you coul

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
128974848, 129e6, 129M,  128974848000m, 123Mi
```

Example 2 (yaml):
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-resources-demo
  namespace: pod-resources-example
spec:
  resources:
    limits:
      cpu: "1"
      memory: "200Mi"
    requests:
      cpu: "1"
      memory: "100Mi"
  containers:
  - name: pod-resources-demo-ctr-1
    image: nginx
    resources:
      limits:
        cpu: "0.5"
        memory: "100Mi"
      requests:
        cpu: "0.5"
        memory: "50Mi"
  - name: pod-resources-demo-ctr-2
    image: fedora
    command:
    - sleep
    - inf
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend
spec:
  containers:
  - name: app
    image: images.my-company.example/app:v4
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  - name: log-aggregator
    image: images.my-company.example/log-aggregator:v6
    resources:
      requests:
        ephemeral-storage: "2Gi"
      limits:
        ephemeral-storage: "4Gi"
    volumeMounts:
    - name: ephemeral
      mountPath: "/tmp"
  volumes:
    - name: ephemeral
      e
...
```

---

## Projected Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/projected-volumes/#clustertrustbundle

**Contents:**
- Projected Volumes
- Introduction
  - Example configuration with a secret, a downwardAPI, and a configMap
  - Example configuration: secrets with a non-default permission mode set
- serviceAccountToken projected volumes
    - Note:
- clusterTrustBundle projected volumes
    - Note:
- podCertificate projected volumes
    - Note:

This document describes projected volumes in Kubernetes. Familiarity with volumes is suggested.

A projected volume maps several existing volume sources into the same directory.

Currently, the following types of volume sources can be projected:

All sources are required to be in the same namespace as the Pod. For more details, see the all-in-one volume design document.

Each projected volume source is listed in the spec under sources. The parameters are nearly the same with two exceptions:

You can inject the token for the current service account into a Pod at a specified path. For example:

The example Pod has a projected volume containing the injected service account token. Containers in this Pod can use that token to access the Kubernetes API server, authenticating with the identity of the pod's ServiceAccount. The audience field contains the intended audience of the token. A recipient of the token must identify itself with an identifier specified in the audience of the token, and otherwise should reject the token. This field is optional and it defaults to the identifier of the API server.

The expirationSeconds is the expected duration of validity of the service account token. It defaults to 1 hour and must be at least 10 minutes (600 seconds). An administrator can also limit its maximum value by specifying the --service-account-max-token-expiration option for the API server. The path field specifies a relative path to the mount point of the projected volume.

The clusterTrustBundle projected volume source injects the contents of one or more ClusterTrustBundle objects as an automatically-updating file in the container filesystem.

ClusterTrustBundles can be selected either by name or by signer name.

To select by name, use the name field to designate a single ClusterTrustBundle object.

To select by signer name, use the signerName field (and optionally the labelSelector field) to designate a set of ClusterTrustBundle objects that use the given signer name. If labelSelector is not present, then all ClusterTrustBundles for that signer are selected.

The kubelet deduplicates the certificates in the selected ClusterTrustBundle objects, normalizes the PEM representations (discarding comments and headers), reorders the certificates, and writes them into the file named by path. As the set of selected ClusterTrustBundles or their content changes, kubelet keeps the file up-to-date.

By default, the kubelet will prevent the pod from starting if the named Cluste

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: all-in-one
      mountPath: "/projected-volume"
      readOnly: true
  volumes:
  - name: all-in-one
    projected:
      sources:
      - secret:
          name: mysecret
          items:
            - key: username
              path: my-group/my-username
      - downwardAPI:
          items:
            - path: "labels"
              fieldRef:
                fieldPath: metadata.labels
            - path: "cp
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: all-in-one
      mountPath: "/projected-volume"
      readOnly: true
  volumes:
  - name: all-in-one
    projected:
      sources:
      - secret:
          name: mysecret
          items:
            - key: username
              path: my-group/my-username
      - secret:
          name: mysecret2
          items:
            - key: password
              path: my-group/my-password
              mode: 511
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sa-token-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: token-vol
      mountPath: "/service-account"
      readOnly: true
  serviceAccountName: default
  volumes:
  - name: token-vol
    projected:
      sources:
      - serviceAccountToken:
          audience: api
          expirationSeconds: 3600
          path: token
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sa-ctb-name-test
spec:
  containers:
  - name: container-test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: token-vol
      mountPath: "/root-certificates"
      readOnly: true
  serviceAccountName: default
  volumes:
  - name: token-vol
    projected:
      sources:
      - clusterTrustBundle:
          name: example
          path: example-roots.pem
      - clusterTrustBundle:
          signerName: "example.com/mysigner"
          labelSelector:
            matchLabels:
              version: live
          path: my
...
```

---

## Container Environment

**URL:** https://kubernetes.io/docs/concepts/containers/container-environment/

**Contents:**
- Container Environment
- Container environment
  - Container information
  - Cluster information
- What's next
- Feedback

This page describes the resources available to Containers in the Container environment.

The Kubernetes Container environment provides several important resources to Containers:

The hostname of a Container is the name of the Pod in which the Container is running. It is available through the hostname command or the gethostname function call in libc.

The Pod name and namespace are available as environment variables through the downward API.

User defined environment variables from the Pod definition are also available to the Container, as are any environment variables specified statically in the container image.

A list of all services that were running when a Container was created is available to that Container as environment variables. This list is limited to services within the same namespace as the new Container's Pod and Kubernetes control plane services.

For a service named foo that maps to a Container named bar, the following variables are defined:

Services have dedicated IP addresses and are available to the Container via DNS, if DNS addon is enabled.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
FOO_SERVICE_HOST=<the host the service is running on>
FOO_SERVICE_PORT=<the port the service is running on>
```

---

## Projected Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/projected-volumes/

**Contents:**
- Projected Volumes
- Introduction
  - Example configuration with a secret, a downwardAPI, and a configMap
  - Example configuration: secrets with a non-default permission mode set
- serviceAccountToken projected volumes
    - Note:
- clusterTrustBundle projected volumes
    - Note:
- podCertificate projected volumes
    - Note:

This document describes projected volumes in Kubernetes. Familiarity with volumes is suggested.

A projected volume maps several existing volume sources into the same directory.

Currently, the following types of volume sources can be projected:

All sources are required to be in the same namespace as the Pod. For more details, see the all-in-one volume design document.

Each projected volume source is listed in the spec under sources. The parameters are nearly the same with two exceptions:

You can inject the token for the current service account into a Pod at a specified path. For example:

The example Pod has a projected volume containing the injected service account token. Containers in this Pod can use that token to access the Kubernetes API server, authenticating with the identity of the pod's ServiceAccount. The audience field contains the intended audience of the token. A recipient of the token must identify itself with an identifier specified in the audience of the token, and otherwise should reject the token. This field is optional and it defaults to the identifier of the API server.

The expirationSeconds is the expected duration of validity of the service account token. It defaults to 1 hour and must be at least 10 minutes (600 seconds). An administrator can also limit its maximum value by specifying the --service-account-max-token-expiration option for the API server. The path field specifies a relative path to the mount point of the projected volume.

The clusterTrustBundle projected volume source injects the contents of one or more ClusterTrustBundle objects as an automatically-updating file in the container filesystem.

ClusterTrustBundles can be selected either by name or by signer name.

To select by name, use the name field to designate a single ClusterTrustBundle object.

To select by signer name, use the signerName field (and optionally the labelSelector field) to designate a set of ClusterTrustBundle objects that use the given signer name. If labelSelector is not present, then all ClusterTrustBundles for that signer are selected.

The kubelet deduplicates the certificates in the selected ClusterTrustBundle objects, normalizes the PEM representations (discarding comments and headers), reorders the certificates, and writes them into the file named by path. As the set of selected ClusterTrustBundles or their content changes, kubelet keeps the file up-to-date.

By default, the kubelet will prevent the pod from starting if the named Cluste

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: all-in-one
      mountPath: "/projected-volume"
      readOnly: true
  volumes:
  - name: all-in-one
    projected:
      sources:
      - secret:
          name: mysecret
          items:
            - key: username
              path: my-group/my-username
      - downwardAPI:
          items:
            - path: "labels"
              fieldRef:
                fieldPath: metadata.labels
            - path: "cp
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: all-in-one
      mountPath: "/projected-volume"
      readOnly: true
  volumes:
  - name: all-in-one
    projected:
      sources:
      - secret:
          name: mysecret
          items:
            - key: username
              path: my-group/my-username
      - secret:
          name: mysecret2
          items:
            - key: password
              path: my-group/my-password
              mode: 511
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sa-token-test
spec:
  containers:
  - name: container-test
    image: busybox:1.28
    command: ["sleep", "3600"]
    volumeMounts:
    - name: token-vol
      mountPath: "/service-account"
      readOnly: true
  serviceAccountName: default
  volumes:
  - name: token-vol
    projected:
      sources:
      - serviceAccountToken:
          audience: api
          expirationSeconds: 3600
          path: token
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sa-ctb-name-test
spec:
  containers:
  - name: container-test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: token-vol
      mountPath: "/root-certificates"
      readOnly: true
  serviceAccountName: default
  volumes:
  - name: token-vol
    projected:
      sources:
      - clusterTrustBundle:
          name: example
          path: example-roots.pem
      - clusterTrustBundle:
          signerName: "example.com/mysigner"
          labelSelector:
            matchLabels:
              version: live
          path: my
...
```

---

## Monitoring, Logging, and Debugging

**URL:** https://kubernetes.io/docs/tasks/debug/

**Contents:**
- Monitoring, Logging, and Debugging
- Getting help
  - Questions
- Help! My question isn't covered! I need help now!
  - Stack Exchange, Stack Overflow, or Server Fault
  - Slack
  - Forum
  - Bugs and feature requests
- Feedback

Sometimes things go wrong. This guide helps you gather the relevant information and resolve issues. It has four sections:

You should also check the known issues for the release you're using.

If your problem isn't answered by any of the guides above, there are variety of ways for you to get help from the Kubernetes community.

The documentation on this site has been structured to provide answers to a wide range of questions. Concepts explain the Kubernetes architecture and how each component works, while Setup provides practical instructions for getting started. Tasks show how to accomplish commonly used tasks, and Tutorials are more comprehensive walkthroughs of real-world, industry-specific, or end-to-end development scenarios. The Reference section provides detailed documentation on the Kubernetes API and command-line interfaces (CLIs), such as kubectl.

If you have questions related to software development for your containerized app, you can ask those on Stack Overflow.

If you have Kubernetes questions related to cluster management or configuration, you can ask those on Server Fault.

There are also several more specific Stack Exchange network sites which might be the right place to ask Kubernetes questions in areas such as DevOps, Software Engineering, or InfoSec.

Someone else from the community may have already asked a similar question or may be able to help with your problem.

The Kubernetes team will also monitor posts tagged Kubernetes. If there aren't any existing questions that help, please ensure that your question is on-topic on Stack Overflow, Server Fault, or the Stack Exchange Network site you're asking on, and read through the guidance on how to ask a new question, before asking a new one!

Many people from the Kubernetes community hang out on Kubernetes Slack in the #kubernetes-users channel. Slack requires registration; you can request an invitation, and registration is open to everyone). Feel free to come and ask any and all questions. Once registered, access the Kubernetes organisation in Slack via your web browser or via Slack's own dedicated app.

Once you are registered, browse the growing list of channels for various subjects of interest. For example, people new to Kubernetes may also want to join the #kubernetes-novice channel. As another example, developers should join the #kubernetes-contributors channel.

There are also many country specific / local language channels. Feel free to join these channels for localized support an

*[Content truncated]*

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/using-api/#enabling-or-disabling

**Contents:**
- API Overview
- API versioning
    - Note:
- API groups
- Enabling or disabling API groups
    - Note:
- Persistence
- What's next
- Feedback

This section provides reference information for the Kubernetes API.

The REST API is the fundamental fabric of Kubernetes. All operations and communications between components, and external user commands are REST API calls that the API Server handles. Consequently, everything in the Kubernetes platform is treated as an API object and has a corresponding entry in the API.

The Kubernetes API reference lists the API for Kubernetes version v1.34.

For general background information, read The Kubernetes API. Controlling Access to the Kubernetes API describes how clients can authenticate to the Kubernetes API server, and how their requests are authorized.

The JSON and Protobuf serialization schemas follow the same guidelines for schema changes. The following descriptions cover both formats.

The API versioning and software versioning are indirectly related. The API and release versioning proposal describes the relationship between API versioning and software versioning.

Different API versions indicate different levels of stability and support. You can find more information about the criteria for each level in the API Changes documentation.

Here's a summary of each level:

The version names contain beta (for example, v2beta3).

Built-in beta API versions are disabled by default and must be explicitly enabled in the kube-apiserver configuration to be used (except for beta versions of APIs introduced prior to Kubernetes 1.22, which were enabled by default).

Built-in beta API versions have a maximum lifetime of 9 months or 3 minor releases (whichever is longer) from introduction to deprecation, and 9 months or 3 minor releases (whichever is longer) from deprecation to removal.

The software is well tested. Enabling a feature is considered safe.

The support for a feature will not be dropped, though the details may change.

The schema and/or semantics of objects may change in incompatible ways in a subsequent beta or stable API version. When this happens, migration instructions are provided. Adapting to a subsequent beta or stable API version may require editing or re-creating API objects, and may not be straightforward. The migration may require downtime for applications that rely on the feature.

The software is not recommended for production uses. Subsequent releases may introduce incompatible changes. Use of beta API versions is required to transition to subsequent beta or stable API versions once the beta API version is deprecated and no longer served.

API

*[Content truncated]*

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Resource Quotas

**URL:** https://kubernetes.io/docs/concepts/policy/resource-quotas/

**Contents:**
- Resource Quotas
    - Caution:
- How Kubernetes ResourceQuotas work
    - Note:
- Enabling Resource Quota
- Types of resource quota
  - Quota for infrastructure resources
  - Quota for extended resources
  - Quota for storage
    - Quota for local ephemeral storage

When several users or teams share a cluster with a fixed number of nodes, there is a concern that one team could use more than its fair share of resources.

Resource quotas are a tool for administrators to address this concern.

A resource quota, defined by a ResourceQuota object, provides constraints that limit aggregate resource consumption per namespace. A ResourceQuota can also limit the quantity of objects that can be created in a namespace by API kind, as well as the total amount of infrastructure resources that may be consumed by API objects found in that namespace.

ResourceQuotas work like this:

Different teams work in different namespaces. This separation can be enforced with RBAC or any other authorization mechanism.

A cluster administrator creates at least one ResourceQuota for each namespace.

Users create resources (pods, services, etc.) in the namespace, and the quota system tracks usage to ensure it does not exceed hard resource limits defined in a ResourceQuota.

You can apply a scope to a ResourceQuota to limit where it applies,

If creating or updating a resource violates a quota constraint, the control plane rejects that request with HTTP status code 403 Forbidden. The error includes a message explaining the constraint that would have been violated.

If quotas are enabled in a namespace for resource such as cpu and memory, users must specify requests or limits for those values when they define a Pod; otherwise, the quota system may reject pod creation.

The resource quota walkthrough shows an example of how to avoid this problem.

You often do not create Pods directly; for example, you more usually create a workload management object such as a Deployment. If you create a Deployment that tries to use more resources than are available, the creation of the Deployment (or other workload management object) succeeds, but the Deployment may not be able to get all of the Pods it manages to exist. In that case you can check the status of the Deployment, for example with kubectl describe, to see what has happened.

You can use a LimitRange to automatically set a default request for these resources.

The name of a ResourceQuota object must be a valid DNS subdomain name.

Examples of policies that could be created using namespaces and quotas are:

In the case where the total capacity of the cluster is less than the sum of the quotas of the namespaces, there may be contention for resources. This is handled on a first-come-first-served basis.

Reso

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values:
          - middle
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pods-high
spec:
  hard:
    cpu: "1000"
    memory: "200Gi"
    pods: "10"
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values: ["high"]
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pods-medium
spec:
  hard:
    cpu: "10"
    memory: "20Gi"
    pods: "10"
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values: ["medium"]
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pods-low
spec:
  hard:
    cpu: "5"
    memory: "10Gi"
   
...
```

Example 3 (shell):
```shell
kubectl create -f ./quota.yaml
```

Example 4 (unknown):
```unknown
resourcequota/pods-high created
resourcequota/pods-medium created
resourcequota/pods-low created
```

---

## Concepts

**URL:** https://kubernetes.io/docs/concepts/

**Contents:**
      - Overview
      - Cluster Architecture
      - Containers
      - Workloads
      - Services, Load Balancing, and Networking
      - Storage
      - Configuration
      - Security
      - Policies
      - Scheduling, Preemption and Eviction

The Concepts section helps you learn about the parts of the Kubernetes system and the abstractions Kubernetes uses to represent your cluster, and helps you obtain a deeper understanding of how Kubernetes works.

Kubernetes is a portable, extensible, open source platform for managing containerized workloads and services, that facilitates both declarative configuration and automation. It has a large, rapidly growing ecosystem. Kubernetes services, support, and tools are widely available.

The architectural concepts behind Kubernetes.

Technology for packaging an application along with its runtime dependencies.

Understand Pods, the smallest deployable compute object in Kubernetes, and the higher-level abstractions that help you to run them.

Concepts and resources behind networking in Kubernetes.

Ways to provide both long-term and temporary storage to Pods in your cluster.

Resources that Kubernetes provides for configuring Pods.

Concepts for keeping your cloud-native workload secure.

Manage security and best-practices with policies.

Lower-level detail relevant to creating or administering a Kubernetes cluster.

Kubernetes supports nodes that run Microsoft Windows.

Different ways to change the behavior of your Kubernetes cluster.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#scheduling-extensions

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Pod Priority and Preemption

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/#pod-priority

**Contents:**
- Pod Priority and Preemption
    - Warning:
- How to use priority and preemption
    - Note:
- PriorityClass
  - Notes about PodPriority and existing clusters
  - Example PriorityClass
- Non-preempting PriorityClass
  - Example Non-preempting PriorityClass
- Pod priority

Pods can have priority. Priority indicates the importance of a Pod relative to other Pods. If a Pod cannot be scheduled, the scheduler tries to preempt (evict) lower priority Pods to make scheduling of the pending Pod possible.

In a cluster where not all users are trusted, a malicious user could create Pods at the highest possible priorities, causing other Pods to be evicted/not get scheduled. An administrator can use ResourceQuota to prevent users from creating pods at high priorities.

See limit Priority Class consumption by default for details.

To use priority and preemption:

Add one or more PriorityClasses.

Create Pods withpriorityClassName set to one of the added PriorityClasses. Of course you do not need to create the Pods directly; normally you would add priorityClassName to the Pod template of a collection object like a Deployment.

Keep reading for more information about these steps.

A PriorityClass is a non-namespaced object that defines a mapping from a priority class name to the integer value of the priority. The name is specified in the name field of the PriorityClass object's metadata. The value is specified in the required value field. The higher the value, the higher the priority. The name of a PriorityClass object must be a valid DNS subdomain name, and it cannot be prefixed with system-.

A PriorityClass object can have any 32-bit integer value smaller than or equal to 1 billion. This means that the range of values for a PriorityClass object is from -2147483648 to 1000000000 inclusive. Larger numbers are reserved for built-in PriorityClasses that represent critical system Pods. A cluster admin should create one PriorityClass object for each such mapping that they want.

PriorityClass also has two optional fields: globalDefault and description. The globalDefault field indicates that the value of this PriorityClass should be used for Pods without a priorityClassName. Only one PriorityClass with globalDefault set to true can exist in the system. If there is no PriorityClass with globalDefault set, the priority of Pods with no priorityClassName is zero.

The description field is an arbitrary string. It is meant to tell users of the cluster when they should use this PriorityClass.

If you upgrade an existing cluster without this feature, the priority of your existing Pods is effectively zero.

Addition of a PriorityClass with globalDefault set to true does not change the priorities of existing Pods. The value of such a PriorityClass is us

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "This priority class should be used for XYZ service pods only."
```

Example 2 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-nonpreempting
value: 1000000
preemptionPolicy: Never
globalDefault: false
description: "This priority class will not cause other pods to be preempted."
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  priorityClassName: high-priority
```

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-restart-rules

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#kube-controller-manager

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#client-extensions

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#node-components

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Service ClusterIP allocation

**URL:** https://kubernetes.io/docs/concepts/services-networking/cluster-ip-allocation/

**Contents:**
- Service ClusterIP allocation
- How Service ClusterIPs are allocated?
- Why do you need to reserve Service Cluster IPs?
- How can you avoid Service ClusterIP conflicts?
- Examples
  - Example 1
  - Example 2
  - Example 3
- What's next
- Feedback

In Kubernetes, Services are an abstract way to expose an application running on a set of Pods. Services can have a cluster-scoped virtual IP address (using a Service of type: ClusterIP). Clients can connect using that virtual IP address, and Kubernetes then load-balances traffic to that Service across the different backing Pods.

When Kubernetes needs to assign a virtual IP address for a Service, that assignment happens one of two ways:

Across your whole cluster, every Service ClusterIP must be unique. Trying to create a Service with a specific ClusterIP that has already been allocated will return an error.

Sometimes you may want to have Services running in well-known IP addresses, so other components and users in the cluster can use them.

The best example is the DNS Service for the cluster. As a soft convention, some Kubernetes installers assign the 10th IP address from the Service IP range to the DNS service. Assuming you configured your cluster with Service IP range 10.96.0.0/16 and you want your DNS Service IP to be 10.96.0.10, you'd have to create a Service like this:

But, as it was explained before, the IP address 10.96.0.10 has not been reserved. If other Services are created before or in parallel with dynamic allocation, there is a chance they can allocate this IP. Hence, you will not be able to create the DNS Service because it will fail with a conflict error.

The allocation strategy implemented in Kubernetes to allocate ClusterIPs to Services reduces the risk of collision.

The ClusterIP range is divided, based on the formula min(max(16, cidrSize / 16), 256), described as never less than 16 or more than 256 with a graduated step between them.

Dynamic IP assignment uses the upper band by default, once this has been exhausted it will use the lower range. This will allow users to use static allocations on the lower band with a low risk of collision.

This example uses the IP address range: 10.96.0.0/24 (CIDR notation) for the IP addresses of Services.

Range Size: 28 - 2 = 254Band Offset: min(max(16, 256/16), 256) = min(16, 256) = 16Static band start: 10.96.0.1Static band end: 10.96.0.16Range end: 10.96.0.254

This example uses the IP address range: 10.96.0.0/20 (CIDR notation) for the IP addresses of Services.

Range Size: 212 - 2 = 4094Band Offset: min(max(16, 4096/16), 256) = min(256, 256) = 256Static band start: 10.96.0.1Static band end: 10.96.1.0Range end: 10.96.15.254

This example uses the IP address range: 10.96.0.0/16 (CIDR notation) 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: CoreDNS
  name: kube-dns
  namespace: kube-system
spec:
  clusterIP: 10.96.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
    targetPort: 53
  - name: dns-tcp
    port: 53
    protocol: TCP
    targetPort: 53
  selector:
    k8s-app: kube-dns
  type: ClusterIP
```

---

## Owners and Dependents

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/

**Contents:**
- Owners and Dependents
- Owner references in object specifications
    - Note:
- Ownership and finalizers
- What's next
- Feedback

In Kubernetes, some objects are owners of other objects. For example, a ReplicaSet is the owner of a set of Pods. These owned objects are dependents of their owner.

Ownership is different from the labels and selectors mechanism that some resources also use. For example, consider a Service that creates EndpointSlice objects. The Service uses labels to allow the control plane to determine which EndpointSlice objects are used for that Service. In addition to the labels, each EndpointSlice that is managed on behalf of a Service has an owner reference. Owner references help different parts of Kubernetes avoid interfering with objects they don’t control.

Dependent objects have a metadata.ownerReferences field that references their owner object. A valid owner reference consists of the object name and a UID within the same namespace as the dependent object. Kubernetes sets the value of this field automatically for objects that are dependents of other objects like ReplicaSets, DaemonSets, Deployments, Jobs and CronJobs, and ReplicationControllers. You can also configure these relationships manually by changing the value of this field. However, you usually don't need to and can allow Kubernetes to automatically manage the relationships.

Dependent objects also have an ownerReferences.blockOwnerDeletion field that takes a boolean value and controls whether specific dependents can block garbage collection from deleting their owner object. Kubernetes automatically sets this field to true if a controller (for example, the Deployment controller) sets the value of the metadata.ownerReferences field. You can also set the value of the blockOwnerDeletion field manually to control which dependents block garbage collection.

A Kubernetes admission controller controls user access to change this field for dependent resources, based on the delete permissions of the owner. This control prevents unauthorized users from delaying owner object deletion.

Cross-namespace owner references are disallowed by design. Namespaced dependents can specify cluster-scoped or namespaced owners. A namespaced owner must exist in the same namespace as the dependent. If it does not, the owner reference is treated as absent, and the dependent is subject to deletion once all owners are verified absent.

Cluster-scoped dependents can only specify cluster-scoped owners. In v1.20+, if a cluster-scoped dependent specifies a namespaced kind as an owner, it is treated as having an unresolvable owner referen

*[Content truncated]*

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#combining-new-apis-with-automation

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## The Kubernetes API

**URL:** https://kubernetes.io/docs/concepts/overview/kubernetes-api/#openapi-interface-definition

**Contents:**
- The Kubernetes API
- Discovery API
  - Aggregated discovery
  - Unaggregated discovery
- OpenAPI interface definition
  - OpenAPI V2
    - Warning:
  - OpenAPI V3
  - Protobuf serialization
- Persistence

The core of Kubernetes' control plane is the API server. The API server exposes an HTTP API that lets end users, different parts of your cluster, and external components communicate with one another.

The Kubernetes API lets you query and manipulate the state of API objects in Kubernetes (for example: Pods, Namespaces, ConfigMaps, and Events).

Most operations can be performed through the kubectl command-line interface or other command-line tools, such as kubeadm, which in turn use the API. However, you can also access the API directly using REST calls. Kubernetes provides a set of client libraries for those looking to write applications using the Kubernetes API.

Each Kubernetes cluster publishes the specification of the APIs that the cluster serves. There are two mechanisms that Kubernetes uses to publish these API specifications; both are useful to enable automatic interoperability. For example, the kubectl tool fetches and caches the API specification for enabling command-line completion and other features. The two supported mechanisms are as follows:

The Discovery API provides information about the Kubernetes APIs: API names, resources, versions, and supported operations. This is a Kubernetes specific term as it is a separate API from the Kubernetes OpenAPI. It is intended to be a brief summary of the available resources and it does not detail specific schema for the resources. For reference about resource schemas, please refer to the OpenAPI document.

The Kubernetes OpenAPI Document provides (full) OpenAPI v2.0 and 3.0 schemas for all Kubernetes API endpoints. The OpenAPI v3 is the preferred method for accessing OpenAPI as it provides a more comprehensive and accurate view of the API. It includes all the available API paths, as well as all resources consumed and produced for every operations on every endpoints. It also includes any extensibility components that a cluster supports. The data is a complete specification and is significantly larger than that from the Discovery API.

Kubernetes publishes a list of all group versions and resources supported via the Discovery API. This includes the following for each resource:

The API is available in both aggregated and unaggregated form. The aggregated discovery serves two endpoints, while the unaggregated discovery serves a separate endpoint for each group version.

Kubernetes offers stable support for aggregated discovery, publishing all resources supported by a cluster through two endpoints (/api and

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
{
  "kind": "APIGroupList",
  "apiVersion": "v1",
  "groups": [
    {
      "name": "apiregistration.k8s.io",
      "versions": [
        {
          "groupVersion": "apiregistration.k8s.io/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apiregistration.k8s.io/v1",
        "version": "v1"
      }
    },
    {
      "name": "apps",
      "versions": [
        {
          "groupVersion": "apps/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apps/v1",
        "version": "v1"
      }
    }
...
```

Example 2 (yaml):
```yaml
{
    "paths": {
        ...,
        "api/v1": {
            "serverRelativeURL": "/openapi/v3/api/v1?hash=CC0E9BFD992D8C59AEC98A1E2336F899E8318D3CF4C68944C3DEC640AF5AB52D864AC50DAA8D145B3494F75FA3CFF939FCBDDA431DAD3CA79738B297795818CF"
        },
        "apis/admissionregistration.k8s.io/v1": {
            "serverRelativeURL": "/openapi/v3/apis/admissionregistration.k8s.io/v1?hash=E19CC93A116982CE5422FC42B590A8AFAD92CDE9AE4D59B5CAAD568F083AD07946E6CB5817531680BCE6E215C16973CD39003B0425F3477CFD854E89A9DB6597"
        },
        ....
    }
}
```

---

## CronJob

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/

**Contents:**
- CronJob
- Example
- Writing a CronJob spec
  - Schedule syntax
    - Note:
  - Job template
  - Deadline for delayed Job start
  - Concurrency policy
  - Schedule suspension
    - Caution:

A CronJob creates Jobs on a repeating schedule.

CronJob is meant for performing regular scheduled actions such as backups, report generation, and so on. One CronJob object is like one line of a crontab (cron table) file on a Unix system. It runs a Job periodically on a given schedule, written in Cron format.

CronJobs have limitations and idiosyncrasies. For example, in certain circumstances, a single CronJob can create multiple concurrent Jobs. See the limitations below.

When the control plane creates new Jobs and (indirectly) Pods for a CronJob, the .metadata.name of the CronJob is part of the basis for naming those Pods. The name of a CronJob must be a valid DNS subdomain value, but this can produce unexpected results for the Pod hostnames. For best compatibility, the name should follow the more restrictive rules for a DNS label. Even when the name is a DNS subdomain, the name must be no longer than 52 characters. This is because the CronJob controller will automatically append 11 characters to the name you provide and there is a constraint that the length of a Job name is no more than 63 characters.

This example CronJob manifest prints the current time and a hello message every minute:

(Running Automated Tasks with a CronJob takes you through this example in more detail).

The .spec.schedule field is required. The value of that field follows the Cron syntax:

For example, 0 3 * * 1 means this task is scheduled to run weekly on a Monday at 3 AM.

The format also includes extended "Vixie cron" step values. As explained in the FreeBSD manual:

Step values can be used in conjunction with ranges. Following a range with /<number> specifies skips of the number's value through the range. For example, 0-23/2 can be used in the hours field to specify command execution every other hour (the alternative in the V7 standard is 0,2,4,6,8,10,12,14,16,18,20,22). Steps are also permitted after an asterisk, so if you want to say "every two hours", just use */2.

Other than the standard syntax, some macros like @monthly can also be used:

To generate CronJob schedule expressions, you can also use web tools like crontab.guru.

The .spec.jobTemplate defines a template for the Jobs that the CronJob creates, and it is required. It has exactly the same schema as a Job, except that it is nested and does not have an apiVersion or kind. You can specify common metadata for the templated Jobs, such as labels or annotations. For information about writing a Job .spec, see Writing

*[Content truncated]*

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

Example 2 (unknown):
```unknown
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)
# │ │ │ │ │                                   OR sun, mon, tue, wed, thu, fri, sat
# │ │ │ │ │
# │ │ │ │ │
# * * * * *
```

Example 3 (unknown):
```unknown
Cannot determine if job needs to be started. Too many missed start time (> 100). Set or decrease .spec.startingDeadlineSeconds or check clock skew.
```

---

## Multi-tenancy

**URL:** https://kubernetes.io/docs/concepts/security/multi-tenancy/

**Contents:**
- Multi-tenancy
- Use cases
  - Multiple teams
  - Multiple customers
- Terminology
  - Tenants
    - A cluster showing coexisting tenancy models
  - Isolation
- Control plane isolation
  - Namespaces

This page provides an overview of available configuration options and best practices for cluster multi-tenancy.

Sharing clusters saves costs and simplifies administration. However, sharing clusters also presents challenges such as security, fairness, and managing noisy neighbors.

Clusters can be shared in many ways. In some cases, different applications may run in the same cluster. In other cases, multiple instances of the same application may run in the same cluster, one for each end user. All these types of sharing are frequently described using the umbrella term multi-tenancy.

While Kubernetes does not have first-class concepts of end users or tenants, it provides several features to help manage different tenancy requirements. These are discussed below.

The first step to determining how to share your cluster is understanding your use case, so you can evaluate the patterns and tools available. In general, multi-tenancy in Kubernetes clusters falls into two broad categories, though many variations and hybrids are also possible.

A common form of multi-tenancy is to share a cluster between multiple teams within an organization, each of whom may operate one or more workloads. These workloads frequently need to communicate with each other, and with other workloads located on the same or different clusters.

In this scenario, members of the teams often have direct access to Kubernetes resources via tools such as kubectl, or indirect access through GitOps controllers or other types of release automation tools. There is often some level of trust between members of different teams, but Kubernetes policies such as RBAC, quotas, and network policies are essential to safely and fairly share clusters.

The other major form of multi-tenancy frequently involves a Software-as-a-Service (SaaS) vendor running multiple instances of a workload for customers. This business model is so strongly associated with this deployment style that many people call it "SaaS tenancy." However, a better term might be "multi-customer tenancy," since SaaS vendors may also use other deployment models, and this deployment model can also be used outside of SaaS.

In this scenario, the customers do not have access to the cluster; Kubernetes is invisible from their perspective and is only used by the vendor to manage the workloads. Cost optimization is frequently a critical concern, and Kubernetes policies are used to ensure that the workloads are strongly isolated from each other.

When dis

*[Content truncated]*

---

## Good practices for Kubernetes Secrets

**URL:** https://kubernetes.io/docs/concepts/security/secrets-good-practices/

**Contents:**
- Good practices for Kubernetes Secrets
- Cluster administrators
  - Configure encryption at rest
  - Configure least-privilege access to Secrets
    - Caution:
    - Restrict Access for Secrets
  - Improve etcd management policies
  - Configure access to external Secrets
- Good practices for using swap memory
- Developers

In Kubernetes, a Secret is an object that stores sensitive information, such as passwords, OAuth tokens, and SSH keys.

In Kubernetes, a Secret is an object that stores sensitive information, such as passwords, OAuth tokens, and SSH keys.

Secrets give you more control over how sensitive information is used and reduces the risk of accidental exposure. Secret values are encoded as base64 strings and are stored unencrypted by default, but can be configured to be encrypted at rest.

A Pod can reference the Secret in a variety of ways, such as in a volume mount or as an environment variable. Secrets are designed for confidential data and ConfigMaps are designed for non-confidential data.

The following good practices are intended for both cluster administrators and application developers. Use these guidelines to improve the security of your sensitive information in Secret objects, as well as to more effectively manage your Secrets.

This section provides good practices that cluster administrators can use to improve the security of confidential information in the cluster.

By default, Secret objects are stored unencrypted in etcd. You should configure encryption of your Secret data in etcd. For instructions, refer to Encrypt Secret Data at Rest.

When planning your access control mechanism, such as Kubernetes Role-based Access Control (RBAC), consider the following guidelines for access to Secret objects. You should also follow the other guidelines in RBAC good practices.

A user who can create a Pod that uses a Secret can also see the value of that Secret. Even if cluster policies do not allow a user to read the Secret directly, the same user could have access to run a Pod that then exposes the Secret. You can detect or limit the impact caused by Secret data being exposed, either intentionally or unintentionally, by a user with this access. Some recommendations include:

Use separate namespaces to isolate access to mounted secrets.

Consider wiping or shredding the durable storage used by etcd once it is no longer in use.

If there are multiple etcd instances, configure encrypted SSL/TLS communication between the instances to protect the Secret data in transit.

You can use third-party Secrets store providers to keep your confidential data outside your cluster and then configure Pods to access that information. The Kubernetes Secrets Store CSI Driver is a DaemonSet that lets the kubelet retrieve Secrets from external stores, and mount the Secrets as a volume i

*[Content truncated]*

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/#csi

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Images

**URL:** https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod

**Contents:**
- Images
    - Note:
- Image names
- Updating images
  - Image pull policy
    - Note:
    - Default image pull policy
    - Note:
    - Required image pull
  - ImagePullBackOff

A container image represents binary data that encapsulates an application and all its software dependencies. Container images are executable software bundles that can run standalone and that make very well-defined assumptions about their runtime environment.

You typically create a container image of your application and push it to a registry before referring to it in a Pod.

This page provides an outline of the container image concept.

Container images are usually given a name such as pause, example/mycontainer, or kube-apiserver. Images can also include a registry hostname; for example: fictional.registry.example/imagename, and possibly a port number as well; for example: fictional.registry.example:10443/imagename.

If you don't specify a registry hostname, Kubernetes assumes that you mean the Docker public registry. You can change this behavior by setting a default image registry in the container runtime configuration.

After the image name part you can add a tag or digest (in the same way you would when using with commands like docker or podman). Tags let you identify different versions of the same series of images. Digests are a unique identifier for a specific version of an image. Digests are hashes of the image's content, and are immutable. Tags can be moved to point to different images, but digests are fixed.

Image tags consist of lowercase and uppercase letters, digits, underscores (_), periods (.), and dashes (-). A tag can be up to 128 characters long, and must conform to the following regex pattern: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}. You can read more about it and find the validation regex in the OCI Distribution Specification. If you don't specify a tag, Kubernetes assumes you mean the tag latest.

Image digests consists of a hash algorithm (such as sha256) and a hash value. For example: sha256:1ff6c18fbef2045af6b9c16bf034cc421a29027b800e4f9b68ae9b1cb3e9ae07. You can find more information about the digest format in the OCI Image Specification.

Some image name examples that Kubernetes can use are:

When you first create a Deployment, StatefulSet, Pod, or other object that includes a PodTemplate, and a pull policy was not explicitly specified, then by default the pull policy of all containers in that Pod will be set to IfNotPresent. This policy causes the kubelet to skip pulling an image if it already exists.

The imagePullPolicy for a container and the tag of the image both affect when the kubelet attempts to pull (download) the specified im

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
    "auths": {
        "my-registry.example/images": { "auth": "…" },
        "*.my-registry.example/images": { "auth": "…" }
    }
}
```

Example 2 (json):
```json
{
    "auths": {
        "my-registry.example/images": {
            "auth": "…"
        },
        "my-registry.example/images/subpath": {
            "auth": "…"
        }
    }
}
```

Example 3 (shell):
```shell
kubectl create secret docker-registry <name> \
  --docker-server=<docker-registry-server> \
  --docker-username=<docker-user> \
  --docker-password=<docker-password> \
  --docker-email=<docker-email>
```

Example 4 (shell):
```shell
cat <<EOF > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: foo
  namespace: awesomeapps
spec:
  containers:
    - name: foo
      image: janedoe/awesomeapp:v1
  imagePullSecrets:
    - name: myregistrykey
EOF

cat <<EOF >> ./kustomization.yaml
resources:
- pod.yaml
EOF
```

---

## Scheduling Framework

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/

**Contents:**
- Scheduling Framework
- Framework workflow
  - Scheduling cycle & binding cycle
- Interfaces
    - Scheduling framework extension points
  - PreEnqueue
  - EnqueueExtension
  - QueueingHint
  - QueueSort
  - PreFilter

The scheduling framework is a pluggable architecture for the Kubernetes scheduler. It consists of a set of "plugin" APIs that are compiled directly into the scheduler. These APIs allow most scheduling features to be implemented as plugins, while keeping the scheduling "core" lightweight and maintainable. Refer to the design proposal of the scheduling framework for more technical information on the design of the framework.

The Scheduling Framework defines a few extension points. Scheduler plugins register to be invoked at one or more extension points. Some of these plugins can change the scheduling decisions and some are informational only.

Each attempt to schedule one Pod is split into two phases, the scheduling cycle and the binding cycle.

The scheduling cycle selects a node for the Pod, and the binding cycle applies that decision to the cluster. Together, a scheduling cycle and binding cycle are referred to as a "scheduling context".

Scheduling cycles are run serially, while binding cycles may run concurrently.

A scheduling or binding cycle can be aborted if the Pod is determined to be unschedulable or if there is an internal error. The Pod will be returned to the queue and retried.

The following picture shows the scheduling context of a Pod and the interfaces that the scheduling framework exposes.

One plugin may implement multiple interfaces to perform more complex or stateful tasks.

Some interfaces match the scheduler extension points which can be configured through Scheduler Configuration.

These plugins are called prior to adding Pods to the internal active queue, where Pods are marked as ready for scheduling.

Only when all PreEnqueue plugins return Success, the Pod is allowed to enter the active queue. Otherwise, it's placed in the internal unschedulable Pods list, and doesn't get an Unschedulable condition.

For more details about how internal scheduler queues work, read Scheduling queue in kube-scheduler.

EnqueueExtension is the interface where the plugin can control whether to retry scheduling of Pods rejected by this plugin, based on changes in the cluster. Plugins that implement PreEnqueue, PreFilter, Filter, Reserve or Permit should implement this interface.

QueueingHint is a callback function for deciding whether a Pod can be requeued to the active queue or backoff queue. It's executed every time a certain kind of event or change happens in the cluster. When the QueueingHint finds that the event might make the Pod schedulable, the 

*[Content truncated]*

**Examples:**

Example 1 (go):
```go
func ScoreNode(_ *v1.pod, n *v1.Node) (int, error) {
    return getBlinkingLightCount(n)
}
```

Example 2 (go):
```go
func NormalizeScores(scores map[string]int) {
    highest := 0
    for _, score := range scores {
        highest = max(highest, score)
    }
    for node, score := range scores {
        scores[node] = score*NodeScoreMax/highest
    }
}
```

Example 3 (go):
```go
type Plugin interface {
    Name() string
}

type QueueSortPlugin interface {
    Plugin
    Less(*v1.pod, *v1.pod) bool
}

type PreFilterPlugin interface {
    Plugin
    PreFilter(context.Context, *framework.CycleState, *v1.pod) error
}

// ...
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#kube-proxy

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#container-resource-monitoring

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## ConfigMaps

**URL:** https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-object

**Contents:**
- ConfigMaps
    - Caution:
- Motivation
    - Note:
- ConfigMap object
- ConfigMaps and Pods
    - Note:
- Using ConfigMaps
  - Using ConfigMaps as files from a Pod
    - Mounted ConfigMaps are updated automatically

A ConfigMap is an API object used to store non-confidential data in key-value pairs. Pods can consume ConfigMaps as environment variables, command-line arguments, or as configuration files in a volume.

A ConfigMap is an API object used to store non-confidential data in key-value pairs. Pods can consume ConfigMaps as environment variables, command-line arguments, or as configuration files in a volume.

A ConfigMap allows you to decouple environment-specific configuration from your container images, so that your applications are easily portable.

Use a ConfigMap for setting configuration data separately from application code.

For example, imagine that you are developing an application that you can run on your own computer (for development) and in the cloud (to handle real traffic). You write the code to look in an environment variable named DATABASE_HOST. Locally, you set that variable to localhost. In the cloud, you set it to refer to a Kubernetes Service that exposes the database component to your cluster. This lets you fetch a container image running in the cloud and debug the exact same code locally if needed.

A ConfigMap is an API object that lets you store configuration for other objects to use. Unlike most Kubernetes objects that have a spec, a ConfigMap has data and binaryData fields. These fields accept key-value pairs as their values. Both the data field and the binaryData are optional. The data field is designed to contain UTF-8 strings while the binaryData field is designed to contain binary data as base64-encoded strings.

The name of a ConfigMap must be a valid DNS subdomain name.

Each key under the data or the binaryData field must consist of alphanumeric characters, -, _ or .. The keys stored in data must not overlap with the keys in the binaryData field.

Starting from v1.19, you can add an immutable field to a ConfigMap definition to create an immutable ConfigMap.

You can write a Pod spec that refers to a ConfigMap and configures the container(s) in that Pod based on the data in the ConfigMap. The Pod and the ConfigMap must be in the same namespace.

Here's an example ConfigMap that has some keys with single values, and other keys where the value looks like a fragment of a configuration format.

There are four different ways that you can use a ConfigMap to configure a container inside a Pod:

These different methods lend themselves to different ways of modeling the data being consumed. For the first three methods, the kubelet uses the 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: game-demo
data:
  # property-like keys; each key maps to a simple value
  player_initial_lives: "3"
  ui_properties_file_name: "user-interface.properties"

  # file-like keys
  game.properties: |
    enemy.types=aliens,monsters
    player.maximum-lives=5    
  user-interface.properties: |
    color.good=purple
    color.bad=yellow
    allow.textmode=true
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-demo-pod
spec:
  containers:
    - name: demo
      image: alpine
      command: ["sleep", "3600"]
      env:
        # Define the environment variable
        - name: PLAYER_INITIAL_LIVES # Notice that the case is different here
                                     # from the key name in the ConfigMap.
          valueFrom:
            configMapKeyRef:
              name: game-demo           # The ConfigMap this value comes from.
              key: player_initial_lives # The key to fetch.
        - name: UI_PROPERTIES_FILE_NAME
          val
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mypod
spec:
  containers:
  - name: mypod
    image: redis
    volumeMounts:
    - name: foo
      mountPath: "/etc/foo"
      readOnly: true
  volumes:
  - name: foo
    configMap:
      name: myconfigmap
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myconfigmap
data:
  username: k8s-admin
  access_level: "1"
```

---

## Kubernetes API Concepts

**URL:** https://kubernetes.io/docs/reference/using-api/api-concepts/#streaming-lists

**Contents:**
- Kubernetes API Concepts
- Kubernetes API terminology
  - Object names
  - API verbs
- Resource URIs
- HTTP media types
    - Chunked encoding of collections
  - JSON resource encoding
  - YAML resource encoding
  - Kubernetes Protobuf encoding

The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).

For some resources, the API includes additional subresources that allow fine-grained authorization (such as separate views for Pod details and log retrievals), and can accept and serve those resources in different representations for convenience or efficiency.

Kubernetes supports efficient change notifications on resources via watches:in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.

in the Kubernetes API, watch is a verb that is used to track changes to an object in Kubernetes as a stream. It is used for the efficient detection of changes.

You can view the API reference online, or read on to learn about the API in general.

Kubernetes generally leverages common RESTful terminology to describe the API concepts:

Most Kubernetes API resource types are objects – they represent a concrete instance of a concept on the cluster, like a pod or namespace. A smaller number of API resource types are virtual in that they often represent operations on objects, rather than objects, such as a permission check (use a POST with a JSON-encoded body of SubjectAccessReview to the subjectaccessreviews resource), or the eviction sub-resource of a Pod (used to trigger API-initiated eviction).

All objects you can create via the API have a unique object name to allow idempotent creation and retrieval, except that virtual resource types may not have unique names if they are not retrievable, or do not rely on idempotency. Within a namespace, only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name. Some objects are not namespaced (for example: Nodes), and so their names must be unique across the whole cluster.

Almost all object resource types support the standard HTTP verbs - GET, POST, PUT, PATCH, and DELETE. Kubernetes also uses its own verbs, which are often written in lowercase to distinguish them from HTTP verbs.

Kubernetes uses the term list to describe the action of returning a collection of resources, to disting

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
GET /api/v1/pods
```

Example 2 (unknown):
```unknown
200 OK
Content-Type: application/json

… JSON encoded collection of Pods (PodList object)
```

Example 3 (unknown):
```unknown
POST /api/v1/namespaces/test/pods
Content-Type: application/json
Accept: application/json
… JSON encoded Pod object
```

Example 4 (unknown):
```unknown
200 OK
Content-Type: application/json

{
  "kind": "Pod",
  "apiVersion": "v1",
  …
}
```

---

## Nodes

**URL:** https://kubernetes.io/docs/concepts/architecture/nodes/

**Contents:**
- Nodes
- Management
    - Note:
  - Node name uniqueness
  - Self-registration of Nodes
    - Note:
  - Manual Node administration
    - Note:
- Node status
- Node heartbeats

Kubernetes runs your workload by placing containers into Pods to run on Nodes. A node may be a virtual or physical machine, depending on the cluster. Each node is managed by the control plane and contains the services necessary to run Pods.

Typically you have several nodes in a cluster; in a learning or resource-limited environment, you might have only one node.

The components on a node include the kubelet, a container runtime, and the kube-proxy.

There are two main ways to have Nodes added to the API server:

After you create a Node object, or the kubelet on a node self-registers, the control plane checks whether the new Node object is valid. For example, if you try to create a Node from the following JSON manifest:

Kubernetes creates a Node object internally (the representation). Kubernetes checks that a kubelet has registered to the API server that matches the metadata.name field of the Node. If the node is healthy (i.e. all necessary services are running), then it is eligible to run a Pod. Otherwise, that node is ignored for any cluster activity until it becomes healthy.

Kubernetes keeps the object for the invalid Node and continues checking to see whether it becomes healthy.

You, or a controller, must explicitly delete the Node object to stop that health checking.

The name of a Node object must be a valid DNS subdomain name.

The name identifies a Node. Two Nodes cannot have the same name at the same time. Kubernetes also assumes that a resource with the same name is the same object. In case of a Node, it is implicitly assumed that an instance using the same name will have the same state (e.g. network settings, root disk contents) and attributes like node labels. This may lead to inconsistencies if an instance was modified without changing its name. If the Node needs to be replaced or updated significantly, the existing Node object needs to be removed from API server first and re-added after the update.

When the kubelet flag --register-node is true (the default), the kubelet will attempt to register itself with the API server. This is the preferred pattern, used by most distros.

For self-registration, the kubelet is started with the following options:

--kubeconfig - Path to credentials to authenticate itself to the API server.

--cloud-provider - How to talk to a cloud provider to read metadata about itself.

--register-node - Automatically register with the API server.

--register-with-taints - Register the node with the given list of taint

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
  "kind": "Node",
  "apiVersion": "v1",
  "metadata": {
    "name": "10.240.79.157",
    "labels": {
      "name": "my-first-k8s-node"
    }
  }
}
```

Example 2 (shell):
```shell
kubectl cordon $NODENAME
```

Example 3 (shell):
```shell
kubectl describe node <insert-node-name-here>
```

---

## Dynamic Volume Provisioning

**URL:** https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/

**Contents:**
- Dynamic Volume Provisioning
- Background
- Enabling Dynamic Provisioning
- Using Dynamic Provisioning
- Defaulting Behavior
- Topology Awareness
- Feedback

Dynamic volume provisioning allows storage volumes to be created on-demand. Without dynamic provisioning, cluster administrators have to manually make calls to their cloud or storage provider to create new storage volumes, and then create PersistentVolume objects to represent them in Kubernetes. The dynamic provisioning feature eliminates the need for cluster administrators to pre-provision storage. Instead, it automatically provisions storage when users create PersistentVolumeClaim objects.

The implementation of dynamic volume provisioning is based on the API object StorageClass from the API group storage.k8s.io. A cluster administrator can define as many StorageClass objects as needed, each specifying a volume plugin (aka provisioner) that provisions a volume and the set of parameters to pass to that provisioner when provisioning. A cluster administrator can define and expose multiple flavors of storage (from the same or different storage systems) within a cluster, each with a custom set of parameters. This design also ensures that end users don't have to worry about the complexity and nuances of how storage is provisioned, but still have the ability to select from multiple storage options.

More information on storage classes can be found here.

To enable dynamic provisioning, a cluster administrator needs to pre-create one or more StorageClass objects for users. StorageClass objects define which provisioner should be used and what parameters should be passed to that provisioner when dynamic provisioning is invoked. The name of a StorageClass object must be a valid DNS subdomain name.

The following manifest creates a storage class "slow" which provisions standard disk-like persistent disks.

The following manifest creates a storage class "fast" which provisions SSD-like persistent disks.

Users request dynamically provisioned storage by including a storage class in their PersistentVolumeClaim. Before Kubernetes v1.6, this was done via the volume.beta.kubernetes.io/storage-class annotation. However, this annotation is deprecated since v1.9. Users now can and should instead use the storageClassName field of the PersistentVolumeClaim object. The value of this field must match the name of a StorageClass configured by the administrator (see below).

To select the "fast" storage class, for example, a user would create the following PersistentVolumeClaim:

This claim results in an SSD-like Persistent Disk being automatically provisioned. When the claim is de

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: slow
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
```

Example 2 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: claim1
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast
  resources:
    requests:
      storage: 30Gi
```

---

## Windows Storage

**URL:** https://kubernetes.io/docs/concepts/storage/windows-storage/

**Contents:**
- Windows Storage
- Persistent storage
      - In-tree volume plugins
- Feedback

This page provides an storage overview specific to the Windows operating system.

Windows has a layered filesystem driver to mount container layers and create a copy filesystem based on NTFS. All file paths in the container are resolved only within the context of that container.

As a result, the following storage functionality is not supported on Windows nodes:

Kubernetes volumes enable complex applications, with data persistence and Pod volume sharing requirements, to be deployed on Kubernetes. Management of persistent volumes associated with a specific storage back-end or protocol includes actions such as provisioning/de-provisioning/resizing of volumes, attaching/detaching a volume to/from a Kubernetes node and mounting/dismounting a volume to/from individual containers in a pod that needs to persist data.

Volume management components are shipped as Kubernetes volume plugin. The following broad classes of Kubernetes volume plugins are supported on Windows:

The following in-tree plugins support persistent storage on Windows nodes:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Jobs

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/job/#completion-mode

**Contents:**
- Jobs
- Running an example Job
- Writing a Job spec
  - Job Labels
  - Pod Template
  - Pod selector
  - Parallel execution for Jobs
    - Controlling parallelism
  - Completion mode
    - Note:

A Job creates one or more Pods and will continue to retry execution of the Pods until a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created. Suspending a Job will delete its active Pods until the Job is resumed again.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.

If you want to run a Job (either a single task, or several in parallel) on a schedule, see CronJob.

Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

You can run the example with this command:

The output is similar to this:

Check on the status of the Job with kubectl:

Name: pi Namespace: default Selector: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi ... Annotations: batch.kubernetes.io/job-tracking: "" Parallelism: 1 Completions: 1 Start Time: Mon, 02 Dec 2019 15:20:11 +0200 Completed At: Mon, 02 Dec 2019 15:21:16 +0200 Duration: 65s Pods Statuses: 0 Running / 1 Succeeded / 0 Failed Pod Template: Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi Containers: pi: Image: perl:5.34.0 Port: <none> Host Port: <none> Command: perl -Mbignum=bpi -wle print bpi(2000) Environment: <none> Mounts: <none> Volumes: <none> Events: Type Reason Age From Message ---- ------ ---- ---- ------- Normal SuccessfulCreate 21s job-controller Created pod: pi-xf9p4 Normal Completed 18s job-controller Job completed

apiVersion: batch/v1 kind: Job metadata: annotations: batch.kubernetes.io/job-tracking: "" ... creationTimestamp: "2022-11-10T17:53:53Z" generation: 1 labels: batch.kubernetes.io/controller-uid: 863452e6-270d-420e-9b94-53a54146c223 batch.kubernetes.io/job-name: pi name: pi namespace: default resourceVersion: "4751" uid: 204fb678-040b-497f-9266-35ffa8716d14 spec: backoffLimit: 4 completionMode: NonIndexed completions: 1 parallelism: 1 selector: matchLabels: batch.kubernetes.io/controller-uid: 863452e6-270d-4

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl:5.34.0
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/job.yaml
```

Example 3 (unknown):
```unknown
job.batch/pi created
```

Example 4 (bash):
```bash
Name:           pi
Namespace:      default
Selector:       batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
Labels:         batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
                batch.kubernetes.io/job-name=pi
                ...
Annotations:    batch.kubernetes.io/job-tracking: ""
Parallelism:    1
Completions:    1
Start Time:     Mon, 02 Dec 2019 15:20:11 +0200
Completed At:   Mon, 02 Dec 2019 15:21:16 +0200
Duration:       65s
Pods Statuses:  0 Running / 1 Succeeded / 0 Failed
Pod Template:
  Labels:  batch.kubernetes.io/controller-u
...
```

---

## Disruptions

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/disruptions/

**Contents:**
- Disruptions
- Voluntary and involuntary disruptions
    - Caution:
- Dealing with disruptions
- Pod disruption budgets
- PodDisruptionBudget example
- Pod disruption conditions
    - Note:
- Separating Cluster Owner and Application Owner Roles
- How to perform Disruptive Actions on your Cluster

This guide is for application owners who want to build highly available applications, and thus need to understand what types of disruptions can happen to Pods.

It is also for cluster administrators who want to perform automated cluster actions, like upgrading and autoscaling clusters.

Pods do not disappear until someone (a person or a controller) destroys them, or there is an unavoidable hardware or system software error.

We call these unavoidable cases involuntary disruptions to an application. Examples are:

Except for the out-of-resources condition, all these conditions should be familiar to most users; they are not specific to Kubernetes.

We call other cases voluntary disruptions. These include both actions initiated by the application owner and those initiated by a Cluster Administrator. Typical application owner actions include:

Cluster administrator actions include:

These actions might be taken directly by the cluster administrator, or by automation run by the cluster administrator, or by your cluster hosting provider.

Ask your cluster administrator or consult your cloud provider or distribution documentation to determine if any sources of voluntary disruptions are enabled for your cluster. If none are enabled, you can skip creating Pod Disruption Budgets.

Here are some ways to mitigate involuntary disruptions:

The frequency of voluntary disruptions varies. On a basic Kubernetes cluster, there are no automated voluntary disruptions (only user-triggered ones). However, your cluster administrator or hosting provider may run some additional services which cause voluntary disruptions. For example, rolling out node software updates can cause voluntary disruptions. Also, some implementations of cluster (node) autoscaling may cause voluntary disruptions to defragment and compact nodes. Your cluster administrator or hosting provider should have documented what level of voluntary disruptions, if any, to expect. Certain configuration options, such as using PriorityClasses in your pod spec can also cause voluntary (and involuntary) disruptions.

Kubernetes offers features to help you run highly available applications even when you introduce frequent voluntary disruptions.

As an application owner, you can create a PodDisruptionBudget (PDB) for each application. A PDB limits the number of Pods of a replicated application that are down simultaneously from voluntary disruptions. For example, a quorum-based application would like to ensure that the number

*[Content truncated]*

---

## Installing Addons

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/addons/

**Contents:**
- Installing Addons
- Networking and Network Policy
- Service Discovery
- Visualization & Control
- Infrastructure
- Instrumentation
- Legacy Add-ons
- Feedback

Add-ons extend the functionality of Kubernetes.

This page lists some of the available add-ons and links to their respective installation instructions. The list does not try to be exhaustive.

There are several other add-ons documented in the deprecated cluster/addons directory.

Well-maintained ones should be linked to here. PRs welcome!

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Organizing Cluster Access Using kubeconfig Files

**URL:** https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/

**Contents:**
- Organizing Cluster Access Using kubeconfig Files
    - Note:
    - Warning:
- Supporting multiple clusters, users, and authentication mechanisms
- Context
- The KUBECONFIG environment variable
- Merging kubeconfig files
- File references
- Proxy
- What's next

Use kubeconfig files to organize information about clusters, users, namespaces, and authentication mechanisms. The kubectl command-line tool uses kubeconfig files to find the information it needs to choose a cluster and communicate with the API server of a cluster.

By default, kubectl looks for a file named config in the $HOME/.kube directory. You can specify other kubeconfig files by setting the KUBECONFIG environment variable or by setting the --kubeconfig flag.

For step-by-step instructions on creating and specifying kubeconfig files, see Configure Access to Multiple Clusters.

Suppose you have several clusters, and your users and components authenticate in a variety of ways. For example:

With kubeconfig files, you can organize your clusters, users, and namespaces. You can also define contexts to quickly and easily switch between clusters and namespaces.

A context element in a kubeconfig file is used to group access parameters under a convenient name. Each context has three parameters: cluster, namespace, and user. By default, the kubectl command-line tool uses parameters from the current context to communicate with the cluster.

To choose the current context:

The KUBECONFIG environment variable holds a list of kubeconfig files. For Linux and Mac, the list is colon-delimited. For Windows, the list is semicolon-delimited. The KUBECONFIG environment variable is not required. If the KUBECONFIG environment variable doesn't exist, kubectl uses the default kubeconfig file, $HOME/.kube/config.

If the KUBECONFIG environment variable does exist, kubectl uses an effective configuration that is the result of merging the files listed in the KUBECONFIG environment variable.

To see your configuration, enter this command:

As described previously, the output might be from a single kubeconfig file, or it might be the result of merging several kubeconfig files.

Here are the rules that kubectl uses when it merges kubeconfig files:

If the --kubeconfig flag is set, use only the specified file. Do not merge. Only one instance of this flag is allowed.

Otherwise, if the KUBECONFIG environment variable is set, use it as a list of files that should be merged. Merge the files listed in the KUBECONFIG environment variable according to these rules:

For an example of setting the KUBECONFIG environment variable, see Setting the KUBECONFIG environment variable.

Otherwise, use the default kubeconfig file, $HOME/.kube/config, with no merging.

Determine the context to use b

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
kubectl config use-context
```

Example 2 (shell):
```shell
kubectl config view
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Config

clusters:
- cluster:
    proxy-url: http://proxy.example.org:3128
    server: https://k8s.example.org/k8s/clusters/c-xxyyzz
  name: development

users:
- name: developer

contexts:
- context:
  name: development
```

---

## Kubernetes Self-Healing

**URL:** https://kubernetes.io/docs/concepts/architecture/self-healing/

**Contents:**
- Kubernetes Self-Healing
- Self-Healing capabilities
- Considerations
- What's next
- Feedback

Kubernetes is designed with self-healing capabilities that help maintain the health and availability of workloads. It automatically replaces failed containers, reschedules workloads when nodes become unavailable, and ensures that the desired state of the system is maintained.

Container-level restarts: If a container inside a Pod fails, Kubernetes restarts it based on the restartPolicy.

Replica replacement: If a Pod in a Deployment or StatefulSet fails, Kubernetes creates a replacement Pod to maintain the specified number of replicas. If a Pod fails that is part of a DaemonSet fails, the control plane creates a replacement Pod to run on the same node.

Persistent storage recovery: If a node is running a Pod with a PersistentVolume (PV) attached, and the node fails, Kubernetes can reattach the volume to a new Pod on a different node.

Load balancing for Services: If a Pod behind a Service fails, Kubernetes automatically removes it from the Service's endpoints to route traffic only to healthy Pods.

Here are some of the key components that provide Kubernetes self-healing:

kubelet: Ensures that containers are running, and restarts those that fail.

ReplicaSet, StatefulSet and DaemonSet controller: Maintains the desired number of Pod replicas.

PersistentVolume controller: Manages volume attachment and detachment for stateful workloads.

Storage Failures: If a persistent volume becomes unavailable, recovery steps may be required.

Application Errors: Kubernetes can restart containers, but underlying application issues must be addressed separately.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Network Policies

**URL:** https://kubernetes.io/docs/concepts/services-networking/network-policies/

**Contents:**
- Network Policies
- Prerequisites
- The two sorts of pod isolation
- The NetworkPolicy resource
    - Note:
- Behavior of to and from selectors
- Default policies
  - Default deny all ingress traffic
  - Allow all ingress traffic
  - Default deny all egress traffic

If you want to control traffic flow at the IP address or port level for TCP, UDP, and SCTP protocols, then you might consider using Kubernetes NetworkPolicies for particular applications in your cluster. NetworkPolicies are an application-centric construct which allow you to specify how a pod is allowed to communicate with various network "entities" (we use the word "entity" here to avoid overloading the more common terms such as "endpoints" and "services", which have specific Kubernetes connotations) over the network. NetworkPolicies apply to a connection with a pod on one or both ends, and are not relevant to other connections.

The entities that a Pod can communicate with are identified through a combination of the following three identifiers:

When defining a pod- or namespace-based NetworkPolicy, you use a selector to specify what traffic is allowed to and from the Pod(s) that match the selector.

Meanwhile, when IP-based NetworkPolicies are created, we define policies based on IP blocks (CIDR ranges).

Network policies are implemented by the network plugin. To use network policies, you must be using a networking solution which supports NetworkPolicy. Creating a NetworkPolicy resource without a controller that implements it will have no effect.

There are two sorts of isolation for a pod: isolation for egress, and isolation for ingress. They concern what connections may be established. "Isolation" here is not absolute, rather it means "some restrictions apply". The alternative, "non-isolated for $direction", means that no restrictions apply in the stated direction. The two sorts of isolation (or not) are declared independently, and are both relevant for a connection from one pod to another.

By default, a pod is non-isolated for egress; all outbound connections are allowed. A pod is isolated for egress if there is any NetworkPolicy that both selects the pod and has "Egress" in its policyTypes; we say that such a policy applies to the pod for egress. When a pod is isolated for egress, the only allowed connections from the pod are those allowed by the egress list of some NetworkPolicy that applies to the pod for egress. Reply traffic for those allowed connections will also be implicitly allowed. The effects of those egress lists combine additively.

By default, a pod is non-isolated for ingress; all inbound connections are allowed. A pod is isolated for ingress if there is any NetworkPolicy that both selects the pod and has "Ingress" in its policyTypes;

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - ipBlock:
        cidr: 172.17.0.0/16
        except:
        - 172.17.1.0/24
    - namespaceSelector:
        matchLabels:
          project: myproject
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 6379
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/24
    ports:
    - protocol: TCP
      port: 597
...
```

Example 2 (yaml):
```yaml
...
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          user: alice
      podSelector:
        matchLabels:
          role: client
  ...
```

Example 3 (yaml):
```yaml
...
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          user: alice
    - podSelector:
        matchLabels:
          role: client
  ...
```

Example 4 (yaml):
```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#api-access-extensions

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## The Kubernetes API

**URL:** https://kubernetes.io/docs/concepts/overview/kubernetes-api/

**Contents:**
- The Kubernetes API
- Discovery API
  - Aggregated discovery
  - Unaggregated discovery
- OpenAPI interface definition
  - OpenAPI V2
    - Warning:
  - OpenAPI V3
  - Protobuf serialization
- Persistence

The core of Kubernetes' control plane is the API server. The API server exposes an HTTP API that lets end users, different parts of your cluster, and external components communicate with one another.

The Kubernetes API lets you query and manipulate the state of API objects in Kubernetes (for example: Pods, Namespaces, ConfigMaps, and Events).

Most operations can be performed through the kubectl command-line interface or other command-line tools, such as kubeadm, which in turn use the API. However, you can also access the API directly using REST calls. Kubernetes provides a set of client libraries for those looking to write applications using the Kubernetes API.

Each Kubernetes cluster publishes the specification of the APIs that the cluster serves. There are two mechanisms that Kubernetes uses to publish these API specifications; both are useful to enable automatic interoperability. For example, the kubectl tool fetches and caches the API specification for enabling command-line completion and other features. The two supported mechanisms are as follows:

The Discovery API provides information about the Kubernetes APIs: API names, resources, versions, and supported operations. This is a Kubernetes specific term as it is a separate API from the Kubernetes OpenAPI. It is intended to be a brief summary of the available resources and it does not detail specific schema for the resources. For reference about resource schemas, please refer to the OpenAPI document.

The Kubernetes OpenAPI Document provides (full) OpenAPI v2.0 and 3.0 schemas for all Kubernetes API endpoints. The OpenAPI v3 is the preferred method for accessing OpenAPI as it provides a more comprehensive and accurate view of the API. It includes all the available API paths, as well as all resources consumed and produced for every operations on every endpoints. It also includes any extensibility components that a cluster supports. The data is a complete specification and is significantly larger than that from the Discovery API.

Kubernetes publishes a list of all group versions and resources supported via the Discovery API. This includes the following for each resource:

The API is available in both aggregated and unaggregated form. The aggregated discovery serves two endpoints, while the unaggregated discovery serves a separate endpoint for each group version.

Kubernetes offers stable support for aggregated discovery, publishing all resources supported by a cluster through two endpoints (/api and

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
{
  "kind": "APIGroupList",
  "apiVersion": "v1",
  "groups": [
    {
      "name": "apiregistration.k8s.io",
      "versions": [
        {
          "groupVersion": "apiregistration.k8s.io/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apiregistration.k8s.io/v1",
        "version": "v1"
      }
    },
    {
      "name": "apps",
      "versions": [
        {
          "groupVersion": "apps/v1",
          "version": "v1"
        }
      ],
      "preferredVersion": {
        "groupVersion": "apps/v1",
        "version": "v1"
      }
    }
...
```

Example 2 (yaml):
```yaml
{
    "paths": {
        ...,
        "api/v1": {
            "serverRelativeURL": "/openapi/v3/api/v1?hash=CC0E9BFD992D8C59AEC98A1E2336F899E8318D3CF4C68944C3DEC640AF5AB52D864AC50DAA8D145B3494F75FA3CFF939FCBDDA431DAD3CA79738B297795818CF"
        },
        "apis/admissionregistration.k8s.io/v1": {
            "serverRelativeURL": "/openapi/v3/apis/admissionregistration.k8s.io/v1?hash=E19CC93A116982CE5422FC42B590A8AFAD92CDE9AE4D59B5CAAD568F083AD07946E6CB5817531680BCE6E215C16973CD39003B0425F3477CFD854E89A9DB6597"
        },
        ....
    }
}
```

---

## Cloud Controller Manager

**URL:** https://kubernetes.io/docs/concepts/architecture/cloud-controller/

**Contents:**
- Cloud Controller Manager
- Design
    - Note:
- Cloud controller manager functions
  - Node controller
  - Route controller
  - Service controller
- Authorization
  - Node controller
  - Route controller

Cloud infrastructure technologies let you run Kubernetes on public, private, and hybrid clouds. Kubernetes believes in automated, API-driven infrastructure without tight coupling between components.

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider's API, and separates out the components that interact with that cloud platform from components that only interact with your cluster.

By decoupling the interoperability logic between Kubernetes and the underlying cloud infrastructure, the cloud-controller-manager component enables cloud providers to release features at a different pace compared to the main Kubernetes project.

The cloud-controller-manager is structured using a plugin mechanism that allows different cloud providers to integrate their platforms with Kubernetes.

The cloud controller manager runs in the control plane as a replicated set of processes (usually, these are containers in Pods). Each cloud-controller-manager implements multiple controllers in a single process.

The controllers inside the cloud controller manager include:

The node controller is responsible for updating Node objects when new servers are created in your cloud infrastructure. The node controller obtains information about the hosts running inside your tenancy with the cloud provider. The node controller performs the following functions:

Some cloud provider implementations split this into a node controller and a separate node lifecycle controller.

The route controller is responsible for configuring routes in the cloud appropriately so that containers on different nodes in your Kubernetes cluster can communicate with each other.

Depending on the cloud provider, the route controller might also allocate blocks of IP addresses for the Pod network.

Services integrate with cloud infrastructure components such as managed load balancers, IP addresses, network packet filtering, and target health checking. The service controller interacts with your cloud provider's APIs to set up load balancers and other infrastructure co

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cloud-controller-manager
rules:
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - '*'
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - services/status
  verbs:
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - serviceaccounts
  verbs:
  - create
- apiGroups:
  - ""
  resources:
  - persistent
...
```

---

## Overview

**URL:** https://kubernetes.io/docs/concepts/overview/#why-you-need-kubernetes-and-what-can-it-do

**Contents:**
- Overview
- Why you need Kubernetes and what it can do
- What Kubernetes is not
- Historical context for Kubernetes
- What's next
- Feedback

This page is an overview of Kubernetes.

The name Kubernetes originates from Greek, meaning helmsman or pilot. K8s as an abbreviation results from counting the eight letters between the "K" and the "s". Google open-sourced the Kubernetes project in 2014. Kubernetes combines over 15 years of Google's experience running production workloads at scale with best-of-breed ideas and practices from the community.

Containers are a good way to bundle and run your applications. In a production environment, you need to manage the containers that run the applications and ensure that there is no downtime. For example, if a container goes down, another container needs to start. Wouldn't it be easier if this behavior was handled by a system?

That's how Kubernetes comes to the rescue! Kubernetes provides you with a framework to run distributed systems resiliently. It takes care of scaling and failover for your application, provides deployment patterns, and more. For example: Kubernetes can easily manage a canary deployment for your system.

Kubernetes provides you with:

Kubernetes is not a traditional, all-inclusive PaaS (Platform as a Service) system. Since Kubernetes operates at the container level rather than at the hardware level, it provides some generally applicable features common to PaaS offerings, such as deployment, scaling, load balancing, and lets users integrate their logging, monitoring, and alerting solutions. However, Kubernetes is not monolithic, and these default solutions are optional and pluggable. Kubernetes provides the building blocks for building developer platforms, but preserves user choice and flexibility where it is important.

Let's take a look at why Kubernetes is so useful by going back in time.

Traditional deployment era:

Early on, organizations ran applications on physical servers. There was no way to define resource boundaries for applications in a physical server, and this caused resource allocation issues. For example, if multiple applications run on a physical server, there can be instances where one application would take up most of the resources, and as a result, the other applications would underperform. A solution for this would be to run each application on a different physical server. But this did not scale as resources were underutilized, and it was expensive for organizations to maintain many physical servers.

Virtualized deployment era:

As a solution, virtualization was introduced. It allows you to run multiple Virtual M

*[Content truncated]*

---

## Scheduling, Preemption and Eviction

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/

**Contents:**
- Scheduling, Preemption and Eviction
- Scheduling
- Pod Disruption
- Feedback

In Kubernetes, scheduling refers to making sure that Pods are matched to Nodes so that the kubelet can run them. Preemption is the process of terminating Pods with lower Priority so that Pods with higher Priority can schedule on Nodes. Eviction is the process of terminating one or more Pods on Nodes.

Pod disruption is the process by which Pods on Nodes are terminated either voluntarily or involuntarily.

Voluntary disruptions are started intentionally by application owners or cluster administrators. Involuntary disruptions are unintentional and can be triggered by unavoidable issues like Nodes running out of resources, or by accidental deletions.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## DaemonSet

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/

**Contents:**
- DaemonSet
- Writing a DaemonSet Spec
  - Create a DaemonSet
  - Required Fields
  - Pod Template
  - Pod Selector
  - Running Pods on select Nodes
- How Daemon Pods are scheduled
    - Note:
  - Taints and tolerations

A DaemonSet ensures that all (or some) Nodes run a copy of a Pod. As nodes are added to the cluster, Pods are added to them. As nodes are removed from the cluster, those Pods are garbage collected. Deleting a DaemonSet will clean up the Pods it created.

Some typical uses of a DaemonSet are:

In a simple case, one DaemonSet, covering all nodes, would be used for each type of daemon. A more complex setup might use multiple DaemonSets for a single type of daemon, but with different flags and/or different memory and cpu requests for different hardware types.

You can describe a DaemonSet in a YAML file. For example, the daemonset.yaml file below describes a DaemonSet that runs the fluentd-elasticsearch Docker image:

Create a DaemonSet based on the YAML file:

As with all other Kubernetes config, a DaemonSet needs apiVersion, kind, and metadata fields. For general information about working with config files, see running stateless applications and object management using kubectl.

The name of a DaemonSet object must be a valid DNS subdomain name.

A DaemonSet also needs a .spec section.

The .spec.template is one of the required fields in .spec.

The .spec.template is a pod template. It has exactly the same schema as a Pod, except it is nested and does not have an apiVersion or kind.

In addition to required fields for a Pod, a Pod template in a DaemonSet has to specify appropriate labels (see pod selector).

A Pod Template in a DaemonSet must have a RestartPolicy equal to Always, or be unspecified, which defaults to Always.

The .spec.selector field is a pod selector. It works the same as the .spec.selector of a Job.

You must specify a pod selector that matches the labels of the .spec.template. Also, once a DaemonSet is created, its .spec.selector can not be mutated. Mutating the pod selector can lead to the unintentional orphaning of Pods, and it was found to be confusing to users.

The .spec.selector is an object consisting of two fields:

When the two are specified the result is ANDed.

The .spec.selector must match the .spec.template.metadata.labels. Config with these two not matching will be rejected by the API.

If you specify a .spec.template.spec.nodeSelector, then the DaemonSet controller will create Pods on nodes which match that node selector. Likewise if you specify a .spec.template.spec.affinity, then DaemonSet controller will create Pods on nodes which match that node affinity. If you do not specify either, then the DaemonSet controller will cr

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd-elasticsearch
  namespace: kube-system
  labels:
    k8s-app: fluentd-logging
spec:
  selector:
    matchLabels:
      name: fluentd-elasticsearch
  template:
    metadata:
      labels:
        name: fluentd-elasticsearch
    spec:
      tolerations:
      # these tolerations are to have the daemonset runnable on control plane nodes
      # remove them if your control plane nodes should not run pods
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernet
...
```

Example 2 (unknown):
```unknown
kubectl apply -f https://k8s.io/examples/controllers/daemonset.yaml
```

Example 3 (yaml):
```yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchFields:
      - key: metadata.name
        operator: In
        values:
        - target-host-name
```

---

## Pod Priority and Preemption

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/#preemption

**Contents:**
- Pod Priority and Preemption
    - Warning:
- How to use priority and preemption
    - Note:
- PriorityClass
  - Notes about PodPriority and existing clusters
  - Example PriorityClass
- Non-preempting PriorityClass
  - Example Non-preempting PriorityClass
- Pod priority

Pods can have priority. Priority indicates the importance of a Pod relative to other Pods. If a Pod cannot be scheduled, the scheduler tries to preempt (evict) lower priority Pods to make scheduling of the pending Pod possible.

In a cluster where not all users are trusted, a malicious user could create Pods at the highest possible priorities, causing other Pods to be evicted/not get scheduled. An administrator can use ResourceQuota to prevent users from creating pods at high priorities.

See limit Priority Class consumption by default for details.

To use priority and preemption:

Add one or more PriorityClasses.

Create Pods withpriorityClassName set to one of the added PriorityClasses. Of course you do not need to create the Pods directly; normally you would add priorityClassName to the Pod template of a collection object like a Deployment.

Keep reading for more information about these steps.

A PriorityClass is a non-namespaced object that defines a mapping from a priority class name to the integer value of the priority. The name is specified in the name field of the PriorityClass object's metadata. The value is specified in the required value field. The higher the value, the higher the priority. The name of a PriorityClass object must be a valid DNS subdomain name, and it cannot be prefixed with system-.

A PriorityClass object can have any 32-bit integer value smaller than or equal to 1 billion. This means that the range of values for a PriorityClass object is from -2147483648 to 1000000000 inclusive. Larger numbers are reserved for built-in PriorityClasses that represent critical system Pods. A cluster admin should create one PriorityClass object for each such mapping that they want.

PriorityClass also has two optional fields: globalDefault and description. The globalDefault field indicates that the value of this PriorityClass should be used for Pods without a priorityClassName. Only one PriorityClass with globalDefault set to true can exist in the system. If there is no PriorityClass with globalDefault set, the priority of Pods with no priorityClassName is zero.

The description field is an arbitrary string. It is meant to tell users of the cluster when they should use this PriorityClass.

If you upgrade an existing cluster without this feature, the priority of your existing Pods is effectively zero.

Addition of a PriorityClass with globalDefault set to true does not change the priorities of existing Pods. The value of such a PriorityClass is us

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "This priority class should be used for XYZ service pods only."
```

Example 2 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-nonpreempting
value: 1000000
preemptionPolicy: Never
globalDefault: false
description: "This priority class will not cause other pods to be preempted."
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  priorityClassName: high-priority
```

---

## CSI Volume Cloning

**URL:** https://kubernetes.io/docs/concepts/storage/volume-pvc-datasource/

**Contents:**
- CSI Volume Cloning
- Introduction
- Provisioning
    - Note:
- Usage
- Feedback

This document describes the concept of cloning existing CSI Volumes in Kubernetes. Familiarity with Volumes is suggested.

The CSI Volume Cloning feature adds support for specifying existing PVCs in the dataSource field to indicate a user would like to clone a Volume.

A Clone is defined as a duplicate of an existing Kubernetes Volume that can be consumed as any standard Volume would be. The only difference is that upon provisioning, rather than creating a "new" empty Volume, the back end device creates an exact duplicate of the specified Volume.

The implementation of cloning, from the perspective of the Kubernetes API, adds the ability to specify an existing PVC as a dataSource during new PVC creation. The source PVC must be bound and available (not in use).

Users need to be aware of the following when using this feature:

Clones are provisioned like any other PVC with the exception of adding a dataSource that references an existing PVC in the same namespace.

The result is a new PVC with the name clone-of-pvc-1 that has the exact same content as the specified source pvc-1.

Upon availability of the new PVC, the cloned PVC is consumed the same as other PVC. It's also expected at this point that the newly created PVC is an independent object. It can be consumed, cloned, snapshotted, or deleted independently and without consideration for it's original dataSource PVC. This also implies that the source is not linked in any way to the newly created clone, it may also be modified or deleted without affecting the newly created clone.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: clone-of-pvc-1
    namespace: myns
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: cloning
  resources:
    requests:
      storage: 5Gi
  dataSource:
    kind: PersistentVolumeClaim
    name: pvc-1
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#cloud-controller-manager

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#extensions

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#pod-index-label

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/#emptydir

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#deviceclass

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## EndpointSlices

**URL:** https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/

**Contents:**
- EndpointSlices
- EndpointSlice API
  - Address types
  - Conditions
    - Serving
    - Terminating
    - Ready
  - Topology information
  - Management
  - Ownership

Kubernetes' EndpointSlice API provides a way to track network endpoints within a Kubernetes cluster.

In Kubernetes, an EndpointSlice contains references to a set of network endpoints. The control plane automatically creates EndpointSlices for any Kubernetes Service that has a selector specified. These EndpointSlices include references to all the Pods that match the Service selector. EndpointSlices group network endpoints together by unique combinations of IP family, protocol, port number, and Service name. The name of a EndpointSlice object must be a valid DNS subdomain name.

As an example, here's a sample EndpointSlice object, that's owned by the example Kubernetes Service.

By default, the control plane creates and manages EndpointSlices to have no more than 100 endpoints each. You can configure this with the --max-endpoints-per-slice kube-controller-manager flag, up to a maximum of 1000.

EndpointSlices act as the source of truth for kube-proxy when it comes to how to route internal traffic.

EndpointSlices support two address types:

Each EndpointSlice object represents a specific IP address type. If you have a Service that is available via IPv4 and IPv6, there will be at least two EndpointSlice objects (one for IPv4, and one for IPv6).

The EndpointSlice API stores conditions about endpoints that may be useful for consumers. The three conditions are serving, terminating, and ready.

The serving condition indicates that the endpoint is currently serving responses, and so it should be used as a target for Service traffic. For endpoints backed by a Pod, this maps to the Pod's Ready condition.

The terminating condition indicates that the endpoint is terminating. For endpoints backed by a Pod, this condition is set when the Pod is first deleted (that is, when it receives a deletion timestamp, but most likely before the Pod's containers exit).

Service proxies will normally ignore endpoints that are terminating, but they may route traffic to endpoints that are both serving and terminating if all available endpoints are terminating. (This helps to ensure that no Service traffic is lost during rolling updates of the underlying Pods.)

The ready condition is essentially a shortcut for checking "serving and not terminating" (though it will also always be true for Services with spec.publishNotReadyAddresses set to true).

Each endpoint within an EndpointSlice can contain relevant topology information. The topology information includes the location of the endp

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: example-abc
  labels:
    kubernetes.io/service-name: example
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 80
endpoints:
  - addresses:
      - "10.1.2.3"
    conditions:
      ready: true
    hostname: pod-1
    nodeName: node-1
    zone: us-west2-a
```

---

## Node Shutdowns

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/#non-graceful-node-shutdown

**Contents:**
- Node Shutdowns
- Graceful node shutdown
  - Enabling graceful node shutdown
    - Note:
    - Note:
  - Configuring graceful node shutdown
    - Note:
    - Note:
  - Pod Priority based graceful node shutdown
    - Note:

In a Kubernetes cluster, a node can be shut down in a planned graceful way or unexpectedly because of reasons such as a power outage or something else external. A node shutdown could lead to workload failure if the node is not drained before the shutdown. A node shutdown can be either graceful or non-graceful.

The kubelet attempts to detect node system shutdown and terminates pods running on the node.

Kubelet ensures that pods follow the normal pod termination process during the node shutdown. During node shutdown, the kubelet does not accept new Pods (even if those Pods are already bound to the node).

FEATURE STATE: Kubernetes v1.21 [beta] (enabled by default: true)On Linux, the graceful node shutdown feature is controlled with the GracefulNodeShutdown feature gate which is enabled by default in 1.21.Note:The graceful node shutdown feature depends on systemd since it takes advantage of systemd inhibitor locks to delay the node shutdown with a given duration.

On Linux, the graceful node shutdown feature is controlled with the GracefulNodeShutdown feature gate which is enabled by default in 1.21.

FEATURE STATE: Kubernetes v1.34 [beta] (enabled by default: true)On Windows, the graceful node shutdown feature is controlled with the WindowsGracefulNodeShutdown feature gate which is introduced in 1.32 as an alpha feature. In Kubernetes 1.34 the feature is Beta and is enabled by default.Note:The Windows graceful node shutdown feature depends on kubelet running as a Windows service, it will then have a registered service control handler to delay the preshutdown event with a given duration.Windows graceful node shutdown can not be cancelled.If kubelet is not running as a Windows service, it will not be able to set and monitor the Preshutdown event, the node will have to go through the Non-Graceful Node Shutdown procedure mentioned above.In the case where the Windows graceful node shutdown feature is enabled, but the kubelet is not running as a Windows service, the kubelet will continue running instead of failing. However, it will log an error indicating that it needs to be run as a Windows service.

On Windows, the graceful node shutdown feature is controlled with the WindowsGracefulNodeShutdown feature gate which is introduced in 1.32 as an alpha feature. In Kubernetes 1.34 the feature is Beta and is enabled by default.

Windows graceful node shutdown can not be cancelled.

If kubelet is not running as a Windows service, it will not be able to set and monitor

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
Reason:         Terminated
Message:        Pod was terminated in response to imminent node shutdown.
```

Example 2 (yaml):
```yaml
shutdownGracePeriodByPodPriority:
  - priority: 100000
    shutdownGracePeriodSeconds: 10
  - priority: 10000
    shutdownGracePeriodSeconds: 180
  - priority: 1000
    shutdownGracePeriodSeconds: 120
  - priority: 0
    shutdownGracePeriodSeconds: 60
```

---

## Network Plugins

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/

**Contents:**
- Network Plugins
- Installation
    - Note:
- Network Plugin Requirements
  - Loopback CNI
  - Support hostPort
  - Support traffic shaping
- What's next
- Feedback

Kubernetes (version 1.3 through to the latest 1.34, and likely onwards) lets you use Container Network Interface (CNI) plugins for cluster networking. You must use a CNI plugin that is compatible with your cluster and that suits your needs. Different plugins are available (both open- and closed- source) in the wider Kubernetes ecosystem.

A CNI plugin is required to implement the Kubernetes network model.

You must use a CNI plugin that is compatible with the v0.4.0 or later releases of the CNI specification. The Kubernetes project recommends using a plugin that is compatible with the v1.0.0 CNI specification (plugins can be compatible with multiple spec versions).

A Container Runtime, in the networking context, is a daemon on a node configured to provide CRI Services for kubelet. In particular, the Container Runtime must be configured to load the CNI plugins required to implement the Kubernetes network model.

Prior to Kubernetes 1.24, the CNI plugins could also be managed by the kubelet using the cni-bin-dir and network-plugin command-line parameters. These command-line parameters were removed in Kubernetes 1.24, with management of the CNI no longer in scope for kubelet.

See Troubleshooting CNI plugin-related errors if you are facing issues following the removal of dockershim.

For specific information about how a Container Runtime manages the CNI plugins, see the documentation for that Container Runtime, for example:

For specific information about how to install and manage a CNI plugin, see the documentation for that plugin or networking provider.

In addition to the CNI plugin installed on the nodes for implementing the Kubernetes network model, Kubernetes also requires the container runtimes to provide a loopback interface lo, which is used for each sandbox (pod sandboxes, vm sandboxes, ...). Implementing the loopback interface can be accomplished by re-using the CNI loopback plugin. or by developing your own code to achieve this (see this example from CRI-O).

The CNI networking plugin supports hostPort. You can use the official portmap plugin offered by the CNI plugin team or use your own plugin with portMapping functionality.

If you want to enable hostPort support, you must specify portMappings capability in your cni-conf-dir. For example:

The CNI networking plugin also supports pod ingress and egress traffic shaping. You can use the official bandwidth plugin offered by the CNI plugin team or use your own plugin with bandwidth control function

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
  "name": "k8s-pod-network",
  "cniVersion": "0.4.0",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "datastore_type": "kubernetes",
      "nodename": "127.0.0.1",
      "ipam": {
        "type": "host-local",
        "subnet": "usePodCidr"
      },
      "policy": {
        "type": "k8s"
      },
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true},
      "externalSetMarkChain": "KUBE-MARK-MASQ"
    }
  ]
}
```

Example 2 (json):
```json
{
  "name": "k8s-pod-network",
  "cniVersion": "0.4.0",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "datastore_type": "kubernetes",
      "nodename": "127.0.0.1",
      "ipam": {
        "type": "host-local",
        "subnet": "usePodCidr"
      },
      "policy": {
        "type": "k8s"
      },
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "bandwidth",
      "capabilities": {"bandwidth": true}
    }
  ]
}
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubernetes.io/ingress-bandwidth: 1M
    kubernetes.io/egress-bandwidth: 1M
...
```

---

## Volume Snapshot Classes

**URL:** https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/

**Contents:**
- Volume Snapshot Classes
- Introduction
- The VolumeSnapshotClass Resource
    - Note:
  - VolumeSnapshotClass dependencies
  - Driver
  - DeletionPolicy
- Parameters
- Feedback

This document describes the concept of VolumeSnapshotClass in Kubernetes. Familiarity with volume snapshots and storage classes is suggested.

Just like StorageClass provides a way for administrators to describe the "classes" of storage they offer when provisioning a volume, VolumeSnapshotClass provides a way to describe the "classes" of storage when provisioning a volume snapshot.

Each VolumeSnapshotClass contains the fields driver, deletionPolicy, and parameters, which are used when a VolumeSnapshot belonging to the class needs to be dynamically provisioned.

The name of a VolumeSnapshotClass object is significant, and is how users can request a particular class. Administrators set the name and other parameters of a class when first creating VolumeSnapshotClass objects, and the objects cannot be updated once they are created.

Administrators can specify a default VolumeSnapshotClass for VolumeSnapshots that don't request any particular class to bind to by adding the snapshot.storage.kubernetes.io/is-default-class: "true" annotation:

If multiple CSI drivers exist, a default VolumeSnapshotClass can be specified for each of them.

When you create a VolumeSnapshot without specifying a VolumeSnapshotClass, Kubernetes automatically selects a default VolumeSnapshotClass that has a CSI driver matching the CSI driver of the PVC’s StorageClass.

This behavior allows multiple default VolumeSnapshotClass objects to coexist in a cluster, as long as each one is associated with a unique CSI driver.

Always ensure that there is only one default VolumeSnapshotClass for each CSI driver. If multiple default VolumeSnapshotClass objects are created using the same CSI driver, a VolumeSnapshot creation will fail because Kubernetes cannot determine which one to use.

Volume snapshot classes have a driver that determines what CSI volume plugin is used for provisioning VolumeSnapshots. This field must be specified.

Volume snapshot classes have a deletionPolicy. It enables you to configure what happens to a VolumeSnapshotContent when the VolumeSnapshot object it is bound to is to be deleted. The deletionPolicy of a volume snapshot class can either be Retain or Delete. This field must be specified.

If the deletionPolicy is Delete, then the underlying storage snapshot will be deleted along with the VolumeSnapshotContent object. If the deletionPolicy is Retain, then both the underlying snapshot and VolumeSnapshotContent remain.

Volume snapshot classes have parameters that descri

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
parameters:
```

Example 2 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
parameters:
```

---

## Pods

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/#pod-os

**Contents:**
- Pods
- What is a Pod?
    - Note:
- Using Pods
  - Workload resources for managing pods
- Working with Pods
    - Note:
  - Pod OS
  - Pods and controllers
  - Pod templates

Pods are the smallest deployable units of computing that you can create and manage in Kubernetes.

A Pod (as in a pod of whales or pea pod) is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers. A Pod's contents are always co-located and co-scheduled, and run in a shared context. A Pod models an application-specific "logical host": it contains one or more application containers which are relatively tightly coupled. In non-cloud contexts, applications executed on the same physical or virtual machine are analogous to cloud applications executed on the same logical host.

As well as application containers, a Pod can contain init containers that run during Pod startup. You can also inject ephemeral containers for debugging a running Pod.

The shared context of a Pod is a set of Linux namespaces, cgroups, and potentially other facets of isolation - the same things that isolate a container. Within a Pod's context, the individual applications may have further sub-isolations applied.

A Pod is similar to a set of containers with shared namespaces and shared filesystem volumes.

Pods in a Kubernetes cluster are used in two main ways:

Pods that run a single container. The "one-container-per-Pod" model is the most common Kubernetes use case; in this case, you can think of a Pod as a wrapper around a single container; Kubernetes manages Pods rather than managing the containers directly.

Pods that run multiple containers that need to work together. A Pod can encapsulate an application composed of multiple co-located containers that are tightly coupled and need to share resources. These co-located containers form a single cohesive unit.

Grouping multiple co-located and co-managed containers in a single Pod is a relatively advanced use case. You should use this pattern only in specific instances in which your containers are tightly coupled.

You don't need to run multiple containers to provide replication (for resilience or capacity); if you need multiple replicas, see Workload management.

The following is an example of a Pod which consists of a container running the image nginx:1.14.2.

To create the Pod shown above, run the following command:

Pods are generally not created directly and are created using workload resources. See Working with Pods for more information on how Pods are used with workload resources.

Usually you don't need to create Pods directly, even singleton Pods. Instead, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml
```

Example 3 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    # This is the pod template
    spec:
      containers:
      - name: hello
        image: busybox:1.28
        command: ['sh', '-c', 'echo "Hello, Kubernetes!" && sleep 3600']
      restartPolicy: OnFailure
    # The pod template ends here
```

---

## Ephemeral Containers

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/

**Contents:**
- Ephemeral Containers
- Understanding ephemeral containers
  - What is an ephemeral container?
    - Note:
- Uses for ephemeral containers
- What's next
- Feedback

This page provides an overview of ephemeral containers: a special type of container that runs temporarily in an existing Pod to accomplish user-initiated actions such as troubleshooting. You use ephemeral containers to inspect services rather than to build applications.

Pods are the fundamental building block of Kubernetes applications. Since Pods are intended to be disposable and replaceable, you cannot add a container to a Pod once it has been created. Instead, you usually delete and replace Pods in a controlled fashion using deployments.

Sometimes it's necessary to inspect the state of an existing Pod, however, for example to troubleshoot a hard-to-reproduce bug. In these cases you can run an ephemeral container in an existing Pod to inspect its state and run arbitrary commands.

Ephemeral containers differ from other containers in that they lack guarantees for resources or execution, and they will never be automatically restarted, so they are not appropriate for building applications. Ephemeral containers are described using the same ContainerSpec as regular containers, but many fields are incompatible and disallowed for ephemeral containers.

Ephemeral containers are created using a special ephemeralcontainers handler in the API rather than by adding them directly to pod.spec, so it's not possible to add an ephemeral container using kubectl edit.

Like regular containers, you may not change or remove an ephemeral container after you have added it to a Pod.

Ephemeral containers are useful for interactive troubleshooting when kubectl exec is insufficient because a container has crashed or a container image doesn't include debugging utilities.

In particular, distroless images enable you to deploy minimal container images that reduce attack surface and exposure to bugs and vulnerabilities. Since distroless images do not include a shell or any debugging utilities, it's difficult to troubleshoot distroless images using kubectl exec alone.

When using ephemeral containers, it's helpful to enable process namespace sharing so you can view processes in other containers.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Pod Overhead

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-overhead/

**Contents:**
- Pod Overhead
- Configuring Pod overhead
- Usage example
    - Note:
- Verify Pod cgroup limits
  - Observability
- What's next
- Feedback

When you run a Pod on a Node, the Pod itself takes an amount of system resources. These resources are additional to the resources needed to run the container(s) inside the Pod. In Kubernetes, Pod Overhead is a way to account for the resources consumed by the Pod infrastructure on top of the container requests & limits.

In Kubernetes, the Pod's overhead is set at admission time according to the overhead associated with the Pod's RuntimeClass.

A pod's overhead is considered in addition to the sum of container resource requests when scheduling a Pod. Similarly, the kubelet will include the Pod overhead when sizing the Pod cgroup, and when carrying out Pod eviction ranking.

You need to make sure a RuntimeClass is utilized which defines the overhead field.

To work with Pod overhead, you need a RuntimeClass that defines the overhead field. As an example, you could use the following RuntimeClass definition with a virtualization container runtime (in this example, Kata Containers combined with the Firecracker virtual machine monitor) that uses around 120MiB per Pod for the virtual machine and the guest OS:

Workloads which are created which specify the kata-fc RuntimeClass handler will take the memory and cpu overheads into account for resource quota calculations, node scheduling, as well as Pod cgroup sizing.

Consider running the given example workload, test-pod:

At admission time the RuntimeClass admission controller updates the workload's PodSpec to include the overhead as described in the RuntimeClass. If the PodSpec already has this field defined, the Pod will be rejected. In the given example, since only the RuntimeClass name is specified, the admission controller mutates the Pod to include an overhead.

After the RuntimeClass admission controller has made modifications, you can check the updated Pod overhead value:

If a ResourceQuota is defined, the sum of container requests as well as the overhead field are counted.

When the kube-scheduler is deciding which node should run a new Pod, the scheduler considers that Pod's overhead as well as the sum of container requests for that Pod. For this example, the scheduler adds the requests and the overhead, then looks for a node that has 2.25 CPU and 320 MiB of memory available.

Once a Pod is scheduled to a node, the kubelet on that node creates a new cgroup for the Pod. It is within this pod that the underlying container runtime will create containers.

If the resource has a limit defined for each containe

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# You need to change this example to match the actual runtime name, and per-Pod
# resource overhead, that the container runtime is adding in your cluster.
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: "120Mi"
    cpu: "250m"
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  runtimeClassName: kata-fc
  containers:
  - name: busybox-ctr
    image: busybox:1.28
    stdin: true
    tty: true
    resources:
      limits:
        cpu: 500m
        memory: 100Mi
  - name: nginx-ctr
    image: nginx
    resources:
      limits:
        cpu: 1500m
        memory: 100Mi
```

Example 3 (bash):
```bash
kubectl get pod test-pod -o jsonpath='{.spec.overhead}'
```

Example 4 (unknown):
```unknown
map[cpu:250m memory:120Mi]
```

---

## Swap memory management

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/

**Contents:**
- Swap memory management
- Operating system support
- How does it work?
  - Swap behaviors
    - Note:
  - Container runtime integration
- Observability for swap use
  - Node and container level metric statistics
  - Using kubectl top --show-swap
  - Nodes to report swap capacity as part of node status

Kubernetes can be configured to use swap memory on a node, allowing the kernel to free up physical memory by swapping out pages to backing storage. This is useful for multiple use-cases. For example, nodes running workloads that can benefit from using swap, such as those that have large memory footprints but only access a portion of that memory at any given time. It also helps prevent Pods from being terminated during memory pressure spikes, shields nodes from system-level memory spikes that might compromise its stability, allows for more flexible memory management on the node, and much more.

To learn about configuring swap in your cluster, read Configuring swap memory on Kubernetes nodes.

There are a number of possible ways that one could envision swap use on a node. If kubelet is already running on a node, it would need to be restarted after swap is provisioned in order to identify it.

When kubelet starts on a node in which swap is provisioned and available (with the failSwapOn: false configuration), kubelet will:

Swap configuration on a node is exposed to a cluster admin via the memorySwap in the KubeletConfiguration. As a cluster administrator, you can specify the node's behaviour in the presence of swap memory by setting memorySwap.swapBehavior.

You need to pick a swap behavior to use. Different nodes in your cluster can use different swap behaviors.

The swap behaviors you can choose for Linux nodes are:

If you choose the NoSwap behavior, and you configure the kubelet to tolerate swap space (failSwapOn: false), then your workloads don't use any swap.

However, processes outside of Kubernetes-managed containers, such as systemi services (and even the kubelet itself!) can utilize swap.

You can read configuring swap memory on Kubernetes nodes to learn about enabling swap for your cluster.

The kubelet uses the container runtime API, and directs the container runtime to apply specific configuration (for example, in the cgroup v2 case, memory.swap.max) in a manner that will enable the desired swap configuration for a container. For runtimes that use control groups, or cgroups, the container runtime is then responsible for writing these settings to the container-level cgroup.

Kubelet now collects node and container level metric statistics, which can be accessed at the /metrics/resource (which is used mainly by monitoring tools like Prometheus) and /stats/summary (which is used mainly by Autoscalers) kubelet HTTP endpoints. This allows clients who c

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl top nodes --show-swap
```

Example 2 (unknown):
```unknown
NAME    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   SWAP(bytes)    SWAP(%)       
node1   1m           10%      2Mi             10%         1Mi            0%   
node2   5m           10%      6Mi             10%         2Mi            0%   
node3   3m           10%      4Mi             10%         <unknown>      <unknown>
```

Example 3 (shell):
```shell
kubectl top pod -n kube-system --show-swap
```

Example 4 (unknown):
```unknown
NAME                                      CPU(cores)   MEMORY(bytes)   SWAP(bytes)
coredns-58d5bc5cdb-5nbk4                  2m           19Mi            0Mi
coredns-58d5bc5cdb-jsh26                  3m           37Mi            0Mi
etcd-node01                               51m          143Mi           5Mi
kube-apiserver-node01                     98m          824Mi           16Mi
kube-controller-manager-node01            20m          135Mi           9Mi
kube-proxy-ffgs2                          1m           24Mi            0Mi
kube-proxy-fhvwx                          1m           39Mi       
...
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#device-plugins

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Assigning Pods to Nodes

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

**Contents:**
- Assigning Pods to Nodes
- Node labels
    - Note:
  - Node isolation/restriction
- nodeSelector
- Affinity and anti-affinity
  - Node affinity
    - Note:
    - Note:
    - Node affinity weight

You can constrain a Pod so that it is restricted to run on particular node(s), or to prefer to run on particular nodes. There are several ways to do this and the recommended approaches all use label selectors to facilitate the selection. Often, you do not need to set any such constraints; the scheduler will automatically do a reasonable placement (for example, spreading your Pods across nodes so as not place Pods on a node with insufficient free resources). However, there are some circumstances where you may want to control which node the Pod deploys to, for example, to ensure that a Pod ends up on a node with an SSD attached to it, or to co-locate Pods from two different services that communicate a lot into the same availability zone.

You can use any of the following methods to choose where Kubernetes schedules specific Pods:

Like many other Kubernetes objects, nodes have labels. You can attach labels manually. Kubernetes also populates a standard set of labels on all nodes in a cluster.

Adding labels to nodes allows you to target Pods for scheduling on specific nodes or groups of nodes. You can use this functionality to ensure that specific Pods only run on nodes with certain isolation, security, or regulatory properties.

If you use labels for node isolation, choose label keys that the kubelet cannot modify. This prevents a compromised node from setting those labels on itself so that the scheduler schedules workloads onto the compromised node.

The NodeRestriction admission plugin prevents the kubelet from setting or modifying labels with a node-restriction.kubernetes.io/ prefix.

To make use of that label prefix for node isolation:

nodeSelector is the simplest recommended form of node selection constraint. You can add the nodeSelector field to your Pod specification and specify the node labels you want the target node to have. Kubernetes only schedules the Pod onto nodes that have each of the labels you specify.

See Assign Pods to Nodes for more information.

nodeSelector is the simplest way to constrain Pods to nodes with specific labels. Affinity and anti-affinity expand the types of constraints you can define. Some of the benefits of affinity and anti-affinity include:

The affinity feature consists of two types of affinity:

Node affinity is conceptually similar to nodeSelector, allowing you to constrain which nodes your Pod can be scheduled on based on node labels. There are two types of node affinity:

You can specify node affinities using t

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-node-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - antarctica-east1
            - antarctica-west1
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: another-node-label-key
            operator: In
            values:
            - another-node-label-va
...
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-affinity-preferred-weight
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: label-1
            operator: In
            values:
            - key-1
      - weight: 50
        preference:
          matchExpressions:
    
...
```

Example 3 (yaml):
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration

profiles:
  - schedulerName: default-scheduler
  - schedulerName: foo-scheduler
    pluginConfig:
      - name: NodeAffinity
        args:
          addedAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: scheduler-profile
                  operator: In
                  values:
                  - foo
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-pod-affinity
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - S1
        topologyKey: topology.kubernetes.io/zone
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: security
              operator: In
              values:
         
...
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#partitionable-devices

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#configuration

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/#headless-services

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#hostalias-v1-core

---

## Cluster Administration

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/#securing-a-cluster

**Contents:**
- Cluster Administration
- Planning a cluster
    - Note:
- Managing a cluster
- Securing a cluster
  - Securing the kubelet
- Optional Cluster Services
- Feedback

The cluster administration overview is for anyone creating or administering a Kubernetes cluster. It assumes some familiarity with core Kubernetes concepts.

See the guides in Setup for examples of how to plan, set up, and configure Kubernetes clusters. The solutions listed in this article are called distros.

Before choosing a guide, here are some considerations:

Learn how to manage nodes.

Learn how to set up and manage the resource quota for shared clusters.

Generate Certificates describes the steps to generate certificates using different tool chains.

Kubernetes Container Environment describes the environment for Kubelet managed containers on a Kubernetes node.

Controlling Access to the Kubernetes API describes how Kubernetes implements access control for its own API.

Authenticating explains authentication in Kubernetes, including the various authentication options.

Authorization is separate from authentication, and controls how HTTP calls are handled.

Using Admission Controllers explains plug-ins which intercepts requests to the Kubernetes API server after authentication and authorization.

Admission Webhook Good Practices provides good practices and considerations when designing mutating admission webhooks and validating admission webhooks.

Using Sysctls in a Kubernetes Cluster describes to an administrator how to use the sysctl command-line tool to set kernel parameters .

Auditing describes how to interact with Kubernetes' audit logs.

DNS Integration describes how to resolve a DNS name directly to a Kubernetes service.

Logging and Monitoring Cluster Activity explains how logging in Kubernetes works and how to implement it.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Cluster Networking

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/networking/

**Contents:**
- Cluster Networking
- Kubernetes IP address ranges
- Cluster networking types
- How to implement the Kubernetes network model
- What's next
- Feedback

Networking is a central part of Kubernetes, but it can be challenging to understand exactly how it is expected to work. There are 4 distinct networking problems to address:

Kubernetes is all about sharing machines among applications. Typically, sharing machines requires ensuring that two applications do not try to use the same ports. Coordinating ports across multiple developers is very difficult to do at scale and exposes users to cluster-level issues outside of their control.

Dynamic port allocation brings a lot of complications to the system - every application has to take ports as flags, the API servers have to know how to insert dynamic port numbers into configuration blocks, services have to know how to find each other, etc. Rather than deal with this, Kubernetes takes a different approach.

To learn about the Kubernetes networking model, see here.

Kubernetes clusters require to allocate non-overlapping IP addresses for Pods, Services and Nodes, from a range of available addresses configured in the following components:

Kubernetes clusters, attending to the IP families configured, can be categorized into:

Kubernetes clusters only consider the IP families present on the Pods, Services and Nodes objects, independently of the existing IPs of the represented objects. Per example, a server or a pod can have multiple IP addresses on its interfaces, but only the IP addresses in node.status.addresses or pod.status.ips are considered for implementing the Kubernetes network model and defining the type of the cluster.

The network model is implemented by the container runtime on each node. The most common container runtimes use Container Network Interface (CNI) plugins to manage their network and security capabilities. Many different CNI plugins exist from many different vendors. Some of these provide only basic features of adding and removing network interfaces, while others provide more sophisticated solutions, such as integration with other container orchestration systems, running multiple CNI plugins, advanced IPAM features etc.

See this page for a non-exhaustive list of networking addons supported by Kubernetes.

The early design of the networking model and its rationale are described in more detail in the networking design document. For future plans and some on-going efforts that aim to improve Kubernetes networking, please refer to the SIG-Network KEPs.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question ab

*[Content truncated]*

---

## Jobs

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/job/

**Contents:**
- Jobs
- Running an example Job
- Writing a Job spec
  - Job Labels
  - Pod Template
  - Pod selector
  - Parallel execution for Jobs
    - Controlling parallelism
  - Completion mode
    - Note:

A Job creates one or more Pods and will continue to retry execution of the Pods until a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created. Suspending a Job will delete its active Pods until the Job is resumed again.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.

If you want to run a Job (either a single task, or several in parallel) on a schedule, see CronJob.

Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

You can run the example with this command:

The output is similar to this:

Check on the status of the Job with kubectl:

Name: pi Namespace: default Selector: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi ... Annotations: batch.kubernetes.io/job-tracking: "" Parallelism: 1 Completions: 1 Start Time: Mon, 02 Dec 2019 15:20:11 +0200 Completed At: Mon, 02 Dec 2019 15:21:16 +0200 Duration: 65s Pods Statuses: 0 Running / 1 Succeeded / 0 Failed Pod Template: Labels: batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c batch.kubernetes.io/job-name=pi Containers: pi: Image: perl:5.34.0 Port: <none> Host Port: <none> Command: perl -Mbignum=bpi -wle print bpi(2000) Environment: <none> Mounts: <none> Volumes: <none> Events: Type Reason Age From Message ---- ------ ---- ---- ------- Normal SuccessfulCreate 21s job-controller Created pod: pi-xf9p4 Normal Completed 18s job-controller Job completed

apiVersion: batch/v1 kind: Job metadata: annotations: batch.kubernetes.io/job-tracking: "" ... creationTimestamp: "2022-11-10T17:53:53Z" generation: 1 labels: batch.kubernetes.io/controller-uid: 863452e6-270d-420e-9b94-53a54146c223 batch.kubernetes.io/job-name: pi name: pi namespace: default resourceVersion: "4751" uid: 204fb678-040b-497f-9266-35ffa8716d14 spec: backoffLimit: 4 completionMode: NonIndexed completions: 1 parallelism: 1 selector: matchLabels: batch.kubernetes.io/controller-uid: 863452e6-270d-4

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl:5.34.0
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

Example 2 (shell):
```shell
kubectl apply -f https://kubernetes.io/examples/controllers/job.yaml
```

Example 3 (unknown):
```unknown
job.batch/pi created
```

Example 4 (bash):
```bash
Name:           pi
Namespace:      default
Selector:       batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
Labels:         batch.kubernetes.io/controller-uid=c9948307-e56d-4b5d-8302-ae2d7b7da67c
                batch.kubernetes.io/job-name=pi
                ...
Annotations:    batch.kubernetes.io/job-tracking: ""
Parallelism:    1
Completions:    1
Start Time:     Mon, 02 Dec 2019 15:20:11 +0200
Completed At:   Mon, 02 Dec 2019 15:21:16 +0200
Duration:       65s
Pods Statuses:  0 Running / 1 Succeeded / 0 Failed
Pod Template:
  Labels:  batch.kubernetes.io/controller-u
...
```

---

## API Overview

**URL:** https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#storageversion-v1alpha1-internal-apiserver-k8s-io

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#prioritized-list

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Labels and Selectors

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/

**Contents:**
- Labels and Selectors
- Motivation
- Syntax and character set
- Label selectors
    - Note:
    - Caution:
  - Equality-based requirement
  - Set-based requirement
- API
  - LIST and WATCH filtering

Labels are key/value pairs that are attached to objects such as Pods. Labels are intended to be used to specify identifying attributes of objects that are meaningful and relevant to users, but do not directly imply semantics to the core system. Labels can be used to organize and to select subsets of objects. Labels can be attached to objects at creation time and subsequently added and modified at any time. Each object can have a set of key/value labels defined. Each Key must be unique for a given object.

Labels allow for efficient queries and watches and are ideal for use in UIs and CLIs. Non-identifying information should be recorded using annotations.

Labels enable users to map their own organizational structures onto system objects in a loosely coupled fashion, without requiring clients to store these mappings.

Service deployments and batch processing pipelines are often multi-dimensional entities (e.g., multiple partitions or deployments, multiple release tracks, multiple tiers, multiple micro-services per tier). Management often requires cross-cutting operations, which breaks encapsulation of strictly hierarchical representations, especially rigid hierarchies determined by the infrastructure rather than by users.

These are examples of commonly used labels; you are free to develop your own conventions. Keep in mind that label Key must be unique for a given object.

Labels are key/value pairs. Valid label keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, followed by a slash (/).

If the prefix is omitted, the label Key is presumed to be private to the user. Automated system components (e.g. kube-scheduler, kube-controller-manager, kube-apiserver, kubectl, or other third-party automation) which add labels to end-user objects must specify a prefix.

The kubernetes.io/ and k8s.io/ prefixes are reserved for Kubernetes core components.

For example, here's a manifest for a Pod that has two labels environment: production and app: nginx:

Unlike names and UIDs, labels do not provide uniqueness. In general, we expect many objects to carry the same label(s).

Via a label sel

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "labels": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: label-demo
  labels:
    environment: production
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 3 (unknown):
```unknown
environment = production
tier != frontend
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  containers:
    - name: cuda-test
      image: "registry.k8s.io/cuda-vector-add:v0.1"
      resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia-tesla-p100
```

---

## Recommended Labels

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/#labels

**Contents:**
- Recommended Labels
    - Note:
- Labels
- Applications And Instances Of Applications
- Examples
  - A Simple Stateless Service
  - Web Application With A Database
- Feedback

You can visualize and manage Kubernetes objects with more tools than kubectl and the dashboard. A common set of labels allows tools to work interoperably, describing objects in a common manner that all tools can understand.

In addition to supporting tooling, the recommended labels describe applications in a way that can be queried.

The metadata is organized around the concept of an application. Kubernetes is not a platform as a service (PaaS) and doesn't have or enforce a formal notion of an application. Instead, applications are informal and described with metadata. The definition of what an application contains is loose.

Shared labels and annotations share a common prefix: app.kubernetes.io. Labels without a prefix are private to users. The shared prefix ensures that shared labels do not interfere with custom user labels.

In order to take full advantage of using these labels, they should be applied on every resource object.

To illustrate these labels in action, consider the following StatefulSet object:

An application can be installed one or more times into a Kubernetes cluster and, in some cases, the same namespace. For example, WordPress can be installed more than once where different websites are different installations of WordPress.

The name of an application and the instance name are recorded separately. For example, WordPress has a app.kubernetes.io/name of wordpress while it has an instance name, represented as app.kubernetes.io/instance with a value of wordpress-abcxyz. This enables the application and instance of the application to be identifiable. Every instance of an application must have a unique name.

To illustrate different ways to use these labels the following examples have varying complexity.

Consider the case for a simple stateless service deployed using Deployment and Service objects. The following two snippets represent how the labels could be used in their simplest form.

The Deployment is used to oversee the pods running the application itself.

The Service is used to expose the application.

Consider a slightly more complicated application: a web application (WordPress) using a database (MySQL), installed using Helm. The following snippets illustrate the start of objects used to deploy this application.

The start to the following Deployment is used for WordPress:

The Service is used to expose WordPress:

MySQL is exposed as a StatefulSet with metadata for both it and the larger application it belongs to:

The Service is 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# This is an excerpt
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app.kubernetes.io/name: mysql
    app.kubernetes.io/instance: mysql-abcxyz
    app.kubernetes.io/version: "5.7.21"
    app.kubernetes.io/component: database
    app.kubernetes.io/part-of: wordpress
    app.kubernetes.io/managed-by: Helm
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: myservice
    app.kubernetes.io/instance: myservice-abcxyz
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: myservice
    app.kubernetes.io/instance: myservice-abcxyz
...
```

Example 4 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: wordpress
    app.kubernetes.io/instance: wordpress-abcxyz
    app.kubernetes.io/version: "4.9.4"
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/component: server
    app.kubernetes.io/part-of: wordpress
...
```

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-subdomain-names

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#resourceclaims-templates

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-garbage-collection

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## API-initiated Eviction

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/

**Contents:**
- API-initiated Eviction
- Calling the Eviction API
    - Note:
    - Note:
- How API-initiated eviction works
- Troubleshooting stuck evictions
- What's next
- Feedback

API-initiated eviction is the process by which you use the Eviction API to create an Eviction object that triggers graceful pod termination.

You can request eviction by calling the Eviction API directly, or programmatically using a client of the API server, like the kubectl drain command. This creates an Eviction object, which causes the API server to terminate the Pod.

API-initiated evictions respect your configured PodDisruptionBudgets and terminationGracePeriodSeconds.

Using the API to create an Eviction object for a Pod is like performing a policy-controlled DELETE operation on the Pod.

You can use a Kubernetes language client to access the Kubernetes API and create an Eviction object. To do this, you POST the attempted operation, similar to the following example:

Note:policy/v1 Eviction is available in v1.22+. Use policy/v1beta1 with prior releases.{ "apiVersion": "policy/v1", "kind": "Eviction", "metadata": { "name": "quux", "namespace": "default" } }

Note:Deprecated in v1.22 in favor of policy/v1{ "apiVersion": "policy/v1beta1", "kind": "Eviction", "metadata": { "name": "quux", "namespace": "default" } }

Alternatively, you can attempt an eviction operation by accessing the API using curl or wget, similar to the following example:

When you request an eviction using the API, the API server performs admission checks and responds in one of the following ways:

If the Pod you want to evict isn't part of a workload that has a PodDisruptionBudget, the API server always returns 200 OK and allows the eviction.

If the API server allows the eviction, the Pod is deleted as follows:

In some cases, your applications may enter a broken state, where the Eviction API will only return 429 or 500 responses until you intervene. This can happen if, for example, a ReplicaSet creates pods for your application but new pods do not enter a Ready state. You may also notice this behavior in cases where the last evicted Pod had a long termination grace period.

If you notice stuck evictions, try one of the following solutions:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (json):
```json
{
  "apiVersion": "policy/v1",
  "kind": "Eviction",
  "metadata": {
    "name": "quux",
    "namespace": "default"
  }
}
```

Example 2 (json):
```json
{
  "apiVersion": "policy/v1beta1",
  "kind": "Eviction",
  "metadata": {
    "name": "quux",
    "namespace": "default"
  }
}
```

Example 3 (bash):
```bash
curl -v -H 'Content-type: application/json' https://your-cluster-api-endpoint.example/api/v1/namespaces/default/pods/quux/eviction -d @eviction.json
```

---

## ConfigMaps

**URL:** https://kubernetes.io/docs/concepts/configuration/configmap/

**Contents:**
- ConfigMaps
    - Caution:
- Motivation
    - Note:
- ConfigMap object
- ConfigMaps and Pods
    - Note:
- Using ConfigMaps
  - Using ConfigMaps as files from a Pod
    - Mounted ConfigMaps are updated automatically

A ConfigMap is an API object used to store non-confidential data in key-value pairs. Pods can consume ConfigMaps as environment variables, command-line arguments, or as configuration files in a volume.

A ConfigMap is an API object used to store non-confidential data in key-value pairs. Pods can consume ConfigMaps as environment variables, command-line arguments, or as configuration files in a volume.

A ConfigMap allows you to decouple environment-specific configuration from your container images, so that your applications are easily portable.

Use a ConfigMap for setting configuration data separately from application code.

For example, imagine that you are developing an application that you can run on your own computer (for development) and in the cloud (to handle real traffic). You write the code to look in an environment variable named DATABASE_HOST. Locally, you set that variable to localhost. In the cloud, you set it to refer to a Kubernetes Service that exposes the database component to your cluster. This lets you fetch a container image running in the cloud and debug the exact same code locally if needed.

A ConfigMap is an API object that lets you store configuration for other objects to use. Unlike most Kubernetes objects that have a spec, a ConfigMap has data and binaryData fields. These fields accept key-value pairs as their values. Both the data field and the binaryData are optional. The data field is designed to contain UTF-8 strings while the binaryData field is designed to contain binary data as base64-encoded strings.

The name of a ConfigMap must be a valid DNS subdomain name.

Each key under the data or the binaryData field must consist of alphanumeric characters, -, _ or .. The keys stored in data must not overlap with the keys in the binaryData field.

Starting from v1.19, you can add an immutable field to a ConfigMap definition to create an immutable ConfigMap.

You can write a Pod spec that refers to a ConfigMap and configures the container(s) in that Pod based on the data in the ConfigMap. The Pod and the ConfigMap must be in the same namespace.

Here's an example ConfigMap that has some keys with single values, and other keys where the value looks like a fragment of a configuration format.

There are four different ways that you can use a ConfigMap to configure a container inside a Pod:

These different methods lend themselves to different ways of modeling the data being consumed. For the first three methods, the kubelet uses the 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: game-demo
data:
  # property-like keys; each key maps to a simple value
  player_initial_lives: "3"
  ui_properties_file_name: "user-interface.properties"

  # file-like keys
  game.properties: |
    enemy.types=aliens,monsters
    player.maximum-lives=5    
  user-interface.properties: |
    color.good=purple
    color.bad=yellow
    allow.textmode=true
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-demo-pod
spec:
  containers:
    - name: demo
      image: alpine
      command: ["sleep", "3600"]
      env:
        # Define the environment variable
        - name: PLAYER_INITIAL_LIVES # Notice that the case is different here
                                     # from the key name in the ConfigMap.
          valueFrom:
            configMapKeyRef:
              name: game-demo           # The ConfigMap this value comes from.
              key: player_initial_lives # The key to fetch.
        - name: UI_PROPERTIES_FILE_NAME
          val
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mypod
spec:
  containers:
  - name: mypod
    image: redis
    volumeMounts:
    - name: foo
      mountPath: "/etc/foo"
      readOnly: true
  volumes:
  - name: foo
    configMap:
      name: myconfigmap
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myconfigmap
data:
  username: k8s-admin
  access_level: "1"
```

---

## Storage Classes

**URL:** https://kubernetes.io/docs/concepts/storage/storage-classes

**Contents:**
- Storage Classes
- StorageClass objects
- Default StorageClass
    - Note:
- Provisioner
- Reclaim policy
- Volume expansion
    - Note:
- Mount options
- Volume binding mode

This document describes the concept of a StorageClass in Kubernetes. Familiarity with volumes and persistent volumes is suggested.

A StorageClass provides a way for administrators to describe the classes of storage they offer. Different classes might map to quality-of-service levels, or to backup policies, or to arbitrary policies determined by the cluster administrators. Kubernetes itself is unopinionated about what classes represent.

The Kubernetes concept of a storage class is similar to “profiles” in some other storage system designs.

Each StorageClass contains the fields provisioner, parameters, and reclaimPolicy, which are used when a PersistentVolume belonging to the class needs to be dynamically provisioned to satisfy a PersistentVolumeClaim (PVC).

The name of a StorageClass object is significant, and is how users can request a particular class. Administrators set the name and other parameters of a class when first creating StorageClass objects.

As an administrator, you can specify a default StorageClass that applies to any PVCs that don't request a specific class. For more details, see the PersistentVolumeClaim concept.

Here's an example of a StorageClass:

You can mark a StorageClass as the default for your cluster. For instructions on setting the default StorageClass, see Change the default StorageClass.

When a PVC does not specify a storageClassName, the default StorageClass is used.

If you set the storageclass.kubernetes.io/is-default-class annotation to true on more than one StorageClass in your cluster, and you then create a PersistentVolumeClaim with no storageClassName set, Kubernetes uses the most recently created default StorageClass.

You can create a PersistentVolumeClaim without specifying a storageClassName for the new PVC, and you can do so even when no default StorageClass exists in your cluster. In this case, the new PVC creates as you defined it, and the storageClassName of that PVC remains unset until a default becomes available.

You can have a cluster without any default StorageClass. If you don't mark any StorageClass as default (and one hasn't been set for you by, for example, a cloud provider), then Kubernetes cannot apply that defaulting for PersistentVolumeClaims that need it.

If or when a default StorageClass becomes available, the control plane identifies any existing PVCs without storageClassName. For the PVCs that either have an empty value for storageClassName or do not have this key, the control plane then 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: low-latency
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: csi-driver.example-vendor.example
reclaimPolicy: Retain # default value is Delete
allowVolumeExpansion: true
mountOptions:
  - discard # this might enable UNMAP / TRIM at the block storage layer
volumeBindingMode: WaitForFirstConsumer
parameters:
  guaranteedReadWriteLatency: "true" # provider-specific
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: task-pv-pod
spec:
  nodeSelector:
    kubernetes.io/hostname: kube-01
  volumes:
    - name: task-pv-storage
      persistentVolumeClaim:
        claimName: task-pv-claim
  containers:
    - name: task-pv-container
      image: nginx
      ports:
        - containerPort: 80
          name: "http-server"
      volumeMounts:
        - mountPath: "/usr/share/nginx/html"
          name: task-pv-storage
```

Example 3 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner:  example.com/example
parameters:
  type: pd-standard
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values:
    - us-central-1a
    - us-central-1b
```

Example 4 (yaml):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  csi.storage.k8s.io/fstype: xfs
  type: io1
  iopsPerGB: "50"
  encrypted: "true"
  tagSpecification_1: "key1=value1"
  tagSpecification_2: "key2=value2"
allowedTopologies:
- matchLabelExpressions:
  - key: topology.ebs.csi.aws.com/zone
    values:
    - us-east-2c
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#cluster-level-logging

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Namespaces

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces

**Contents:**
- Namespaces
- When to Use Multiple Namespaces
    - Note:
- Initial namespaces
- Working with Namespaces
    - Note:
  - Viewing namespaces
  - Setting the namespace for a request
  - Setting the namespace preference
- Namespaces and DNS

In Kubernetes, namespaces provide a mechanism for isolating groups of resources within a single cluster. Names of resources need to be unique within a namespace, but not across namespaces. Namespace-based scoping is applicable only for namespaced objects (e.g. Deployments, Services, etc.) and not for cluster-wide objects (e.g. StorageClass, Nodes, PersistentVolumes, etc.).

Namespaces are intended for use in environments with many users spread across multiple teams, or projects. For clusters with a few to tens of users, you should not need to create or think about namespaces at all. Start using namespaces when you need the features they provide.

Namespaces provide a scope for names. Names of resources need to be unique within a namespace, but not across namespaces. Namespaces cannot be nested inside one another and each Kubernetes resource can only be in one namespace.

Namespaces are a way to divide cluster resources between multiple users (via resource quota).

It is not necessary to use multiple namespaces to separate slightly different resources, such as different versions of the same software: use labels to distinguish resources within the same namespace.

Kubernetes starts with four initial namespaces:

Creation and deletion of namespaces are described in the Admin Guide documentation for namespaces.

You can list the current namespaces in a cluster using:

To set the namespace for a current request, use the --namespace flag.

You can permanently save the namespace for all subsequent kubectl commands in that context.

When you create a Service, it creates a corresponding DNS entry. This entry is of the form <service-name>.<namespace-name>.svc.cluster.local, which means that if a container only uses <service-name>, it will resolve to the service which is local to a namespace. This is useful for using the same configuration across multiple namespaces such as Development, Staging and Production. If you want to reach across namespaces, you need to use the fully qualified domain name (FQDN).

As a result, all namespace names must be valid RFC 1123 DNS labels.

By creating namespaces with the same name as public top-level domains, Services in these namespaces can have short DNS names that overlap with public DNS records. Workloads from any namespace performing a DNS lookup without a trailing dot will be redirected to those services, taking precedence over public DNS.

To mitigate this, limit privileges for creating namespaces to trusted users. If required

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get namespace
```

Example 2 (unknown):
```unknown
NAME              STATUS   AGE
default           Active   1d
kube-node-lease   Active   1d
kube-public       Active   1d
kube-system       Active   1d
```

Example 3 (shell):
```shell
kubectl run nginx --image=nginx --namespace=<insert-namespace-name-here>
kubectl get pods --namespace=<insert-namespace-name-here>
```

Example 4 (shell):
```shell
kubectl config set-context --current --namespace=<insert-namespace-name-here>
# Validate it
kubectl config view --minify | grep namespace:
```

---

## Container Runtime Interface (CRI)

**URL:** https://kubernetes.io/docs/concepts/architecture/cri

**Contents:**
- Container Runtime Interface (CRI)
- The API
- Upgrading
- What's next
- Feedback

The CRI is a plugin interface which enables the kubelet to use a wide variety of container runtimes, without having a need to recompile the cluster components.

You need a working container runtime on each Node in your cluster, so that the kubelet can launch Pods and their containers.

The Container Runtime Interface (CRI) is the main protocol for the communication between the kubelet and Container Runtime.

The Container Runtime Interface (CRI) is the main protocol for the communication between the kubelet and Container Runtime.

The Kubernetes Container Runtime Interface (CRI) defines the main gRPC protocol for the communication between the node components kubelet and container runtime.

The kubelet acts as a client when connecting to the container runtime via gRPC. The runtime and image service endpoints have to be available in the container runtime, which can be configured separately within the kubelet by using the --container-runtime-endpoint command line flag.

For Kubernetes v1.26 and later, the kubelet requires that the container runtime supports the v1 CRI API. If a container runtime does not support the v1 API, the kubelet will not register the node.

When upgrading the Kubernetes version on a node, the kubelet restarts. If the container runtime does not support the v1 CRI API, the kubelet will fail to register and report an error. If a gRPC re-dial is required because the container runtime has been upgraded, the runtime must support the v1 CRI API for the connection to succeed. This might require a restart of the kubelet after the container runtime is correctly configured.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Process ID Limits And Reservations

**URL:** https://kubernetes.io/docs/concepts/policy/pid-limiting/

**Contents:**
- Process ID Limits And Reservations
    - Note:
    - Caution:
- Node PID limits
- Pod PID limits
- PID based eviction
- What's next
- Feedback

Kubernetes allow you to limit the number of process IDs (PIDs) that a Pod can use. You can also reserve a number of allocatable PIDs for each node for use by the operating system and daemons (rather than by Pods).

Process IDs (PIDs) are a fundamental resource on nodes. It is trivial to hit the task limit without hitting any other resource limits, which can then cause instability to a host machine.

Cluster administrators require mechanisms to ensure that Pods running in the cluster cannot induce PID exhaustion that prevents host daemons (such as the kubelet or kube-proxy, and potentially also the container runtime) from running. In addition, it is important to ensure that PIDs are limited among Pods in order to ensure they have limited impact on other workloads on the same node.

You can configure a kubelet to limit the number of PIDs a given Pod can consume. For example, if your node's host OS is set to use a maximum of 262144 PIDs and expect to host less than 250 Pods, one can give each Pod a budget of 1000 PIDs to prevent using up that node's overall number of available PIDs. If the admin wants to overcommit PIDs similar to CPU or memory, they may do so as well with some additional risks. Either way, a single Pod will not be able to bring the whole machine down. This kind of resource limiting helps to prevent simple fork bombs from affecting operation of an entire cluster.

Per-Pod PID limiting allows administrators to protect one Pod from another, but does not ensure that all Pods scheduled onto that host are unable to impact the node overall. Per-Pod limiting also does not protect the node agents themselves from PID exhaustion.

You can also reserve an amount of PIDs for node overhead, separate from the allocation to Pods. This is similar to how you can reserve CPU, memory, or other resources for use by the operating system and other facilities outside of Pods and their containers.

PID limiting is an important sibling to compute resource requests and limits. However, you specify it in a different way: rather than defining a Pod's resource limit in the .spec for a Pod, you configure the limit as a setting on the kubelet. Pod-defined PID limits are not currently supported.

Kubernetes allows you to reserve a number of process IDs for the system use. To configure the reservation, use the parameter pid=<number> in the --system-reserved and --kube-reserved command line options to the kubelet. The value you specified declares that the specified number of 

*[Content truncated]*

---

## Init Containers

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/init-containers/

**Contents:**
- Init Containers
- Understanding init containers
  - Differences from regular containers
  - Differences from sidecar containers
- Using init containers
  - Examples
    - Init containers in use
- Detailed behavior
  - Resource sharing within containers
  - Init containers and Linux cgroups

This page provides an overview of init containers: specialized containers that run before app containers in a Pod. Init containers can contain utilities or setup scripts not present in an app image.

You can specify init containers in the Pod specification alongside the containers array (which describes app containers).

In Kubernetes, a sidecar container is a container that starts before the main application container and continues to run. This document is about init containers: containers that run to completion during Pod initialization.

A Pod can have multiple containers running apps within it, but it can also have one or more init containers, which are run before the app containers are started.

Init containers are exactly like regular containers, except:

If a Pod's init container fails, the kubelet repeatedly restarts that init container until it succeeds. However, if the Pod has a restartPolicy of Never, and an init container fails during startup of that Pod, Kubernetes treats the overall Pod as failed.

To specify an init container for a Pod, add the initContainers field into the Pod specification, as an array of container items (similar to the app containers field and its contents). See Container in the API reference for more details.

The status of the init containers is returned in .status.initContainerStatuses field as an array of the container statuses (similar to the .status.containerStatuses field).

Init containers support all the fields and features of app containers, including resource limits, volumes, and security settings. However, the resource requests and limits for an init container are handled differently, as documented in Resource sharing within containers.

Regular init containers (in other words: excluding sidecar containers) do not support the lifecycle, livenessProbe, readinessProbe, or startupProbe fields. Init containers must run to completion before the Pod can be ready; sidecar containers continue running during a Pod's lifetime, and do support some probes. See sidecar container for further details about sidecar containers.

If you specify multiple init containers for a Pod, kubelet runs each init container sequentially. Each init container must succeed before the next can run. When all of the init containers have run to completion, kubelet initializes the application containers for the Pod and runs them as usual.

Init containers run and complete their tasks before the main application container starts. Unlike sidecar con

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
for i in {1..100}; do sleep 1; if nslookup myservice; then exit 0; fi; done; exit 1
```

Example 2 (shell):
```shell
curl -X POST http://$MANAGEMENT_SERVICE_HOST:$MANAGEMENT_SERVICE_PORT/register -d 'instance=$(<POD_NAME>)&ip=$(<POD_IP>)'
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app.kubernetes.io/name: MyApp
spec:
  containers:
  - name: myapp-container
    image: busybox:1.28
    command: ['sh', '-c', 'echo The app is running! && sleep 3600']
  initContainers:
  - name: init-myservice
    image: busybox:1.28
    command: ['sh', '-c', "until nslookup myservice.$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace).svc.cluster.local; do echo waiting for myservice; sleep 2; done"]
  - name: init-mydb
    image: busybox:1.28
    command: ['sh', '-c', "until nslookup mydb.$(cat /var/run/secrets/kub
...
```

Example 4 (shell):
```shell
kubectl apply -f myapp.yaml
```

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#container-runtime

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Finalizers

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/

**Contents:**
- Finalizers
- How finalizers work
    - Note:
    - Note:
- Owner references, labels, and finalizers
    - Note:
- What's next
- Feedback

Finalizers are namespaced keys that tell Kubernetes to wait until specific conditions are met before it fully deletes resources that are marked for deletion. Finalizers alert controllers to clean up resources the deleted object owned.

When you tell Kubernetes to delete an object that has finalizers specified for it, the Kubernetes API marks the object for deletion by populating .metadata.deletionTimestamp, and returns a 202 status code (HTTP "Accepted"). The target object remains in a terminating state while the control plane, or other components, take the actions defined by the finalizers. After these actions are complete, the controller removes the relevant finalizers from the target object. When the metadata.finalizers field is empty, Kubernetes considers the deletion complete and deletes the object.

You can use finalizers to control garbage collection of resources. For example, you can define a finalizer to clean up related API resources or infrastructure before the controller deletes the object being finalized.

You can use finalizers to control garbage collection of objects by alerting controllers to perform specific cleanup tasks before deleting the target resource.

Finalizers don't usually specify the code to execute. Instead, they are typically lists of keys on a specific resource similar to annotations. Kubernetes specifies some finalizers automatically, but you can also specify your own.

When you create a resource using a manifest file, you can specify finalizers in the metadata.finalizers field. When you attempt to delete the resource, the API server handling the delete request notices the values in the finalizers field and does the following:

The controller managing that finalizer notices the update to the object setting the metadata.deletionTimestamp, indicating deletion of the object has been requested. The controller then attempts to satisfy the requirements of the finalizers specified for that resource. Each time a finalizer condition is satisfied, the controller removes that key from the resource's finalizers field. When the finalizers field is emptied, an object with a deletionTimestamp field set is automatically deleted. You can also use finalizers to prevent deletion of unmanaged resources.

A common example of a finalizer is kubernetes.io/pv-protection, which prevents accidental deletion of PersistentVolume objects. When a PersistentVolume object is in use by a Pod, Kubernetes adds the pv-protection finalizer. If you try to delet

*[Content truncated]*

---

## Configuration Best Practices

**URL:** https://kubernetes.io/docs/concepts/configuration/overview/

**Contents:**
- Configuration Best Practices
- General Configuration Tips
    - Note:
- "Naked" Pods versus ReplicaSets, Deployments, and Jobs
- Services
- Using Labels
- Using kubectl
- Feedback

This document highlights and consolidates configuration best practices that are introduced throughout the user guide, Getting Started documentation, and examples.

This is a living document. If you think of something that is not on this list but might be useful to others, please don't hesitate to file an issue or submit a PR.

When defining configurations, specify the latest stable API version.

Configuration files should be stored in version control before being pushed to the cluster. This allows you to quickly roll back a configuration change if necessary. It also aids cluster re-creation and restoration.

Write your configuration files using YAML rather than JSON. Though these formats can be used interchangeably in almost all scenarios, YAML tends to be more user-friendly.

Group related objects into a single file whenever it makes sense. One file is often easier to manage than several. See the guestbook-all-in-one.yaml file as an example of this syntax.

Note also that many kubectl commands can be called on a directory. For example, you can call kubectl apply on a directory of config files.

Don't specify default values unnecessarily: simple, minimal configuration will make errors less likely.

Put object descriptions in annotations, to allow better introspection.

There is a breaking change introduced in the YAML 1.2 boolean values specification with respect to YAML 1.1. This is a known issue in Kubernetes. YAML 1.2 only recognizes true and false as valid booleans, while YAML 1.1 also accepts yes, no, on, and off as booleans. However, Kubernetes uses YAML parsers that are mostly compatible with YAML 1.1, which means that using yes or no instead of true or false in a YAML manifest may cause unexpected errors or behaviors. To avoid this issue, it is recommended to always use true or false for boolean values in YAML manifests, and to quote any strings that may be confused with booleans, such as "yes" or "no".

Besides booleans, there are additional specifications changes between YAML versions. Please refer to the YAML Specification Changes documentation for a comprehensive list.

Don't use naked Pods (that is, Pods not bound to a ReplicaSet or Deployment) if you can avoid it. Naked Pods will not be rescheduled in the event of a node failure.

A Deployment, which both creates a ReplicaSet to ensure that the desired number of Pods is always available, and specifies a strategy to replace Pods (such as RollingUpdate), is almost always preferable to creating 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
FOO_SERVICE_HOST=<the host the Service is running on>
FOO_SERVICE_PORT=<the port the Service is running on>
```

---

## Pods

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/#privileged-mode-for-containers

**Contents:**
- Pods
- What is a Pod?
    - Note:
- Using Pods
  - Workload resources for managing pods
- Working with Pods
    - Note:
  - Pod OS
  - Pods and controllers
  - Pod templates

Pods are the smallest deployable units of computing that you can create and manage in Kubernetes.

A Pod (as in a pod of whales or pea pod) is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers. A Pod's contents are always co-located and co-scheduled, and run in a shared context. A Pod models an application-specific "logical host": it contains one or more application containers which are relatively tightly coupled. In non-cloud contexts, applications executed on the same physical or virtual machine are analogous to cloud applications executed on the same logical host.

As well as application containers, a Pod can contain init containers that run during Pod startup. You can also inject ephemeral containers for debugging a running Pod.

The shared context of a Pod is a set of Linux namespaces, cgroups, and potentially other facets of isolation - the same things that isolate a container. Within a Pod's context, the individual applications may have further sub-isolations applied.

A Pod is similar to a set of containers with shared namespaces and shared filesystem volumes.

Pods in a Kubernetes cluster are used in two main ways:

Pods that run a single container. The "one-container-per-Pod" model is the most common Kubernetes use case; in this case, you can think of a Pod as a wrapper around a single container; Kubernetes manages Pods rather than managing the containers directly.

Pods that run multiple containers that need to work together. A Pod can encapsulate an application composed of multiple co-located containers that are tightly coupled and need to share resources. These co-located containers form a single cohesive unit.

Grouping multiple co-located and co-managed containers in a single Pod is a relatively advanced use case. You should use this pattern only in specific instances in which your containers are tightly coupled.

You don't need to run multiple containers to provide replication (for resilience or capacity); if you need multiple replicas, see Workload management.

The following is an example of a Pod which consists of a container running the image nginx:1.14.2.

To create the Pod shown above, run the following command:

Pods are generally not created directly and are created using workload resources. See Working with Pods for more information on how Pods are used with workload resources.

Usually you don't need to create Pods directly, even singleton Pods. Instead, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml
```

Example 3 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    # This is the pod template
    spec:
      containers:
      - name: hello
        image: busybox:1.28
        command: ['sh', '-c', 'echo "Hello, Kubernetes!" && sleep 3600']
      restartPolicy: OnFailure
    # The pod template ends here
```

---

## Kubernetes Components

**URL:** https://kubernetes.io/docs/concepts/overview/components/

**Contents:**
- Kubernetes Components
- Core Components
  - Control Plane Components
  - Node Components
- Addons
- Flexibility in Architecture
- Feedback

This page provides a high-level overview of the essential components that make up a Kubernetes cluster.

The components of a Kubernetes cluster

A Kubernetes cluster consists of a control plane and one or more worker nodes. Here's a brief overview of the main components:

Manage the overall state of the cluster:

Run on every node, maintaining running pods and providing the Kubernetes runtime environment:

Your cluster may require additional software on each node; for example, you might also run systemd on a Linux node to supervise local components.

Addons extend the functionality of Kubernetes. A few important examples include:

Kubernetes allows for flexibility in how these components are deployed and managed. The architecture can be adapted to various needs, from small development environments to large-scale production deployments.

For more detailed information about each component and various ways to configure your cluster architecture, see the Cluster Architecture page.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#network-plugins

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Volume Snapshots

**URL:** https://kubernetes.io/docs/concepts/storage/volume-snapshots/

**Contents:**
- Volume Snapshots
- Introduction
- Lifecycle of a volume snapshot and volume snapshot content
  - Provisioning Volume Snapshot
    - Pre-provisioned
    - Dynamic
  - Binding
  - Persistent Volume Claim as Snapshot Source Protection
  - Delete
- VolumeSnapshots

In Kubernetes, a VolumeSnapshot represents a snapshot of a volume on a storage system. This document assumes that you are already familiar with Kubernetes persistent volumes.

Similar to how API resources PersistentVolume and PersistentVolumeClaim are used to provision volumes for users and administrators, VolumeSnapshotContent and VolumeSnapshot API resources are provided to create volume snapshots for users and administrators.

A VolumeSnapshotContent is a snapshot taken from a volume in the cluster that has been provisioned by an administrator. It is a resource in the cluster just like a PersistentVolume is a cluster resource.

A VolumeSnapshot is a request for snapshot of a volume by a user. It is similar to a PersistentVolumeClaim.

VolumeSnapshotClass allows you to specify different attributes belonging to a VolumeSnapshot. These attributes may differ among snapshots taken from the same volume on the storage system and therefore cannot be expressed by using the same StorageClass of a PersistentVolumeClaim.

Volume snapshots provide Kubernetes users with a standardized way to copy a volume's contents at a particular point in time without creating an entirely new volume. This functionality enables, for example, database administrators to backup databases before performing edit or delete modifications.

Users need to be aware of the following when using this feature:

For advanced use cases, such as creating group snapshots of multiple volumes, see the external CSI Volume Group Snapshot documentation.

VolumeSnapshotContents are resources in the cluster. VolumeSnapshots are requests for those resources. The interaction between VolumeSnapshotContents and VolumeSnapshots follow this lifecycle:

There are two ways snapshots may be provisioned: pre-provisioned or dynamically provisioned.

A cluster administrator creates a number of VolumeSnapshotContents. They carry the details of the real volume snapshot on the storage system which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

Instead of using a pre-existing snapshot, you can request that a snapshot to be dynamically taken from a PersistentVolumeClaim. The VolumeSnapshotClass specifies storage provider-specific parameters to use when taking a snapshot.

The snapshot controller handles the binding of a VolumeSnapshot object with an appropriate VolumeSnapshotContent object, in both pre-provisioned and dynamically provisioned scenarios. The binding

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: new-snapshot-test
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: pvc-test
```

Example 2 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  source:
    volumeSnapshotContentName: test-content
```

Example 3 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: snapcontent-72d9a349-aacd-42d2-a240-d775650d2455
spec:
  deletionPolicy: Delete
  driver: hostpath.csi.k8s.io
  source:
    volumeHandle: ee0cfb94-f8d4-11e9-b2d8-0242ac110002
  sourceVolumeMode: Filesystem
  volumeSnapshotClassName: csi-hostpath-snapclass
  volumeSnapshotRef:
    name: new-snapshot-test
    namespace: default
    uid: 72d9a349-aacd-42d2-a240-d775650d2455
```

Example 4 (yaml):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: new-snapshot-content-test
spec:
  deletionPolicy: Delete
  driver: hostpath.csi.k8s.io
  source:
    snapshotHandle: 7bdd0de3-aaeb-11e8-9aae-0242ac110002
  sourceVolumeMode: Filesystem
  volumeSnapshotRef:
    name: new-snapshot-test
    namespace: default
```

---

## Pod Priority and Preemption

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/#how-to-use-priority-and-preemption

**Contents:**
- Pod Priority and Preemption
    - Warning:
- How to use priority and preemption
    - Note:
- PriorityClass
  - Notes about PodPriority and existing clusters
  - Example PriorityClass
- Non-preempting PriorityClass
  - Example Non-preempting PriorityClass
- Pod priority

Pods can have priority. Priority indicates the importance of a Pod relative to other Pods. If a Pod cannot be scheduled, the scheduler tries to preempt (evict) lower priority Pods to make scheduling of the pending Pod possible.

In a cluster where not all users are trusted, a malicious user could create Pods at the highest possible priorities, causing other Pods to be evicted/not get scheduled. An administrator can use ResourceQuota to prevent users from creating pods at high priorities.

See limit Priority Class consumption by default for details.

To use priority and preemption:

Add one or more PriorityClasses.

Create Pods withpriorityClassName set to one of the added PriorityClasses. Of course you do not need to create the Pods directly; normally you would add priorityClassName to the Pod template of a collection object like a Deployment.

Keep reading for more information about these steps.

A PriorityClass is a non-namespaced object that defines a mapping from a priority class name to the integer value of the priority. The name is specified in the name field of the PriorityClass object's metadata. The value is specified in the required value field. The higher the value, the higher the priority. The name of a PriorityClass object must be a valid DNS subdomain name, and it cannot be prefixed with system-.

A PriorityClass object can have any 32-bit integer value smaller than or equal to 1 billion. This means that the range of values for a PriorityClass object is from -2147483648 to 1000000000 inclusive. Larger numbers are reserved for built-in PriorityClasses that represent critical system Pods. A cluster admin should create one PriorityClass object for each such mapping that they want.

PriorityClass also has two optional fields: globalDefault and description. The globalDefault field indicates that the value of this PriorityClass should be used for Pods without a priorityClassName. Only one PriorityClass with globalDefault set to true can exist in the system. If there is no PriorityClass with globalDefault set, the priority of Pods with no priorityClassName is zero.

The description field is an arbitrary string. It is meant to tell users of the cluster when they should use this PriorityClass.

If you upgrade an existing cluster without this feature, the priority of your existing Pods is effectively zero.

Addition of a PriorityClass with globalDefault set to true does not change the priorities of existing Pods. The value of such a PriorityClass is us

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "This priority class should be used for XYZ service pods only."
```

Example 2 (yaml):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-nonpreempting
value: 1000000
preemptionPolicy: Never
globalDefault: false
description: "This priority class will not cause other pods to be preempted."
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    env: test
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  priorityClassName: high-priority
```

---

## Service

**URL:** https://kubernetes.io/docs/concepts/services-networking/service/#endpoints

**Contents:**
- Service
- Services in Kubernetes
  - Cloud-native service discovery
- Defining a Service
    - Note:
  - Relaxed naming requirements for Service objects
  - Port definitions
  - Services without selectors
    - Custom EndpointSlices
    - Note:

In Kubernetes, a Service is a method for exposing a network application that is running as one or more Pods in your cluster.

A key aim of Services in Kubernetes is that you don't need to modify your existing application to use an unfamiliar service discovery mechanism. You can run code in Pods, whether this is a code designed for a cloud-native world, or an older app you've containerized. You use a Service to make that set of Pods available on the network so that clients can interact with it.

If you use a Deployment to run your app, that Deployment can create and destroy Pods dynamically. From one moment to the next, you don't know how many of those Pods are working and healthy; you might not even know what those healthy Pods are named. Kubernetes Pods are created and destroyed to match the desired state of your cluster. Pods are ephemeral resources (you should not expect that an individual Pod is reliable and durable).

Each Pod gets its own IP address (Kubernetes expects network plugins to ensure this). For a given Deployment in your cluster, the set of Pods running in one moment in time could be different from the set of Pods running that application a moment later.

This leads to a problem: if some set of Pods (call them "backends") provides functionality to other Pods (call them "frontends") inside your cluster, how do the frontends find out and keep track of which IP address to connect to, so that the frontend can use the backend part of the workload?

The Service API, part of Kubernetes, is an abstraction to help you expose groups of Pods over a network. Each Service object defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible.

For example, consider a stateless image-processing backend which is running with 3 replicas. Those replicas are fungible—frontends do not care which backend they use. While the actual Pods that compose the backend set may change, the frontend clients should not need to be aware of that, nor should they need to keep track of the set of backends themselves.

The Service abstraction enables this decoupling.

The set of Pods targeted by a Service is usually determined by a selector that you define. To learn about other ways to define Service endpoints, see Services without selectors.

If your workload speaks HTTP, you might choose to use an Ingress to control how web traffic reaches that workload. Ingress is not a Service type, but it acts as the entry

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
  - name: nginx
    image: nginx:stable
    ports:
      - containerPort: 80
        name: http-web-svc

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
  - name: name-of-service-port
    protocol: TCP
    port: 80
    targetPort: http-web-svc
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
```

Example 4 (yaml):
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1 # by convention, use the name of the Service
                     # as a prefix for the name of the EndpointSlice
  labels:
    # You should set the "kubernetes.io/service-name" label.
    # Set its value to match the name of the Service
    kubernetes.io/service-name: my-service
addressType: IPv4
ports:
  - name: http # should match with the name of the service port defined above
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolume-deletion-protection-finalizer

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## Nodes

**URL:** https://kubernetes.io/docs/concepts/architecture/nodes/#swap-memory

**Contents:**
- Nodes
- Management
    - Note:
  - Node name uniqueness
  - Self-registration of Nodes
    - Note:
  - Manual Node administration
    - Note:
- Node status
- Node heartbeats

Kubernetes runs your workload by placing containers into Pods to run on Nodes. A node may be a virtual or physical machine, depending on the cluster. Each node is managed by the control plane and contains the services necessary to run Pods.

Typically you have several nodes in a cluster; in a learning or resource-limited environment, you might have only one node.

The components on a node include the kubelet, a container runtime, and the kube-proxy.

There are two main ways to have Nodes added to the API server:

After you create a Node object, or the kubelet on a node self-registers, the control plane checks whether the new Node object is valid. For example, if you try to create a Node from the following JSON manifest:

Kubernetes creates a Node object internally (the representation). Kubernetes checks that a kubelet has registered to the API server that matches the metadata.name field of the Node. If the node is healthy (i.e. all necessary services are running), then it is eligible to run a Pod. Otherwise, that node is ignored for any cluster activity until it becomes healthy.

Kubernetes keeps the object for the invalid Node and continues checking to see whether it becomes healthy.

You, or a controller, must explicitly delete the Node object to stop that health checking.

The name of a Node object must be a valid DNS subdomain name.

The name identifies a Node. Two Nodes cannot have the same name at the same time. Kubernetes also assumes that a resource with the same name is the same object. In case of a Node, it is implicitly assumed that an instance using the same name will have the same state (e.g. network settings, root disk contents) and attributes like node labels. This may lead to inconsistencies if an instance was modified without changing its name. If the Node needs to be replaced or updated significantly, the existing Node object needs to be removed from API server first and re-added after the update.

When the kubelet flag --register-node is true (the default), the kubelet will attempt to register itself with the API server. This is the preferred pattern, used by most distros.

For self-registration, the kubelet is started with the following options:

--kubeconfig - Path to credentials to authenticate itself to the API server.

--cloud-provider - How to talk to a cloud provider to read metadata about itself.

--register-node - Automatically register with the API server.

--register-with-taints - Register the node with the given list of taint

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
  "kind": "Node",
  "apiVersion": "v1",
  "metadata": {
    "name": "10.240.79.157",
    "labels": {
      "name": "my-first-k8s-node"
    }
  }
}
```

Example 2 (shell):
```shell
kubectl cordon $NODENAME
```

Example 3 (shell):
```shell
kubectl describe node <insert-node-name-here>
```

---

## Communication between Nodes and the Control Plane

**URL:** https://kubernetes.io/docs/concepts/architecture/control-plane-node-communication/

**Contents:**
- Communication between Nodes and the Control Plane
- Node to Control Plane
- Control plane to node
  - API server to kubelet
  - API server to nodes, pods, and services
  - SSH tunnels
    - Note:
  - Konnectivity service
- What's next
- Feedback

This document catalogs the communication paths between the API server and the Kubernetes cluster. The intent is to allow users to customize their installation to harden the network configuration such that the cluster can be run on an untrusted network (or on fully public IPs on a cloud provider).

Kubernetes has a "hub-and-spoke" API pattern. All API usage from nodes (or the pods they run) terminates at the API server. None of the other control plane components are designed to expose remote services. The API server is configured to listen for remote connections on a secure HTTPS port (typically 443) with one or more forms of client authentication enabled. One or more forms of authorization should be enabled, especially if anonymous requests or service account tokens are allowed.

Nodes should be provisioned with the public root certificate for the cluster such that they can connect securely to the API server along with valid client credentials. A good approach is that the client credentials provided to the kubelet are in the form of a client certificate. See kubelet TLS bootstrapping for automated provisioning of kubelet client certificates.

Pods that wish to connect to the API server can do so securely by leveraging a service account so that Kubernetes will automatically inject the public root certificate and a valid bearer token into the pod when it is instantiated. The kubernetes service (in default namespace) is configured with a virtual IP address that is redirected (via kube-proxy) to the HTTPS endpoint on the API server.

The control plane components also communicate with the API server over the secure port.

As a result, the default operating mode for connections from the nodes and pod running on the nodes to the control plane is secured by default and can run over untrusted and/or public networks.

There are two primary communication paths from the control plane (the API server) to the nodes. The first is from the API server to the kubelet process which runs on each node in the cluster. The second is from the API server to any node, pod, or service through the API server's proxy functionality.

The connections from the API server to the kubelet are used for:

These connections terminate at the kubelet's HTTPS endpoint. By default, the API server does not verify the kubelet's serving certificate, which makes the connection subject to man-in-the-middle attacks and unsafe to run over untrusted and/or public networks.

To verify this connection, use 

*[Content truncated]*

---

## Pods

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/#pod-templates

**Contents:**
- Pods
- What is a Pod?
    - Note:
- Using Pods
  - Workload resources for managing pods
- Working with Pods
    - Note:
  - Pod OS
  - Pods and controllers
  - Pod templates

Pods are the smallest deployable units of computing that you can create and manage in Kubernetes.

A Pod (as in a pod of whales or pea pod) is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers. A Pod's contents are always co-located and co-scheduled, and run in a shared context. A Pod models an application-specific "logical host": it contains one or more application containers which are relatively tightly coupled. In non-cloud contexts, applications executed on the same physical or virtual machine are analogous to cloud applications executed on the same logical host.

As well as application containers, a Pod can contain init containers that run during Pod startup. You can also inject ephemeral containers for debugging a running Pod.

The shared context of a Pod is a set of Linux namespaces, cgroups, and potentially other facets of isolation - the same things that isolate a container. Within a Pod's context, the individual applications may have further sub-isolations applied.

A Pod is similar to a set of containers with shared namespaces and shared filesystem volumes.

Pods in a Kubernetes cluster are used in two main ways:

Pods that run a single container. The "one-container-per-Pod" model is the most common Kubernetes use case; in this case, you can think of a Pod as a wrapper around a single container; Kubernetes manages Pods rather than managing the containers directly.

Pods that run multiple containers that need to work together. A Pod can encapsulate an application composed of multiple co-located containers that are tightly coupled and need to share resources. These co-located containers form a single cohesive unit.

Grouping multiple co-located and co-managed containers in a single Pod is a relatively advanced use case. You should use this pattern only in specific instances in which your containers are tightly coupled.

You don't need to run multiple containers to provide replication (for resilience or capacity); if you need multiple replicas, see Workload management.

The following is an example of a Pod which consists of a container running the image nginx:1.14.2.

To create the Pod shown above, run the following command:

Pods are generally not created directly and are created using workload resources. See Working with Pods for more information on how Pods are used with workload resources.

Usually you don't need to create Pods directly, even singleton Pods. Instead, 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/simple-pod.yaml
```

Example 3 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    # This is the pod template
    spec:
      containers:
      - name: hello
        image: busybox:1.28
        command: ['sh', '-c', 'echo "Hello, Kubernetes!" && sleep 3600']
      restartPolicy: OnFailure
    # The pod template ends here
```

---

## Sidecar Containers

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/

**Contents:**
- Sidecar Containers
- Sidecar containers in Kubernetes
  - Example application
- Sidecar containers and Pod lifecycle
  - Jobs with sidecar containers
- Differences from application containers
- Differences from init containers
- Resource sharing within containers
  - Sidecar containers and Linux cgroups
- What's next

Sidecar containers are the secondary containers that run along with the main application container within the same Pod. These containers are used to enhance or to extend the functionality of the primary app container by providing additional services, or functionality such as logging, monitoring, security, or data synchronization, without directly altering the primary application code.

Typically, you only have one app container in a Pod. For example, if you have a web application that requires a local webserver, the local webserver is a sidecar and the web application itself is the app container.

Kubernetes implements sidecar containers as a special case of init containers; sidecar containers remain running after Pod startup. This document uses the term regular init containers to clearly refer to containers that only run during Pod startup.

Provided that your cluster has the SidecarContainers feature gate enabled (the feature is active by default since Kubernetes v1.29), you can specify a restartPolicy for containers listed in a Pod's initContainers field. These restartable sidecar containers are independent from other init containers and from the main application container(s) within the same pod. These can be started, stopped, or restarted without affecting the main application container and other init containers.

You can also run a Pod with multiple containers that are not marked as init or sidecar containers. This is appropriate if the containers within the Pod are required for the Pod to work overall, but you don't need to control which containers start or stop first. You could also do this if you need to support older versions of Kubernetes that don't support a container-level restartPolicy field.

Here's an example of a Deployment with two containers, one of which is a sidecar:

If an init container is created with its restartPolicy set to Always, it will start and remain running during the entire life of the Pod. This can be helpful for running supporting services separated from the main application containers.

If a readinessProbe is specified for this init container, its result will be used to determine the ready state of the Pod.

Since these containers are defined as init containers, they benefit from the same ordering and sequential guarantees as regular init containers, allowing you to mix sidecar containers with regular init containers for complex Pod initialization flows.

Compared to regular init containers, sidecars defined within initC

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: alpine:latest
          command: ['sh', '-c', 'while true; do echo "logging" >> /opt/logs.txt; sleep 1; done']
          volumeMounts:
            - name: data
              mountPath: /opt
      initContainers:
        - name: logshipper
          image: alpine:latest
          restartPolicy: Always
          command: [
...
```

Example 2 (yaml):
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: myjob
spec:
  template:
    spec:
      containers:
        - name: myjob
          image: alpine:latest
          command: ['sh', '-c', 'echo "logging" > /opt/logs.txt']
          volumeMounts:
            - name: data
              mountPath: /opt
      initContainers:
        - name: logshipper
          image: alpine:latest
          restartPolicy: Always
          command: ['sh', '-c', 'tail -F /opt/logs.txt']
          volumeMounts:
            - name: data
              mountPath: /opt
      restartPolicy: Never
      volumes:
        - n
...
```

---

## Container Runtime Interface (CRI)

**URL:** https://kubernetes.io/docs/concepts/architecture/cri/

**Contents:**
- Container Runtime Interface (CRI)
- The API
- Upgrading
- What's next
- Feedback

The CRI is a plugin interface which enables the kubelet to use a wide variety of container runtimes, without having a need to recompile the cluster components.

You need a working container runtime on each Node in your cluster, so that the kubelet can launch Pods and their containers.

The Container Runtime Interface (CRI) is the main protocol for the communication between the kubelet and Container Runtime.

The Container Runtime Interface (CRI) is the main protocol for the communication between the kubelet and Container Runtime.

The Kubernetes Container Runtime Interface (CRI) defines the main gRPC protocol for the communication between the node components kubelet and container runtime.

The kubelet acts as a client when connecting to the container runtime via gRPC. The runtime and image service endpoints have to be available in the container runtime, which can be configured separately within the kubelet by using the --container-runtime-endpoint command line flag.

For Kubernetes v1.26 and later, the kubelet requires that the container runtime supports the v1 CRI API. If a container runtime does not support the v1 API, the kubelet will not register the node.

When upgrading the Kubernetes version on a node, the kubelet restarts. If the container runtime does not support the v1 CRI API, the kubelet will fail to register and report an error. If a gRPC re-dial is required because the container runtime has been upgraded, the runtime must support the v1 CRI API for the connection to succeed. This might require a restart of the kubelet after the container runtime is correctly configured.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Policies

**URL:** https://kubernetes.io/docs/concepts/policy/

**Contents:**
- Policies
- Apply policies using API objects
- Apply policies using admission controllers
- Apply policies using ValidatingAdmissionPolicy
- Apply policies using dynamic admission control
  - Implementations
- Apply policies using Kubelet configurations
- Feedback

Kubernetes policies are configurations that manage other configurations or runtime behaviors. Kubernetes offers various forms of policies, described below:

Some API objects act as policies. Here are some examples:

An admission controller runs in the API server and can validate or mutate API requests. Some admission controllers act to apply policies. For example, the AlwaysPullImages admission controller modifies a new Pod to set the image pull policy to Always.

Kubernetes has several built-in admission controllers that are configurable via the API server --enable-admission-plugins flag.

Details on admission controllers, with the complete list of available admission controllers, are documented in a dedicated section:

Validating admission policies allow configurable validation checks to be executed in the API server using the Common Expression Language (CEL). For example, a ValidatingAdmissionPolicy can be used to disallow use of the latest image tag.

A ValidatingAdmissionPolicy operates on an API request and can be used to block, audit, and warn users about non-compliant configurations.

Details on the ValidatingAdmissionPolicy API, with examples, are documented in a dedicated section:

Dynamic admission controllers (or admission webhooks) run outside the API server as separate applications that register to receive webhooks requests to perform validation or mutation of API requests.

Dynamic admission controllers can be used to apply policies on API requests and trigger other policy-based workflows. A dynamic admission controller can perform complex checks including those that require retrieval of other cluster resources and external data. For example, an image verification check can lookup data from OCI registries to validate the container image signatures and attestations.

Details on dynamic admission control are documented in a dedicated section:

Dynamic Admission Controllers that act as flexible policy engines are being developed in the Kubernetes ecosystem, such as:

Kubernetes allows configuring the Kubelet on each worker node. Some Kubelet configurations act as policies:

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

*[Content truncated]*

---

## Controlling Access to the Kubernetes API

**URL:** https://kubernetes.io/docs/concepts/security/controlling-access/

**Contents:**
- Controlling Access to the Kubernetes API
- Transport security
- Authentication
- Authorization
- Admission control
- Auditing
- What's next
- Feedback

This page provides an overview of controlling access to the Kubernetes API.

Users access the Kubernetes API using kubectl, client libraries, or by making REST requests. Both human users and Kubernetes service accounts can be authorized for API access. When a request reaches the API, it goes through several stages, illustrated in the following diagram:

By default, the Kubernetes API server listens on port 6443 on the first non-localhost network interface, protected by TLS. In a typical production Kubernetes cluster, the API serves on port 443. The port can be changed with the --secure-port, and the listening IP address with the --bind-address flag.

The API server presents a certificate. This certificate may be signed using a private certificate authority (CA), or based on a public key infrastructure linked to a generally recognized CA. The certificate and corresponding private key can be set by using the --tls-cert-file and --tls-private-key-file flags.

If your cluster uses a private certificate authority, you need a copy of that CA certificate configured into your ~/.kube/config on the client, so that you can trust the connection and be confident it was not intercepted.

Your client can present a TLS client certificate at this stage.

Once TLS is established, the HTTP request moves to the Authentication step. This is shown as step 1 in the diagram. The cluster creation script or cluster admin configures the API server to run one or more Authenticator modules. Authenticators are described in more detail in Authentication.

The input to the authentication step is the entire HTTP request; however, it typically examines the headers and/or client certificate.

Authentication modules include client certificates, password, and plain tokens, bootstrap tokens, and JSON Web Tokens (used for service accounts).

Multiple authentication modules can be specified, in which case each one is tried in sequence, until one of them succeeds.

If the request cannot be authenticated, it is rejected with HTTP status code 401. Otherwise, the user is authenticated as a specific username, and the user name is available to subsequent steps to use in their decisions. Some authenticators also provide the group memberships of the user, while other authenticators do not.

While Kubernetes uses usernames for access control decisions and in request logging, it does not have a User object nor does it store usernames or other information about users in its API.

After the request is auth

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
    "apiVersion": "abac.authorization.kubernetes.io/v1beta1",
    "kind": "Policy",
    "spec": {
        "user": "bob",
        "namespace": "projectCaribou",
        "resource": "pods",
        "readonly": true
    }
}
```

Example 2 (json):
```json
{
  "apiVersion": "authorization.k8s.io/v1beta1",
  "kind": "SubjectAccessReview",
  "spec": {
    "resourceAttributes": {
      "namespace": "projectCaribou",
      "verb": "get",
      "group": "unicorn.example.org",
      "resource": "pods"
    }
  }
}
```

---

## Runtime Class

**URL:** https://kubernetes.io/docs/concepts/containers/runtime-class/

**Contents:**
- Runtime Class
- Motivation
- Setup
  - 1. Configure the CRI implementation on nodes
    - Note:
  - 2. Create the corresponding RuntimeClass resources
    - Note:
- Usage
  - CRI Configuration
    - containerd

This page describes the RuntimeClass resource and runtime selection mechanism.

RuntimeClass is a feature for selecting the container runtime configuration. The container runtime configuration is used to run a Pod's containers.

You can set a different RuntimeClass between different Pods to provide a balance of performance versus security. For example, if part of your workload deserves a high level of information security assurance, you might choose to schedule those Pods so that they run in a container runtime that uses hardware virtualization. You'd then benefit from the extra isolation of the alternative runtime, at the expense of some additional overhead.

You can also use RuntimeClass to run different Pods with the same container runtime but with different settings.

The configurations available through RuntimeClass are Container Runtime Interface (CRI) implementation dependent. See the corresponding documentation (below) for your CRI implementation for how to configure.

The configurations have a corresponding handler name, referenced by the RuntimeClass. The handler must be a valid DNS label name.

The configurations setup in step 1 should each have an associated handler name, which identifies the configuration. For each handler, create a corresponding RuntimeClass object.

The RuntimeClass resource currently only has 2 significant fields: the RuntimeClass name (metadata.name) and the handler (handler). The object definition looks like this:

The name of a RuntimeClass object must be a valid DNS subdomain name.

Once RuntimeClasses are configured for the cluster, you can specify a runtimeClassName in the Pod spec to use it. For example:

This will instruct the kubelet to use the named RuntimeClass to run this pod. If the named RuntimeClass does not exist, or the CRI cannot run the corresponding handler, the pod will enter the Failed terminal phase. Look for a corresponding event for an error message.

If no runtimeClassName is specified, the default RuntimeHandler will be used, which is equivalent to the behavior when the RuntimeClass feature is disabled.

For more details on setting up CRI runtimes, see CRI installation.

Runtime handlers are configured through containerd's configuration at /etc/containerd/config.toml. Valid handlers are configured under the runtimes section:

See containerd's config documentation for more details:

Runtime handlers are configured through CRI-O's configuration at /etc/crio/crio.conf. Valid handlers are configured u

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# RuntimeClass is defined in the node.k8s.io API group
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  # The name the RuntimeClass will be referenced by.
  # RuntimeClass is a non-namespaced resource.
  name: myclass 
# The name of the corresponding CRI configuration
handler: myconfiguration
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mypod
spec:
  runtimeClassName: myclass
  # ...
```

Example 3 (unknown):
```unknown
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.${HANDLER_NAME}]
```

Example 4 (unknown):
```unknown
[crio.runtime.runtimes.${HANDLER_NAME}]
  runtime_path = "${PATH_TO_BINARY}"
```

---

## Dynamic Resource Allocation

**URL:** https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/#device-taints-and-tolerations

**Contents:**
- Dynamic Resource Allocation
- About DRA
  - Benefits of DRA
  - Types of DRA users
- DRA terminology
  - DeviceClass
  - ResourceClaims and ResourceClaimTemplates
    - Use cases for ResourceClaims and ResourceClaimTemplates
    - Prioritized list
  - ResourceSlice

This page describes dynamic resource allocation (DRA) in Kubernetes.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

DRA is a Kubernetes feature that lets you request and share resources among Pods. These resources are often attached devices like hardware accelerators.

With DRA, device drivers and cluster admins define device classes that are available to claim in workloads. Kubernetes allocates matching devices to specific claims and places the corresponding Pods on nodes that can access the allocated devices.

Allocating resources with DRA is a similar experience to dynamic volume provisioning, in which you use PersistentVolumeClaims to claim storage capacity from storage classes and request the claimed capacity in your Pods.

DRA provides a flexible way to categorize, request, and use devices in your cluster. Using DRA provides benefits like the following:

These benefits provide significant improvements in the device allocation workflow when compared to device plugins, which require per-container device requests, don't support device sharing, and don't support expression-based device filtering.

The workflow of using DRA to allocate devices involves the following types of users:

Device owner: responsible for devices. Device owners might be commercial vendors, the cluster operator, or another entity. To use DRA, devices must have DRA-compatible drivers that do the following:

Cluster admin: responsible for configuring clusters and nodes, attaching devices, installing drivers, and similar tasks. To use DRA, cluster admins do the following:

Workload operator: responsible for deploying and managing workloads in the cluster. To use DRA to allocate devices to Pods, workload operators do the following:

DRA uses the following Kubernetes API kinds to provide the core allocation functionality. All of these API kinds are included in the resource.k8s.io/v1 API group.

A DeviceClass lets cluster admins or device drivers define categories of devices in the cluster. DeviceClasses tell operators what devices they can request and how they can request those devices. You can use common expression language (CEL) to select devices based on specific attributes. A ResourceClaim that references the DeviceClass can then request specific configurations within the DeviceClass.

To create a DeviceClass, see Set Up DRA in a Cluster.

A ResourceClaim defines the resources 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: prioritized-list-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        firstAvailable:
        - name: large-black
          deviceClassName: resource.example.com
          selectors:
          - cel:
              expression: |-
                device.attributes["resource-driver.example.com"].color == "black" &&
                device.attributes["resource-driver.example.com"].size == "large"                
        - name: small-white
          deviceClassName: resource.example.com
   
...
```

Example 2 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata:
  name: cat-slice
spec:
  driver: "resource-driver.example.com"
  pool:
    generation: 1
    name: "black-cat-pool"
    resourceSliceCount: 1
  # The allNodes field defines whether any node in the cluster can access the device.
  allNodes: true
  devices:
  - name: "large-black-cat"
    attributes:
      color:
        string: "black"
      size:
        string: "large"
      cat:
        bool: true
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-cats
spec:
  nodeSelector:
    kubernetes.io/hostname: name-of-the-intended-node
  ...
```

Example 4 (yaml):
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: large-black-cat-claim-template
spec:
  spec:
    devices:
      requests:
      - name: req-0
        exactly:
          deviceClassName: resource.example.com
          allocationMode: All
          adminAccess: true
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#api-extensions

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Mixed Version Proxy

**URL:** https://kubernetes.io/docs/concepts/architecture/mixed-version-proxy/

**Contents:**
- Mixed Version Proxy
- Enabling the Mixed Version Proxy
  - Proxy transport and authentication between API servers
  - Configuration for peer API server connectivity
- Mixed version proxying
  - How it works under the hood
- Feedback

Kubernetes 1.34 includes an alpha feature that lets an API Server proxy a resource requests to other peer API servers. This is useful when there are multiple API servers running different versions of Kubernetes in one cluster (for example, during a long-lived rollout to a new release of Kubernetes).

This enables cluster administrators to configure highly available clusters that can be upgraded more safely, by directing resource requests (made during the upgrade) to the correct kube-apiserver. That proxying prevents users from seeing unexpected 404 Not Found errors that stem from the upgrade process.

This mechanism is called the Mixed Version Proxy.

Ensure that UnknownVersionInteroperabilityProxy feature gate is enabled when you start the API Server:

The source kube-apiserver reuses the existing APIserver client authentication flags --proxy-client-cert-file and --proxy-client-key-file to present its identity that will be verified by its peer (the destination kube-apiserver). The destination API server verifies that peer connection based on the configuration you specify using the --requestheader-client-ca-file command line argument.

To authenticate the destination server's serving certs, you must configure a certificate authority bundle by specifying the --peer-ca-file command line argument to the source API server.

To set the network location of a kube-apiserver that peers will use to proxy requests, use the --peer-advertise-ip and --peer-advertise-port command line arguments to kube-apiserver or specify these fields in the API server configuration file. If these flags are unspecified, peers will use the value from either --advertise-address or --bind-address command line argument to the kube-apiserver. If those too, are unset, the host's default interface is used.

When you enable mixed version proxying, the aggregation layer loads a special filter that does the following:

When an API Server receives a resource request, it first checks which API servers can serve the requested resource. This check happens using the internal StorageVersion API.

If the resource is known to the API server that received the request (for example, GET /api/v1/pods/some-pod), the request is handled locally.

If there is no internal StorageVersion object found for the requested resource (for example, GET /my-api/v1/my-resource) and the configured APIService specifies proxying to an extension API server, that proxying happens following the usual flow for extension APIs.

If

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kube-apiserver \
--feature-gates=UnknownVersionInteroperabilityProxy=true \
# required command line arguments for this feature
--peer-ca-file=<path to kube-apiserver CA cert>
--proxy-client-cert-file=<path to aggregator proxy cert>,
--proxy-client-key-file=<path to aggregator proxy key>,
--requestheader-client-ca-file=<path to aggregator CA cert>,
# requestheader-allowed-names can be set to blank to allow any Common Name
--requestheader-allowed-names=<valid Common Names to verify proxy client cert against>,

# optional flags for this feature
--peer-advertise-ip=`IP of this kube-apiserver that 
...
```

---

## Pod Lifecycle

**URL:** https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination

**Contents:**
- Pod Lifecycle
- Pod lifetime
  - Pods and fault recovery
  - Associated lifetimes
    - Figure 1.
- Pod phase
    - Note:
- Container states
  - Waiting
  - Running

This page describes the lifecycle of a Pod. Pods follow a defined lifecycle, starting in the Pending phase, moving through Running if at least one of its primary containers starts OK, and then through either the Succeeded or Failed phases depending on whether any container in the Pod terminated in failure.

Like individual application containers, Pods are considered to be relatively ephemeral (rather than durable) entities. Pods are created, assigned a unique ID (UID), and scheduled to run on nodes where they remain until termination (according to restart policy) or deletion. If a Node dies, the Pods running on (or scheduled to run on) that node are marked for deletion. The control plane marks the Pods for removal after a timeout period.

Whilst a Pod is running, the kubelet is able to restart containers to handle some kind of faults. Within a Pod, Kubernetes tracks different container states and determines what action to take to make the Pod healthy again.

In the Kubernetes API, Pods have both a specification and an actual status. The status for a Pod object consists of a set of Pod conditions. You can also inject custom readiness information into the condition data for a Pod, if that is useful to your application.

Pods are only scheduled once in their lifetime; assigning a Pod to a specific node is called binding, and the process of selecting which node to use is called scheduling. Once a Pod has been scheduled and is bound to a node, Kubernetes tries to run that Pod on the node. The Pod runs on that node until it stops, or until the Pod is terminated; if Kubernetes isn't able to start the Pod on the selected node (for example, if the node crashes before the Pod starts), then that particular Pod never starts.

You can use Pod Scheduling Readiness to delay scheduling for a Pod until all its scheduling gates are removed. For example, you might want to define a set of Pods but only trigger scheduling once all the Pods have been created.

If one of the containers in the Pod fails, then Kubernetes may try to restart that specific container. Read How Pods handle problems with containers to learn more.

Pods can however fail in a way that the cluster cannot recover from, and in that case Kubernetes does not attempt to heal the Pod further; instead, Kubernetes deletes the Pod and relies on other components to provide automatic healing.

If a Pod is scheduled to a node and that node then fails, the Pod is treated as unhealthy and Kubernetes eventually deletes t

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
NAMESPACE               NAME               READY   STATUS             RESTARTS   AGE
  alessandras-namespace   alessandras-pod    0/1     CrashLoopBackOff   200        2d9h
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: on-failure-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: try-once-container    # This container will run only once because the restartPolicy is Never.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Only running once" && sleep 10 && exit 1']
    restartPolicy: Never     
  - name: on-failure-container  # This container will be restarted on failure.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Keep restarting" && sleep 1800 && exit 1']
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fail-pod-if-init-fails
spec:
  restartPolicy: Always
  initContainers:
  - name: init-once      # This init container will only try once. If it fails, the pod will fail.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'echo "Failing initialization" && sleep 10 && exit 1']
    restartPolicy: Never
  containers:
  - name: main-container # This container will always be restarted once initialization succeeds.
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 1800 && exit 0']
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-on-exit-codes
spec:
  restartPolicy: Never
  containers:
  - name: restart-on-exit-codes
    image: docker.io/library/busybox:1.28
    command: ['sh', '-c', 'sleep 60 && exit 0']
    restartPolicy: Never     # Container restart policy must be specified if rules are specified
    restartPolicyRules:      # Only restart the container if it exits with code 42
    - action: Restart
      exitCodes:
        operator: In
        values: [42]
```

---

## Application Security Checklist

**URL:** https://kubernetes.io/docs/concepts/security/application-security-checklist/

**Contents:**
- Application Security Checklist
    - Caution:
- Base security hardening
  - Application design
  - Service account
  - Pod-level securityContext recommendations
  - Container-level securityContext recommendations
  - Role Based Access Control (RBAC)
  - Image security
  - Network policies

This checklist aims to provide basic guidelines on securing applications running in Kubernetes from a developer's perspective. This list is not meant to be exhaustive and is intended to evolve over time.

On how to read and use this document:

The following checklist provides base security hardening recommendations that would apply to most applications deploying to Kubernetes.

The create, update and delete verbs should be permitted judiciously. The patch verb if allowed on a Namespace can allow users to update labels on the namespace or deployments which can increase the attack surface.

For sensitive workloads, consider providing a recommended ValidatingAdmissionPolicy that further restricts the permitted write actions.

Make sure that your cluster provides and enforces NetworkPolicy. If you are writing an application that users will deploy to different clusters, consider whether you can assume that NetworkPolicy is available and enforced.

This section of this guide covers some advanced security hardening points which might be valuable based on different Kubernetes environment setup.

Configure Security Context for the pod-container.

Some containers may require a different isolation level from what is provided by the default runtime of the cluster. runtimeClassName can be used in a podspec to define a different runtime class.

For sensitive workloads consider using kernel emulation tools like gVisor, or virtualized isolation using a mechanism such as kata-containers.

In high trust environments, consider using confidential virtual machines to improve cluster security even further.

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Labels and Selectors

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/labels

**Contents:**
- Labels and Selectors
- Motivation
- Syntax and character set
- Label selectors
    - Note:
    - Caution:
  - Equality-based requirement
  - Set-based requirement
- API
  - LIST and WATCH filtering

Labels are key/value pairs that are attached to objects such as Pods. Labels are intended to be used to specify identifying attributes of objects that are meaningful and relevant to users, but do not directly imply semantics to the core system. Labels can be used to organize and to select subsets of objects. Labels can be attached to objects at creation time and subsequently added and modified at any time. Each object can have a set of key/value labels defined. Each Key must be unique for a given object.

Labels allow for efficient queries and watches and are ideal for use in UIs and CLIs. Non-identifying information should be recorded using annotations.

Labels enable users to map their own organizational structures onto system objects in a loosely coupled fashion, without requiring clients to store these mappings.

Service deployments and batch processing pipelines are often multi-dimensional entities (e.g., multiple partitions or deployments, multiple release tracks, multiple tiers, multiple micro-services per tier). Management often requires cross-cutting operations, which breaks encapsulation of strictly hierarchical representations, especially rigid hierarchies determined by the infrastructure rather than by users.

These are examples of commonly used labels; you are free to develop your own conventions. Keep in mind that label Key must be unique for a given object.

Labels are key/value pairs. Valid label keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, followed by a slash (/).

If the prefix is omitted, the label Key is presumed to be private to the user. Automated system components (e.g. kube-scheduler, kube-controller-manager, kube-apiserver, kubectl, or other third-party automation) which add labels to end-user objects must specify a prefix.

The kubernetes.io/ and k8s.io/ prefixes are reserved for Kubernetes core components.

For example, here's a manifest for a Pod that has two labels environment: production and app: nginx:

Unlike names and UIDs, labels do not provide uniqueness. In general, we expect many objects to carry the same label(s).

Via a label sel

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "labels": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: label-demo
  labels:
    environment: production
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 3 (unknown):
```unknown
environment = production
tier != frontend
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  containers:
    - name: cuda-test
      image: "registry.k8s.io/cuda-vector-add:v0.1"
      resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia-tesla-p100
```

---

## Images

**URL:** https://kubernetes.io/docs/concepts/containers/images/#ensureimagepullcredentialverification

**Contents:**
- Images
    - Note:
- Image names
- Updating images
  - Image pull policy
    - Note:
    - Default image pull policy
    - Note:
    - Required image pull
  - ImagePullBackOff

A container image represents binary data that encapsulates an application and all its software dependencies. Container images are executable software bundles that can run standalone and that make very well-defined assumptions about their runtime environment.

You typically create a container image of your application and push it to a registry before referring to it in a Pod.

This page provides an outline of the container image concept.

Container images are usually given a name such as pause, example/mycontainer, or kube-apiserver. Images can also include a registry hostname; for example: fictional.registry.example/imagename, and possibly a port number as well; for example: fictional.registry.example:10443/imagename.

If you don't specify a registry hostname, Kubernetes assumes that you mean the Docker public registry. You can change this behavior by setting a default image registry in the container runtime configuration.

After the image name part you can add a tag or digest (in the same way you would when using with commands like docker or podman). Tags let you identify different versions of the same series of images. Digests are a unique identifier for a specific version of an image. Digests are hashes of the image's content, and are immutable. Tags can be moved to point to different images, but digests are fixed.

Image tags consist of lowercase and uppercase letters, digits, underscores (_), periods (.), and dashes (-). A tag can be up to 128 characters long, and must conform to the following regex pattern: [a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}. You can read more about it and find the validation regex in the OCI Distribution Specification. If you don't specify a tag, Kubernetes assumes you mean the tag latest.

Image digests consists of a hash algorithm (such as sha256) and a hash value. For example: sha256:1ff6c18fbef2045af6b9c16bf034cc421a29027b800e4f9b68ae9b1cb3e9ae07. You can find more information about the digest format in the OCI Image Specification.

Some image name examples that Kubernetes can use are:

When you first create a Deployment, StatefulSet, Pod, or other object that includes a PodTemplate, and a pull policy was not explicitly specified, then by default the pull policy of all containers in that Pod will be set to IfNotPresent. This policy causes the kubelet to skip pulling an image if it already exists.

The imagePullPolicy for a container and the tag of the image both affect when the kubelet attempts to pull (download) the specified im

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
    "auths": {
        "my-registry.example/images": { "auth": "…" },
        "*.my-registry.example/images": { "auth": "…" }
    }
}
```

Example 2 (json):
```json
{
    "auths": {
        "my-registry.example/images": {
            "auth": "…"
        },
        "my-registry.example/images/subpath": {
            "auth": "…"
        }
    }
}
```

Example 3 (shell):
```shell
kubectl create secret docker-registry <name> \
  --docker-server=<docker-registry-server> \
  --docker-username=<docker-user> \
  --docker-password=<docker-password> \
  --docker-email=<docker-email>
```

Example 4 (shell):
```shell
cat <<EOF > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: foo
  namespace: awesomeapps
spec:
  containers:
    - name: foo
      image: janedoe/awesomeapp:v1
  imagePullSecrets:
    - name: myregistrykey
EOF

cat <<EOF >> ./kustomization.yaml
resources:
- pod.yaml
EOF
```

---

## Labels and Selectors

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#using-labels-effectively

**Contents:**
- Labels and Selectors
- Motivation
- Syntax and character set
- Label selectors
    - Note:
    - Caution:
  - Equality-based requirement
  - Set-based requirement
- API
  - LIST and WATCH filtering

Labels are key/value pairs that are attached to objects such as Pods. Labels are intended to be used to specify identifying attributes of objects that are meaningful and relevant to users, but do not directly imply semantics to the core system. Labels can be used to organize and to select subsets of objects. Labels can be attached to objects at creation time and subsequently added and modified at any time. Each object can have a set of key/value labels defined. Each Key must be unique for a given object.

Labels allow for efficient queries and watches and are ideal for use in UIs and CLIs. Non-identifying information should be recorded using annotations.

Labels enable users to map their own organizational structures onto system objects in a loosely coupled fashion, without requiring clients to store these mappings.

Service deployments and batch processing pipelines are often multi-dimensional entities (e.g., multiple partitions or deployments, multiple release tracks, multiple tiers, multiple micro-services per tier). Management often requires cross-cutting operations, which breaks encapsulation of strictly hierarchical representations, especially rigid hierarchies determined by the infrastructure rather than by users.

These are examples of commonly used labels; you are free to develop your own conventions. Keep in mind that label Key must be unique for a given object.

Labels are key/value pairs. Valid label keys have two segments: an optional prefix and name, separated by a slash (/). The name segment is required and must be 63 characters or less, beginning and ending with an alphanumeric character ([a-z0-9A-Z]) with dashes (-), underscores (_), dots (.), and alphanumerics between. The prefix is optional. If specified, the prefix must be a DNS subdomain: a series of DNS labels separated by dots (.), not longer than 253 characters in total, followed by a slash (/).

If the prefix is omitted, the label Key is presumed to be private to the user. Automated system components (e.g. kube-scheduler, kube-controller-manager, kube-apiserver, kubectl, or other third-party automation) which add labels to end-user objects must specify a prefix.

The kubernetes.io/ and k8s.io/ prefixes are reserved for Kubernetes core components.

For example, here's a manifest for a Pod that has two labels environment: production and app: nginx:

Unlike names and UIDs, labels do not provide uniqueness. In general, we expect many objects to carry the same label(s).

Via a label sel

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
"metadata": {
  "labels": {
    "key1" : "value1",
    "key2" : "value2"
  }
}
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: label-demo
  labels:
    environment: production
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

Example 3 (unknown):
```unknown
environment = production
tier != frontend
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  containers:
    - name: cuda-test
      image: "registry.k8s.io/cuda-vector-add:v0.1"
      resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia-tesla-p100
```

---

## StatefulSets

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#rolling-updates

**Contents:**
- StatefulSets
- Using StatefulSets
- Limitations
- Components
    - Note:
  - Pod Selector
  - Volume Claim Templates
  - Minimum ready seconds
- Pod Identity
  - Ordinal Index

StatefulSet is the workload API object used to manage stateful applications.

Manages the deployment and scaling of a set of Pods, and provides guarantees about the ordering and uniqueness of these Pods.

Like a Deployment, a StatefulSet manages Pods that are based on an identical container spec. Unlike a Deployment, a StatefulSet maintains a sticky identity for each of its Pods. These pods are created from the same spec, but are not interchangeable: each has a persistent identifier that it maintains across any rescheduling.

If you want to use storage volumes to provide persistence for your workload, you can use a StatefulSet as part of the solution. Although individual Pods in a StatefulSet are susceptible to failure, the persistent Pod identifiers make it easier to match existing volumes to the new Pods that replace any that have failed.

StatefulSets are valuable for applications that require one or more of the following.

In the above, stable is synonymous with persistence across Pod (re)scheduling. If an application doesn't require any stable identifiers or ordered deployment, deletion, or scaling, you should deploy your application using a workload object that provides a set of stateless replicas. Deployment or ReplicaSet may be better suited to your stateless needs.

The example below demonstrates the components of a StatefulSet.

In the above example:

The name of a StatefulSet object must be a valid DNS label.

You must set the .spec.selector field of a StatefulSet to match the labels of its .spec.template.metadata.labels. Failing to specify a matching Pod Selector will result in a validation error during StatefulSet creation.

You can set the .spec.volumeClaimTemplates field to create a PersistentVolumeClaim. This will provide stable storage to the StatefulSet if either

.spec.minReadySeconds is an optional field that specifies the minimum number of seconds for which a newly created Pod should be running and ready without any of its containers crashing, for it to be considered available. This is used to check progression of a rollout when using a Rolling Update strategy. This field defaults to 0 (the Pod will be considered available as soon as it is ready). To learn more about when a Pod is considered ready, see Container Probes.

StatefulSet Pods have a unique identity that consists of an ordinal, a stable network identity, and stable storage. The identity sticks to the Pod, regardless of which node it's (re)scheduled on.

For a StatefulSet wit

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: nginx # has to match .spec.template.metadata.labels
  serviceName: "nginx"
  replicas: 3 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: nginx # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - n
...
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: webapp
spec:
  revisionHistoryLimit: 5  # Keep last 5 revisions
  # ... other spec fields ...
```

Example 3 (bash):
```bash
# View revision history
kubectl rollout history statefulset/webapp

# Rollback to a specific revision
kubectl rollout undo statefulset/webapp --to-revision=3
```

Example 4 (bash):
```bash
# List all revisions for the StatefulSet
kubectl get controllerrevisions -l app.kubernetes.io/name=webapp

# View detailed configuration of a specific revision
kubectl get controllerrevision/webapp-3 -o yaml
```

---

## Persistent Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/persistent-volumes/

**Contents:**
- Persistent Volumes
- Introduction
- Lifecycle of a volume and claim
  - Provisioning
    - Static
    - Dynamic
  - Binding
  - Using
  - Storage Object in Use Protection
    - Note:

This document describes persistent volumes in Kubernetes. Familiarity with volumes, StorageClasses and VolumeAttributesClasses is suggested.

Managing storage is a distinct problem from managing compute instances. The PersistentVolume subsystem provides an API for users and administrators that abstracts details of how storage is provided from how it is consumed. To do this, we introduce two new API resources: PersistentVolume and PersistentVolumeClaim.

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany, ReadWriteMany, or ReadWriteOncePod, see AccessModes).

While PersistentVolumeClaims allow a user to consume abstract storage resources, it is common that users need PersistentVolumes with varying properties, such as performance, for different problems. Cluster administrators need to be able to offer a variety of PersistentVolumes that differ in more ways than size and access modes, without exposing users to the details of how those volumes are implemented. For these needs, there is the StorageClass resource.

See the detailed walkthrough with working examples.

PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource. The interaction between PVs and PVCs follows this lifecycle:

There are two ways PVs may be provisioned: statically or dynamically.

A cluster administrator creates a number of PVs. They carry the details of the real storage, which is available for use by cluster users. They exist in the Kubernetes API and are available for consumption.

When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC. This provisioning is based on StorageClasses: th

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl describe pvc hostpath
Name:          hostpath
Namespace:     default
StorageClass:  example-hostpath
Status:        Terminating
Volume:
Labels:        <none>
Annotations:   volume.beta.kubernetes.io/storage-class=example-hostpath
               volume.beta.kubernetes.io/storage-provisioner=example.com/hostpath
Finalizers:    [kubernetes.io/pvc-protection]
...
```

Example 2 (shell):
```shell
kubectl describe pv task-pv-volume
Name:            task-pv-volume
Labels:          type=local
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Terminating
Claim:
Reclaim Policy:  Delete
Access Modes:    RWO
Capacity:        1Gi
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/data
    HostPathType:
Events:            <none>
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-recycler
  namespace: default
spec:
  restartPolicy: Never
  volumes:
  - name: vol
    hostPath:
      path: /any/path/it/will/be/replaced
  containers:
  - name: pv-recycler
    image: "registry.k8s.io/busybox"
    command: ["/bin/sh", "-c", "test -e /scrub && rm -rf /scrub/..?* /scrub/.[!.]* /scrub/*  && test -z \"$(ls -A /scrub)\" || exit 1"]
    volumeMounts:
    - name: vol
      mountPath: /scrub
```

Example 4 (shell):
```shell
kubectl describe pv pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Name:            pvc-74a498d6-3929-47e8-8c02-078c1ece4d78
Labels:          <none>
Annotations:     kubernetes.io/createdby: vsphere-volume-dynamic-provisioner
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/vsphere-volume
Finalizers:      [kubernetes.io/pv-protection kubernetes.io/pv-controller]
StorageClass:    vcp-sc
Status:          Bound
Claim:           default/vcp-pvc-1
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:   
...
```

---

## IPv4/IPv6 dual-stack

**URL:** https://kubernetes.io/docs/concepts/services-networking/dual-stack/

**Contents:**
- IPv4/IPv6 dual-stack
- Supported Features
- Prerequisites
- Configure IPv4/IPv6 dual-stack
    - Note:
- Services
    - Note:
  - Dual-stack Service configuration scenarios
    - Dual-stack options on new Services
    - Dual-stack defaults on existing Services

IPv4/IPv6 dual-stack networking enables the allocation of both IPv4 and IPv6 addresses to Pods and Services.

IPv4/IPv6 dual-stack networking is enabled by default for your Kubernetes cluster starting in 1.21, allowing the simultaneous assignment of both IPv4 and IPv6 addresses.

IPv4/IPv6 dual-stack on your Kubernetes cluster provides the following features:

The following prerequisites are needed in order to utilize IPv4/IPv6 dual-stack Kubernetes clusters:

Kubernetes 1.20 or later

For information about using dual-stack services with earlier Kubernetes versions, refer to the documentation for that version of Kubernetes.

Provider support for dual-stack networking (Cloud provider or otherwise must be able to provide Kubernetes nodes with routable IPv4/IPv6 network interfaces)

A network plugin that supports dual-stack networking.

To configure IPv4/IPv6 dual-stack, set dual-stack cluster network assignments:

An example of an IPv4 CIDR: 10.244.0.0/16 (though you would supply your own address range)

An example of an IPv6 CIDR: fdXY:IJKL:MNOP:15::/64 (this shows the format but is not a valid address - see RFC 4193)

You can create Services which can use IPv4, IPv6, or both.

The address family of a Service defaults to the address family of the first service cluster IP range (configured via the --service-cluster-ip-range flag to the kube-apiserver).

When you define a Service you can optionally configure it as dual stack. To specify the behavior you want, you set the .spec.ipFamilyPolicy field to one of the following values:

If you would like to define which IP family to use for single stack or define the order of IP families for dual-stack, you can choose the address families by setting an optional field, .spec.ipFamilies, on the Service.

You can set .spec.ipFamilies to any of the following array values:

The first family you list is used for the legacy .spec.clusterIP field.

These examples demonstrate the behavior of various dual-stack Service configuration scenarios.

This Service specification does not explicitly define .spec.ipFamilyPolicy. When you create this Service, Kubernetes assigns a cluster IP for the Service from the first configured service-cluster-ip-range and sets the .spec.ipFamilyPolicy to SingleStack. (Services without selectors and headless Services with selectors will behave in this same way.)

This Service specification explicitly defines PreferDualStack in .spec.ipFamilyPolicy. When you create this Service on a dual-stack cluste

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  ipFamilyPolicy: PreferDualStack
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
  - IPv6
  - IPv4
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

---

## Policies

**URL:** https://kubernetes.io/docs/concepts/policy/#third-party-content-disclaimer

**Contents:**
- Policies
- Apply policies using API objects
- Apply policies using admission controllers
- Apply policies using ValidatingAdmissionPolicy
- Apply policies using dynamic admission control
  - Implementations
- Apply policies using Kubelet configurations
- Feedback

Kubernetes policies are configurations that manage other configurations or runtime behaviors. Kubernetes offers various forms of policies, described below:

Some API objects act as policies. Here are some examples:

An admission controller runs in the API server and can validate or mutate API requests. Some admission controllers act to apply policies. For example, the AlwaysPullImages admission controller modifies a new Pod to set the image pull policy to Always.

Kubernetes has several built-in admission controllers that are configurable via the API server --enable-admission-plugins flag.

Details on admission controllers, with the complete list of available admission controllers, are documented in a dedicated section:

Validating admission policies allow configurable validation checks to be executed in the API server using the Common Expression Language (CEL). For example, a ValidatingAdmissionPolicy can be used to disallow use of the latest image tag.

A ValidatingAdmissionPolicy operates on an API request and can be used to block, audit, and warn users about non-compliant configurations.

Details on the ValidatingAdmissionPolicy API, with examples, are documented in a dedicated section:

Dynamic admission controllers (or admission webhooks) run outside the API server as separate applications that register to receive webhooks requests to perform validation or mutation of API requests.

Dynamic admission controllers can be used to apply policies on API requests and trigger other policy-based workflows. A dynamic admission controller can perform complex checks including those that require retrieval of other cluster resources and external data. For example, an image verification check can lookup data from OCI registries to validate the container image signatures and attestations.

Details on dynamic admission control are documented in a dedicated section:

Dynamic Admission Controllers that act as flexible policy engines are being developed in the Kubernetes ecosystem, such as:

Kubernetes allows configuring the Kubelet on each worker node. Some Kubelet configurations act as policies:

Items on this page refer to third party products or projects that provide functionality required by Kubernetes. The Kubernetes project authors aren't responsible for those third-party products or projects. See the CNCF website guidelines for more details.

You should read the content guide before proposing a change that adds an extra third-party link.

Was this page helpful?

*[Content truncated]*

---

## Workload Management

**URL:** https://kubernetes.io/docs/concepts/workloads/controllers/

**Contents:**
- Workload Management
- Feedback

Kubernetes provides several built-in APIs for declarative management of your workloads and the components of those workloads.

Ultimately, your applications run as containers inside Pods; however, managing individual Pods would be a lot of effort. For example, if a Pod fails, you probably want to run a new Pod to replace it. Kubernetes can do that for you.

You use the Kubernetes API to create a workload object that represents a higher abstraction level than a Pod, and then the Kubernetes control plane automatically manages Pod objects on your behalf, based on the specification for the workload object you defined.

The built-in APIs for managing workloads are:

Deployment (and, indirectly, ReplicaSet), the most common way to run an application on your cluster. Deployment is a good fit for managing a stateless application workload on your cluster, where any Pod in the Deployment is interchangeable and can be replaced if needed. (Deployments are a replacement for the legacy ReplicationController API).

A StatefulSet lets you manage one or more Pods – all running the same application code – where the Pods rely on having a distinct identity. This is different from a Deployment where the Pods are expected to be interchangeable. The most common use for a StatefulSet is to be able to make a link between its Pods and their persistent storage. For example, you can run a StatefulSet that associates each Pod with a PersistentVolume. If one of the Pods in the StatefulSet fails, Kubernetes makes a replacement Pod that is connected to the same PersistentVolume.

A DaemonSet defines Pods that provide facilities that are local to a specific node; for example, a driver that lets containers on that node access a storage system. You use a DaemonSet when the driver, or other node-level service, has to run on the node where it's useful. Each Pod in a DaemonSet performs a role similar to a system daemon on a classic Unix / POSIX server. A DaemonSet might be fundamental to the operation of your cluster, such as a plugin to let that node access cluster networking, it might help you to manage the node, or it could provide less essential facilities that enhance the container platform you are running. You can run DaemonSets (and their pods) across every node in your cluster, or across just a subset (for example, only install the GPU accelerator driver on nodes that have a GPU installed).

You can use a Job and / or a CronJob to define tasks that run to completion and then stop. A Jo

*[Content truncated]*

---

## Cluster Architecture

**URL:** https://kubernetes.io/docs/concepts/architecture/#kube-apiserver

**Contents:**
- Cluster Architecture
- Control plane components
  - kube-apiserver
  - etcd
  - kube-scheduler
  - kube-controller-manager
  - cloud-controller-manager
- Node components
  - kubelet
  - kube-proxy (optional)

A Kubernetes cluster consists of a control plane plus a set of worker machines, called nodes, that run containerized applications. Every cluster needs at least one worker node in order to run Pods.

The worker node(s) host the Pods that are the components of the application workload. The control plane manages the worker nodes and the Pods in the cluster. In production environments, the control plane usually runs across multiple computers and a cluster usually runs multiple nodes, providing fault-tolerance and high availability.

This document outlines the various components you need to have for a complete and working Kubernetes cluster.

Figure 1. Kubernetes cluster components.

The diagram in Figure 1 presents an example reference architecture for a Kubernetes cluster. The actual distribution of components can vary based on specific cluster setups and requirements.

In the diagram, each node runs the kube-proxy component. You need a network proxy component on each node to ensure that the Service API and associated behaviors are available on your cluster network. However, some network plugins provide their own, third party implementation of proxying. When you use that kind of network plugin, the node does not need to run kube-proxy.

The control plane's components make global decisions about the cluster (for example, scheduling), as well as detecting and responding to cluster events (for example, starting up a new pod when a Deployment's replicas field is unsatisfied).

Control plane components can be run on any machine in the cluster. However, for simplicity, setup scripts typically start all control plane components on the same machine, and do not run user containers on this machine. See Creating Highly Available clusters with kubeadm for an example control plane setup that runs across multiple machines.

The API server is a component of the Kubernetes control plane that exposes the Kubernetes API. The API server is the front end for the Kubernetes control plane.

The main implementation of a Kubernetes API server is kube-apiserver. kube-apiserver is designed to scale horizontally—that is, it scales by deploying more instances. You can run several instances of kube-apiserver and balance traffic between those instances.

Consistent and highly-available key value store used as Kubernetes' backing store for all cluster data.

If your Kubernetes cluster uses etcd as its backing store, make sure you have a back up plan for the data.

You can find in-depth inf

*[Content truncated]*

---

## Pod Security Admission

**URL:** https://kubernetes.io/docs/concepts/security/pod-security-admission/

**Contents:**
- Pod Security Admission
  - Built-in Pod Security admission enforcement
- Pod Security levels
- Pod Security Admission labels for namespaces
- Workload resources and Pod templates
- Exemptions
    - Caution:
- Metrics
- What's next
- Feedback

The Kubernetes Pod Security Standards define different isolation levels for Pods. These standards let you define how you want to restrict the behavior of pods in a clear, consistent fashion.

Kubernetes offers a built-in Pod Security admission controller to enforce the Pod Security Standards. Pod security restrictions are applied at the namespace level when pods are created.

This page is part of the documentation for Kubernetes v1.34. If you are running a different version of Kubernetes, consult the documentation for that release.

Pod Security admission places requirements on a Pod's Security Context and other related fields according to the three levels defined by the Pod Security Standards: privileged, baseline, and restricted. Refer to the Pod Security Standards page for an in-depth look at those requirements.

Once the feature is enabled or the webhook is installed, you can configure namespaces to define the admission control mode you want to use for pod security in each namespace. Kubernetes defines a set of labels that you can set to define which of the predefined Pod Security Standard levels you want to use for a namespace. The label you select defines what action the control plane takes if a potential violation is detected:

A namespace can configure any or all modes, or even set a different level for different modes.

For each mode, there are two labels that determine the policy used:

Check out Enforce Pod Security Standards with Namespace Labels to see example usage.

Pods are often created indirectly, by creating a workload object such as a Deployment or Job. The workload object defines a Pod template and a controller for the workload resource creates Pods based on that template. To help catch violations early, both the audit and warning modes are applied to the workload resources. However, enforce mode is not applied to workload resources, only to the resulting pod objects.

You can define exemptions from pod security enforcement in order to allow the creation of pods that would have otherwise been prohibited due to the policy associated with a given namespace. Exemptions can be statically configured in the Admission Controller configuration.

Exemptions must be explicitly enumerated. Requests meeting exemption criteria are ignored by the Admission Controller (all enforce, audit and warn behaviors are skipped). Exemption dimensions include:

Updates to the following pod fields are exempt from policy checks, meaning that if a pod update reque

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# The per-mode level label indicates which policy level to apply for the mode.
#
# MODE must be one of `enforce`, `audit`, or `warn`.
# LEVEL must be one of `privileged`, `baseline`, or `restricted`.
pod-security.kubernetes.io/<MODE>: <LEVEL>

# Optional: per-mode version label that can be used to pin the policy to the
# version that shipped with a given Kubernetes minor version (for example v1.34).
#
# MODE must be one of `enforce`, `audit`, or `warn`.
# VERSION must be a valid Kubernetes minor version, or `latest`.
pod-security.kubernetes.io/<MODE>-version: <VERSION>
```

---

## Cloud Native Security and Kubernetes

**URL:** https://kubernetes.io/docs/concepts/security/cloud-native-security/

**Contents:**
- Cloud Native Security and Kubernetes
- Cloud native information security
- Develop lifecycle phase
- Distribute lifecycle phase
- Deploy lifecycle phase
- Runtime lifecycle phase
  - Runtime protection: access
  - Runtime protection: compute
  - Runtime protection: storage
  - Networking and security

Kubernetes is based on a cloud-native architecture, and draws on advice from the CNCF about good practice for cloud native information security.

Read on through this page for an overview of how Kubernetes is designed to help you deploy a secure cloud native platform.

The CNCF white paper on cloud native security defines security controls and practices that are appropriate to different lifecycle phases.

To achieve this, you can:

To achieve this, you can:

Ensure appropriate restrictions on what can be deployed, who can deploy it, and where it can be deployed to. You can enforce measures from the distribute phase, such as verifying the cryptographic identity of container image artifacts.

You can deploy different applications and cluster components into different namespaces. Containers themselves, and namespaces, both provide isolation mechanisms that are relevant to information security.

When you deploy Kubernetes, you also set the foundation for your applications' runtime environment: a Kubernetes cluster (or multiple clusters). That IT infrastructure must provide the security guarantees that higher layers expect.

The Runtime phase comprises three critical areas: access, compute, and storage.

The Kubernetes API is what makes your cluster work. Protecting this API is key to providing effective cluster security.

Other pages in the Kubernetes documentation have more detail about how to set up specific aspects of access control. The security checklist has a set of suggested basic checks for your cluster.

Beyond that, securing your cluster means implementing effective authentication and authorization for API access. Use ServiceAccounts to provide and manage security identities for workloads and cluster components.

Kubernetes uses TLS to protect API traffic; make sure to deploy the cluster using TLS (including for traffic between nodes and the control plane), and protect the encryption keys. If you use Kubernetes' own API for CertificateSigningRequests, pay special attention to restricting misuse there.

Containers provide two things: isolation between different applications, and a mechanism to combine those isolated applications to run on the same host computer. Those two aspects, isolation and aggregation, mean that runtime security involves identifying trade-offs and finding an appropriate balance.

Kubernetes relies on a container runtime to actually set up and run containers. The Kubernetes project does not recommend a specific container runtime a

*[Content truncated]*

---

## API Priority and Fairness

**URL:** https://kubernetes.io/docs/concepts/cluster-administration/flow-control/#maintenance-of-the-mandatory-and-suggested-configuration-objects

**Contents:**
- API Priority and Fairness
    - Caution:
- Enabling/Disabling API Priority and Fairness
- Recursive server scenarios
- Concepts
  - Priority Levels
  - Seats Occupied by a Request
  - Execution time tweaks for watch requests
  - Queuing
  - Exempt requests

Controlling the behavior of the Kubernetes API server in an overload situation is a key task for cluster administrators. The kube-apiserver has some controls available (i.e. the --max-requests-inflight and --max-mutating-requests-inflight command-line flags) to limit the amount of outstanding work that will be accepted, preventing a flood of inbound requests from overloading and potentially crashing the API server, but these flags are not enough to ensure that the most important requests get through in a period of high traffic.

The API Priority and Fairness feature (APF) is an alternative that improves upon aforementioned max-inflight limitations. APF classifies and isolates requests in a more fine-grained way. It also introduces a limited amount of queuing, so that no requests are rejected in cases of very brief bursts. Requests are dispatched from queues using a fair queuing technique so that, for example, a poorly-behaved controller need not starve others (even at the same priority level).

This feature is designed to work well with standard controllers, which use informers and react to failures of API requests with exponential back-off, and other clients that also work this way.

The API Priority and Fairness feature is controlled by a command-line flag and is enabled by default. See Options for a general explanation of the available kube-apiserver command-line options and how to enable and disable them. The name of the command-line option for APF is "--enable-priority-and-fairness". This feature also involves an API Group with: (a) a stable v1 version, introduced in 1.29, and enabled by default (b) a v1beta3 version, enabled by default, and deprecated in v1.29. You can disable the API group beta version v1beta3 by adding the following command-line flags to your kube-apiserver invocation:

The command-line flag --enable-priority-and-fairness=false will disable the API Priority and Fairness feature.

API Priority and Fairness must be used carefully in recursive server scenarios. These are scenarios in which some server A, while serving a request, issues a subsidiary request to some server B. Perhaps server B might even make a further subsidiary call back to server A. In situations where Priority and Fairness control is applied to both the original request and some subsidiary ones(s), no matter how deep in the recursion, there is a danger of priority inversions and/or deadlocks.

One example of recursion is when the kube-apiserver issues an admission we

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kube-apiserver \
--runtime-config=flowcontrol.apiserver.k8s.io/v1beta3=false \
 # …and other flags as usual
```

Example 2 (yaml):
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: health-for-strangers
spec:
  matchingPrecedence: 1000
  priorityLevelConfiguration:
    name: exempt
  rules:
    - nonResourceRules:
      - nonResourceURLs:
          - "/healthz"
          - "/livez"
          - "/readyz"
        verbs:
          - "*"
      subjects:
        - kind: Group
          group:
            name: "system:unauthenticated"
```

Example 3 (yaml):
```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: list-events-default-service-account
spec:
  distinguisherMethod:
    type: ByUser
  matchingPrecedence: 8000
  priorityLevelConfiguration:
    name: catch-all
  rules:
    - resourceRules:
      - apiGroups:
          - '*'
        namespaces:
          - default
        resources:
          - events
        verbs:
          - list
      subjects:
        - kind: ServiceAccount
          serviceAccount:
            name: default
            namespace: default
```

---

## Extending Kubernetes

**URL:** https://kubernetes.io/docs/concepts/extend-kubernetes/#changing-built-in-resources

**Contents:**
- Extending Kubernetes
- Configuration
- Extensions
  - Extension patterns
    - Note:
  - Extension points
    - Key to the figure
    - Extension point choice flowchart
- Client extensions
- API extensions

Kubernetes is highly configurable and extensible. As a result, there is rarely a need to fork or submit patches to the Kubernetes project code.

This guide describes the options for customizing a Kubernetes cluster. It is aimed at cluster operators who want to understand how to adapt their Kubernetes cluster to the needs of their work environment. Developers who are prospective Platform Developers or Kubernetes Project Contributors will also find it useful as an introduction to what extension points and patterns exist, and their trade-offs and limitations.

Customization approaches can be broadly divided into configuration, which only involves changing command line arguments, local configuration files, or API resources; and extensions, which involve running additional programs, additional network services, or both. This document is primarily about extensions.

Configuration files and command arguments are documented in the Reference section of the online documentation, with a page for each binary:

Command arguments and configuration files may not always be changeable in a hosted Kubernetes service or a distribution with managed installation. When they are changeable, they are usually only changeable by the cluster operator. Also, they are subject to change in future Kubernetes versions, and setting them may require restarting processes. For those reasons, they should be used only when there are no other options.

Built-in policy APIs, such as ResourceQuota, NetworkPolicy and Role-based Access Control (RBAC), are built-in Kubernetes APIs that provide declaratively configured policy settings. APIs are typically usable even with hosted Kubernetes services and with managed Kubernetes installations. The built-in policy APIs follow the same conventions as other Kubernetes resources such as Pods. When you use a policy APIs that is stable, you benefit from a defined support policy like other Kubernetes APIs. For these reasons, policy APIs are recommended over configuration files and command arguments where suitable.

Extensions are software components that extend and deeply integrate with Kubernetes. They adapt it to support new types and new kinds of hardware.

Many cluster administrators use a hosted or distribution instance of Kubernetes. These clusters come with extensions pre-installed. As a result, most Kubernetes users will not need to install extensions and even fewer users will need to author new ones.

Kubernetes is designed to be automated by writing c

*[Content truncated]*

---

## Volumes

**URL:** https://kubernetes.io/docs/concepts/storage/volumes/#read-only-mounts

**Contents:**
- Volumes
- Why volumes are important
- How volumes work
- Types of volumes
  - awsElasticBlockStore (deprecated)
  - azureDisk (deprecated)
  - azureFile (deprecated)
  - cephfs (removed)
  - cinder (deprecated)
  - configMap

Kubernetes volumes provide a way for containers in a pod to access and share data via the filesystem. There are different kinds of volume that you can use for different purposes, such as:

Data sharing can be between different local processes within a container, or between different containers, or between Pods.

Data persistence: On-disk files in a container are ephemeral, which presents some problems for non-trivial applications when running in containers. One problem occurs when a container crashes or is stopped, the container state is not saved so all of the files that were created or modified during the lifetime of the container are lost. After a crash, kubelet restarts the container with a clean state.

Shared storage: Another problem occurs when multiple containers are running in a Pod and need to share files. It can be challenging to set up and access a shared filesystem across all of the containers.

The Kubernetes volume abstraction can help you to solve both of these problems.

Before you learn about volumes, PersistentVolumes and PersistentVolumeClaims, you should read up about Pods and make sure that you understand how Kubernetes uses Pods to run containers.

Kubernetes supports many types of volumes. A Pod can use any number of volume types simultaneously. Ephemeral volume types have a lifetime linked to a specific Pod, but persistent volumes exist beyond the lifetime of any individual pod. When a pod ceases to exist, Kubernetes destroys ephemeral volumes; however, Kubernetes does not destroy persistent volumes. For any kind of volume in a given pod, data is preserved across container restarts.

At its core, a volume is a directory, possibly with some data in it, which is accessible to the containers in a pod. How that directory comes to be, the medium that backs it, and the contents of it are determined by the particular volume type used.

To use a volume, specify the volumes to provide for the Pod in .spec.volumes and declare where to mount those volumes into containers in .spec.containers[*].volumeMounts.

When a pod is launched, a process in the container sees a filesystem view composed from the initial contents of the container image, plus volumes (if defined) mounted inside the container. The process sees a root filesystem that initially matches the contents of the container image. Any writes to within that filesystem hierarchy, if allowed, affect what that process views when it performs a subsequent filesystem access. Volumes are mounte

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configmap-pod
spec:
  containers:
    - name: test
      image: busybox:1.28
      command: ['sh', '-c', 'echo "The app is running!" && tail -f /dev/null']
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
  volumes:
    - name: config-vol
      configMap:
        name: log-config
        items:
          - key: log_level
            path: log_level.conf
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pd
spec:
  containers:
  - image: registry.k8s.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /cache
      name: cache-volume
  volumes:
  - name: cache-volume
    emptyDir:
      sizeLimit: 500Mi
      medium: Memory
```

Example 4 (cel):
```cel
!has(object.spec.volumes) || !object.spec.volumes.exists(v, has(v.gitRepo))
```

---

## Security

**URL:** https://kubernetes.io/docs/concepts/security/

**Contents:**
- Security
- Kubernetes security mechanisms
  - Control plane protection
  - Secrets
  - Workload protection
  - Admission control
  - Auditing
- Cloud provider security
- Policies
- What's next

This section of the Kubernetes documentation aims to help you learn to run workloads more securely, and about the essential aspects of keeping a Kubernetes cluster secure.

Kubernetes is based on a cloud-native architecture, and draws on advice from the CNCF about good practice for cloud native information security.

Read Cloud Native Security and Kubernetes for the broader context about how to secure your cluster and the applications that you're running on it.

Kubernetes includes several APIs and security controls, as well as ways to define policies that can form part of how you manage information security.

A key security mechanism for any Kubernetes cluster is to control access to the Kubernetes API.

Kubernetes expects you to configure and use TLS to provide data encryption in transit within the control plane, and between the control plane and its clients. You can also enable encryption at rest for the data stored within Kubernetes control plane; this is separate from using encryption at rest for your own workloads' data, which might also be a good idea.

The Secret API provides basic protection for configuration values that require confidentiality.

Enforce Pod security standards to ensure that Pods and their containers are isolated appropriately. You can also use RuntimeClasses to define custom isolation if you need it.

Network policies let you control network traffic between Pods, or between Pods and the network outside your cluster.

You can deploy security controls from the wider ecosystem to implement preventative or detective controls around Pods, their containers, and the images that run in them.

Admission controllers are plugins that intercept Kubernetes API requests and can validate or mutate the requests based on specific fields in the request. Thoughtfully designing these controllers helps to avoid unintended disruptions as Kubernetes APIs change across version updates. For design considerations, see Admission Webhook Good Practices.

Kubernetes audit logging provides a security-relevant, chronological set of records documenting the sequence of actions in a cluster. The cluster audits the activities generated by users, by applications that use the Kubernetes API, and by the control plane itself.

If you are running a Kubernetes cluster on your own hardware or a different cloud provider, consult your documentation for security best practices. Here are links to some of the popular cloud providers' security documentation:

You can define se

*[Content truncated]*

---

## Object Names and IDs

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names

**Contents:**
- Object Names and IDs
- Names
    - Note:
  - DNS Subdomain Names
  - RFC 1123 Label Names
    - Note:
  - RFC 1035 Label Names
    - Note:
  - Path Segment Names
    - Note:

Each object in your cluster has a Name that is unique for that type of resource. Every Kubernetes object also has a UID that is unique across your whole cluster.

For example, you can only have one Pod named myapp-1234 within the same namespace, but you can have one Pod and one Deployment that are each named myapp-1234.

For non-unique user-provided attributes, Kubernetes provides labels and annotations.

A client-provided string that refers to an object in a resource URL, such as /api/v1/pods/some-name.

Only one object of a given kind can have a given name at a time. However, if you delete the object, you can make a new object with the same name.

Names must be unique across all API versions of the same resource. API resources are distinguished by their API group, resource type, namespace (for namespaced resources), and name. In other words, API version is irrelevant in this context.

The server may generate a name when generateName is provided instead of name in a resource create request. When generateName is used, the provided value is used as a name prefix, which server appends a generated suffix to. Even though the name is generated, it may conflict with existing names resulting in an HTTP 409 response. This became far less likely to happen in Kubernetes v1.31 and later, since the server will make up to 8 attempts to generate a unique name before returning an HTTP 409 response.

Below are four types of commonly used name constraints for resources.

Most resource types require a name that can be used as a DNS subdomain name as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1123. This means the name must:

Some resource types require their names to follow the DNS label standard as defined in RFC 1035. This means the name must:

Some resource types require their names to be able to be safely encoded as a path segment. In other words, the name may not be "." or ".." and the name may not contain "/" or "%".

Here's an example manifest for a Pod named nginx-demo.

A Kubernetes systems-generated string to uniquely identify objects.

Every object created over the whole lifetime of a Kubernetes cluster has a distinct UID. It is intended to distinguish between historical occurrences of similar entities.

Kubernetes UIDs are universally unique identifiers (also known as UUIDs). UUIDs are standardized as ISO/IEC 9834-8 and as ITU-T X.667.

Was this page helpful?

Thanks f

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
```

---

## Controllers

**URL:** https://kubernetes.io/docs/concepts/architecture/controller/

**Contents:**
- Controllers
- Controller pattern
  - Control via API server
  - Direct control
- Desired versus current state
- Design
    - Note:
- Ways of running controllers
- What's next
- Feedback

In robotics and automation, a control loop is a non-terminating loop that regulates the state of a system.

Here is one example of a control loop: a thermostat in a room.

When you set the temperature, that's telling the thermostat about your desired state. The actual room temperature is the current state. The thermostat acts to bring the current state closer to the desired state, by turning equipment on or off.

A controller tracks at least one Kubernetes resource type. These objects have a spec field that represents the desired state. The controller(s) for that resource are responsible for making the current state come closer to that desired state.

The controller might carry the action out itself; more commonly, in Kubernetes, a controller will send messages to the API server that have useful side effects. You'll see examples of this below.

The Job controller is an example of a Kubernetes built-in controller. Built-in controllers manage state by interacting with the cluster API server.

Job is a Kubernetes resource that runs a Pod, or perhaps several Pods, to carry out a task and then stop.

(Once scheduled, Pod objects become part of the desired state for a kubelet).

When the Job controller sees a new task it makes sure that, somewhere in your cluster, the kubelets on a set of Nodes are running the right number of Pods to get the work done. The Job controller does not run any Pods or containers itself. Instead, the Job controller tells the API server to create or remove Pods. Other components in the control plane act on the new information (there are new Pods to schedule and run), and eventually the work is done.

After you create a new Job, the desired state is for that Job to be completed. The Job controller makes the current state for that Job be nearer to your desired state: creating Pods that do the work you wanted for that Job, so that the Job is closer to completion.

Controllers also update the objects that configure them. For example: once the work is done for a Job, the Job controller updates that Job object to mark it Finished.

(This is a bit like how some thermostats turn a light off to indicate that your room is now at the temperature you set).

In contrast with Job, some controllers need to make changes to things outside of your cluster.

For example, if you use a control loop to make sure there are enough Nodes in your cluster, then that controller needs something outside the current cluster to set up new Nodes when needed.

Controlle

*[Content truncated]*

---

## Objects In Kubernetes

**URL:** https://kubernetes.io/docs/concepts/overview/working-with-objects/

**Contents:**
- Objects In Kubernetes
- Understanding Kubernetes objects
  - Object spec and status
  - Describing a Kubernetes object
  - Required fields
    - Note:
- Server side field validation
- What's next
- Feedback

This page explains how Kubernetes objects are represented in the Kubernetes API, and how you can express them in .yaml format.

Kubernetes objects are persistent entities in the Kubernetes system. Kubernetes uses these entities to represent the state of your cluster. Specifically, they can describe:

A Kubernetes object is a "record of intent"--once you create the object, the Kubernetes system will constantly work to ensure that the object exists. By creating an object, you're effectively telling the Kubernetes system what you want your cluster's workload to look like; this is your cluster's desired state.

To work with Kubernetes objects—whether to create, modify, or delete them—you'll need to use the Kubernetes API. When you use the kubectl command-line interface, for example, the CLI makes the necessary Kubernetes API calls for you. You can also use the Kubernetes API directly in your own programs using one of the Client Libraries.

Almost every Kubernetes object includes two nested object fields that govern the object's configuration: the object spec and the object status. For objects that have a spec, you have to set this when you create the object, providing a description of the characteristics you want the resource to have: its desired state.

The status describes the current state of the object, supplied and updated by the Kubernetes system and its components. The Kubernetes control plane continually and actively manages every object's actual state to match the desired state you supplied.

For example: in Kubernetes, a Deployment is an object that can represent an application running on your cluster. When you create the Deployment, you might set the Deployment spec to specify that you want three replicas of the application to be running. The Kubernetes system reads the Deployment spec and starts three instances of your desired application--updating the status to match your spec. If any of those instances should fail (a status change), the Kubernetes system responds to the difference between spec and status by making a correction--in this case, starting a replacement instance.

For more information on the object spec, status, and metadata, see the Kubernetes API Conventions.

When you create an object in Kubernetes, you must provide the object spec that describes its desired state, as well as some basic information about the object (such as a name). When you use the Kubernetes API to create the object (either directly or via kubectl), that API reque

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

Example 3 (unknown):
```unknown
deployment.apps/nginx-deployment created
```

---
