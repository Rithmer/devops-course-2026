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
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
