.PHONY: bootstrap bootstrap-check bootstrap-print-env

bootstrap:
	bash scripts/bootstrap.sh apply

bootstrap-check:
	bash scripts/bootstrap.sh check

bootstrap-print-env:
	bash scripts/bootstrap.sh print-env
