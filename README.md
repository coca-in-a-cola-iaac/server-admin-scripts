# admin-utils

Идемпотентный бутстрап новых VPS (Debian 12 / Ubuntu 22.04+).
Порядок строгий, номера — не для красоты:

```bash
# как root на новом сервере:
git clone <repo-url> && cd admin-utils
export TYLER_SSH_KEY="$(cat /path/to/your/agent_key.pub)"
bash scripts/new-server.sh            # one-shot: 10..50 + gate
# либо по шагам:
bash scripts/10-user.sh        # юзер tyler + sudo + ключ
bash scripts/20-sshd.sh        # key-only auth, drop-in config, rollback-guard
bash scripts/30-ufw.sh         # deny incoming; SSH-порт авто-детект; EXTRA_PORTS="8443 ..." для стейджа
bash scripts/40-fail2ban.sh    # sshd jail, bantime.increment до 1w
bash scripts/50-basics.sh      # unattended-upgrades, TZ, journald 200M cap, swappiness, autoclean
bash scripts/90-verify.sh      # гейт: все проверки, exit != 0 если что-то красное
```

Все скрипты можно гонять повторно — состояние не дублируется.

## Гарантии безопасности
- `10-user.sh`: отказывается работать без `TYLER_SSH_KEY` (не прописываем чужой/зашитый ключ).
- `20-sshd.sh`: перед рестартом `sshd -t`, после — проверка что сервис жив; иначе rollback. Отказ работать, если у root И tyler нет authorized_keys (не отрубаем себе руки).
- `30-ufw.sh`: SSH-порт определяется из фактического листенера (`ss`), не из догадок; добавляется правилом до enable.
- sudoers пишется только через валидацию `visudo -cf` временного файла.

## Переменные
| env | где | по умолчанию |
|---|---|---|
| `TYLER_SSH_KEY` | 10-user | — (обязательна: публичный ключ агента) |
| `TYLER_USER` | 10-user | `tyler` |
| `TYLER_GROUPS` | 10-user | — (напр. `docker`) |
| `OWNER_USERS` | 20-sshd | `root` (кому оставляем парольный вход; напр. `"root alice"`) |
| `EXTRA_PORTS` | 30-ufw | — (напр. `"8443 20085"`) |

## После прогона
1. Сверить `90-verify.sh` → ALL GREEN.
2. Открыть Tyler-сессию и проверить `sudo -n true`.
3. Только потом отключать root-сессию / харднить root по желанию.
