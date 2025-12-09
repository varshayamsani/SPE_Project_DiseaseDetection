# HashiCorp Vault Configuration for Disease Detector
# This configuration stores sensitive credentials securely

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1  # Enable TLS in production
}

api_addr = "http://0.0.0.0:8200"
ui = true

# Enable audit logging
audit_device "file" {
  path = "/opt/vault/audit.log"
}


