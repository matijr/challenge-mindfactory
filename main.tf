provider "kubernetes" {
    config_path = "~/.kube/config"
}

#Namespace for a workspace
resource "kubernetes_namespace" "workspace" {
    metadata {
        name = "workspace-ns"
    }
}

#local volume as a S3 bucket

resource "kubernetes_persistent_volume_claim" "s3_pvc" {
  metadata {
    name = "s3-pvc"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# Redis application deployment and service

resource "kubernetes_deployment" "redis_deployment" {
    metadata {
        name = "redis-deployment"
        namespace = kubernetes_namespace.workspace.metadata[0].name
    }

    spec {
        replicas = 1
        selector {
            match_labels = {
                app = "redis-deployment"
            }
        }
        template {
            metadata {
                labels = {
                    app = "redis-deployment"
                }
            }
            spec {
                container {
                    name  = "redis"
                    image = "redis:latest"
                    port {
                        container_port = 6379
                    }
                    volume_mount {
                        mount_path = "/data"
                        name       = "s3-pvc"
                    }
                }
                volume {
                    name = "s3-pvc"
                    persistent_volume_claim {
                        claim_name = kubernetes_persistent_volume_claim.s3_pvc.metadata[0].name
                    }
                }
            }
        }
    }
}

resource "kubernetes_service" "redis_service" {
    metadata {
        name = "redis-service"
        namespace = kubernetes_namespace.workspace.metadata[0].name
    }
    spec {
        selector = {
            app = "redis-deployment"
        }
        port {
            port        = 6379
            target_port = 6379
        }
        type = "NodePort"
    }
}

# Add network policy like security groups in AWS

resource "kubernetes_network_policy" "network_policy" {
  metadata {
    name      = "network-policy"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "redis-deployment"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        ip_block {
          cidr = "192.168.0.0/16"
          except = ["192.168.1.0/24"]
        }
      }
      ports {
        protocol = "TCP"
        port     = 6379
      }
    }

    egress {
      to {
        ip_block {
          cidr = "192.168.0.0/16"
          except = ["192.168.1.0/24"]
        }
      }
      ports {
        protocol = "TCP"
        port     = 6379
      }
    }
  }
}