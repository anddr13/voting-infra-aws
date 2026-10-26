SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Short-lived credentials from `aws login --remote --profile gpu-lab`, refreshed by credential_process.
AWS_PROFILE ?= gpu-lab-terraform
REGION      ?= eu-north-1
CLUSTER     ?= voting-dev
# The lab cluster gets its own kubeconfig file; ~/.kube/config and its current context are never touched.
KUBECONFIG_FILE ?= $(HOME)/.kube/voting-aws
BUDGET_EMAIL    ?= $(shell git config user.email)
# e.g. TF_FLAGS=-auto-approve for unattended runs; interactive approval by default.
TF_FLAGS        ?=

export AWS_PROFILE
export AWS_REGION := $(REGION)
export TF_VAR_region := $(REGION)

.PHONY: session
session: ## Fail early if the aws login session has expired
	@aws sts get-caller-identity --query Arn --output text > /dev/null 2>&1 || \
	  { echo "AWS session expired: run  aws login --remote --profile gpu-lab" >&2; exit 1; }

.PHONY: bootstrap
bootstrap: session ## One-time: S3 state bucket + budget alerts, writes infra/backend.hcl
	terraform -chdir=bootstrap init -input=false
	terraform -chdir=bootstrap apply $(TF_FLAGS) -var budget_email=$(BUDGET_EMAIL)

.PHONY: up
up: session ## terraform apply, then wait until the app answers on the load balancer
	terraform -chdir=infra init -input=false -backend-config=backend.hcl
	terraform -chdir=infra apply $(TF_FLAGS)
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) --kubeconfig $(KUBECONFIG_FILE)
	KUBECONFIG=$(KUBECONFIG_FILE) bash scripts/wait-for-app.sh $(CLUSTER)
	@echo; echo "kubectl: export KUBECONFIG=$(KUBECONFIG_FILE)    Remember: make down when you are done."

.PHONY: down
down: session ## Remove load balancers and volumes Kubernetes created, then terraform destroy
	terraform -chdir=infra init -input=false -backend-config=backend.hcl
	@if aws eks describe-cluster --name $(CLUSTER) > /dev/null 2>&1; then \
	  aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION) --kubeconfig $(KUBECONFIG_FILE) && \
	  KUBECONFIG=$(KUBECONFIG_FILE) bash scripts/drain-cluster.sh $(CLUSTER); \
	else echo "No cluster, nothing to drain."; fi
	terraform -chdir=infra destroy $(TF_FLAGS)
	rm -f $(KUBECONFIG_FILE)

.PHONY: leftovers
leftovers: session ## Anything billable left in the region after make down?
	@echo "EKS: $$(aws eks list-clusters --query clusters --output text)"
	@echo "EC2: $$(aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping --query 'Reservations[].Instances[].InstanceId' --output text)"
	@echo "EBS: $$(aws ec2 describe-volumes --query 'Volumes[].VolumeId' --output text)"
	@echo "LB:  $$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text)"

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-z-]+:.*##/ {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
