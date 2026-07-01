#!/usr/bin/env sh
#
# Compile all MIBs and produce two summaries of every node:
#
#   mibs.oid          original net-snmp dump:   "label"   "1.3.6.1.2.1.1.1"
#   mibs-modules.oid  module-qualified version: MIB-MODULE::label<TAB>1.3.6...
#
# net-snmp has no bulk tree dump that emits the defining module, and resolving
# it per-node (snmptranslate -OS -IR) re-parses every MIB on each call, which is
# unusably slow. So for mibs-modules.oid we:
#   1. take the module qualifier from the MIB *sources* in a single awk pass, and
#   2. take the numeric OID from the mibs.oid dump,
# then join the two on the node's label.
#
# NOTE: written to work with both gawk and mawk (Debian/Ubuntu default), so it
# uses [ \t] rather than the [[:space:]] class, which mawk mishandles.

MIBDIRS=/usr/local/mibs/
OUT=mibs.oid
OUT_MOD=mibs-modules.oid

# Original, fast, single-process dump: node label -> numeric OID.
snmptranslate -M "$MIBDIRS" -m ALL -Pu -Tz > "$OUT"

# Stream all MIB sources, then a sentinel, then the dump, into one awk:
#   - `find -exec cat {} +` walks $MIBDIRS recursively (regular files only) and
#     batches them, so there's no shell argument-length limit to hit.
#   - while reading sources, build label -> module from each file's
#     "<NAME> DEFINITIONS ::= BEGIN" header and its object definitions.
#   - after the sentinel, emit each dump line joined with its module.
{
  find "$MIBDIRS" -type f -exec cat {} +
  printf '\037DUMP\037\n'
  cat "$OUT"
} | awk '
  { sub(/\r$/, "") }                    # tolerate CRLF line endings

  $0 == "\037DUMP\037" { dump = 1; next }

  # --- MIB source lines (before the sentinel) ---
  !dump {
    # module name: "<NAME> DEFINITIONS ::= BEGIN"
    if ($0 ~ /DEFINITIONS[ \t]*::=[ \t]*BEGIN/) {
      l = $0
      sub(/[ \t]*DEFINITIONS.*/, "", l)
      sub(/^[ \t]+/, "", l)
      n = split(l, a, /[ \t]+/)
      module = a[n]
      next
    }
    # object definition: "<name> <KEYWORD> ..." -> map the label to its module
    if (match($0, /^[ \t]*[A-Za-z0-9_-]+[ \t]+(OBJECT-TYPE|OBJECT[ \t]+IDENTIFIER|MODULE-IDENTITY|OBJECT-IDENTITY|OBJECT-GROUP|NOTIFICATION-TYPE|NOTIFICATION-GROUP|MODULE-COMPLIANCE|AGENT-CAPABILITIES|TRAP-TYPE)/)) {
      nm = $0
      sub(/^[ \t]+/, "", nm)
      split(nm, b, /[ \t]+/)
      if (module != "" && !(b[1] in map)) { map[b[1]] = module; nmap++ }
    }
    next
  }

  # --- the -Tz dump (after the sentinel) ---
  {
    line = $0
    gsub(/"/, "", line)                 # -Tz quotes both fields
    sub(/^[ \t]+/, "", line)
    nf = split(line, f, /[ \t]+/)
    name = f[1]; oid = f[nf]
    if (name == "" || oid == "") next
    ndump++
    if (name in map) { printf "%s::%s\t%s\n", map[name], name, oid; nhit++ }
    else               printf "%s\t%s\n",     name, oid
  }

  END {
    printf "mapped %d module labels; %d dump nodes, %d matched, %d fell back\n", \
           nmap, ndump, nhit, ndump - nhit > "/dev/stderr"
  }
' > "$OUT_MOD"
