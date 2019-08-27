#!/bin/bash

export FQDN
export DOMAIN
export VMAILUID
export VMAILGID
export VMAIL_SUBDIR

export DBDRIVER
export DBHOST
export DBPORT
export DBNAME
export DBUSER

export REDIS_HOST
export REDIS_PORT
export REDIS_PASS
export REDIS_NUMB

export DISABLE_CLAMAV
export DISABLE_DNS_RESOLVER
export DISABLE_MARIADB_HOSTNAME
export DISABLE_REDISDB_HOSTNAME
export ALLOW_PLAINTEXT_AUTH
export RECIPIENT_DELIMITER
export FETCHMAIL_INTERVAL
export RELAY_NETWORKS
export PASSWORD_SCHEME
export ALWAYS_BCC

FQDN=${FQDN:-$(hostname --fqdn)}
DOMAIN=${DOMAIN:-$(hostname --domain)}
VMAILUID=${VMAILUID:-1024}
VMAILGID=${VMAILGID:-1024}
VMAIL_SUBDIR=${VMAIL_SUBDIR:-"mail"}

DBDRIVER=${DBDRIVER:-mysql}
DBHOST=${DBHOST:-mariadb}
DBNAME=${DBNAME:-postfix}
DBUSER=${DBUSER:-postfix}

if [ "$DBDRIVER" = "ldap" ]; then
  DBPORT=${DBPORT:-389}
else
  DBPORT=${DBPORT:-3306}
fi

REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_PASS=$([ -f "$REDIS_PASS" ] && cat "$REDIS_PASS" || echo "${REDIS_PASS:-}")
REDIS_NUMB=${REDIS_NUMB:-0}
RSPAMD_PASSWORD=$([ -f "$RSPAMD_PASSWORD" ] && cat "$RSPAMD_PASSWORD" || echo "${RSPAMD_PASSWORD:-}")
WHITELIST_SPAM_ADDRESSES=${WHITELIST_SPAM_ADDRESSES:-}
DISABLE_RSPAMD_MODULE=${DISABLE_RSPAMD_MODULE:-}
DISABLE_SIEVE=${DISABLE_SIEVE:-false}
DISABLE_SIGNING=${DISABLE_SIGNING:-false}
DISABLE_GREYLISTING=${DISABLE_GREYLISTING:-false}
DISABLE_RATELIMITING=${DISABLE_RATELIMITING:-true}
DISABLE_MARIADB_HOSTNAME=${DISABLE_MARIADB_HOSTNAME:-false}
DISABLE_REDISDB_HOSTNAME=${DISABLE_REDISDB_HOSTNAME:-false}
ALLOW_PLAINTEXT_AUTH=${ALLOW_PLAINTEXT_AUTH:-false}
ENABLE_POP3=${ENABLE_POP3:-false}
ENABLE_FETCHMAIL=${ENABLE_FETCHMAIL:-false}
ENABLE_ENCRYPTION=${ENABLE_ENCRYPTION:-false}
TESTING=${TESTING:-false}
OPENDKIM_KEY_LENGTH=${OPENDKIM_KEY_LENGTH:-1024}
ADD_DOMAINS=${ADD_DOMAINS:-}
RECIPIENT_DELIMITER=${RECIPIENT_DELIMITER:-"+"}
FETCHMAIL_INTERVAL=${FETCHMAIL_INTERVAL:-10}
RELAY_NETWORKS=${RELAY_NETWORKS:-}
PASSWORD_SCHEME=${PASSWORD_SCHEME:-"SHA512-CRYPT"}
ALWAYS_BCC=$([ -f "${ALWAYS_BCC:-}" ] && cat "${ALWAYS_BCC:-}" || echo "${ALWAYS_BCC:-}")

DISABLE_CLAMAV=${DISABLE_CLAMAV:-false} # --
DISABLE_DNS_RESOLVER=${DISABLE_DNS_RESOLVER:-false} # --

if [ "$DBDRIVER" = "ldap" ]; then
  export LDAP_BIND
  export LDAP_BIND_DN
  export LDAP_BIND_PW

  LDAP_BIND=${LDAP_BIND:-true}
  LDAP_BIND_DN=${LDAP_BIND_DN:-}
  LDAP_BIND_PW=$([ -f "$LDAP_BIND_PW" ] && cat "$LDAP_BIND_PW" || echo "${LDAP_BIND_PW:-}")

  if [ "$LDAP_BIND" = true ]; then
    if [ -z "$LDAP_BIND_DN" ]; then
      echo "[ERROR] LDAP_BIND_ED must be set !"
      exit 1
    fi
    if [ -z "$LDAP_BIND_PW" ]; then
      echo "[ERROR] LDAP_BIND_PW must be set !"
      exit 1
    fi
  fi
else
  if [ -z "$DBPASS" ]; then
    echo "[ERROR] MariaDB/PostgreSQL database password must be set !"
    exit 1
  fi
fi

if [ -z "$RSPAMD_PASSWORD" ]; then
  echo "[ERROR] Rspamd password must be set !"
  exit 1
fi

if [ -z "$FQDN" ]; then
  echo "[ERROR] The fully qualified domain name must be set !"
  exit 1
fi

if [ -z "$DOMAIN" ]; then
  echo "[ERROR] The domain name must be set !"
  exit 1
fi

# https://github.com/docker-library/redis/issues/53
if [[ "$REDIS_PORT" =~ [^[:digit:]] ]]; then
  REDIS_PORT=6379
fi

# DATABASES HOSTNAME CHECKING
# We need to set these in the hosts file before Unbound takes over for DNS
# ---------------------------------------------------------------------------------------------

# Check mariadb/postgres hostname
if [ "$DISABLE_MARIADB_HOSTNAME" = false ]; then
  grep -q "${DBHOST}" /etc/hosts

  if [ $? -ne 0 ]; then
    echo "[INFO] MariaDB/PostgreSQL hostname not found in /etc/hosts"
    IP=$(dig A ${DBHOST} +short +search)
    if [ -n "$IP" ]; then
      echo "[INFO] Container IP found, adding a new record in /etc/hosts"
      echo "${IP} ${DBHOST}" >> /etc/hosts
    else
      echo "[ERROR] Container IP not found with embedded DNS server... Abort !"
      exit 1
    fi
  else
    echo "[ERROR] Container IP not found with embedded DNS server... Abort !"
    echo "[ERROR] Check your DBHOST environment variable"
    exit 1
  fi
fi

# Check redis hostname
if [ "$DISABLE_REDISDB_HOSTNAME" = false ]; then
  grep -q "${REDIS_HOST}" /etc/hosts

  if [ $? -ne 0 ]; then
    echo "[INFO] Redis hostname not found in /etc/hosts"
    IP=$(dig A ${REDIS_HOST} +short +search)
    if [ -n "$IP" ]; then
      echo "[INFO] Container IP found, adding a new record in /etc/hosts"
      echo "${IP} ${REDIS_HOST}" >> /etc/hosts
    else
      echo "[ERROR] Container IP not found with embedded DNS server... Abort !"
      exit 1
    fi
  else
    echo "[ERROR] Container IP not found with embedded DNS server... Abort !"
    echo "[ERROR] Check your REDIS_HOST environment variable"
    exit 1
  fi
fi

# SETUP CONFIG FILES
# ---------------------------------------------------------------------------------------------

certs_helper.sh update_certs

# Make sure that configuration is only run once
if [ ! -f "/etc/configuration_built" ]; then
  touch "/etc/configuration_built"
  setup.sh
fi

# Unrecoverable errors detection
if [ -f "/etc/setup-error" ]; then
  echo "[ERROR] One or more unrecoverable errors have occurred during initial setup. See above to find the cause."
  exit 1
fi

# LAUNCH ALL SERVICES
# ---------------------------------------------------------------------------------------------

echo "[INFO] Starting services"
exec s6-svscan /services
