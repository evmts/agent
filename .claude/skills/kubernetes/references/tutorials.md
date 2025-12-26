# Kubernetes - Tutorials

**Pages:** 14

---

## Tutorials

**URL:** https://kubernetes.io/docs/tutorials/

**Contents:**
- Basics
- Configuration
- Authoring Pods
- Stateless Applications
- Stateful Applications
- Services
- Security
- Cluster Management
- What's next
- Feedback

This section of the Kubernetes documentation contains tutorials. A tutorial shows how to accomplish a goal that is larger than a single task. Typically a tutorial has several sections, each of which has a sequence of steps. Before walking through each tutorial, you may want to bookmark the Standardized Glossary page for later references.

If you would like to write a tutorial, see Content Page Types for information about the tutorial page type.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Configuring swap memory on Kubernetes nodes

**URL:** https://kubernetes.io/docs/tutorials/cluster-management/provision-swap-memory/

**Contents:**
- Configuring swap memory on Kubernetes nodes
- Objectives
- Before you begin
- Install a swap-enabled cluster with kubeadm
  - Create a swap file and turn swap on
    - Verify that swap is enabled
    - Enable swap on boot
  - Set up kubelet configuration
- Feedback

This page provides an example of how to provision and configure swap memory on a Kubernetes node using kubeadm.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:iximiuz LabsKillercodaKodeKloudPlay with KubernetesYour Kubernetes server must be at or later than version 1.33.To check the version, enter kubectl version.

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

You need at least one worker node in your cluster which needs to run a Linux operating system. It is required for this demo that the kubeadm tool be installed, following the steps outlined in the kubeadm installation guide.

On each worker node where you will configure swap use, you need:

For encrypted swap space (recommended), you also need:

If swap is not enabled, there's a need to provision swap on the node. The following sections demonstrate creating 4GiB of swap, both in the encrypted and unencrypted case.

An encrypted swap file can be set up as follows. Bear in mind that this example uses the cryptsetup binary (which is available on most Linux distributions).# Allocate storage and restrict access fallocate --length 4GiB /swapfile chmod 600 /swapfile # Create an encrypted device backed by the allocated storage cryptsetup --type plain --cipher aes-xts-plain64 --key-size 256 -d /dev/urandom open /swapfile cryptswap # Format the swap space mkswap /dev/mapper/cryptswap # Activate the swap space for paging swapon /dev/mapper/cryptswap

An encrypted swap file can be set up as follows. Bear in mind that this example uses the cryptsetup binary (which is available on most Linux distributions).

An unencrypted swap file can be set up as follows.# Allocate storage and restrict access fallocate --length 4GiB /swapfile chmod 600 /swapfile # Format the swap space mkswap /swapfile # Activate the swap space for paging swa

*[Content truncated]*

**Examples:**

Example 1 (bash):
```bash
# Allocate storage and restrict access
fallocate --length 4GiB /swapfile
chmod 600 /swapfile

# Create an encrypted device backed by the allocated storage
cryptsetup --type plain --cipher aes-xts-plain64 --key-size 256 -d /dev/urandom open /swapfile cryptswap

# Format the swap space
mkswap /dev/mapper/cryptswap

# Activate the swap space for paging
swapon /dev/mapper/cryptswap
```

Example 2 (bash):
```bash
# Allocate storage and restrict access
fallocate --length 4GiB /swapfile
chmod 600 /swapfile

# Format the swap space
mkswap /swapfile

# Activate the swap space for paging
swapon /swapfile
```

Example 3 (unknown):
```unknown
Filename       Type		Size		Used		Priority
/dev/dm-0      partition 	4194300		0		-2
```

Example 4 (unknown):
```unknown
total        used        free      shared  buff/cache   available
Mem:           3.8Gi       1.3Gi       249Mi        25Mi       2.5Gi       2.5Gi
Swap:          4.0Gi          0B       4.0Gi
```

---

## Running Kubelet in Standalone Mode

**URL:** https://kubernetes.io/docs/tutorials/cluster-management/kubelet-standalone/

**Contents:**
- Running Kubelet in Standalone Mode
- Objectives
    - Caution:
- Before you begin
- Prepare the system
  - Swap configuration
    - Note:
  - Enable IPv4 packet forwarding
- Download, install, and configure the components
  - Install a container runtime

This tutorial shows you how to run a standalone kubelet instance.

You may have different motivations for running a standalone kubelet. This tutorial is aimed at introducing you to Kubernetes, even if you don't have much experience with it. You can follow this tutorial and learn about node setup, basic (static) Pods, and how Kubernetes manages containers.

Once you have followed this tutorial, you could try using a cluster that has a control plane to manage pods and nodes, and other types of objects. For example, Hello, minikube.

You can also run the kubelet in standalone mode to suit production use cases, such as to run the control plane for a highly available, resiliently deployed cluster. This tutorial does not cover the details you need for running a resilient control plane.

By default, kubelet fails to start if swap memory is detected on a node. This means that swap should either be disabled or tolerated by kubelet.

If you have swap memory enabled, either disable it or add failSwapOn: false to the kubelet configuration file.

To check if swap is enabled:

If there is no output from the command, then swap memory is already disabled.

To disable swap temporarily:

To make this change persistent across reboots:

Make sure swap is disabled in either /etc/fstab or systemd.swap, depending on how it was configured on your system.

To check if IPv4 packet forwarding is enabled:

If the output is 1, it is already enabled. If the output is 0, then follow next steps.

To enable IPv4 packet forwarding, create a configuration file that sets the net.ipv4.ip_forward parameter to 1:

Apply the changes to the system:

The output is similar to:

Download the latest available versions of the required packages (recommended).

This tutorial suggests installing the CRI-O container runtime (external link).

There are several ways to install the CRI-O container runtime, depending on your particular Linux distribution. Although CRI-O recommends using either deb or rpm packages, this tutorial uses the static binary bundle script of the CRI-O Packaging project, both to streamline the overall process, and to remain distribution agnostic.

The script installs and configures additional required software, such as cni-plugins, for container networking, and crun and runc, for running containers.

The script will automatically detect your system's processor architecture (amd64 or arm64) and select and install the latest versions of the software packages.

Visit the releases page (e

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
sudo swapon --show
```

Example 2 (shell):
```shell
sudo swapoff -a
```

Example 3 (shell):
```shell
cat /proc/sys/net/ipv4/ip_forward
```

Example 4 (shell):
```shell
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
EOF
```

---

## Example: Deploying PHP Guestbook application with Redis

**URL:** https://kubernetes.io/docs/tutorials/stateless-application/guestbook/

**Contents:**
- Example: Deploying PHP Guestbook application with Redis
- Objectives
- Before you begin
- Start up the Redis Database
  - Creating the Redis Deployment
  - Creating the Redis leader Service
    - Note:
  - Set up Redis followers
  - Creating the Redis follower service
    - Note:

This tutorial shows you how to build and deploy a simple (not production ready), multi-tier web application using Kubernetes and Docker. This example consists of the following components:

You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. It is recommended to run this tutorial on a cluster with at least two nodes that are not acting as control plane hosts. If you do not already have a cluster, you can create one by using minikube or you can use one of these Kubernetes playgrounds:

To check the version, enter kubectl version.

The guestbook application uses Redis to store its data.

The manifest file, included below, specifies a Deployment controller that runs a single replica Redis Pod.

Launch a terminal window in the directory you downloaded the manifest files.

Apply the Redis Deployment from the redis-leader-deployment.yaml file:

Query the list of Pods to verify that the Redis Pod is running:

The response should be similar to this:

Run the following command to view the logs from the Redis leader Pod:

The guestbook application needs to communicate to the Redis to write its data. You need to apply a Service to proxy the traffic to the Redis Pod. A Service defines a policy to access the Pods.

Apply the Redis Service from the following redis-leader-service.yaml file:

Query the list of Services to verify that the Redis Service is running:

The response should be similar to this:

Although the Redis leader is a single Pod, you can make it highly available and meet traffic demands by adding a few Redis followers, or replicas.

Apply the Redis Deployment from the following redis-follower-deployment.yaml file:

Verify that the two Redis follower replicas are running by querying the list of Pods:

The response should be similar to this:

The guestbook application needs to communicate with the Redis followers to read data. To make the Redis followers discoverable, you must set up another Service.

Apply the Redis Service from the following redis-follower-service.yaml file:

Query the list of Services to verify that the Redis Service is running:

The response should be similar to this:

Now that you have the Redis storage of your guestbook up and running, start the guestbook web servers. Like the Redis followers, the frontend is deployed using a Kubernetes Deployment.

The guestbook app uses a PHP frontend. It is configured to communicate with either the Redis follower or leader Ser

*[Content truncated]*

**Examples:**

Example 1 (yaml):
```yaml
# SOURCE: https://cloud.google.com/kubernetes-engine/docs/tutorials/guestbook
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-leader
  labels:
    app: redis
    role: leader
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        role: leader
        tier: backend
    spec:
      containers:
      - name: leader
        image: "docker.io/redis:6.0.5"
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        ports:
        - containerPort: 6379
```

Example 2 (shell):
```shell
kubectl apply -f https://k8s.io/examples/application/guestbook/redis-leader-deployment.yaml
```

Example 3 (shell):
```shell
kubectl get pods
```

Example 4 (unknown):
```unknown
NAME                           READY   STATUS    RESTARTS   AGE
redis-leader-fb76b4755-xjr2n   1/1     Running   0          13s
```

---

## Stateful Applications

**URL:** https://kubernetes.io/docs/tutorials/stateful-application/

**Contents:**
- Stateful Applications
      - StatefulSet Basics
      - Example: Deploying WordPress and MySQL with Persistent Volumes
      - Example: Deploying Cassandra with a StatefulSet
      - Running ZooKeeper, A Distributed System Coordinator
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Hello Minikube

**URL:** https://kubernetes.io/docs/tutorials/hello-minikube/#dashboard-1

**Contents:**
- Hello Minikube
- Objectives
- Before you begin
    - Note:
- Create a minikube cluster
- Open the Dashboard
    - Note:
- Create a Deployment
    - Note:
    - Note:

This tutorial shows you how to run a sample app on Kubernetes using minikube. The tutorial provides a container image that uses NGINX to echo back all the requests.

This tutorial assumes that you have already set up minikube. See Step 1 in minikube start for installation instructions.Note:Only execute the instructions in Step 1, Installation. The rest is covered on this page.

You also need to install kubectl. See Install tools for installation instructions.

Open the Kubernetes dashboard. You can do this two different ways:

Open a new terminal, and run:# Start a new terminal, and leave this running. minikube dashboard Now, switch back to the terminal where you ran minikube start.Note:The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

Open a new terminal, and run:

Now, switch back to the terminal where you ran minikube start.

The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.

To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.

By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.

To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

If you don't want minikube to open a web browser for you, run the dashboard subcommand with the --url flag. minikube outputs a URL that you can open in the bro

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube start
```

Example 2 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard
```

Example 3 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard --url
```

Example 4 (shell):
```shell
# Run a test container image that includes a webserver
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
```

---

## Using kubectl to Create a Deployment

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/deploy-app/deploy-intro/

**Contents:**
- Using kubectl to Create a Deployment
- Objectives
- Kubernetes Deployments
    - Note:
- Deploying your first app on Kubernetes
  - kubectl basics
  - Deploy an app
  - View the app
    - Note:
- What's next

Once you have a running Kubernetes cluster, you can deploy your containerized applications on top of it. To do so, you create a Kubernetes Deployment. The Deployment instructs Kubernetes how to create and update instances of your application. Once you've created a Deployment, the Kubernetes control plane schedules the application instances included in that Deployment to run on individual Nodes in the cluster.

Once the application instances are created, a Kubernetes Deployment controller continuously monitors those instances. If the Node hosting an instance goes down or is deleted, the Deployment controller replaces the instance with an instance on another Node in the cluster. This provides a self-healing mechanism to address machine failure or maintenance.

In a pre-orchestration world, installation scripts would often be used to start applications, but they did not allow recovery from machine failure. By both creating your application instances and keeping them running across Nodes, Kubernetes Deployments provide a fundamentally different approach to application management.

You can create and manage a Deployment by using the Kubernetes command line interface, kubectl. kubectl uses the Kubernetes API to interact with the cluster. In this module, you'll learn the most common kubectl commands needed to create Deployments that run your applications on a Kubernetes cluster.

When you create a Deployment, you'll need to specify the container image for your application and the number of replicas that you want to run. You can change that information later by updating your Deployment; Module 5 and Module 6 of the bootcamp discuss how you can scale and update your Deployments.

For your first Deployment, you'll use a hello-node application packaged in a Docker container that uses NGINX to echo back all the requests. (If you didn't already try creating a hello-node application and deploying it using a container, you can do that first by following the instructions from the Hello Minikube tutorial.)

You will need to have installed kubectl as well. If you need to install it, visit install tools.

Now that you know what Deployments are, let's deploy our first app!

The common format of a kubectl command is: kubectl action resource.

This performs the specified action (like create, describe or delete) on the specified resource (like node or deployment. You can use --help after the subcommand to get additional info about possible parameters (for example: kubectl get no

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1
```

Example 2 (shell):
```shell
kubectl get deployments
```

Example 3 (shell):
```shell
kubectl proxy
```

Example 4 (shell):
```shell
curl http://localhost:8001/version
```

---

## Hello Minikube

**URL:** https://kubernetes.io/docs/tutorials/hello-minikube/

**Contents:**
- Hello Minikube
- Objectives
- Before you begin
    - Note:
- Create a minikube cluster
- Open the Dashboard
    - Note:
- Create a Deployment
    - Note:
    - Note:

This tutorial shows you how to run a sample app on Kubernetes using minikube. The tutorial provides a container image that uses NGINX to echo back all the requests.

This tutorial assumes that you have already set up minikube. See Step 1 in minikube start for installation instructions.Note:Only execute the instructions in Step 1, Installation. The rest is covered on this page.

You also need to install kubectl. See Install tools for installation instructions.

Open the Kubernetes dashboard. You can do this two different ways:

Open a new terminal, and run:# Start a new terminal, and leave this running. minikube dashboard Now, switch back to the terminal where you ran minikube start.Note:The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

Open a new terminal, and run:

Now, switch back to the terminal where you ran minikube start.

The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.

To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.

By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.

To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

If you don't want minikube to open a web browser for you, run the dashboard subcommand with the --url flag. minikube outputs a URL that you can open in the bro

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube start
```

Example 2 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard
```

Example 3 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard --url
```

Example 4 (shell):
```shell
# Run a test container image that includes a webserver
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
```

---

## Performing a Rolling Update

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/

**Contents:**
- Performing a Rolling Update
- Objectives
- Updating an application
- Rolling updates overview
  - Update the version of the app
  - Verify an update
  - Roll back an update
- What's next
- Feedback

Perform a rolling update using kubectl.

Users expect applications to be available all the time, and developers are expected to deploy new versions of them several times a day. In Kubernetes this is done with rolling updates. A rolling update allows a Deployment update to take place with zero downtime. It does this by incrementally replacing the current Pods with new ones. The new Pods are scheduled on Nodes with available resources, and Kubernetes waits for those new Pods to start before removing the old Pods.

In the previous module we scaled our application to run multiple instances. This is a requirement for performing updates without affecting application availability. By default, the maximum number of Pods that can be unavailable during the update and the maximum number of new Pods that can be created, is one. Both options can be configured to either numbers or percentages (of Pods). In Kubernetes, updates are versioned and any Deployment update can be reverted to a previous (stable) version.

Similar to application Scaling, if a Deployment is exposed publicly, the Service will load-balance the traffic only to available Pods during the update. An available Pod is an instance that is available to the users of the application.

Rolling updates allow the following actions:

In the following interactive tutorial, we'll update our application to a new version, and also perform a rollback.

To list your Deployments, run the get deployments subcommand:

To list the running Pods, run the get pods subcommand:

To view the current image version of the app, run the describe pods subcommand and look for the Image field:

To update the image of the application to version 2, use the set image subcommand, followed by the deployment name and the new image version:

The command notified the Deployment to use a different image for your app and initiated a rolling update. Check the status of the new Pods, and view the old one terminating with the get pods subcommand:

First, check that the service is running, as you might have deleted it in previous tutorial step, run describe services/kubernetes-bootcamp. If it's missing, you can create it again with:

Create an environment variable called NODE_PORT that has the value of the Node port assigned:

Next, do a curl to the exposed IP and port:

Every time you run the curl command, you will hit a different Pod. Notice that all Pods are now running the latest version (v2).

You can also confirm the update by running the roll

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl get deployments
```

Example 2 (shell):
```shell
kubectl get pods
```

Example 3 (shell):
```shell
kubectl describe pods
```

Example 4 (shell):
```shell
kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=docker.io/jocatalin/kubernetes-bootcamp:v2
```

---

## Stateless Applications

**URL:** https://kubernetes.io/docs/tutorials/stateless-application/

**Contents:**
- Stateless Applications
      - Exposing an External IP Address to Access an Application in a Cluster
      - Example: Deploying PHP Guestbook application with Redis
- Feedback

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Hello Minikube

**URL:** https://kubernetes.io/docs/tutorials/hello-minikube/#dashboard-0

**Contents:**
- Hello Minikube
- Objectives
- Before you begin
    - Note:
- Create a minikube cluster
- Open the Dashboard
    - Note:
- Create a Deployment
    - Note:
    - Note:

This tutorial shows you how to run a sample app on Kubernetes using minikube. The tutorial provides a container image that uses NGINX to echo back all the requests.

This tutorial assumes that you have already set up minikube. See Step 1 in minikube start for installation instructions.Note:Only execute the instructions in Step 1, Installation. The rest is covered on this page.

You also need to install kubectl. See Install tools for installation instructions.

Open the Kubernetes dashboard. You can do this two different ways:

Open a new terminal, and run:# Start a new terminal, and leave this running. minikube dashboard Now, switch back to the terminal where you ran minikube start.Note:The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

Open a new terminal, and run:

Now, switch back to the terminal where you ran minikube start.

The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.

To find out how to avoid directly invoking the browser from the terminal and get a URL for the web dashboard, see the "URL copy and paste" tab.

By default, the dashboard is only accessible from within the internal Kubernetes virtual network. The dashboard command creates a temporary proxy to make the dashboard accessible from outside the Kubernetes virtual network.

To stop the proxy, run Ctrl+C to exit the process. After the command exits, the dashboard remains running in the Kubernetes cluster. You can run the dashboard command again to create another proxy to access the dashboard.

If you don't want minikube to open a web browser for you, run the dashboard subcommand with the --url flag. minikube outputs a URL that you can open in the bro

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
minikube start
```

Example 2 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard
```

Example 3 (shell):
```shell
# Start a new terminal, and leave this running.
minikube dashboard --url
```

Example 4 (shell):
```shell
# Run a test container image that includes a webserver
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
```

---

## Running Multiple Instances of Your App

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/scale/scale-intro/

**Contents:**
- Running Multiple Instances of Your App
- Objectives
- Scaling an application
    - Note:
- Scaling overview
  - Scaling a Deployment
  - Load Balancing
    - Note:
  - Scale Down
- What's next

Previously we created a Deployment, and then exposed it publicly via a Service. The Deployment created only one Pod for running our application. When traffic increases, we will need to scale the application to keep up with user demand.

If you haven't worked through the earlier sections, start from Using minikube to create a cluster.

Scaling is accomplished by changing the number of replicas in a Deployment.

If you are trying this after the previous section, then you may have deleted the service you created, or have created a Service of type: NodePort. In this section, it is assumed that a service with type: LoadBalancer is created for the kubernetes-bootcamp Deployment.

If you have not deleted the Service created in the previous section, first delete that Service and then run the following command to create a new Service with its type set to LoadBalancer:

Scaling out a Deployment will ensure new Pods are created and scheduled to Nodes with available resources. Scaling will increase the number of Pods to the new desired state. Kubernetes also supports autoscaling of Pods, but it is outside of the scope of this tutorial. Scaling to zero is also possible, and it will terminate all Pods of the specified Deployment.

Running multiple instances of an application will require a way to distribute the traffic to all of them. Services have an integrated load-balancer that will distribute network traffic to all Pods of an exposed Deployment. Services will monitor continuously the running Pods using endpoints, to ensure the traffic is sent only to available Pods.

Once you have multiple instances of an application running, you would be able to do Rolling updates without downtime. We'll cover that in the next section of the tutorial. Now, let's go to the terminal and scale our application.

To list your Deployments, use the get deployments subcommand:

The output should be similar to:

We should have 1 Pod. If not, run the command again. This shows:

To see the ReplicaSet created by the Deployment, run:

Notice that the name of the ReplicaSet is always formatted as [DEPLOYMENT-NAME]-[RANDOM-STRING]. The random string is randomly generated and uses the pod-template-hash as a seed.

Two important columns of this output are:

Next, let’s scale the Deployment to 4 replicas. We’ll use the kubectl scale command, followed by the Deployment type, name and desired number of instances:

To list your Deployments once again, use get deployments:

The change was applied, and w

*[Content truncated]*

**Examples:**

Example 1 (shell):
```shell
kubectl expose deployment/kubernetes-bootcamp --type="LoadBalancer" --port 8080
```

Example 2 (shell):
```shell
kubectl get deployments
```

Example 3 (unknown):
```unknown
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   1/1     1            1           11m
```

Example 4 (shell):
```shell
kubectl get rs
```

---

## Create a Cluster

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/create-cluster/

**Contents:**
- Create a Cluster
      - Using Minikube to Create a Cluster
- Feedback

Learn about Kubernetes cluster and create a simple cluster using Minikube.

Was this page helpful?

Thanks for the feedback. If you have a specific, answerable question about how to use Kubernetes, ask it on Stack Overflow. Open an issue in the GitHub Repository if you want to report a problem or suggest an improvement.

---

## Using Minikube to Create a Cluster

**URL:** https://kubernetes.io/docs/tutorials/kubernetes-basics/create-cluster/cluster-intro/

**Contents:**
- Using Minikube to Create a Cluster
- Objectives
- Kubernetes Clusters
  - Cluster Diagram
- What's next
- Feedback

Kubernetes coordinates a highly available cluster of computers that are connected to work as a single unit. The abstractions in Kubernetes allow you to deploy containerized applications to a cluster without tying them specifically to individual machines. To make use of this new model of deployment, applications need to be packaged in a way that decouples them from individual hosts: they need to be containerized. Containerized applications are more flexible and available than in past deployment models, where applications were installed directly onto specific machines as packages deeply integrated into the host. Kubernetes automates the distribution and scheduling of application containers across a cluster in a more efficient way. Kubernetes is an open-source platform and is production-ready.

A Kubernetes cluster consists of two types of resources:

The Control Plane is responsible for managing the cluster. The Control Plane coordinates all activities in your cluster, such as scheduling applications, maintaining applications' desired state, scaling applications, and rolling out new updates.

A node is a VM or a physical computer that serves as a worker machine in a Kubernetes cluster. Each node has a Kubelet, which is an agent for managing the node and communicating with the Kubernetes control plane. The node should also have tools for handling container operations, such as containerd or CRI-O. A Kubernetes cluster that handles production traffic should have a minimum of three nodes because if one node goes down, both an etcd member and a control plane instance are lost, and redundancy is compromised. You can mitigate this risk by adding more control plane nodes.

When you deploy applications on Kubernetes, you tell the control plane to start the application containers. The control plane schedules the containers to run on the cluster's nodes. Node-level components, such as the kubelet, communicate with the control plane using the Kubernetes API, which the control plane exposes. End users can also use the Kubernetes API directly to interact with the cluster.

A Kubernetes cluster can be deployed on either physical or virtual machines. To get started with Kubernetes development, you can use Minikube. Minikube is a lightweight Kubernetes implementation that creates a VM on your local machine and deploys a simple cluster containing only one node. Minikube is available for Linux, macOS, and Windows systems. The Minikube CLI provides basic bootstrapping operation

*[Content truncated]*

---
