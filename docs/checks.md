# Kontrol kataloğu

Status: **PASS** · **WARN** (devam edilebilir; PROD'da `sql_precheck_fail_on_warning: true` ile durdurur) · **FAIL** (host durur) · **SKIPPED** · **INFO**

## Faz 1 – Bağlantı (`sql_connection`)

| ID | Kontrol | FAIL/WARN koşulu | Neden önemli |
|---|---|---|---|
| CN-001 | Hedef adı FQDN | IP veya kısa ad → FAIL | Kerberos SPN `HTTP/<fqdn>` ile eşleşir |
| CN-002 | Controller'dan DNS çözümleme | Çözülemiyor → FAIL | EE/controller DNS |
| CN-003 | WinRM portu | 5986/5985 kapalı → FAIL; HTTP seçildi → INFO | Transport otomatik seçilir |
| CN-004 | WinRM oturumu (win_ping) | Bağlanamıyor → FAIL | Kerberos/credential/sertifika |
| CN-005 | Kimlik doğrulama protokolü | Kerberos değil → FAIL | NTLM'de double-hop yok |
| CN-006 | Yerel admin (elevated) | Değil → FAIL | SQL setup admin ister |
| CN-007 | Domain üyeliği | Değil → FAIL | Kerberos modeli |
| CN-008 | Hostname = inventory adı | Farklı → WARN | CNAME / yanlış sunucu |
| CN-009 | Saat farkı | >60 sn WARN, >300 sn FAIL | Kerberos toleransı 5 dk |
| CN-010 | Uzak ortam | INFO | OS, PS sürümü, listener'lar |
| CN-011 | Medya paylaşımı erişimi | Erişim yok → WARN; tanımsız → SKIPPED | Double-hop (D-1) teşhisi |

## Faz 2 – Precheck (`sql_precheck`)

Gereksinimler seçilen `sql_version` (2019 | 2022 | 2025) için `playbooks/group_vars/all/sql_version_matrix.yml`'den gelir.

| ID | Kontrol | FAIL/WARN koşulu | Kaynak |
|---|---|---|---|
| PC-001 | Desteklenen OS (seçilen SQL sürümü için) | Build matriste yok → FAIL | Microsoft |
| PC-002 | Product type | Workstation → FAIL; DC → FAIL (`allow_domain_controller` ile WARN) | Microsoft |
| PC-003 | Mimari | x64 değil → FAIL | Microsoft |
| PC-004 | Installation type | INFO (Server / Server Core) | — |
| PC-005 | .NET Framework | 2022/2025: release < 461808 (4.7.2) → FAIL. 2019: Microsoft ayrı şart belirtmiyor → INFO | Microsoft |
| PC-006 | CPU hızı | < 1400 MHz → FAIL | Microsoft |
| PC-007 | CPU topolojisi | INFO (Faz 5 MAXDOP/tempdb için) | — |
| PC-008 | RAM | < 1024 MB → FAIL | Microsoft |
| PC-009 | Sistem sürücüsü boş alan | < 6 GB → FAIL (setup geçici dosyaları) | Microsoft |
| PC-019 | Binary sürücüsü (sistemden farklıysa) | Yok → FAIL, varsa INFO | — |
| PC-010/013/016 | D: / L: / T: mevcut ve yerel sabit disk | Yok veya DriveType≠3 → FAIL | Kurumsal standart |
| PC-011/014/017 | D: / L: / T: dosya sistemi | NTFS/ReFS değil → FAIL | Microsoft |
| PC-012/015/018 | D: / L: / T: allocation unit | 64 KB değil → WARN | Best practice |
| PC-030 | Bekleyen reboot | CBS, WU, PendingFileRename, ComputerRename, DomainJoin, UpdateExeVolatile → FAIL | SQL setup kuralı |
| PC-031 | Windows Installer servisi | Disabled → FAIL | SQL setup |
| PC-032 | Hedef instance durumu | Aynı ad + aynı major → WARN (idempotency). Aynı ad + farklı major → FAIL (ad çakışması, upgrade kapsam dışı) | İdempotency |
| PC-033 | Diğer SQL instance'lar | INFO | — |
| PC-034 | TCP port | Başka süreç veya farklı sürümdeki instance dinliyor → WARN; aynı sürümdeki hedef instance → INFO | Port çakışması |
