# ДЗ №2 — YARN и веб-интерфейсы кластера

На HDFS из [первого задания](https://github.com/zarmeux/hw1-hdfs) мы развернули YARN: ResourceManager, три NodeManager и MapReduce JobHistory. Для доступа к веб-интерфейсам настроили nginx на edge.

На выданном стенде все десять интерфейсов открываются с внешнего компьютера через SSH-туннель. Прямой HTTPS мы тоже настроили, но из внешней сети он пока не работает. Ниже описали оба способа и результаты проверок.

## Размещение служб

Мы использовали тот же стенд team-34: Ubuntu 24.04, OpenJDK 11 и Hadoop 3.4.2. Версия nginx — 1.24.0.

| Машина | IP | Службы YARN и публикации |
|---|---|---|
| team-34-en | 10.34.0.10 | ResourceManager, JobHistory, nginx |
| team-34-nn | 10.34.0.11 | NodeManager |
| team-34-00 | 10.34.0.12 | NodeManager |
| team-34-01 | 10.34.0.13 | NodeManager |

HDFS продолжает работать: SecondaryNameNode находится на edge, NameNode и один DataNode — на `team-34-nn`, ещё два DataNode — на остальных рабочих машинах.

## Установка и настройки

На edge из папки `/home/team/hw2-yarn`:

```bash
bash scripts/deploy.sh
```

Скрипт использует установленный в ДЗ №1 Hadoop, создаёт пользователя `yarn`, конфигурацию `/etc/hadoop-yarn` и systemd-службы. Затем готовит каталоги HDFS, запускает YARN и JobHistory, настраивает nginx и проверяет работу через WordCount. При успешном завершении выводит `VERIFY_OK` и `DEPLOY_OK`.

В `yarn-site.xml` мы задали адреса служб, ресурсы NodeManager, shuffle-сервис и агрегирование логов. В `mapred-site.xml` указали запуск MapReduce через YARN и адрес JobHistory. Конфигурацию HDFS в `/etc/hadoop` не меняем, NameNode не форматируем.

На машине с NameNode мы выделили контейнерам 1024 MiB и 1 vcore, на двух других — по 2048 MiB и 2 vcore. Всего получилось 5120 MiB и 5 vcore. Map, Reduce и ApplicationMaster используют по 512 MiB с heap 384 MiB. Проверка физической памяти включена; проверку виртуальной памяти мы отключили из-за резервирования адресного пространства JVM.

Web Application Proxy работает внутри ResourceManager по пути `/proxy/`. Отдельный Timeline Server мы не разворачивали.

Параметры стенда находятся в [cluster.env](cluster.env), подробная инструкция — в [INSTALL.md](INSTALL.md). Повторный deploy перезапускает YARN, поэтому его нужно выполнять без активных заданий.

## Проверка WordCount

Для проверки мы использовали такой входной файл:

```text
hadoop yarn hadoop
yarn cluster
```

Ожидаемый результат:

```text
cluster  1
hadoop   2
yarn     2
```

Два запуска 11.10.2026 завершились со статусами `FINISHED / SUCCEEDED`:

```text
application_1791736103627_0001
application_1791736103627_0002
```

12.10.2026 мы повторно развернули кластер и запустили ещё один WordCount — `application_1791817038776_0001`. Он тоже завершился успешно, результат совпал с ожидаемым. JobHistory сохранил историю задания, а агрегированные логи удалось прочитать через `yarn logs`.

![Задание WordCount в JobHistory](evidence/job-history.png)

ResourceManager видит три NodeManager в состоянии `RUNNING`, lost и unhealthy узлов нет. После повторной установки HDFS остался целым: три DataNode работают, полный `fsck` возвращает `HEALTHY`.

![Три работающих NodeManager](evidence/yarn-nodes.png)

Свежие результаты: [повторное развёртывание](evidence/redeploy-20261012.txt), [WordCount](evidence/wordcount-result-20261012.txt), [JobHistory](evidence/job-history-20261012.json) и [проверка HDFS](evidence/hdfs-fsck-20261012.txt).

## Доступ к веб-интерфейсам

Для каждого интерфейса мы настроили отдельный HTTPS-порт и отдельный локальный порт для SSH-туннеля.

| Интерфейс | HTTPS-порт на 111.88.130.214 | Адрес через SSH-туннель |
|---|---|---|
| ResourceManager | 8443 | http://127.0.0.1:18088/cluster/nodes |
| NameNode | 8444 | http://127.0.0.1:19870/dfshealth.html#tab-datanode |
| SecondaryNameNode | 8445 | http://127.0.0.1:19868/ |
| JobHistory | 8446 | http://127.0.0.1:19889/jobhistory |
| DataNode nn | 8451 | http://127.0.0.1:19864/ |
| DataNode 00 | 8452 | http://127.0.0.1:19865/ |
| DataNode 01 | 8453 | http://127.0.0.1:19866/ |
| NodeManager nn | 8461 | http://127.0.0.1:18042/ |
| NodeManager 00 | 8462 | http://127.0.0.1:18043/ |
| NodeManager 01 | 8463 | http://127.0.0.1:18044/ |

Для подключения с Linux/macOS сначала проверьте обычный SSH-вход, затем из папки репозитория запустите туннель:

```bash
ssh team@111.88.130.214
# После входа выйдите с ВМ командой exit.
bash scripts/connect-ui.sh
```

Оставьте терминал с туннелем открытым и перейдите по адресам из таблицы. Если нужен конкретный SSH-ключ, передайте его путь первым аргументом. Для Windows есть `scripts/connect-ui.ps1`; команды приведены в [INSTALL.md](INSTALL.md).

Мы проверили доступ с внешнего компьютера: все десять интерфейсов вернули HTTP 200, переход ResourceManager → JobHistory работает. Результат сохранён в [ssh-tunnel-check-20261012.json](evidence/ssh-tunnel-check-20261012.json).

### Исправление ссылок на DataNode

В интерфейсе NameNode ссылки на DataNode сначала вели на внутренние IP. Обычной замены адресов в nginx оказалось недостаточно: NameNode собирает эти ссылки в JavaScript из имени узла.

Мы добавили в `publish.py` отдельную версию `dfshealth.js` для каждого способа доступа. Файлы установленного Hadoop при этом не меняются. Теперь через туннель ссылки ведут на `127.0.0.1:19864–19866`, а для HTTPS — на внешний адрес и порты `8451–8453`.

Проверку ссылок включили в `verify.sh` и `review.sh`. Её также можно запустить отдельно при открытом туннеле:

```bash
python3 scripts/check-links.py
```

Ожидаемый результат — три `DATANODE_LINK_OK` и `LINKS_OK`. Ссылки мы дополнительно проверили в браузере: [результат](evidence/namenode-links-fixed.json).

![Исправленные ссылки NameNode на DataNode](evidence/namenode-links-fixed.jpg)

### Что пока не работает в прямом HTTPS

Для HTTPS мы настроили TLS 1.2/1.3, самоподписанный сертификат и Basic Auth. В nginx разрешены только GET/HEAD. Пароль и приватные ключи в репозиторий не входят.

При проверке внутри стенда все десять интерфейсов возвращают 200 с авторизацией, 401 без пароля и 403 для PUT. Однако с внешнего компьютера TCP-соединение устанавливается, а TLS-handshake завершается тайм-аутом: [внешняя проверка](evidence/direct-public-check-20261012.json).

Причину внешнего ограничения мы окончательно не установили. Доступ к панели управления сетью ВМ нам не выдали, поэтому для проверки сетевых правил понадобится помощь администратора стенда. Пока используем рабочий SSH-туннель и не считаем прямой HTTPS проверенным способом доступа.

## Файлы работы

- [INSTALL.md](INSTALL.md) — установка, управление и подключение к интерфейсам.
- [scripts/](scripts/) — автоматизация и проверки.
- [evidence/REPORT-final.md](evidence/REPORT-final.md) — итоговая проверка 12.10.2026.
- [evidence/review-20261012.txt](evidence/review-20261012.txt) — состояние служб, интерфейсов и ссылок, `REVIEW_OK`.
- [Условие задания](https://go.teachbase.ru/education/listener/course_player/sessions/1415858/tasks/412112).
