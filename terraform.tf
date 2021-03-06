variable "region" {
}

variable "ssh_fingerprint" {
}
variable "do_token" {}
variable "pvt_key" {}

provider "digitalocean" {
  token = var.do_token
}

# create a vpc to host all of this lot.

resource "digitalocean_vpc" "lab"{
  name ="lab"
  region = var.region
}

# create three droplets, 1 waf, 1 web, 1 db
resource "digitalocean_droplet" "wafvpn" {
  image    = "ubuntu-20-04-x64"
  name     = "wafvpn"
  region   = var.region
  size     = "s-1vcpu-1gb"
  ssh_keys = [var.ssh_fingerprint]
  vpc_uuid = digitalocean_vpc.lab.id # our lab vpc set up earlier
}

resource "digitalocean_droplet" "web" {
  image    = "ubuntu-20-04-x64"
  name     = "web"
  region   = var.region
  size     = "s-1vcpu-1gb"
  ssh_keys = [var.ssh_fingerprint]
  vpc_uuid = digitalocean_vpc.lab.id # our lab vpc set up earlier
}
resource "digitalocean_droplet" "db" {
  image    = "ubuntu-20-04-x64"
  name     = "db"
  region   = var.region
  size     = "s-1vcpu-2gb"
  ssh_keys = [var.ssh_fingerprint]
  vpc_uuid = digitalocean_vpc.lab.id # our lab vpc set up earlier
}

# create a firewall that only accepts port 80, 443 and 22 traffic from outside.
resource "digitalocean_firewall" "firewall-waf" {
  name = "firewall-waf"

  droplet_ids = [
    digitalocean_droplet.wafvpn.id,
  ]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0"]
  }
  inbound_rule {
    protocol                  = "tcp"
    port_range                = "443"
    source_addresses = ["0.0.0.0/0"]
  }

  inbound_rule {
    protocol                  = "tcp"
    port_range                = "80"
    source_addresses = ["0.0.0.0/0"]
  }

resource "digitalocean_firewall" "firewall-web" {
  name = "firewall-web"
    # The droplets to apply this firewall to                                   #
    droplet_ids =  [
      digitalocean_droplet.web.id,
      digitalocean_droplet.db.id
    ] 

    #--------------------------------------------------------------------------#
    # Internal VPC Rules. We have to let ourselves talk to each other          #
    #--------------------------------------------------------------------------#
    inbound_rule {
        protocol = "tcp"
        port_range = "1-65535"
        source_addresses = [digitalocean_vpc.lab.ip_range]
    }

    inbound_rule {
        protocol = "udp"
        port_range = "1-65535"
        source_addresses = [digitalocean_vpc.lab.ip_range]
    }

    inbound_rule {
        protocol = "icmp"
        source_addresses = [digitalocean_vpc.lab.ip_range]
    }

    outbound_rule {
        protocol = "udp"
        port_range = "1-65535"
        destination_addresses = [digitalocean_vpc.lab.ip_range]
    }

    outbound_rule {
        protocol = "tcp"
        port_range = "1-65535"
        destination_addresses = [digitalocean_vpc.lab.ip_range]
    }

    outbound_rule {
        protocol = "icmp"
        destination_addresses = [digitalocean_vpc.lab.ip_range]
    }
  
}

# create an ansible inventory file
resource "null_resource" "ansible-provision" {
  depends_on = [
    digitalocean_droplet.wafvpn,
    digitalocean_droplet.web,
    digitalocean_droplet.db
  ]

  provisioner "local-exec" {
    command = "echo '${digitalocean_droplet.wafvpn.name} ansible_host=${digitalocean_droplet.wafvpn.ipv4_address} ansible_ssh_user=ansible ansible_python_interpreter=/usr/bin/python3' > inventory"
  }

  provisioner "local-exec" {
    command = "echo '${digitalocean_droplet.web.name} ansible_host=${digitalocean_droplet.web.ipv4_address} ansible_ssh_user=ansible ansible_python_interpreter=/usr/bin/python3' >> inventory"
  }
  provisioner "local-exec" {
    command = "echo '${digitalocean_droplet.db.name} ansible_host=${digitalocean_droplet.db.ipv4_address} ansible_ssh_user=ansible ansible_python_interpreter=/usr/bin/python3' >> inventory"
  }
}
}

# output the load balancer ip
output "ip" {
  value = digitalocean_loadbalancer.wafvpn.ip
}

