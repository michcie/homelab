# Homelab — notatki i decyzje

Fizyczny homelab na **jednym hoście** (Ryzen 16 rdzeni, 64 GB RAM, bare-metal
Ubuntu). Osobny temat od klastra `k8s-hetzner`, ale ma dzielić z nim filozofię:
**wszystko jako kod w gicie**.

## Pytanie wyjściowe
Jak najlepiej stawiać aplikacje na jednym hoście? Obecnie jest **Portainer** —
czy to najlepsze rozwiązanie?

## Ocena Portainera
OK na start, ale **kłóci się z podejściem IaC**: domyślnie klikasz w UI → stan
ląduje w bazie Portainera, nie w gicie → dryf, brak reprodukowalności, słaby
disaster-recovery. Da się go używać git-native (stacks-from-git/GitOps), ale to
okrężna droga do tego, co inne narzędzia robią prościej.

> Antywzorzec, od którego odchodzimy niezależnie od ścieżki:
> **klikanie apek w UI bez gita.**

## Opcje

### A) „Usługi mają po prostu niezawodnie chodzić" → Docker Compose w gicie
- `compose.yaml` w repo, katalog na apkę, `git pull` + `docker compose up -d`
- UI bez utraty gita jako źródła prawdy: **Dockge** (trzyma compose na dysku,
  nie w bazie jak Portainer) albo **Komodo** (build/deploy/monitoring, git-native)
- aktualizacje obrazów: Watchtower / Renovate
- najlepszy stosunek wysiłku do niezawodności na jednym hoście, mały narzut

### B) „Homelab ma ćwiczyć Kubernetes" → k3s single-node + Flux
- jeden węzeł k3s, apki przez Helm + **FluxCD** — ten sam workflow co Hetzner
- plus: **spójność** — manifesty, Flux, Helm, ingress, cert-manager reużywasz 1:1
- plus: podwaja repsy z k8s (zgodne z celem nauki)
- minus: więcej ruchomych części niż Docker; na 16c/64GB to komfort

### C) Zostać przy Portainerze
- sensowne tylko z włączonym **GitOps/stacks-from-git** (definicje w gicie, nie
  w klikach). Inaczej = dług techniczny.

## Rekomendacja
**Opcja B (k3s + Flux)** — bo kompounduje naukę i unifikuje narzędzia z Hetznerem.
Praktyczny hybryd: **k3s do rzeczy, na których chcesz ćwiczyć k8s, a Compose
(w gicie) do prostych appliance'ów** (Jellyfin, Vaultwarden). Na jednym hoście
spokojnie odpalisz oba.

## Czy w opcji B da się trzymać wszystko w gicie? (tak — to sedno GitOps)

**Git trzyma (deklaratywny stan całego klastra):**
- konfigurację Fluxa (`GitRepository`, `Kustomization`)
- wszystkie manifesty: Deploymenty, Service, Ingress, namespace, RBAC, NetworkPolicy
- Helm releases jako CR-y (`HelmRepository` + `HelmRelease`, wersje przypięte)
- dodatki: ingress (Traefik), cert-manager + Issuery, storage class
- instalację k3s (przez Ansible/cloud-init — też w gicie)

**Sekrety — w gicie, ale zaszyfrowane:**
- **SOPS + age** (Flux odszyfrowuje natywnie w klastrze) — złoty standard
- albo **Sealed Secrets**, albo **External Secrets Operator** (wartości w Vault/1Password)
- klucz odszyfrowujący trzymany **bezpiecznie poza gitem** (menedżer haseł/offline)

**Czego git NIE odtworzy (osobne mechanizmy):**
- **dane aplikacji** (bazy, media, uploady) — żyją w PersistentVolume na dysku;
  git trzyma deklarację PVC, nie zawartość → potrzebny **backup**
  (Velero / restic / VolSync / rsync)
- **klucz odszyfrowujący** SOPS/age — świadomie poza gitem
- runtime klastra (etcd, certy) — odtwarza się przy bootstrapie

**Odtworzenie od zera:**
```
1. Ansible/cloud-init  → OS + k3s            (z gita)
2. flux bootstrap      → wskazanie repo      (z gita)
3. Flux reconcile      → cały stan klastra   (z gita)
4. restore z backupu   → wracają DANE        (NIE z gita)
```

**Typowa struktura repo (Flux):**
```
homelab-k3s/
├── clusters/homelab/     # punkt wejścia Fluxa (Kustomizations)
├── infrastructure/       # ingress, cert-manager, storage…
├── apps/                 # aplikacje (HelmRelease / manifesty)
└── (sekrety zaszyfrowane SOPS-em)
```

## Co robimy (plan)
- [x] **Decyzja:** B — k3s + Flux (hybryd: Compose akceptowalny dla prostych appliance'ów)
- [ ] Domknąć Hetznera (serwery `off` na zdeprecjonowanym `cpx22`)
- [x] Ansible playbook gotowy (`ansible/`) — role: base, docker, k3s, sops, flux
- [x] Założyć repo `homelab` na GitHubie (`michcie/homelab`), uzupełnić `flux_github_owner` w `group_vars/all.yml`
- [x] Uruchomić Ansible na docelowym hoście (k3s v1.35.5+k3s1 na `homelab` node)
- [x] `flux bootstrap github` — Flux działa, branch `master`, path `clusters/homelab`
- [x] Struktura repo Flux: `clusters/homelab/`, `infrastructure/`, `apps/`
- [x] Traefik przez Flux (`infrastructure/traefik/` — HelmRepository + HelmRelease v33.x)
- [x] `apps/whoami/` — test deploymentu, Ingress na `whoami.homelab.local`
- [ ] Zweryfikować że Traefik dostał IP i whoami odpowiada przez Ingress
- [ ] cert-manager (`infrastructure/cert-manager/`)
- [ ] Migracja istniejących apek z Portainera do gita
- [ ] Backupy danych (PV) — Velero/restic — zanim zaczniemy polegać na klastrze

### Struktura repo
```
homelab/
├── clusters/homelab/          # punkt wejścia Fluxa
│   ├── flux-system/           # auto-generowane przez flux bootstrap
│   ├── infrastructure.yaml    # Flux Kustomization → ./infrastructure
│   └── apps.yaml              # Flux Kustomization → ./apps (depends: infrastructure)
├── infrastructure/
│   └── traefik/               # HelmRepository + HelmRelease
└── apps/
    └── whoami/                # test: Deployment + Service + Ingress
```

### Uwagi z konfiguracji
- k3s instalowany przez Ansible role z `/etc/rancher/k3s/config.yaml` (tls-san, disable traefik)
- Traefik jako HelmRelease, service type LoadBalancer (klipper-lb k3s)
- Ingress używa `ingressClassName: traefik`, host `whoami.homelab.local`

## Ansible — jak uruchomić

```bash
# Instalacja zależności (raz)
pip install ansible

# Wszystkie role naraz
ansible-playbook -i inventory.yml site.yml

# Tylko wybrane role (tagi)
ansible-playbook -i inventory.yml site.yml --tags base
ansible-playbook -i inventory.yml site.yml --tags k3s
ansible-playbook -i inventory.yml site.yml --tags sops,flux

# Flux bootstrap wymaga tokenu GitHub
GITHUB_TOKEN=ghp_xxx ansible-playbook -i inventory.yml site.yml --tags flux
```

Przed uruchomieniem uzupełnij w `group_vars/all.yml`:
- `flux_github_owner` — twój GitHub username
- opcjonalnie `k3s_version` (puste = latest)

IP hosta ustawiasz w `inventory.yml` → `ansible_host`.

## Jak działa Flux (krok po kroku)

### Idea
Flux to operator działający **wewnątrz klastra k3s**. Jego jedyne zadanie:
obserwować repo git i wymuszać, żeby klaster wyglądał dokładnie tak jak git.
Ty nie robisz `kubectl apply` ręcznie — robisz `git push`, a Flux robi resztę.

```
git push → Flux widzi zmianę → kubectl apply w tle → klaster = git
```

### Krok 1 — `flux bootstrap github`
To jednorazowa komenda (Ansible robi ją automatycznie przy pierwszym uruchomieniu).
Co się dzieje:

1. Flux instaluje swoje komponenty w namespace `flux-system` w klastrze
2. Tworzy deploy key na repo GitHubie (read-only dostęp do repo)
3. Commituje do repo manifesty Fluxa (`clusters/homelab/flux-system/`)
4. Od tej chwili Flux sam się utrzymuje — jeśli skasujesz pod Fluxa, k3s go wznowi

### Krok 2 — Source Controller śledzi repo
Flux co 1 minutę (domyślnie) robi `git fetch` na repo. Gdy widzi nowy commit:
- pobiera zmiany
- przekazuje dalej do kontrolerów

### Krok 3 — Kustomize Controller aplikuje manifesty
Czyta pliki YAML z repo (zwykłe manifesty k8s lub Kustomize) i robi `kubectl apply`.
Jeśli plik zniknął z gita → Flux usuwa zasób z klastra.

### Krok 4 — Helm Controller zarządza HelmRelease
Zamiast ręcznie robić `helm install`, w gicie trzymasz:
```yaml
# apps/traefik/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
spec:
  chart:
    spec:
      chart: traefik
      version: "30.x"
      sourceRef:
        kind: HelmRepository
        name: traefik
  values:
    service:
      type: LoadBalancer
```
Flux widzi ten plik → sam robi `helm upgrade --install traefik ...` z podanymi values.
Chcesz zmienić wersję? Edytujesz YAML, robisz `git push` — Flux upgraduje chart.

### Krok 5 — SOPS odszyfrowuje sekrety
Sekrety w repo są zaszyfrowane age'em. Flux ma dostęp do klucza age
(wgranego jako Secret do klastra przez Ansible) i odszyfrowuje je **w locie**
zanim zaaplikuje do klastra. Ty commitujesz zaszyfrowany YAML, w klastrze
ląduje plaintext jako `Secret`.

### Struktura repo po bootstrapie
```
homelab-k3s/
├── clusters/
│   └── homelab/
│       ├── flux-system/          # auto-generowane przez flux bootstrap
│       ├── infrastructure.yaml   # wskazuje na infrastructure/
│       └── apps.yaml             # wskazuje na apps/
├── infrastructure/
│   ├── traefik/                  # HelmRepository + HelmRelease
│   ├── cert-manager/
│   └── longhorn/                 # storage (opcjonalnie)
└── apps/
    ├── jellyfin/
    ├── vaultwarden/
    └── ...
```

### Kolejność deploymentu (dependency)
Flux pozwala zdefiniować zależności między Kustomizacjami:
```yaml
# apps.yaml musi czekać na infrastructure (ingress, cert-manager)
spec:
  dependsOn:
    - name: infrastructure
```
Dzięki temu aplikacje nie startują zanim nie ma ingressu i TLS.

## Powiązane
- `homelab-briefing.md` — pierwotny brief (wspomina ten host jako hypervisor/
  dodatkowy klaster spięty z Hetznerem przez Wireguard)
- `k8s-hetzner/README.md` — klaster na Hetznerze (ten sam model GitOps)
