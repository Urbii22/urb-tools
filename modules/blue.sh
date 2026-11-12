#!/usr/bin/env bash
# BLUE uses a local Python standard-library backend; the shell is shared with GOD.
[[ -n "${_URB_BLUE_LOADED:-}" ]] && return 0
_URB_BLUE_LOADED=1

blue_help() {
    cat <<'EOF'
urb blue — offline SOC workspace

  urb blue                          Open or reconnect to the BLUE shell
  urb blue --no-anim | --session | --check | --kill [--yes]
  urb blue status                   Workspace, events, alerts and cases
  urb blue workspace new|use <name> Create/select a workspace
  urb blue workspace list|status    List or inspect workspaces
  urb blue ingest windows|linux <file> [--tz UTC|+01:00] [--year YYYY]
  urb blue sources                  Source hashes and import quality
  urb blue events [--id 4625] [--user name] [--ip IP] [--since ISO] [--limit N]
  urb blue events show E-001        Full event and provenance
  urb blue detect rules|run [--threshold N] [--window seconds]
  urb blue alerts [show A-001|status A-001 <status>]
  urb blue cases new "title" | list | show C-001
  urb blue cases link C-001 --alert A-001
  urb blue cases note C-001 "text" | evidence C-001 <file>
  urb blue cases status C-001 <status> | close C-001

Windows CSV: Timestamp,EventID,Host,User,IP,Message (UTF-8).
Timezone-free timestamps require --tz for use in detection; legacy syslog
also requires --year. A rule match is not a confirmed incident.
EOF
}

blue_main() {
    case "${1:-}" in
        '') URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec bash "$URB_HOME/godmode/god.sh" --profile blue ;;
        --help|-h|help) blue_help ;;
        --no-anim|--kill|--check|--session)
            local opt="$1"; shift
            [[ "$opt" == --session ]] && opt=--status
            URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec bash "$URB_HOME/godmode/god.sh" --profile blue "$opt" "$@" ;;
        *)
            local py root
            py="$(svc_python)" || { msg_err 'python3 is required for URB BLUE'; return 127; }
            root="$(cfg BLUE_DIR '~/urb-blue')"
            URB_BLUE_ROOT="$root" "$py" -B "$URB_HOME/lib/blue_cli.py" "$@" ;;
    esac
}
