# Homelab — notatki i decyzje

> Rozkminki i uzasadnienia wyborów architektonicznych. Operacyjna dokumentacja
> (jak postawić, struktura, troubleshooting) jest w [`README.md`](README.md).

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

## Co robimy (plan)
- [x] **Decyzja:** B — k3s + Flux (hybryd: Compose akceptowalny dla prostych appliance'ów)
- [x] Ansible playbook gotowy (`ansible/`) — role: base, docker, k3s, sops, flux
- [x] Założyć repo `homelab` na GitHubie (`michcie/homelab`)
- [x] `flux bootstrap github` — Flux działa, branch `master`, path `clusters/homelab`
- [x] Struktura repo Flux: `clusters/homelab/`, `infrastructure/`, `apps/`
- [x] Traefik przez Flux (`infrastructure/traefik/` — HelmRelease v33.x)
- [x] `apps/whoami/` — test deploymentu, Ingress na `whoami.homelab.local`
- [x] Traefik działa, whoami odpowiada przez Ingress
- [x] cert-manager (`infrastructure/cert-manager/`) — Cloudflare DNS-01, staging + prod ClusterIssuer
- [x] SOPS + age — sekrety szyfrowane w repo, Flux odszyfrowuje przez `sops-age` Secret
- [x] Provisioning Hetzner utwardzony — prywatny NIC w cloud-init, `PermitRootLogin prohibit-password`, `IdentitiesOnly` w Ansible (patrz: Troubleshooting w README)
- [x] Flux guard naprawiony — rola `flux` sprawdza deployment `source-controller`, nie sam namespace (rola `sops` tworzy `flux-system` wcześniej, więc check na namespace zawsze skipował bootstrap)
- [ ] Wyjąć `hcloud_token` z `terraform.tfvars` do env (`TF_VAR_hcloud_token`/`HCLOUD_TOKEN`) — teraz wisi jawnie
- [ ] Zaszyfrować `cloudflare-secret.yaml` przez SOPS i pushować
- [ ] Migracja istniejących apek z Portainera do gita
- [ ] Backupy danych (PV) — Velero/restic — zanim zaczniemy polegać na klastrze

## Powiązane
- `homelab-briefing.md` — pierwotny brief (wspomina ten host jako hypervisor/
  dodatkowy klaster spięty z Hetznerem przez Wireguard)
- `k8s-hetzner/README.md` — klaster na Hetznerze (ten sam model GitOps)
