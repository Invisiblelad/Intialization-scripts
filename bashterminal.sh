#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  DevOps / K8s Bash Prompt  •  Source this from your ~/.bashrc or ~/.bash_profile
#  Features: Git • kubectl context/namespace • AWS profile • Python venv • Exit code
#
#  Install:
#    echo 'source ~/.devops_prompt.sh' >> ~/.bashrc        # Linux
#    echo 'source ~/.devops_prompt.sh' >> ~/.bash_profile  # macOS
# ─────────────────────────────────────────────────────────────────────────────

# ── Colour palette (256-colour safe) ──────────────────────────────────────────
R='\[\e[0m\]'
BOLD='\[\e[1m\]'

FG_WHITE='\[\e[97m\]'
FG_GRAY='\[\e[38;5;245m\]'
FG_DARK_GRAY='\[\e[38;5;240m\]'
FG_RED='\[\e[38;5;203m\]'
FG_GREEN='\[\e[38;5;114m\]'
FG_YELLOW='\[\e[38;5;221m\]'
FG_BLUE='\[\e[38;5;75m\]'
FG_CYAN='\[\e[38;5;80m\]'
FG_MAGENTA='\[\e[38;5;176m\]'
FG_ORANGE='\[\e[38;5;215m\]'
FG_TEAL='\[\e[38;5;43m\]'
FG_PURPLE='\[\e[38;5;141m\]'
FG_PINK='\[\e[38;5;211m\]'

# ── Symbols ────────────────────────────────────────────────────────────────────
SYM_GIT="⎇"
SYM_K8S="⎈"
SYM_AWS="☁"
SYM_VENV="🐍"
SYM_DIRTY="✗"
SYM_CLEAN="✓"
SYM_AHEAD="↑"
SYM_BEHIND="↓"
SYM_JOBS="⚙"
SYM_ROOT="#"
SYM_USER="❯"

# ── Helpers ────────────────────────────────────────────────────────────────────

# Shorten deep paths:  ~/projects/infra/k8s/production → ~/projects/…/production
__shorten_path() {
  local path="${PWD/#$HOME/\~}"
  local IFS='/'
  read -ra parts <<< "$path"
  local count=${#parts[@]}
  if (( count <= 4 )); then
    echo "$path"
  else
    echo "${parts[0]}/${parts[1]}/…/${parts[$((count-1))]}"
  fi
}

# Git segment: branch + dirty/clean + ahead/behind
__git_segment() {
  command -v git &>/dev/null || return
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || \
  branch=$(git rev-parse --short HEAD 2>/dev/null) || return

  local status_out
  status_out=$(git status --porcelain 2>/dev/null)

  local state_sym state_col
  if [[ -z "$status_out" ]]; then
    state_sym="$SYM_CLEAN"; state_col="$FG_GREEN"
  else
    state_sym="$SYM_DIRTY"; state_col="$FG_RED"
  fi

  local ab=""
  local ahead behind
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
  [[ "$ahead"  =~ ^[0-9]+$ && "$ahead"  -gt 0 ]] && ab+="${FG_YELLOW}${SYM_AHEAD}${ahead}"
  [[ "$behind" =~ ^[0-9]+$ && "$behind" -gt 0 ]] && ab+="${FG_MAGENTA}${SYM_BEHIND}${behind}"

  echo -e " ${FG_DARK_GRAY}[${FG_CYAN}${SYM_GIT} ${branch}${state_col} ${state_sym}${ab}${FG_DARK_GRAY}]${R}"
}

# kubectl context + namespace
__k8s_segment() {
  command -v kubectl &>/dev/null || return
  local ctx ns
  ctx=$(kubectl config current-context 2>/dev/null) || return
  ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
  [[ -z "$ns" ]] && ns="default"

  local ctx_col="$FG_TEAL"
  [[ "$ctx" =~ (prod|production|prd) ]] && ctx_col="$FG_RED"
  [[ "$ctx" =~ (stag|staging|uat|qa) ]] && ctx_col="$FG_YELLOW"

  echo -e " ${FG_DARK_GRAY}[${ctx_col}${SYM_K8S} ${ctx}${FG_DARK_GRAY}:${FG_PURPLE}${ns}${FG_DARK_GRAY}]${R}"
}

# AWS profile / region
__aws_segment() {
  local profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  [[ -z "$profile" && -z "$region" ]] && return

  local parts=""
  [[ -n "$profile" ]] && parts="${FG_ORANGE}${SYM_AWS} ${profile}"
  if [[ -n "$region" ]]; then
    [[ -n "$parts" ]] && parts+="${FG_DARK_GRAY}@${FG_YELLOW}${region}"
    [[ -z "$parts" ]] && parts="${FG_YELLOW}${SYM_AWS} ${region}"
  fi

  echo -e " ${FG_DARK_GRAY}[${parts}${FG_DARK_GRAY}]${R}"
}

# Python virtualenv
__venv_segment() {
  [[ -z "$VIRTUAL_ENV" ]] && return
  local venv_name
  venv_name=$(basename "$VIRTUAL_ENV")
  echo -e " ${FG_DARK_GRAY}[${FG_GREEN}${SYM_VENV} ${venv_name}${FG_DARK_GRAY}]${R}"
}

# Background jobs
__jobs_segment() {
  local job_count
  job_count=$(jobs -p 2>/dev/null | wc -l | tr -d ' ')
  (( job_count > 0 )) || return
  echo -e " ${FG_DARK_GRAY}[${FG_YELLOW}${SYM_JOBS} ${job_count}${FG_DARK_GRAY}]${R}"
}

# Exit-code indicator — only shown on non-zero
__exit_segment() {
  local code=$1
  (( code == 0 )) && return
  echo -e " ${FG_RED}[✘ ${code}]${R}"
}

# ── PROMPT_COMMAND ─────────────────────────────────────────────────────────────
__build_prompt() {
  local exit_code=$?   # must be first line

  local time_str
  time_str=$(date +%H:%M:%S)

  local user_col="$FG_GREEN"
  [[ "$EUID" -eq 0 ]] && user_col="$FG_RED"

  local host_col="$FG_BLUE"
  [[ "$HOSTNAME" =~ (prod|prd) ]]    && host_col="$FG_RED"
  [[ "$HOSTNAME" =~ (stag|qa|uat) ]] && host_col="$FG_YELLOW"

  local path_str
  path_str=$(__shorten_path)

  local line1
  line1="${FG_DARK_GRAY}${time_str}${R} ${user_col}${BOLD}\u${R}${FG_DARK_GRAY}@${host_col}${BOLD}\h${R} ${FG_WHITE}${BOLD}${path_str}${R}"

  local git_seg k8s_seg aws_seg venv_seg jobs_seg exit_seg
  git_seg=$(__git_segment)
  k8s_seg=$(__k8s_segment)
  aws_seg=$(__aws_segment)
  venv_seg=$(__venv_segment)
  jobs_seg=$(__jobs_segment)
  exit_seg=$(__exit_segment "$exit_code")

  local prompt_char prompt_col
  if [[ "$EUID" -eq 0 ]]; then
    prompt_char="$SYM_ROOT"; prompt_col="$FG_RED"
  else
    prompt_char="$SYM_USER"; prompt_col="$FG_CYAN"
  fi

  PS1="\n${line1}${git_seg}${k8s_seg}${aws_seg}${venv_seg}${jobs_seg}${exit_seg}\n${prompt_col}${BOLD}${prompt_char}${R} "
}

PROMPT_COMMAND='__build_prompt'

# ── kubectl aliases ────────────────────────────────────────────────────────────
alias k='kubectl'
alias kx='kubectl config use-context'
alias kn='kubectl config set-context --current --namespace'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias kl='kubectl logs --tail=100 -f'
alias kex='kubectl exec -it'
alias kgp='kubectl get pods -o wide'
alias kgs='kubectl get svc -o wide'
alias kgd='kubectl get deployments'
alias kgi='kubectl get ingress'
alias kgn='kubectl get nodes -o wide'
alias kctx='kubectl config get-contexts'
alias kns='kubectl get namespaces'
alias kwatch='watch -n2 kubectl get pods -o wide'

# ── Docker ─────────────────────────────────────────────────────────────────────
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlogs='docker logs --tail=100 -f'

# ── AWS ────────────────────────────────────────────────────────────────────────
if command -v aws &>/dev/null; then
  alias awswho='aws sts get-caller-identity'
  awsp() { export AWS_PROFILE="$1"; echo "AWS_PROFILE → $1"; }
fi

# ── Terraform ──────────────────────────────────────────────────────────────────
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'

# ── Helm ───────────────────────────────────────────────────────────────────────
alias h='helm'
alias hl='helm list -A'
alias hr='helm repo update'

# ── Navigation & safety ────────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ll='ls -lhA --color=auto'    # Linux  (macOS: alias ll='ls -lhAG')
alias ls='ls --color=auto'         # Linux  (macOS: alias ls='ls -G')
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ── Network ────────────────────────────────────────────────────────────────────
alias myip='curl -s https://api.ipify.org && echo'
alias ports='ss -tulnp'
alias listening='lsof -i -P -n | grep LISTEN'

# ── System ─────────────────────────────────────────────────────────────────────
alias free='free -h'
alias df='df -h'
alias duh='du -sh * 2>/dev/null | sort -h'
alias grep='grep --color=auto'

# ── History ────────────────────────────────────────────────────────────────────
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%F %T "
shopt -s histappend
shopt -s checkwinsize
shopt -s cdspell
export PROMPT_COMMAND="history -a; ${PROMPT_COMMAND}"

# ── Pager ──────────────────────────────────────────────────────────────────────
export LESS='-R --quit-if-one-screen --no-init'
export PAGER='less'

# Colourised man pages
man() {
  LESS_TERMCAP_mb=$'\e[1;31m' \
  LESS_TERMCAP_md=$'\e[1;36m' \
  LESS_TERMCAP_me=$'\e[0m'    \
  LESS_TERMCAP_se=$'\e[0m'    \
  LESS_TERMCAP_so=$'\e[1;44;33m' \
  LESS_TERMCAP_ue=$'\e[0m'    \
  LESS_TERMCAP_us=$'\e[1;32m' \
  command man "$@"
}

# ── PATH additions ─────────────────────────────────────────────────────────────
[[ -d /usr/local/bin ]]        && export PATH="/usr/local/bin:$PATH"
[[ -d /opt/homebrew/bin ]]     && export PATH="/opt/homebrew/bin:$PATH"
[[ -d "$HOME/.local/bin" ]]    && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/go/bin" ]]        && export PATH="$HOME/go/bin:$PATH"

# ── Shell completions ──────────────────────────────────────────────────────────
if [[ -f /etc/bash_completion ]] && ! shopt -oq posix; then
  source /etc/bash_completion
fi
if [[ -f /opt/homebrew/etc/profile.d/bash_completion.sh ]]; then
  source /opt/homebrew/etc/profile.d/bash_completion.sh
fi
if command -v kubectl &>/dev/null; then
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi
if command -v helm &>/dev/null; then
  source <(helm completion bash)
fi
if command -v terraform &>/dev/null; then
  complete -C "$(command -v terraform)" terraform tf
fi

echo -e "\e[38;5;75m🚀  DevOps prompt loaded\e[0m"




# # Option 1 — save and source permanently (recommended)
# curl -o ~/.devops_prompt.sh <your-downloaded-file>
# echo 'source ~/.devops_prompt.sh' >> ~/.bashrc     # Linux
# echo 'source ~/.devops_prompt.sh' >> ~/.bash_profile  # macOS

# # Option 2 — try it live right now without touching your config
# source ~/.devops_prompt.sh
