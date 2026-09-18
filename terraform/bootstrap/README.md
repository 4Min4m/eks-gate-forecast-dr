# Bootstrap: Terraform remote-state backend

Creates the S3 bucket and DynamoDB lock table that the **main** stack uses for
remote state. Run this **once**, before `terraform init` in `../`.

This stack uses **local state** on purpose (it's the thing that creates the
remote backend — it can't store its own state there yet). It's small and
rarely changes.

## Run

```bash
cd terraform/bootstrap

terraform init
terraform apply \
  -var 'state_bucket_name=my-globally-unique-tfstate-bucket' \
  -var 'region=us-east-1'
```

Then copy the printed `backend_hcl_snippet` into `../backend.hcl`:

```bash
terraform output -raw backend_hcl_snippet > ../backend.hcl
```

## Then initialize the main stack

```bash
cd ..
terraform init -backend-config=backend.hcl
```

## Notes

- The bucket has `prevent_destroy = true` so a stray `terraform destroy` can't
  wipe your state history. Remove that guard deliberately if you ever tear the
  backend down.
- Encryption is SSE-S3 (AES256). To use a customer-managed KMS key instead,
  switch the SSE config to `aws:kms` and add `kms_key_id` to `backend.hcl`.
