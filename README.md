# Dark Side forum static archive

Статическое зеркало форума альянса **Dark Side** (EVE Online, `ds-alliance.ru`), сохранённое участником через Offline Explorer в апреле 2014.

Оригинальный движок: **Simple Machines Forum 2.0.4** + мод **TEA 1.3.1** (Temars EVE API).  
Это **не** бэкап сервера и **не** дамп MySQL — только HTML/статика, пригодная для раздачи через nginx.

## Что лежит в git, а что нет

GitHub не подходит для выкладки ~6 ГБ исходников и ~6 ГБ очищенного сайта целиком в git.

| В репозитории | Вне git (GitHub Releases / своё хранилище) |
|---|---|
| Скрипты сборки (`scripts/`) | Исходные `.rar` / `.zip` Offline Explorer |
| Конфиг nginx (`nginx/`) | Очищенный сайт `work/site/` (чанки `*.tar.zst.part*`) |
| Документация | `SHA256SUMS` к релизным томам |

Лимиты GitHub, из‑за которых так сделано:

- файл в git **>100 МБ** — отказ (warning с 50 МБ);
- артефакт **Release** — до **2 ГиБ** на файл → режем на части ~1800 МиБ;
- квота LFS/пакета маленькая относительно архива → LFS не используем по умолчанию.

## Быстрый старт (хост с nginx)

```bash
git clone https://github.com/Z1zi/ds-forum-archive.git
cd ds-forum-archive

# 1) Скачать тома данных с Releases и склеить
mkdir -p work && cd work
# подставьте URL ассетов релиза, например:
# gh release download <tag> -D dist -R Z1zi/ds-forum-archive
cd dist
cat ds-forum-static.tar.zst.part* > ds-forum-static.tar.zst
sha256sum -c SHA256SUMS
zstd -d ds-forum-static.tar.zst
mkdir -p /var/www/ds-forum-archive
tar -xf ds-forum-static.tar -C /var/www/ds-forum-archive

# 2) nginx
sudo cp nginx/archive.conf /etc/nginx/sites-available/ds-forum-archive.conf
# поправьте server_name и root при необходимости
sudo ln -sf /etc/nginx/sites-available/ds-forum-archive.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Открыть: `http://archive.example.com/` → редирект на главную `default.htm`.

## Сборка сайта из исходных архивов Offline Explorer

Нужны локально `DarkSide_forum-001.rar` и опционально `drive-download-*.zip`.

```bash
export DATA_DIR=/path/to/folder/with/rar   # по умолчанию — родитель репозитория
./scripts/extract.sh
python3 scripts/clean_static.py \
  --src "${DATA_DIR:-..}/work/raw/Offline Explorer/download" \
  --dst "${DATA_DIR:-..}/work/site" \
  --stats "${DATA_DIR:-..}/work/site-stats.json"
./scripts/pack_release.sh   # → work/dist/*.part* для gh release
```

Пути: скрипты ожидают дерево данных рядом с клоном:

```
parent/
  DarkSide_forum-001.rar
  work/raw/ …
  work/site/ …
  ds-forum-archive/   ← этот git-репозиторий
```

Либо задайте `DATA_DIR` / `OUT` / `SITE` / `DIST` явно (см. скрипты).

## Что делает очистка

- сохраняет раскладку хостов Offline Explorer (`ds-alliance.ru/forum/…`, `i.imgur.com/…`, …), чтобы относительные `../../cdn/...` продолжали работать;
- склеивает каталоги перезаписи `%&OvrN` / `_&OvrN` (побеждает более полный/поздний файл);
- выбрасывает шум: `markasread`, `emailuser`, `collapse`, `wap`/`wap2`, session-токены в именах, метаданные `Descr.WD3`;
- **удаляет** страницы с `login2` / `hash_passwrd` (секреты бота сохранения);
- правит в HTML ссылки `*.css@fin20` → `*.css`, обрезает session-хвосты в `href`;
- точка входа: `ds-alliance.ru/forum/default.htm` (оригинальная главная SMF).

Статистика последнего прогона см. `work/site-stats.json` (локально, не в git).

## Известные ограничения (потери неизбежны)

1. Нет живого SMF: нельзя логиниться, отвечать, искать по движку, листать «как на сервере» через PHP.
2. Часть картинок/вложений вела на внешние хосты; что не попало в Offline-дамп — будет 404.
3. Закрытые разделы, которых не видел аккаунт `history_bot`, в архиве отсутствуют.
4. Имена файлов с `@`, `;`, `=` — норма для этого зеркала; nginx отдаёт их как есть.
5. Кодировка страниц в основном **windows-1251** (`charset` в nginx уже выставлен).
6. Дубли пагинации/сортировок частично отфильтрованы; редкие «дыры» в середине длинных тем возможны.
7. Это музейный срез ~2014, не актуальный форум альянса.

Подробнее: [docs/LIMITATIONS.md](docs/LIMITATIONS.md).

## Публикация релиза данных

```bash
./scripts/pack_release.sh
gh release create v1.0.0 work/dist/* \
  --title "Static site data v1.0.0" \
  --notes "Cleaned Offline Explorer mirror for nginx. See README."
```

В git пушьте только код и документацию — не `work/`, не исходные rar/zip.

## Лицензии и этика

Контент форума принадлежит авторам постов и альянсу Dark Side. Репозиторий — техническая обвязка для сохранения истории.  
SMF © Simple Machines; TEA © авторы мода. Не публикуйте в Releases сырой проект Offline Explorer (`WebDown.dat` и т.п.) — там бывают cookies/хеши.
