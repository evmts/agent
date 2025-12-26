# Kubernetes - Workloads

**Pages:** 36

---

## Running Pods on Only Some Nodes

**URL:** https://kubernetes.io/docs/tasks/manage-daemon/pods-some-nodes/

**Contents:**
- Running Pods on Only Some Nodes
- Before you begin
- Running Pods on only some Nodes
  - Step 1: Add labels to your nodes
  - Step 2: Create the manifest
  - Step 3: Create the DaemonSet
- Feedback

This page demonstrates how can you run Pods on only some Nodes as part of a DaemonSet

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Imagine that you want to run a DaemonSet, but you only need to run those daemon pods on nodes that have local solid state (SSD) storage. For example, the Pod might provide cache service to the node, and the cache is only useful when low-latency local storage is available.

Add the label ssd=true to the nodes which have SSDs.

Let's create a DaemonSet which will provision the daemon pods on the SSD labeled nodes only.

Next, use a nodeSelector to ensure that the DaemonSet only runs Pods on nodes with the ssd label set to "true".

Create the DaemonSet from the manifest by using kubectl create or kubectl apply

Let's label another node as ssd=true.

Labelling the node automatically triggers the control plane (specifically, the DaemonSet controller) to run a new daemon pod on that node.

The output is similar to:

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl label nodes example-node-1 example-node-2 ssd=true
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ssd-driver
  labels:
    app: nginx
spec:
  selector:
    matchLabels:
      app: ssd-driver-pod
  template:
    metadata:
      labels:
        app: ssd-driver-pod
    spec:
      nodeSelector:
        ssd: "true"
      containers:
        - name: example-container
          image: example-image
```

Example 3 (shell):
```shell
kubectl label nodes example-node-3 ssd=true
```

Example 4 (shell):
```shell
kubectl get pods -o wide
```

---

## Horizontal Pod Autoscaling

**URL:** https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#tolerance

**Contents:**
- Horizontal Pod Autoscaling
- How does a HorizontalPodAutoscaler work?
  - Algorithm details
  - Pod readiness and autoscaling metrics
    - Best Practice:
- API Object
- Stability of workload scale
- Autoscaling during rolling update
- Support for resource metrics
    - Note:

In Kubernetes, a HorizontalPodAutoscaler automatically updates a workload resource (such as a Deployment or StatefulSet), with the aim of automatically scaling the workload to match demand.

Horizontal scaling means that the response to increased load is to deploy more Pods. This is different from vertical scaling, which for Kubernetes would mean assigning more resources (for example: memory or CPU) to the Pods that are already running for the workload.

If the load decreases, and the number of Pods is above the configured minimum, the HorizontalPodAutoscaler instructs the workload resource (the Deployment, StatefulSet, or other similar resource) to scale back down.

Horizontal pod autoscaling does not apply to objects that can't be scaled (for example: a DaemonSet.)

The HorizontalPodAutoscaler is implemented as a Kubernetes API resource and a controller. The resource determines the behavior of the controller. The horizontal pod autoscaling controller, running within the Kubernetes control plane, periodically adjusts the desired scale of its target (for example, a Deployment) to match observed metrics such as average CPU utilization, average memory utilization, or any other custom metric you specify.

There is walkthrough example of using horizontal pod autoscaling.

Figure 1. HorizontalPodAutoscaler controls the scale of a Deployment and its ReplicaSet

Kubernetes implements horizontal pod autoscaling as a control loop that runs intermittently (it is not a continuous process). The interval is set by the --horizontal-pod-autoscaler-sync-period parameter to the kube-controller-manager (and the default interval is 15 seconds).

Once during each period, the controller manager queries the resource utilization against the metrics specified in each HorizontalPodAutoscaler definition. The controller manager finds the target resource defined by the scaleTargetRef, then selects the pods based on the target resource's .spec.selector labels, and obtains the metrics from either the resource metrics API (for per-pod resource metrics), or the custom metrics API (for all other metrics).

For per-pod resource metrics (like CPU), the controller fetches the metrics from the resource metrics API for each Pod targeted by the HorizontalPodAutoscaler. Then, if a target utilization value is set, the controller calculates the utilization value as a percentage of the equivalent resource request on the containers in each Pod. If a target raw value is set, the raw metric values are

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
type: Resource
resource:
  name: cpu
  target:
    type: Utilization
    averageUtilization: 60
```

Example 2 (yaml):
```yaml
type: ContainerResource
containerResource:
  name: cpu
  container: application
  target:
    type: Utilization
    averageUtilization: 60
```

Example 3 (yaml):
```yaml
behavior:
  scaleDown:
    policies:
    - type: Pods
      value: 4
      periodSeconds: 60
    - type: Percent
      value: 10
      periodSeconds: 60
```

Example 4 (yaml):
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
```

---

## Create static Pods

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/

**Contents:**
- Create static Pods
    - Note:
    - Note:
    - Note:
- Before you begin
- Create a static pod
  - Filesystem-hosted static Pod manifest
  - Web-hosted static pod manifest
- Observe static pod behavior
    - Note:

Static Pods are managed directly by the kubelet daemon on a specific node, without the API server observing them. Unlike Pods that are managed by the control plane (for example, a Deployment); instead, the kubelet watches each static Pod (and restarts it if it fails).

Static Pods are always bound to one Kubelet on a specific node.

The kubelet automatically tries to create a mirror Pod on the Kubernetes API server for each static Pod. This means that the Pods running on a node are visible on the API server, but cannot be controlled from there. The Pod names will be suffixed with the node hostname with a leading hyphen.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

This page assumes you're using CRI-O to run Pods, and that your nodes are running the Fedora operating system. Instructions for other distributions or Kubernetes installations may vary.

You can configure a static Pod with either a file system hosted configuration file or a web hosted configuration file.

Manifests are standard Pod definitions in JSON or YAML format in a specific directory. Use the staticPodPath: <the directory> field in the kubelet configuration file, which periodically scans the directory and creates/deletes static Pods as YAML/JSON files appear/disappear there. Note that the kubelet will ignore files starting with dots when scanning the specified directory.

For example, this is how to start a simple web server as a static Pod:

Choose a node where you want to run the static Pod. In this example, it's my-node1.

Choose a directory, say /etc/kubernetes/manifests and place a web server Pod definition there, for example /etc/kubernetes/manifests/stati

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
ssh my-node1
```

Example 2 (shell):
```shell
# Run this command on the node where kubelet is running
mkdir -p /etc/kubernetes/manifests/
cat <<EOF >/etc/kubernetes/manifests/static-web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    role: myrole
spec:
  containers:
    - name: web
      image: nginx
      ports:
        - name: web
          containerPort: 80
          protocol: TCP
EOF
```

Example 3 (shell):
```shell
# Run this command on the node where the kubelet is running
systemctl restart kubelet
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    role: myrole
spec:
  containers:
    - name: web
      image: nginx
      ports:
        - name: web
          containerPort: 80
          protocol: TCP
```

---

## Assign Devices to Pods and Containers

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-resources/

**Contents:**
- Assign Devices to Pods and Containers
      - Set Up DRA in a Cluster
      - Allocate Devices to Workloads with DRA
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Assign CPU Resources to Containers and Pods

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/

**Contents:**
- Assign CPU Resources to Containers and Pods
- Before you begin
- Create a namespace
- Specify a CPU request and a CPU limit
    - Note:
- CPU units
- Specify a CPU request that is too big for your Nodes
- If you do not specify a CPU limit
- If you specify a CPU limit but do not specify a CPU request
- Motivation for CPU requests and limits

This page shows how to assign a CPU request and a CPU limit to a container. Containers cannot use more CPU than the configured limit. Provided the system has CPU time free, a container is guaranteed to be allocated as much CPU as it requests.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Your cluster must have at least 1 CPU available for use to run the task examples.

A few of the steps on this page require you to run the metrics-server service in your cluster. If you have the metrics-server running, you can skip those steps.

If you are running Minikube, run the following command to enable metrics-server:

To see whether metrics-server (or another provider of the resource metrics API, metrics.k8s.io) is running, type the following command:

If the resource metrics API is available, the output will include a reference to metrics.k8s.io.

Create a Namespace so that the resources you create in this exercise are isolated from the rest of your cluster.

To specify a CPU request for a container, include the resources:requests field in the Container resource manifest. To specify a CPU limit, include resources:limits.

In this exercise, you create a Pod that has one container. The container has a request of 0.5 CPU and a limit of 1 CPU. Here is the configuration file for the Pod:

The args section of the configuration file provides arguments for the container when it starts. The -cpus "2" argument tells the Container to attempt to use 2 CPUs.

Verify that the Pod is running:

View detailed information about the Pod:

The output shows that the one container in the Pod has a CPU request of 500 milliCPU and a CPU limit of 1 CPU.

Use kub

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube addons enable metrics-server
```

Example 2 (shell):
```shell
kubectl get apiservices
```

Example 3 (unknown):
```unknown
NAME
v1beta1.metrics.k8s.io
```

Example 4 (shell):
```shell
kubectl create namespace cpu-example
```

---

## Configure Service Accounts for Pods

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

**Contents:**
- Configure Service Accounts for Pods
- Before you begin
- Use the default service account to access the API server
  - Opt out of API credential automounting
- Use more than one ServiceAccount
    - Note:
  - Cleanup
- Manually create an API token for a ServiceAccount
    - Note:
  - Manually create a long-lived API token for a ServiceAccount

Kubernetes offers two distinct ways for clients that run within your cluster, or that otherwise have a relationship to your cluster's control plane to authenticate to the API server.

A service account provides an identity for processes that run in a Pod, and maps to a ServiceAccount object. When you authenticate to the API server, you identify yourself as a particular user. Kubernetes recognises the concept of a user, however, Kubernetes itself does not have a User API.

This task guide is about ServiceAccounts, which do exist in the Kubernetes API. The guide shows you some ways to configure ServiceAccounts for Pods.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

When Pods contact the API server, Pods authenticate as a particular ServiceAccount (for example, default). There is always at least one ServiceAccount in each namespace.

Every Kubernetes namespace contains at least one ServiceAccount: the default ServiceAccount for that namespace, named default. If you do not specify a ServiceAccount when you create a Pod, Kubernetes automatically assigns the ServiceAccount named default in that namespace.

You can fetch the details for a Pod you have created. For example:

In the output, you see a field spec.serviceAccountName. Kubernetes automatically sets that value if you don't specify it when you create a Pod.

An application running inside a Pod can access the Kubernetes API using automatically mounted service account credentials. See accessing the Cluster to learn more.

When a Pod authenticates as a ServiceAccount, its level of access depends on the authorization plugin and policy in use.

The API credentials are automatically revoked when the Pod is deleted, even if finalizers are in place. In particular, the API credentials are revoked 60 seconds beyond the .metadata.deletionTimestamp set on the Pod (the deletion timestamp is typically the time that the delete request was accepted plus the Pod's termination grace period).

If you don't want the kubelet to automatically mount a ServiceAccount's API credentials, you can opt out of the default behavior. You can opt out of automounting API credentials on /var/run/secrets/kubernetes.io

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pods/<podname> -o yaml
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: build-robot
automountServiceAccountToken: false
...
```

Example 3 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  serviceAccountName: build-robot
  automountServiceAccountToken: false
  ...
```

Example 4 (shell):
```shell
kubectl get serviceaccounts
```

---

## Exposing an External IP Address to Access an Application in a Cluster

**URL:** https://kubernetes.io/docs/tutorials/stateless-application/expose-external-ip-address/

**Contents:**
- Exposing an External IP Address to Access an Application in a Cluster
- Before you begin
- Objectives
- Creating a service for an application running in five pods
    - Note:
    - Note:
- Cleaning up
- What's next
- Feedback

This page shows how to create a Kubernetes Service object that exposes an external IP address.

Run a Hello World application in your cluster:

The preceding command creates a Deployment and an associated ReplicaSet. The ReplicaSet has five Pods each of which runs the Hello World application.

Display information about the Deployment:

Display information about your ReplicaSet objects:

Create a Service object that exposes the deployment:

Display information about the Service:

The output is similar to:

Display detailed information about the Service:

The output is similar to:

Make a note of the external IP address (LoadBalancer Ingress) exposed by your service. In this example, the external IP address is 104.198.205.71. Also note the value of Port and NodePort. In this example, the Port is 8080 and the NodePort is 32377.

In the preceding output, you can see that the service has several endpoints: 10.0.0.6:8080,10.0.1.6:8080,10.0.1.7:8080 + 2 more. These are internal addresses of the pods that are running the Hello World application. To verify these are pod addresses, enter this command:

The output is similar to:

Use the external IP address (LoadBalancer Ingress) to access the Hello World application:

where <external-ip> is the external IP address (LoadBalancer Ingress) of your Service, and <port> is the value of Port in your Service description. If you are using minikube, typing minikube service my-service will automatically open the Hello World application in a browser.

The response to a successful request is a hello message:

To delete the Service, enter this command:

To delete the Deployment, the ReplicaSet, and the Pods that are running the Hello World application, enter this command:

Learn more about connecting applications with services.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: load-balancer-example
  name: hello-world
spec:
  replicas: 5
  selector:
    matchLabels:
      app.kubernetes.io/name: load-balancer-example
  template:
    metadata:
      labels:
        app.kubernetes.io/name: load-balancer-example
    spec:
      containers:
      - image: gcr.io/google-samples/hello-app:2.0
        name: hello-world
        ports:
        - containerPort: 8080
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/service/load-balancer-example.yaml
```

Example 3 (shell):
```shell
kubectl get deployments hello-world
kubectl describe deployments hello-world
```

Example 4 (shell):
```shell
kubectl get replicasets
kubectl describe replicasets
```

---

## Configure GMSA for Windows Pods and containers

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-gmsa/

**Contents:**
- Configure GMSA for Windows Pods and containers
- Before you begin
  - Install the GMSACredentialSpec CRD
  - Install webhooks to validate GMSA users
- Configure GMSAs and Windows nodes in Active Directory
- Create GMSA credential spec resources
- Configure cluster role to enable RBAC on specific GMSA credential specs
- Assign role to service accounts to use specific GMSA credspecs
- Configure GMSA credential spec reference in Pod spec
- Authenticating to network shares using hostname or FQDN

This page shows how to configure Group Managed Service Accounts (GMSA) for Pods and containers that will run on Windows nodes. Group Managed Service Accounts are a specific type of Active Directory account that provides automatic password management, simplified service principal name (SPN) management, and the ability to delegate the management to other administrators across multiple servers.

In Kubernetes, GMSA credential specs are configured at a Kubernetes cluster-wide scope as Custom Resources. Windows Pods, as well as individual containers within a Pod, can be configured to use a GMSA for domain based functions (e.g. Kerberos authentication) when interacting with other Windows services.

You need to have a Kubernetes cluster and the kubectl command-line tool must be configured to communicate with your cluster. The cluster is expected to have Windows worker nodes. This section covers a set of initial steps required once for each cluster:

A CustomResourceDefinition(CRD) for GMSA credential spec resources needs to be configured on the cluster to define the custom resource type GMSACredentialSpec. Download the GMSA CRD YAML and save it as gmsa-crd.yaml. Next, install the CRD with kubectl apply -f gmsa-crd.yaml

Two webhooks need to be configured on the Kubernetes cluster to populate and validate GMSA credential spec references at the Pod or container level:

A mutating webhook that expands references to GMSAs (by name from a Pod specification) into the full credential spec in JSON form within the Pod spec.

A validating webhook ensures all references to GMSAs are authorized to be used by the Pod service account.

Installing the above webhooks and associated objects require the steps below:

Create a certificate key pair (that will be used to allow the webhook container to communicate to the cluster)

Install a secret with the certificate from above.

Create a deployment for the core webhook logic.

Create the validating and mutating webhook configurations referring to the deployment.

A script can be used to deploy and configure the GMSA webhooks and associated objects mentioned above. The script can be run with a --dry-run=server option to allow you to review the changes that would be made to your cluster.

The YAML template used by the script may also be used to deploy the webhooks and associated objects manually (with appropriate substitutions for the parameters)

Before Pods in Kubernetes can be configured to use GMSAs, the desired GMSAs need to be p

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: windows.k8s.io/v1
kind: GMSACredentialSpec
metadata:
  name: gmsa-WebApp1  # This is an arbitrary name but it will be used as a reference
credspec:
  ActiveDirectoryConfig:
    GroupManagedServiceAccounts:
    - Name: WebApp1   # Username of the GMSA account
      Scope: CONTOSO  # NETBIOS Domain Name
    - Name: WebApp1   # Username of the GMSA account
      Scope: contoso.com # DNS Domain Name
  CmsPlugins:
  - ActiveDirectory
  DomainJoinConfig:
    DnsName: contoso.com  # DNS Domain Name
    DnsTreeName: contoso.com # DNS Domain Name Root
    Guid: 244818ae-87ac-4fcd-92ec-e79e5
...
```

Example 2 (yaml):
```yaml
# Create the Role to read the credspec
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: webapp1-role
rules:
- apiGroups: ["windows.k8s.io"]
  resources: ["gmsacredentialspecs"]
  verbs: ["use"]
  resourceNames: ["gmsa-WebApp1"]
```

Example 3 (yaml):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: allow-default-svc-account-read-on-gmsa-WebApp1
  namespace: default
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
roleRef:
  kind: ClusterRole
  name: webapp1-role
  apiGroup: rbac.authorization.k8s.io
```

Example 4 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: with-creds
  name: with-creds
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: with-creds
  template:
    metadata:
      labels:
        run: with-creds
    spec:
      securityContext:
        windowsOptions:
          gmsaCredentialSpecName: gmsa-webapp1
      containers:
      - image: mcr.microsoft.com/windows/servercore/iis:windowsservercore-ltsc2019
        imagePullPolicy: Always
        name: iis
      nodeSelector:
        kubernetes.io/os: windows
```

---

## Debug Running Pods

**URL:** https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/

**Contents:**
- Debug Running Pods
- Before you begin
- Using kubectl describe pod to fetch details about pods
- Example: debugging Pending Pods
- Examining pod logs
- Debugging with container exec
    - Note:
- Debugging with an ephemeral debug container
  - Example debugging using ephemeral containers
    - Note:

This page explains how to debug Pods running (or crashing) on a Node.

For this example we'll use a Deployment to create two pods, similar to the earlier example.

Create deployment by running following command:

Check pod status by following command:

We can retrieve a lot more information about each of these pods using kubectl describe pod. For example:

Here you can see configuration information about the container(s) and Pod (labels, resource requirements, etc.), as well as status information about the container(s) and Pod (state, readiness, restart count, events, etc.).

The container state is one of Waiting, Running, or Terminated. Depending on the state, additional information will be provided -- here you can see that for a container in Running state, the system tells you when the container started.

Ready tells you whether the container passed its last readiness probe. (In this case, the container does not have a readiness probe configured; the container is assumed to be ready if no readiness probe is configured.)

Restart Count tells you how many times the container has been restarted; this information can be useful for detecting crash loops in containers that are configured with a restart policy of 'always.'

Currently the only Condition associated with a Pod is the binary Ready condition, which indicates that the pod is able to service requests and should be added to the load balancing pools of all matching services.

Lastly, you see a log of recent events related to your Pod. "From" indicates the component that is logging the event. "Reason" and "Message" tell you what happened.

A common scenario that you can detect using events is when you've created a Pod that won't fit on any node. For example, the Pod might request more resources than are free on any node, or it might specify a label selector that doesn't match any nodes. Let's say we created the previous Deployment with 5 replicas (instead of 2) and requesting 600 millicores instead of 500, on a four-node cluster where each (virtual) machine has 1 CPU. In that case one of the Pods will not be able to schedule. (Note that because of the cluster addon pods such as fluentd, skydns, etc., that run on each node, if we requested 1000 millicores then none of the Pods would be able to schedule.)

To find out why the nginx-deployment-1370807587-fz9sd pod is not running, we can use kubectl describe pod on the pending Pod and look at its events:

Here you can see the event generated by the scheduler

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
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          limits:
            memory: "128Mi"
            cpu: "500m"
        ports:
        - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/nginx-with-request.yaml
```

Example 3 (none):
```none
deployment.apps/nginx-deployment created
```

Example 4 (shell):
```shell
kubectl get pods
```

---

## Perform a Rollback on a DaemonSet

**URL:** https://kubernetes.io/docs/tasks/manage-daemon/rollback-daemon-set/

**Contents:**
- Perform a Rollback on a DaemonSet
- Before you begin
- Performing a rollback on a DaemonSet
  - Step 1: Find the DaemonSet revision you want to roll back to
  - Step 2: Roll back to a specific revision
    - Note:
  - Step 3: Watch the progress of the DaemonSet rollback
- Understanding DaemonSet revisions
    - Note:
- Troubleshooting

This page shows how to perform a rollback on a DaemonSet.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.7.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

You should already know how to perform a rolling update on a DaemonSet.

You can skip this step if you only want to roll back to the last revision.

List all revisions of a DaemonSet:

This returns a list of DaemonSet revisions:

To see the details of a specific revision:

This returns the details of that revision:

If it succeeds, the command returns:

kubectl rollout undo daemonset tells the server to start rolling back the DaemonSet. The real rollback is done asynchronously inside the cluster control plane.

To watch the progress of the rollback:

When the rollback is complete, the output is similar to:

In the previous kubectl rollout history step, you got a list of DaemonSet revisions. Each revision is stored in a resource named ControllerRevision.

To see what is stored in each revision, find the DaemonSet revision raw resources:

This returns a list of ControllerRevisions:

Each ControllerRevision stores the annotations and template of a DaemonSet revision.

kubectl rollout undo takes a specific ControllerRevision and replaces DaemonSet template with the template stored in the ControllerRevision. kubectl rollout undo is equivalent to updating DaemonSet template to a previous revision through other commands, such as kubectl edit or kubectl apply.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl rollout history daemonset <daemonset-name>
```

Example 2 (unknown):
```unknown
daemonsets "<daemonset-name>"
REVISION        CHANGE-CAUSE
1               ...
2               ...
...
```

Example 3 (shell):
```shell
kubectl rollout history daemonset <daemonset-name> --revision=1
```

Example 4 (unknown):
```unknown
daemonsets "<daemonset-name>" with revision #1
Pod Template:
Labels:       foo=bar
Containers:
app:
 Image:        ...
 Port:         ...
 Environment:  ...
 Mounts:       ...
Volumes:      ...
```

---

## HorizontalPodAutoscaler Walkthrough

**URL:** https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

**Contents:**
- HorizontalPodAutoscaler Walkthrough
- Before you begin
- Run and expose php-apache server
- Create the HorizontalPodAutoscaler
- Increase the load
    - Note:
- Stop generating load
- Autoscaling on multiple metrics and custom metrics
  - Autoscaling on more specific metrics
  - Autoscaling on metrics not related to Kubernetes objects

A HorizontalPodAutoscaler (HPA for short) automatically updates a workload resource (such as a Deployment or StatefulSet), with the aim of automatically scaling the workload to match demand.

Horizontal scaling means that the response to increased load is to deploy more Pods. This is different from vertical scaling, which for Kubernetes would mean assigning more resources (for example: memory or CPU) to the Pods that are already running for the workload.

If the load decreases, and the number of Pods is above the configured minimum, the HorizontalPodAutoscaler instructs the workload resource (the Deployment, StatefulSet, or other similar resource) to scale back down.

This document walks you through an example of enabling HorizontalPodAutoscaler to automatically manage scale for an example web app. This example workload is Apache httpd running some PHP code.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.23.To check the version, enter kubectl version.If you're running an older release of Kubernetes, refer to the version of the documentation for that release (see available documentation versions).

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

To follow this walkthrough, you also need to use a cluster that has a Metrics Server deployed and configured. The Kubernetes Metrics Server collects resource metrics from the kubelets in your cluster, and exposes those metrics through the Kubernetes API, using an APIService to add new kinds of resource that represent metric readings.

To learn how to deploy the Metrics Server, see the metrics-server documentation.

If you are running Minikube, run the following command to enable metrics-server:

To demonstrate a HorizontalPo

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube addons enable metrics-server
```

Example 2 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/php-apache.yaml
```

Example 4 (unknown):
```unknown
deployment.apps/php-apache created
service/php-apache created
```

---

## Assign Pods to Nodes using Node Affinity

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/

**Contents:**
- Assign Pods to Nodes using Node Affinity
- Before you begin
- Add a label to a node
- Schedule a Pod using required node affinity
- Schedule a Pod using preferred node affinity
- What's next
- Feedback

This page shows how to assign a Kubernetes Pod to a particular node using Node Affinity in a Kubernetes cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.10.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

List the nodes in your cluster, along with their labels:

The output is similar to this:

Choose one of your nodes, and add a label to it:

where <your-node-name> is the name of your chosen node.

Verify that your chosen node has a disktype=ssd label:

The output is similar to this:

In the preceding output, you can see that the worker0 node has a disktype=ssd label.

This manifest describes a Pod that has a requiredDuringSchedulingIgnoredDuringExecution node affinity,disktype: ssd. This means that the pod will get scheduled only on a node that has a disktype=ssd label.

Apply the manifest to create a Pod that is scheduled onto your chosen node:

Verify that the pod is running on your chosen node:

The output is similar to this:

This manifest describes a Pod that has a preferredDuringSchedulingIgnoredDuringExecution node affinity,disktype: ssd. This means that the pod will prefer a node that has a disktype=ssd label.

Apply the manifest to create a Pod that is scheduled onto your chosen node:

Verify that the pod is running on your chosen node:

The output is similar to this:

Learn more about Node Affinity.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes --show-labels
```

Example 2 (shell):
```shell
NAME      STATUS    ROLES    AGE     VERSION        LABELS
worker0   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker0
worker1   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker1
worker2   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker2
```

Example 3 (shell):
```shell
kubectl label nodes <your-node-name> disktype=ssd
```

Example 4 (shell):
```shell
kubectl get nodes --show-labels
```

---

## Guaranteed Scheduling For Critical Add-On Pods

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/

**Contents:**
- Guaranteed Scheduling For Critical Add-On Pods
  - Marking pod as critical
- Feedback

Kubernetes core components such as the API server, scheduler, and controller-manager run on a control plane node. However, add-ons must run on a regular cluster node. Some of these add-ons are critical to a fully functional cluster, such as metrics-server, DNS, and UI. A cluster may stop working properly if a critical add-on is evicted (either manually or as a side effect of another operation like upgrade) and becomes pending (for example when the cluster is highly utilized and either there are other pending pods that schedule into the space vacated by the evicted critical add-on pod or the amount of resources available on the node changed for some other reason).

Note that marking a pod as critical is not meant to prevent evictions entirely; it only prevents the pod from becoming permanently unavailable. A static pod marked as critical can't be evicted. However, non-static pods marked as critical are always rescheduled.

To mark a Pod as critical, set priorityClassName for that Pod to system-cluster-critical or system-node-critical. system-node-critical is the highest available priority, even higher than system-cluster-critical.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Horizontal Pod Autoscaling

**URL:** https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

**Contents:**
- Horizontal Pod Autoscaling
- How does a HorizontalPodAutoscaler work?
  - Algorithm details
  - Pod readiness and autoscaling metrics
    - Best Practice:
- API Object
- Stability of workload scale
- Autoscaling during rolling update
- Support for resource metrics
    - Note:

In Kubernetes, a HorizontalPodAutoscaler automatically updates a workload resource (such as a Deployment or StatefulSet), with the aim of automatically scaling the workload to match demand.

Horizontal scaling means that the response to increased load is to deploy more Pods. This is different from vertical scaling, which for Kubernetes would mean assigning more resources (for example: memory or CPU) to the Pods that are already running for the workload.

If the load decreases, and the number of Pods is above the configured minimum, the HorizontalPodAutoscaler instructs the workload resource (the Deployment, StatefulSet, or other similar resource) to scale back down.

Horizontal pod autoscaling does not apply to objects that can't be scaled (for example: a DaemonSet.)

The HorizontalPodAutoscaler is implemented as a Kubernetes API resource and a controller. The resource determines the behavior of the controller. The horizontal pod autoscaling controller, running within the Kubernetes control plane, periodically adjusts the desired scale of its target (for example, a Deployment) to match observed metrics such as average CPU utilization, average memory utilization, or any other custom metric you specify.

There is walkthrough example of using horizontal pod autoscaling.

Figure 1. HorizontalPodAutoscaler controls the scale of a Deployment and its ReplicaSet

Kubernetes implements horizontal pod autoscaling as a control loop that runs intermittently (it is not a continuous process). The interval is set by the --horizontal-pod-autoscaler-sync-period parameter to the kube-controller-manager (and the default interval is 15 seconds).

Once during each period, the controller manager queries the resource utilization against the metrics specified in each HorizontalPodAutoscaler definition. The controller manager finds the target resource defined by the scaleTargetRef, then selects the pods based on the target resource's .spec.selector labels, and obtains the metrics from either the resource metrics API (for per-pod resource metrics), or the custom metrics API (for all other metrics).

For per-pod resource metrics (like CPU), the controller fetches the metrics from the resource metrics API for each Pod targeted by the HorizontalPodAutoscaler. Then, if a target utilization value is set, the controller calculates the utilization value as a percentage of the equivalent resource request on the containers in each Pod. If a target raw value is set, the raw metric values are

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
type: Resource
resource:
  name: cpu
  target:
    type: Utilization
    averageUtilization: 60
```

Example 2 (yaml):
```yaml
type: ContainerResource
containerResource:
  name: cpu
  container: application
  target:
    type: Utilization
    averageUtilization: 60
```

Example 3 (yaml):
```yaml
behavior:
  scaleDown:
    policies:
    - type: Pods
      value: 4
      periodSeconds: 60
    - type: Percent
      value: 10
      periodSeconds: 60
```

Example 4 (yaml):
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
```

---

## Perform a Rolling Update on a DaemonSet

**URL:** https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/

**Contents:**
- Perform a Rolling Update on a DaemonSet
- Before you begin
- DaemonSet Update Strategy
- Performing a Rolling Update
  - Creating a DaemonSet with RollingUpdate update strategy
  - Checking DaemonSet RollingUpdate update strategy
  - Updating a DaemonSet template
    - Declarative commands
    - Imperative commands
      - Updating only the container image

This page shows how to perform a rolling update on a DaemonSet.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

DaemonSet has two update strategy types:

To enable the rolling update feature of a DaemonSet, you must set its .spec.updateStrategy.type to RollingUpdate.

You may want to set .spec.updateStrategy.rollingUpdate.maxUnavailable (default to 1), .spec.minReadySeconds (default to 0) and .spec.updateStrategy.rollingUpdate.maxSurge (defaults to 0) as well.

This YAML file specifies a DaemonSet with an update strategy as 'RollingUpdate'

After verifying the update strategy of the DaemonSet manifest, create the DaemonSet:

Alternatively, use kubectl apply to create the same DaemonSet if you plan to update the DaemonSet with kubectl apply.

Check the update strategy of your DaemonSet, and make sure it's set to RollingUpdate:

If you haven't created the DaemonSet in the system, check your DaemonSet manifest with the following command instead:

The output from both commands should be:

If the output isn't RollingUpdate, go back and modify the DaemonSet object or manifest accordingly.

Any updates to a RollingUpdate DaemonSet .spec.template will trigger a rolling update. Let's update the DaemonSet by applying a new YAML file. This can be done with several different kubectl commands.

If you update DaemonSets using configuration files, use kubectl apply:

If you update DaemonSets using imperative commands, use kubectl edit :

If you only need to update the container image in the DaemonSet template, i.e. .spec.template.spec.containers[*].image, use kubectl set image:

Finally, watch the rollout status of the latest DaemonSet rolling update:

When the rollout is complete, the output is similar to this:

Sometimes, a DaemonSet rolling update may be stuck. Here are some possible causes:

The rollout is stuck because new DaemonSet pods can't be scheduled on at least one node. This is possible when the node is running out of resources.

When this happens, find the nodes that don't have the DaemonSet pods scheduled on by comparing the output of kubectl get nodes and the output of:

Once you've found those nodes, delete some non-DaemonSet pods fr

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
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        name: fluentd-elasticsearch
    spec:
      tolerations:
      # these tolerations are to have the daemonset runnable on control plane nodes
      # remove them if your control plane nodes should not run pods
      - key: node-role.kubernetes.io/control-plan
...
```

Example 2 (shell):
```shell
kubectl create -f https://k8s.io/examples/controllers/fluentd-daemonset.yaml
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/controllers/fluentd-daemonset.yaml
```

Example 4 (shell):
```shell
kubectl get ds/fluentd-elasticsearch -o go-template='{{.spec.updateStrategy.type}}{{"\n"}}' -n kube-system
```

---

## Using a Service to Expose Your App

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/expose/expose-intro/

**Contents:**
- Using a Service to Expose Your App
- Objectives
- Overview of Kubernetes Services
- Services and Labels
  - Step 1: Creating a new Service
    - Note:
  - Step 2: Using labels
  - Step 3: Deleting a service
- What's next
- Feedback

Kubernetes Pods are mortal. Pods have a lifecycle. When a worker node dies, the Pods running on the Node are also lost. A Replicaset might then dynamically drive the cluster back to the desired state via the creation of new Pods to keep your application running. As another example, consider an image-processing backend with 3 replicas. Those replicas are exchangeable; the front-end system should not care about backend replicas or even if a Pod is lost and recreated. That said, each Pod in a Kubernetes cluster has a unique IP address, even Pods on the same Node, so there needs to be a way of automatically reconciling changes among Pods so that your applications continue to function.

A Service in Kubernetes is an abstraction which defines a logical set of Pods and a policy by which to access them. Services enable a loose coupling between dependent Pods. A Service is defined using YAML or JSON, like all Kubernetes object manifests. The set of Pods targeted by a Service is usually determined by a label selector (see below for why you might want a Service without including a selector in the spec).

Although each Pod has a unique IP address, those IPs are not exposed outside the cluster without a Service. Services allow your applications to receive traffic. Services can be exposed in different ways by specifying a type in the spec of the Service:

ClusterIP (default) - Exposes the Service on an internal IP in the cluster. This type makes the Service only reachable from within the cluster.

NodePort - Exposes the Service on the same port of each selected Node in the cluster using NAT. Makes a Service accessible from outside the cluster using NodeIP:NodePort. Superset of ClusterIP.

LoadBalancer - Creates an external load balancer in the current cloud (if supported) and assigns a fixed, external IP to the Service. Superset of NodePort.

ExternalName - Maps the Service to the contents of the externalName field (e.g. foo.bar.example.com), by returning a CNAME record with its value. No proxying of any kind is set up. This type requires v1.7 or higher of kube-dns, or CoreDNS version 0.0.8 or higher.

More information about the different types of Services can be found in the Using Source IP tutorial. Also see Connecting Applications with Services.

Additionally, note that there are some use cases with Services that involve not defining a selector in the spec. A Service created without selector will also not create the corresponding Endpoints object. This allows users t

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pods
```

Example 2 (shell):
```shell
kubectl get services
```

Example 3 (shell):
```shell
kubectl expose deployment/kubernetes-bootcamp --type="NodePort" --port 8080
```

Example 4 (shell):
```shell
kubectl describe services/kubernetes-bootcamp
```

---

## Example: Deploying Cassandra with a StatefulSet

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/cassandra/

**Contents:**
- Example: Deploying Cassandra with a StatefulSet
    - Note:
- Objectives
- Before you begin
  - Additional Minikube setup instructions
    - Caution:
- Creating a headless Service for Cassandra
  - Validating (optional)
- Using a StatefulSet to create a Cassandra ring
    - Note:

This tutorial shows you how to run Apache Cassandra on Kubernetes. Cassandra, a database, needs persistent storage to provide data durability (application state). In this example, a custom Cassandra seed provider lets the database discover new Cassandra instances as they join the Cassandra cluster.

StatefulSets make it easier to deploy stateful applications into your Kubernetes cluster. For more information on the features used in this tutorial, see StatefulSet.

Cassandra and Kubernetes both use the term node to mean a member of a cluster. In this tutorial, the Pods that belong to the StatefulSet are Cassandra nodes and are members of the Cassandra cluster (called a ring). When those Pods run in your Kubernetes cluster, the Kubernetes control plane schedules those Pods onto Kubernetes Nodes.

When a Cassandra node starts, it uses a seed list to bootstrap discovery of other nodes in the ring. This tutorial deploys a custom Cassandra seed provider that lets the database discover new Cassandra Pods as they appear inside your Kubernetes cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To complete this tutorial, you should already have a basic familiarity with Pods, Services, and StatefulSets.

Minikube defaults to 2048MB of memory and 2 CPU. Running Minikube with the default resource configuration results in insufficient resource errors during this tutorial. To avoid these errors, start Minikube with the following settings:

In Kubernetes, a Service describes a set of Pods that perform the same task.

The following Service is used for DNS lookups between Cassandra Pods and clients within your cluster:

Create a Service to track all Cassandra StatefulSet members from the cassandra-service.yaml file:

Get the Cassandra Service.

If you don't see a Service named cassandra, that means creation failed. Read Debug Services for help troubleshooting common issues.

The StatefulSet manifest, included below, creates a Cassandra ring that consists of three Pods.

Create the Cassandra StatefulSet from the cassandra-statefulset.yaml file:

If you need to modify cassandra-statefulset.yaml to suit your cluster, download https://k8s.io/examples/

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube start --memory 5120 --cpus=4
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: cassandra
  name: cassandra
spec:
  clusterIP: None
  ports:
  - port: 9042
  selector:
    app: cassandra
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/cassandra/cassandra-service.yaml
```

Example 4 (shell):
```shell
kubectl get svc cassandra
```

---

## Configure RunAsUserName for Windows pods and containers

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/configure-runasusername/

**Contents:**
- Configure RunAsUserName for Windows pods and containers
- Before you begin
- Set the Username for a Pod
- Set the Username for a Container
- Windows Username limitations
- What's next
- Feedback

This page shows how to use the runAsUserName setting for Pods and containers that will run on Windows nodes. This is roughly equivalent of the Linux-specific runAsUser setting, allowing you to run applications in a container as a different username than the default.

You need to have a Kubernetes cluster and the kubectl command-line tool must be configured to communicate with your cluster. The cluster is expected to have Windows worker nodes where pods with containers running Windows workloads will get scheduled.

To specify the username with which to execute the Pod's container processes, include the securityContext field (PodSecurityContext) in the Pod specification, and within it, the windowsOptions (WindowsSecurityContextOptions) field containing the runAsUserName field.

The Windows security context options that you specify for a Pod apply to all Containers and init Containers in the Pod.

Here is a configuration file for a Windows Pod that has the runAsUserName field set:

Verify that the Pod's Container is running:

Get a shell to the running Container:

Check that the shell is running user the correct username:

The output should be:

To specify the username with which to execute a Container's processes, include the securityContext field (SecurityContext) in the Container manifest, and within it, the windowsOptions (WindowsSecurityContextOptions) field containing the runAsUserName field.

The Windows security context options that you specify for a Container apply only to that individual Container, and they override the settings made at the Pod level.

Here is the configuration file for a Pod that has one Container, and the runAsUserName field is set at the Pod level and the Container level:

Verify that the Pod's Container is running:

Get a shell to the running Container:

Check that the shell is running user the correct username (the one set at the Container level):

The output should be:

In order to use this feature, the value set in the runAsUserName field must be a valid username. It must have the following format: DOMAIN\USER, where DOMAIN\ is optional. Windows user names are case insensitive. Additionally, there are some restrictions regarding the DOMAIN and USER:

Examples of acceptable values for the runAsUserName field: ContainerAdministrator, ContainerUser, NT AUTHORITY\NETWORK SERVICE, NT AUTHORITY\LOCAL SERVICE.

For more information about these limtations, check here and here.

Was this page helpful?

Thanks for the feedback. If you 

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: run-as-username-pod-demo
spec:
  securityContext:
    windowsOptions:
      runAsUserName: "ContainerUser"
  containers:
  - name: run-as-username-demo
    image: mcr.microsoft.com/windows/servercore:ltsc2019
    command: ["ping", "-t", "localhost"]
  nodeSelector:
    kubernetes.io/os: windows
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/windows/run-as-username-pod.yaml
```

Example 3 (shell):
```shell
kubectl get pod run-as-username-pod-demo
```

Example 4 (shell):
```shell
kubectl exec -it run-as-username-pod-demo -- powershell
```

---

## Assign Pods to Nodes

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/

**Contents:**
- Assign Pods to Nodes
- Before you begin
- Add a label to a node
- Create a pod that gets scheduled to your chosen node
- Create a pod that gets scheduled to specific node
- What's next
- Feedback

This page shows how to assign a Kubernetes Pod to a particular node in a Kubernetes cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

List the nodes in your cluster, along with their labels:

The output is similar to this:

Choose one of your nodes, and add a label to it:

where <your-node-name> is the name of your chosen node.

Verify that your chosen node has a disktype=ssd label:

The output is similar to this:

In the preceding output, you can see that the worker0 node has a disktype=ssd label.

This pod configuration file describes a pod that has a node selector, disktype: ssd. This means that the pod will get scheduled on a node that has a disktype=ssd label.

Use the configuration file to create a pod that will get scheduled on your chosen node:

Verify that the pod is running on your chosen node:

The output is similar to this:

You can also schedule a pod to one specific node via setting nodeName.

Use the configuration file to create a pod that will get scheduled on foo-node only.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get nodes --show-labels
```

Example 2 (shell):
```shell
NAME      STATUS    ROLES    AGE     VERSION        LABELS
worker0   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker0
worker1   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker1
worker2   Ready     <none>   1d      v1.13.0        ...,kubernetes.io/hostname=worker2
```

Example 3 (shell):
```shell
kubectl label nodes <your-node-name> disktype=ssd
```

Example 4 (shell):
```shell
kubectl get nodes --show-labels
```

---

## Running ZooKeeper, A Distributed System Coordinator

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/zookeeper/

**Contents:**
- Running ZooKeeper, A Distributed System Coordinator
- Before you begin
- Objectives
  - ZooKeeper
- Creating a ZooKeeper ensemble
  - Facilitating leader election
  - Achieving consensus
  - Sanity testing the ensemble
  - Providing durable storage
- Ensuring consistent configuration

This tutorial demonstrates running Apache Zookeeper on Kubernetes using StatefulSets, PodDisruptionBudgets, and PodAntiAffinity.

Before starting this tutorial, you should be familiar with the following Kubernetes concepts:

You must have a cluster with at least four nodes, and each node requires at least 2 CPUs and 4 GiB of memory. In this tutorial you will cordon and drain the cluster's nodes. This means that the cluster will terminate and evict all Pods on its nodes, and the nodes will temporarily become unschedulable. You should use a dedicated cluster for this tutorial, or you should ensure that the disruption you cause will not interfere with other tenants.

This tutorial assumes that you have configured your cluster to dynamically provision PersistentVolumes. If your cluster is not configured to do so, you will have to manually provision three 20 GiB volumes before starting this tutorial.

After this tutorial, you will know the following.

Apache ZooKeeper is a distributed, open-source coordination service for distributed applications. ZooKeeper allows you to read, write, and observe updates to data. Data are organized in a file system like hierarchy and replicated to all ZooKeeper servers in the ensemble (a set of ZooKeeper servers). All operations on data are atomic and sequentially consistent. ZooKeeper ensures this by using the Zab consensus protocol to replicate a state machine across all servers in the ensemble.

The ensemble uses the Zab protocol to elect a leader, and the ensemble cannot write data until that election is complete. Once complete, the ensemble uses Zab to ensure that it replicates all writes to a quorum before it acknowledges and makes them visible to clients. Without respect to weighted quorums, a quorum is a majority component of the ensemble containing the current leader. For instance, if the ensemble has three servers, a component that contains the leader and one other server constitutes a quorum. If the ensemble can not achieve a quorum, the ensemble cannot write data.

ZooKeeper servers keep their entire state machine in memory, and write every mutation to a durable WAL (Write Ahead Log) on storage media. When a server crashes, it can recover its previous state by replaying the WAL. To prevent the WAL from growing without bound, ZooKeeper servers will periodically snapshot them in memory state to storage media. These snapshots can be loaded directly into memory, and all WAL entries that preceded the snapshot may be disca

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: zk-hs
  labels:
    app: zk
spec:
  ports:
  - port: 2888
    name: server
  - port: 3888
    name: leader-election
  clusterIP: None
  selector:
    app: zk
---
apiVersion: v1
kind: Service
metadata:
  name: zk-cs
  labels:
    app: zk
spec:
  ports:
  - port: 2181
    name: client
  selector:
    app: zk
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zk-pdb
spec:
  selector:
    matchLabels:
      app: zk
  maxUnavailable: 1
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: zk
spec:
  selector:
    matchLabels:
 
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/zookeeper/zookeeper.yaml
```

Example 3 (unknown):
```unknown
service/zk-hs created
service/zk-cs created
poddisruptionbudget.policy/zk-pdb created
statefulset.apps/zk created
```

Example 4 (shell):
```shell
kubectl get pods -w -l app=zk
```

---

## Configure Pods and Containers

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/

**Contents:**
- Configure Pods and Containers
      - Assign Memory Resources to Containers and Pods
      - Assign CPU Resources to Containers and Pods
      - Assign Devices to Pods and Containers
      - Assign Pod-level CPU and memory resources
      - Configure GMSA for Windows Pods and containers
      - Resize CPU and Memory Resources assigned to Containers
      - Configure RunAsUserName for Windows pods and containers
      - Create a Windows HostProcess Pod
      - Configure Quality of Service for Pods

Assign infrastructure resources to your Kubernetes workloads.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Deploy and Access the Kubernetes Dashboard

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/

**Contents:**
- Deploy and Access the Kubernetes Dashboard
- Deploying the Dashboard UI
    - Note:
- Accessing the Dashboard UI
    - Warning:
  - Command line proxy
    - Note:
- Welcome view
- Deploying containerized applications
  - Specifying application details

Dashboard is a web-based Kubernetes user interface. You can use Dashboard to deploy containerized applications to a Kubernetes cluster, troubleshoot your containerized application, and manage the cluster resources. You can use Dashboard to get an overview of applications running on your cluster, as well as for creating or modifying individual Kubernetes resources (such as Deployments, Jobs, DaemonSets, etc). For example, you can scale a Deployment, initiate a rolling update, restart a pod or deploy new applications using a deploy wizard.

Dashboard also provides information on the state of Kubernetes resources in your cluster and on any errors that may have occurred.

The Dashboard UI is not deployed by default. To deploy it, run the following command:

To protect your cluster data, Dashboard deploys with a minimal RBAC configuration by default. Currently, Dashboard only supports logging in with a Bearer Token. To create a token for this demo, you can follow our guide on creating a sample user.

You can enable access to the Dashboard using the kubectl command-line tool, by running the following command:

Kubectl will make Dashboard available at https://localhost:8443.

The UI can only be accessed from the machine where the command is executed. See kubectl port-forward --help for more options.

When you access Dashboard on an empty cluster, you'll see the welcome page. This page contains a link to this document as well as a button to deploy your first application. In addition, you can view which system applications are running by default in the kube-system namespace of your cluster, for example the Dashboard itself.

Dashboard lets you create and deploy a containerized application as a Deployment and optional Service with a simple wizard. You can either manually specify application details, or upload a YAML or JSON manifest file containing application configuration.

Click the CREATE button in the upper right corner of any page to begin.

The deploy wizard expects that you provide the following information:

App name (mandatory): Name for your application. A label with the name will be added to the Deployment and Service, if any, that will be deployed.

The application name must be unique within the selected Kubernetes namespace. It must start with a lowercase character, and end with a lowercase character or a number, and contain only lowercase letters, numbers and dashes (-). It is limited to 24 characters. Leading and trailing spaces are ignored.

Contain

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
# Add kubernetes-dashboard repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
```

Example 2 (unknown):
```unknown
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

Example 3 (conf):
```conf
release=1.0
tier=frontend
environment=pod
track=stable
```

---

## Adding entries to Pod /etc/hosts with HostAliases

**URL:** https://kubernetes.io/docs/tasks/network/customize-hosts-file-for-pods/

**Contents:**
- Adding entries to Pod /etc/hosts with HostAliases
- Default hosts file content
- Adding additional entries with hostAliases
- Why does the kubelet manage the hosts file?
    - Caution:
- Feedback

Adding entries to a Pod's /etc/hosts file provides Pod-level override of hostname resolution when DNS and other options are not applicable. You can add these custom entries with the HostAliases field in PodSpec.

The Kubernetes project recommends modifying DNS configuration using the hostAliases field (part of the .spec for a Pod), and not by using an init container or other means to edit /etc/hosts directly. Change made in other ways may be overwritten by the kubelet during Pod creation or restart.

Start an Nginx Pod which is assigned a Pod IP:

The hosts file content would look like this:

By default, the hosts file only includes IPv4 and IPv6 boilerplates like localhost and its own hostname.

In addition to the default boilerplate, you can add additional entries to the hosts file. For example: to resolve foo.local, bar.local to 127.0.0.1 and foo.remote, bar.remote to 10.1.2.3, you can configure HostAliases for a Pod under .spec.hostAliases:

You can start a Pod with that configuration by running:

Examine a Pod's details to see its IPv4 address and its status:

The hosts file content looks like this:

with the additional entries specified at the bottom.

The kubelet manages the hosts file for each container of the Pod to prevent the container runtime from modifying the file after the containers have already been started. Historically, Kubernetes always used Docker Engine as its container runtime, and Docker Engine would then modify the /etc/hosts file after each container had started.

Current Kubernetes can use a variety of container runtimes; even so, the kubelet manages the hosts file within each container so that the outcome is as intended regardless of which container runtime you use.

Avoid making manual changes to the hosts file inside a container.

If you make manual changes to the hosts file, those changes are lost when the container exits.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl run nginx --image nginx
```

Example 2 (unknown):
```unknown
pod/nginx created
```

Example 3 (shell):
```shell
kubectl get pods --output=wide
```

Example 4 (unknown):
```unknown
NAME     READY     STATUS    RESTARTS   AGE    IP           NODE
nginx    1/1       Running   0          13s    10.200.0.4   worker0
```

---

## Migrate from PodSecurityPolicy to the Built-In PodSecurity Admission Controller

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/migrate-from-psp/

**Contents:**
- Migrate from PodSecurityPolicy to the Built-In PodSecurity Admission Controller
- Before you begin
- Overall approach
- 0. Decide whether Pod Security Admission is right for you
- 1. Review namespace permissions
- 2. Simplify & standardize PodSecurityPolicies
  - 2.a. Eliminate purely mutating fields
    - Caution:
  - 2.b. Eliminate options not covered by the Pod Security Standards
    - Caution:

This page describes the process of migrating from PodSecurityPolicies to the built-in PodSecurity admission controller. This can be done effectively using a combination of dry-run and audit and warn modes, although this becomes harder if mutating PSPs are used.

Your Kubernetes server must be at or later than version v1.22.

To check the version, enter kubectl version.

If you are currently running a version of Kubernetes other than 1.34, you may want to switch to viewing this page in the documentation for the version of Kubernetes that you are actually running.

This page assumes you are already familiar with the basic Pod Security Admission concepts.

There are multiple strategies you can take for migrating from PodSecurityPolicy to Pod Security Admission. The following steps are one possible migration path, with a goal of minimizing both the risks of a production outage and of a security gap.

Pod Security Admission was designed to meet the most common security needs out of the box, and to provide a standard set of security levels across clusters. However, it is less flexible than PodSecurityPolicy. Notably, the following features are supported by PodSecurityPolicy but not Pod Security Admission:

Even if Pod Security Admission does not meet all of your needs it was designed to be complementary to other policy enforcement mechanisms, and can provide a useful fallback running alongside other admission webhooks.

Pod Security Admission is controlled by labels on namespaces. This means that anyone who can update (or patch or create) a namespace can also modify the Pod Security level for that namespace, which could be used to bypass a more restrictive policy. Before proceeding, ensure that only trusted, privileged users have these namespace permissions. It is not recommended to grant these powerful permissions to users that shouldn't have elevated permissions, but if you must you will need to use an admission webhook to place additional restrictions on setting Pod Security labels on Namespace objects.

In this section, you will reduce mutating PodSecurityPolicies and remove options that are outside the scope of the Pod Security Standards. You should make the changes recommended here to an offline copy of the original PodSecurityPolicy being modified. The cloned PSP should have a different name that is alphabetically before the original (for example, prepend a 0 to it). Do not create the new policies in Kubernetes yet - that will be covered in the Rollout th

*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
PSP_NAME="original" # Set the name of the PSP you're checking for
kubectl get pods --all-namespaces -o jsonpath="{range .items[?(@.metadata.annotations.kubernetes\.io\/psp=='$PSP_NAME')]}{.metadata.namespace} {.metadata.name}{'\n'}{end}"
```

Example 2 (sh):
```sh
kubectl get pods -n $NAMESPACE -o jsonpath="{.items[*].metadata.annotations.kubernetes\.io\/psp}" | tr " " "\n" | sort -u
```

Example 3 (sh):
```sh
# $LEVEL is the level to dry-run, either "baseline" or "restricted".
kubectl label --dry-run=server --overwrite ns $NAMESPACE pod-security.kubernetes.io/enforce=$LEVEL
```

Example 4 (sh):
```sh
kubectl label --overwrite ns $NAMESPACE pod-security.kubernetes.io/audit=$LEVEL
```

---

## Force Delete StatefulSet Pods

**URL:** https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/

**Contents:**
- Force Delete StatefulSet Pods
- Before you begin
- StatefulSet considerations
- Delete Pods
  - Force Deletion
- What's next
- Feedback

This page shows how to delete Pods which are part of a stateful set, and explains the considerations to keep in mind when doing so.

In normal operation of a StatefulSet, there is never a need to force delete a StatefulSet Pod. The StatefulSet controller is responsible for creating, scaling and deleting members of the StatefulSet. It tries to ensure that the specified number of Pods from ordinal 0 through N-1 are alive and ready. StatefulSet ensures that, at any time, there is at most one Pod with a given identity running in a cluster. This is referred to as at most one semantics provided by a StatefulSet.

Manual force deletion should be undertaken with caution, as it has the potential to violate the at most one semantics inherent to StatefulSet. StatefulSets may be used to run distributed and clustered applications which have a need for a stable network identity and stable storage. These applications often have configuration which relies on an ensemble of a fixed number of members with fixed identities. Having multiple members with the same identity can be disastrous and may lead to data loss (e.g. split brain scenario in quorum-based systems).

You can perform a graceful pod deletion with the following command:

For the above to lead to graceful termination, the Pod must not specify a pod.Spec.TerminationGracePeriodSeconds of 0. The practice of setting a pod.Spec.TerminationGracePeriodSeconds of 0 seconds is unsafe and strongly discouraged for StatefulSet Pods. Graceful deletion is safe and will ensure that the Pod shuts down gracefully before the kubelet deletes the name from the apiserver.

A Pod is not deleted automatically when a node is unreachable. The Pods running on an unreachable Node enter the 'Terminating' or 'Unknown' state after a timeout. Pods may also enter these states when the user attempts graceful deletion of a Pod on an unreachable Node. The only ways in which a Pod in such a state can be removed from the apiserver are as follows:

The recommended best practice is to use the first or second approach. If a Node is confirmed to be dead (e.g. permanently disconnected from the network, powered down, etc), then delete the Node object. If the Node is suffering from a network partition, then try to resolve this or wait for it to resolve. When the partition heals, the kubelet will complete the deletion of the Pod and free up its name in the apiserver.

Normally, the system completes the deletion once the Pod is no longer running on a Node, o

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl delete pods <pod>
```

Example 2 (shell):
```shell
kubectl delete pods <pod> --grace-period=0 --force
```

Example 3 (shell):
```shell
kubectl delete pods <pod> --grace-period=0
```

Example 4 (shell):
```shell
kubectl patch pod <pod> -p '{"metadata":{"finalizers":null}}'
```

---

## Building a Basic DaemonSet

**URL:** https://kubernetes.io/docs/tasks/manage-daemon/create-daemon-set/

**Contents:**
- Building a Basic DaemonSet
- Before you begin
- Define the DaemonSet
- Cleaning up
- What's next
- Feedback

This page demonstrates how to build a basic DaemonSet that runs a Pod on every node in a Kubernetes cluster. It covers a simple use case of mounting a file from the host, logging its contents using an init container, and utilizing a pause container.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

A Kubernetes cluster with at least two nodes (one control plane node and one worker node) to demonstrate the behavior of DaemonSets.

In this task, a basic DaemonSet is created which ensures that the copy of a Pod is scheduled on every node. The Pod will use an init container to read and log the contents of /etc/machine-id from the host, while the main container will be a pause container, which keeps the Pod running.

Create a DaemonSet based on the (YAML) manifest:

Once applied, you can verify that the DaemonSet is running a Pod on every node in the cluster:

The output will list one Pod per node, similar to:

You can inspect the contents of the logged /etc/machine-id file by checking the log directory mounted from the host:

Where <pod-name> is the name of one of your Pods.

To delete the DaemonSet, run this command:

This simple DaemonSet example introduces key components like init containers and host path volumes, which can be expanded upon for more advanced use cases. For more details refer to DaemonSet.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: example-daemonset
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: example
  template:
    metadata:
      labels:
        app.kubernetes.io/name: example
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause
      initContainers:
      - name: log-machine-id
        image: busybox:1.37
        command: ['sh', '-c', 'cat /etc/machine-id > /var/log/machine-id.log']
        volumeMounts:
        - name: machine-id
          mountPath: /etc/machine-id
          readOnly: true
        - name: log-d
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/basic-daemonset.yaml
```

Example 3 (shell):
```shell
kubectl get pods -o wide
```

Example 4 (unknown):
```unknown
NAME                                READY   STATUS    RESTARTS   AGE    IP       NODE
example-daemonset-xxxxx             1/1     Running   0          5m     x.x.x.x  node-1
example-daemonset-yyyyy             1/1     Running   0          5m     x.x.x.x  node-2
```

---

## Delete a StatefulSet

**URL:** https://kubernetes.io/docs/tasks/run-application/delete-stateful-set/

**Contents:**
- Delete a StatefulSet
- Before you begin
- Deleting a StatefulSet
  - Persistent Volumes
    - Note:
  - Complete deletion of a StatefulSet
  - Force deletion of StatefulSet pods
- What's next
- Feedback

This task shows you how to delete a StatefulSet.

You can delete a StatefulSet in the same way you delete other resources in Kubernetes: use the kubectl delete command, and specify the StatefulSet either by file or by name.

You may need to delete the associated headless service separately after the StatefulSet itself is deleted.

When deleting a StatefulSet through kubectl, the StatefulSet scales down to 0. All Pods that are part of this workload are also deleted. If you want to delete only the StatefulSet and not the Pods, use --cascade=orphan. For example:

By passing --cascade=orphan to kubectl delete, the Pods managed by the StatefulSet are left behind even after the StatefulSet object itself is deleted. If the pods have a label app.kubernetes.io/name=MyApp, you can then delete them as follows:

Deleting the Pods in a StatefulSet will not delete the associated volumes. This is to ensure that you have the chance to copy data off the volume before deleting it. Deleting the PVC after the pods have terminated might trigger deletion of the backing Persistent Volumes depending on the storage class and reclaim policy. You should never assume ability to access a volume after claim deletion.

To delete everything in a StatefulSet, including the associated pods, you can run a series of commands similar to the following:

In the example above, the Pods have the label app.kubernetes.io/name=MyApp; substitute your own label as appropriate.

If you find that some pods in your StatefulSet are stuck in the 'Terminating' or 'Unknown' states for an extended period of time, you may need to manually intervene to forcefully delete the pods from the apiserver. This is a potentially dangerous task. Refer to Force Delete StatefulSet Pods for details.

Learn more about force deleting StatefulSet Pods.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl delete -f <file.yaml>
```

Example 2 (shell):
```shell
kubectl delete statefulsets <statefulset-name>
```

Example 3 (shell):
```shell
kubectl delete service <service-name>
```

Example 4 (shell):
```shell
kubectl delete -f <file.yaml> --cascade=orphan
```

---

## Scale a StatefulSet

**URL:** https://kubernetes.io/docs/tasks/run-application/scale-stateful-set/

**Contents:**
- Scale a StatefulSet
- Before you begin
- Scaling StatefulSets
  - Use kubectl to scale StatefulSets
  - Make in-place updates on your StatefulSets
- Troubleshooting
  - Scaling down does not work right
- What's next
- Feedback

This task shows how to scale a StatefulSet. Scaling a StatefulSet refers to increasing or decreasing the number of replicas.

StatefulSets are only available in Kubernetes version 1.5 or later. To check your version of Kubernetes, run kubectl version.

Not all stateful applications scale nicely. If you are unsure about whether to scale your StatefulSets, see StatefulSet concepts or StatefulSet tutorial for further information.

You should perform scaling only when you are confident that your stateful application cluster is completely healthy.

First, find the StatefulSet you want to scale.

Change the number of replicas of your StatefulSet:

Alternatively, you can do in-place updates on your StatefulSets.

If your StatefulSet was initially created with kubectl apply, update .spec.replicas of the StatefulSet manifests, and then do a kubectl apply:

Otherwise, edit that field with kubectl edit:

Or use kubectl patch:

You cannot scale down a StatefulSet when any of the stateful Pods it manages is unhealthy. Scaling down only takes place after those stateful Pods become running and ready.

If spec.replicas > 1, Kubernetes cannot determine the reason for an unhealthy Pod. It might be the result of a permanent fault or of a transient fault. A transient fault can be caused by a restart required by upgrading or maintenance.

If the Pod is unhealthy due to a permanent fault, scaling without correcting the fault may lead to a state where the StatefulSet membership drops below a certain minimum number of replicas that are needed to function correctly. This may cause your StatefulSet to become unavailable.

If the Pod is unhealthy due to a transient fault and the Pod might become available again, the transient error may interfere with your scale-up or scale-down operation. Some distributed databases have issues when nodes join and leave at the same time. It is better to reason about scaling operations at the application level in these cases, and perform scaling only when you are sure that your stateful application cluster is completely healthy.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

**Examples:**

Example 1 (shell):
```shell
kubectl get statefulsets <stateful-set-name>
```

Example 2 (shell):
```shell
kubectl scale statefulsets <stateful-set-name> --replicas=<new-replicas>
```

Example 3 (shell):
```shell
kubectl apply -f <stateful-set-file-updated>
```

Example 4 (shell):
```shell
kubectl edit statefulsets <stateful-set-name>
```

---

## StatefulSet Basics

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/

**Contents:**
- StatefulSet Basics
- Before you begin
    - Note:
- Objectives
- Creating a StatefulSet
  - Ordered Pod creation
    - Note:
- Pods in a StatefulSet
  - Examining the Pod's ordinal index
  - Using stable network identities

This tutorial provides an introduction to managing applications with StatefulSets. It demonstrates how to create, delete, scale, and update the Pods of StatefulSets.

Before you begin this tutorial, you should familiarize yourself with the following Kubernetes concepts:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You should configure kubectl to use a context that uses the default namespace. If you are using an existing cluster, make sure that it's OK to use that cluster's default namespace to practice. Ideally, practice in a cluster that doesn't run any real workloads.

It's also useful to read the concept page about StatefulSets.

StatefulSets are intended to be used with stateful applications and distributed systems. However, the administration of stateful applications and distributed systems on Kubernetes is a broad, complex topic. In order to demonstrate the basic features of a StatefulSet, and not to conflate the former topic with the latter, you will deploy a simple web application using a StatefulSet.

After this tutorial, you will be familiar with the following.

Begin by creating a StatefulSet (and the Service that it relies upon) using the example below. It is similar to the example presented in the StatefulSets concept. It creates a headless Service, nginx, to publish the IP addresses of Pods in the StatefulSet, web.

You will need to use at least two terminal windows. In the first terminal, use kubectl get to watch the creation of the StatefulSet's Pods.

In the second terminal, use kubectl apply to create the headless Service and StatefulSet:

The command above creates two Pods, each running an NGINX webserver. Get the nginx Service...

...then get the web StatefulSet, to verify that both were created successfully:

A StatefulSet defaults to creating its Pods in a strict order.

For a StatefulSet with n replicas, when Pods are being deployed, they are created sequentially, ordered from {0..n-1}. Examine the output of the kubectl get command in the first terminal. Eventually, the output will look like the example below.

Notice that the web-1 Pod is not launched until the web-0 Pod is Running (see Pod Phase) and Ready (

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
  serviceName: "nginx"
  replicas: 2
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
        image: registry.k8s.io/nginx-slim:0.21
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: www
          mountPath: /u
...
```

Example 2 (shell):
```shell
# use this terminal to run commands that specify --watch
# end this watch when you are asked to start a new watch
kubectl get pods --watch -l app=nginx
```

Example 3 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/web/web.yaml
```

Example 4 (unknown):
```unknown
service/nginx created
statefulset.apps/web created
```

---

## Control CPU Management Policies on the Node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/#windows-support

**Contents:**
- Control CPU Management Policies on the Node
- Before you begin
- Configuring CPU management policies
- Windows Support
- Configuration
- Changing the CPU Manager Policy
    - Note:
  - none policy configuration
  - static policy configuration
    - Note:

Kubernetes keeps many aspects of how pods execute on nodes abstracted from the user. This is by design. However, some workloads require stronger guarantees in terms of latency and/or performance in order to operate acceptably. The kubelet provides methods to enable more complex workload placement policies while keeping the abstraction free from explicit placement directives.

For detailed information on resource management, please refer to the Resource Management for Pods and Containers documentation.

For detailed information on how the kubelet implements resource management, please refer to the Node ResourceManagers documentation.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.26.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

If you are running an older version of Kubernetes, please look at the documentation for the version you are actually running.

By default, the kubelet uses CFS quota to enforce pod CPU limits. When the node runs many CPU-bound pods, the workload can move to different CPU cores depending on whether the pod is throttled and which CPU cores are available at scheduling time. Many workloads are not sensitive to this migration and thus work fine without any intervention.

However, in workloads where CPU cache affinity and scheduling latency significantly affect workload performance, the kubelet allows alternative CPU management policies to determine some placement preferences on the node.

CPU Manager support can be enabled on Windows by using the WindowsCPUAndMemoryAffinity feature gate and it requires support in the container runtime. Once the feature gate is enabled, follow the steps below to conf

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
could not restore state from checkpoint: configured policy "static" differs from state checkpoint policy "none", please drain this node and delete the CPU manager checkpoint file "/var/lib/kubelet/cpu_manager_state" before restarting Kubelet
```

---

## Restrict a Container's Syscalls with seccomp

**URL:** https://kubernetes.io/docs/tutorials/security/seccomp/

**Contents:**
- Restrict a Container's Syscalls with seccomp
- Objectives
- Before you begin
    - Note:
- Download example seccomp profiles
- Create a local Kubernetes cluster with kind
- Create a Pod that uses the container runtime default seccomp profile
    - Note:
- Create a Pod with a seccomp profile for syscall auditing
    - Note:

Seccomp stands for secure computing mode and has been a feature of the Linux kernel since version 2.6.12. It can be used to sandbox the privileges of a process, restricting the calls it is able to make from userspace into the kernel. Kubernetes lets you automatically apply seccomp profiles loaded onto a node to your Pods and containers.

Identifying the privileges required for your workloads can be difficult. In this tutorial, you will go through how to load seccomp profiles into a local Kubernetes cluster, how to apply them to a Pod, and how you can begin to craft profiles that give only the necessary privileges to your container processes.

In order to complete all steps in this tutorial, you must install kind and kubectl.

The commands used in the tutorial assume that you are using Docker as your container runtime. (The cluster that kind creates may use a different container runtime internally). You could also use Podman but in that case, you would have to follow specific instructions in order to complete the tasks successfully.

This tutorial shows some examples that are still beta (since v1.25) and others that use only generally available seccomp functionality. You should make sure that your cluster is configured correctly for the version you are using.

The tutorial also uses the curl tool for downloading examples to your computer. You can adapt the steps to use a different tool if you prefer.

The contents of these profiles will be explored later on, but for now go ahead and download them into a directory named profiles/ so that they can be loaded into the cluster.

pods/security/seccomp/profiles/audit.json { "defaultAction": "SCMP_ACT_LOG" }

pods/security/seccomp/profiles/violation.json { "defaultAction": "SCMP_ACT_ERRNO" }

pods/security/seccomp/profiles/fine-grained.json { "defaultAction": "SCMP_ACT_ERRNO", "architectures": [ "SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32" ], "syscalls": [ { "names": [ "accept4", "epoll_wait", "pselect6", "futex", "madvise", "epoll_ctl", "getsockname", "setsockopt", "vfork", "mmap", "read", "write", "close", "arch_prctl", "sched_getaffinity", "munmap", "brk", "rt_sigaction", "rt_sigprocmask", "sigaltstack", "gettid", "clone", "bind", "socket", "openat", "readlinkat", "exit_group", "epoll_create1", "listen", "rt_sigreturn", "sched_yield", "clock_gettime", "connect", "dup2", "epoll_pwait", "execve", "exit", "fcntl", "getpid", "getuid", "ioctl", "mprotect", "nanosleep", "open", "poll", "recvfrom", "sendto", "s

*[Content truncated]*

**Examples:**

Example 1 (json):
```json
{
    "defaultAction": "SCMP_ACT_LOG"
}
```

Example 2 (json):
```json
{
    "defaultAction": "SCMP_ACT_ERRNO"
}
```

Example 3 (json):
```json
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": [
        "SCMP_ARCH_X86_64",
        "SCMP_ARCH_X86",
        "SCMP_ARCH_X32"
    ],
    "syscalls": [
        {
            "names": [
                "accept4",
                "epoll_wait",
                "pselect6",
                "futex",
                "madvise",
                "epoll_ctl",
                "getsockname",
                "setsockopt",
                "vfork",
                "mmap",
                "read",
                "write",
                "close",
                "arch_prctl",
                "sche
...
```

Example 4 (shell):
```shell
mkdir ./profiles
curl -L -o profiles/audit.json https://k8s.io/examples/pods/security/seccomp/profiles/audit.json
curl -L -o profiles/violation.json https://k8s.io/examples/pods/security/seccomp/profiles/violation.json
curl -L -o profiles/fine-grained.json https://k8s.io/examples/pods/security/seccomp/profiles/fine-grained.json
ls profiles
```

---

## Assign Memory Resources to Containers and Pods

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/

**Contents:**
- Assign Memory Resources to Containers and Pods
- Before you begin
- Create a namespace
- Specify a memory request and a memory limit
- Exceed a Container's memory limit
- Specify a memory request that is too big for your Nodes
- Memory units
- If you do not specify a memory limit
- Motivation for memory requests and limits
- Clean up

This page shows how to assign a memory request and a memory limit to a Container. A Container is guaranteed to have as much memory as it requests, but is not allowed to use more memory than its limit.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Each node in your cluster must have at least 300 MiB of memory.

A few of the steps on this page require you to run the metrics-server service in your cluster. If you have the metrics-server running, you can skip those steps.

If you are running Minikube, run the following command to enable the metrics-server:

To see whether the metrics-server is running, or another provider of the resource metrics API (metrics.k8s.io), run the following command:

If the resource metrics API is available, the output includes a reference to metrics.k8s.io.

Create a namespace so that the resources you create in this exercise are isolated from the rest of your cluster.

To specify a memory request for a Container, include the resources:requests field in the Container's resource manifest. To specify a memory limit, include resources:limits.

In this exercise, you create a Pod that has one Container. The Container has a memory request of 100 MiB and a memory limit of 200 MiB. Here's the configuration file for the Pod:

The args section in the configuration file provides arguments for the Container when it starts. The "--vm-bytes", "150M" arguments tell the Container to attempt to allocate 150 MiB of memory.

Verify that the Pod Container is running:

View detailed information about the Pod:

The output shows that the one Container in the Pod has a memory request of 100 MiB and a memory limit of 200 MiB.

R

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube addons enable metrics-server
```

Example 2 (shell):
```shell
kubectl get apiservices
```

Example 3 (shell):
```shell
NAME
v1beta1.metrics.k8s.io
```

Example 4 (shell):
```shell
kubectl create namespace mem-example
```

---

## Control CPU Management Policies on the Node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/

**Contents:**
- Control CPU Management Policies on the Node
- Before you begin
- Configuring CPU management policies
- Windows Support
- Configuration
- Changing the CPU Manager Policy
    - Note:
  - none policy configuration
  - static policy configuration
    - Note:

Kubernetes keeps many aspects of how pods execute on nodes abstracted from the user. This is by design. However, some workloads require stronger guarantees in terms of latency and/or performance in order to operate acceptably. The kubelet provides methods to enable more complex workload placement policies while keeping the abstraction free from explicit placement directives.

For detailed information on resource management, please refer to the Resource Management for Pods and Containers documentation.

For detailed information on how the kubelet implements resource management, please refer to the Node ResourceManagers documentation.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.26.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

If you are running an older version of Kubernetes, please look at the documentation for the version you are actually running.

By default, the kubelet uses CFS quota to enforce pod CPU limits. When the node runs many CPU-bound pods, the workload can move to different CPU cores depending on whether the pod is throttled and which CPU cores are available at scheduling time. Many workloads are not sensitive to this migration and thus work fine without any intervention.

However, in workloads where CPU cache affinity and scheduling latency significantly affect workload performance, the kubelet allows alternative CPU management policies to determine some placement preferences on the node.

CPU Manager support can be enabled on Windows by using the WindowsCPUAndMemoryAffinity feature gate and it requires support in the container runtime. Once the feature gate is enabled, follow the steps below to conf

*[Content truncated]*

**Examples:**

Example 1 (unknown):
```unknown
could not restore state from checkpoint: configured policy "static" differs from state checkpoint policy "none", please drain this node and delete the CPU manager checkpoint file "/var/lib/kubelet/cpu_manager_state" before restarting Kubelet
```

---

## Troubleshooting Applications

**URL:** https://kubernetes.io/docs/tasks/debug/debug-application/

**Contents:**
- Troubleshooting Applications
      - Debug Pods
      - Debug Services
      - Debug a StatefulSet
      - Determine the Reason for Pod Failure
      - Debug Init Containers
      - Debug Running Pods
      - Get a Shell to a Running Container
- Feedback

This doc contains a set of resources for fixing issues with containerized applications. It covers things like common issues with Kubernetes resources (like Pods, Services, or StatefulSets), advice on making sense of container termination messages, and ways to debug running containers.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Viewing Pods and Nodes

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/explore/explore-intro/

**Contents:**
- Viewing Pods and Nodes
- Objectives
- Kubernetes Pods
  - Pods overview
- Nodes
  - Nodes overview
- Troubleshooting with kubectl
  - Check application configuration
    - Note:
  - Show the app in the terminal

When you created a Deployment in Module 2, Kubernetes created a Pod to host your application instance. A Pod is a Kubernetes abstraction that represents a group of one or more application containers (such as Docker), and some shared resources for those containers. Those resources include:

A Pod models an application-specific "logical host" and can contain different application containers which are relatively tightly coupled. For example, a Pod might include both the container with your Node.js app as well as a different container that feeds the data to be published by the Node.js webserver. The containers in a Pod share an IP Address and port space, are always co-located and co-scheduled, and run in a shared context on the same Node.

Pods are the atomic unit on the Kubernetes platform. When we create a Deployment on Kubernetes, that Deployment creates Pods with containers inside them (as opposed to creating containers directly). Each Pod is tied to the Node where it is scheduled, and remains there until termination (according to restart policy) or deletion. In case of a Node failure, identical Pods are scheduled on other available Nodes in the cluster.

A Pod always runs on a Node. A Node is a worker machine in Kubernetes and may be either a virtual or a physical machine, depending on the cluster. Each Node is managed by the control plane. A Node can have multiple pods, and the Kubernetes control plane automatically handles scheduling the pods across the Nodes in the cluster. The control plane's automatic scheduling takes into account the available resources on each Node.

Every Kubernetes Node runs at least:

Kubelet, a process responsible for communication between the Kubernetes control plane and the Node; it manages the Pods and the containers running on a machine.

A container runtime (like Docker) responsible for pulling the container image from a registry, unpacking the container, and running the application.

In Module 2, you used the kubectl command-line interface. You'll continue to use it in Module 3 to get information about deployed applications and their environments. The most common operations can be done with the following kubectl subcommands:

You can use these commands to see when applications were deployed, what their current statuses are, where they are running and what their configurations are.

Now that we know more about our cluster components and the command line, let's explore our application.

Let's verify that the application we 

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get pods
```

Example 2 (shell):
```shell
kubectl describe pods
```

Example 3 (shell):
```shell
kubectl proxy
```

Example 4 (shell):
```shell
export POD_NAME="$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')"
echo Name of the Pod: $POD_NAME
```

---

## Configure Quality of Service for Pods

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/

**Contents:**
- Configure Quality of Service for Pods
- Before you begin
- Create a namespace
- Create a Pod that gets assigned a QoS class of Guaranteed
    - Note:
    - Clean up
- Create a Pod that gets assigned a QoS class of Burstable
    - Clean up
- Create a Pod that gets assigned a QoS class of BestEffort
    - Clean up

This page shows how to configure Pods so that they will be assigned particular Quality of Service (QoS) classes. Kubernetes uses QoS classes to make decisions about evicting Pods when Node resources are exceeded.

When Kubernetes creates a Pod it assigns one of these QoS classes to the Pod:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

You also need to be able to create and delete namespaces.

Create a namespace so that the resources you create in this exercise are isolated from the rest of your cluster.

For a Pod to be given a QoS class of Guaranteed:

These restrictions apply to init containers and app containers equally. Ephemeral containers cannot define resources so these restrictions do not apply.

Here is a manifest for a Pod that has one Container. The Container has a memory limit and a memory request, both equal to 200 MiB. The Container has a CPU limit and a CPU request, both equal to 700 milliCPU:

View detailed information about the Pod:

The output shows that Kubernetes gave the Pod a QoS class of Guaranteed. The output also verifies that the Pod Container has a memory request that matches its memory limit, and it has a CPU request that matches its CPU limit.

A Pod is given a QoS class of Burstable if:

Here is a manifest for a Pod that has one Container. The Container has a memory limit of 200 MiB and a memory request of 100 MiB.

View detailed information about the Pod:

The output shows that Kubernetes gave the Pod a QoS class of Burstable:

For a Pod to be given a QoS class of BestEffort, the Containers in the Pod must not have any memory or CPU limits or requests.

Here is a manifest for a Pod that has one Container. The Container has no memory or CPU limits or requests:

View detailed information about the Pod:

The output shows that Kubernetes gave the Pod a QoS class of BestEffort:

Here is a manifest for a Pod that has two Containers. One container specifies a memory request of 200 MiB. The other Container does not specify any requests or limits.

Notice that this Pod meets the criteria for QoS class Burstable. That is, it does not meet the criteria for QoS class Guaranteed, and one of its Containers has a mem

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create namespace qos-example
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: qos-demo
  namespace: qos-example
spec:
  containers:
  - name: qos-demo-ctr
    image: nginx
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
kubectl apply -f https://k8s.io/examples/pods/qos/qos-pod.yaml --namespace=qos-example
```

Example 4 (shell):
```shell
kubectl get pod qos-demo --namespace=qos-example --output=yaml
```

---
