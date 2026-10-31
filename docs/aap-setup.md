# Ansible Automation Platform kurulumu (Faz 1–2)

## 1. Execution Environment

Kerberos ile WinRM için EE içinde şunlar olmalıdır:

- `ansible.windows` collection'ı
- `pywinrm` ve Kerberos desteği (`pyspnego` + krb5 binding)
- Kerberos istemci kütüphaneleri (`krb5-workstation` / `krb5-libs`)

**Önce hazır image'ı kontrol edin.** Red Hat'in `ee-supported` image'ı bunları zaten içeriyorsa custom build gerekmez:

```bash
podman run --rm registry.redhat.io/ansible-automation-platform-26/ee-supported-rhel9:latest \
  bash -c "ansible-galaxy collection list ansible.windows; \
           python3 -c 'import winrm, spnego; print(\"pywinrm\", winrm.__version__ if hasattr(winrm, \"__version__\") else \"ok\")'; \
           python3 -c 'import krb5' && echo krb5-binding-ok; which kinit"
```

Bu çıktıda collection listelenmiyor, `import` hata veriyor veya `kinit` bulunamıyorsa repo'daki `execution-environment.yml` ile custom EE build edin:

```bash
podman login registry.redhat.io
ansible-builder build -f execution-environment.yml -t <private-automation-hub>/sql-automation-ee:1.0.0
podman push <private-automation-hub>/sql-automation-ee:1.0.0
```

AAP'te: **Automation Execution → Infrastructure → Execution Environments → Create**. Image olarak yukarıdaki tag'i seçin, Pull = *Always* veya *Missing*.

## 2. krb5.conf

`krb5.conf` image'a gömülmez, çünkü realm ve KDC bilgisi ortama özeldir. Red Hat'in önerdiği iki yol:

| Seçenek | Nasıl | Not |
|---|---|---|
| **Mount (önerilen)** | Controller/execution node'lara `/etc/krb5.conf` dosyasını koyun. Ardından **Settings → Job Settings → Paths to expose to isolated jobs** alanına `/etc/krb5.conf` ekleyin (`includedir` kullanılıyorsa `/etc/krb5.conf.d` de eklenmeli). | Realm değişikliği image rebuild gerektirmez |
| Image'a eklemek | ansible-builder `additional_build_files` ile kopyalamak | Her değişiklikte rebuild gerekir |

Minimal örnek (değerler size ait, IR-14):

```ini
[libdefaults]
  default_realm = CORP.EXAMPLE.COM
  dns_lookup_kdc = true
  dns_lookup_realm = false
  forwardable = true       # Faz 3'te Kerberos delegation (double-hop) için gerekecek
  rdns = false
  # Container içinden host keyring'e erişilemez; dosya tabanlı cache kullanılmalı
  default_ccache_name = FILE:/tmp/krb5cc_%{uid}
```

> `krb5.conf.d` içindeki `includedir` satırları, EE'nin göremediği dizinleri gösteriyorsa Kerberos sessizce başarısız olur. Red Hat'in troubleshooting notu da bu konuda uyarıyor.

## 3. Credential

| Tür | Alan | Değer |
|---|---|---|
| Machine | Username | `svc_ansible@CORP.EXAMPLE.COM` (**realm büyük harf**) |
| Machine | Password | hesap şifresi |

**Neden survey değil de Machine credential?** WinRM giriş şifresi AAP'te şifreli saklanır, job çıktısına ve `extra_vars`'a hiç düşmez. Ayrıca RBAC ile kimin kullanabileceği yönetilir. SQL servis hesabı ve SA şifreleri (Faz 4) için survey `password` alanları kullanılacak.

Collection'ların proje sync'te inmesi için organizasyona bir **Ansible Galaxy / Automation Hub credential** tanımlı olmalıdır (Access Management → Organizations → Galaxy Credentials).

## 4. Project ve Inventory

- **Project:** bu Git repository'si. Source Control Branch = `main` (onaylanmış fazlar).
- **Inventory:** her ortam için ayrı inventory. Source = *Sourced from a Project*, dosya = `inventories/<env>/hosts.yml`. Yanındaki `group_vars/sql_targets.yml` otomatik yüklenir.
- `playbooks/group_vars/all/sql_version_matrix.yml` playbook'un yanında olduğu için her job'da otomatik yüklenir.

## 5. Job Template'ler

| Ad | Playbook | Survey | Limit |
|---|---|---|---|
| SQL - 00 Connectivity Check | `playbooks/00_connectivity_check.yml` | `aap/surveys/00_connectivity_check.json` | *Prompt on launch* |
| SQL - 01 Precheck | `playbooks/01_precheck.yml` | `aap/surveys/01_precheck.json` | *Prompt on launch* |

Ortak ayarlar: Execution Environment = §1, Credential = Machine (§3), Verbosity = 0 (Normal).

Survey'i API ile yüklemek için (AAP 2.5+ gateway yolu):

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d @aap/surveys/01_precheck.json \
  https://<aap>/api/controller/v2/job_templates/<id>/survey_spec/
```

Survey'deki **SQL Server sürümü** alanı zorunludur ve default değeri yoktur. Operatör her çalıştırmada sürümü bilinçli olarak seçer.

`sql_precheck_fail_on_warning` bilinçli olarak survey'de **yok**. Survey değişkenleri en yüksek önceliğe sahiptir; bu ayar survey'de olsaydı PROD'daki katı politika launch anında kapatılabilirdi.

## 6. Job artifact

Her iki playbook da sonunda `set_stats` ile `sql_execution_id` ve host bazlı özet yayınlar. Bir AAP workflow'unda sonraki node bu değişkenleri doğrudan okuyabilir (ör. precheck PASSED olmayan hostu install node'una göndermemek için).
