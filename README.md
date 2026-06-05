# Homelab — k3s + Flux (GitOps)

Single-node **k3s** zarządzany w pełni deklaratywnie przez **FluxCD**. Stan całego
klastra (manifesty, Helm releases, ingress, certy, sekrety) żyje w tym repo —
nie robisz `kubectl apply` ręcznie, robisz `git push`, a Flux dociąga resztę.

Docelowo: fizyczny homelab na jednym hoście (Ryzen 16c / 64 GB). Obecnie
provisioning i testy lecą na **serwerze testowym Hetzner** (`hetzner-terraform/`).

> Rozkminki, uzasadnienia wyborów i plan są w [`planning.md`](planning.md).
> Zasady pracy w repo — w [`CLAUDE.md`](CLAUDE.md).

## Stack

| Warstwa        | Narzędzie                                                |
|----------------|----------------------------------------------------------|
| Infra serwera  | Terraform (Hetzner) + cloud-init                         |
| Provisioning   | Ansible (role: base, docker, k3s, sops, flux)            |
| Kubernetes     | k3s single-node (traefik z k3s wyłączony)                |
| GitOps         | FluxCD v2 (branch `master`, path `clusters/homelab`)     |
| Ingress        | Traefik (HelmRelease, LoadBalancer / klipper-lb)         |
| TLS            | cert-manager + Cloudflare DNS-01 (staging + prod Issuer) |
| Monitoring     | kube-prometheus-stack (Prometheus+Grafana+KSM) + Loki+promtail |
| Sekrety        | SOPS + age (Flux odszyfrowuje w klastrze)                |

## Struktura repo

```
homelab/
├── clusters/homelab/              # punkt wejścia Fluxa
│   ├── flux-system/               # auto-generowane przez flux bootstrap
│   ├── infrastructure.yaml        # Kustomization → ./infrastructure/controllers (decryption: sops)
│   ├── infrastructure-configs.yaml# Kustomization → ./infrastructure/configs (dependsOn: controllers)
│   └── apps.yaml                  # Kustomization → ./apps (dependsOn: configs)
├── infrastructure/
│   ├── controllers/               # Traefik + cert-manager (HelmRepository + HelmRelease + namespace)
│   └── configs/                   # cert-manager ClusterIssuers + cloudflare-secret (SOPS)
├── monitoring/
│   ├── controllers/               # kube-prometheus-stack + loki (HelmReleases)
│   └── configs/                   # PodMonitor Fluxa + dashboardy Grafany
├── apps/
│   └── whoami/                    # test: Deployment + Service + Ingress
├── hetzner-terraform/             # Terraform — serwer testowy na Hetznerze (+ cloud-init)
└── ansible/                       # provisioning: base, docker, k3s, sops, flux
    ├── secrets.yml                # lokalny plik z sekretami (gitignore!)
    ├── group_vars/all.yml
    ├── inventory.yml              # gitignore — generowany przez Terraform
    └── roles/
        ├── k3s/                   # instalacja k3s + auto-fix TLS SAN
        ├── sops/                  # instalacja sops/age + wgranie klucza do klastra
        └── flux/                  # flux bootstrap (GitHub)
```

Kaskada Kustomizacji: **infrastructure-controllers → infrastructure-configs → apps**
(`dependsOn`), żeby apki nie startowały zanim jest ingress i TLS. Monitoring jest
osobną gałęzią: **monitoring-controllers** (`dependsOn: infrastructure-controllers`)
**→ monitoring-configs**.

Grafana wystawiona przez Traefik na `grafana.homelab.dekros97.pl` (cert
Let's Encrypt przez cert-manager / Cloudflare DNS-01). Wymaga rekordu **A**
`grafana.homelab.dekros97.pl → <public IP serwera>` w Cloudflare. Bez DNS:
`kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`.

## Jak postawić

### Wymagania (raz)
```bash
pip install ansible

# generuj klucz age (Linux/macOS):
age-keygen -o ~/.config/sops/age/keys.txt
# Windows (PowerShell):
age-keygen -o "$env:APPDATA\sops\age\keys.txt"
# Wypisze: Public key: age1abc... — wstaw do .sops.yaml w repo
```

### Plik z sekretami
Utwórz `ansible/secrets.yml` (gitignore — nie trafi do gita):
```yaml
github_token: "ghp_twój_token"        # PAT z dostępem do repo (flux bootstrap)
age_private_key: "AGE-SECRET-KEY-1..."
```

### Komendy (z katalogu `homelab/`)
```bash
make                          # pokaż help

make tf-apply                 # postaw serwer na Hetznerze
make ansible                  # wszystkie role (base, docker, k3s, sops, flux)
make ansible TAGS=k3s,flux    # tylko wybrane role
make deploy                   # tf-apply + ansible (wszystko od zera)

make tf-destroy               # zniszcz serwer
```

Przed uruchomieniem uzupełnij w `ansible/group_vars/all.yml`:
- `flux_github_owner` — twój GitHub username (obecnie `michcie`)
- opcjonalnie `k3s_version` (puste = latest)

IP hosta ustawia Terraform w `ansible/inventory.yml` → `ansible_host`.

> Bootstrap Fluxa z roli `flux` delegowany jest na `localhost`, więc wymaga
> **flux CLI na maszynie sterującej** oraz `GITHUB_TOKEN` (brany z `secrets.yml`).

## Uwagi z konfiguracji

- **Sieć:** k3s gada wewnętrznie po sieci **prywatnej** Hetznera (`--node-ip` /
  `--advertise-address` = `10.0.1.10`), a API/kubeconfig wystawione jest na
  **publicznym** IP. Hetzner dokłada prywatny NIC tylko na warstwie SDN —
  `cloud-init` (`setup-private-net.sh`) sam wykrywa interfejs (nazwa zależy od
  typu serwera) i podnosi go przez DHCP **przed** startem k3s, inaczej etcd nie
  zbinduje się do `10.0.1.10`.
- **k3s config:** `tls-san` z publicznym IP, `disable: traefik`; Ansible
  auto-naprawia cert jeśli brak publicznego IP w SAN.
- **Dwa instalatory k3s:** `cloud-init` (terraform, pierwszy boot) i rola `k3s`
  (Ansible). Configi są zgodne, ale to potencjalne źródło driftu — docelowo
  jedno źródło prawdy.
- **SSH:** łączymy się jako `root`, więc hardening używa
  `PermitRootLogin prohibit-password` (NIE `no` — `no` zablokuje też logowanie
  kluczem). `ansible.cfg` ma `IdentitiesOnly=yes`, żeby `ssh-agent` nie podsuwał
  obcych kluczy i nie wyczerpywał `MaxAuthTries`.
- **Traefik:** HelmRelease, service type LoadBalancer (klipper-lb k3s).
- **SOPS:** klucz prywatny age w `ansible/secrets.yml` (lokalnie) + jako Secret
  `sops-age` w klastrze (klucz w secretcie musi kończyć się na `.agekey` — Flux
  tego szuka).
- **Flux decryption:** skonfigurowany w `clusters/homelab/infrastructure.yaml`,
  `infrastructure-configs.yaml` i `apps.yaml`. Bez Secreta `sops-age`
  Kustomizacje z `decryption.sops` lecą `Ready=False` i blokują kaskadę.
- **Kolejność ról i guard Fluxa:** rola `sops` leci **przed** `flux` i tworzy
  z góry namespace `flux-system` (dla sekretu `sops-age`). Dlatego rola `flux`
  sprawdza, czy bootstrap już był, po **deploymencie `source-controller`** — a
  nie po istnieniu namespace (inaczej check zawsze zwracałby „istnieje" i
  bootstrap byłby pomijany na każdym świeżym klastrze).

## Troubleshooting / rozwiązane wpadki

Wpadki z bootstrapu, które warto pamiętać (wszystkie naprawione w kodzie):

- **k3s crash-loop: `bind: cannot assign requested address` (10.0.1.10:2380).**
  etcd nie mógł zbindować się do prywatnego IP, bo Hetzner nie konfiguruje
  prywatnego NIC w systemie — był tylko w SDN. Fix: `setup-private-net.sh` w
  cloud-init podnosi NIC (DHCP) przed k3s. Objaw pochodny: brak
  `/etc/rancher/k3s/k3s.yaml` → task „Wait for k3s" w Ansible leci w nieskończoność.
- **Po Ansible `Permission denied (publickey)` jako root.** Rola `base`
  ustawiała `PermitRootLogin no` i restartowała sshd → root zablokowany. Fix:
  `prohibit-password`. Odzysk żywego serwera: konsola Hetznera (Reset root
  password) → popraw sshd_config. Na świeżym serwerze już nie wystąpi.
- **`Permission denied` przez ssh-agent.** Agent podsuwał obce klucze i
  wyczerpywał `MaxAuthTries`, zanim ssh spróbował właściwego `id_rsa`. Fix:
  `IdentitiesOnly=yes` w `ansible.cfg`. Test izolujący:
  `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa root@<IP>`.
- **`REMOTE HOST IDENTIFICATION HAS CHANGED` po `tf-destroy`+`tf-apply`.** Nowy
  serwer = nowy host key na tym samym IP. Fix:
  `ssh-keygen -f ~/.ssh/known_hosts -R <IP>`.
- **Traefik/whoami nie wstają, choć k3s żyje.** `flux get kustomizations`
  pokazywał `secrets "sops-age" not found` → kaskada zablokowana. Przyczyna:
  playbook wywalił się wcześniej na roli `k3s`, więc role `sops`/`flux` nie
  doszły i klucz age nie trafił do klastra. Fix: `make ansible TAGS=sops,flux`.
- **Flux bootstrap pomijany (`skipping`) na nowym klastrze.** Rola `sops`
  tworzyła namespace `flux-system` przed rolą `flux`, a stary guard sprawdzał
  istnienie namespace → zawsze `rc=0` → skip. Fix: guard sprawdza deployment
  `source-controller`. Jeśli trafisz na pusty `flux-system` (z poprzedniej
  nieudanej próby): `kubectl delete ns flux-system` i odpal ponownie.
- **Grafana wstała, ale brak dashboardów Fluxa.** `monitoring-configs`
  (configmapa z dashboardami) ma `dependsOn: monitoring-controllers`. Jeśli
  złapie „dependency ... is not ready" zanim controllers się dopną, czeka aż do
  następnego cyklu (`interval: 10m`) — Grafana stoi bez dashboardów. Sidecar
  importuje je dopiero gdy configmapa `flux-grafana-dashboards` (label
  `grafana_dashboard=1`) trafi do ns `monitoring`. Fix natychmiastowy:
  `flux reconcile kustomization monitoring-configs --with-source`.

## Jak działa Flux (krok po kroku)

### Idea
Flux to operator działający **wewnątrz klastra k3s**. Jego jedyne zadanie:
obserwować repo git i wymuszać, żeby klaster wyglądał dokładnie tak jak git.
Ty nie robisz `kubectl apply` ręcznie — robisz `git push`, a Flux robi resztę.

```
git push → Flux widzi zmianę → kubectl apply w tle → klaster = git
```

### Krok 1 — `flux bootstrap github`
Jednorazowa komenda (Ansible robi ją automatycznie przy pierwszym uruchomieniu):

1. Flux instaluje swoje komponenty w namespace `flux-system` w klastrze
2. Tworzy deploy key na repo GitHubie (dostęp do repo)
3. Commituje do repo manifesty Fluxa (`clusters/homelab/flux-system/`)
4. Od tej chwili Flux sam się utrzymuje — jeśli skasujesz pod Fluxa, k3s go wznowi

### Krok 2 — Source Controller śledzi repo
Flux co 1 minutę (domyślnie) robi `git fetch`. Gdy widzi nowy commit — pobiera
zmiany i przekazuje dalej do kontrolerów.

### Krok 3 — Kustomize Controller aplikuje manifesty
Czyta YAML z repo (zwykłe manifesty k8s lub Kustomize) i robi `kubectl apply`.
Jeśli plik zniknął z gita → Flux usuwa zasób z klastra.

### Krok 4 — Helm Controller zarządza HelmRelease
Zamiast ręcznego `helm install`, w gicie trzymasz `HelmRelease` z przypiętą
wersją chartu:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
spec:
  chart:
    spec:
      chart: traefik
      version: "33.x"
      sourceRef:
        kind: HelmRepository
        name: traefik
  values:
    service:
      type: LoadBalancer
```
Flux sam robi `helm upgrade --install`. Zmiana wersji = edycja YAML + `git push`.

### Krok 5 — SOPS odszyfrowuje sekrety
Sekrety w repo są zaszyfrowane age'em. Flux ma klucz age (wgrany jako Secret
`sops-age` przez Ansible) i odszyfrowuje je **w locie** zanim zaaplikuje. Ty
commitujesz zaszyfrowany YAML, w klastrze ląduje plaintext jako `Secret`.

## Powiązane
- [`planning.md`](planning.md) — decyzje, opcje, plan
- [`CLAUDE.md`](CLAUDE.md) — zasady pracy w repo
- `k8s-hetzner/README.md` — klaster na Hetznerze (ten sam model GitOps)
