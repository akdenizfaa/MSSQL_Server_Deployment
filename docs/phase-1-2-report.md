# PHASE 1 + 2 – Bağlantı katmanı ve Precheck (Revizyon 2)

**Tarih:** 2026-11-01
**Durum:** Kod yazıldı, mock testlerden geçti. Gerçek DEV sunucusunda çalıştırılmadı. **Onay bekleniyor (PR #1).**

## 0. Revizyon 2 – ne değişti

| Karar güncellemesi (kullanıcı) | Koda etkisi |
|---|---|
| Otomasyon **SQL Server 2019, 2022 ve 2025** için çalışacak | Zorunlu `sql_version` girdisi; sürüm matrisi (`playbooks/group_vars/all/sql_version_matrix.yml`); precheck OS, .NET ve instance kontrollerini seçilen sürüme göre yapıyor |
| Platform **Ansible Automation Platform** | AS-1 kapandı. EE base image AAP `ee-minimal`; `docs/aap-setup.md`; `aap/surveys/`; AAP 2.5+ API yolu |

Değişen dosyalar (özet):

| Dosya | Değişiklik |
|---|---|
| `playbooks/group_vars/all/sql_version_matrix.yml` | **Yeni.** 2019/2022/2025 için major sürüm, instance ID öneki, desteklenen OS build'leri, .NET ve donanım minimumları |
| `roles/sql_precheck/vars/main.yml` | **Silindi.** Tek sürümlük gereksinimler matrise taşındı |
| `roles/sql_precheck/tasks/main.yml` | `sql_version` doğrulaması, sürüme göre policy seçimi, rapor başlığı sürüme göre |
| `roles/sql_precheck/files/Invoke-SqlPrecheck.ps1` | Sürüme göre OS mesajı; .NET şartı yoksa INFO; sistem sürücüsü kontrolü; major sürüm çakışması FAIL; port sahipliği major'a göre |
| `aap/surveys/01_precheck.json` | Zorunlu **SQL Server sürümü** (2019/2022/2025) alanı, default yok |
| `execution-environment.yml` | Base image: `registry.redhat.io/ansible-automation-platform-26/ee-minimal-rhel9` |
| `collections/requirements.yml` | `community.windows` kaldırıldı (kullanılmıyordu) |
| `docs/aap-setup.md` | AWX dokümanı yerine; EE doğrulama komutu, krb5.conf mount, Galaxy credential |
| `tests/` | Mock testleri 3 sürüm × beklenen sonuç tablosuyla; Ansible akışında 7 senaryo |

Bağlantı katmanı (Faz 1) sürümden bağımsız olduğu için mantığı değişmedi; sadece AAP terminolojisi güncellendi.

## 1. Alınan kararlar

| Konu | Karar | Kaynak |
|---|---|---|
| SQL sürümleri | **2019, 2022, 2025** | Kullanıcı (Rev. 2) |
| Platform | **Ansible Automation Platform** | Kullanıcı (Rev. 2) |
| Domain / Kerberos (IR-2) | Hedefler ve controller domain'de, Kerberos hazır | Kullanıcı |
| WinRM transport (IR-2) | Bilinmiyor → playbook otomatik tespit eder (HTTPS öncelikli) | Kullanıcı |
| Secret yönetimi (D-2) | Başlangıçta vars + AAP survey | Kullanıcı |
| Disk standardı (IR-3) | D = data + system DB root, L = log, T = tempdb; precheck varlığını doğrular | Kullanıcı |

## 2. Microsoft'tan doğrulanan sürüm gereksinimleri (2026-11-01)

| | SQL Server 2019 (15.x) | SQL Server 2022 (16.x) | SQL Server 2025 (17.x) |
|---|---|---|---|
| WS 2019 / 2022 / 2025 | Destekli (RTM) | Destekli (RTM) | Destekli (RTM) |
| Server Core | Destekli | Destekli | Destekli |
| .NET Framework | Ayrı şart yok: "minimum OS includes minimum .NET" | 4.7.2 | 4.7.2 |
| RAM (Express dışı) | 1 GB | 1 GB | 1 GB |
| CPU | x64, 1.4 GHz | x64, 1.4 GHz | x64, 1.4 GHz |
| Disk | 6 GB, **sistem sürücüsünde** | 6 GB, sistem sürücüsünde | 6 GB |

Not: Microsoft SQL 2019/2022'yi Windows Server 2016'da da destekliyor. WS2016 projenin hedef OS listesinde olmadığı için matrise eklenmedi. Eklenmesi tek satırlık bir değişiklik (build 14393).

## 3. Assumption / Default / Reason

| # | Assumption / Default | Reason | Nasıl değişir |
|---|---|---|---|
| ~~AS-1~~ | ~~AWX/AAP varsayımı~~ | **Kapandı:** kullanıcı AAP'yi teyit etti | — |
| AS-2 | WinRM **giriş** kimliği survey yerine AAP **Machine credential** | Şifre job extra_vars'a düşmez, RBAC ile yönetilir. Survey password alanları Faz 4'te SQL hesapları için | Survey isterseniz `ansible_password` survey değişkeni olarak da çalışır |
| DF-1 | `sql_instance_name: MSSQLSERVER` | Default instance en yaygın kurumsal model | group_vars veya survey |
| DF-2 | `sql_tcp_port: 1433` | Port standardı teyit edilmedi | group_vars veya survey |
| DF-3 | Binary sürücüsü `C:` | Sadece D/L/T standardı verildi | `sql_binaries_drive` |
| DF-4 | Allocation unit 64 KB değilse **WARN** (FAIL değil) | Microsoft best practice, zorunlu değil | `sql_precheck_recommended_allocation_unit_kb` |
| DF-5 | **PROD'da WARN = FAIL** (`sql_precheck_fail_on_warning: true`) | PROD'da formatlama/port sorunu sonradan düzeltilemez | `inventories/prod/group_vars` |
| DF-6 | HTTPS sertifika doğrulaması `validate` | `ignore` MITM riskini açar | `sql_connection_cert_validation` |
| DF-7 | Kerberos delegation **kapalı** | D-1 kararı ve medya reposu (IR-1) henüz yok | Faz 3 |
| DF-8 | Bekleyen reboot → FAIL, otomasyon reboot **yapmaz** | Phase 0 kararı | `sql_precheck_fail_on_pending_reboot` |
| DF-9 | Domain controller hedef → FAIL | Microsoft önermez | `sql_precheck_allow_domain_controller` |
| DF-10 | EE base image AAP **2.6** namespace (`ansible-automation-platform-26`) | AAP sürümü bilinmiyor; 2.6 güncel dokümantasyondaki sürüm | IR-13 |
| DF-11 | `sql_version` için **default yok**, zorunlu | Yanlış sürümün sessizce kurulmasını engellemek | — |
| DF-12 | Aynı instance adıyla **farklı major** sürüm kuruluysa → **FAIL** | Ad çakışması; in-place upgrade projenin kapsamında değil | Upgrade ileride ayrı bir faz olarak ele alınabilir |

## 4. Phase 0 planından sapmalar

| Sapma | Neden |
|---|---|
| Kök `group_vars/all/` yerine `playbooks/group_vars/all/` (sürüm matrisi) ve `inventories/<env>/group_vars/` | Ansible `group_vars`'ı yalnızca inventory'nin veya **playbook'un** yanında okur. Kökteki dizin hiç yüklenmezdi |
| İç içe `sql_server:` sözlüğü yerine düz değişkenler (`sql_version`, `sql_instance_name`, `sql_tcp_port`) | Survey/extra_vars bir sözlüğün tek anahtarını override edemez, sözlüğün tamamını değiştirir |
| `sql_common` rolü şimdilik sadece rapor yardımcısı | execution_id ayrı bir play'de üretiliyor (`_init_execution.yml`) |

## 5. Mimari notlar (kritik)

1. **Sürüm = veri, kod değil.** Sürüme özgü her şey (`major`, `instance_id_prefix`, desteklenen OS build'leri, .NET, donanım) tek bir matris dosyasında. Faz 3–6'da medya yolu, beklenen build ve setup parametreleri de bu matrise eklenecek. Yeni bir sürüm eklemek, kod değişikliği değil veri değişikliği olacak.
2. **Matrisin yeri.** `playbooks/group_vars/all/` her playbook'a otomatik yüklenir, rol dışından okunabilir ve tüm rollerce paylaşılır. Alternatif olan rol `vars/` her rolde kopya gerektirirdi. Bedeli: inventory group_vars daha yüksek öncelikli olduğu için matris ortam bazında override edilebilir. Bunu bilinçli bir esneklik olarak bıraktım.
3. **Transport tespiti controller'dan yapılır.** Önce TCP probe (5986 → 5985), sonra `set_fact` ile `ansible_port` / `ansible_winrm_scheme` host'a uygulanır. HTTP seçilirse `ansible_winrm_message_encryption: always` zorlanır.
4. **Toplama ve değerlendirme hedefte, politika Ansible'da.** Seçilen sürümün gereksinimleri `PolicyJson` ile gönderilir; tek WinRM çağrısında tüm kontroller yapılır.
5. **Salt okuma garantisi.** PowerShell script'leri `[CmdletBinding(SupportsShouldProcess)]` taşır; `--check` modunda da çalışır ve `changed=0` döner.
6. **Kısmi başarısızlıkta tam rapor.** `block/rescue` sayesinde tüm hostlar fail olsa bile özet ve AAP artifact yayınlanır; job yine de FAILED biter.
7. **Unreachable yakalama.** Kerberos hataları genelde *unreachable* olarak gelir ve `rescue` bunu yakalamaz. CN-004'te `ignore_unreachable: true` kullanıldı.

## 6. Test sonuçları

| Test | Sonuç |
|---|---|
| `yamllint` | Temiz |
| `ansible-lint` (profile: production) | 0 hata, 0 uyarı |
| `--syntax-check` (2 playbook) | OK |
| PowerShell AST parse (pwsh 7.4.6) | 0 hata |
| PowerShell mock, 3 sürüm × beklenen sonuç tablosu | Tüm assertion'lar geçti. Mock sunucuda MSSQLSERVER = SQL 2022 kurulu → hedef 2022: PC-032 WARN / port INFO; hedef 2019 ve 2025: PC-032 FAIL (ad çakışması) / port WARN; 2019'da .NET INFO |
| Ansible negatif: IP adresi / çözülemeyen ad / kapalı port | CN-001 / CN-002 / CN-003 FAIL |
| Ansible mock: `sql_version` = 2019 / 2022 / 2025 | PASSED, rc=0 (rapor başlığı sürüme göre) |
| Ansible mock: `sql_version` yok | Anlaşılır hata, rc=2 |
| Ansible mock: `sql_version=2017` | Anlaşılır hata, rc=2 |
| Ansible mock: disk eksik | precheck FAILED, rc=2 |
| Ansible mock: NTLM oturumu | CN-005 FAIL, precheck NOT_RUN, rc=2 |

Mock testi bir mantık hatası yakaladı ve düzeltildi: aynı adla farklı sürüm kuruluyken port "hedef instance'a ait" diye INFO raporlanıyordu. Artık sadece aynı major sürümde INFO.

**Test edilmeyen:** Gerçek Windows + gerçek Kerberos + AAP. Bunun için IR-12 gerekli.
Tekrar çalıştırmak için: `tests/run_mock_tests.sh`.

## 7. Riskler

| # | Risk | Azaltma |
|---|---|---|
| R-12 | EE'de `krb5.conf` yoksa CN-004 belirsiz bir hatayla düşer | `docs/aap-setup.md` §2 (Paths to expose to isolated jobs) |
| R-13 | Kurumsal CA EE'de güvenilir değilse HTTPS bağlantısı düşer | CA'yı EE'ye ekleyin; `ignore` önerilmez |
| R-14 | PROD'da kurulu instance (PC-032 WARN) yeniden çalıştırmada precheck'i durdurur | Bilinçli. Faz 4 idempotency akışında ele alınacak |
| R-15 | `PendingFileRenameOperations` bazen zararsız kalıntıdır ve FAIL üretir | SQL setup da aynı anahtara bakar; reboot dışında güvenli çözüm yok |
| R-16 | Operatör yanlış sürümü seçebilir | Survey zorunlu ve default'suz; rapor başlığında sürüm açıkça yazıyor; aynı adla farklı sürüm FAIL |
| R-17 | AAP proje sync'te `ansible.windows` inmez | Organizasyona Galaxy/Automation Hub credential tanımlanmalı (`docs/aap-setup.md` §3) |

## 8. Information Required (açık kalanlar)

| # | Gerekli bilgi | Hangi faz |
|---|---|---|
| IR-13 | **AAP sürümü** (2.4 / 2.5 / 2.6), private automation hub var mı, onaylı EE image | EE build, API yolları |
| IR-12 | Test edilebilir DEV Windows sunucusu (FQDN) | Faz 1–2 gerçek doğrulama |
| IR-14 | Kerberos realm adı, KDC'ler DNS SRV ile mi bulunuyor | `krb5.conf` |
| IR-1 | Medya reposu: UNC yolu, **3 sürüm için** klasör düzeni (sürüm/edition/CU), hash dosyası | Faz 3 |
| IR-15 | Her sürüm için hedef güncelleme seviyesi politikası (ör. "en son CU" mu, kurum onaylı sabit CU mu) | Faz 3–4 |
| IR-3 (kalan) | Klasör yapısı (ör. `D:\MSSQL\Data`?), port standardı, collation, MAXDOP/memory politikası | Faz 4–5 |
| IR-4 | Servis hesabı tipi (gMSA / domain user / virtual account) | Faz 4 |

## 9. Rollback

Hedef sistemlerde değişiklik yok. Repository tarafında rollback = PR #1'i merge etmemek.

## APPROVAL REQUIRED

Faz 3'e (offline medya) geçmeden önce:
1. Bu fazın onayı (PR #1 merge) — özellikle AS-2, DF-5, DF-11, DF-12
2. IR-13 (AAP sürümü)
3. Bir DEV sunucusunda `00_connectivity_check` ve `01_precheck` çıktısının paylaşılması (IR-12)
4. IR-1, IR-15 ve D-1 (double-hop) kararı
