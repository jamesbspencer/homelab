# OpenBao Server Configuration
# Spencer's Homelab - Secrets & Encryption Management

ui = true

storage "raft" {
  path    = "/openbao/file"
  node_id = "openbao-1"
}

listener "tcp" {
  address                          = "0.0.0.0:8200"
  tls_disable                      = true
  x_forwarded_for_authorized_addrs = "127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}

api_addr     = "https://vault.spencer.lan"
cluster_addr = "http://openbao:8201"
