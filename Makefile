SHELL := bash
PYTHON := env python3
VENV_DIR := .venv
VENV_ACTIVATE := "$(VENV_DIR)/bin/activate"
REQUIREMENTS_FILE := requirements.txt

# Check to ensure certain environment variables are set
env_require = @( [[ -v '$(1)' ]] && [[ -n "$${$(1)}" ]] ) \
	&& { printf "export $(1)=$${$(1)}\n" > /dev/stderr; } \
	|| { printf '::error:: [FATAL] Required environment variable "$(1)" is not set\n' > /dev/stderr; exit 1; }

$(VENV_DIR): Makefile $(REQUIREMENTS_FILE) .pre-commit-config.yaml
	@echo "::group::Set up Python virtual environment in $(VENV_DIR)"
	$(PYTHON) -m venv $(VENV_DIR)
	source $(VENV_ACTIVATE) && \
		pip install --upgrade pip && \
		pip install --upgrade -r $(REQUIREMENTS_FILE)
	@echo "::endgroup::"
	@echo "::group::Set up pre-commit"
	source $(VENV_ACTIVATE) && \
		pre-commit install
	@echo "::endgroup::"

.PHONY: setup
setup: $(VENV_DIR)

.PHONY: code-quality
code-quality: setup
	@echo "::group::Code Quality -- pre-commit"
	source $(VENV_ACTIVATE) && pre-commit run --all
	@echo "::endgroup::"

# This target should not be called from outside this Makefile.
.PHONY: sceptre
sceptre: setup
	$(call env_require,AWS_REGION)
	$(call env_require,AWS_ENVIRONMENT)
	$(call env_require,SCEPTRE_ACTION)
	$(call env_require,SCEPTRE_STACK)
	@if [[ -d sceptre/$(AWS_REGION)/obsolete ]] ; then \
		echo "::group::Removing obsolete resources in region $(AWS_REGION)" ; \
		echo $(MAKE) sceptre SCEPTRE_ACTION=prune SCEPTRE_ACTION_ARGS="-y" SCEPTRE_STACK="obsolete" ; \
		echo "::endgroup::" ; \
	fi
	@echo "::group::Validate Sceptre stack '$(AWS_REGION)/$(SCEPTRE_STACK)'"
	source $(VENV_ACTIVATE) && \
		cd sceptre && \
			sceptre \
				$(SCEPTRE_GLOBAL_ARGS) \
				--var-file vars/$(AWS_ENVIRONMENT).yaml \
				validate \
				$(AWS_REGION)/$(SCEPTRE_STACK)
	@echo "::endgroup::"
	@echo "::group::Print CloudFormation template used for '$(AWS_REGION)/$(SCEPTRE_STACK)'"
	source $(VENV_ACTIVATE) && \
		cd sceptre && \
			sceptre $(SCEPTRE_GLOBAL_ARGS) --var-file vars/$(AWS_ENVIRONMENT).yaml \
				generate \
				$(AWS_REGION)/$(SCEPTRE_STACK)
	@echo "::endgroup::"
	@echo "::group::Print Sceptre diff for '$(AWS_REGION)/$(SCEPTRE_STACK)'"
	source $(VENV_ACTIVATE) && \
		cd sceptre && \
			sceptre $(SCEPTRE_GLOBAL_ARGS) --var-file vars/$(AWS_ENVIRONMENT).yaml \
				diff \
				$(AWS_REGION)/$(SCEPTRE_STACK)
	@echo "::endgroup::"
	@echo "::group::Run Sceptre action '$(SCEPTRE_ACTION)' on '$(AWS_REGION)/$(SCEPTRE_STACK)'"
	source $(VENV_ACTIVATE) && \
		cd sceptre && \
			sceptre $(SCEPTRE_GLOBAL_ARGS) --var-file vars/$(AWS_ENVIRONMENT).yaml \
				$(SCEPTRE_ACTION) $(SCEPTRE_ACTION_ARGS) \
				$(AWS_REGION)/$(SCEPTRE_STACK)
	@echo "::endgroup::"

# Does not actually modify all resources. Notably, this excludes the temporary IAM user
.PHONY: modify-all-resources
modify-all-resources:
	$(MAKE) sceptre AWS_REGION=eu-west-2 SCEPTRE_STACK=s3-replication.yaml
	$(MAKE) sceptre AWS_REGION=eu-west-1 SCEPTRE_STACK=s3.yaml
	$(MAKE) sceptre AWS_REGION=us-west-2 SCEPTRE_STACK=iam-user/sir
	$(MAKE) sceptre AWS_REGION=us-west-2 SCEPTRE_STACK=data-lake
	$(MAKE) sceptre AWS_REGION=us-west-2 SCEPTRE_STACK=s3-athena.yaml
	$(MAKE) sceptre AWS_REGION=us-west-2 SCEPTRE_STACK=glue

# Launches all* resources using the modify-all-resources target.
# If there are any stacks that may be present using old stack names, use the prune function to delete them.
# The "prune" action gracefully exits when the stack is not present.
.PHONY: launch-all
launch-all:
	$(MAKE) modify-all-resources SCEPTRE_ACTION=launch SCEPTRE_ACTION_ARGS="--prune -y"

# # Deletes all* resources using the modify-all-resources target.
# .PHONY: delete-all
# delete-all:
# 	$(MAKE) modify-all-resources SCEPTRE_ACTION=delete SCEPTRE_ACTION_ARGS="-y"
### DO NOT ALLOW DELETION OF ALL RESOURCES BY AUTOMATION
.PHONY: delete-all
delete-all:
	@echo "::error::This action is not permitted" > /dev/stderr ; exit 1

# some targets to deal with the temporary IAM user
.PHONY: temp-iam-user
temp-iam-user:
	$(MAKE) sceptre AWS_REGION=us-west-2 SCEPTRE_STACK=iam-user/temp

.PHONY: launch-temp-iam-user
launch-temp-iam-user:
	$(MAKE) temp-iam-user SCEPTRE_ACTION=launch

.PHONY: delete-temp-iam-user
delete-temp-iam-user:
	$(MAKE) temp-iam-user SCEPTRE_ACTION=delete
