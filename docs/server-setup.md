## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Имя | devops-vm |
| ОС | Ubuntu Server 24.04.5 LTS, ARM64, обычная установка |
| Оперативная память | 2048 МБ |
| Процессоры | 2 |
| Виртуальный диск | 25 ГБ, динамический |
| Разметка | LVM; корневая файловая система около 10,7 ГиБ, не весь диск выделен корню |

После установки выполнены `sudo apt update` и `sudo apt upgrade`. OpenSSH установлен при установке ОС. Машина сохраняется для следующих работ.

## 2. Сетевые интерфейсы

| Интерфейс | Режим | Адрес | Назначение |
| --- | --- | --- | --- |
| lo | Loopback | 127.0.0.1/8 | Локальные соединения |
| enp0s8 | NAT, адаптер 1 | 10.0.2.15/24 | Выход гостевой системы в интернет |
| enp0s9 | Host-only, адаптер 2, HostNetwork | 192.168.56.2/24 | Прямая связь с хостом |

Адрес хоста в Host-only: `192.168.56.1`. Адрес гостя получен по DHCP; после отката проверить его командой `ip -brief address`, при изменении обновить hosts. Тип виртуальных адаптеров — Intel PRO/1000.

На Mac в `/etc/hosts` добавлено:

```text
192.168.56.2 devops.local
```

На сервере hostname — `devops-vm`, строка `/etc/hosts`:

```text
127.0.1.1 devops-vm.devops.local devops-vm
```

Проверки: `hostname -f` на сервере возвращает `devops-vm.devops.local`; `ping -c 3 devops.local` и `ssh devops.local` на Mac работают.

## 3. Правило проброса портов

Правило адаптера 1 в VirtualBox: имя `ssh`, протокол TCP, IP хоста `127.0.0.1`, порт хоста `2222`, IP гостя пустой, порт гостя `2222`.

В состоянии `01-clean-install` гостевой SSH слушает **22**, поэтому перед восстановлением настроек вернуть гостевой порт правила на **22**. После усиления SSH изменить только гостевой порт на **2222**. Порт хоста всегда 2222.

## 4. Учётные записи

| Пользователь | UID | Права и назначение | Вход |
| --- | --- | --- | --- |
| student | 1000 | Первоначальная учётная запись, группа sudo | Консоль; после hardening не разрешён по SSH |
| devops | 1001 | Группы devops, sudo, users; администрирование | SSH по выделенному ключу |
| root | 0 | Системный администратор | Прямой вход по SSH запрещён |

Закрытый ключ находится только на Mac: `~/.ssh/devops_vm`; открытый — `~/.ssh/devops_vm.pub`. Тип — Ed25519. На сервере открытый ключ установлен в `/home/devops/.ssh/authorized_keys`; владелец каталога и файла — devops, права соответственно 700 и 600. Пароль devops нужен для sudo, но SSH-парольная аутентификация отключена.

Конфигурация `~/.ssh/config` на Mac, права 600:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` не изменён; резервная копия — `/etc/ssh/sshd_config.backup`. Настройки находятся в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```sshconfig
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована конфликтующая `PasswordAuthentication yes`. OpenSSH использует первое полученное значение; одного файла 99-hardening.conf недостаточно при наличии более раннего значения.

Отключена socket activation: `ssh.socket` остановлен и выключен; `ssh.service` включён. Служба слушает `0.0.0.0:2222` и `[::]:2222`.

Проверки на сервере:

```bash
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
sudo ss -tlnp | grep sshd
```

В новом **локальном** терминале Mac: `ssh devops` успешен; следующие попытки отклонены:

```bash
ssh -i ~/.ssh/devops_vm -p 2222 root@127.0.0.1
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
```

Обе могут возвращать `Permission denied (publickey)`. Журнал раскрывает причину отказа root: пользователь не перечислен в AllowUsers. Для devops отключение PubkeyAuthentication оставляет клиента без разрешённого метода.

## 6. Правила межсетевого экрана

UFW активен и запускается при загрузке. Политики: deny incoming, allow outgoing, disabled routed. Logging: on (medium).

| Порт TCP | Действие | Назначение |
| --- | --- | --- |
| 2222 | LIMIT IN | SSH с ограничением частоты |
| 80 | ALLOW IN | HTTP для следующей практики |
| 443 | ALLOW IN | HTTPS |

Правила существуют для IPv4 и IPv6, источник Anywhere. Перед включением UFW созданы разрешения на 2222, 80 и 443. После проверки нового соединения правило SSH заменено на LIMIT:

```bash
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

На Mac проверен закрытый порт:

```bash
curl --noproxy '*' -m 3 http://192.168.56.2:8080
```

Запрос завершился по тайм-ауту. На сервере:

```bash
sudo grep 'UFW BLOCK' /var/log/ufw.log | grep 'DPT=8080' | tail -3
```

В записи: SRC=192.168.56.1 (Mac), DST=192.168.56.2 (VM), PROTO=TCP, DPT=8080 (порт назначения), IN=enp0s9. Пакет SYN заблокирован, так как разрешающего правила для 8080 нет.

## 7. Снимки состояния

Все моменты создания — 04.10.2026, московское время.

| Снимок | Время | Состояние |
| --- | --- | --- |
| 01-clean-install | 19:11 | Установлена и обновлена ОС, два адаптера, SSH на 22 |
| 02-keys-configured | 19:35 | Создан devops, установлен ключ, работает ssh devops |
| 03-ssh-hardened | 19:44 | SSH на 2222, root и парольный вход запрещены; до настройки UFW |

### Восстановление после отката на 01-clean-install

Подготовить на Mac существующий ключ `~/.ssh/devops_vm` и этот репозиторий. Восстановление не требует новой установки или apt upgrade. Снимок возвращает гостевую ОС; отдельно проверить правило NAT и конфигурацию клиента на Mac.

1. В VirtualBox восстановить 01-clean-install. Проверить NAT и Host-only, временно установить гостевой порт NAT-правила в 22. Запустить VM. Подключиться с Mac:

   ```bash
   ssh -p 2222 student@127.0.0.1
   ```

2. В сессии student создать администратора (пароль задаётся вручную):

   ```bash
   sudo adduser devops
   sudo usermod -aG sudo,users devops
   ```

3. На Mac, из корня репозитория, установить существующий открытый ключ и передать скрипт аудита:

   ```bash
   ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
   ssh devops 'chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; mkdir -p ~/scripts'
   scp -P 2222 -i ~/.ssh/devops_vm scripts/audit.sh devops@127.0.0.1:~/scripts/
   ssh devops
   ```

   Убедиться, что вход по ключу не запрашивает пароль учётной записи. При необходимости восстановить два блока ~/.ssh/config из раздела 4. Эту сессию сохранить открытой.

4. В сессии devops подготовить hardening и перевести службу на 2222:

   ```bash
   sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
   sudo cp /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/50-cloud-init.conf.backup
   sudo sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]]\+yes[[:space:]]*$/# PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
   sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'CONF'
   Port 2222
   PermitRootLogin no
   PasswordAuthentication no
   PubkeyAuthentication yes
   PermitEmptyPasswords no
   MaxAuthTries 3
   LoginGraceTime 30
   AllowUsers devops
   X11Forwarding no
   ClientAliveInterval 300
   ClientAliveCountMax 2
   CONF
   sudo /usr/sbin/sshd -t
   sudo /usr/sbin/sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
   sudo systemctl disable --now ssh.socket
   sudo systemctl enable --now ssh.service
   sudo systemctl restart ssh
   sudo ss -tlnp | grep sshd
   ```

   В VirtualBox изменить гостевой порт NAT-правила на 2222. Открыть новый терминал Mac и проверить `ssh devops`; только после успеха продолжать.

5. На сервере включить UFW:

   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 2222/tcp comment 'SSH'
   sudo ufw allow 80/tcp comment 'HTTP'
   sudo ufw allow 443/tcp comment 'HTTPS'
   sudo ufw enable
   ```

   Снова проверить `ssh devops` из нового терминала Mac. Затем выполнить команды замены ALLOW на LIMIT и logging из раздела 6.

6. На сервере задать FQDN:

   ```bash
   sudo hostnamectl set-hostname devops-vm
   sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
   hostname -f
   ip -brief address
   ```

   На Mac проверить запись devops.local в /etc/hosts. Если её нет, добавить фактический Host-only IP командой `sudo nano /etc/hosts`. Не дублировать имеющуюся запись.

7. Проверить итог:

   ```bash
   bash ~/scripts/audit.sh; echo "exit=$?"
   sudo ufw status verbose
   ```

   Ожидаются 6 успешных проверок, 0 ошибок, exit=0, LIMIT для 2222. На Mac проверить `ssh devops.local` и две отрицательные попытки из раздела 5.

   Для требуемого отрицательного теста аудита временно изменить конфигурацию на диске без перезапуска SSH:

   ```bash
   sudo sed -i 's/^MaxAuthTries 3$/MaxAuthTries 10/' /etc/ssh/sshd_config.d/99-hardening.conf
   bash ~/scripts/audit.sh; echo "exit=$?"
   sudo sed -i 's/^MaxAuthTries 10$/MaxAuthTries 3/' /etc/ssh/sshd_config.d/99-hardening.conf
   sudo /usr/sbin/sshd -t
   bash ~/scripts/audit.sh; echo "exit=$?"
   ```

   Ожидается exit=1 при MaxAuthTries 10 и exit=0 после возврата 3. Обязательно вернуть значение 3.

Аудит проверяет конфигурацию на диске и UFW; доступность нового SSH-соединения и фактический слушающий порт проверяются отдельно.
