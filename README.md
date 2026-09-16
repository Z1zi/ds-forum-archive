# Dark Side forum static archive

Статическое зеркало форума альянса **Dark Side** (EVE Online, `ds-alliance.ru`), сохранённое участником через Offline Explorer в апреле 2014.

Оригинальный движок: **Simple Machines Forum 2.0.4** + мод **TEA 1.3.1** (Temars EVE API).  
Это **не** бэкап сервера и **не** дамп MySQL — только HTML/статика под nginx.

Репозиторий **private**: https://github.com/Z1zi/ds-forum-archive

## Источник исходников (канон)

Всё сырьё лежит на Google Drive:

**[ds_forum_damps](https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy)**

| На Drive | Назначение |
|---|---|
| `DarkSide_forum.rar` (~2.54 ГБ) | Архив Offline Explorer (локально часто как `DarkSide_forum-001.rar`) |
| `Offline Explorer/` | Уже распакованный проект OE (если качали папку) |
| `ds-alliance.ru/` | Дерево хоста форума рядом с OE |

Скачивание папок через веб-интерфейс Drive часто даёт ZIP вида `drive-download-*.zip` — скрипты их тоже подхватывают.

Кладёте содержимое Drive в один каталог (`DATA_DIR`) рядом с клоном репозитория или указываете `DATA_DIR` явно.

## Что в git, а что нет

GitHub не тянет многогигабайтные дампы в git (лимит файла 100 МБ).

| В репозитории | Вне git |
|---|---|
| `scripts/`, `nginx/`, docs | Сырьё с [Google Drive](https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy) |
| README | Опционально: очищенный сайт в GitHub Release (`*.tar.zst.part*`) |

Release — удобный «готовый сайт» для хоста без пересборки. Сырьё для пересборки и канон истории файлов — **Drive**.

## Если уже всё скачано локально

Типичная раскладка после загрузки Drive (как на рабочей машине сборки):

```
DATA_DIR/                          # например …/Downloads/ds_forum
  DarkSide_forum-001.rar           # = DarkSide_forum.rar с Drive
  drive-download-*.zip             # опционально (выгрузки папок)
  Offline Explorer/                # если качали папку с Drive
  ds-alliance.ru/                  # если качали папку с Drive
  ds-forum-archive/                # git clone этого репо
  work/
    raw/                           # результат extract.sh
    site/                          # результат clean_static.py  ← document root
    dist/                          # чанки для gh release
```

Уже есть очищенный `work/site/` — можно сразу проверять и ставить в nginx (см. ниже). Пересобирать из RAR не обязательно.

### Локальная проверка без nginx

```bash
cd ds-forum-archive
export DATA_DIR=..                 # каталог, где лежит work/site
./scripts/serve_local.sh           # http://127.0.0.1:8765/
# главная: /ds-alliance.ru/forum/default.htm
```

Проверено на уже собранном `work/site`: главная, CSS темы и страница топика (`index.php@topic=10.0`) отдаются 200.

### Сборка с нуля из локального DATA_DIR

```bash
cd ds-forum-archive
export DATA_DIR=/path/to/ds_forum  # папка с rar / Offline Explorer / zip с Drive

./scripts/extract.sh               # → $DATA_DIR/work/raw/Offline Explorer/download
./scripts/build_site.sh            # → $DATA_DIR/work/site
./scripts/serve_local.sh           # быстрый смоук-тест
# по желанию:
./scripts/pack_release.sh          # → work/dist для private Release
```

`extract.sh` выбирает источник: готовый `Offline Explorer/download` → папка `ds-alliance.ru` → RAR.  
ZIP `drive-download-*.zip` по умолчанию **не** мержатся (много шума); включить: `MERGE_DRIVE_ZIP=1 ./scripts/extract.sh`.

## Развёртывание на хосте (nginx)

### Вариант A — из уже собранного `work/site` (этот компьютер)

```bash
sudo mkdir -p /var/www/ds-forum-archive
sudo rsync -a --delete "$DATA_DIR/work/site/" /var/www/ds-forum-archive/
sudo cp nginx/archive.conf /etc/nginx/sites-available/ds-forum-archive.conf
# поправьте server_name и root
sudo ln -sf /etc/nginx/sites-available/ds-forum-archive.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### Вариант B — с private GitHub Release (готовые чанки)

```bash
gh auth login   # доступ к private repo
gh release download v1.0.0 -R Z1zi/ds-forum-archive -D dist
cd dist
cat ds-forum-static.tar.zst.part* > ds-forum-static.tar.zst
sha256sum -c SHA256SUMS
zstd -d ds-forum-static.tar.zst
sudo mkdir -p /var/www/ds-forum-archive
sudo tar -xf ds-forum-static.tar -C /var/www/ds-forum-archive
# далее nginx как в варианте A
```

Открыть сайт → редирект на `/ds-alliance.ru/forum/default.htm`.

## Что делает очистка

- сохраняет раскладку хостов OE (`ds-alliance.ru/forum/…`, `i.imgur.com/…`, …), чтобы `../../cdn/...` работали;
- склеивает `%&OvrN` / `_&OvrN`;
- выбрасывает markasread / wap / session-имена / `Descr.WD3`;
- **удаляет** `login2` / `hash_passwrd`;
- правит `@fin20` и session-хвосты в HTML;
- вход: `ds-alliance.ru/forum/default.htm`.

## Известные ограничения

1. Нет живого SMF (логин, ответы, серверный поиск).
2. Внешние картинки — только то, что попало в дамп OE.
3. Закрытые борды вне ACL `history_bot` отсутствуют.
4. Имена с `@`, `;`, `=` — норма; nginx отдаёт как файлы.
5. Кодировка в основном **windows-1251**.
6. Музейный срез ~2014.

Подробнее: [docs/LIMITATIONS.md](docs/LIMITATIONS.md).

## Публикация / обновление private Release

```bash
./scripts/pack_release.sh
gh release create v1.0.1 "$DATA_DIR"/work/dist/* \
  -R Z1zi/ds-forum-archive \
  --title "Static site data v1.0.1" \
  --notes "Rebuild from Drive sources. See README."
```

В git — только код и документация. Сырой OE (`WebDown.dat` и т.п.) и rar/zip в git не пушить.

## Лицензии и этика

Контент — авторы постов и альянс Dark Side. Репозиторий — обвязка для сохранения истории.  
SMF © Simple Machines; TEA © авторы мода.
