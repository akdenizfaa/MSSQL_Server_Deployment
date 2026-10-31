# PHASE 1 + 2 – Bağlantı katmanı ve Precheck

**Tarih:** 2026-11-01
**Durum:** Kod yazıldı, mock testlerden geçti. Gerçek DEV sunucusunda çalıştırılmadı. **Onay bekleniyor.**

## 1. Alınan kararlar

| Konu | Karar | Kaynak |
|---|---|---|
| Domain / Kerberos (IR-2) | Hedefler ve controller domain'de, Kerberos hazır | Kullanıcı |
| WinRM transport (IR-2) | Bilinmiyor → playbook otomatik tespit eder (HTTPS öncelikli) | Kullanıcı |
| Secret yönetimi (D-2) | Başlangıçta vars + AWX survey | Kullanıcı |
| Disk standardı (IR-3) | D = data + system DB root, L = log, T = tempdb; precheck varlığını doğrular | Kullanıcı |

## 2. Assumption / Default / Reason

| # | Assumption / Default | Reason | Nasıl değişir |
|---|---|---|---|
| AS-1 | "Survey" ifadesinden çalışma platformunun **AWX veya AAP** olduğu varsayıldı | Survey yalnızca AWX/AAP job template'lerinde var | IR-13 teyidi |
| AS-2 | WinRM **giriş** kimliği survey yerine AWX **Machine credential** | Şifre job extra_vars'a düşmez; AWX standardı. Survey password alanları Faz 4'te SQL hesapları için kullanılacak | Survey isterseniz `ansible_password` survey değişkeni olarak da çalışır |
| DF-1 | `sql_instance_name: MSSQLSERVER` | Default instance en yaygın kurumsal model | group_vars veya survey |
| DF-2 | `sql_tcp_port: 1433` | Port standardı teyit edilmedi | group_vars veya survey |
| DF-3 | Binary dizini `C:` (min. 6 GB) | Sadece D/L/T standardı verildi | `sql_binaries_drive` |
| DF-4 | Allocation unit 64 KB değilse **WARN** (FAIL değil) | Microsoft best practice, zorunlu değil | `sql_precheck_recommended_allocation_unit_kb` |
| DF-5 | **PROD'da WARN = FAIL** (`sql_precheck_fail_on_warning: true`), diğer ortamlarda WARN geçer | PROD'da formatlama/port sorunu sonradan düzeltilemez | `inventories/prod/group_vars` |
| DF-6 | HTTPS sertifika doğrulaması `validate` | `ignore` MITM riskini açar | `sql_connection_cert_validation` |
| DF-7 | Kerberos delegation **kapalı** | D-1 kararı ve medya reposu (IR-1) henüz yok | Faz 3 |
| DF-8 | Bekleyen reboot → FAIL, otomasyon reboot **yapmaz** | Phase 0 kararı (reboot.allowed=false) | `sql_precheck_fail_on_pending_reboot` |
| DF-9 | Domain controller hedef → FAIL | Microsoft önermez | `sql_precheck_allow_domain_controller` |
| DF-10 | EE base image `quay.io/ansible/awx-ee:latest` | Kurumsal onaylı image bilinmiyor | IR-13 |

## 3. Phase 0 planından sapmalar

| Sapma | Neden |
|---|---|
| Kök dizindeki `group_vars/all/` kaldırıldı; değişkenler `inventories/<env>/group_vars/` ve rol `defaults/vars` içinde | Ansible `group_vars`'ı yalnızca **inventory dosyasının** veya **playbook'un** yanında okur. Kökteki `group_vars/`, playbook'lar `playbooks/` altında olduğu için hiç yüklenmezdi |
| İç içe `sql_server:` sözlüğü yerine düz değişkenler (`sql_instance_name`, `sql_tcp_port`) | Survey/extra_vars bir sözlüğün tek anahtarını override edemez, sözlüğün tamamını değiştirir |
| OS destek matrisi `roles/sql_precheck/vars/main.yml` içinde | Microsoft gerçeği; ortama göre değişmemeli (vars önceliği yüksek) |
| `sql_common` rolü şimdilik sadece rapor yardımcısı | execution_id controller'da ayrı bir play'de üretiliyor (`_init_execution.yml`) |

## 4. Mimari notlar (kritik)

1. **Transport tespiti controller'dan yapılır.** Önce TCP probe (5986 → 5985), sonra seçilen değer `set_fact` ile `ansible_port` / `ansible_winrm_scheme` olarak host'a uygulanır. `set_fact` önceliği inventory'den yüksek olduğu için sonraki tüm Windows task'ları bu değeri kullanır. HTTP seçilirse `ansible_winrm_message_encryption: always` zorlanır.
2. **Toplama ve değerlendirme hedefte, politika Ansible'da.** Eşikler `PolicyJson` ile tek seferde gönderilir, tek WinRM çağrısıyla tüm kontroller yapılır (host başına ~1 round-trip). Politika kodda değil, rol değişkenlerinde.
3. **Salt okuma garantisi.** PowerShell script'leri `[CmdletBinding(SupportsShouldProcess)]` taşır; `win_powershell` bu bildirim olmadan check mode'da script'i atlar. Böylece `--check` ile de çalışır ve `changed=0` döner.
4. **Kısmi başarısızlıkta tam rapor.** Her kontrol bir listeye eklenir; bloklayıcı hata sonraki adımları atlar ama rapor yine üretilir. Playbook'larda `block/rescue` kullanıldı: Ansible bir play'deki tüm hostlar fail olursa sonraki play'leri atlar; rescue sayesinde özet ve AWX artifact her zaman yayınlanır, job yine de FAILED biter.
5. **Unreachable yakalama.** Kerberos hataları Ansible'da genelde *unreachable* olarak gelir ve `rescue` bunu yakalamaz. CN-004'te `ignore_unreachable: true` + register ile değerlendirildi.

## 5. Test sonuçları

| Test | Sonuç |
|---|---|
| `yamllint` | Temiz |
| `ansible-lint` (profile: production) | 0 hata, 0 uyarı |
| `--syntax-check` (2 playbook) | OK |
| PowerShell AST parse (pwsh 7.4.6) | 0 hata (2 script) |
| PowerShell mock çalıştırma (sahte CIM/registry) | 22 kontrol beklendiği gibi: T: yok → FAIL, CBS reboot → FAIL, 4 KB AU → WARN, kurulu instance → WARN, port sahibi kendi instance → INFO |
| Ansible negatif: IP adresi | CN-001 FAIL |
| Ansible negatif: çözülemeyen ad | CN-002 FAIL |
| Ansible negatif: WinRM portu kapalı | CN-003 FAIL |
| Ansible mock: iyi senaryo | connection PASSED, precheck PASSED, rc=0 |
| Ansible mock: NTLM oturumu | CN-005 FAIL, precheck NOT_RUN, rc=2 |
| Ansible mock: disk eksik | precheck FAILED, özet + job fail, rc=2 |

**Test edilmeyen:** Gerçek Windows + gerçek Kerberos. Bunun için IR-12 (DEV sunucusu) gerekli.
Mock testleri tekrar çalıştırmak için: `tests/run_mock_tests.sh`.

## 6. Riskler

| # | Risk | Azaltma |
|---|---|---|
| R-12 | EE'de `krb5.conf` yoksa CN-004 belirsiz bir hatayla düşer | `docs/awx-setup.md` §1; hata mesajı olası nedenleri listeler |
| R-13 | Kurumsal CA EE'de güvenilir değilse HTTPS bağlantısı düşer | CA'yı EE'ye ekleyin; `ignore` önerilmez |
| R-14 | PROD'da kurulu instance (PC-032 WARN) yeniden çalıştırmada precheck'i durdurur | Bilinçli: precheck "kuruluma hazır mı" sorar. Faz 4 idempotency akışında ele alınacak |
| R-15 | `PendingFileRenameOperations` bazen zararsız kalıntıdır ve FAIL üretir | SQL setup da aynı anahtara bakar; reboot dışında güvenli çözüm yok |

## 7. Information Required (açık kalanlar)

| # | Gerekli bilgi | Hangi faz |
|---|---|---|
| IR-1 | Medya reposu UNC yolu, klasör düzeni, hash dosyası | Faz 3 (CN-011 testi de bunu bekliyor) |
| IR-3 (kalan) | Klasör yapısı (ör. `D:\MSSQL\Data`?), port standardı, collation, MAXDOP/memory politikası | Faz 4–5 |
| IR-4 | Servis hesabı tipi (gMSA / domain user / virtual account) | Faz 4 |
| IR-12 | Test edilebilir DEV Windows sunucusu (FQDN) | Faz 1–2 gerçek doğrulama |
| IR-13 | AWX mı AAP mı, sürümü, onaylı EE base image | EE build |
| IR-14 | Kerberos realm adı, KDC'ler DNS'te SRV kaydıyla mı bulunuyor | EE `krb5.conf` |

## 8. Rollback

Hedef sistemlerde değişiklik yok. Repository tarafında rollback = bu değişiklikleri merge etmemek.

## APPROVAL REQUIRED

Faz 3'e (offline medya) geçmeden önce:
1. Bu fazın onayı (özellikle AS-1, AS-2, DF-5)
2. Bir DEV sunucusunda `00_connectivity_check` ve `01_precheck` çıktısının paylaşılması (IR-12)
3. IR-1 ve D-1 (double-hop) kararı
