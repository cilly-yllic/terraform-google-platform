.PHONY: bootstrap bootstrap-check bootstrap-print-env
.PHONY: create-billing-account create-billing-account-check create-billing-account-print-env

bootstrap:
	bash scripts/bootstrap.sh apply

bootstrap-check:
	bash scripts/bootstrap.sh check

bootstrap-print-env:
	bash scripts/bootstrap.sh print-env

create-billing-account:
	bash scripts/create-billing-account.sh apply

create-billing-account-check:
	bash scripts/create-billing-account.sh check

create-billing-account-print-env:
	bash scripts/create-billing-account.sh print-env
