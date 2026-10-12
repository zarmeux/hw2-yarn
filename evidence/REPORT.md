# YARN: результаты проверки

Стенд team-34, 11.10.2026. Последняя проверка состояния — 20:14 МСК. В машинных отчётах время указано в UTC.

| Проверка | Результат |
|---|---|
| ResourceManager, JobHistory, три NodeManager, nginx | active / enabled |
| NodeManager RUNNING / lost / unhealthy | 3 / 0 / 0 |
| Ресурс YARN | 5120 MiB / 5 vcore |
| Два WordCount | FINISHED / SUCCEEDED, завершены map и reduce |
| Результат | cluster=1, hadoop=2, yarn=2 |
| JobHistory и агрегированные логи | доступны, агрегирование SUCCEEDED |
| Десять интерфейсов через SSH с внешнего компьютера | GET 200 |
| HTTPS со стороны edge | GET 200 с паролем, 401 без пароля, PUT 403 |
| Прямой HTTPS с внешнего компьютера | тайм-аут на десяти портах |
| HDFS после установки YARN | три DataNode, fsck HEALTHY |

Приложения: `application_1791736103627_0001`, `application_1791736103627_0002`. Результат второй проверки хранится в `/user/yarn/hw2-check-20261011T163126Z-8104/output`.

- [review.txt](review.txt) — свежая проверка действующих служб, существующего задания и интерфейсов, `REVIEW_OK`.
- [verification.txt](verification.txt) — запуск WordCount и проверки nginx, `VERIFY_OK`.
- [wordcount-result.txt](wordcount-result.txt) — фактический результат подсчёта.
- [yarn-nodes.json](yarn-nodes.json), [yarn-applications.json](yarn-applications.json), [job-history.json](job-history.json) — REST-снимки.
- [ssh-tunnel-check.txt](ssh-tunnel-check.txt) — десять интерфейсов с внешнего компьютера.
- [direct-public-check.json](direct-public-check.json) — отдельная проверка прямых HTTPS-портов.
- [hdfs-fsck.txt](hdfs-fsck.txt) — целостность HDFS.
- [yarn-nodes.png](yarn-nodes.png), [job-history.png](job-history.png) — интерфейсы через SSH.

Прямая публикация HTTPS не подтверждена. nginx слушает нужные порты, UFW на edge не активен; предполагаемый блок — облачные сетевые правила. Для просмотра доступен SSH-туннель через порт 22.

Повторное развёртывание сохранило HDFS, веб-пароль и сертификат. ERROR-сообщения о SIGTERM и InterruptedException в старых логах относятся к штатному перезапуску; последующие задания завершились успешно.
