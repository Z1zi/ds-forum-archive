# Как править сайт на вершине домена

Вершина домена (`https://example.org/`) — одна HTML-страница. Архив форума на неё не подключён: он открывается на отдельном имени, обычно `archive.example.org`.

Ниже все имена задаются переменными. Подставьте свои один раз в начале сессии терминала и дальше копируйте команды как есть.

```bash
export APEX_DOMAIN=example.org
export ARCHIVE_DOMAIN=archive.example.org
export APEX_ROOT=/var/www/apex-stub
export SSH_USER=deploy
export SSH_HOST=203.0.113.10
export SSH_PORT=22
export SSH_KEY=~/.ssh/id_ed25519
```

| Переменная | Что это |
|---|---|
| `APEX_DOMAIN` | имя, на котором открывается заглушка |
| `ARCHIVE_DOMAIN` | имя архива форума |
| `APEX_ROOT` | папка страницы на сервере |
| `SSH_USER` | пользователь SSH |
| `SSH_HOST` | адрес VDS |
| `SSH_PORT` | порт SSH |
| `SSH_KEY` | путь к приватному ключу на вашем компьютере |

Первый раз страница ставится скриптом на самом сервере (репозиторий уже склонирован):

```bash
APEX_DOMAIN="$APEX_DOMAIN" ARCHIVE_DOMAIN="$ARCHIVE_DOMAIN" APEX_ROOT="$APEX_ROOT" \
  ./scripts/deploy_apex.sh
```

Скрипт подставляет домены в [`nginx/apex-stub.conf`](../nginx/apex-stub.conf) и [`nginx/apex-stub.html`](../nginx/apex-stub.html), кладёт страницу в `$APEX_ROOT/index.html` и включает сайт `apex-stub`. Архив форума ставится отдельно: `DOMAIN="$ARCHIVE_DOMAIN" ./scripts/deploy_nginx.sh`.

Дальше текст меняют уже в файле на сервере. Повторный запуск `deploy_apex.sh` перезапишет `index.html` шаблоном из git.

## 1. Зайти на сервер

```bash
ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}"
```

Команды с `sudo` спросят пароль этого пользователя.

На сервере задайте те же `APEX_DOMAIN`, `ARCHIVE_DOMAIN` и `APEX_ROOT`, если открыли новый сеанс.

## 2. Открыть страницу

```bash
sudo nano "$APEX_ROOT/index.html"
```

Видимый текст — внизу файла, между `<h1>` и `<p>`:

```html
<h1>example.org</h1>
<p>Заглушка. Здесь нет архива форума.</p>
```

После `deploy_apex.sh` вместо `example.org` уже стоит ваш `APEX_DOMAIN`. Меняйте слова внутри тегов. `<h1>` — крупный заголовок, `<p>` — абзац под ним. Несколько абзацев — несколько тегов `<p>…</p>` подряд.

Ссылка на архив:

```html
<p><a href="https://archive.example.org/">Архив форума</a></p>
```

Вместо `archive.example.org` подставьте значение `ARCHIVE_DOMAIN`.

Цвет фона и текста — в блоке `<style>` вверху того же файла: `background` (фон) и `color` (текст). В шаблоне фон `#1c1f24`, текст `#f2f2f2`.

Сохранить в nano: `Ctrl+O`, Enter. Выйти: `Ctrl+X`.

Перезапускать nginx не нужно. Обновите страницу в браузере: `https://$APEX_DOMAIN/`. Если виден старый текст, обновите с очисткой кэша: `Ctrl+F5`.

## 3. Картинка

С вашего компьютера:

```bash
scp -i "$SSH_KEY" -P "$SSH_PORT" картинка.jpg "${SSH_USER}@${SSH_HOST}:/tmp/"
```

На сервере:

```bash
sudo mv /tmp/картинка.jpg "$APEX_ROOT/картинка.jpg"
sudo chmod 644 "$APEX_ROOT/картинка.jpg"
```

В `index.html` внутри `<main>`:

```html
<img src="/картинка.jpg" alt="описание">
```

Адрес картинки: `https://$APEX_DOMAIN/картинка.jpg`.

## 4. Вторая страница

Например «О сайте» по адресу `https://$APEX_DOMAIN/about.html`.

```bash
sudo nano "$APEX_ROOT/about.html"
```

Минимальный файл:

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <title>О сайте</title>
</head>
<body>
  <h1>О сайте</h1>
  <p>Текст страницы.</p>
  <p><a href="/">На главную</a></p>
</body>
</html>
```

С главной на неё:

```html
<p><a href="/about.html">О сайте</a></p>
```

Имя файла в папке и имя в ссылке должны совпадать.

## 5. Чего не менять

- Каталог архива (`WEBROOT`, по умолчанию `/var/www/ds-forum-archive/`). Его правка меняет сайт `ARCHIVE_DOMAIN`, не вершину домена.
- `/etc/nginx/sites-available/ds-forum-archive.conf` — конфиг архива.
- `/etc/letsencrypt/` — сертификаты. Без них `https://` перестанет открываться.
- В конфиге заглушки `/etc/nginx/sites-available/apex-stub.conf` строки `listen`, `ssl_certificate` и `server_name`. Их не переписывают, чтобы поменять абзац. Имя в `server_name` меняют только вместе со сменой DNS, через `APEX_DOMAIN=… ./scripts/deploy_apex.sh`, затем снова выпускают сертификат: `sudo certbot --nginx -d "$APEX_DOMAIN"`.

Сертификат для архива выпускается отдельно: `sudo certbot --nginx -d "$ARCHIVE_DOMAIN"`.
