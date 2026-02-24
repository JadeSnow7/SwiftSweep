#!/bin/bash
set -euo pipefail

MODE="${1:-auto}"
STRICT="${SWIFTSWEEP_CI_DOCTOR_STRICT:-0}"

errors=0
warnings=0

log_info() {
  echo "SwiftSweep Doctor: $*"
}

log_warn() {
  warnings=$((warnings + 1))
  echo "SwiftSweep Doctor [WARN]: $*"
}

log_error() {
  errors=$((errors + 1))
  echo "SwiftSweep Doctor [ERROR]: $*"
}

is_set() {
  local name="$1"
  [[ -n "${!name:-}" ]]
}

check_notary_credentials() {
  local has_api=0
  local has_appleid=0

  if is_set NOTARY_KEY_ID && is_set NOTARY_ISSUER_ID && is_set NOTARY_PRIVATE_KEY_BASE64; then
    has_api=1
  fi

  if is_set APPLE_ID && is_set APPLE_TEAM_ID && is_set APPLE_APP_PASSWORD; then
    has_appleid=1
  fi

  if [[ "$has_api" == "0" && "$has_appleid" == "0" ]]; then
    log_error "SWIFTSWEEP_CI_NOTARIZE=1 但未配置可用公证凭据。"
    log_error "需要配置 API Key 三元组或 Apple ID 三元组。"
  fi
}

check_release_credentials() {
  if ! is_set GH_TOKEN && ! is_set GITHUB_TOKEN; then
    log_error "SWIFTSWEEP_CI_UPLOAD_RELEASE=1 但未配置 GH_TOKEN/GITHUB_TOKEN。"
  fi
}

log_info "mode=${MODE}, strict=${STRICT}"

if is_set MACOS_CERTIFICATE && ! is_set MACOS_CERTIFICATE_PWD; then
  log_error "设置了 MACOS_CERTIFICATE 但缺少 MACOS_CERTIFICATE_PWD。"
fi

if [[ "${SWIFTSWEEP_CI_EXPORT_DMG:-0}" == "1" ]]; then
  log_info "DMG export enabled."

  if [[ -z "${CI_ARCHIVE_PATH:-}" && "${SWIFTSWEEP_CI_SPM_BUILD:-0}" != "1" ]]; then
    log_warn "CI_ARCHIVE_PATH 为空且未启用 SWIFTSWEEP_CI_SPM_BUILD=1，Build/Test 动作可能失败。"
  fi

  if [[ "${SWIFTSWEEP_CI_NOTARIZE_APP:-0}" == "1" && "${SWIFTSWEEP_CI_NOTARIZE:-0}" != "1" ]]; then
    log_warn "SWIFTSWEEP_CI_NOTARIZE_APP=1 但 SWIFTSWEEP_CI_NOTARIZE!=1，APP 公证开关将被忽略。"
  fi

  if [[ "${SWIFTSWEEP_CI_NOTARIZE:-0}" == "1" ]]; then
    check_notary_credentials
  fi

  if [[ "${SWIFTSWEEP_CI_UPLOAD_RELEASE:-0}" == "1" ]]; then
    check_release_credentials
  fi
else
  log_info "DMG export disabled (SWIFTSWEEP_CI_EXPORT_DMG!=1)."
fi

if [[ "$errors" -gt 0 ]]; then
  log_info "summary: ${errors} error(s), ${warnings} warning(s)."
  if [[ "$STRICT" == "1" ]]; then
    exit 1
  fi
fi

if [[ "$warnings" -gt 0 && "$errors" -eq 0 ]]; then
  log_info "summary: 0 error(s), ${warnings} warning(s)."
fi

if [[ "$warnings" -eq 0 && "$errors" -eq 0 ]]; then
  log_info "summary: no issues detected."
fi
