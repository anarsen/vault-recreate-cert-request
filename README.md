# vault-recreate-cert-request

This repo contains an example on how to conditionally recreate the `vault_pki_secret_backend_intermediate_cert_request` resources in case the underlying PKI mount has been recreated.

In case of ephemeral Vault clusters this, the Terraform state will keep around the CSR, but not recreate it when recreating the PKI mount.
`vault_mount` returns an `accessor` which is unique everytime, which is what we'll use to recreate the necessary resources.

Look for the `null_resource.intermediate_one_tracker` resource in `main.tf`.
