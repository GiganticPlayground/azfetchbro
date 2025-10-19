# subscription_id is provided from a private, untracked file (see terraform.secrets.tfvars)
resource_group_name = "rg-azfetchbro-demo-eastus"
location            = "eastus"
key_vault_name      = "kv-azfetchbro-demo"

# For this demo, we store harmless demo secrets, but in a real-world scenario, you would want to
# store real secrets in the terraform.secrets.tfvars file.
secrets = {
    apiKey        = "super-secret-value"
    connection    = "Server=tcp:sql.example;Database=app;"
    webhookToken  = "xyz-123"
}