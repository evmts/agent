# Kubernetes - Services

**Pages:** 19

---

## Use a Service to Access an Application in a Cluster

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/service-access-application-cluster/

**Contents:**
- Use a Service to Access an Application in a Cluster
- Before you begin
- Objectives
- Creating a service for an application running in two pods
- Using a service configuration file
- Cleaning up
- What's next
- Feedback

This page shows how to create a Kubernetes Service object that external clients can use to access an application running in a cluster. The Service provides load balancing for an application that has two running instances.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Here is the configuration file for the application Deployment:

Run a Hello World application in your cluster: Create the application Deployment using the file above:

The preceding command creates a Deployment and an associated ReplicaSet. The ReplicaSet has two Pods each of which runs the Hello World application.

Display information about the Deployment:

Display information about your ReplicaSet objects:

Create a Service object that exposes the deployment:

Display information about the Service:

The output is similar to this:

Make a note of the NodePort value for the Service. For example, in the preceding output, the NodePort value is 31496.

List the pods that are running the Hello World application:

The output is similar to this:

Get the public IP address of one of your nodes that is running a Hello World pod. How you get this address depends on how you set up your cluster. For example, if you are using Minikube, you can see the node address by running kubectl cluster-info. If you are using Google Compute Engine instances, you can use the gcloud compute instances list command to see the public addresses of your nodes.

On your chosen node, create a firewall rule that allows TCP traffic on your node port. For example, if your Service has a NodePort value of 31568, create a firewall rule that allows TCP traffic on port 31568. Different cloud providers offer different ways of configuring firewall rules.

Use the node address and node port to access the Hello World application:

where <public-node-ip> is the public IP address of your node, and <node-port> is the NodePort value for your service. The response to a successful request is a hello message:

As an alternative to using kubectl expose, you can use a service configuration file to create a Service.

To delete the Service, enter this command:

To delete the Deployment, the ReplicaSet, and the Pods that are ru

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
spec:
  selector:
    matchLabels:
      run: load-balancer-example
  replicas: 2
  template:
    metadata:
      labels:
        run: load-balancer-example
    spec:
      containers:
        - name: hello-world
          image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:2.0
          ports:
            - containerPort: 8080
              protocol: TCP
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/service/access/hello-application.yaml
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

## Expose Pod Information to Containers Through Environment Variables

**URL:** https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/

**Contents:**
- Expose Pod Information to Containers Through Environment Variables
- Before you begin
- Use Pod fields as values for environment variables
    - Note:
- Use container fields as values for environment variables
- What's next
- Feedback

This page shows how a Pod can use environment variables to expose information about itself to containers running in the Pod, using the downward API. You can use environment variables to expose Pod fields, container fields, or both.

In Kubernetes, there are two ways to expose Pod and container fields to a running container:

Together, these two ways of exposing Pod and container fields are called the downward API.

As Services are the primary mode of communication between containerized applications managed by Kubernetes, it is helpful to be able to discover them at runtime.

Read more about accessing Services here.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

In this part of exercise, you create a Pod that has one container, and you project Pod-level fields into the running container as environment variables.

In that manifest, you can see five environment variables. The env field is an array of environment variable definitions. The first element in the array specifies that the MY_NODE_NAME environment variable gets its value from the Pod's spec.nodeName field. Similarly, the other environment variables get their names from Pod fields.

Verify that the container in the Pod is running:

View the container's logs:

The output shows the values of selected environment variables:

To see why these values are in the log, look at the command and args fields in the configuration file. When the container starts, it writes the values of five environment variables to stdout. It repeats this every ten seconds.

Next, get a shell into the container that is running in your Pod:

In your shell, view the environment variables:

The output shows that certain environment variables have been assigned the values of Pod fields:

In the preceding exercise, you used information from Pod-level fields as the values for environment variables. In this next exercise, you are going to pass fields that are part of the Pod definition, but taken from the specific container rather than from the Pod overall.

Here is a manifest for another Pod that again has just one container:

In this manifest, you can see four environment variables. The env field is an array of e

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dapi-envars-fieldref
spec:
  containers:
    - name: test-container
      image: registry.k8s.io/busybox:1.27.2
      command: [ "sh", "-c"]
      args:
      - while true; do
          echo -en '\n';
          printenv MY_NODE_NAME MY_POD_NAME MY_POD_NAMESPACE;
          printenv MY_POD_IP MY_POD_SERVICE_ACCOUNT;
          sleep 10;
        done;
      env:
        - name: MY_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/pods/inject/dapi-envars-pod.yaml
```

Example 3 (shell):
```shell
# If the new Pod isn't yet healthy, rerun this command a few times.
kubectl get pods
```

Example 4 (shell):
```shell
kubectl logs dapi-envars-fieldref
```

---

## Create an External Load Balancer

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/

**Contents:**
- Create an External Load Balancer
- Before you begin
- Create a Service
  - Create a Service from a manifest
  - Create a Service using kubectl
- Finding your IP address
    - Note:
- Preserving the client source IP
  - Caveats and limitations when preserving source IPs
- Garbage collecting load balancers

This page shows how to create an external load balancer.

When creating a Service, you have the option of automatically creating a cloud load balancer. This provides an externally-accessible IP address that sends traffic to the correct port on your cluster nodes, provided your cluster runs in a supported environment and is configured with the correct cloud load balancer provider package.

You can also use an Ingress in place of Service. For more information, check the Ingress documentation.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Your cluster must be running in a cloud or other environment that already has support for configuring external load balancers.

To create an external load balancer, add the following line to your Service manifest:

Your manifest might then look like:

You can alternatively create the service with the kubectl expose command and its --type=LoadBalancer flag:

This command creates a new Service using the same selectors as the referenced resource (in the case of the example above, a Deployment named example).

For more information, including optional flags, refer to the kubectl expose reference.

You can find the IP address created for your service by getting the service information through kubectl:

which should produce output similar to:

The load balancer's IP address is listed next to LoadBalancer Ingress.

If you are running your service on Minikube, you can find the assigned IP address and port with:

By default, the source IP seen in the target container is not the original source IP of the client. To enable preservation of the client IP, the following fields can be configured in the .spec of the Service:

Setting externalTrafficPolicy to Local in the Service manifest activates this feature. For example:

Load balancing services from some cloud providers do not let you configure different weights for each target.

With each target weighted equally in terms of sending traffic to Nodes, external traffic is not equally load balanced across different Pods. The external load balancer is unaware of the number of Pods on each node that are used as a target.

Where NumServicePods << NumNodes or NumServicePo

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
type: LoadBalancer
```

Example 2 (yaml):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: example-service
spec:
  selector:
    app: example
  ports:
    - port: 8765
      targetPort: 9376
  type: LoadBalancer
```

Example 3 (bash):
```bash
kubectl expose deployment example --port=8765 --target-port=9376 \
        --name=example-service --type=LoadBalancer
```

Example 4 (bash):
```bash
kubectl describe services example-service
```

---

## Access Services Running on Clusters

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster-services/

**Contents:**
- Access Services Running on Clusters
- Before you begin
- Accessing services running on the cluster
  - Ways to connect
  - Discovering builtin services
    - Note:
    - Manually constructing apiserver proxy URLs
      - Examples
    - Using web browsers to access services running on the cluster
- Feedback

This page shows how to connect to services running on the Kubernetes cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

In Kubernetes, nodes, pods and services all have their own IPs. In many cases, the node IPs, pod IPs, and some service IPs on a cluster will not be routable, so they will not be reachable from a machine outside the cluster, such as your desktop machine.

You have several options for connecting to nodes, pods and services from outside the cluster:

Typically, there are several services which are started on a cluster by kube-system. Get a list of these with the kubectl cluster-info command:

The output is similar to this:

This shows the proxy-verb URL for accessing each service. For example, this cluster has cluster-level logging enabled (using Elasticsearch), which can be reached at https://192.0.2.1/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy/ if suitable credentials are passed, or through a kubectl proxy at, for example: http://localhost:8080/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy/.

As mentioned above, you use the kubectl cluster-info command to retrieve the service's proxy URL. To create proxy URLs that include service endpoints, suffixes, and parameters, you append to the service's proxy URL: http://kubernetes_master_address/api/v1/namespaces/namespace_name/services/[https:]service_name[:port_name]/proxy

If you haven't specified a name for your port, you don't have to specify port_name in the URL. You can also use the port number in place of the port_name for both named and unnamed ports.

By default, the API server proxies to your service using HTTP.

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl cluster-info
```

Example 2 (unknown):
```unknown
Kubernetes master is running at https://192.0.2.1
elasticsearch-logging is running at https://192.0.2.1/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy
kibana-logging is running at https://192.0.2.1/api/v1/namespaces/kube-system/services/kibana-logging/proxy
kube-dns is running at https://192.0.2.1/api/v1/namespaces/kube-system/services/kube-dns/proxy
grafana is running at https://192.0.2.1/api/v1/namespaces/kube-system/services/monitoring-grafana/proxy
heapster is running at https://192.0.2.1/api/v1/namespaces/kube-system/services/monitoring-heapster/proxy
```

Example 3 (unknown):
```unknown
http://192.0.2.1/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy/_search?q=user:kimchy
```

Example 4 (unknown):
```unknown
https://192.0.2.1/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy/_cluster/health?pretty=true
```

---

## Using CoreDNS for Service Discovery

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/coredns/

**Contents:**
- Using CoreDNS for Service Discovery
- Before you begin
- About CoreDNS
- Installing CoreDNS
- Migrating to CoreDNS
  - Upgrading an existing cluster with kubeadm
- Upgrading CoreDNS
- Tuning CoreDNS
- What's next
- Feedback

This page describes the CoreDNS upgrade process and how to install CoreDNS instead of kube-dns.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.9.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

CoreDNS is a flexible, extensible DNS server that can serve as the Kubernetes cluster DNS. Like Kubernetes, the CoreDNS project is hosted by the CNCF.

You can use CoreDNS instead of kube-dns in your cluster by replacing kube-dns in an existing deployment, or by using tools like kubeadm that will deploy and upgrade the cluster for you.

For manual deployment or replacement of kube-dns, see the documentation at the CoreDNS website.

In Kubernetes version 1.21, kubeadm removed its support for kube-dns as a DNS application. For kubeadm v1.34, the only supported cluster DNS application is CoreDNS.

You can move to CoreDNS when you use kubeadm to upgrade a cluster that is using kube-dns. In this case, kubeadm generates the CoreDNS configuration ("Corefile") based upon the kube-dns ConfigMap, preserving configurations for stub domains, and upstream name server.

You can check the version of CoreDNS that kubeadm installs for each version of Kubernetes in the page CoreDNS version in Kubernetes.

CoreDNS can be upgraded manually in case you want to only upgrade CoreDNS or use your own custom image. There is a helpful guideline and walkthrough available to ensure a smooth upgrade. Make sure the existing CoreDNS configuration ("Corefile") is retained when upgrading your cluster.

If you are upgrading your cluster using the kubeadm tool, kubeadm can take care of retaining the existing CoreDNS configuration automatically.

When resource utili

*[Content truncated]*

---

## Autoscale the DNS Service in a Cluster

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/dns-horizontal-autoscaling/

**Contents:**
- Autoscale the DNS Service in a Cluster
- Before you begin
- Determine whether DNS horizontal autoscaling is already enabled
- Get the name of your DNS Deployment
    - Note:
- Enable DNS horizontal autoscaling
- Tune DNS autoscaling parameters
- Disable DNS horizontal autoscaling
  - Option 1: Scale down the kube-dns-autoscaler deployment to 0 replicas
  - Option 2: Delete the kube-dns-autoscaler deployment

This page shows how to enable and configure autoscaling of the DNS service in your Kubernetes cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

This guide assumes your nodes use the AMD64 or Intel 64 CPU architecture.

Make sure Kubernetes DNS is enabled.

List the Deployments in your cluster in the kube-system namespace:

The output is similar to this:

If you see "kube-dns-autoscaler" in the output, DNS horizontal autoscaling is already enabled, and you can skip to Tuning autoscaling parameters.

List the DNS deployments in your cluster in the kube-system namespace:

The output is similar to this:

If you don't see a Deployment for DNS services, you can also look for it by name:

and look for a deployment named coredns or kube-dns.

where <your-deployment-name> is the name of your DNS Deployment. For example, if the name of your Deployment for DNS is coredns, your scale target is Deployment/coredns.

In this section, you create a new Deployment. The Pods in the Deployment run a container based on the cluster-proportional-autoscaler-amd64 image.

Create a file named dns-horizontal-autoscaler.yaml with this content:

In the file, replace <SCALE_TARGET> with your scale target.

Go to the directory that contains your configuration file, and enter this command to create the Deployment:

The output of a successful command is:

DNS horizontal autoscaling is now enabled.

Verify that the kube-dns-autoscaler ConfigMap exists:

The output is similar to this:

Modify the data in the ConfigMap:

Modify the fields according to your needs. The "min" field indicates the minimal number of DNS backends. The actual number of backends is ca

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get deployment --namespace=kube-system
```

Example 2 (unknown):
```unknown
NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
...
kube-dns-autoscaler    1/1     1            1           ...
...
```

Example 3 (shell):
```shell
kubectl get deployment -l k8s-app=kube-dns --namespace=kube-system
```

Example 4 (unknown):
```unknown
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
...
coredns   2/2     2            2           ...
...
```

---

## Kubernetes Default Service CIDR Reconfiguration

**URL:** https://kubernetes.io/docs/tasks/network/reconfigure-default-service-ip-ranges/

**Contents:**
- Kubernetes Default Service CIDR Reconfiguration
- Before you begin
- Kubernetes Default Service CIDR Reconfiguration
  - Kubernetes Service CIDR Reconfiguration Categories
  - Manual Operations for Replacing the Default Service CIDR
  - Illustrative Reconfiguration Steps
- What's next
- Feedback

This document shares how to reconfigure the default Service IP range(s) assigned to a cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

This document explains how to manage the Service IP address range within a Kubernetes cluster, which also influences the cluster's supported IP families for Services.

The IP families available for Service ClusterIPs are determined by the --service-cluster-ip-range flag to kube-apiserver. For a better understanding of Service IP address allocation, refer to the Services IP address allocation tracking documentation.

Since Kubernetes 1.33, the Service IP families configured for the cluster are reflected by the ServiceCIDR object named kubernetes. The kubernetes ServiceCIDR object is created by the first kube-apiserver instance that starts, based on its configured --service-cluster-ip-range flag. To ensure consistent cluster behavior, all kube-apiserver instances must be configured with the same --service-cluster-ip-range values, which must match the default kubernetes ServiceCIDR object.

We can categorize Service CIDR reconfiguration into the following scenarios:

Extending the existing Service CIDRs: This can be done dynamically by adding new ServiceCIDR objects without the need of reconfiguration of the kube-apiserver. Please refer to the dedicated documentation on Extending Service IP Ranges.

Single-to-dual-stack conversion preserving the primary service CIDR: This involves introducing a secondary IP family (IPv6 to an IPv4-only cluster, or IPv4 to an IPv6-only cluster) while keeping the original IP family as primary. This requires an update to the kube-apiserver configuration and a corresponding modification of various cluster components that need to handle this additional IP family. These components include, but are not limited to, kube-proxy, the CNI or network plugin, service mesh implementations, and DNS services.

Dual-to-single conversion preserving the primary service CIDR: This involves removing the secondary IP family from a dual-stack cluster, reverting to a single IP family while retaining the original primary IP family. In addition t

*[Content truncated]*

---

## Control Topology Management Policies on a node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/#topology-manager-policy-options

**Contents:**
- Control Topology Management Policies on a node
- Before you begin
- How topology manager works
- Windows Support
- Topology manager scopes and policies
    - Note:
    - Note:
- Topology manager scopes
  - container scope
  - pod scope

An increasing number of systems leverage a combination of CPUs and hardware accelerators to support latency-critical execution and high-throughput parallel computation. These include workloads in fields such as telecommunications, scientific computing, machine learning, financial services and data analytics. Such hybrid systems comprise a high performance environment.

In order to extract the best performance, optimizations related to CPU isolation, memory and device locality are required. However, in Kubernetes, these optimizations are handled by a disjoint set of components.

Topology Manager is a kubelet component that aims to coordinate the set of components that are responsible for these optimizations.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.18.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Prior to the introduction of Topology Manager, the CPU and Device Manager in Kubernetes make resource allocation decisions independently of each other. This can result in undesirable allocations on multiple-socketed systems, and performance/latency sensitive applications will suffer due to these undesirable allocations. Undesirable in this case meaning, for example, CPUs and devices being allocated from different NUMA Nodes, thus incurring additional latency.

The Topology Manager is a kubelet component, which acts as a source of truth so that other kubelet components can make topology aligned resource allocation choices.

The Topology Manager provides an interface for components, called Hint Providers, to send and receive topology information. The Topology Manager has a set of node level policies which are explained be

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

## Learn Kubernetes Basics

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/

**Contents:**
- Learn Kubernetes Basics
- Objectives
- What can Kubernetes do for you?
- Kubernetes Basics Modules
      - 1. Create a Kubernetes cluster
      - 2. Deploy an app
      - 3. Explore your app
      - 4. Expose your app publicly
      - 5. Scale up your app
      - 6. Update your app

This tutorial provides a walkthrough of the basics of the Kubernetes cluster orchestration system. Each module contains some background information on major Kubernetes features and concepts, and a tutorial for you to follow along.

Using the tutorials, you can learn to:

With modern web services, users expect applications to be available 24/7, and developers expect to deploy new versions of those applications several times a day. Containerization helps package software to serve these goals, enabling applications to be released and updated without downtime. Kubernetes helps you make sure those containerized applications run where and when you want, and helps them find the resources and tools they need to work. Kubernetes is a production-ready, open source platform designed with Google's accumulated experience in container orchestration, combined with best-of-breed ideas from the community.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Create a Windows HostProcess Pod

**URL:** https://kubernetes.io/docs/tasks/configure-pod-container/create-hostprocess-pod/

**Contents:**
- Create a Windows HostProcess Pod
  - When should I use a Windows HostProcess container?
- Before you begin
- Limitations
- HostProcess Pod configuration requirements
  - Example manifest (excerpt)
- Volume mounts
  - Containerd v1.6
  - Containerd v1.7 (and greater)
- Resource limits

Windows HostProcess containers enable you to run containerized workloads on a Windows host. These containers operate as normal processes but have access to the host network namespace, storage, and devices when given the appropriate user privileges. HostProcess containers can be used to deploy network plugins, storage configurations, device plugins, kube-proxy, and other components to Windows nodes without the need for dedicated proxies or the direct installation of host services.

Administrative tasks such as installation of security patches, event log collection, and more can be performed without requiring cluster operators to log onto each Windows node. HostProcess containers can run as any user that is available on the host or is in the domain of the host machine, allowing administrators to restrict resource access through user permissions. While neither filesystem or process isolation are supported, a new volume is created on the host upon starting the container to give it a clean and consolidated workspace. HostProcess containers can also be built on top of existing Windows base images and do not inherit the same compatibility requirements as Windows server containers, meaning that the version of the base images does not need to match that of the host. It is, however, recommended that you use the same base image version as your Windows Server container workloads to ensure you do not have any unused images taking up space on the node. HostProcess containers also support volume mounts within the container volume.

This task guide is specific to Kubernetes v1.34. If you are not running Kubernetes v1.34, check the documentation for that version of Kubernetes.

In Kubernetes 1.34, the HostProcess container feature is enabled by default. The kubelet will communicate with containerd directly by passing the hostprocess flag via CRI. You can use the latest version of containerd (v1.6+) to run HostProcess containers. How to install containerd.

These limitations are relevant for Kubernetes v1.34:

Enabling a Windows HostProcess pod requires setting the right configurations in the pod security configuration. Of the policies defined in the Pod Security Standards HostProcess pods are disallowed by the baseline and restricted policies. It is therefore recommended that HostProcess pods run in alignment with the privileged profile.

When running under the privileged policy, here are the configurations which need to be set to enable the creation of a HostProcess pod:


*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
spec:
  securityContext:
    windowsOptions:
      hostProcess: true
      runAsUserName: "NT AUTHORITY\\Local service"
  hostNetwork: true
  containers:
  - name: test
    image: image1:latest
    command:
      - ping
      - -t
      - 127.0.0.1
  nodeSelector:
    "kubernetes.io/os": windows
```

Example 2 (cmd):
```cmd
net localgroup hpc-localgroup /add
```

Example 3 (yaml):
```yaml
securityContext:
  windowsOptions:
    hostProcess: true
    runAsUserName: hpc-localgroup
```

---

## Customizing DNS Service

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/

**Contents:**
- Customizing DNS Service
- Before you begin
- Introduction
    - Note:
- CoreDNS
  - CoreDNS ConfigMap options
  - Configuration of Stub-domain and upstream nameserver using CoreDNS
    - Example
    - Note:
- What's next

This page explains how to configure your DNS Pod(s) and customize the DNS resolution process in your cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

Your cluster must be running the CoreDNS add-on.

Your Kubernetes server must be at or later than version v1.12.

To check the version, enter kubectl version.

DNS is a built-in Kubernetes service launched automatically using the addon manager cluster add-on.

If you are running CoreDNS as a Deployment, it will typically be exposed as a Kubernetes Service with a static IP address. The kubelet passes DNS resolver information to each container with the --cluster-dns=<dns-service-ip> flag.

DNS names also need domains. You configure the local domain in the kubelet with the flag --cluster-domain=<default-local-domain>.

The DNS server supports forward lookups (A and AAAA records), port lookups (SRV records), reverse IP address lookups (PTR records), and more. For more information, see DNS for Services and Pods.

If a Pod's dnsPolicy is set to default, it inherits the name resolution configuration from the node that the Pod runs on. The Pod's DNS resolution should behave the same as the node. But see Known issues.

If you don't want this, or if you want a different DNS config for pods, you can use the kubelet's --resolv-conf flag. Set this flag to "" to prevent Pods from inheriting DNS. Set it to a valid file path to specify a file other than /etc/resolv.conf for DNS inheritance.

CoreDNS is a general-purpose authoritative DNS server that can serve as cluster DNS, complying with the DNS specifications.

CoreDNS is a DNS server that is modular and pluggable, with plugins adding new functionalities. The CoreDNS server can be configured by maintaining a Corefile, which is the CoreDNS configuration file. As a cluster administrator, you can modify the ConfigMap for the CoreDNS Corefile to change how DNS service discovery behaves for that cluster.

In Kubernetes, CoreDNS is installed with the following default Corefile configuration:

The Corefile configuration includes the following plugins of CoreDNS:

You can modify the default CoreDNS behavior by modifying the ConfigMap.

CoreDNS has the

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```

Example 2 (unknown):
```unknown
consul.local:53 {
    errors
    cache 30
    forward . 10.150.0.1
}
```

Example 3 (unknown):
```unknown
forward .  172.16.0.1
```

Example 4 (yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . 172.16.0.1
        cache 30
        loop
        reload
        loadbalance
    }
    consul.local:53 {
        errors
        cache 30
        forward . 10.150.0.1
    }
```

---

## Using Source IP

**URL:** https://kubernetes.io/docs/tutorials/services/source-ip/

**Contents:**
- Using Source IP
- Before you begin
  - Terminology
  - Prerequisites
    - Note:
- Objectives
- Source IP for Services with Type=ClusterIP
- Source IP for Services with Type=NodePort
- Source IP for Services with Type=LoadBalancer
- Cross-platform support

Applications running in a Kubernetes cluster find and communicate with each other, and the outside world, through the Service abstraction. This document explains what happens to the source IP of packets sent to different types of Services, and how you can toggle this behavior according to your needs.

This document makes use of the following terms:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

The examples use a small nginx webserver that echoes back the source IP of requests it receives through an HTTP header. You can create it as follows:

Packets sent to ClusterIP from within the cluster are never source NAT'd if you're running kube-proxy in iptables mode, (the default). You can query the kube-proxy mode by fetching http://localhost:10249/proxyMode on the node where kube-proxy is running.

The output is similar to this:

Get the proxy mode on one of the nodes (kube-proxy listens on port 10249):

You can test source IP preservation by creating a Service over the source IP app:

The output is similar to:

And hitting the ClusterIP from a pod in the same cluster:

The output is similar to this:

You can then run a command inside that Pod:

…then use wget to query the local webserver

The client_address is always the client pod's IP address, whether the client pod and server pod are in the same node or in different nodes.

Packets sent to Services with Type=NodePort are source NAT'd by default. You can test this by creating a NodePort Service:

If you're running on a cloud provider, you may need to open up a firewall-rule for the nodes:nodeport reported above. Now you can try reaching the Service from outside the cluster through the node port allocated above.

The output is similar to:

Note that these are not the correct client IPs, they're cluster internal IPs. This is what happens:

Figure. Source IP Type=NodePort using SNAT

To avoid this, Kubernetes has a feature to preserve the client source IP. If you set service.spec.externalTrafficPolicy to the value Local, kube-proxy only proxies proxy requests to local endpoints, and does not forward traffic to other nodes. This approach preserves the original source IP address. If there ar

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create deployment source-ip-app --image=registry.k8s.io/echoserver:1.10
```

Example 2 (unknown):
```unknown
deployment.apps/source-ip-app created
```

Example 3 (console):
```console
kubectl get nodes
```

Example 4 (unknown):
```unknown
NAME                           STATUS     ROLES    AGE     VERSION
kubernetes-node-6jst   Ready      <none>   2h      v1.13.0
kubernetes-node-cx31   Ready      <none>   2h      v1.13.0
kubernetes-node-jj1t   Ready      <none>   2h      v1.13.0
```

---

## Tools for Monitoring Resources

**URL:** https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-usage-monitoring/

**Contents:**
- Tools for Monitoring Resources
- Resource metrics pipeline
- Full metrics pipeline
- What's next
- Feedback

To scale an application and provide a reliable service, you need to understand how the application behaves when it is deployed. You can examine application performance in a Kubernetes cluster by examining the containers, pods, services, and the characteristics of the overall cluster. Kubernetes provides detailed information about an application's resource usage at each of these levels. This information allows you to evaluate your application's performance and where bottlenecks can be removed to improve overall performance.

In Kubernetes, application monitoring does not depend on a single monitoring solution. On new clusters, you can use resource metrics or full metrics pipelines to collect monitoring statistics.

The resource metrics pipeline provides a limited set of metrics related to cluster components such as the Horizontal Pod Autoscaler controller, as well as the kubectl top utility. These metrics are collected by the lightweight, short-term, in-memory metrics-server and are exposed via the metrics.k8s.io API.

metrics-server discovers all nodes on the cluster and queries each node's kubelet for CPU and memory usage. The kubelet acts as a bridge between the Kubernetes master and the nodes, managing the pods and containers running on a machine. The kubelet translates each pod into its constituent containers and fetches individual container usage statistics from the container runtime through the container runtime interface. If you use a container runtime that uses Linux cgroups and namespaces to implement containers, and the container runtime does not publish usage statistics, then the kubelet can look up those statistics directly (using code from cAdvisor). No matter how those statistics arrive, the kubelet then exposes the aggregated pod resource usage statistics through the metrics-server Resource Metrics API. This API is served at /metrics/resource/v1beta1 on the kubelet's authenticated and read-only ports.

A full metrics pipeline gives you access to richer metrics. Kubernetes can respond to these metrics by automatically scaling or adapting the cluster based on its current state, using mechanisms such as the Horizontal Pod Autoscaler. The monitoring pipeline fetches metrics from the kubelet and then exposes them to Kubernetes via an adapter by implementing either the custom.metrics.k8s.io or external.metrics.k8s.io API.

Kubernetes is designed to work with OpenMetrics, which is one of the CNCF Observability and Analysis - Monitoring Projects, bu

*[Content truncated]*

---

## Networking

**URL:** https://kubernetes.io/docs/tasks/network/

**Contents:**
- Networking
      - Adding entries to Pod /etc/hosts with HostAliases
      - Extend Service IP Ranges
      - Kubernetes Default Service CIDR Reconfiguration
      - Validate IPv4/IPv6 dual-stack
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Connect a Frontend to a Backend Using Services

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/connecting-frontend-backend/

**Contents:**
- Connect a Frontend to a Backend Using Services
- Objectives
- Before you begin
- Creating the backend using a Deployment
- Creating the hello Service object
- Creating the frontend
    - Note:
- Interact with the frontend Service
- Send traffic through the frontend
- Cleaning up

This task shows how to create a frontend and a backend microservice. The backend microservice is a hello greeter. The frontend exposes the backend using nginx and a Kubernetes Service object.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesTo check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

This task uses Services with external load balancers, which require a supported environment. If your environment does not support this, you can use a Service of type NodePort instead.

The backend is a simple hello greeter microservice. Here is the configuration file for the backend Deployment:

Create the backend Deployment:

View information about the backend Deployment:

The output is similar to this:

The key to sending requests from a frontend to a backend is the backend Service. A Service creates a persistent IP address and DNS name entry so that the backend microservice can always be reached. A Service uses selectors to find the Pods that it routes traffic to.

First, explore the Service configuration file:

In the configuration file, you can see that the Service, named hello routes traffic to Pods that have the labels app: hello and tier: backend.

Create the backend Service:

At this point, you have a backend Deployment running three replicas of your hello application, and you have a Service that can route traffic to them. However, this service is neither available nor resolvable outside the cluster.

Now that you have your backend running, you can create a frontend that is accessible outside the cluster, and connects to the backend by proxying requests to it.

The frontend sends requests to the backend worker Pods by using the DNS name given to the backend Service. The DNS name is hell

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  selector:
    matchLabels:
      app: hello
      tier: backend
      track: stable
  replicas: 3
  template:
    metadata:
      labels:
        app: hello
        tier: backend
        track: stable
    spec:
      containers:
        - name: hello
          image: "gcr.io/google-samples/hello-go-gke:1.0"
          ports:
            - name: http
              containerPort: 80
...
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/service/access/backend-deployment.yaml
```

Example 3 (shell):
```shell
kubectl describe deployment backend
```

Example 4 (unknown):
```unknown
Name:                           backend
Namespace:                      default
CreationTimestamp:              Mon, 24 Oct 2016 14:21:02 -0700
Labels:                         app=hello
                                tier=backend
                                track=stable
Annotations:                    deployment.kubernetes.io/revision=1
Selector:                       app=hello,tier=backend,track=stable
Replicas:                       3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:                   RollingUpdate
MinReadySeconds:                0
RollingUpdateS
...
```

---

## Connecting Applications with Services

**URL:** https://kubernetes.io/docs/tutorials/services/connect-applications-service/

**Contents:**
- Connecting Applications with Services
- The Kubernetes model for connecting containers
- Exposing pods to the cluster
- Creating a Service
- Accessing the Service
    - Note:
  - Environment Variables
  - DNS
- Securing the Service
- Exposing the Service

Now that you have a continuously running, replicated application you can expose it on a network.

Kubernetes assumes that pods can communicate with other pods, regardless of which host they land on. Kubernetes gives every pod its own cluster-private IP address, so you do not need to explicitly create links between pods or map container ports to host ports. This means that containers within a Pod can all reach each other's ports on localhost, and all pods in a cluster can see each other without NAT. The rest of this document elaborates on how you can run reliable services on such a networking model.

This tutorial uses a simple nginx web server to demonstrate the concept.

We did this in a previous example, but let's do it once again and focus on the networking perspective. Create an nginx Pod, and note that it has a container port specification:

This makes it accessible from any node in your cluster. Check the nodes the Pod is running on:

Check your pods' IPs:

You should be able to ssh into any node in your cluster and use a tool such as curl to make queries against both IPs. Note that the containers are not using port 80 on the node, nor are there any special NAT rules to route traffic to the pod. This means you can run multiple nginx pods on the same node all using the same containerPort, and access them from any other pod or node in your cluster using the assigned IP address for the pod. If you want to arrange for a specific port on the host Node to be forwarded to backing Pods, you can - but the networking model should mean that you do not need to do so.

You can read more about the Kubernetes Networking Model if you're curious.

So we have pods running nginx in a flat, cluster wide, address space. In theory, you could talk to these pods directly, but what happens when a node dies? The pods die with it, and the ReplicaSet inside the Deployment will create new ones, with different IPs. This is the problem a Service solves.

A Kubernetes Service is an abstraction which defines a logical set of Pods running somewhere in your cluster, that all provide the same functionality. When created, each Service is assigned a unique IP address (also called clusterIP). This address is tied to the lifespan of the Service, and will not change while the Service is alive. Pods can be configured to talk to the Service, and know that communication to the Service will be automatically load-balanced out to some pod that is a member of the Service.

You can create a Service

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  selector:
    matchLabels:
      run: my-nginx
  replicas: 2
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx
        ports:
        - containerPort: 80
```

Example 2 (shell):
```shell
kubectl apply -f ./run-my-nginx.yaml
kubectl get pods -l run=my-nginx -o wide
```

Example 3 (unknown):
```unknown
NAME                        READY     STATUS    RESTARTS   AGE       IP            NODE
my-nginx-3800858182-jr4a2   1/1       Running   0          13s       10.244.3.4    kubernetes-minion-905m
my-nginx-3800858182-kna2y   1/1       Running   0          13s       10.244.2.5    kubernetes-minion-ljyd
```

Example 4 (shell):
```shell
kubectl get pods -l run=my-nginx -o custom-columns=POD_IP:.status.podIPs
    POD_IP
    [map[ip:10.244.3.4]]
    [map[ip:10.244.2.5]]
```

---

## Set up Ingress on Minikube with the NGINX Ingress Controller

**URL:** https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/

**Contents:**
- Set up Ingress on Minikube with the NGINX Ingress Controller
- Before you begin
    - Note:
  - Create a minikube cluster
- Enable the Ingress controller
    - Note:
- Deploy a hello, world app
- Create an Ingress
    - Note:
    - Note:

An Ingress is an API object that defines rules which allow external access to services in a cluster. An Ingress controller fulfills the rules set in the Ingress.

This page shows you how to set up a simple Ingress which routes requests to Service 'web' or 'web2' depending on the HTTP URI.

This tutorial assumes that you are using minikube to run a local Kubernetes cluster. Visit Install tools to learn how to install minikube.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.19.To check the version, enter kubectl version.If you are using an older Kubernetes version, switch to the documentation for that version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

If you haven't already set up a cluster locally, run minikube start to create a cluster.

To enable the NGINX Ingress controller, run the following command:

Verify that the NGINX Ingress controller is running

The output is similar to:

Create a Deployment using the following command:

The output should be:

Verify that the Deployment is in a Ready state:

The output should be similar to:

Expose the Deployment:

The output should be:

Verify the Service is created and is available on a node port:

The output is similar to:

Visit the Service via NodePort, using the minikube service command. Follow the instructions for your platform:

LinuxMacOSminikube service web --url The output is similar to:http://172.17.0.15:31637 Invoke the URL obtained in the output of the previous step:curl http://172.17.0.15:31637 # The command must be run in a separate terminal. minikube service web --url The output is similar to:http://127.0.0.1:62445 ! Because you are using a Docker driver on darwin, the terminal needs to be open to

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube addons enable ingress
```

Example 2 (shell):
```shell
kubectl get pods -n ingress-nginx
```

Example 3 (none):
```none
NAME                                        READY   STATUS      RESTARTS    AGE
ingress-nginx-admission-create-g9g49        0/1     Completed   0          11m
ingress-nginx-admission-patch-rqp78         0/1     Completed   1          11m
ingress-nginx-controller-59b45fb494-26npt   1/1     Running     0          11m
```

Example 4 (shell):
```shell
kubectl create deployment web --image=gcr.io/google-samples/hello-app:1.0
```

---

## Control Topology Management Policies on a node

**URL:** https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/

**Contents:**
- Control Topology Management Policies on a node
- Before you begin
- How topology manager works
- Windows Support
- Topology manager scopes and policies
    - Note:
    - Note:
- Topology manager scopes
  - container scope
  - pod scope

An increasing number of systems leverage a combination of CPUs and hardware accelerators to support latency-critical execution and high-throughput parallel computation. These include workloads in fields such as telecommunications, scientific computing, machine learning, financial services and data analytics. Such hybrid systems comprise a high performance environment.

In order to extract the best performance, optimizations related to CPU isolation, memory and device locality are required. However, in Kubernetes, these optimizations are handled by a disjoint set of components.

Topology Manager is a kubelet component that aims to coordinate the set of components that are responsible for these optimizations.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version v1.18.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Prior to the introduction of Topology Manager, the CPU and Device Manager in Kubernetes make resource allocation decisions independently of each other. This can result in undesirable allocations on multiple-socketed systems, and performance/latency sensitive applications will suffer due to these undesirable allocations. Undesirable in this case meaning, for example, CPUs and devices being allocated from different NUMA Nodes, thus incurring additional latency.

The Topology Manager is a kubelet component, which acts as a source of truth so that other kubelet components can make topology aligned resource allocation choices.

The Topology Manager provides an interface for components, called Hint Providers, to send and receive topology information. The Topology Manager has a set of node level policies which are explained be

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

## Extend Service IP Ranges

**URL:** https://kubernetes.io/docs/tasks/network/extend-service-ip-ranges/

**Contents:**
- Extend Service IP Ranges
- Before you begin
    - Note:
- Extend Service IP Ranges
- Extend the number of available IPs for Services
  - Adding a new ServiceCIDR
  - Deleting a ServiceCIDR
- Kubernetes Service CIDR Policies
  - Preventing Unauthorized ServiceCIDR Creation/Update using Validating Admission Policy
    - Note:

This document shares how to extend the existing Service IP range assigned to a cluster.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

Kubernetes clusters with kube-apiservers that have enabled the MultiCIDRServiceAllocator feature gate and have the networking.k8s.io/v1beta1 API group active, will create a ServiceCIDR object that takes the well-known name kubernetes, and that specifies an IP address range based on the value of the --service-cluster-ip-range command line argument to kube-apiserver.

The well-known kubernetes Service, that exposes the kube-apiserver endpoint to the Pods, calculates the first IP address from the default ServiceCIDR range and uses that IP address as its cluster IP address.

The default Service, in this case, uses the ClusterIP 10.96.0.1, that has the corresponding IPAddress object.

The ServiceCIDRs are protected with finalizers, to avoid leaving Service ClusterIPs orphans; the finalizer is only removed if there is another subnet that contains the existing IPAddresses or there are no IPAddresses belonging to the subnet.

There are cases that users will need to increase the number addresses available to Services, previously, increasing the Service range was a disruptive operation that could also cause data loss. With this new feature users only need to add a new ServiceCIDR to increase the number of available addresses.

On a cluster with a 10.96.0.0/28 range for Services, there is only 2^(32-28) - 2 = 14 IP addresses available. The kubernetes.default Service is always created; for this example, that leaves you with only 13 possible Services.

You can increase the number of IP addresses available for Services, by creating a new ServiceCIDR that extends or adds new IP address ranges.

and this will allow you to create new Services with ClusterIPs that will be picked from this new range.

You cannot delete a ServiceCIDR if there are IPAddresses that depend on the ServiceCIDR.

Kubernetes uses a finalizer on the ServiceCIDR to track this dependent relationship.

By removing the Services containing the IP addresses that are blocking the deletion of the ServiceCIDR


*[Content truncated]*

**Examples:**

Example 1 (sh):
```sh
kubectl get servicecidr
```

Example 2 (unknown):
```unknown
NAME         CIDRS          AGE
kubernetes   10.96.0.0/28   17d
```

Example 3 (sh):
```sh
kubectl get service kubernetes
```

Example 4 (unknown):
```unknown
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   17d
```

---
