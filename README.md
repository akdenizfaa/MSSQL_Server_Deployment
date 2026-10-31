# SQL Server 2025 Kurulum Otomasyonu

Ansible + AWX/AAP ile Windows Server 2019/2022/2025 üzerine SQL Server 2025 (17.x) kurulumu.

## Durum

| Faz | Kapsam | Durum |
|---|---|---|
| 0 | Discovery | Tamamlandı |
| 1 | İskelet + bağlantı (WinRM/Kerberos) | **Onay bekliyor** |
| 2 | Precheck | **Onay bekliyor** |
| 3+ | Medya, kurulum, konfigürasyon... | Başlamadı |

## Playbook'lar

| Playbook | Ne yapar | Hedefte değişiklik |
|---|---|---|
| `playbooks/00_connectivity_check.yml` | FQDN/DNS, WinRM port tespiti, Kerberos oturum, admin, domain, saat farkı, (ops.) medya paylaşımı | Yok |
| `playbooks/01_precheck.yml` | Bağlantı + OS/mimari/.NET/CPU/RAM/D-L-T diskleri/pending reboot/mevcut instance/port | Yok |

## Dizin yapısı

```
ansible.cfg                     # AWX proje kökünde otomatik okunur
collections/requirements.yml    # AWX proje sync'te otomatik kurulur
execution-environment.yml       # ansible-builder (pywinrm[kerberos] + krb5)
inventories/<env>/              # dev | test | uat | prod
playbooks/                      # 00_, 01_ ... + _init_execution.yml
roles/sql_common                # ortak rapor yardımcısı
roles/sql_connection            # Faz 1
roles/sql_precheck              # Faz 2
awx/surveys/                    # job template survey JSON'ları
tests/                          # Windows'suz mock testleri
docs/
```

## Hızlı başlangıç (CLI)

```bash
ansible-galaxy collection install -r collections/requirements.yml
pip install -r requirements.txt
ansible-playbook -i inventories/dev/hosts.yml playbooks/00_connectivity_check.yml \
  --limit sqlsrv01.corp.example.com \
  -e ansible_user=svc_ansible@CORP.EXAMPLE.COM -e ansible_password='***'
```

AWX/AAP kurulumu: [docs/awx-setup.md](docs/awx-setup.md) · Kontrol kataloğu: [docs/checks.md](docs/checks.md)
