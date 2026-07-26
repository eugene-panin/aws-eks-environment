TERRAFORM ?= terraform

.PHONY: check fmt init test validate

fmt:
	$(TERRAFORM) fmt -recursive

init:
	$(TERRAFORM) init -backend=false

validate: init
	$(TERRAFORM) validate

test: init
	$(TERRAFORM) test

check:
	$(TERRAFORM) fmt -check -recursive
	$(TERRAFORM) init -backend=false
	$(TERRAFORM) validate
	$(TERRAFORM) test
