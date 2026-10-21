#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
sudo -v || exit 1
SSH_CONFIG=$(sudo /usr/sbin/sshd -T) || exit 1
UFW_STATUS=$(sudo ufw status verbose) || exit 1
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(awk '$1=="permitrootlogin"{print $2}' <<< "$SSH_CONFIG")"
check "Парольная аутентификация отключена" "no" "$(awk '$1=="passwordauthentication"{print $2}' <<< "$SSH_CONFIG")"
PORTS=$(awk '$1=="port"{print $2}' <<< "$SSH_CONFIG")
NONSTANDARD=no
if [[ -n "$PORTS" ]] && ! grep -qx '22' <<< "$PORTS"; then NONSTANDARD=yes; fi
check "SSH использует порт, отличный от 22" "yes" "$NONSTANDARD"
check "MaxAuthTries равно 3" "3" "$(awk '$1=="maxauthtries"{print $2}' <<< "$SSH_CONFIG")"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(awk '/^Status:/{print $2}' <<< "$UFW_STATUS")"
check "Входящие соединения по умолчанию запрещены" "deny" "$(sed -nE 's/^Default: ([^ ]+) \(incoming\).*/\1/p' <<< "$UFW_STATUS")"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
NGINX_ACTIVE=no
if systemctl is-active --quiet nginx; then NGINX_ACTIVE=yes; fi
check "Служба Nginx активна" "yes" "$NGINX_ACTIVE"
NGINX_CONFIG_OK=no
if sudo nginx -t >/dev/null 2>&1; then NGINX_CONFIG_OK=yes; fi
check "Конфигурация Nginx синтаксически корректна" "yes" "$NGINX_CONFIG_OK"
CERT_VALID=no
if sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend 2592000 -noout >/dev/null 2>&1; then CERT_VALID=yes; fi
check "Сертификат действует ещё не менее 30 дней" "yes" "$CERT_VALID"
WORLD_WRITABLE=no
if sudo find /var/www/devops-site -type f -perm -0002 -print -quit 2>/dev/null | grep -q .; then WORLD_WRITABLE=yes; fi
KEY_MODE_OWNER=$(sudo stat -c '%a,%U' /etc/ssl/private/devops.key 2>/dev/null || true)
WEB_PERMISSIONS=clear
[[ "$WORLD_WRITABLE" == yes ]] && WEB_PERMISSIONS=world-writable
check "Нет записи для всех; ключ root:600" "clear,600,root" "$WEB_PERMISSIONS,$KEY_MODE_OWNER"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
