# Example: Multi-Cloud between AWS, Google and Azure Cloud with PacketFabric Cloud Router Terraform module

This example demonstrates how to set up a multi-cloud network connection between AWS, Google and Azure Cloud using PacketFabric's Cloud Router and the PacketFabric Cloud ROuter Terraform module for network automation.

## Before you begin

- Check Prerequisites on the [main page](../README.md).

## Quick start

**Estimated time:** ~45 min

1. Set the PacketFabric API key and Account ID in your terminal as environment variables.

```sh
export PF_TOKEN="secret"
export PF_ACCOUNT_ID="123456789"
```

Set additional environment variables for AWS, Google and Azure:

```sh
### AWS
export PF_AWS_ACCOUNT_ID="98765432"
export AWS_ACCESS_KEY_ID="ABCDEFGH"
export AWS_SECRET_ACCESS_KEY="secret"

### Google
export TF_VAR_gcp_project_id="my-project-id" # used for bash script used with gcloud module
export GOOGLE_CREDENTIALS='{ "type": "service_account", "project_id": "demo-setting-1234", "private_key_id": "1234", "private_key": "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n", "client_email": "demoapi@demo-setting-1234.iam.gserviceaccount.com", "client_id": "102640829015169383380", "auth_uri": "https://accounts.google.com/o/oauth2/auth", "token_uri": "https://oauth2.googleapis.com/token", "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs", "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/demoapi%40demo-setting-1234.iam.gserviceaccount.com" }'
### Azure
export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
export ARM_CLIENT_SECRET="00000000-0000-0000-0000-000000000000"
export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"

export TF_VAR_public_key="ssh-rsa AAAA..." # used to create to access to the demo instances in AWS/Google
export TF_VAR_my_ip="1.2.3.1/32" # replace with your public IP address (used in AWS/Google security groups) - https://www.whatismyip.com/
```

**Note**: To convert a pretty-printed JSON into a single line JSON string: `jq -c '.' google_credentials.json`.

2. Initialize Terraform, create an execution plan and execute the plan.

```sh
terraform init
terraform plan
```

**Note:** you can update terraform variables in the ``variables*.tf``.

3. Apply the plan:

```sh
terraform apply
```

4. You can test connectivity between AWS and Google by navigating to `http://<aws_ec2_public_ip_server>:8089/` and simulate traffic between the 2 nginx servers.

**Note:** Default login/password for Locust is ``demo:packetfabric``. Use Private IP of the consul client nodes.

5. Destroy the rest of the demo infra.

```sh
terraform destroy
```
