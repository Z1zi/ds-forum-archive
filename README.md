# Dark Side forum static archive

Статическое зеркало форума альянса **Dark Side** (EVE Online, `ds-alliance.ru`), Offline Explorer, апрель 2014.

Движок оригинала: **SMF 2.0.4** + **TEA 1.3.1**. Это HTML-статика под nginx, не дамп MySQL.

- Репозиторий: https://github.com/Z1zi/ds-forum-archive  
- Сырьё (канон): [Google Drive — ds_forum_damps](https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy)

Готовая ссылка всегда такого вида:

```text
http://<хост>/ds-alliance.ru/forum/default.htm
```

Скрипты в конце выводят блок `ARCHIVE READY` с этим URL.

---

## Быстрый старт (выберите один путь)

Нужны: `git`, `gh` (для Release), на VDS ещё `nginx`, `rsync`, `curl`, `zstd`.

### 1) Локально — уже есть `work/site` (без nginx)

```bash
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive
# DATA_DIR = каталог, где лежит work/site (рядом с клоном или ваш путь)
export DATA_DIR=/home/fz/Downloads/ds_forum   # ← поправьте под себя

./scripts/serve_local.sh
# в консоли будет:
#   ARCHIVE READY
#   http://127.0.0.1:8765/ds-alliance.ru/forum/default.htm
```

Открыть в браузере именно эту строку.

Чтобы слушать на всех интерфейсах (доступ с телефона в LAN):

```bash
BIND=0.0.0.0 PORT=8765 ./scripts/serve_local.sh
# URL в консоли будет с 0.0.0.0 — замените на IP машины, например:
# http://192.168.1.10:8765/ds-alliance.ru/forum/default.htm
```

### 2) VDS / хост — готовые чанки с GitHub Release + nginx

Один проход: скачать → распаковать → nginx → печать ссылки.

```bash
sudo apt-get update
sudo apt-get install -y nginx rsync curl zstd git
# GitHub CLI: https://github.com/cli/cli#installation
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive

# домен VDS или оставьте _ (тогда в ссылке будет IP сервера)
export DOMAIN=archive.example.com    # ← ваш домен или IP, либо _
export TAG=v1.0.0

./scripts/install_from_release.sh
# в консоли будет:
#   ARCHIVE READY
#   http://archive.example.com/ds-alliance.ru/forum/default.htm
#   (или http://<IP>/ds-alliance.ru/forum/default.htm если DOMAIN=_)
```

A-запись домена должна смотреть на этот VDS. Порт 80 открыт в firewall (`ufw allow 80/tcp`).

### 3) VDS / хост — сайт уже собран в `work/site` (rsync + nginx)

```bash
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive

export DATA_DIR=/path/to/ds_forum          # там есть work/site
export DOMAIN=archive.example.com          # или _ для IP
# export SITE=$DATA_DIR/work/site          # по умолчанию так и есть

./scripts/deploy_nginx.sh
#   ARCHIVE READY
#   http://archive.example.com/ds-alliance.ru/forum/default.htm
```

### 4) Сборка с нуля из Drive, потом локальный линк

Скачайте с [Drive](https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy) в `$DATA_DIR`:  
`DarkSide_forum.rar` (или `DarkSide_forum-001.rar`), опционально папки `Offline Explorer/`, `ds-alliance.ru/`.

```bash
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive
export DATA_DIR=/path/to/folder/with/drive/files

./scripts/extract.sh
./scripts/build_site.sh
./scripts/serve_local.sh
#   ARCHIVE READY
#   http://127.0.0.1:8765/ds-alliance.ru/forum/default.htm
```

На nginx после сборки: `DOMAIN=… ./scripts/deploy_nginx.sh`.

---

## Параллельно с современным форумом

Архив — **музейный read-only срез**. Новый движок (XenForo, Discourse, Flarum, свежий SMF и т.п.) ставьте отдельно и **не** пытайтесь импортировать HTML как живую БД в первый день.

Рекомендуемая схема — **два vhost на одном VDS**:

| Роль | URL | Содержимое |
|---|---|---|
| Живой форум | `https://forum.example.com/` | современный движок |
| История DS 2014 | `https://history.example.com/` | этот статический архив |

Почему поддомен, а не `/archive` на том же сайте: у зеркала OE относительные пути вида `../../i.imgur.com/…`. Им нужен свой document root (как после `deploy_nginx.sh`), иначе картинки и соседние хосты ломаются.

### Пример развёртывания на VDS

```bash
# 0) DNS: forum.example.com и history.example.com → IP VDS

# 1) Живой форум — как обычно для выбранного движка
#    (документация XenForo / Discourse / …). Ниже только архив.

# 2) Архив на поддомене history
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive
export DOMAIN=history.example.com
export TAG=v1.0.0
./scripts/install_from_release.sh
#   ARCHIVE READY
#   http://history.example.com/ds-alliance.ru/forum/default.htm

# 3) Подключить пример двух server{} (живой форум — заглушка/ваш сниппет)
sudo cp nginx/parallel-with-live-forum.conf \
  /etc/nginx/sites-available/ds-parallel.conf
# поправьте server_name и блок forum.example.com под свой движок
sudo ln -sfn /etc/nginx/sites-available/ds-parallel.conf \
  /etc/nginx/sites-enabled/ds-parallel.conf
sudo nginx -t && sudo systemctl reload nginx

# 4) TLS (после того как оба A-записи отвечают)
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d forum.example.com -d history.example.com

echo "LIVE:    https://forum.example.com/"
echo "HISTORY: https://history.example.com/ds-alliance.ru/forum/default.htm"
```

Готовый сниппет: [`nginx/parallel-with-live-forum.conf`](nginx/parallel-with-live-forum.conf).

### Связка в UI нового форума

В живом движке заведите read-only раздел или пункт меню, например «История Dark Side (2014)», со ссылкой:

```text
https://history.example.com/ds-alliance.ru/forum/default.htm
```

Старые треды в новом форуме **не продолжайте** — пишите в новых бордах; архив остаётся зафиксированным срезом.

### Чего не делать

- Не класть архив в `public/archive/` современного PHP-форума без отдельного `root`/`alias` на всё дерево хостов OE.
- Не смешивать пользователей/пароли старого SMF с новым движком (их в дампе нет).
- Не открывать запись в статике — только `GET`/`HEAD` (уже в конфиге архива).

---

## Что должно получиться

| Где | Команда | Линк в консоли |
|---|---|---|
| Ноутбук | `./scripts/serve_local.sh` | `http://127.0.0.1:8765/ds-alliance.ru/forum/default.htm` |
| VDS + Release | `./scripts/install_from_release.sh` | `http://<DOMAIN-или-IP>/ds-alliance.ru/forum/default.htm` |
| VDS + свой site | `./scripts/deploy_nginx.sh` | то же |
| Параллельно с новым форумом | `DOMAIN=history… ./scripts/install_from_release.sh` | `http://history.example.com/ds-alliance.ru/forum/default.htm` (+ живой `forum.example.com`) |

Проверка с другой машины:

```bash
curl -sI "http://<хост>/ds-alliance.ru/forum/default.htm" | head -3
# ожидание: HTTP/1.1 200
```

---

## Раскладка DATA_DIR

```
DATA_DIR/
  DarkSide_forum-001.rar     # = DarkSide_forum.rar с Drive
  Offline Explorer/          # если качали папку
  ds-alliance.ru/            # если качали папку
  ds-forum-archive/          # этот git clone
  work/site/                 # очищенный сайт = document root
```

| В git | Вне git |
|---|---|
| scripts, nginx, docs | [Drive](https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy) |
| | Release `*.tar.zst.part*` (готовый сайт) |

`drive-download-*.zip` по умолчанию не мержатся (`MERGE_DRIVE_ZIP=1` чтобы включить).

---

## Ограничения

Нет живого SMF; часть внешних картинок 404; закрытые борды вне `history_bot` отсутствуют; кодировка windows-1251; срез ~2014.  
Подробнее: [docs/LIMITATIONS.md](docs/LIMITATIONS.md).

---

## Обновить Release

Пересборка и публикация томов данных нужна только при **несовместимых изменениях артефакта**: иная раскладка document root, другой формат/нарезка `*.tar.zst.part*`, смена алгоритма `clean_static.py`, затрагивающая уже выложенный сайт, или замена канонического среза. Косметические правки README/nginx без влияния на содержимое `work/site` Release не требуют.

```bash
export DATA_DIR=/path/to/ds_forum
./scripts/pack_release.sh
gh release create v1.0.1 "$DATA_DIR"/work/dist/* -R Z1zi/ds-forum-archive \
  --title "Static site data v1.0.1" --notes "See README."
```

Не пушить в git rar/zip/`work/`/секреты OE (`WebDown.dat`, `hash_passwrd`).

## Лицензии

Контент — авторы постов и альянс Dark Side. SMF © Simple Machines; TEA © авторы мода.
