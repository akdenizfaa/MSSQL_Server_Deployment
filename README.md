# SQL Server Kurulum Otomasyonu

Ansible Automation Platform (AAP) ile Windows Server 2019 / 2022 / 2025 üzerine
**SQL Server 2019 (15.x), 2022 (16.x) ve 2025 (17.x)** kurulumu.

Geliştirme fazlar halinde ilerler. Her faz kendi branch'inde geliştirilir ve
onaydan sonra pull request ile `main`'e merge edilir.

## Durum

| Faz | Kapsam | Durum |
|---|---|---|
| 0 | Discovery | Tamamlandı |
| 1 | İskelet + bağlantı (WinRM/Kerberos) | **Onay bekliyor** (PR #1) |
| 2 | Precheck (sürüme duyarlı) | **Onay bekliyor** (PR #1) |
| 3+ | Medya, kurulum, konfigürasyon... | Başlamadı |

## Desteklenen kombinasyonlar

| | WS 2019 | WS 2022 | WS 2025 |
|---|---|---|---|
| SQL Server 2019 | ✔ | ✔ | ✔ |
| SQL Server 2022 | ✔ | ✔ | ✔ |
| SQL Server 2025 | ✔ | ✔ | ✔ |

Kaynak: Microsoft "Using SQL Server in Windows" destek matrisi (hepsi RTM'den itibaren).
Veri: `playbooks/group_vars/all/sql_version_matrix.yml`

## Playbook'lar

| Playbook | Ne yapar | Hedefte değişiklik |
|---|---|---|
| `playbooks/00_connectivity_check.yml` | FQDN/DNS, WinRM port tespiti, Kerberos oturum, admin, domain, saat farkı, (ops.) medya paylaşımı | Yok |
| `playbooks/01_precheck.yml` | Bağlantı + seçilen SQL sürümüne göre OS/.NET/donanım, D-L-T diskleri, pending reboot, mevcut instance/sürüm çakışması, port | Yok |

## Dizin yapısı

```
ansible.cfg                          # AAP proje kökünde otomatik okunur
collections/requirements.yml         # AAP proje sync'te otomatik kurulur
execution-environment.yml            # ansible-builder (AAP ee-minimal + Kerberos)
inventories/<env>/                   # dev | test | uat | prod
playbooks/                           # 00_, 01_ ... + _init_execution.yml
playbooks/group_vars/all/            # sürüm matrisi (tüm playbook'lara yüklenir)
roles/sql_common                     # ortak rapor yardımcısı
roles/sql_connection                 # Faz 1
roles/sql_precheck                   # Faz 2
aap/surveys/                         # job template survey JSON'ları
tests/                               # Windows'suz mock testleri
docs/
```

## Hızlı başlangıç (CLI, AAP dışında deneme için)

```bash
ansible-galaxy collection install -r collections/requirements.yml
pip install -r requirements.txt
ansible-playbook -i inventories/dev/hosts.yml playbooks/01_precheck.yml \
  --limit sqlsrv01.corp.example.com -e sql_version=2022 \
  -e ansible_user=svc_ansible@CORP.EXAMPLE.COM -e ansible_password='***'
```

AAP kurulumu: [docs/aap-setup.md](docs/aap-setup.md) · Kontrol kataloğu: [docs/checks.md](docs/checks.md)
