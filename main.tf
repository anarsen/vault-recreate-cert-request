provider "vault" {
  address         = "https://10.1.132.21:8200"
  skip_tls_verify = true
}

resource "vault_mount" "root" {
  path = "root"
  type = "pki"
}

resource "vault_pki_secret_backend_config_urls" "root" {
  backend = vault_mount.root.path
  issuing_certificates = [
    "https://10.1.132.21:8200/v1/${vault_mount.root.path}/ca",
  ]
}

resource "vault_mount" "intermediate_one" {
  path = "intermediate/playground"
  type = "pki"
}

resource "vault_pki_secret_backend_config_urls" "intermediate_one" {
  backend = vault_mount.intermediate_one.path
  issuing_certificates = [
    "https://10.1.132.21:8200/v1/${vault_mount.intermediate_one.path}/ca",
  ]
}

resource "vault_mount" "intermediate_two" {
  path = "intermediate/two"
  type = "pki"
}

resource "vault_pki_secret_backend_config_urls" "intermediate_two" {
  backend = vault_mount.intermediate_two.path
  issuing_certificates = [
    "https://10.1.132.21:8200/v1/${vault_mount.intermediate_two.path}/ca",
  ]
}

resource "vault_pki_secret_backend_root_cert" "this" {
  backend              = vault_mount.root.path
  type                 = "internal"
  common_name          = "Root CA"
  ttl                  = "315360000"
  format               = "pem"
  key_type             = "rsa"
  key_bits             = 4096
  exclude_cn_from_sans = true
  ou                   = "My OU"
  organization         = "My organization"

  depends_on = [vault_mount.root]
}

# Intermediate Level 1

# Will be recreated whenever `vault_mount.intermediate_one` is recreated.
# This will in turn force `vault_pki_secret_backend_intermediate_cert_request`
# to also be recreated, which will not happen otherwise.
#
# If the cert request isn't recreated when the PKI mount is, the issuer ref will
# not be valid, and certs cannot be issued.
resource "null_resource" "intermediate_one_tracker" {
  triggers = {
    accessor = vault_mount.intermediate_one.accessor
  }
}

resource "vault_pki_secret_backend_intermediate_cert_request" "one" {
  backend     = vault_mount.intermediate_one.path
  type        = "internal"
  common_name = "Intermediate Level 1"

  depends_on = [vault_mount.intermediate_one]

  lifecycle {
    replace_triggered_by = [
      null_resource.intermediate_one_tracker,
    ]
  }
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate_one" {
  backend              = vault_mount.root.path
  csr                  = vault_pki_secret_backend_intermediate_cert_request.one.csr
  common_name          = "Intermediate Level 1"
  exclude_cn_from_sans = true
  ou                   = "My OU"
  organization         = "My organization"

  depends_on = [vault_pki_secret_backend_intermediate_cert_request.one]
}

resource "vault_pki_secret_backend_intermediate_set_signed" "one" {
  backend     = vault_mount.intermediate_one.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate_one.certificate
}

# Intermediate Level 2
# Same explanation with the `null_resource` hop as with Intermediate Level 1.
resource "null_resource" "intermediate_two_tracker" {
  triggers = {
    accessor = vault_mount.intermediate_two.accessor
  }
}

resource "vault_pki_secret_backend_intermediate_cert_request" "two" {
  backend     = vault_mount.intermediate_two.path
  type        = "internal"
  common_name = "Intermediate Authority Level 2"

  depends_on = [
    vault_mount.intermediate_two,
    vault_pki_secret_backend_intermediate_set_signed.one,
  ]

  lifecycle {
    replace_triggered_by = [
      null_resource.intermediate_two_tracker,
    ]
  }
}

resource "vault_pki_secret_backend_root_sign_intermediate" "two" {
  backend              = vault_mount.intermediate_one.path
  csr                  = vault_pki_secret_backend_intermediate_cert_request.two.csr
  common_name          = "Intermediate Authority Level 2"
  exclude_cn_from_sans = true
  ou                   = "My OU"
  organization         = "My organization"

  depends_on = [
    vault_mount.intermediate_one,
    vault_pki_secret_backend_intermediate_cert_request.one,
  ]
}

resource "vault_pki_secret_backend_intermediate_set_signed" "two" {
  backend     = vault_mount.intermediate_two.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.two.certificate
}

resource "vault_pki_secret_backend_role" "this" {
  backend          = vault_mount.intermediate_two.path
  name             = "server"
  ttl              = 3600
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 4096
  allow_subdomains = true
  allow_any_name   = true

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.two]
}

resource "vault_pki_secret_backend_cert" "this" {
  backend = vault_mount.intermediate_two.path
  name    = vault_pki_secret_backend_role.this.name

  common_name = "some.name.here"

  depends_on = [
    vault_pki_secret_backend_role.this,
    vault_pki_secret_backend_root_cert.this
  ]
}

output "intermediate_two_cert" {
  value = vault_pki_secret_backend_root_sign_intermediate.two.certificate
}

output "leaf_cert" {
  value = vault_pki_secret_backend_cert.this.certificate
}

output "leaf_key" {
  value     = vault_pki_secret_backend_cert.this.private_key
  sensitive = true
}
