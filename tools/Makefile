TERRAFORM ?= terraform
STATE_BUCKET ?= casino-state-master
PLAN_ONLY ?= false

PLAN_FILE = $(INSTANCE)_$(OU)_$(ACCOUNT)_$(ENV).plan
VAR_FILE = $(INSTANCE)_$(ACCOUNT)_$(ENV).tfvars

init:
	@echo "running terraform init $(INSTANCE)"
	rm -rf .terraform/modules/ && \
	$(TERRAFORM) init -reconfigure \
		-backend-config="encrypt=true" \
		-backend-config="bucket=$(STATE_BUCKET)" \
		-backend-config="key=$(OU)/$(ACCOUNT)/$(ENV).tfstate" \
		-backend-config="region=$(AWS_REGION)"

validate: init
	@echo "running terraform validate"
	$(TERRAFORM) validate

workspace:
	@echo "switching to workspace $(INSTANCE)"
	$(TERRAFORM) workspace select $(INSTANCE) || $(TERRAFORM) workspace new $(INSTANCE)

plan: workspace
	@echo "running terraform plan"
	$(TERRAFORM) plan \
		-var-file=$(VAR_FILE) \
		-var='plan_only=$(PLAN_ONLY)' \
		-var='instance=$(INSTANCE)' \
		-var='ou=$(OU)' \
		-var='account=$(ACCOUNT)' \
		-var='env=$(ENV)' \
		-var='aws_region=$(AWS_REGION)' \
		-out=$(PLAN_FILE)

console: workspace
	@echo "running terraform console"
	$(TERRAFORM) console \
		-var-file=$(VAR_FILE) \
		-var='plan_only=$(PLAN_ONLY)' \
		-var='instance=$(INSTANCE)' \
		-var='ou=$(OU)' \
		-var='account=$(ACCOUNT)' \
		-var='env=$(ENV)' \
		-var='aws_region=$(AWS_REGION)'

apply:
	@echo "running terraform apply"
	if [ "$(APPROVE)" = "yes" ]; then \
  		$(TERRAFORM) apply $(PLAN_FILE); \
	else \
  		$(TERRAFORM) apply -var-file=$(VAR_FILE); \
	fi

format:
	@echo Formatting terraform files
	$(TERRAFORM) fmt --recursive

destroy: workspace
	@echo "running terraform destroy"
	$(TERRAFORM) plan \
		-destroy \
		-var-file=$(VAR_FILE) \
		-var='plan_only=$(PLAN_ONLY)' \
		-var='instance=$(INSTANCE)' \
		-var='ou=$(OU)' \
		-var='account=$(ACCOUNT)' \
		-var='env=$(ENV)' \
		-var='aws_region=$(AWS_REGION)' \
		-out=$(PLAN_FILE)
