TF      := terraform -chdir=hetzner-test
ANSIBLE := ansible-playbook -i ansible/inventory.yml ansible/site.yml

.PHONY: deploy tf-apply provision bootstrap-flux destroy

# Stawia serwer i od razu provisionuje
deploy: tf-apply provision

# Tylko terraform apply (generuje też ansible/inventory.yml)
tf-apply:
	$(TF) apply

# Ansible — wszystkie role
provision:
	$(ANSIBLE)

# Ansible — tylko wybrana rola, np: make run TAGS=k3s
run:
	$(ANSIBLE) --tags $(TAGS)

# Flux bootstrap (wymaga GITHUB_TOKEN)
bootstrap-flux:
	GITHUB_TOKEN=$(GITHUB_TOKEN) $(ANSIBLE) --tags flux

# Niszczy infrastrukturę na Hetznerze
destroy:
	$(TF) destroy
