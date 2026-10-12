# Установка YARN и веб-интерфейсов

## Требования

Работающий HDFS из ДЗ №1: `/opt/hadoop`, Java 11, `/etc/hadoop` и пользователь `hadoop` на edge. Нужен доступ `team` с edge на внутренние узлы по SSH-ключу и `sudo` без пароля. Имена узлов должны разрешаться во внутренние IP.

## Запуск установки

Разместите содержимое ДЗ на edge в `/home/team/hw2-yarn`. В `cluster.env` задаются адреса edge, NameNode, SecondaryNameNode и трёх рабочих узлов, внешний адрес, внутренний SSH-ключ и рабочая папка. Локальные переопределения можно записать в `cluster.local.env`.

```bash
cd /home/team/hw2-yarn
bash scripts/deploy.sh
```

Скрипт создаёт пользователя `yarn`, отдельную конфигурацию `/etc/hadoop-yarn`, локальные каталоги и systemd-службы. В HDFS создаются `/user/yarn`, `/yarn-logs`, `/mr-history/tmp` и `/mr-history/done`. Затем запускаются YARN и JobHistory, настраивается nginx и выполняется WordCount. Ожидаемый итог — `VERIFY_OK`, затем `DEPLOY_OK`.

Повторный deploy перезапускает YARN, поэтому выполняйте его без активных заданий. Конфигурация и данные HDFS сохраняются; NameNode не форматируется. Пароль HTTPS и сертификат сохраняются. Для изменения существующего `PUBLIC_HOST` или `UI_USER` потребуется отдельно обновить реквизиты и сертификат. Чужие `/etc/hadoop-yarn` и `hw2.conf` скрипт не перезаписывает.

## Ресурсы и службы

На узле NameNode для контейнеров выделено 1024 MiB / 1 vcore, на двух других — по 2048 MiB / 2 vcore. Значения памяти заданы в `NN_WORKER_MEMORY_MB` и `WORKER_MEMORY_MB`. Heap ResourceManager — 512 MiB, NodeManager и JobHistory — 384 MiB. Map, Reduce и ApplicationMaster используют по 512 MiB памяти с heap 384 MiB. Проверка физической памяти включена; проверка виртуальной памяти отключена из-за резервирования адресного пространства JVM.

На edge работают `hadoop-resourcemanager`, `hadoop-historyserver` и nginx; на рабочих узлах — `hadoop-nodemanager`. Web Application Proxy встроен в ResourceManager. Timeline Server для этого решения не используется.

```bash
bash scripts/cluster.sh status
bash scripts/cluster.sh stop
bash scripts/cluster.sh start
```

Конфигурация: `/etc/hadoop-yarn`; локальные данные и состояние ResourceManager: `/var/lib/hadoop-yarn`; логи: `/var/log/hadoop-yarn`. При штатном restart Hadoop может писать SIGTERM и InterruptedException с уровнем ERROR; проверяйте, относятся ли они к остановке или к новому запуску.

## nginx и доступ

Для каждого интерфейса настроен отдельный порт HTTPS и отдельный порт на loopback для SSH-туннеля. nginx допускает GET/HEAD и переписывает внутренние ссылки на адреса соответствующего способа доступа. Таблица адресов приведена в [README](README.md). Проверенный внешний доступ на этом стенде выполняется через SSH-туннель; точные команды приведены ниже.

Для прямого доступа необходимо разрешить входящий TCP на edge: `8443–8446`, `8451–8453`, `8461–8463`. На 12.10.2026 TCP-соединения устанавливаются, но внешний TLS-handshake завершается тайм-аутом; установка nginx сама по себе не меняет облачные сетевые правила.

HTTPS использует TLS 1.2/1.3 и Basic Auth. Реквизиты: `/etc/nginx/hw2/access.json`; netrc: `/etc/nginx/hw2/access.netrc`; приватный TLS-ключ: `/etc/nginx/hw2/server.key`. Эти файлы не входят в репозиторий. Сертификат самоподписанный, с SAN внешнего IP. Для curl нужен публичный `/etc/nginx/hw2/server.crt`, полученный по проверенному SSH-каналу.

После открытия портов проверяйте с внешнего компьютера:

```bash
python3 scripts/check-public.py --host 111.88.130.214 --ca-cert server.crt --netrc-file access.netrc
curl --cacert server.crt --netrc-file access.netrc -L https://111.88.130.214:8443/
```

Проверка должна завершиться с кодом 0 и `all_ok=true`: на всех десяти портах нужны TCP OPEN, TLS VERIFIED, HTTP 200 с авторизацией и 401 без неё. Одного TCP OPEN недостаточно. HTTPS должен возвращать 200 с паролем, 401 без пароля и 403 для PUT. Повторите HTTPS-проверку для остальных портов. `review.sh` и `verify.sh` проверяют HTTPS на edge через приватный адрес; они не заменяют проверку из внешней сети.

## Скрипты проверки

`review.sh` проверяет уже запущенные службы, существующий WordCount и интерфейсы, не создавая задания. `verify.sh` запускает новое задание с уникальным HDFS-каталогом, сверяет результат, JobHistory и агрегированные логи. Тестовые каталоги сохраняются.

Туннель Windows принимает `-KeyPath`, `-Edge`, `-User` и `-KnownHostsFile`; при заданном known_hosts требует совпадения ключа сервера. В Linux/macOS адрес и пользователь берутся из `cluster.env`, приватный ключ можно передать аргументом; без него используются SSH-конфигурация и агент. Туннель привязан к `127.0.0.1`; при первом SSH-подключении сверяйте отпечаток сервера.

Документация: [Cluster Setup](https://hadoop.apache.org/docs/r3.4.2/hadoop-project-dist/hadoop-common/ClusterSetup.html), [Web Application Proxy](https://hadoop.apache.org/docs/r3.4.2/hadoop-yarn/hadoop-yarn-site/WebApplicationProxy.html), [nginx sub_filter](https://nginx.org/en/docs/http/ngx_http_sub_module.html).

## Доступ с внешнего компьютера через SSH

Сначала убедитесь, что обычное подключение работает, и проверьте отпечаток SSH-сервера:

```bash
ssh team@111.88.130.214
# После успешного входа выйдите из удалённой оболочки:
exit
```

На Linux/macOS скачайте репозиторий на свой компьютер и запустите:

```bash
git clone https://github.com/zarmeux/hw2-yarn.git
cd hw2-yarn
bash scripts/connect-ui.sh
# Если нужен явно указанный приватный ключ:
# bash scripts/connect-ui.sh /absolute/path/to/key
```

В Windows с установленным OpenSSH из папки репозитория:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\connect-ui.ps1
# При необходимости добавьте: -KeyPath C:\path\to\key
```

Оставьте терминал открытым. Откройте в браузере:

- ResourceManager: http://127.0.0.1:18088/cluster/nodes
- NameNode: http://127.0.0.1:19870/dfshealth.html#tab-datanode
- JobHistory: http://127.0.0.1:19889/jobhistory
- Все остальные интерфейсы — по таблице README.

Переходы на DataNode используют соответствующие адреса `127.0.0.1:19864–19866`, а не внутренние IP. Все десять локальных портов должны быть свободны: при конфликте SSH завершится с ошибкой. `Ctrl+C` закрывает туннель. HTTP существует только на локальной стороне туннеля; данные по сети передаются через зашифрованное SSH-соединение.

Проверка ссылок с компьютера, на котором открыт туннель:

```bash
python3 scripts/check-links.py
```

Ожидаются три `DATANODE_LINK_OK` и `LINKS_OK`. На edge эта проверка также включена в `review.sh` и `verify.sh`.

## Получение файлов для дополнительной HTTPS-проверки

На Linux/macOS с вашего компьютера:

```bash
umask 077
ssh team@111.88.130.214 'sudo -n cat /etc/nginx/hw2/server.crt' > server.crt
ssh team@111.88.130.214 'sudo -n cat /etc/nginx/hw2/access.netrc' > access.netrc
python3 scripts/check-public.py --host 111.88.130.214 --ca-cert server.crt --netrc-file access.netrc
```

`access.netrc` содержит пароль, исключён из Git и передаётся преподавателю только отдельно при необходимости. Приватный ключ TLS и SSH-ключи в репозитории отсутствуют. Если внешний TLS зависает, не отключайте проверку сертификата: это не исправляет сетевую проблему. Необходимо разрешение соответствующих входящих портов со стороны владельца инфраструктуры.
