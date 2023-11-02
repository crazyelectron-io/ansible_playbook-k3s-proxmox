# Install a full-blown Kubernetes cluster with K3s

> This is just _note keeping_ so I can reproduce and adjust my Kubernetes environments when needed.
> It might contain some usefull tips for others.

There are many ways to deploy Kubernetes clusters, but currently I use [K3s](https://k3s.io) for both single and multi node clusters.
_Disclaimer: These clusters run in my home environment and I would not recommend this for mission critical workloads._
The workloads deployed on my Kubernetes cluster include MetalLB, Longhorn, Traefik, a Private registry, Replicator, and Cert-Manager, among others.
Using _K3s_ makes installing a Kubernetes cluster straightforward and it supports the deployment of MetalLB as loadbalancer and Flannel as cluster network out-of-the-box.
More information about K3s can be found at the [official website](https://docs.k3s.io/).
The basic setup of the Kubernetes cluster, including the Proxmox VM hosts, is done with Terraform and Ansible.
For additional workload deployments on the cluster, the GitOps tool _Flux_ (v2) is used.

## Kubernetes cluster overview

Obviously Kubernetes needs compute nodes to run on and they can be physical or virtual.
I deploy my cluster on [Proxmox](https://www.proxmox.com/en/proxmox-ve) hosted Linux virtual machines.
Proxmox runs on a cluster of three physical servers, each with 20 cores, 128 GB RAM, two 1 TB NVMe SSDs (RAID1) for the host OS and VMs, and four 8 TB SSD's for the Volumes (attached to nodes as one logical volume managed by Longhorn).
Two K3s VM's are deployed on each phyiscal host, a controller and a worker node, resulting in a 6-node Kubernetes cluster.

The configuration of the VM's for this 'production' home cluster:

|     Node     | cores |  RAM  |  disk  |  host  |
|--------------|------:|------:|-------:|:-------|
| k3s-prod-m01 |     6 | 32 GB | 100 GB | prox01 |
| k3s-prod-w01 |     8 | 64 GB | 100 GB | prox01 |
| k3s-prod-m02 |     6 | 32 GB | 100 GB | prox02 |
| k3s-prod-w02 |     8 | 64 GB | 100 GB | prox02 |
| k3s-prod-m03 |     6 | 32 GB | 100 GB | prox03 |
| k3s-prod-w03 |     8 | 64 GB | 100 GB | prox03 |

And I frequently (re)deploy a much smaller single Proxmox test and development host with just two (and sometimes three) VMs:

|     Node    | cores |  RAM  |  disk  |  host  |
|-------------|------:|------:|-------:|:-------|
| k3s-dev-m01 |     6 | 16 GB |  80 GB | prox04 |
| k3s-dev-m02 |     6 | 16 GB |  80 GB | prox04 |
| k3s-dev-w01 |     6 | 24 GB |  80 GB | prox04 |

All VM's run Debian (12.2 at the moment) and are provisioned using [Ansible](https://docs.ansible.com/ansible/2.9/modules/proxmox_kvm_module.html) with some help from [cloud-init](https://canonical-cloud-init.readthedocs-hosted.com/en/latest/).
The starting point is a [Debian 12 cloud-init image](https://cloud.debian.org/images/cloud/bullseye/) prepaired as template which largely speeds up the deployment of VM's.

An SSH key-pair must be available to enable SSH access to the hosts with Ansible, generated with:

```shell
> ssh-keygen -b 4096 -t ed25519 -f mainuser_key -C "MainUser for K3s"
```

The private key must be kept secure (on the local machine) and the public key should be installed with `cloud-init` on each node so that Ansible can connect to them.

## Create a VM template

Using a Debian 12 cloud-init image, we first create a VM template in Proxmox.
Just SSH into the Proxmox host and run the following commands (check the URL to select the latest Debian image):

```shell
wget https://cloud.debian.org/images/cloud/bookworm/20230910-1499/debian-12-genericcloud-amd64-20230910-1499.qcow2
qm create 8010 --memory 4096 --name debian-12-cloudinit --net0 virtio,bridge=vmbr100
qm importdisk 8010 debian-12-genericcloud-amd64-20230910-1499.qcow2 local-lvm
qm set 8010 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-8010-disk-0
qm set 8010 --ide2 local-lvm:cloudinit
qm set 8010 --boot c --bootdisk scsi0
qm set 8010 --serial0 socket --vga serial0
```

To minimize dependancies and maximize deployment speed, a template is created on `local-lvm` storage on eacallh Proxmox cluster nodes, each with a unique VMID (use 8010, 8011, 8012).
Fill in the cloud-init parameters and upload the SSH public key before creating a template from this VM image in the Proxmox GUI.

> If you run `ceph` on the Proxmox cluster, that wpuld also be an option to make the template available on all PVE nodes.

## Deploy Rancher for cluster management

Deploy an Ubuntu VM
Deploy Docker
Run docker command:

```bash
sudo mkdir /opt/rancher
docker run -d --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -v /opt/rancher:/var/lib/rancher \
  --privileged \
  rancher/rancher:latest
```

## Prepare for Kubernetes deployment

Ansible VM provisioning uses the PVE API and requires a userid and password specified in the `group_vars` file.
The VM's are deployed with reserved IP addresses by registering their MAC address (configured during Ansible deployment) in DHCP so that we can easily pre-populate the `hosts.yml` file used by Ansible in the playbook used to create the cluster nodes.
DNS could also be used, but since I prefer to give my core server workloads a 'fixed' IP, I can use IP addresses just as easily.

An example `hosts.yml` for a 6-node cluster:

```yaml
# file: inventory/[ENV]/hosts.yml
# synopsis: K3s VM configuration parameters used by Ansible.
---
all:
  children:
    # The node IP addresses are predefined as reserved IPs (based on MAC address) in the DHCP server.
    kube:
      children:
        master:
          hosts:
            k3s-prod-m01:
              host_address: 10.100.3.21
              node: prox01
              vmid: 8001
              newid: 2001
              memory: 12288
              disk_size: 107374182400
              cores: 6
              mac: '02:be:11:64:03:21'
            k3s-prod-m02:
              host_addres: 10.100.3.22
              node: prox02
              vmid: 8002
              newid: 2002
              memory: 12288
              disk_size: 107374182400
              cores: 6
              mac: '02:be:11:64:03:22'
            k3s-prod-m03:
              host_address: 10.100.3.23
              node: prox01
              vmid: 8001
              newid: 2003
              memory: 12288
              disk_size: 107374182400
              cores: 6
              mac: '02:be:11:64:03:23'
        worker:
          hosts:
            k3s-prod-w01:
              host_address: 10.100.3.24
              node: "prox01"
              vmid: 8001
              newid: 2004
              memory: 16384
              disk_size: 107374182400
              cores: 6
              mac: '02:be:11:64:03:24'
            k3s-prod-w02:
              host_address: 10.100.3.25
              node: prox02
              vmid: 8002
              newid: 2005
              memory: 16384
              disk_size: 107374182400
              cores: 6
              mac:  '02:be:11:64:03:25'
            k3s-prod-w03:
              host_address: 10.100.3.26
              node: prox02
              vmid: 8002
              newid: 2006
              memory: 16384
              disk_size: 107374182400
              cores: 6
              mac:  '02:be:11:64:03:26'
    pve:
      children:
        proxmox:
          hosts:
            prox01:
              host_address: 10.0.0.11
              mgmt_nic: eno1
              vm_nic1: enp3s0
              vm_nic2: enp4s0
              mgmt_ip: "10.0.0.11/24"
              mgmt_gw: "10.0.0.1"
              bridge_ip: "10.100.0.11/22"
            prox02:
              host_address: 10.0.0.12
              mgmt_nic: eno1
              vm_nic1: enp2s0f0
              vm_nic2: enp2s0f1
              mgmt_gw: "10.0.0.1"
              mgmt_ip: "10.0.0.12/24"
              bridge_ip: "10.100.0.12/22"
            prox03:
              host_address: 10.0.0.13
              mgmt_nic: eno1
              vm_nic1: enp2s0f0
              vm_nic2: enp2s0f1
              mgmt_gw: "10.0.0.1"
              mgmt_ip: "10.0.0.13/24"
              bridge_ip: "10.100.0.13/22"
        pvemain:
          hosts:
            prox01:
              host_adress: 10.0.0.11
```

The API parameters needed to access the Proxmox cluster are located in the `group_vars/all.sops.yaml` variables file (which will be encrypted as described below).
An example of the variables needed during VM deployment:

```yaml
# Proxmox authentication variables:
pve_api_user: deployemnt_user@pam
pve_api_password: sUperSeCret!Pa$$w00rd
pve_api_host: 10.0.0.11
# SSH key to inject
pve_ssh_key: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACA....GS3KZjJFhh44PYYn+6nQ== MainUser key
# DNS servers used by the nodes
pve_dns_servers: 10.0.0.10 10.0.0.1
# Search domain set in the network interface configuration of the VMs
pve_domain: example.com
# VM cloning template used (cloud-init based)
ci_template_name: debian-12-cloudinit
# User with SSH access to the VMs
ansible_user: mainuser
# PVE VM bridge
vm_bridge: vmbr100
```

Before the Ansible playbook can deploy a complete Kubernetes cluster, a few tools must be installed on the local machine.
Obviously, [Ansible](https://github.com/ansible/ansible) 2.12 or higher is needed (shouldn't be a problem because 2.15 is currently the latest version); check with `ansible --version`.
`Helm` is used to perform test deployments of certain functionality, so let's install `Helm` version 3 (check with `helm version`); currently v3.13.
On MacOS, it is recommended to use [brew](https://brew.sh/) for installation of these tools.

Since there is sensitive data in parameter files, we use [Mozilla SOPS](https://github.com/mozilla/sops) and [age](https://github.com/FiloSottile/age) for encryption and decryption.
See below for installation and usage instructions.

Start by cloning the [GitHub repository](https://github.com/crazyelectron-io/ansible-k3s-cluster) with these deployment files.
The Ansible playbook assumes a certain directory structure as layed out below.
The `./roles` directory holds all the different roles installed with Ansible, the `./inventory/[ENV]` directory has the host definitions and the `./inventory/[ENV]/group_vars` directory has all global parameters used by Ansible.
Because we use both local and external roles a directory structure that can easily distinguish between them is defined: all local roles are in the `./roles/local` directory and the imported roles in the `./roles` directory with a `.gitignore` to prevent them from being commited to the local repository.

```yaml
.
├── inventory
│   ├── dev
│   │   └── group_vars
│   └── prod
│       └── group_vars
└── roles
    ├── debian-base
    │   ├── defaults
    │   ├── files
    │   │   └── fonts
    │   ├── handlers
    │   ├── meta
    │   ├── tasks
    │   ├── templates
    │   └── vars
    ├── debian-upgrade
    │   ├── meta
    │   └── tasks
    ├── k3s-prereq
    │   ├── defaults
    │   ├── meta
    │   └── tasks
    ├── k3s-reset
    │   ├── meta
    │   └── tasks
    ├── linux-sensors
    │   ├── defaults
    │   ├── meta
    │   ├── tasks
    │   └── vars
    ├── local
    │   ├── common
    │   │   ├── flux
    │   │   │   └── tasks
    │   │   └── ssh-reset
    │   │       └── tasks
    │   ├── k3s
    │   │   ├── _context
    │   │   │   ├── tasks
    │   │   │   └── templates
    │   │   ├── fluxcd
    │   │   │   ├── defaults
    │   │   │   └── tasks
    │   │   ├── k3s-master
    │   │   │   ├── defaults
    │   │   │   ├── tasks
    │   │   │   └── templates
    │   │   ├── k3s-post
    │   │   │   ├── defaults
    │   │   │   ├── tasks
    │   │   │   └── templates
    │   │   ├── k3s-reset
    │   │   │   └── tasks
    │   │   ├── k3s-worker
    │   │   │   ├── tasks
    │   │   │   └── templates
    │   │   └── labels
    │   │       └── tasks
    │   ├── proxmox
    │   │   ├── pve-deploy
    │   │   │   ├── defaults
    │   │   │   ├── tasks
    │   │   │   └── vars
    │   │   ├── pve-host-base
    │   │   │   ├── defaults
    │   │   │   ├── tasks
    │   │   │   ├── templates
    │   │   │   └── vars
    │   │   └── vm-destroy
    │   │       ├── defaults
    │   │       ├── tasks
    │   │       └── vars
    │   └── sops
    │       └── tasks
    └── reboot
        ├── defaults
        ├── meta
        └── tasks
```

After cloning this repo, import roles with `ansible-galaxy install -r roles/requirements.yaml`, which retrieves them from GitHub and stores them in the `roles` directory.
To force an update of these roles, add the `-f` parameter.

In the following paragraphs the parameters to adjust will be covered, but first let's make sure these super secret variables are kept away from prying eyes.

## Keeping our secrets secret with encryption

Secrets are an important part of every IaC deployment and to ensure these parameters can be used without compromising the environment when the code is committed to a GitHub repository or otherwise shared, we need an encryption/decryption mechanism.
This is needed both during automated cluster bootstrapping with Ansible, as well as when deploying workloads on Kubernetes with Flux.
These secrets have to be readable for automated deployments when needed and secured from prying eyes when stored locally or in GitHub repositories.
There are many ways to deal with secrets, all with their own pro's and con's, but I use [Mozilla SOPS](https://github.com/mozilla/sops), mainly because it integrates quite nicely with Kubernetes and [Visual Studio Code](https://code.visualstudio.com/), but more on that later.
We could also opt for a key vault solutions to store the secrets but that creates another dependancy and increases the cost.

SOPS provides a simple CLI that can interpret key/value entries in configuration files and encrypt only the relevant value parts of designated keys so that the file is still 'readable'.
You can use [age](https://github.com/FiloSottile/age) or OpenPGP for the key to encrypt and decrypt the content (SOPS also supports Azure Key Vault and AWS KMS).

### Encryption/decryption with age

Currently the [age](https://github.com/FiloSottile/age) encryption/decryption tool is recommened by Mozilla in combination with `SOPS`.

Install `age` (and sops) with `brew install sops age` on your local MacOS system (refer to the [`age`](https://github.com/FiloSottile/age) documentation for other installation options).
Create a private/public key pair with `age-keygen -o ~/.sops/key.txt`.
Manually encrypting a secret is done with the command:

```shell
sops --encrypt --age $(cat $SOPS_AGE_KEY_FILE | ggrep -oP "public key: \K(.*)") --encrypted-regex '^(data|stringData)$' --in-place [YOUR_FILENAME].
```

> On MacOS the default `grep` command does not support the `-oP` options.
> You should install the GNU version which does support this option with `brew install ggrep`.

### Encrypting and decrypting secrets

To simplify running SOPS, create a `.sops.yaml` file in the root of the repo to specify the `SOPS` parameters for encryption of the secrets inside YAML file(s).

```yaml
# file: ./.sops.yaml
# synopsis: define the files and keys to encrypt with SOPS within this repository.
creation_rules:
  - path_regex: .*group_vars/.*
    age: age1u07cpzdmuthtk83dzsqdv2s8s4gxzdfv86t6tzny64tvs7e3hfcqflnfk8
  - path_regex: .*host_vars/.*
    age: age1u07cpzdmuthtk83dzsqdv2s8s4gxzdfv86t6tzny64tvs7e3hfcqflnfk8
```

The encryption key is specified with the `age` parameter and holds the public key from `~/.sops/key.txt`.
The `path_regex` entry specifies for which files and directories this specification is valid.
With `.*group_vars/.*` we specify that the SOPS parameters specified are valid for all files in the `group_vars` directory and its subdirectories (which will only contain YAML files).
There can be multiple `.sops.yaml` files in different directories, but remember that we have to initially encrypt each file seperately.

With the `.sops.yaml` file in place we can run `sops --encrypt --in-place [YOUR_SECRET_FILE.YAML]` to encrypt data entries in a YAML file in any of the directories in or below the current directory where `.sops.yaml` is located.

By adding other expressions to `encrypted_regex` it is possible to handle different key values, also in other file types like `.env` or `.json`, or even use `gpg` alongside `age` (not recommended).

> There is also a rule for `host_vars` files which are currently not used.

We can also use an extension for VS Code to transparently deal with SOPS encrypted files.
There are a few to choose from, but I use [@signageos/vscode-sops](https://github.com/signageos/vscode-sops) which transparently decrypts and re-encrypts files while viewing and editing these files.

Fortunately, the Ansible plugin for SOPS integration is now also available for MacOS, so we let ansible decrypt `group_vars` files automanually when loading the variables in memory.
Since there are multiple keys to encrypt in the `group_vars` file, we simply encrypt them all (that ensures we don't mis any) usinga `./inventory/[ENV]/.sops.yml` file, like this:

```yaml
# file: .sops.yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    age: age1u07cpzdmuthtk83dzsqdv2s8s4gxzdfv86t6tzny64tvs7e3hfcqflnfk8
```

With `encrypted_regex` we specify which key/value entries should have their value encrypted and use standard regex syntax for that.
The example above specifies that only the keys `data` and `stringData` should have its value encrypted; if you omit this, all keys will be encrypted.

Now we can encrypt the specified key values in the main configuration file `inventory/[ENV]/group_vars/all.sops,yml`.
By adding `sops` to the file name we ensure the dencryption is automatically handled by Ansible.

## Global configuration file all.sops.yaml

The parameters used throughout the playbooks are consolidated in the global configuration file `inventory/[ENV]/group_vars/all.sops.yaml`.
Most of the variables in this configuration file are self-explaining.
You find them both in the `dev` directory and in `prod` to support a production and a development cluster.
The most important parameters to check and possibly change are explained below.
K3s uses Flannel VXLAN as container network by default and we will use that as well.

### ansible_user

The user that will be used by Ansible to connect to the VM's over SSH.
This should match the user defined in `cloud-init` during setup of the VM, with the corresponding key.

### system_timezone

The timezone to be configured on all VM's (should all be equal).
In my case it 's `Europe/Amsterdam`.

### shell_user / shell_group

Shell user and group to setup the bash localization configuration in `.bashrc` (needed because it is not set correctly for my mixed region and language settings).
You may want to skip this by defining them as empty string.

### k3s_version

Specifies the K3s version to deploy.
The latest version is currently _v1.28.2+k3s1_, but since I also use [Rancer](https://github.com/rancher/rancher/releases), we have to stick with _v1.25.6+k3s1_ until 1.28 is also supported.
Make sure to use a version that is supported by [Longhorn](https://longhorn.io/docs/1.4.0/deploy/important-notes/) as well.

### longhorn_chart_version

The Helm chart version (in sync with the Longhorn version deployed) to be used; currently _1.4.0_.

### kube_vip_version

The image tag for `kube-vip`.
Currently _v0.5.9_ is the latest version.

### metal_lb_speaker_tag_version / metal_lb_controller_tag_version

The image tag for Metal LB.
Currently _v0.13.7_ is thre latest version.

### apiserver_endpoint

The API server endpoint VIP (on each master) to use.
This will configure the nodes so that they can communicate with the Kubernetes API server, as well as the entrypoint for external API access.

### k3s_token

The K3S token ensures only allowed nodes can join the cluster.
This token must be alpha numeric only.

### metal_lb_ip_range

Metal LB IP range for load balancer; for example "10.100.3.101-10.100.3.119".

### traefik_cluster_ip

We have to set the Reverse Proxy external IP address through which the web services behind the proxy can be accessed, for example `traefik_cluster_ip: "10.100.3.101"`.
All web services hosted behind the reverse proxy will be accessed through this IP based on the hostname.

### extra_server_args

This parameter defines all the arguments to be passed to the different Kubernetes services, like API server, Kubelet, Kube controller and Kube controller manager.
Since we are using Metall LB, the default K3s installed load balancer should be skipped with the option `--disable servicelb`.
We also skip installation of Traefik for now so that we can do a custom installation with the option `--no-disable traefik`.

Next we have a few options that make sure we can get the cluster metrics:

```yaml
 extra_server_args: >-
  {{ extra_args }} --tls-san {{ apiserver_endpoint }}
  --disable servicelb --disable traefik
  --write-kubeconfig-mode 644
  --etcd-expose-metrics true
  --kubelet-arg node-status-update-frequency=5s
  --kube-apiserver-arg default-unreachable-toleration-seconds=20 --kube-apiserver-arg default-not-ready-toleration-seconds=20
  --kube-controller-arg node-monitor-grace-period=40s`.
```

The other commandline arguments are to ensure Kubernetes detects and reacts to pod and node issues faster allowing faster recovery of pods from failures.

### pve_domain

Specifies the domain used for this cluster when accessing it externally as well as the FQDN domain for the nodes.
Note that this parameter should be encrypted with SOPS if it is replaced by a literal value.

## Install prerequisites on the nodes

Each freshly deployed VM must be setup with the required Linux settings and packages.
As mentioned before, these VMs should be configured with an SSH public key so that Ansible can access and configure them directly.
The _QEMU agents_ can optionally be installed with Ansible so it is a general purpose Debian VM out-of-the-box, except for required and optional Debian packages and configuration settings which can now easily be applied to these VMs.
That way the same VM template can be used for different purposes and the packages to be installed or updated can be specified in the playbook as needed.

## Provision the K3s cluster

### Attach SSD disks to worker nodes

```bash
# --- In the PVE hosts
# For each worker node find and attach the disks (by id)
ls -l /dev/disk/by-id | grep -i samsung
qm set 2004 -scsi1 /dev/disk/by-id/ata_xxxxxxxxxxx
qm set 2004 -scsi2 /dev/disk/by-id/ata_xxxxxxxxxxx
qm set 2004 -scsi3 /dev/disk/by-id/ata_xxxxxxxxxxx
qm set 2004 -scsi4 /dev/disk/by-id/ata_xxxxxxxxxxx

# --- In the worker nodes:
# Remove existing LV (when recreating)
sudo umount /var/lib/longhorn
sudo sudo pvs -a -o+dev_size
sudo lvchange -an /dev/mapper/vglonghorn-lvlonghorn
sudo lvremove /dev/vglonghorn/lvlonghorn
sudo vgremove vglonghorn
sudo pvremove /dev/sdb /dev/sdc /dev/sdd /dev/sde
sudo lvmdiskscan
# Create LV
sudo wipefs --all /dev/sd{b..e}
sudo pvcreate /dev/sdb /dev/sdc /dev/sdd /dev/sde
sudo vgcreate vglonghorn /dev/sdb /dev/sdc /dev/sdd /dev/sde
sudo lvcreate -L 21.82T -n lvlonghorn vglonghorn
sudo mkfs -t ext4 /dev/vglonghorn/lvlonghorn
```

### Deploy the cluster with Ansible

With all the relevant parameters set and the tools installed, the cluster can be deployed.
Ansible uses playbooks and roles to define and run automated commands.
At the highest level it is simply two sets of playbooks to execute, `deploy-hosts.yaml` and `deploy-cluster.yaml`.
The first playbook deploys the VMs on Proxmox and the second one deploys the K3s cluster on those VMs.

For convenience, there is a tiny script that runs this command with all parameters: `k3s-deploy.sh [ENV] [USER]`.

```shell
#!/bin/bash
# file: k3s-deploy.sh
# synopsis: deploy a cluster (specify the environment 'dev' or 'prod' on the command line)

if [ "$#" -lt 2 ]
then
  echo "Error: no arguments supplied."
  echo " Usage: $0 [ENV] [USER]"
  echo "  [ENV] = Environment, e.g. prod"
  echo "  [USER] = Ansible user, e.g. mainuser"
  exit 1
fi

ansible-playbook deploy-hosts.yml --inventory ./inventory/$1 -u root --extra-vars "ansible_user=root k3s_environment=$1"
ansible-playbook deploy-cluster.yml --inventory ./inventory/$1 --key-file $HOME/.ssh/$2_key -u $2 --extra-vars k3s_environment=$1
```

The invoked VM deployment playbook `deploy-hosts.yaml` has two main roles: configure the Proxmox hosts and create the VMs.

```yaml
# file: deploy-hosts.yml
# synopsis: deploy the vm's on proxmox
---
# Configutre the proxmox hosts
- hosts: proxmox
  any_errors_fatal: true
  vars:
    install_in_vm: false
  roles:
    - local/proxmox/pve-host-base
    - linux-sensors

# Deploy the k3s node VMs
- hosts: pvemain
  gather_facts: false
  any_errors_fatal: true
  vars:
    install_in_vm: true
  roles:
    - local/proxmox/pve-deploy
```

The Kubernetes cluster deployment playbook is invoked next and has more steps:

```yaml
# file: ./deploy-cluster.yaml
# synopsis: deploy the K3s cluster
# notes: the local tools kubectl, sops, and flux must be available in the path
---
# Prepare the nodes
- hosts: kube
  gather_facts: true
  any_errors_fatal: true
  become: true
  vars:
    install_in_vm: true
    install_lh_prereq: true
  roles:
    - debian-base
    - debian-upgrade
    - reboot
    - local/common/ssh-reset
    - k3s-prereq

# Deploy the master node(s)
- name: Setup k3s master nodes
  hosts: master
  become: true
  vars:
    install_in_vm: true
  roles:
    - local/k3s/k3s-master

# Deploy the worker nodes
- name: Setup k3s worker nodes
  hosts: worker
  become: true
  vars:
    install_in_vm: true
  roles:
    - local/k3s/k3s-worker

# Setup MetalLB/kube-vip as well as Flux CD
- name: Configure k3s cluster
  hosts: master
  become: true
  vars:
    install_in_vm: true
  roles:
    - local/k3s/k3s-post
    - local/k3s/fluxcd

# Setup K3s cluster basics
- hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - local/k3s/context
    - local/k3s/labels
```

> All steps in the `deploy-cluster.yaml` playbook are idempotent and can be rerun whenever needed, just like the previous playbook `deploy-hosts.yaml`.

First, all packages are updated and some needed or usefull Debian packages are installed, followed by a reboot.

Next **K3s** is installed, starting with the prerequisites and download of the K3s binary, then the _master_ nodes are installed and finally the _worker_ nodes.
This should result in a functional Kubernetes cluster in a matter of minutes.

We will also update the Kubernetes contexts and apply labels to the worker nodes so they can be used for targeting (or avoiding) with _labels_, _taints_ and _tolerations_ in manifests.
Note that this step is run locally and not remote on the cluster nodes.

Finally, Flux is bootstrapped to provide Continuous Deployment for the rest of the cluster components.
After the playbook is finished, check the status of the cluster nodes with:

```shell
$ kubectl get nodes -o Wide
NAME     STATUS   ROLES                       AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION          CONTAINER-RUNTIME
k3sm01   Ready    control-plane,etcd,master   25m   v1.26.1+k3s1   10.100.3.91   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
k3sm02   Ready    control-plane,etcd,master   25m   v1.26.1+k3s1   10.100.3.92   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
k3sm03   Ready    control-plane,etcd,master   25m   v1.26.1+k3s1   10.100.3.93   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
k3sw01   Ready    worker                      24m   v1.26.1+k3s1   10.100.3.94   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
k3sw02   Ready    worker                      24m   v1.26.1+k3s1   10.100.3.95   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
k3sw03   Ready    worker                      24m   v1.26.1+k3s1   10.100.3.96   <none>        Debian GNU/Linux 11 (bullseye)   5.10.0-21-cloud-amd64   containerd://1.6.12-k3s1
```

and the pods with:

```shell
> kubectl get pods -A
NAMESPACE        NAME                                      READY   STATUS    RESTARTS        AGE
kube-system      coredns-5c6b6c5476-hbd6j                  1/1     Running   1 (9m49s ago)   10m
kube-system      kube-vip-ds-l9xt9                         1/1     Running   1 (9m49s ago)   10m
kube-system      kube-vip-ds-w92g7                         1/1     Running   1 (9m47s ago)   10m
kube-system      local-path-provisioner-5d56847996-ntrb9   1/1     Running   1 (9m49s ago)   10m
kube-system      metrics-server-7b67f64457-8j4gm           1/1     Running   1 (9m49s ago)   10m
metallb-system   controller-577b5bdfcc-vlpb5               1/1     Running   1 (9m49s ago)   10m
metallb-system   speaker-bfd2r                             1/1     Running   0               9m13s
metallb-system   speaker-c5564                             1/1     Running   0               10m
metallb-system   speaker-m95kz                             1/1     Running   1 (9m47s ago)   10m
```

> Note: `kubectl taint nodes k3s-prod-m01 k3s-prod-m02 k3s-prod- m03 CriticalAddonsOnly=true:NoExecute` only works at K3s node creation time.

The Kubernetes cluster is up and running but lacks basic functionality like providing secure access to the cluster and managing Secrets, to be added later...

## Using kubectl and VSCode with multiple contexts

When dealing with multiple clusters and workloads in different namespaces, we can make live easier by using cluster context configurations for all our clusters and namespaces as well as Visual Studio Code extensions for Kubernetes.

### Setup kubectl contexts

After running the above playbooks, we end up with a `kubectl` configuration in `$HOME/.kube/[ENV]` specifying a context named `[ENV]` and it is also set as the current context.
We can manage multiple clusters and/or namespaces with `kubectl config` by switching the context.
The context file deployed by the playbook looks like this:

```yaml
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority: {{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}/cluster.crt
    server: https://{{ apiserver_endpoint }}:6443
  name: default
contexts:
- context:
    cluster: k3s-{{ k3s_environment }}
    user: k3s-{{ k3s_environment }}-user
  name: k3s-{{ k3s_environment }}
users:
- name: k3s-{{ k3s_environment }}-user
  user:
    client-certificate: {{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}/client.crt
    client-key: {{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}/client.key
```

It has three sections: `clusters`, `users` and `contexts` and each section can have an array list of entries.
The `context` can optionally also contain a namespace (by default it is `default`), which means that when switching to that context you not only select the user and cluster but also the default namespace for `kubectl`.
To handle multiple contexts for one or more clusters we store the configuration in different directories and add the location of the `kubectl` configuration file to the `KUBECONFIG` environment variable.

```shell
# Contexts should be in ~/.kube/custom-contexts/
CUSTOM_KUBE_CONTEXTS="$HOME/.kube/custom-contexts"
mkdir -p "${CUSTOM_KUBE_CONTEXTS}"

OIFS="$IFS"
IFS=$'\n'
for contextFile in `find "${CUSTOM_KUBE_CONTEXTS}" -type f -name "*.yaml"`
do
    export KUBECONFIG="$contextFile:$KUBECONFIG"
done
IFS="$OIFS"
```

This way multiple configurations are combined and we can check the result with:

```shell
> kubectl config view
```

It is also possible to add extra contexts with different namespaces for the same cluster.
This makes working with resources in a specific namespace easier when using `kubectl`.

To show the current context, use:

```shell
> kubectl config current-context
```

To switch the context to `theborg`, use:

```shell
> kubectl config use-context theborg
```

> Be aware that by default the certificates in K3s expire in 12 months and should be rotated.

The [official Kubernetes documentation](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) has more background information about contexts.

### Context for the new cluster

After (re)installing a K3s cluster, it will have new certificates and keys that need to be added to the existing contexts.
By default the `kubectl` config file has the certificates and keys embedded in the config file when we copy them locally, base64 encoded.
They can be extracted and stored locally resulting in a simple and clean context file for the new cluster.
The following commands are used in the playbook to automatically extract that information and create the needed context files:

```shell
rm -rf {{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}
mkdir -p {{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}
cat {{ kube_root }}/k3s-config | ggrep -oP "certificate-authority-data: \K(.*)" | base64 --decode >{{ kube_root }}/custom-contexts/k3s-{{ k3s_environment}}/cluster.crt
cat {{ kube_root }}/k3s-config | ggrep -oP "client-certificate-data: \K(.*)" | base64 --decode >{{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}}}/client.crt
cat {{ kube_root }}/k3s-config | ggrep -oP "client-key-data: \K(.*)" | base64 --decode >{{ kube_root }}/custom-contexts/k3s-{{ k3s_environment }}/client.key
```

To check that the new cluster is accessible and selected:

```shell
> kubectl cluster-info
Kubernetes control plane is running at https://10.100.3.100:6443
CoreDNS is running at https://10.100.3.100:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://10.100.3.100:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

> kubectl get nodes
NAME                       STATUS   ROLES                       AGE   VERSION
k3tstm1                    Ready    control-plane,etcd,master   20h   v1.25.6+k3s1
k3tstm2.crazyelectron.io   Ready    control-plane,etcd,master   20h   v1.25.6+k3s1
k3tstm3.crazyelectron.io   Ready    control-plane,etcd,master   20h   v1.25.6+k3s1
k3tstw1                    Ready    <none>                      20h   v1.25.6+k3s1
```

### Setup GitOps to manage workload deployments

Nowadays CI/CD is the fashonable way of managing workload deployments.
_Continous Integration (CI)_ takes care of building the needed artifacts from source files whenever a change is committed to a Git repo (basically the _Dev_ part of _DevOps_) and _Continous Delivery (CD)_ deploys those changes automatically (more or less the _Ops_ part of _DevOps_).
[Flux v2](https://fluxcd.io/flux/) is a nice open source tool for GitOps and takes care of the Continous Delivery side using a Git repository to control deployments.

Install Flux on the local machine (macOS in this example) with `brew install fluxcd/tap/flux` (see the [official documentation](https://fluxcd.io/flux/installation/#install-the-flux-cli) for other install options).
Define the GitHub personal access token and username in an environment variable and check if the prerequisites for Flux are covered:

```shell
> export GITHUB_TOKEN=[yOUrsUperSeCrettoKEnHERE]
> export GITHUB_USER=[YourGitHubUserHERE]
> flux check --pre
► checking prerequisites
✔ Kubernetes 1.26.1+k3s1 >=1.20.6-0
✔ prerequisites checks passed
```

### Setup Flux CD

The cluster is also bootstrapped with Flux using a personal GitHub account (indicated with the `--personal` argument) and stored in `./cluster/[ENV]` as part of the `deploy-cluster.yaml` playbook.
As a result of the Flux bootstrap, a GitHub repository is created that should be cloned locally to add and push additional manifests, Kustomizations or Helm charts through GitHub for deployment to the cluster.
Except for some of flux' own manifests, this results in an empty private repository when you bootstrap flux for the first time.
If the repository already exists, the existing content is retained and the Kustomizations, Manifests and Charts are still there, otherwise create the following structure for the Flux repository:

```shell
.
├── cluster
│   └── prod
│       └── flux-system
│           ├── gotk-components.yaml
│           ├── gotk-sync.yaml
│           ├── kustomization.yaml
└── infrastructure
```

this shows both a production and a development cluster in the same repository; separate repositories are also an option but cannot benefit from common definitions and templates.

Clone the Flux repo in a separate directory and add it to the VS Code workspace.

```bash
# Replace with the actual GitHub account and repository
git clone git@github.com:crazyelectron-io/flux-k3s.git
```

To check the status of a GitOps deployment after pushing a commit, run the following command:

```bash
> flux get kustomizations --watch
NAME            REVISION             SUSPENDED       READY   MESSAGE
flux-system     main@sha1:b899ac4    False           True    Applied revision: main@sha1:b899ac4
```

This example shows the initial commit of the Flux system manifests created during bootstrap.

### Handling encrypted Secrets and ConfigMaps with Flux

So far we handled encryption and decryption on the local machine, but we also have to decrypt Kubernetes Secrets and ConfigMaps within the cluster.
Flux has support for SOPS and can decrypt Secrets and ConfigMaps when they are created in the cluster.
It needs the private key in a Kubernetes Secret in the `flux-system` namespace to do its magic.
The private key is extracted in the playbook role `local/ks3/fluxcd` and used as input for the generated Kubernetes Secret `sops-age`.
With that secret Flux can decrypt Secrets and ConfigMaps before creating them in Kubernetes.

For the SOPS VS Code extension we should make sure the environment variable `$SOPS_AGE_KEY_FILE` is defined and references the `~/.sops/key.txt` file created before.

### Encrypting your secrets

[ #TODO: Description of encryption process ]

### Decryption in Kubernetes

Last automated encrypt/decrypt scenario step is to tell Flux how to decrypt the encrypted files by adding the following lines to the `clusters/{{ k3s_environment }}/flux-system/gotk-sync.yaml` manifest (at the start of the `spec` section of the `Kustomization`) and commit it to the repository:

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

We should also commit the `age` public key to the repository so that others that clone the repo can encrypt new files as well (but not decrypt them!).
Store the public key (extracted from `~/.sops/key.txt`) in `../flux-k3s/cluster/bootstrap/.sops.pub.age` and commit this to the branch with:

```shell
> cat $SOPS_AGE_KEY_FILE | ggrep -oP "public key: \K(.*)" > ../flux-k3s/clusters/[ENV]/.sops.pub.age
> git add ../flux-k3s/clusters/[ENV]]/.sops.pub.age
> git commit -am 'Share age public key for secrets generation'
```

As a result, any Secret encrypted and commited to the GitHub repo is decrypted in the cluster by Flux before the resource is created.
Validate this by creating a dummy secret and see how it gets handled in Kubernetes by creating, encrypting and committing this sample manifest to the flux repository:

```yaml
# ./app/default/test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
    name: test-secret
    namespace: default
type: Opaque
stringData:
  myKey: super$ecretKey##
```

Encrypt the file with:

```shell
sops -e -i ./app/default/test-secret.yaml
```

The encrypted file should look like this:

```yaml
# file: app/default/test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
    name: test-secret
    namespace: default
type: Opaque
stringData:
    myKey: ENC[AES256_GCM,data:E49uYFGr6CwNrsGHRSfhpw==,iv:YGqyMAQsKbfu4nBPdpv9CGGVtaACGGPfHfVAzN8S/1Y=,tag:UUlb0KOgo1A23G2SWYBFeA==,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1u07cpzdmuthtk63dxsqdv2s0s4gxxvfv86t6tzny64tvt7e3hfcqflnfk8
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSAzcEpROWlHcythN2twVlQ3
            MHFMeFpFcVlSdXFhK3REQVBJa3IyNUdLRDNRCjRjZExPbVF4MFRGZmJOWFlHd29F
            bFQycFVQVGtaSDJRY0R6NnJVQXorb0UKLS0tIGRoUkRHK0J4UDRGcTNmTmJsQkxK
            VzRFd0lkQlBDdWZsSHE1SlRHdlI0RXMKsIvTEA56yPo3ka/ltTQrnB8Uf8srZpS+
            7UAGqvC+tWTSI3ycbWTkCANvD6YawwXHIpLUkqkMCTwqe129FzIm8A==
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2023-03-01T08:58:52Z"
    mac: ENC[AES256_GCM,data:te0G8vYhso4fJZXa0h0aA1s1AuDcUAKgw8R9ofI8QJGNmbwRI5j+fJ8WZzKozRMWCj18a/TXsJ7YRA/PKG/89HCTZQEO3XKZC01D2DkBWS3oVJUfpo+U8+jwxQ1yjWpz9zVsomhH9+14vL3uxpU/rwFZcaYQvJqp+1n9/LdN4Yw=,iv:ROMRSapgl4nh00A9tu7qjnP9SXVFiOhcyiJxZbDKRLY=,tag:wZeCZ6sapR3VZheJe5uA/Q==,type:str]
    pgp: []
    encrypted_regex: ^(data|stringData)$
    version: 3.7.3
```

Commit this encrypted secret to the Flux repository and check for its result:

```shell
git add -A
git commit -m "Test encryption of Secret"
git push
flux get kustomizations --watch
```

Once the Secret is created in Kubernetes you can check its content with:

```shell
kubectl get secret test-secret -o jsonpath="{.data.myKey}" | base64 --decode
```

which should show the original unencrypted content.
Remove the test Secret again to cleanup (`kubectl delete secret test-secret`).

## Setup Flux repository for K3s core workloads

The `flux-k3s` repository needs the followoing directory structure:

```shell
.
├── apps
│   ├── cert-manager
│   ├── external-dns
│   ├── letsencrypt
│   ├── metallb
│   └── traefik
└── cluster
    └── bootstrap
        ├── flux-system
        ├── helmrepositories
        ├── kustomizations
        └── namespaces
```

The `age` public key and the `.sops.yaml` files are placed in the root and the `gotk-sync.yaml` has the age decrypt specification added.

## Deploy cluster workloads

The cluster is now ready for GitOps CD and you can deploy workloads through Flux by committing new manifests to the repository.

### Install Metal LB

```shell
 #TODO:
```

## Install external-dns

```shell
#TODO:
```

### Install cert-manager

We will deploy the latest (currently v1.11.0) CRD's and deployment manifests for `cert-manager` with Flux.
The manifests are already in the example repository, but a newer version can be downloaded if needed from the [Jetstack GitHub repository](https://github.com/cert-manager/cert-manager/releases).
The downloaded deployment manifests needs some tweaking to make it fit for our purpose.
The example below shows using Cloudflare as the primary DNS provider and Google DNS as secondary.
First, change the `replicaCount` parameter of the `cert-manager` deployment to 3 from its default value of 1.
Next, add the following to the end of that same deployment (below `nodeSelector`):

```yaml
      dnsPolicy: None
      dnsConfig:
        nameservers:
          - "1.1.1.1"
          - "8.8.8.8"
```

And finaly add the following to the `args` parameter:

```yaml
          args:
          - --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53
          - --dns01-recursive-nameservers-only
```

Commit and push the change and check the Flux status with:

```shell
> flux get kustomizations --watch
flux-system     main/b899ac44fd51ea0a7cd53fed56b4c48543bb2307   False   Unknown Reconciliation in progress
flux-system     main/b899ac44fd51ea0a7cd53fed56b4c48543bb2307   False   Unknown Reconciliation in progress
flux-system     main/b899ac44fd51ea0a7cd53fed56b4c48543bb2307   False   Unknown Reconciliation in progress
flux-system     main/b899ac44fd51ea0a7cd53fed56b4c48543bb2307   False   Unknown Reconciliation in progress
flux-system     main/b899ac4    False   True    Applied revision: main/5ddd522
flux-system     main/5ddd522    False   True    Applied revision: main/5ddd522
```

Here it shows that commit **main/5ddd522** has been applied sucessfully.
You can also check the deployment status of cert-manager with `kubectl get pods -n cert-manager`.

Later we will install Traefik and configure Let's Encrypt (LE) as certificate authority that uses DNS-01 ACME to validate certificate requests.
Cloudflare hosts our example domain and we need to generate an API token in Cloudflare to create DNS entries for LE DNS validation.
Store the Cloudflare token in Kubernetes and ensure it is stored encrypted in the GitHub repository:

```shell
> sops --encrypt --in-place ./cluster/example/cert-manager/cloudflare-secret.yaml
```

The above command assumes that a `.sops.yaml` file is in place that defines the regex and encryption key for `SOPS`.
The resulting manifest looks like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: cloudflare-token-secret
    namespace: cert-manager
type: Opaque
stringData:
    cloudflare-token: ENC[AES256_GCM,data:2iRG7MjdpDdxmc1EieZY/w1zcm2iJeoepNN2di8uczHp7y54Zqpj+w==,iv:e1Witf/DiEhdYwRYvB/LtQ8e3al8oSXZFFrAkDaxau4=,tag:pESbjI9gjqPs0VuBEcnhDg==,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age: []
    lastmodified: "2023-02-15T19:53:49Z"
    mac: ENC[AES256_GCM,data:8X6S8k0JpTxNnXgmDw4u/f7YmBC6ILpejl+gxIqUiRG1WICLpX7xUJ47C/g3xsB0+vfWbTuo/lvC/hW9wCPz+ZBx3jJiPV0s0P0Vi8qZY3+9fMjt7Bhelvbhs27KSJM1Z6CWVNExm1l59/Rtgna+C5lGqzxmPuXy1QKEzFF3uIc=,iv:TMXxeb2Qv3BulIS1htGW/knZeN7qUah7Gb0YUx0d2bU=,tag:HQbhN3kwBhf8a4/XzdIT7g==,type:str]
    pgp:
        - created_at: "2023-02-15T19:53:48Z"
          enc: |
            -----BEGIN PGP MESSAGE-----

            hQIMA4ieJf7RD0z7ARAAtxCBmmtO8MaOG1WGNy3Pju5p9GRZmlzwHGkLzwxYJjJw
            sRHHUP0K76qr2YJWhci6vARyfNerr5YdPvNw6+NWSiKeC2UkfsPgrv7+3rULU9vJ
            ZVN9O/NmFJR1certzGkth4FwVmqpKXuZiMnh7nABkmGJXwAwyLC3Ctub0HUGcgAF
            N4WYZJ8BxI5QoBrOCdaUoYD7W3N6bttqNMoN9z9Es8nem7GGftYJsrpSF+T4eXld
            q2oMFP5dPfE3JOK3q0jSN1+DFoblmUnXn2zW0ZqgLN9U4DH1zDxhNJzFp75sqTXX
            6j+QBm/kGWtBr4Nx87zmKgeV0X/+nuxvKTRMjCQPFhw2xz2bZYvbmcTLkdqybU0q
            4BnMMZNZAK31xYKYm1vgGdjGpyaNMNzEOUssNsXVQhnNzNYgbTPKahBnAF7lyTto
            UCYUa0ESiwTJH/Lgs7CXgXZ73R7itejDR43DsStwEV/kaGJXfo8MjbYgOXK+3piG
            igNaI0pTgwpfvt5bSFqJBen5oLK8NCWyzluVqJbOVWnPcfRE3Jh3VUnddXP0+7Kk
            8Nv0yssWBekj7Mm4tHzQt/2bzzTGDvvJi15Jm2WSlnbiDEWmYcPAhwZmNGmAXetf
            4PPtHyQHhbK84aX5FAgnOeEk+VB6ZYmdoite3fvTP5OGbdzhFJaUE5awOjOtSYrU
            aAEJAhBzRl7tViyCOnpcHkWYlvD3s0z0CT+0CS9CawGL/W8cFAZ6DJoBJveXCAa1
            DngPrMs8ZX0kC6WxGaYaTW+uz7H7pSP4sTBh0mCV1NGfp0F0dYGpYjbgMHfMgQzW
            +jMB6tURP6cP
            =JgBd
            -----END PGP MESSAGE-----
          fp: B5603692D4ED1EB04BF2AF3C2E78F6DEFCF961F9
    encrypted_regex: ^(data|stringData)$
    version: 3.7.3
```

Commit the change to GitHub and check that you can read the Secret from within Kubernetes:

```shell
> kubectl get secret -n cert-manager cloudflare-token-secret -o jsonpath="{.data.cloudflare-token}" | base64 --decode
```

A `ClusterIssuer` must be create to enable the generation of a Let's Encrypt certificate through DNS-01 validation by `cert-manager`.
The manifest looks like shown below and should be placed in `./cluster/example/cert-manager` (make sure to adjust the parameters):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: "me@crazyelectron.io"  # TODO: Chaneg to your configuration
    server: "https://acme-v02.api.letsencrypt.org/directory"
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            email: "me@crazyelectron.io"  # TODO: Chaneg to your configuration
            apiTokenSecretRef:
              name: cloudflare-token-secret
              key: cloudflare-token
        selector:
          dnsZones:
            - crazyelectron.io  # TODO: Chaneg to your configuration
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: "me@crazyelectron.io"  # TODO: Chaneg to your configuration
    server: "https://{acme-staging-v02.api.letsencrypt.org/directory"
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - dns01:
          cloudflare:
            email: "me@crazyelectron.io"  # TODO: Chaneg to your configuration
            apiTokenSecretRef:
              name: cloudflare-token-secret
              key: cloudflare-token
        selector:
          dnsZones:
            - crazyelectron.io  # TODO: Chaneg to your configuration
```

When applying the manifest through Flux it creates two ClusterIssuers, one for production and one for staging (so we can test deployments over and over again without hitting the LE limits).

### Secrets and ConfigMap replication

In Kubernetes, Secrets and ConfigMaps are scoped to a namespace but sometimes you need them also in another namespace.
That's where a replicator provides a solution; Secrets and ConfigMaps that are labeled for replication will be automatically replicated to other namespaces (either explicitly specified or to all new namespaces).
We will deploy the Kubernetes controller [Mittwals Replicator](https://github.com/mittwald/kubernetes-replicator) with the following manifest that should be placed in `./cluster/example/kube-system`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: replicator-kubernetes-replicator
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: replicator-kubernetes-replicator
rules:
- apiGroups: [ "" ]
  resources: [ "namespaces" ]
  verbs: [ "get", "watch", "list" ]
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets", "configmaps"]
  verbs: ["get", "watch", "list", "create", "update", "patch", "delete"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["get", "watch", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: replicator-kubernetes-replicator
roleRef:
  kind: ClusterRole
  name: replicator-kubernetes-replicator
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: replicator-kubernetes-replicator
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: replicator-kubernetes-replicator
  namespace: kube-system
  labels:
    app.kubernetes.io/name: kubernetes-replicator
    app.kubernetes.io/instance: replicator
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: kubernetes-replicator
      app.kubernetes.io/instance: replicator
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kubernetes-replicator
        app.kubernetes.io/instance: replicator
    spec:
      serviceAccountName: replicator-kubernetes-replicator
      securityContext: {}
      containers:
      - name: kubernetes-replicator
        securityContext: {}
        image: quay.io/mittwald/kubernetes-replicator:latest
        imagePullPolicy: Always
        args: []
        ports:
        - name: health
          containerPort: 9102
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: health
        readinessProbe:
          httpGet:
            path: /healthz
            port: health
        resources: {}
```

To flag a Secret for replication, you can choose between name-based and label-based replication.
I prefer to use the label-based aproach that allows you to label a Secret or ConfigMap for replication using an annotation like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  annotations:
    replicator.v1.mittwald.de/replicate-to-matching: >
      my-label=value,my-other-label,my-other-label notin (foo,bar)
data:
  key1: <value>
```

### Longhorn cluster storage

And _Longhorn_ is installed as the distributed cluster storage, which makes `PersistentVolumes` available throughout the cluster through replication.
Longhorn is installed on all nodes so every node can access the storage of the cluster, but the disks are only attached to the worker nodes (using QEMU passthrough).
Since there are three worker nodes in our main cluster, the `longhorn` storage class is configured for 3 replications.

## Traefik IngressRoute

We use Traefik for all traffik that needs external HTTPS access to services and pods inside the cluster.
Installation of Traefik is straightforward with the Helm chart, just define a Helm Repository and Release for Flux Kustomization and provide a few settings through Helm _values_:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 1m
  url: https://traefik.github.io/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 5m
  chart:
    spec:
      chart: traefik
      version: '21.1.0'
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: traefik
      interval: 1m
  values:
    image:
      name: traefik
      tag: "2.9.8"
      pullPolicy: IfNotPresent
    deployment:
      enabled: true
      replicas: 3
      annotations: {}
      podAnnotations: {}
      additionalContainers: []
      initContainers: []
    ingressRoute:
      dashboard:
        enabled: false
    providers:
      kubernetesCRD:
        enabled: true
        ingressClass: traefik-external
      kubernetesIngress:
        enabled: true
        publishedService:
          enabled: false
    logs:
      general:
        level: DEBUG
      access:
        enabled: true
        bufferingSize: 100
    metrics:
      prometheus:
        entryPoint: metrics
    globalArguments:
      - "--global.checknewversion=false"
      - "--global.sendanonymoususage=false"
    additionalArguments:
      - "--serversTransport.insecureSkipVerify=true"
      - "--log.level=DEBUG"
    ports:
      traefik:
        port: 9000
      web:
        redirectTo: websecure
      websecure:
        tls:
          enabled: true
        middlewares: []
      metrics:
        port: 9100
        expose: false
        exposedPort: 9100
        protocol: TCP
    service:
      enabled: true
      type: LoadBalancer
      annotations: {}
      labels: {}
      spec:
        # TODO: Change IP address to match your network
        loadBalancerIP: 10.100.3.101
      loadBalancerSourceRanges: []
      externalIPs: []
    rbac:
      enabled: true
    resources:
      requests:
        cpu: "100m"
        memory: "80Mi"
      limits:
        cpu: "300m"
        memory: "180Mi"
    securityContext:
      capabilities:
        drop: [ALL]
      readOnlyRootFilesystem: true
      runAsGroup: 65532
      runAsNonRoot: true
      runAsUser: 65532
    # podSecurityContext:
    #   fsGroup: 65532
```

Traefik provides a simple dashboard to show the services, routes, etc. and their status, but even though it is read-only, you don't want to allow unauthorized access.
By adding BasicAuth to the the dashboard it is secured with a username and password (to be generated with `htpasswd` and placed in the Secret shown below).
First, a Middleware must be created to 'intercept' the connection to the dashbloard and add authentication to it.

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: traefik-dashboard-basicauth
  namespace: traefik
spec:
  basicAuth:
    secret: traefik-dashboard-auth
```

Next, the dashboard must be exposed and secured with a certificate for HTTPS.
The manifest shown below uses the Let's Encrypt production environment which provides certificates trusted by every browser but has rate limits to take into account.
For testing purpose it woiuld be best to use the Let's Encrypt staging environment.
This can easily be done by replacing `prod` in the Secrets and Certificates to `staging` because we already deployed the staging ClusterIssuer alongside the production issuer.

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
  annotations:
    kubernetes.io/ingress.class: traefik-external
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`traefik.crazyelectron.io`) # TODO: Change to the correct FQDN for dashboard access
      kind: Rule
      middlewares:
        - name: traefik-dashboard-basicauth
          namespace: traefik
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    secretName: "traefik-dashboard-prod-tls"
---
# Make sure there is a Public DNS entry for the FQDN for DNS-01 ACME LE validation
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik-dashboard-cert-prod
  namespace: traefik
spec:
  secretName: "traefik-dashboard-prod-tls"
  issuerRef:
    name: "letsencrypt-prod"
      kind: ClusterIssuer # TODO: Change to the correct DNS name(s)
  dnsNames:
    - "traefik.crazyelectron.io"  # TODO: Change to the correct DNS name(s)
```

And finally the secret must be created (and encrypted with SOPS):

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: traefik-dashboard-auth
    namespace: traefik
type: Opaque
data:
    users: YmVoZWVyZGVyOiDhcHIxJGlEeE8FdGw1JE14ZGpMb3k5cHguSC5XdWlQMHd4eC4KCg==
```

Check the resulst by going to the Traefik dashboard URL with the browser and see the routers and services managed by Traefik once you logged in.
We have our first service running that is accessible to the outside world!

## Container image registry

To run a flexible cluster where nodes and pods can be started, stopped, redeployed, updated and deleted as needed, we may hit the rate limits of [Docker Hub](https://hub.docker.com/), which is not very high ast 200 per 6 hours for anonymous requests considering that every check with Docker Hub for the presence of an (updated) image will count.
You can pay a monthly fee to get a much higher limit, but you can also deploy a local registry for container images.
Deployments will also be much faster in most cases because you have the full bandwidth of the local network and storage available for pulling an image.

To access the container registry from outside the cluster (so we can easily upload new images), we'll use Traefik to provide the Ingress and generate a BasicAuth username and password with `htpasswd` (part of `apache-utils`).
Generate a secure username and password with:

```bash
> htpasswd xxxxxxxx xxxxxxx
```

This secret needs to be stored in Kubernetes and encrypted locally in the repository and encrypted with `sops`.

```yaml
# Create registry password secret
kind: Secret
apiVersion: v1
metadata:
    name: docker-registry-htpasswd
    namespace: default
stringData:
    htpasswd: user:$2y$05$oZpx45k3hgHGya1Wu24Mr.McHsJFEirMnDYAmD2GY/WT4ZrIQ1kmK
```

The manifest for registry deploment:

```yaml
---
# Create Docker Registry certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: docker-registry-certificate
  namespace: default
spec:
  secretName: docker-registry-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "docker.crazyelectron.io"
  dnsNames:
    - "docker.crazyelectron.io"
---
# Create Container Registry PVC
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: docker-registry-pvc
  namespace: default
spec:
  storageClassName: longhorn
  # persistentVolumeReclaimPolicy: Retain
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
# Create Container Registry Service
apiVersion: v1
kind: Service
metadata:
  name: docker-registry-service
  namespace: default
spec:
  selector:
    app: docker-registry
  ports:
    - protocol: TCP
      port: 5000
---
# Create Private Registry Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: default
  labels:
    app: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
        - name: docker-registry
          image: registry
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5000
          volumeMounts:
            - name: storage
              mountPath: /var/lib/registry
              readOnly: false
            - name: htpasswd
              mountPath: /auth
              readOnly: true
          env:
            - name: REGISTRY_AUTH
              value: htpasswd
            - name: REGISTRY_AUTH_HTPASSWD_REALM
              value: Docker Registry
            - name: REGISTRY_AUTH_HTPASSWD_PATH
              value: /auth/htpasswd
            - name: REGISTRY_STORAGE_DELETE_ENABLED
              value: "true"
            - name: REGISTRY_HTTP_ADDR
              value: :5000
            - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
              value: /var/lib/registry
          resources:
            limits:
              cpu: 100m
              memory: 200Mi
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: docker-registry-pvc
        - name: htpasswd
          secret:
            secretName: docker-registry-htpasswd
---
# Create IngressRoute for Docker Registry public access
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: docker-registry-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: traefik-external
spec:
  entryPoints:
    - websecure
  routes:
    - match: "Host(`docker.crazyelectron.io`)"
      kind: Rule
      services:
        - name: docker-registry-service
          port: 5000
  tls:
    secretName: docker-registry-tls
```

To pull an image to a MacOS system with arm64 used te option `--platform linux/amd64` to get an `amd64` version of the image.

```shell
# Get a list of images in the registry
> curl -X GET -u username:password "https://docker.crazyelectron.io/v2/_catalog"
# Get a list of tages for a specific image repository
> curl -X GET -u username:password "https://docker.crazyelectron.io/v2/{repository}/tags/list"
# Get the manifest of an image
> curl -X GET -u username:password "https://docker.crazyelectron.io/v2/{repository}/manifests/{tags}"
{
   "schemaVersion": 1,
   "name": "eclipse-mosquitto",
   "tag": "2.0.15",
   "architecture": "arm64",
   ...
# To get the digest of an image
> curl -X GET -u username:password https://docker.crazyelectron.io/v2/{repository}/manifests/{tags} -H 'Accept: application/vnd.docker.distribution.manifest.v2+json'
{
   "schemaVersion": 2,
   "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
   "config": {
      "mediaType": "application/vnd.docker.container.image.v1+json",
      "size": 8179,
      "digest": "sha256:8a8daf179f68972469d14a519efcf3c52db5e61e5485a5ac7dcc23a468f9d608"
   },
   "layers": [
      ...
# To delete an image
> curl -X DELETE -u username:password "https://docker.crazyelectrin.io/v2/{repository}/manifests/{digest}"
```

There is also a [nice script](https://github.com/byrnedo/docker-reg-tool) to simplify all these commands.

## MQTT broker with failover

One of the benefits of Kubernetes is its ability to recover from Pod failures (if they are stateless).
By default Mosquitto does not have any kind of HA or fail-over built-in but by creating a bridge between two instances with a load balancer in front we can come close.

## InfluxDB timeseries database

## Flux automatic updates

```bash
> flux create image repository mosquitto-repo \
--image=docker.moerman.online/eclipse-mosquitto \
--secret-ref docker-registry-htpasswd \
--interval=1m \
--export > ./cluster/home/mosquitto-registry.yaml
```

```bash
> flux create image policy mosquitto-repo \
--image-ref=eclipse-mosquitto \
--select-semver=2.0.x \
--export > ./cluster/home/mosquitto-policy.yaml
```

## Managing K3s clusters

### Certificate rotation

Note that K3s has generated certificates for accessing the different services, like the API.
By defeault, they expire after 12 months and will be automatically rotated when `k3s` is restarted within 90 days of the expiration date.
You can also manually start key rotation using the `k3s certificate rotate` subcommand:

```shell
# Stop K3s
> systemctl stop k3s
# Rotate certificates
> k3s certificate rotate
# Start K3s
> systemctl start k3s
```

### Storage configuration

When running in an environment where the server is also hosting workload pods, care should be taken to ensure that agent and workload IOPS do not interfere with the datastore.
This can be best accomplished by placing the server components (`/var/lib/rancher/k3s/server`) on a different storage medium than the agent components (`/var/lib/rancher/k3s/agent`), which include the containerd image store.
Workload storage (pod ephemeral storage and volumes) should also be isolated from the datastore.

Failure to meet datastore throughput and latency requirements may result in delayed response from the control plane and/or failure of the control plane to maintain system state.

### check manifests

To check a manifest before commiting to to the repository, run `kubectl apply --server-side --dry-run=server -f <file>`.

### Reconcile Git sources

To sync the Kubernetes resources with the definitions in the Git repository, run `flux reconcile source git flux-system`.

### Run a shell inside a Pod

`kubectl exec --stdin --tty shell-demo -- /bin/bash`.
If its an Alpine based image replace `/bin/bash` with `/bin/sh`.

### Retry HelmRelease

`flux suspend hr my-helmrelease -n myhelmrelease-ns`
`flux resume hr my-helmrelease -n myhelmrelease-ns`

```shell
# Substitute paramaters for environment variable values:
> find . -iname \*.yaml -type f -exec sh -c 'envsubst < $0 > $0.tmp && mv $0.tmp $0' {} \;
```

## Multi-cluster management

If you wish to target clusters created by other means than CAPI, you can create a ServiceAccount on the remote cluster, generate a KubeConfig for that account, and then create a secret on the cluster where kustomize-controller is running e.g.:

```shell
> kubectl create secret generic prod-kubeconfig \
    --from-file=value.yaml=./kubeconfig
```

## vvvvvvv

kubectl get nodes --show-labels

### Kubernetes replicator

quay.io/mittwald/kubernetes-replicator

## Prometheus/Grafana

https://docs.technotim.live/posts/kube-grafana-prometheus/
https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml
https://docs.technotim.live/posts/kube-grafana-prometheus/
https://github.com/techno-tim/launchpad/blob/master/kubernetes/kube-prometheus-stack/ingress.yaml
