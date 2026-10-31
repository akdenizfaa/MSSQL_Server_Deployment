# AWX / AAP kurulumu (Faz 1–2)

## 1. Execution Environment

Kerberos için EE içinde `pywinrm[kerberos]`, `krb5-workstation` ve bir `krb5.conf` gerekir.

```bash
ansible-builder build -f execution-environment.yml -t <registry>/sql-automation-ee:1.0.0
podman push <registry>/sql-automation-ee:1.0.0
```

`krb5.conf` image'a gömülmez (realm/KDC ortama özel). İki seçenek:

| Seçenek | Nasıl | Not |
|---|---|---|
| Volume mount (önerilen) | AWX: Settings → Job Settings → *Paths to expose to isolated jobs* veya container group pod spec ile `/etc/krb5.conf` mount | Realm değişikliği image rebuild gerektirmez |
| Image'a eklemek | `additional_build_files` ile kopyalamak | Basit ama her değişiklikte rebuild |

Minimal `krb5.conf` örneği (değerler sizin ortamınıza göre — IR-14):

```ini
[libdefaults]
  default_realm = CORP.EXAMPLE.COM
  dns_lookup_kdc = true
  dns_lookup_realm = false
  forwardable = true          # Phase 3'te Kerberos delegation için gerekli olacak
  rdns = false
```

## 2. Credential

| Tür | Alan | Değer |
|---|---|---|
| Machine | Username | `svc_ansible@CORP.EXAMPLE.COM` (**realm büyük harf**) |
| Machine | Password | hesap şifresi |

Neden Machine credential, survey değil? WinRM giriş şifresi AWX'te şifreli saklanır, job çıktısına
ve `extra_vars`'a hiç düşmez. Survey `password` alanları da maskelenir ama job'un extra_vars'ında
`$encrypted$` olarak tutulur ve relaunch'ta yeniden sorulur; bağlantı kimliği için Machine
credential AWX'in standart yoludur. SQL servis hesabı / SA şifreleri (Faz 4) için survey `password`
alanı kullanılacak.

## 3. Project ve Inventory

- Project: bu repository (SCM). Collection'lar `collections/requirements.yml`'den otomatik kurulur.
- Inventory: her ortam için ayrı inventory, source = *Sourced from a Project*, dosya = `inventories/<env>/hosts.yml`.
  `group_vars/sql_targets.yml` otomatik yüklenir.

## 4. Job Template'ler

| Ad | Playbook | Survey | Limit |
|---|---|---|---|
| SQL - 00 Connectivity Check | `playbooks/00_connectivity_check.yml` | `awx/surveys/00_connectivity_check.json` | *Prompt on launch* |
| SQL - 01 Precheck | `playbooks/01_precheck.yml` | `awx/surveys/01_precheck.json` | *Prompt on launch* |

Ortak ayarlar: Execution Environment = yukarıdaki EE, Credential = Machine, Verbosity = 0 (Normal).

Survey JSON'u AWX API ile yüklemek için:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d @awx/surveys/01_precheck.json https://<awx>/api/v2/job_templates/<id>/survey_spec/
```

`sql_precheck_fail_on_warning` bilinçli olarak survey'de **yok**: survey değişkenleri en yüksek
önceliğe sahiptir; PROD'daki katı politikanın operatör tarafından launch anında kapatılmasını engeller.

## 5. Job artifact

Her iki playbook da sonunda `set_stats` ile `sql_execution_id` ve host bazlı özet yayınlar.
Bir AWX workflow'unda sonraki node bu değişkenleri doğrudan okuyabilir.
