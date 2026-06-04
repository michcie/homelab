TF      := terraform -chdir=hetzner-terraform
ANSIBLE := ansible-playbook -i ansible/inventory.yml ansible/site.yml

.PHONY: tf-apply tf-destroy tf-output ansible deploy help

##@ Terraform

tf-apply: ## Postaw infrastrukturę na Hetznerze
	$(TF) apply

tf-destroy: ## Zniszcz infrastrukturę na Hetznerze
	$(TF) destroy

tf-output: ## Pokaż outputy terraforma (IP serwera itp.)
	$(TF) output

##@ Ansible

ansible: ## Uruchom Ansible, opcjonalnie z tagami: make ansible TAGS=k3s,flux
	$(ANSIBLE) $(if $(TAGS),--tags $(TAGS),)

##@ Skróty

deploy: tf-apply ansible ## Postaw infrastrukturę i sprovisionuj od zera

##@ Info

help: ## Pokaż tę pomoc
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help
