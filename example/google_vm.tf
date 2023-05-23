resource "google_compute_firewall" "ssh-rule1" {
  provider = google
  name     = "${random_pet.name.id}-rule1"
  network  = google_compute_network.vpc.name
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "ssh-rule2" {
  provider = google
  name     ="${random_pet.name.id}-rule2"
  network  = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22", "8089"]
  }
  source_ranges = ["${var.my_ip}"]
}

resource "google_compute_instance" "vm" {
  provider     = google
  name         = "${random_pet.name.id}-vm"
  machine_type = "e2-micro"
  zone         = var.google_zone
  tags         = ["${random_pet.name.id}"]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {}
  }
  metadata_startup_script = file("./user-data-ubuntu.sh")
  metadata = {
    sshKeys = "ubuntu:${var.public_key}"
  }
}

data "google_compute_instance" "vm" {
  provider = google
  name     = "${random_pet.name.id}-vm"
  zone     = var.google_zone
  depends_on = [
    google_compute_instance.vm
  ]
}

output "google_private_ip_vm" {
  description = "Private ip address for VM"
  value       = data.google_compute_instance.vm.network_interface.0.network_ip
}

output "google_public_ip_vm" {
  description = "Public ip address for VM (ssh user: ubuntu)"
  value       = data.google_compute_instance.vm.network_interface.0.access_config.0.nat_ip
}