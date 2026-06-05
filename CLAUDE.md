# CLAUDE.md — zasady pracy w repo `homelab`

Kontekst dla Claude / współpracowników. Operacyjne „jak postawić" jest w
[`README.md`](README.md), uzasadnienia decyzji w [`planning.md`](planning.md).

## Czym jest to repo
Single-node **k3s** zarządzany przez **FluxCD** (GitOps). Repo jest **źródłem
prawdy** dla całego stanu klastra. Provisioning serwera: Terraform (Hetzner) +
cloud-init + Ansible. Branch Fluxa: `master`, path: `clusters/homelab`.

## Złota zasada: GitOps, nie `kubectl apply`
- **Trwałe zmiany w klastrze idą przez `git push`**, nie przez ręczny
  `kubectl apply`. Flux reconciluje repo → klaster (domyślnie co ~1 min).
- `kubectl` używaj do **diagnostyki i debugowania** (get/describe/logs), nie do
  mutowania stanu, który ma żyć w gicie. Ręczny apply i tak zostanie nadpisany
  albo spowoduje dryf.
- Chcesz wymusić sync od ręki: `flux reconcile kustomization <name> --with-source`.

## Sekrety — nigdy plaintext do gita
- Szyfrowanie: **SOPS + age**. Reguła w `.sops.yaml` (klucz publiczny age).
- Klucz **prywatny** age żyje w `ansible/secrets.yml` (gitignore) i jako Secret
  `sops-age` w klastrze (rola `sops`). Klucz w secretcie musi kończyć się na
  `.agekey` — Flux tego szuka.
- `ansible/secrets.yml` i `ansible/inventory.yml` są w `.gitignore` — **nigdy
  ich nie commituj** (są tam tokeny GitHub/age, klucz hcloud).
- Szyfrowanie pliku: `sops -e -i path/to/secret.yaml`. Edycja:
  `sops path/to/secret.yaml`. **Uwaga:** `.sops.yaml` ma `path_regex: .*\.yaml$`
  — pasuje do *wszystkich* yamli, więc nie odpalaj `sops -e` na zwykłym
  manifeście; szyfruj tylko realne sekrety (np. `cloudflare-secret.yaml`).
- Przed commitem sprawdź, że nie wrzucasz plaintextu: szukaj `kind: Secret`
  z niezaszyfrowanym `data:`/`stringData:`.

## Gdzie co dodawać
- **Nowa aplikacja** → `apps/<nazwa>/` (Deployment/Service/Ingress albo
  HelmRelease). Łapie ją Kustomization `apps.yaml`.
- **Kontroler infra** (ingress, cert-manager itp.) → `infrastructure/controllers/<nazwa>/`
  (HelmRepository + HelmRelease + namespace).
- **Konfiguracja infra** (ClusterIssuery, sekrety configów) →
  `infrastructure/configs/`.
- **Wejścia Fluxa** (Kustomizations) → `clusters/homelab/*.yaml`.
- Kaskada zależności: **controllers → configs → apps** (`dependsOn`). Nie łam
  kolejności — apki nie mają startować przed ingressem i TLS.

## Konwencje
- **HelmRelease**: wersja chartu **przypięta** (`spec.chart.spec.version`), nie
  `latest`. Upgrade = zmiana wersji + `git push`.
- **Namespace** dla kontrolerów trzymany jawnie w `controllers/<nazwa>/namespace.yaml`.
- Po edycji manifestów: `git push`, potem zweryfikuj
  `flux get kustomizations` / `flux get helmreleases` (Ready=True).

## Ansible
- Kolejność ról (`ansible/site.yml`): **base → docker → k3s → sops → flux**.
  `sops` **musi** lecieć przed `flux` (klucz age w klastrze, zanim Flux
  zacznie odszyfrowywać).
- `sops` tworzy z góry namespace `flux-system` (na Secret `sops-age`). Dlatego
  rola `flux` sprawdza, czy bootstrap już był, po **deploymencie
  `source-controller`** — NIE po istnieniu namespace. **Nie zmieniaj tego z
  powrotem na `get namespace`** — sops zawsze utworzy namespace pierwszy, więc
  check na namespace zawsze skipowałby bootstrap (deadlock na świeżym klastrze).
- Wybiórcze role: `make ansible TAGS=k3s,flux`.
- Bootstrap Fluxa jest `delegate_to: localhost` → wymaga **flux CLI lokalnie**
  + `GITHUB_TOKEN` (brany z `secrets.yml`).

## Częste pułapki (więcej w README → Troubleshooting)
- Po `tf-destroy`+`tf-apply` ten sam IP ma nowy host key →
  `ssh-keygen -f ~/.ssh/known_hosts -R <IP>`.
- Pusty namespace `flux-system` z nieudanej próby blokuje bootstrap →
  `kubectl delete ns flux-system` i odpal ponownie.
- `secrets "sops-age" not found` w Kustomizacjach → rola `sops` nie doszła;
  `make ansible TAGS=sops,flux`.

## Otwarte TODO (z `planning.md`)
- Wyjąć `hcloud_token` z `terraform.tfvars` do env (`TF_VAR_hcloud_token`).
- Zaszyfrować `cloudflare-secret.yaml` przez SOPS i wypchnąć.
- Backupy danych PV (Velero/restic) przed poleganiem na klastrze.

## Środowisko
- Pliki edytuj **tylko** w `/home/dekros/cloud/homelab/` (jedyny zamontowany
  katalog roboczy).
