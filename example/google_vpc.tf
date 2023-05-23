resource "google_compute_network" "vpc" {
  provider                = google
  name                    = "${random_pet.name.id}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  provider      = google
  name          = "${random_pet.name.id}"
  ip_cidr_range = var.google_subnet_cidr
  region        = var.google_region
  network       = google_compute_network.vpc.id
}